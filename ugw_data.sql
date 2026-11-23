-- =====================================================================
-- UGW Travel and Events Management Database
-- Part 2 of 3: sample data
-- All names, numbers, emails and passports are fictional.
-- Run after ugw_schema.sql, in the same connection.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- Employee: the owner and 10 employees (1 Accounting, 4 Ticketing,
-- 4 Packages, 1 IT). Ticketing and Packages have staff in both offices.
-- ---------------------------------------------------------------------
INSERT INTO Employee (employeeId, firstName, lastName, email, department, branch)
VALUES
    (1,  'Karim',  'Haddad',    'k.haddad@ugw-travel.example',    'Owner',      'Beirut'),
    (2,  'Rania',  'Khoury',    'r.khoury@ugw-travel.example',    'Ticketing',  'Beirut'),
    (3,  'Fadi',   'Nassar',    'f.nassar@ugw-travel.example',    'Ticketing',  'Beirut'),
    (4,  'Omar',   'Hamdan',    'o.hamdan@ugw-travel.example',    'Ticketing',  'Dubai'),
    (5,  'Maya',   'Aoun',      'm.aoun@ugw-travel.example',      'Ticketing',  'Beirut'),
    (6,  'Nour',   'Fakhoury',  'n.fakhoury@ugw-travel.example',  'Packages',   'Beirut'),
    (7,  'Ziad',   'Mansour',   'z.mansour@ugw-travel.example',   'Packages',   'Beirut'),
    (8,  'Hala',   'Jaber',     'h.jaber@ugw-travel.example',     'Packages',   'Dubai'),
    (9,  'Tarek',  'Salameh',   't.salameh@ugw-travel.example',   'Packages',   'Dubai'),
    (10, 'Rita',   'Abi Nader', 'r.abinader@ugw-travel.example',  'Accounting', 'Beirut'),
    (11, 'Elie',   'Karam',     'e.karam@ugw-travel.example',     'IT',         'Beirut');

INSERT INTO EmployeePhone (employeeId, employeePhoneNo)
VALUES
    (1,  '+961 3 200 101'), (1,  '+961 1 900 100'),
    (2,  '+961 3 200 102'), (3,  '+961 3 200 103'),
    (4,  '+971 50 300 2104'), (5, '+961 3 200 105'),
    (6,  '+961 3 200 106'), (7,  '+961 3 200 107'),
    (8,  '+971 50 300 2108'), (9, '+971 50 300 2109'),
    (10, '+961 3 200 110'), (10, '+961 1 900 110'),
    (11, '+961 3 200 111');

-- ---------------------------------------------------------------------
-- Client: companies, individuals and families, each with one assigned
-- employee (Accounting and IT handle no clients).
-- ---------------------------------------------------------------------
INSERT INTO Client (clientId, clientName, clientType, email, street, city, country, employeeId)
VALUES
    (1,  'Cedar Pharma SAL',         'Company',    'travel@cedarpharma.example',   'Hamra Street 120',      'Beirut', 'Lebanon',              2),
    (2,  'Levant Engineering Group', 'Company',    'admin@levanteng.example',      'Charles Malek Ave 45',  'Beirut', 'Lebanon',              3),
    (3,  'Gulf Horizon Trading LLC', 'Company',    'hr@gulfhorizon.example',       'Sheikh Zayed Road 8',   'Dubai',  'United Arab Emirates', 4),
    (4,  'Nadine Rizk',              'Individual', 'nadine.rizk@mail.example',     'Mar Mikhael Street 14', 'Beirut', 'Lebanon',              6),
    (5,  'Mouawad Family',           'Family',     'a.mouawad@mail.example',       'Fouad Chehab Ave 22',   'Jounieh','Lebanon',              7),
    (6,  'Sami Daher',               'Individual', NULL,                           'Mina Road 3',           'Tripoli','Lebanon',              5),
    (7,  'Phoenicia Fintech SAL',    'Company',    'events@phoeniciafintech.example','Weygand Street 9',    'Beirut', 'Lebanon',              1),
    (8,  'Farah Itani',              'Individual', 'farah.itani@mail.example',     'Al Wasl Road 51',       'Dubai',  'United Arab Emirates', 8),
    (9,  'Khalil Family',            'Family',     'rami.khalil@mail.example',     'Jumeirah Street 77',    'Dubai',  'United Arab Emirates', 9),
    (10, 'Byblos Medical Center',    'Company',    'office@byblosmedical.example', 'Main Road 200',         'Byblos', 'Lebanon',              3),
    (11, 'Lara Chamoun',             'Individual', 'lara.chamoun@mail.example',    NULL,                    NULL,     NULL,                   2),
    (12, 'Atlas Logistics FZE',      'Company',    'ops@atlaslogistics.example',   'Jebel Ali Free Zone 5', 'Dubai',  'United Arab Emirates', 4);

