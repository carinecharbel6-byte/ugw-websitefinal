-- =====================================================================
-- UGW Travel and Events Management Database
-- Part 1 of 3: table creation (final normalized schema, Chapter 6)
-- Data types, lengths, choices, ranges and defaults follow the
-- updated data dictionary (Table 6.2).
-- =====================================================================

PRAGMA foreign_keys = ON;   -- must be run for each connection

-- Tables are created in an order in which every referenced table
-- already exists. Dropping them uses the reverse order.
DROP TABLE IF EXISTS Payment;
DROP TABLE IF EXISTS Invoice;
DROP TABLE IF EXISTS Modification;
DROP TABLE IF EXISTS BookingTraveler;
DROP TABLE IF EXISTS BookingService;
DROP TABLE IF EXISTS SupplierPhone;
DROP TABLE IF EXISTS Supplier;
DROP TABLE IF EXISTS Booking;
DROP TABLE IF EXISTS QuotationLine;
DROP TABLE IF EXISTS Quotation;
DROP TABLE IF EXISTS ClientTraveler;
DROP TABLE IF EXISTS TravelerPhone;
DROP TABLE IF EXISTS Traveler;
DROP TABLE IF EXISTS CreditAccount;
DROP TABLE IF EXISTS ClientPhone;
DROP TABLE IF EXISTS Client;
DROP TABLE IF EXISTS EmployeePhone;
DROP TABLE IF EXISTS Employee;

-- ---------------------------------------------------------------------
-- Employee
-- ---------------------------------------------------------------------
CREATE TABLE Employee (
    employeeId  INT          PRIMARY KEY,
    firstName   VARCHAR(30)  NOT NULL,
    lastName    VARCHAR(30)  NOT NULL,
    email       VARCHAR(100) NOT NULL UNIQUE,
    department  VARCHAR(10)  NOT NULL,
    branch      VARCHAR(6)   NOT NULL,
    CHECK (employeeId >= 1),
    CHECK (length(firstName) BETWEEN 1 AND 30),
    CHECK (length(lastName) BETWEEN 1 AND 30),
    CHECK (length(email) <= 100 AND email LIKE '%_@_%._%'),
    CHECK (department IN ('Owner', 'Ticketing', 'Packages', 'Accounting', 'IT')),
    CHECK (branch IN ('Beirut', 'Dubai'))
);

CREATE TABLE EmployeePhone (
    employeeId       INT         NOT NULL,
    employeePhoneNo  VARCHAR(20) NOT NULL,
    PRIMARY KEY (employeeId, employeePhoneNo),
    FOREIGN KEY (employeeId) REFERENCES Employee(employeeId),
    CHECK (length(employeePhoneNo) BETWEEN 8 AND 20
           AND employeePhoneNo GLOB '+[0-9]*'
           AND employeePhoneNo NOT GLOB '?*[^0-9 ]*')
);

-- ---------------------------------------------------------------------
-- Client (1:M Handles from Employee)
-- ---------------------------------------------------------------------
CREATE TABLE Client (
    clientId    INT          PRIMARY KEY,
    clientName  VARCHAR(50)  NOT NULL,
    clientType  VARCHAR(10)  NOT NULL,
    email       VARCHAR(100),
    street      VARCHAR(100),
    city        VARCHAR(40),
    country     VARCHAR(40),
    employeeId  INT          NOT NULL,
    FOREIGN KEY (employeeId) REFERENCES Employee(employeeId),
    CHECK (clientId >= 1),
    CHECK (length(clientName) BETWEEN 1 AND 50),
    CHECK (clientType IN ('Individual', 'Family', 'Company')),
    CHECK (email IS NULL OR (length(email) <= 100 AND email LIKE '%_@_%._%')),
    CHECK (street IS NULL OR length(street) <= 100),
    CHECK (city IS NULL OR length(city) <= 40),
    CHECK (country IS NULL OR length(country) <= 40)
);

CREATE TABLE ClientPhone (
    clientId       INT         NOT NULL,
    clientPhoneNo  VARCHAR(20) NOT NULL,
    PRIMARY KEY (clientId, clientPhoneNo),
    FOREIGN KEY (clientId) REFERENCES Client(clientId),
    CHECK (length(clientPhoneNo) BETWEEN 8 AND 20
           AND clientPhoneNo GLOB '+[0-9]*'
           AND clientPhoneNo NOT GLOB '?*[^0-9 ]*')
);

