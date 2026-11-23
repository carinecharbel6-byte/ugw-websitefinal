-- =====================================================================
-- UGW Travel and Events Management Database
-- Part 3 of 3: queries
-- Run after ugw_schema.sql and ugw_data.sql.
-- Queries that depend on the current date use a fixed reference date
-- (2026-11-20) in a small "Today" table so that the results shown in
-- the report can be reproduced. In the live system, replace
-- '2026-11-20' with date('now').
-- =====================================================================

PRAGMA foreign_keys = ON;

-- Q1. Pending quotations, oldest request first
-- Purpose: the agents' follow-up list of quotations still waiting for
-- the client's answer. Filtering (WHERE), join, sorting (ORDER BY).
SELECT q.quotationId, q.requestDate, q.requestType, c.clientName,
       e.firstName || ' ' || e.lastName AS preparedBy,
       q.issuedDate
FROM Quotation q
JOIN Client c   ON q.clientId = c.clientId
JOIN Employee e ON q.employeeId = e.employeeId
WHERE q.quoteStatus = 'Pending'
ORDER BY q.requestDate ASC;

-- Q2. Corporate clients and their assigned agent
-- Purpose: the account list of company clients with the employee who
-- handles each one. Filtering, join, sorting on two columns.
SELECT c.clientName, c.city, e.firstName || ' ' || e.lastName AS assignedEmployee,
       e.department, e.branch
FROM Client c
JOIN Employee e ON c.employeeId = e.employeeId
WHERE c.clientType = 'Company'
ORDER BY e.branch, c.clientName;

-- Q3. Booking overview: client, preparing employee and lead traveler
-- Purpose: one line per booking, following the links
-- Booking -> Quotation -> Client / Employee and Booking -> BookingTraveler -> Traveler.
SELECT b.bookingId, b.bookingDate, b.bookingStatus, c.clientName,
       e.firstName || ' ' || e.lastName AS preparedBy,
       t.firstName || ' ' || t.lastName AS leadTraveler
FROM Booking b
JOIN Quotation q       ON b.quotationId = q.quotationId
JOIN Client c          ON q.clientId = c.clientId
JOIN Employee e        ON q.employeeId = e.employeeId
JOIN BookingTraveler bt ON bt.bookingId = b.bookingId AND bt.isLeadTraveler = 1
JOIN Traveler t        ON bt.travelerId = t.travelerId
ORDER BY b.bookingId;

-- Q4. Derived attributes of each booking: travelerCount and totalAmount
-- Purpose: calculates two derived attributes that are not stored
-- (Table 4.1). totalAmount = sum of price (supplierCost + serviceFee)
-- of the booking's Active services. Aggregates, GROUP BY, subquery.
SELECT b.bookingId, b.bookingStatus,
       (SELECT COUNT(*) FROM BookingTraveler bt
        WHERE bt.bookingId = b.bookingId) AS travelerCount,
       ROUND(SUM(CASE WHEN s.serviceStatus = 'Active'
                      THEN s.supplierCost + s.serviceFee ELSE 0 END), 2) AS totalAmount
FROM Booking b
JOIN BookingService s ON s.bookingId = b.bookingId
GROUP BY b.bookingId, b.bookingStatus
ORDER BY totalAmount DESC;

-- Q5. Bookings with an open balance (derived balanceDue)
-- Purpose: balanceDue = totalAmount + total charges of its modifications
-- - payments on its invoices + refunds. The invoices of a booking are
-- its Original invoices and the Supplementary invoices of its
-- modifications (Section 6.16). HAVING keeps bookings whose balance is
-- not zero.
WITH BookingInvoice AS (
    SELECT invoiceNo, bookingId FROM Invoice WHERE invoiceType = 'Original'
    UNION ALL
    SELECT i.invoiceNo, m.bookingId
    FROM Invoice i JOIN Modification m ON i.modificationId = m.modificationId
),
Totals AS (
    SELECT bookingId,
           SUM(CASE WHEN serviceStatus = 'Active' THEN supplierCost + serviceFee ELSE 0 END) AS totalAmount
    FROM BookingService GROUP BY bookingId
),
Charges AS (
    SELECT bookingId,
           SUM(IFNULL(supplierPenaltyFee, 0) + IFNULL(agencyChangeFee, 0)) AS charges,
           SUM(IFNULL(refundToClient, 0)) AS refunds
    FROM Modification GROUP BY bookingId
),
Paid AS (
    SELECT bi.bookingId, SUM(p.amount) AS paid
    FROM BookingInvoice bi JOIN Payment p ON p.invoiceNo = bi.invoiceNo
    GROUP BY bi.bookingId
)
SELECT b.bookingId, c.clientName, b.bookingStatus,
       t.totalAmount,
       IFNULL(ch.charges, 0) AS charges,
       IFNULL(pd.paid, 0)    AS paid,
       IFNULL(ch.refunds, 0) AS refunds,
       ROUND(t.totalAmount + IFNULL(ch.charges, 0) - IFNULL(pd.paid, 0) + IFNULL(ch.refunds, 0), 2) AS balanceDue