INSERT INTO ClientPhone (clientId, clientPhoneNo)
VALUES
    (1,  '+961 1 350 120'), (1, '+961 3 410 120'),
    (2,  '+961 1 360 245'),
    (3,  '+971 4 330 0808'),
    (4,  '+961 3 422 014'),
    (5,  '+961 3 433 022'), (5, '+961 9 640 022'),
    (6,  '+961 3 444 003'),
    (7,  '+961 1 370 909'),
    (8,  '+971 55 410 5151'),
    (9,  '+971 55 420 7777'),
    (10, '+961 9 540 200'),
    (11, '+961 3 455 016'),
    (12, '+971 4 880 0505');

-- ---------------------------------------------------------------------
-- CreditAccount: Company clients only. Account 4 omits paymentTerms,
-- so it receives the default of 180 days. Account 5 is suspended.
-- ---------------------------------------------------------------------
INSERT INTO CreditAccount (creditAccountId, creditLimit, paymentTerms, approvalDate, expiryDate, status, clientId)
VALUES
    (1, 50000.00, 30, '2025-03-01', NULL,         'Active',    1),
    (2, 30000.00, 45, '2025-06-15', '2027-06-14', 'Active',    2),
    (3, 40000.00, 60, '2025-09-01', NULL,         'Active',    3),
    (5, 15000.00, 30, '2025-01-10', '2026-01-09', 'Suspended', 12);

INSERT INTO CreditAccount (creditAccountId, creditLimit, approvalDate, clientId)
VALUES
    (4, 100000.00, '2026-02-01', 7);

-- ---------------------------------------------------------------------
-- Traveler, TravelerPhone and ClientTraveler
-- Traveler 16 (Lara Chamoun) is registered by her employer (client 1)
-- and by herself (client 11). Children have no phone number.
-- ---------------------------------------------------------------------
INSERT INTO Traveler (travelerId, passportNo, firstName, lastName, dateOfBirth, nationality, passportExpiry, email)
VALUES
    (1,  'LR4821037',  'Georges', 'Saliba',      '1981-04-12', 'LBN', '2029-05-30', 'g.saliba@cedarpharma.example'),
    (2,  'LR5530218',  'Mira',    'Tannous',     '1990-09-03', 'LBN', '2028-11-14', 'm.tannous@cedarpharma.example'),
    (3,  'LR3392054',  'Hadi',    'Moussa',      '1985-01-27', 'LBN', '2030-02-18', 'h.moussa@levanteng.example'),
    (4,  'LR6107783',  'Joelle',  'Azar',        '1993-06-15', 'LBN', '2029-08-09', 'j.azar@levanteng.example'),
    (5,  'LR2276419',  'Bassel',  'Fares',       '1988-12-02', 'LBN', '2027-10-21', NULL),
    (6,  'A7731562',   'Ahmad',   'Al Mansoori', '1979-03-08', 'ARE', '2028-04-30', 'a.mansoori@gulfhorizon.example'),
    (7,  'A8843017',   'Sara',    'Al Qasimi',   '1991-11-19', 'ARE', '2029-01-12', 's.qasimi@gulfhorizon.example'),
    (8,  'LR7045126',  'Nadine',  'Rizk',        '1995-02-24', 'LBN', '2030-06-01', 'nadine.rizk@mail.example'),
    (9,  'LR1904388',  'Antoine', 'Mouawad',     '1976-07-30', 'LBN', '2028-09-17', 'a.mouawad@mail.example'),
    (10, '21FR38457',  'Carla',   'Mouawad',     '1980-10-05', 'FRA', '2031-03-22', NULL),
    (11, 'LR8810234',  'Yara',    'Mouawad',     '2015-05-11', 'LBN', '2027-05-10', NULL),
    (12, 'LR8810235',  'Marc',    'Mouawad',     '2018-08-23', 'LBN', '2028-08-22', NULL),
    (13, 'LR0937751',  'Sami',    'Daher',       '1987-03-14', 'LBN', '2027-03-01', NULL),
    (14, 'LR4458812',  'Walid',   'Harb',        '1983-08-09', 'LBN', '2029-12-31', 'w.harb@phoeniciafintech.example'),
    (15, 'LR6672901',  'Farah',   'Itani',       '1997-01-30', 'LBN', '2031-07-07', 'farah.itani@mail.example'),
    (16, 'LR5218846',  'Lara',    'Chamoun',     '1992-12-18', 'LBN', '2030-04-25', 'lara.chamoun@mail.example'),
    (17, 'J3384120',   'Rami',    'Khalil',      '1982-02-02', 'JOR', '2029-02-01', 'rami.khalil@mail.example'),
    (18, 'J3384121',   'Dina',    'Khalil',      '1986-05-21', 'JOR', '2029-02-01', NULL),
    (19, 'J3384122',   'Tia',     'Khalil',      '2017-09-09', 'JOR', '2027-09-08', NULL),
    (20, 'LR3015567',  'Elias',   'Sfeir',       '1974-11-28', 'LBN', '2028-03-15', 'e.sfeir@byblosmedical.example');