-- ---------------------------------------------------------------------
-- CreditAccount (1:1 Holds: clientId is UNIQUE and NOT NULL)
-- ---------------------------------------------------------------------
CREATE TABLE CreditAccount (
    creditAccountId  INT            PRIMARY KEY,
    creditLimit      DECIMAL(10,2)  NOT NULL,
    paymentTerms     INT            NOT NULL DEFAULT 180,
    approvalDate     DATE           NOT NULL,
    expiryDate       DATE,
    status           VARCHAR(9)     NOT NULL DEFAULT 'Active',
    clientId         INT            NOT NULL UNIQUE,
    FOREIGN KEY (clientId) REFERENCES Client(clientId),
    CHECK (creditAccountId >= 1),
    CHECK (creditLimit > 0 AND creditLimit <= 100000),
    CHECK (paymentTerms BETWEEN 1 AND 180),
    CHECK (date(approvalDate) = approvalDate),
    CHECK (expiryDate IS NULL OR (date(expiryDate) = expiryDate AND expiryDate > approvalDate)),
    CHECK (status IN ('Active', 'Suspended'))
);

-- ---------------------------------------------------------------------
-- Traveler, TravelerPhone and ClientTraveler (M:N Registers)
-- ---------------------------------------------------------------------
CREATE TABLE Traveler (
    travelerId      INT          PRIMARY KEY,
    passportNo      VARCHAR(12)  NOT NULL UNIQUE,
    firstName       VARCHAR(30)  NOT NULL,
    lastName        VARCHAR(30)  NOT NULL,
    dateOfBirth     DATE         NOT NULL,
    nationality     CHAR(3)      NOT NULL,
    passportExpiry  DATE         NOT NULL,
    email           VARCHAR(100),
    CHECK (travelerId >= 1),
    CHECK (length(passportNo) BETWEEN 6 AND 12 AND passportNo NOT GLOB '*[^A-Z0-9]*'),
    CHECK (length(firstName) BETWEEN 1 AND 30),
    CHECK (length(lastName) BETWEEN 1 AND 30),
    CHECK (date(dateOfBirth) = dateOfBirth),
    CHECK (length(nationality) = 3 AND nationality NOT GLOB '*[^A-Z]*'),
    CHECK (date(passportExpiry) = passportExpiry AND passportExpiry > dateOfBirth),
    CHECK (email IS NULL OR (length(email) <= 100 AND email LIKE '%_@_%._%'))
);

CREATE TABLE TravelerPhone (
    travelerId       INT         NOT NULL,
    travelerPhoneNo  VARCHAR(20) NOT NULL,
    PRIMARY KEY (travelerId, travelerPhoneNo),
    FOREIGN KEY (travelerId) REFERENCES Traveler(travelerId),
    CHECK (length(travelerPhoneNo) BETWEEN 8 AND 20
           AND travelerPhoneNo GLOB '+[0-9]*'
           AND travelerPhoneNo NOT GLOB '?*[^0-9 ]*')
);

CREATE TABLE ClientTraveler (
    clientId    INT NOT NULL,
    travelerId  INT NOT NULL,
    PRIMARY KEY (clientId, travelerId),
    FOREIGN KEY (clientId)   REFERENCES Client(clientId),
    FOREIGN KEY (travelerId) REFERENCES Traveler(travelerId)
);