FROM Booking b
JOIN Quotation q ON b.quotationId = q.quotationId
JOIN Client c    ON q.clientId = c.clientId
JOIN Totals t    ON t.bookingId = b.bookingId
LEFT JOIN Charges ch ON ch.bookingId = b.bookingId
LEFT JOIN Paid pd    ON pd.bookingId = b.bookingId
GROUP BY b.bookingId
HAVING balanceDue <> 0
ORDER BY balanceDue DESC;

-- Q6. Invoice status (derived invoiceStatus) as of the reference date
-- Purpose: Paid if the payments reach the amount; otherwise Overdue if
-- the due date has passed; otherwise Partially paid or Unpaid.
-- LEFT JOIN keeps invoices with no payment yet.
WITH Today AS (SELECT '2026-11-20' AS d)
SELECT i.invoiceNo, i.invoiceType, i.dueDate, i.amount,
       IFNULL(SUM(p.amount), 0) AS paid,
       CASE
           WHEN IFNULL(SUM(p.amount), 0) >= i.amount THEN 'Paid'
           WHEN i.dueDate < (SELECT d FROM Today)     THEN 'Overdue'
           WHEN COUNT(p.paymentId) > 0                THEN 'Partially paid'
           ELSE 'Unpaid'
       END AS invoiceStatus
FROM Invoice i
LEFT JOIN Payment p ON p.invoiceNo = i.invoiceNo
GROUP BY i.invoiceNo
ORDER BY i.invoiceNo;

-- Q7. Overdue invoices with the client to contact
-- Purpose: the accounting team's collection list: unpaid amount, days
-- overdue and the client's first phone number. Joins through
-- Booking or Modification, aggregate and HAVING.
WITH Today AS (SELECT '2026-11-20' AS d),
InvoiceBooking AS (
    SELECT i.invoiceNo, IFNULL(i.bookingId, m.bookingId) AS bookingId
    FROM Invoice i LEFT JOIN Modification m ON i.modificationId = m.modificationId
)
SELECT i.invoiceNo, c.clientName,
       (SELECT MIN(clientPhoneNo) FROM ClientPhone cp WHERE cp.clientId = c.clientId) AS phone,
       i.dueDate,
       CAST(julianday((SELECT d FROM Today)) - julianday(i.dueDate) AS INT) AS daysOverdue,
       i.amount - IFNULL(SUM(p.amount), 0) AS unpaid
FROM Invoice i
JOIN InvoiceBooking ib ON ib.invoiceNo = i.invoiceNo
JOIN Booking b   ON b.bookingId = ib.bookingId
JOIN Quotation q ON q.quotationId = b.quotationId
JOIN Client c    ON c.clientId = q.clientId
LEFT JOIN Payment p ON p.invoiceNo = i.invoiceNo
WHERE i.dueDate < (SELECT d FROM Today)
GROUP BY i.invoiceNo
HAVING unpaid > 0
ORDER BY daysOverdue DESC;