INSERT INTO TravelerPhone (travelerId, travelerPhoneNo)
VALUES
    (1, '+961 3 510 001'), (2, '+961 3 510 002'), (3, '+961 3 510 003'),
    (4, '+961 3 510 004'), (5, '+961 3 510 005'), (6, '+971 50 610 0006'),
    (7, '+971 50 610 0007'), (8, '+961 3 422 014'), (9, '+961 3 433 022'),
    (10, '+33 6 12 34 56 78'), (13, '+961 3 444 003'), (14, '+961 3 510 014'),
    (15, '+971 55 410 5151'), (16, '+961 3 455 016'), (16, '+961 1 350 160'),
    (17, '+971 55 420 7777'), (18, '+971 55 420 7778'), (20, '+961 3 510 020');

INSERT INTO ClientTraveler (clientId, travelerId)
VALUES
    (1, 1), (1, 2), (1, 16),
    (2, 3), (2, 4), (2, 5),
    (3, 6), (3, 7),
    (4, 8),
    (5, 9), (5, 10), (5, 11), (5, 12),
    (6, 13),
    (7, 14),
    (8, 15),
    (9, 17), (9, 18), (9, 19),
    (10, 20),
    (11, 16);

-- ---------------------------------------------------------------------
-- Supplier and SupplierPhone. Corniche Bay Hotel supplies both hotel
-- rooms and an event venue (one supplier, two service types).
-- ---------------------------------------------------------------------
INSERT INTO Supplier (supplierId, supplierName, supplierType, country, email, commissionRate)
VALUES
    (1,  'Cedar Wings Airlines',   'Airline',   'Lebanon',              'agents@cedarwings.example',     NULL),
    (2,  'Gulf Sky Airways',       'Airline',   'United Arab Emirates', 'trade@gulfsky.example',         NULL),
    (3,  'Corniche Bay Hotel',     'Hotel',     'Lebanon',              'sales@cornichebay.example',     10.00),
    (4,  'Marina Palm Hotel',      'Hotel',     'United Arab Emirates', 'groups@marinapalm.example',     12.00),
    (5,  'SafeTrip Insurance',     'Insurer',   'Lebanon',              NULL,                            15.00),
    (6,  'CityLink Transfers',     'Transfer',  'Lebanon',              'book@citylink.example',         NULL),
    (7,  'DesertDrive Car Rental', 'CarRental', 'United Arab Emirates', 'rentals@desertdrive.example',    8.00),
    (8,  'Bosphorus Holidays',     'Other',     'Turkey',               'b2b@bosphorusholidays.example', 10.00),
    (9,  'Summit Event Hall',      'Venue',     'Lebanon',              'events@summithall.example',      5.00),
    (10, 'Alpine Escapes',         'Other',     'Switzerland',          'partners@alpineescapes.example',10.00);