-- ---------------------------------------------------------------------
-- Quotation (1:M Requests from Client, 1:M Prepares from Employee)
-- ---------------------------------------------------------------------
CREATE TABLE Quotation (
    quotationId     INT         PRIMARY KEY,
    requestDate     DATE        NOT NULL DEFAULT CURRENT_DATE,
    contactChannel  VARCHAR(9)  NOT NULL,
    requestType     VARCHAR(7)  NOT NULL,
    issuedDate      DATE,
    validUntil      DATE,
    quoteStatus     VARCHAR(9)  NOT NULL DEFAULT 'Pending',
    clientId        INT         NOT NULL,
    employeeId      INT         NOT NULL,
    FOREIGN KEY (clientId)   REFERENCES Client(clientId),
    FOREIGN KEY (employeeId) REFERENCES Employee(employeeId),
    CHECK (quotationId >= 1),
    CHECK (date(requestDate) = requestDate),
    CHECK (contactChannel IN ('Phone', 'WhatsApp', 'Email', 'In person')),
    CHECK (requestType IN ('Flight', 'Package', 'Event')),
    CHECK (issuedDate IS NULL OR (date(issuedDate) = issuedDate AND issuedDate >= requestDate)),
    CHECK (validUntil IS NULL OR (date(validUntil) = validUntil AND issuedDate IS NOT NULL AND validUntil >= issuedDate)),
    CHECK (quoteStatus IN ('Pending', 'Confirmed', 'Rejected', 'Expired')),
    CHECK (quoteStatus = 'Pending' OR issuedDate IS NOT NULL)
);

-- Weak entity: key = owner key + discriminator lineNo
CREATE TABLE QuotationLine (
    quotationId  INT            NOT NULL,
    lineNo       INT            NOT NULL,
    serviceType  VARCHAR(9)     NOT NULL,
    startDate    DATE           NOT NULL,
    endDate      DATE,
    quotedPrice  DECIMAL(10,2)  NOT NULL,
    PRIMARY KEY (quotationId, lineNo),
    FOREIGN KEY (quotationId) REFERENCES Quotation(quotationId),
    CHECK (lineNo >= 1),
    CHECK (serviceType IN ('Flight', 'Hotel', 'Package', 'Insurance', 'CarRental', 'Transfer', 'Event')),
    CHECK (date(startDate) = startDate),
    CHECK (endDate IS NULL OR (date(endDate) = endDate AND endDate >= startDate)),
    CHECK (quotedPrice >= 0)
);

-- ---------------------------------------------------------------------
-- Booking (1:1 ResultsIn: quotationId is UNIQUE and NOT NULL)
-- ---------------------------------------------------------------------
CREATE TABLE Booking (
    bookingId      INT         PRIMARY KEY,
    bookingDate    DATE        NOT NULL DEFAULT CURRENT_DATE,
    bookingStatus  VARCHAR(9)  NOT NULL DEFAULT 'Reserved',
    quotationId    INT         NOT NULL UNIQUE,
    FOREIGN KEY (quotationId) REFERENCES Quotation(quotationId),
    CHECK (bookingId >= 1),
    CHECK (date(bookingDate) = bookingDate),
    CHECK (bookingStatus IN ('Reserved', 'Issued', 'Completed', 'Cancelled'))
);

-- ---------------------------------------------------------------------
-- Supplier and SupplierPhone
-- ---------------------------------------------------------------------
CREATE TABLE Supplier (
    supplierId      INT            PRIMARY KEY,
    supplierName    VARCHAR(50)    NOT NULL,
    supplierType    VARCHAR(9)     NOT NULL,
    country         VARCHAR(40)    NOT NULL,
    email           VARCHAR(100),
    commissionRate  DECIMAL(5,2),
    CHECK (supplierId >= 1),
    CHECK (length(supplierName) BETWEEN 1 AND 50),
    CHECK (supplierType IN ('Airline', 'Hotel', 'Transfer', 'CarRental', 'Insurer', 'Venue', 'Other')),
    CHECK (length(country) BETWEEN 1 AND 40),
    CHECK (email IS NULL OR (length(email) <= 100 AND email LIKE '%_@_%._%')),
    CHECK (commissionRate IS NULL OR commissionRate BETWEEN 0 AND 100)
);

CREATE TABLE SupplierPhone (
    supplierId       INT         NOT NULL,
    supplierPhoneNo  VARCHAR(20) NOT NULL,
    PRIMARY KEY (supplierId, supplierPhoneNo),
    FOREIGN KEY (supplierId) REFERENCES Supplier(supplierId),
    CHECK (length(supplierPhoneNo) BETWEEN 8 AND 20
           AND supplierPhoneNo GLOB '+[0-9]*'
           AND supplierPhoneNo NOT GLOB '?*[^0-9 ]*')
);

