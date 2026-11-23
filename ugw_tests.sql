-- =====================================================================
-- UGW Travel and Events Management Database
-- Constraint tests: each statement below must FAIL.
-- Run after ugw_schema.sql and ugw_data.sql. Each failure shows that a
-- rule from the data dictionary is enforced by the database.
-- SQLite stops at the first error, so run the tests one at a time
-- (paste or select a single test, then run it).
-- =====================================================================
PRAGMA foreign_keys = ON;

-- T1. CHECK (allowed choices): 'Pending' is not a booking status
UPDATE Booking SET bookingStatus = 'Pending' WHERE bookingId = 1;

-- T2. CHECK (fixed length CHAR(3)): nationality must have exactly 3 capital letters
INSERT INTO Traveler (travelerId, passportNo, firstName, lastName, dateOfBirth, nationality, passportExpiry)
VALUES (21, 'LR9999999', 'Test', 'Traveler', '1990-01-01', 'LB', '2030-01-01');

-- T3. CHECK (numeric range): commissionRate must be between 0 and 100
INSERT INTO Supplier (supplierId, supplierName, supplierType, country, commissionRate)
VALUES (11, 'Test Supplier', 'Other', 'Lebanon', 120);

-- T4. FOREIGN KEY: employee 99 does not exist
INSERT INTO Client (clientId, clientName, clientType, employeeId)
VALUES (13, 'Test Client', 'Individual', 99);

-- T5. UNIQUE: two employees cannot share a work email
INSERT INTO Employee (employeeId, firstName, lastName, email, department, branch)
VALUES (12, 'Test', 'Employee', 'r.khoury@ugw-travel.example', 'Ticketing', 'Dubai');

-- T6. NOT NULL: a quotation must have a requesting client
INSERT INTO Quotation (quotationId, contactChannel, requestType, employeeId)
VALUES (18, 'Email', 'Flight', 2);

-- T7. Trigger: credit accounts are for Company clients only (client 4 is an Individual)
INSERT INTO CreditAccount (creditAccountId, creditLimit, approvalDate, clientId)
VALUES (6, 5000, '2026-11-20', 4);

-- T8. Trigger: a booking needs a Confirmed quotation (quotation 15 is Pending)
INSERT INTO Booking (bookingId, quotationId) VALUES (13, 15);

-- T9. Trigger: an invoice receives at most three payments (invoice 1005 already has three)
INSERT INTO Payment (paymentId, amount, method, paymentType, invoiceNo)
VALUES (18, 100, 'Cash', 'Installment', 1005);

-- T10. Partial unique index: booking 1 already has a lead traveler
UPDATE BookingTraveler SET isLeadTraveler = 1 WHERE bookingId = 1 AND travelerId = 2;

-- T11. CHECK (3NF rule): a Supplementary invoice must not record bookingId
INSERT INTO Invoice (invoiceNo, dueDate, invoiceType, amount, modificationId, bookingId)
VALUES (1015, '2026-12-20', 'Supplementary', 40, 2, 6);

-- T12. CHECK (across columns): a Confirmed quotation must have an issue date
INSERT INTO Quotation (quotationId, contactChannel, requestType, quoteStatus, clientId, employeeId)
VALUES (18, 'Email', 'Flight', 'Confirmed', 1, 2);

-- T13. Trigger on UPDATE: client 1 holds a credit account, so it must stay a Company
UPDATE Client SET clientType = 'Individual' WHERE clientId = 1;

-- T14. Trigger on UPDATE: quotation 1 resulted in booking 1, so it must stay Confirmed
UPDATE Quotation SET quoteStatus = 'Pending' WHERE quotationId = 1;

-- T15. Trigger on UPDATE: payment 1 cannot be moved to invoice 1005, which already has three payments
UPDATE Payment SET invoiceNo = 1005 WHERE paymentId = 1;