INSERT INTO SupplierPhone (supplierId, supplierPhoneNo)
VALUES
    (1, '+961 1 629 999'), (1, '+961 1 629 998'),
    (2, '+971 4 600 5000'),
    (3, '+961 1 371 000'),
    (4, '+971 4 399 8000'), (4, '+971 4 399 8001'),
    (5, '+961 1 480 480'),
    (6, '+961 3 777 666'),
    (7, '+971 4 255 2550'),
    (8, '+90 212 555 0101'),
    (9, '+961 4 520 520'),
    (10, '+41 27 555 0303');

-- ---------------------------------------------------------------------
-- Quotation and QuotationLine. Quotations 8 and 17 are prepared by a
-- Packages agent although the client's assigned employee is in Ticketing.
-- Quotation 17 omits quoteStatus, so it receives the default 'Pending'.
-- ---------------------------------------------------------------------
INSERT INTO Quotation (quotationId, requestDate, contactChannel, requestType, issuedDate, validUntil, quoteStatus, clientId, employeeId)
VALUES
    (1,  '2026-01-12', 'Email',     'Flight',  '2026-01-13', '2026-01-20', 'Confirmed', 1,  2),
    (2,  '2026-02-03', 'WhatsApp',  'Package', '2026-02-05', '2026-02-15', 'Confirmed', 4,  6),
    (3,  '2026-02-20', 'Phone',     'Flight',  '2026-02-21', '2026-02-28', 'Confirmed', 2,  3),
    (4,  '2026-03-10', 'Email',     'Event',   '2026-03-15', '2026-03-31', 'Confirmed', 7,  1),
    (5,  '2026-04-02', 'In person', 'Package', '2026-04-04', '2026-04-18', 'Confirmed', 5,  7),
    (6,  '2026-05-06', 'Email',     'Flight',  '2026-05-07', '2026-05-14', 'Rejected',  10, 3),
    (7,  '2026-05-20', 'WhatsApp',  'Flight',  '2026-05-21', '2026-05-28', 'Confirmed', 6,  5),
    (8,  '2026-06-11', 'Email',     'Package', '2026-06-13', '2026-06-27', 'Confirmed', 3,  8),
    (9,  '2026-07-01', 'Phone',     'Package', '2026-07-03', '2026-07-17', 'Expired',   8,  8),
    (10, '2026-08-18', 'WhatsApp',  'Package', '2026-08-20', '2026-09-03', 'Confirmed', 9,  9),
    (11, '2026-09-08', 'Email',     'Flight',  '2026-09-09', '2026-09-16', 'Confirmed', 1,  2),
    (12, '2026-10-05', 'Email',     'Flight',  '2026-10-06', '2026-10-13', 'Confirmed', 11, 2),
    (13, '2026-10-22', 'Email',     'Event',   '2026-10-25', '2026-11-10', 'Confirmed', 7,  1),
    (14, '2026-11-10', 'Phone',     'Flight',  '2026-11-11', '2026-11-18', 'Confirmed', 6,  5),
    (15, '2026-11-16', 'WhatsApp',  'Package', NULL,         NULL,         'Pending',   4,  6),
    (16, '2026-11-18', 'Email',     'Flight',  '2026-11-19', '2026-11-26', 'Pending',   12, 4);

INSERT INTO Quotation (quotationId, requestDate, contactChannel, requestType, clientId, employeeId)
VALUES
    (17, '2026-11-19', 'Email', 'Package', 2, 7);