-- ---------------------------------------------------------------------
-- BookingService (weak entity of Booking; 1:M Provides from Supplier)
-- ---------------------------------------------------------------------
CREATE TABLE BookingService (
    bookingId      INT            NOT NULL,
    serviceNo      INT            NOT NULL,
    serviceType    VARCHAR(9)     NOT NULL,
    startDate      DATE           NOT NULL,
    endDate        DATE,
    supplierCost   DECIMAL(10,2)  NOT NULL,
    serviceFee     DECIMAL(10,2)  NOT NULL,
    serviceStatus  VARCHAR(9)     NOT NULL DEFAULT 'Active',
    supplierId     INT            NOT NULL,
    PRIMARY KEY (bookingId, serviceNo),
    FOREIGN KEY (bookingId)  REFERENCES Booking(bookingId),
    FOREIGN KEY (supplierId) REFERENCES Supplier(supplierId),
    CHECK (serviceNo >= 1),
    CHECK (serviceType IN ('Flight', 'Hotel', 'Package', 'Insurance', 'CarRental', 'Transfer', 'Event')),
    CHECK (date(startDate) = startDate),
    CHECK (endDate IS NULL OR (date(endDate) = endDate AND endDate >= startDate)),
    CHECK (supplierCost >= 0),
    CHECK (serviceFee >= 0),
    CHECK (serviceStatus IN ('Active', 'Cancelled'))
);

-- M:N Includes, with relationship attribute isLeadTraveler
CREATE TABLE BookingTraveler (
    bookingId       INT NOT NULL,
    travelerId      INT NOT NULL,
    isLeadTraveler  INT NOT NULL DEFAULT 0,
    PRIMARY KEY (bookingId, travelerId),
    FOREIGN KEY (bookingId)  REFERENCES Booking(bookingId),
    FOREIGN KEY (travelerId) REFERENCES Traveler(travelerId),
    CHECK (isLeadTraveler IN (0, 1))
);

-- ---------------------------------------------------------------------
-- Modification (1:M Undergoes from Booking)
-- ---------------------------------------------------------------------
CREATE TABLE Modification (
    modificationId      INT            PRIMARY KEY,
    modDate             DATE           NOT NULL DEFAULT CURRENT_DATE,
    modType             VARCHAR(12)    NOT NULL,
    reason              VARCHAR(200)   NOT NULL,
    refundToClient      DECIMAL(10,2),
    refundDate          DATE,
    refundMethod        VARCHAR(13),
    supplierPenaltyFee  DECIMAL(10,2)  DEFAULT 0,
    agencyChangeFee     DECIMAL(10,2)  DEFAULT 0,
    bookingId           INT            NOT NULL,
    FOREIGN KEY (bookingId) REFERENCES Booking(bookingId),
    CHECK (modificationId >= 1),
    CHECK (date(modDate) = modDate),
    CHECK (modType IN ('Change', 'Cancellation')),
    CHECK (length(reason) BETWEEN 1 AND 200),
    CHECK (refundToClient IS NULL OR refundToClient > 0),
    CHECK (refundDate IS NULL OR (date(refundDate) = refundDate AND refundDate >= modDate)),
    CHECK (refundMethod IS NULL OR refundMethod IN ('Cash', 'Bank transfer', 'Card')),
    -- the refund amount, date and method are recorded together
    CHECK ((refundToClient IS NULL AND refundDate IS NULL AND refundMethod IS NULL)
        OR (refundToClient IS NOT NULL AND refundDate IS NOT NULL AND refundMethod IS NOT NULL)),
    CHECK (supplierPenaltyFee IS NULL OR supplierPenaltyFee >= 0),
    CHECK (agencyChangeFee IS NULL OR agencyChangeFee >= 0)
);