-- Q8. Credit control: outstandingBalance and availableCredit
-- Purpose: calculates the two derived attributes of CreditAccount
-- (Table 4.1). outstandingBalance = sum of balanceDue over the client's
-- bookings with a positive balance; availableCredit = creditLimit -
-- outstandingBalance.
WITH BookingInvoice AS (
    SELECT invoiceNo, bookingId FROM Invoice WHERE invoiceType = 'Original'
    UNION ALL
    SELECT i.invoiceNo, m.bookingId
    FROM Invoice i JOIN Modification m ON i.modificationId = m.modificationId
),
Balance AS (
    SELECT b.bookingId, q.clientId,
           (SELECT IFNULL(SUM(CASE WHEN serviceStatus = 'Active' THEN supplierCost + serviceFee END), 0)
              FROM BookingService s WHERE s.bookingId = b.bookingId)
         + (SELECT IFNULL(SUM(IFNULL(supplierPenaltyFee, 0) + IFNULL(agencyChangeFee, 0)), 0)
              FROM Modification m WHERE m.bookingId = b.bookingId)
         - (SELECT IFNULL(SUM(p.amount), 0)
              FROM BookingInvoice bi JOIN Payment p ON p.invoiceNo = bi.invoiceNo
              WHERE bi.bookingId = b.bookingId)
         + (SELECT IFNULL(SUM(refundToClient), 0)
              FROM Modification m WHERE m.bookingId = b.bookingId) AS balanceDue
    FROM Booking b JOIN Quotation q ON q.quotationId = b.quotationId
)
SELECT ca.creditAccountId, c.clientName, ca.status, ca.creditLimit, ca.paymentTerms,
       IFNULL(SUM(CASE WHEN bl.balanceDue > 0 THEN bl.balanceDue END), 0) AS outstandingBalance,
       ca.creditLimit - IFNULL(SUM(CASE WHEN bl.balanceDue > 0 THEN bl.balanceDue END), 0) AS availableCredit
FROM CreditAccount ca
JOIN Client c ON c.clientId = ca.clientId
LEFT JOIN Balance bl ON bl.clientId = ca.clientId
GROUP BY ca.creditAccountId
ORDER BY availableCredit;

-- Q9. Service fee income per department and employee
-- Purpose: UGW earns a service fee on every booked service. This sums
-- the fees of Active services by the employee who prepared the
-- quotation. Joins, SUM, COUNT, GROUP BY and ORDER BY.
SELECT e.department, e.firstName || ' ' || e.lastName AS employee,
       COUNT(DISTINCT b.bookingId) AS bookings,
       SUM(s.serviceFee) AS feeIncome
FROM Employee e
JOIN Quotation q      ON q.employeeId = e.employeeId
JOIN Booking b        ON b.quotationId = q.quotationId
JOIN BookingService s ON s.bookingId = b.bookingId
WHERE s.serviceStatus = 'Active'
GROUP BY e.employeeId
ORDER BY feeIncome DESC;

-- Q10. Commission earned from each supplier
-- Purpose: suppliers with a commission rate pay UGW a percentage of the
-- supplier cost. HAVING keeps suppliers that generated commission.
SELECT su.supplierName, su.supplierType, su.commissionRate,
       COUNT(*) AS services,
       SUM(s.supplierCost) AS totalCost,
       ROUND(SUM(s.supplierCost * su.commissionRate / 100), 2) AS commission
FROM Supplier su
JOIN BookingService s ON s.supplierId = su.supplierId
WHERE s.serviceStatus = 'Active'
GROUP BY su.supplierId
HAVING commission > 0
ORDER BY commission DESC;