INSERT INTO QuotationLine (quotationId, lineNo, serviceType, startDate, endDate, quotedPrice)
VALUES
    (1,  1, 'Flight',    '2026-02-02', '2026-02-06', 1400.00),
    (1,  2, 'Hotel',     '2026-02-02', '2026-02-06', 1180.00),
    (2,  1, 'Flight',    '2026-03-20', '2026-03-27',  490.00),
    (2,  2, 'Hotel',     '2026-03-20', '2026-03-27',  960.00),
    (2,  3, 'Transfer',  '2026-03-20', NULL,            50.00),
    (3,  1, 'Flight',    '2026-03-15', '2026-03-18', 2250.00),
    (3,  2, 'Insurance', '2026-03-15', '2026-03-18',  105.00),
    (4,  1, 'Event',     '2026-05-14', NULL,         20500.00),
    (4,  2, 'Hotel',     '2026-05-13', '2026-05-15', 4500.00),
    (4,  3, 'Transfer',  '2026-05-14', NULL,           700.00),
    (5,  1, 'Package',   '2026-07-01', '2026-07-08', 5600.00),
    (5,  2, 'Insurance', '2026-07-01', '2026-07-08',  180.00),
    (5,  3, 'Transfer',  '2026-07-01', NULL,            75.00),
    (6,  1, 'Flight',    '2026-06-01', '2026-06-04', 2600.00),
    (7,  1, 'Flight',    '2026-06-10', '2026-06-17',  410.00),
    (8,  1, 'Hotel',     '2026-07-10', '2026-07-14', 1720.00),
    (8,  2, 'Flight',    '2026-07-10', '2026-07-14', 1060.00),
    (9,  1, 'Package',   '2026-08-10', '2026-08-17', 3900.00),
    (10, 1, 'Package',   '2026-12-20', '2026-12-27', 10500.00),
    (10, 2, 'Flight',    '2026-12-20', '2026-12-27', 3400.00),
    (10, 3, 'Insurance', '2026-12-20', '2026-12-27',  270.00),
    (11, 1, 'Flight',    '2026-10-05', '2026-10-09', 1340.00),
    (11, 2, 'Hotel',     '2026-10-05', '2026-10-09', 1080.00),
    (11, 3, 'CarRental', '2026-10-05', '2026-10-09',  340.00),
    (12, 1, 'Flight',    '2026-12-05', '2026-12-12',  560.00),
    (13, 1, 'Event',     '2026-12-18', NULL,         14000.00),
    (13, 2, 'Transfer',  '2026-12-18', NULL,           900.00),
    (14, 1, 'Flight',    '2026-12-20', '2027-01-05',  685.00),
    (15, 1, 'Package',   '2027-02-14', '2027-02-18', 2400.00),
    (16, 1, 'Flight',    '2027-01-12', '2027-01-15', 3150.00),
    (17, 1, 'Package',   '2027-03-01', '2027-03-06', 6800.00);

-- ---------------------------------------------------------------------
-- Booking: one per Confirmed quotation (12 bookings)
-- ---------------------------------------------------------------------
INSERT INTO Booking (bookingId, bookingDate, bookingStatus, quotationId)
VALUES
    (1,  '2026-01-14', 'Completed', 1),
    (2,  '2026-02-06', 'Completed', 2),
    (3,  '2026-02-23', 'Completed', 3),
    (4,  '2026-03-20', 'Completed', 4),
    (5,  '2026-04-06', 'Completed', 5),
    (6,  '2026-05-22', 'Cancelled', 7),
    (7,  '2026-06-15', 'Completed', 8),
    (8,  '2026-08-21', 'Issued',    10),
    (9,  '2026-09-10', 'Completed', 11),
    (10, '2026-10-07', 'Issued',    12),
    (11, '2026-10-28', 'Reserved',  13),
    (12, '2026-11-12', 'Reserved',  14);