-- ---------------------------------------------------------------------
-- Invoice (1:M Generates from Booking for Original invoices;
--          1:1 Bills from Modification for Supplementary invoices)
-- ---------------------------------------------------------------------
CREATE TABLE Invoice (
    invoiceNo       INT            PRIMARY KEY,
    issueDate       DATE           NOT NULL DEFAULT CURRENT_DATE,
    dueDate         DATE           NOT NULL,
    invoiceType     VARCHAR(13)    NOT NULL DEFAULT 'Original',
    amount          DECIMAL(10,2)  NOT NULL,
    modificationId  INT            UNIQUE,
    bookingId       INT,
    FOREIGN KEY (modificationId) REFERENCES Modification(modificationId),
    FOREIGN KEY (bookingId)      REFERENCES Booking(bookingId),
    CHECK (invoiceNo >= 1),
    CHECK (date(issueDate) = issueDate),
    CHECK (date(dueDate) = dueDate AND dueDate >= issueDate),
    CHECK (invoiceType IN ('Original', 'Supplementary')),
    CHECK (amount > 0),
    -- 3NF rule (Section 6.16): exactly one of the two foreign keys is filled
    CHECK ((invoiceType = 'Original' AND bookingId IS NOT NULL AND modificationId IS NULL)
        OR (invoiceType = 'Supplementary' AND modificationId IS NOT NULL AND bookingId IS NULL))
);

-- ---------------------------------------------------------------------
-- Payment (1:M Receives from Invoice)
-- ---------------------------------------------------------------------
CREATE TABLE Payment (
    paymentId         INT            PRIMARY KEY,
    paymentDate       DATE           NOT NULL DEFAULT CURRENT_DATE,
    amount            DECIMAL(10,2)  NOT NULL,
    method            VARCHAR(13)    NOT NULL,
    paymentType       VARCHAR(11)    NOT NULL,
    receiptReference  VARCHAR(30),
    invoiceNo         INT            NOT NULL,
    FOREIGN KEY (invoiceNo) REFERENCES Invoice(invoiceNo),
    CHECK (paymentId >= 1),
    CHECK (date(paymentDate) = paymentDate),
    CHECK (amount > 0),
    CHECK (method IN ('Cash', 'Bank transfer', 'Card')),
    CHECK (paymentType IN ('Deposit', 'Installment', 'Full')),
    CHECK (receiptReference IS NULL OR length(receiptReference) BETWEEN 4 AND 30)
);

-- =====================================================================
-- Indexes marked Y (Y) in the data dictionary (duplicates allowed).
-- Y (N) indexes are created by the UNIQUE constraints above.
-- =====================================================================
CREATE INDEX ixClientName          ON Client(clientName);
CREATE INDEX ixClientCity          ON Client(city);
CREATE INDEX ixClientEmployee      ON Client(employeeId);
CREATE INDEX ixEmployeeLastName    ON Employee(lastName);
CREATE INDEX ixEmployeeDepartment  ON Employee(department);
CREATE INDEX ixTravelerLastName    ON Traveler(lastName);
CREATE INDEX ixQuotationStatus     ON Quotation(quoteStatus);
CREATE INDEX ixQuotationClient     ON Quotation(clientId);
CREATE INDEX ixQuotationEmployee   ON Quotation(employeeId);
CREATE INDEX ixBookingStatus       ON Booking(bookingStatus);
CREATE INDEX ixServiceSupplier     ON BookingService(supplierId);
CREATE INDEX ixSupplierName        ON Supplier(supplierName);
CREATE INDEX ixSupplierType        ON Supplier(supplierType);
CREATE INDEX ixInvoiceDueDate      ON Invoice(dueDate);
CREATE INDEX ixInvoiceBooking      ON Invoice(bookingId);
CREATE INDEX ixPaymentInvoice      ON Payment(invoiceNo);
CREATE INDEX ixModificationBooking ON Modification(bookingId);

-- At most one lead traveler per booking (partial unique index)
CREATE UNIQUE INDEX uxOneLeadPerBooking
    ON BookingTraveler(bookingId) WHERE isLeadTraveler = 1;

-- =====================================================================
-- Triggers for rules that depend on other rows or on the current date,
-- which a CHECK constraint on a single row cannot express. Each rule is
-- checked when a row is inserted and when the related column is updated.
-- =====================================================================

-- A credit account may only belong to a Company client (R16)
CREATE TRIGGER trgCreditCompanyOnly
BEFORE INSERT ON CreditAccount
WHEN (SELECT clientType FROM Client WHERE clientId = NEW.clientId) <> 'Company'
BEGIN
    SELECT RAISE(ABORT, 'A credit account can only belong to a Company client');