-- Q11. Quotation conversion rate per employee
-- Purpose: how many of each employee's quotations became bookings.
-- COUNT, SUM with CASE, a calculated percentage and HAVING (employees
-- with at least two quotations).
SELECT e.firstName || ' ' || e.lastName AS employee, e.department,
       COUNT(*) AS quotations,
       SUM(CASE WHEN q.quoteStatus = 'Confirmed' THEN 1 ELSE 0 END) AS confirmed,
       ROUND(100.0 * SUM(CASE WHEN q.quoteStatus = 'Confirmed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS conversionPct
FROM Employee e
JOIN Quotation q ON q.employeeId = e.employeeId
GROUP BY e.employeeId
HAVING COUNT(*) >= 2
ORDER BY conversionPct DESC, quotations DESC;

-- Q12. Upcoming services in the next 45 days
-- Purpose: the operations calendar: Active services starting between the
-- reference date and 45 days later, with the supplier and the number of
-- travelers. Date filter, joins, sorting.
WITH Today AS (SELECT '2026-11-20' AS d)
SELECT s.startDate, s.bookingId, s.serviceNo, s.serviceType, su.supplierName,
       (SELECT COUNT(*) FROM BookingTraveler bt WHERE bt.bookingId = s.bookingId) AS travelers
FROM BookingService s
JOIN Supplier su ON su.supplierId = s.supplierId
WHERE s.serviceStatus = 'Active'
  AND s.startDate BETWEEN (SELECT d FROM Today) AND date((SELECT d FROM Today), '+45 days')
ORDER BY s.startDate, s.bookingId, s.serviceNo;

-- Q13. Travelers whose passport expires within six months of travel
-- Purpose: many countries require a passport valid for six months
-- after arrival. Lists travelers on upcoming bookings whose passport
-- expires less than six months after the first service starts.
WITH Today AS (SELECT '2026-11-20' AS d),
Trip AS (
    SELECT bookingId, MIN(startDate) AS departure
    FROM BookingService WHERE serviceStatus = 'Active' GROUP BY bookingId
)
SELECT t.travelerId, t.firstName || ' ' || t.lastName AS traveler, t.passportNo,
       t.passportExpiry, tr.bookingId, tr.departure
FROM Trip tr
JOIN BookingTraveler bt ON bt.bookingId = tr.bookingId
JOIN Traveler t         ON t.travelerId = bt.travelerId
WHERE tr.departure >= (SELECT d FROM Today)
  AND t.passportExpiry < date(tr.departure, '+6 months')
ORDER BY tr.departure;

-- Q14. Rule check: travelers not registered by any client
-- Purpose: R5 requires every traveler to be registered by at least one
-- client. This minimum cannot be declared in SQLite, so this query
-- verifies it. An empty result means the rule holds.
SELECT t.travelerId, t.firstName, t.lastName
FROM Traveler t
WHERE NOT EXISTS (SELECT 1 FROM ClientTraveler ct WHERE ct.travelerId = t.travelerId);

-- Q15. Travelers registered by more than one client
-- Purpose: shows the M:N Registers relationship in use: the same person
-- booked by different clients. GROUP BY and HAVING.
SELECT t.travelerId, t.firstName || ' ' || t.lastName AS traveler,
       COUNT(*) AS clients,
       GROUP_CONCAT(c.clientName, '; ') AS registeredBy
FROM Traveler t
JOIN ClientTraveler ct ON ct.travelerId = t.travelerId
JOIN Client c          ON c.clientId = ct.clientId
GROUP BY t.travelerId
HAVING COUNT(*) > 1;

-- Q16. Suppliers that provide more than one type of service
-- Purpose: supports the normalization assumption in Section 6.12 that
-- supplierId does not determine serviceType. GROUP BY and HAVING with
-- COUNT(DISTINCT).
SELECT su.supplierName, su.supplierType,
       COUNT(DISTINCT s.serviceType) AS serviceTypes,
       GROUP_CONCAT(DISTINCT s.serviceType) AS types
FROM Supplier su
JOIN BookingService s ON s.supplierId = su.supplierId
GROUP BY su.supplierId
HAVING COUNT(DISTINCT s.serviceType) > 1;

-- Q17. Departments with staff in more than one branch
-- Purpose: supports the normalization assumption in Section 6.4 that
-- department does not determine branch. GROUP BY and HAVING with
-- COUNT(DISTINCT).
SELECT department,
       COUNT(*) AS employees,
       COUNT(DISTINCT branch) AS branches,
       GROUP_CONCAT(DISTINCT branch) AS offices
FROM Employee
GROUP BY department
HAVING COUNT(DISTINCT branch) > 1;

-- Q18. Changes and cancellations summary
-- Purpose: how often bookings are changed or cancelled and the amounts
-- involved: charges billed to clients and refunds paid back.
SELECT modType,
       COUNT(*) AS modifications,
       SUM(IFNULL(supplierPenaltyFee, 0)) AS supplierPenalties,
       SUM(IFNULL(agencyChangeFee, 0))    AS agencyFees,
       SUM(IFNULL(refundToClient, 0))     AS refunds
FROM Modification
GROUP BY modType
ORDER BY modifications DESC;