-- price of a service = supplierCost + serviceFee (derived, not stored)
INSERT INTO BookingService (bookingId, serviceNo, serviceType, startDate, endDate, supplierCost, serviceFee, serviceStatus, supplierId)
VALUES
    (1,  1, 'Flight',    '2026-02-02', '2026-02-06',  1300.00,  100.00, 'Active',    1),
    (1,  2, 'Hotel',     '2026-02-02', '2026-02-06',  1100.00,   80.00, 'Active',    4),
    (2,  1, 'Flight',    '2026-03-20', '2026-03-27',   450.00,   40.00, 'Active',    1),
    (2,  2, 'Hotel',     '2026-03-20', '2026-03-27',   900.00,   60.00, 'Active',    4),
    (2,  3, 'Transfer',  '2026-03-20', NULL,            40.00,   10.00, 'Active',    6),
    (3,  1, 'Flight',    '2026-03-15', '2026-03-18',  2100.00,  150.00, 'Active',    2),
    (3,  2, 'Insurance', '2026-03-15', '2026-03-18',    90.00,   15.00, 'Active',    5),
    (4,  1, 'Event',     '2026-05-14', NULL,          18000.00, 2500.00, 'Active',    3),
    (4,  2, 'Hotel',     '2026-05-13', '2026-05-15',  4200.00,  300.00, 'Active',    3),
    (4,  3, 'Transfer',  '2026-05-14', NULL,           600.00,  100.00, 'Active',    6),
    (5,  1, 'Package',   '2026-07-01', '2026-07-08',  5200.00,  400.00, 'Active',    8),
    (5,  2, 'Insurance', '2026-07-01', '2026-07-08',   160.00,   20.00, 'Active',    5),
    (5,  3, 'Transfer',  '2026-07-01', NULL,            60.00,   15.00, 'Cancelled', 6),
    (6,  1, 'Flight',    '2026-06-10', '2026-06-17',   380.00,   30.00, 'Cancelled', 1),
    (7,  1, 'Hotel',     '2026-07-10', '2026-07-14',  1600.00,  120.00, 'Active',    3),
    (7,  2, 'Flight',    '2026-07-10', '2026-07-14',   980.00,   80.00, 'Active',    2),
    (8,  1, 'Package',   '2026-12-20', '2026-12-27',  9800.00,  700.00, 'Active',   10),
    (8,  2, 'Flight',    '2026-12-20', '2026-12-27',  3200.00,  200.00, 'Active',    2),
    (8,  3, 'Insurance', '2026-12-20', '2026-12-27',   240.00,   30.00, 'Active',    5),
    (9,  1, 'Flight',    '2026-10-05', '2026-10-09',  1250.00,   90.00, 'Active',    1),
    (9,  2, 'Hotel',     '2026-10-05', '2026-10-09',  1000.00,   80.00, 'Active',    4),
    (9,  3, 'CarRental', '2026-10-05', '2026-10-09',   300.00,   40.00, 'Active',    7),
    (10, 1, 'Flight',    '2026-12-05', '2026-12-12',   520.00,   40.00, 'Active',    1),
    (11, 1, 'Event',     '2026-12-18', NULL,          12000.00, 2000.00, 'Active',    9),
    (11, 2, 'Transfer',  '2026-12-18', NULL,           800.00,  100.00, 'Active',    6),
    (12, 1, 'Flight',    '2026-12-20', '2027-01-05',   640.00,   45.00, 'Active',    2);

-- isLeadTraveler is omitted for non-lead travelers, so it defaults to 0
INSERT INTO BookingTraveler (bookingId, travelerId, isLeadTraveler)
VALUES
    (1, 1, 1), (2, 8, 1), (3, 3, 1), (4, 14, 1), (5, 9, 1), (6, 13, 1),
    (7, 6, 1), (8, 17, 1), (9, 16, 1), (10, 16, 1), (11, 14, 1), (12, 13, 1);

INSERT INTO BookingTraveler (bookingId, travelerId)
VALUES
    (1, 2), (3, 4), (3, 5), (5, 10), (5, 11), (5, 12),
    (7, 7), (8, 18), (8, 19), (9, 1);

-- ---------------------------------------------------------------------
-- Modification: changes and cancellations
-- ---------------------------------------------------------------------
INSERT INTO Modification (modificationId, modDate, modType, reason, refundToClient, refundDate, refundMethod, supplierPenaltyFee, agencyChangeFee, bookingId)
VALUES
    (1, '2026-03-01', 'Change',
        'Return flight (service 1) moved to a later departure on 27 March at the traveler''s request',
        NULL, NULL, NULL, 50.00, 25.00, 2),
    (2, '2026-05-30', 'Cancellation',
        'Whole booking cancelled by the client for personal reasons; flight (service 1) cancelled',
        290.00, '2026-06-02', 'Bank transfer', 100.00, 20.00, 6),
    (3, '2026-06-20', 'Cancellation',
        'Airport transfer (service 3) cancelled: the family will use its own car',
        75.00, '2026-06-25', 'Card', 0.00, 0.00, 5),
    (4, '2026-09-25', 'Change',
        'Outbound flight (service 1) changed to an earlier departure on 5 October',
        NULL, NULL, NULL, 60.00, 30.00, 9);