END;

CREATE TRIGGER trgCreditCompanyOnlyUpd
BEFORE UPDATE OF clientId ON CreditAccount
WHEN (SELECT clientType FROM Client WHERE clientId = NEW.clientId) <> 'Company'
BEGIN
    SELECT RAISE(ABORT, 'A credit account can only belong to a Company client');
END;

CREATE TRIGGER trgCreditClientTypeUpd
BEFORE UPDATE OF clientType ON Client
WHEN NEW.clientType <> 'Company'
 AND EXISTS (SELECT 1 FROM CreditAccount WHERE clientId = NEW.clientId)
BEGIN
    SELECT RAISE(ABORT, 'A client with a credit account must remain a Company client');
END;

-- A booking can only be created from a Confirmed quotation (R9)
CREATE TRIGGER trgBookingConfirmedQuote
BEFORE INSERT ON Booking
WHEN (SELECT quoteStatus FROM Quotation WHERE quotationId = NEW.quotationId) <> 'Confirmed'
BEGIN
    SELECT RAISE(ABORT, 'A booking can only be created from a Confirmed quotation');
END;

CREATE TRIGGER trgBookingConfirmedQuoteUpd
BEFORE UPDATE OF quotationId ON Booking
WHEN (SELECT quoteStatus FROM Quotation WHERE quotationId = NEW.quotationId) <> 'Confirmed'
BEGIN
    SELECT RAISE(ABORT, 'A booking can only be created from a Confirmed quotation');
END;

CREATE TRIGGER trgBookedQuoteStaysConfirmed
BEFORE UPDATE OF quoteStatus ON Quotation
WHEN NEW.quoteStatus <> 'Confirmed'
 AND EXISTS (SELECT 1 FROM Booking WHERE quotationId = NEW.quotationId)
BEGIN
    SELECT RAISE(ABORT, 'A quotation that resulted in a booking must remain Confirmed');
END;

-- A booking includes at most 100 travelers (R13)
CREATE TRIGGER trgMax100Travelers
BEFORE INSERT ON BookingTraveler
WHEN (SELECT COUNT(*) FROM BookingTraveler WHERE bookingId = NEW.bookingId) >= 100
BEGIN
    SELECT RAISE(ABORT, 'A booking cannot include more than 100 travelers');
END;

CREATE TRIGGER trgMax100TravelersUpd
BEFORE UPDATE OF bookingId ON BookingTraveler
WHEN NEW.bookingId <> OLD.bookingId
 AND (SELECT COUNT(*) FROM BookingTraveler WHERE bookingId = NEW.bookingId) >= 100
BEGIN
    SELECT RAISE(ABORT, 'A booking cannot include more than 100 travelers');
END;

-- An invoice is settled by at most three payments (R15)
CREATE TRIGGER trgMax3Payments
BEFORE INSERT ON Payment
WHEN (SELECT COUNT(*) FROM Payment WHERE invoiceNo = NEW.invoiceNo) >= 3
BEGIN
    SELECT RAISE(ABORT, 'An invoice cannot receive more than three payments');
END;

CREATE TRIGGER trgMax3PaymentsUpd
BEFORE UPDATE OF invoiceNo ON Payment
WHEN NEW.invoiceNo <> OLD.invoiceNo
 AND (SELECT COUNT(*) FROM Payment WHERE invoiceNo = NEW.invoiceNo) >= 3
BEGIN
    SELECT RAISE(ABORT, 'An invoice cannot receive more than three payments');
END;

-- A date of birth cannot be in the future (date('now') is not allowed in CHECK)
CREATE TRIGGER trgTravelerBirthDate
BEFORE INSERT ON Traveler
WHEN NEW.dateOfBirth > date('now')
BEGIN
    SELECT RAISE(ABORT, 'dateOfBirth cannot be later than the current date');
END;

CREATE TRIGGER trgTravelerBirthDateUpd
BEFORE UPDATE OF dateOfBirth ON Traveler
WHEN NEW.dateOfBirth > date('now')
BEGIN
    SELECT RAISE(ABORT, 'dateOfBirth cannot be later than the current date');
END;
