# UGW Travel and Events Management System – Website

INDE 513 Information Systems · Project Phase II · American University of Beirut

A Flask website connected to the project's SQLite database. The database is built
from the same SQL files that are submitted with the report, so the website shows
exactly the tables, records, rules and query results described in Chapter 7.

## Run it on your computer

Requirements: Python 3.10 or later.

```bash
cd ugw_website
python -m pip install -r requirements.txt
python app.py
```

Then open **http://127.0.0.1:5000** in a browser.

On the first run, the app creates `instance/ugw.db` from
`database/ugw_schema.sql` and `database/ugw_data.sql`. The button
**Reset demo data** (bottom of the sidebar) rebuilds it at any time, which removes
any records added through the website.

## Put it online with Render (free)

1. Create a GitHub repository and upload the contents of the `ugw_website` folder.
2. Sign in to https://render.com with GitHub and choose **New → Web Service**.
3. Select the repository. Render reads `render.yaml`; otherwise set
   - Build command: `pip install -r requirements.txt`
   - Start command: `gunicorn app:app`
4. Click **Create Web Service** and wait for the build. Render gives a link such as
   `https://ugw-travel-events.onrender.com`.

On the free plan the site sleeps when it is not used, so the first visit can take
about a minute. Its disk is temporary, so the database is rebuilt from the SQL
files whenever the service restarts.

## Folder contents

| Path | Content |
|---|---|
| `app.py` | Flask application: routes, SQL queries and form handling |
| `database/ugw_schema.sql` | CREATE TABLE statements, indexes and triggers (Section 7.1) |
| `database/ugw_data.sql` | Sample data (Section 7.2) |
| `database/ugw_queries.sql` | The 18 queries (Section 7.3), shown on the SQL Reports page |
| `database/ugw_tests.sql` | The constraint tests (Section 7.4), shown on the Database Rules page |
| `templates/` | HTML pages (Jinja templates) |
| `static/` | Stylesheet and the diagrams shown on the website |

## Signing in and roles

The first page asks you to choose a staff account. The accounts are the rows of the
`Employee` table, so no password is needed in this demo. Each department sees the
pages its work needs:

| Department | Can do |
|---|---|
| Owner | Everything, including approving credit accounts and resetting the demo data |
| Ticketing, Packages (agents) | Clients, travelers, quotations, bookings, changes, payments and refunds; "My clients" and "My follow-ups" show the clients they handle and the quotations they prepared |
| Accounting | Invoices, payments, refunds, credit accounts and the SQL reports |
| IT | The SQL reports, the database rules and the table explorer |

Sign in as **Karim Haddad (Owner)** to see every page. Use the menu under your name
(top right) to switch user or sign out.

## Guided workflow

Every client, quotation and booking page shows a **Next step** with a button, so a
trip moves naturally from client → traveler → quotation → issue → client's answer →
booking → deposit → tickets issued → full payment → completed. Each booking also shows
a journey bar and an **activity history** built from the dates stored in Quotation,
Booking, Invoice, Payment and Modification.

## Main features

| Page | What it does | Tables used |
|---|---|---|
| Dashboard | Fee income, open bookings, outstanding balances, overdue invoices, upcoming services, passport alerts, quotation follow-ups (past validity, waiting for the client, not sent yet) with one-click actions, charts | all |
| Clients | Search and filter clients; quick-view side panel; client page with contact details, credit account (derived outstanding balance and available credit), travelers, quotations, bookings and invoices; add, edit and delete a client (delete is blocked by the foreign keys when the client has quotations or a credit account); open a credit account | Client, ClientPhone, CreditAccount, ClientTraveler |
| Travelers | Search by name, passport or nationality; filter passports that expire within six months; register a traveler for a client | Traveler, TravelerPhone, ClientTraveler |
| Quotations | Create a quotation with its lines; issue it; confirm, reject or expire it; convert a confirmed quotation into a booking (booking, services, travelers and original invoice in one transaction) | Quotation, QuotationLine, Booking, BookingService, BookingTraveler, Invoice |
| Bookings | Filter by status; quick-view side panel with the itinerary; booking page with services, travelers, changes, invoices, payments and the derived balance due; change the status; record a change (new dates or a new price) or the cancellation of the services you tick; charges are billed on a Supplementary invoice that refers to the modification, or taken out of the refund; the form suggests the refund and shows the balance after the change | Booking, BookingService, Modification, Invoice |
| Invoices & Payments | Derived invoice status (Paid, Partially paid, Unpaid, Overdue); printable invoice (Print / Save as PDF); record a payment, with the remaining amount shown as you type | Invoice, Payment, Modification |
| Refunds | Refunds due (bookings whose derived balance is negative, because the client paid more than the booking now costs) with a form to record each refund, and the history of refunds already paid | Modification (refundToClient, refundDate, refundMethod) |
| Suppliers | Services provided and commission earned | Supplier, SupplierPhone, BookingService |
| SQL Reports | Runs the 18 queries of the report and shows the SQL and the results | all |
| Database Rules | Runs the 15 constraint tests inside a savepoint that is rolled back, and shows SQLite's error for each | all |
| Table Explorer | Columns, keys, foreign keys and all records of the 18 tables | all |

The website uses **today's date** for statuses such as Overdue and for follow-ups. The
SQL Reports page keeps the report's reference date (20 November 2026), so its results
match Chapter 7. To run the website on another date, set the environment variable
`UGW_TODAY`, for example `set UGW_TODAY=2026-11-20` (Windows) before `python app.py`.

## How the database rules appear on the website

The website does not repeat the rules in Python: every insert and update is sent to
SQLite with `PRAGMA foreign_keys = ON`, and if a CHECK, UNIQUE, NOT NULL, FOREIGN KEY
or trigger rejects it, the page shows the message returned by SQLite. Examples to try:

- Record a fourth payment on invoice 1005 → trigger `trgMax3Payments`.
- Open a credit account for an Individual client → trigger `trgCreditCompanyOnly`.
- Mark a quotation Confirmed before issuing it → CHECK on `quoteStatus` and `issuedDate`.
- Register a traveler with an existing passport number → UNIQUE on `passportNo`.

## AI assistance

The website code was written with the help of Claude (Anthropic). The team defined
the features from the project requirements, reviewed the generated code, and tested
every page and form against the database.