-- ---------------------------------------------------------------------
-- Invoice: one Original invoice per booking (bookingId filled) and one
-- Supplementary invoice per modification that increases the amount due
-- (modificationId filled). Amounts never change once issued.
-- ---------------------------------------------------------------------
INSERT INTO Invoice (invoiceNo, issueDate, dueDate, invoiceType, amount, modificationId, bookingId)
VALUES
    (1001, '2026-01-14', '2026-02-13', 'Original',       2580.00, NULL, 1),
    (1002, '2026-02-06', '2026-02-20', 'Original',       1500.00, NULL, 2),
    (1003, '2026-02-23', '2026-04-09', 'Original',       2355.00, NULL, 3),
    (1004, '2026-03-01', '2026-03-15', 'Supplementary',    75.00, 1,    NULL),
    (1005, '2026-03-20', '2026-09-16', 'Original',      25700.00, NULL, 4),
    (1006, '2026-04-06', '2026-04-20', 'Original',       5855.00, NULL, 5),
    (1007, '2026-05-22', '2026-06-05', 'Original',        410.00, NULL, 6),
    (1008, '2026-06-15', '2026-08-14', 'Original',       2780.00, NULL, 7),
    (1009, '2026-08-21', '2026-09-04', 'Original',      14170.00, NULL, 8),
    (1010, '2026-09-10', '2026-10-10', 'Original',       2760.00, NULL, 9),
    (1011, '2026-09-25', '2026-10-25', 'Supplementary',    90.00, 4,    NULL),
    (1012, '2026-10-07', '2026-10-21', 'Original',        560.00, NULL, 10),
    (1013, '2026-10-28', '2027-04-26', 'Original',      14900.00, NULL, 11),
    (1014, '2026-11-12', '2026-11-26', 'Original',        685.00, NULL, 12);

-- ---------------------------------------------------------------------
-- Payment: at most three payments per invoice
-- ---------------------------------------------------------------------
INSERT INTO Payment (paymentId, paymentDate, amount, method, paymentType, receiptReference, invoiceNo)
VALUES
    (1,  '2026-02-10',  2580.00, 'Bank transfer', 'Full',        'TRF-260210-01', 1001),
    (2,  '2026-02-06',   500.00, 'Card',          'Deposit',     'POS-558210',    1002),
    (3,  '2026-03-10',  1000.00, 'Bank transfer', 'Installment', 'TRF-260310-04', 1002),
    (4,  '2026-03-02',    75.00, 'Cash',          'Full',        NULL,            1004),
    (5,  '2026-04-01',  2355.00, 'Bank transfer', 'Full',        'TRF-260401-02', 1003),
    (6,  '2026-03-25', 10000.00, 'Bank transfer', 'Deposit',     'TRF-260325-07', 1005),
    (7,  '2026-05-20',  8000.00, 'Bank transfer', 'Installment', 'TRF-260520-03', 1005),
    (8,  '2026-08-30',  7700.00, 'Bank transfer', 'Installment', 'TRF-260830-01', 1005),
    (9,  '2026-04-06',  2000.00, 'Card',          'Deposit',     'POS-561447',    1006),
    (10, '2026-05-30',  3855.00, 'Bank transfer', 'Installment', 'TRF-260530-05', 1006),
    (11, '2026-05-22',   410.00, 'Card',          'Full',        'POS-563902',    1007),
    (12, '2026-08-01',  2780.00, 'Bank transfer', 'Full',        'TRF-260801-02', 1008),
    (13, '2026-08-21',  5000.00, 'Card',          'Deposit',     'POS-570118',    1009),
    (14, '2026-10-01',  5000.00, 'Bank transfer', 'Installment', 'TRF-261001-06', 1009),
    (15, '2026-10-08',  2760.00, 'Bank transfer', 'Full',        'TRF-261008-03', 1010),
    (16, '2026-10-07',   560.00, 'Card',          'Full',        'POS-574520',    1012),
    (17, '2026-11-02',  5000.00, 'Bank transfer', 'Deposit',     'TRF-261102-01', 1013);
