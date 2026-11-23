"""
UGW Travel and Events Management System - website
INDE 513 Information Systems, Project Phase II

A Flask website connected to the project's SQLite database. The database is
built from the same SQL files that are submitted with the report
(database/ugw_schema.sql and database/ugw_data.sql), so every page shows the
records, rules and query results described in the report.
"""
import os
import re
import sqlite3
from datetime import date, timedelta
from functools import lru_cache

from flask import (send_from_directory, Flask, abort, flash, g, redirect, render_template, request,
                   session, url_for)

BASE = os.path.dirname(os.path.abspath(__file__))

def _folder(name):
    """Use the sub-folder if it exists; otherwise the files are next to app.py
    (this happens when the files are uploaded to GitHub without their folders)."""
    path = os.path.join(BASE, name)
    return path if os.path.isdir(path) else BASE


SQL_DIR = _folder("database")
TEMPLATE_DIR = _folder("templates")
STATIC_DIR = _folder("static")
DB_PATH = os.environ.get("UGW_DB", os.path.join(BASE, "instance", "ugw.db"))
# The website works with today's date, like a live system. Set UGW_TODAY (YYYY-MM-DD) to use
# another date; the SQL Reports page keeps the report's reference date (2026-11-20).
TODAY = os.environ.get("UGW_TODAY") or date.today().isoformat()
REPORT_DATE = "2026-11-20"

# Which departments may use each action (the Employee table provides the staff accounts).
AGENTS = {"Ticketing", "Packages"}
PERMS = {
    "client_new": AGENTS | {"Owner"}, "client_edit": AGENTS | {"Owner"}, "client_delete": {"Owner"},
    "traveler_new": AGENTS | {"Owner"},
    "quotation_new": AGENTS | {"Owner"}, "quotation_status": AGENTS | {"Owner"}, "quotation_book": AGENTS | {"Owner"},
    "booking_modify": AGENTS | {"Owner"}, "booking_status": AGENTS | {"Owner"},
    "credit_new": {"Owner", "Accounting"},
    "payment_new": AGENTS | {"Owner", "Accounting"},
    "refunds": AGENTS | {"Owner", "Accounting"}, "refund_record": AGENTS | {"Owner", "Accounting"},
    "reports": {"Owner", "IT", "Accounting"}, "rules": {"Owner", "IT"}, "explorer": {"Owner", "IT"},
    "reset": {"Owner", "IT"},
}


def can(endpoint):
    me = g.get("me")
    return bool(me) and (endpoint not in PERMS or me["department"] in PERMS[endpoint])

app = Flask(__name__, template_folder=TEMPLATE_DIR, static_folder=None)


@app.route("/static/<path:filename>", endpoint="static")
def static_files(filename):
    if not filename.lower().endswith((".css", ".js", ".png")):
        abort(404)
    if not os.path.exists(os.path.join(STATIC_DIR, filename)):
        filename = os.path.basename(filename)
    return send_from_directory(STATIC_DIR, filename)


app.secret_key = os.environ.get("SECRET_KEY", "ugw-inde513-demo")

# Allowed choices, taken from the CHECK constraints of the data dictionary
CHOICES = {
    "clientType": ["Individual", "Family", "Company"],
    "contactChannel": ["Phone", "WhatsApp", "Email", "In person"],
    "requestType": ["Flight", "Package", "Event"],
    "serviceType": ["Flight", "Hotel", "Package", "Insurance", "CarRental", "Transfer", "Event"],
    "quoteStatus": ["Pending", "Confirmed", "Rejected", "Expired"],
    "bookingStatus": ["Reserved", "Issued", "Completed", "Cancelled"],
    "method": ["Cash", "Bank transfer", "Card"],
    "paymentType": ["Deposit", "Installment", "Full"],
}


# ---------------------------------------------------------------- database
def build_database(path=DB_PATH):
    """Create the database from the submitted SQL files (schema + sample data)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    con = sqlite3.connect(tmp)
    con.execute("PRAGMA foreign_keys = ON")
    for name in ("ugw_schema.sql", "ugw_data.sql"):
        with open(os.path.join(SQL_DIR, name), encoding="utf-8") as f:
            con.executescript(f.read())
    con.commit()
    con.close()
    os.replace(tmp, path)


def db():
    if "db" not in g:
        if not os.path.exists(DB_PATH):
            build_database()
        # autocommit mode: transactions are opened explicitly with BEGIN
        g.db = sqlite3.connect(DB_PATH, isolation_level=None)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    con = g.pop("db", None)
    if con is not None:
        con.close()


def q(sql, args=(), one=False):
    rows = db().execute(sql, args).fetchall()
    return (rows[0] if rows else None) if one else rows


def next_id(table, column):
    return q(f"SELECT IFNULL(MAX({column}), 0) + 1 AS n FROM {table}", one=True)["n"]


class Tx:
    """Run several statements as one transaction; roll back if any fails."""
    def __enter__(self):
        db().execute("BEGIN")
        return db()

    def __exit__(self, exc_type, exc, tb):
        db().execute("ROLLBACK" if exc_type else "COMMIT")
        return False


class AppRule(Exception):
    """A minimum-cardinality rule that SQLite cannot declare, checked by the website."""


FRIENDLY = [
    ("quoteStatus = 'Pending' OR issuedDate", "A quotation must be issued to the client before it can be Confirmed, Rejected or Expired."),
    ("UNIQUE constraint failed: Traveler.passportNo", "This passport number is already registered."),
    ("UNIQUE constraint failed: Employee.email", "This email already belongs to another employee."),
    ("UNIQUE constraint failed: CreditAccount.clientId", "This client already holds a credit account."),
    ("UNIQUE constraint failed: Booking.quotationId", "This quotation has already resulted in a booking."),
    ("FOREIGN KEY constraint failed", "Foreign key rule: the record is linked to other records (or links to one that does not exist)."),
    ("NOT NULL constraint failed", "A required value is missing."),
    ("CHECK constraint failed", "A value is outside the allowed range or choices of the data dictionary."),
]


def db_error(e):
    """Show the rule that rejected the statement, as SQLite reported it."""
    msg = str(e)
    if isinstance(e, AppRule):
        flash(("rule", msg))
        return
    hint = next((h for k, h in FRIENDLY if k in msg), None)
    flash(("rule", f"{hint + ' ' if hint else ''}SQLite: {msg}"))


# ------------------------------------------------- derived attributes (SQL)
# Same definitions as queries Q5, Q6 and Q8 of the report.
BALANCE_CTE = """
WITH BookingInvoice AS (
    SELECT invoiceNo, bookingId FROM Invoice WHERE invoiceType = 'Original'
    UNION ALL
    SELECT i.invoiceNo, m.bookingId
    FROM Invoice i JOIN Modification m ON i.modificationId = m.modificationId
),
Bal AS (
    SELECT b.bookingId, b.bookingDate, b.bookingStatus, b.quotationId,
           q.clientId, q.employeeId,
           (SELECT COUNT(*) FROM BookingTraveler bt WHERE bt.bookingId = b.bookingId) AS travelerCount,
           (SELECT IFNULL(SUM(CASE WHEN serviceStatus = 'Active' THEN supplierCost + serviceFee END), 0)
              FROM BookingService s WHERE s.bookingId = b.bookingId) AS totalAmount,
           (SELECT IFNULL(SUM(IFNULL(supplierPenaltyFee, 0) + IFNULL(agencyChangeFee, 0)), 0)
              FROM Modification m WHERE m.bookingId = b.bookingId) AS charges,
           (SELECT IFNULL(SUM(p.amount), 0)
              FROM BookingInvoice bi JOIN Payment p ON p.invoiceNo = bi.invoiceNo
              WHERE bi.bookingId = b.bookingId) AS paid,
           (SELECT IFNULL(SUM(refundToClient), 0)
              FROM Modification m WHERE m.bookingId = b.bookingId) AS refunds,
           (SELECT MIN(startDate) FROM BookingService s
              WHERE s.bookingId = b.bookingId AND serviceStatus = 'Active') AS tripStart
    FROM Booking b JOIN Quotation q ON q.quotationId = b.quotationId
)
"""


def bookings(where="1=1", args=(), order="b.bookingId DESC"):
    return q(BALANCE_CTE + f"""
        SELECT b.*, ROUND(b.totalAmount + b.charges - b.paid + b.refunds, 2) AS balanceDue,
               c.clientName, c.clientType,
               e.firstName || ' ' || e.lastName AS agent
        FROM Bal b JOIN Client c ON c.clientId = b.clientId
        JOIN Employee e ON e.employeeId = b.employeeId
        WHERE {where} ORDER BY {order}""", args)


INVOICE_SQL = """
SELECT i.*, COALESCE(i.bookingId, m.bookingId) AS forBooking,
       c.clientName, c.clientId, c.email AS clientEmail,
       IFNULL((SELECT SUM(amount) FROM Payment p WHERE p.invoiceNo = i.invoiceNo), 0) AS paid,
       (SELECT COUNT(*) FROM Payment p WHERE p.invoiceNo = i.invoiceNo) AS nPayments,
       CASE
         WHEN IFNULL((SELECT SUM(amount) FROM Payment p WHERE p.invoiceNo = i.invoiceNo), 0) >= i.amount THEN 'Paid'
         WHEN i.dueDate < :today THEN 'Overdue'
         WHEN (SELECT COUNT(*) FROM Payment p WHERE p.invoiceNo = i.invoiceNo) > 0 THEN 'Partially paid'
         ELSE 'Unpaid'
       END AS invoiceStatus
FROM Invoice i
LEFT JOIN Modification m ON m.modificationId = i.modificationId
JOIN Booking b ON b.bookingId = COALESCE(i.bookingId, m.bookingId)
JOIN Quotation qu ON qu.quotationId = b.quotationId
JOIN Client c ON c.clientId = qu.clientId
"""


def invoices(where="1=1", args=None, order="i.invoiceNo"):
    args = dict(args or {}, today=TODAY)
    return q(INVOICE_SQL + f" WHERE {where} ORDER BY {order}", args)


def credit_accounts(where="1=1", args=()):
    return q(BALANCE_CTE + f"""
        SELECT ca.*, c.clientName,
               IFNULL(SUM(CASE WHEN ROUND(b.totalAmount + b.charges - b.paid + b.refunds, 2) > 0
                               THEN ROUND(b.totalAmount + b.charges - b.paid + b.refunds, 2) END), 0) AS outstandingBalance
        FROM CreditAccount ca JOIN Client c ON c.clientId = ca.clientId
        LEFT JOIN Bal b ON b.clientId = ca.clientId
        WHERE {where} GROUP BY ca.creditAccountId ORDER BY c.clientName""", args)


# --------------------------------------------------------- template helpers
@app.template_filter("money")
def money(v):
    try:
        return f"{float(v):,.2f}"
    except (TypeError, ValueError):
        return "–"


@app.template_filter("nice_date")
def nice_date(v):
    if not v:
        return "–"
    try:
        y, m, d = map(int, str(v).split("-"))
        return date(y, m, d).strftime("%d %b %Y")
    except ValueError:
        return v


ICON_TXT = {}
SERVICE_ICON = {"Flight": "✈️", "Hotel": "🏨", "Package": "🧳", "Insurance": "🛡️",
                "CarRental": "🚗", "Transfer": "🚐", "Event": "🎟️"}
AVATAR_COLORS = ["#7a1f2b", "#1d4ed8", "#047857", "#b45309", "#6d28d9", "#be185d", "#0e7490", "#4d7c0f"]


@app.template_filter("initials")
def initials(name):
    words = [w for w in str(name or "?").replace("-", " ").split() if w[:1].isalpha()]
    return ("".join(w[0] for w in words[:2]) or "?").upper()


@app.template_filter("avatar_color")
def avatar_color(name):
    return AVATAR_COLORS[sum(map(ord, str(name or ""))) % len(AVATAR_COLORS)]


def passport_alerts():
    return q("""
        SELECT bt.bookingId, t.travelerId, t.firstName || ' ' || t.lastName AS traveler,
               t.passportExpiry, MIN(s.startDate) AS tripStart
        FROM BookingTraveler bt JOIN Traveler t ON t.travelerId = bt.travelerId
        JOIN Booking b ON b.bookingId = bt.bookingId
        JOIN BookingService s ON s.bookingId = bt.bookingId AND s.serviceStatus = 'Active'
        WHERE b.bookingStatus IN ('Reserved', 'Issued')
        GROUP BY bt.bookingId, t.travelerId
        HAVING t.passportExpiry < date(MIN(s.startDate), '+6 months')""")


def followups(employee_id=None):
    """Pending quotations that need action: past validity, waiting for the client, or not sent yet."""
    rows = q("""SELECT qu.*, c.clientName, e.firstName || ' ' || e.lastName AS agent,
                       (SELECT SUM(quotedPrice) FROM QuotationLine l WHERE l.quotationId = qu.quotationId) AS quotedTotal,
                       CAST(julianday(qu.validUntil) - julianday(:t) AS INT) AS daysLeft,
                       CAST(julianday(:t) - julianday(qu.requestDate) AS INT) AS daysOpen
                FROM Quotation qu JOIN Client c ON c.clientId = qu.clientId JOIN Employee e ON e.employeeId = qu.employeeId
                WHERE qu.quoteStatus = 'Pending' AND (:e IS NULL OR qu.employeeId = :e)
                ORDER BY qu.validUntil IS NULL, qu.validUntil, qu.requestDate""", {"t": TODAY, "e": employee_id})
    out = []
    for r in rows:
        if r["issuedDate"] and r["validUntil"] < TODAY:
            kind, text = "expired", f"Validity ended {nice_date(r['validUntil'])}, client never replied"
        elif r["issuedDate"]:
            kind, text = "waiting", f"Sent {nice_date(r['issuedDate'])} · {r['daysLeft']} day(s) left to reply"
        elif r["daysOpen"] >= 3:
            kind, text = "unsent", f"Requested {r['daysOpen']} days ago and not sent to the client yet"
        else:
            continue
        out.append(dict(r, kind=kind, text=text))
    return out


def alerts():
    out = []
    me = g.get("me")
    for f in followups(me["employeeId"] if me and me["department"] in AGENTS else None):
        icon = {"expired": "⌛", "waiting": "📨", "unsent": "📝"}[f["kind"]]
        out.append((icon, f"Q-{f['quotationId']} ({f['clientName']}): {f['text']}.",
                    url_for("quotation_detail", qid=f["quotationId"])))
    for p in passport_alerts():
        out.append(("🛂", f"{p['traveler']}'s passport expires {nice_date(p['passportExpiry'])}, less than 6 months after the trip.",
                    url_for("booking_detail", bid=p["bookingId"])))
    for i in invoices():
        if i["invoiceStatus"] == "Overdue":
            out.append(("⏰", f"Invoice {i['invoiceNo']} ({i['clientName']}) is overdue: ${money(i['amount'] - i['paid'])} unpaid.",
                        url_for("invoices_page", status="Overdue")))
    for b in bookings(f"{BAL_SQL} < 0"):
        out.append(("↩️", f"Booking #{b['bookingId']} ({b['clientName']}): refund ${money(-b['balanceDue'])} due to the client.",
                    url_for("refunds", booking=b["bookingId"])))
    return out


@app.context_processor
def globals_():
    ctx = {"TODAY": TODAY, "REPORT_DATE": REPORT_DATE, "CHOICES": CHOICES, "endpoint": request.endpoint or "",
           "ICON": SERVICE_ICON, "can": can, "ME": g.get("me")}
    if g.get("me") and request.endpoint and not request.endpoint.startswith(("static", "peek")):
        ctx["ALERTS"] = alerts()
    return ctx


# ------------------------------------------------------------- staff sign-in
@app.before_request
def gate():
    ep = request.endpoint
    if ep in (None, "static", "login", "logout"):
        return None
    eid = session.get("eid")
    g.me = q("SELECT * FROM Employee WHERE employeeId = ?", (eid,), one=True) if eid else None
    if not g.me:
        return redirect(url_for("login", next=request.full_path if request.method == "GET" else "/"))
    if not can(ep):
        flash(("deny", f"Your role ({g.me['department']}) does not include this action. Sign in as the Owner or another department to use it."))
        return redirect(request.referrer or url_for("dashboard"))
    return None


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        emp = q("SELECT * FROM Employee WHERE employeeId = ?", (request.form.get("employeeId", type=int),), one=True)
        if emp:
            session["eid"] = emp["employeeId"]
            flash(("ok", f"Welcome, {emp['firstName']}! You are signed in as {emp['department']} ({emp['branch']})."))
            nxt = request.form.get("next", "")
            return redirect(nxt if nxt.startswith("/") and not nxt.startswith("/login") else url_for("dashboard"))
    staff = q("""SELECT e.*, (SELECT COUNT(*) FROM Client c WHERE c.employeeId = e.employeeId) AS nClients,
                        (SELECT COUNT(*) FROM Quotation qu WHERE qu.employeeId = e.employeeId) AS nQuotes
                 FROM Employee e ORDER BY CASE department WHEN 'Owner' THEN 0 WHEN 'Ticketing' THEN 1
                 WHEN 'Packages' THEN 2 WHEN 'Accounting' THEN 3 ELSE 4 END, firstName""")
    return render_template("login.html", staff=staff, next=request.args.get("next", ""))


@app.route("/logout")
def logout():
    session.pop("eid", None)
    return redirect(url_for("login"))


# ------------------------------------------------------- guided next steps
def client_next(c, travelers, quotes, bks, inv):
    cid = c["clientId"]
    if not travelers:
        return ("👤", "Register the travelers", "Add the people who will travel for this client.", url_for("traveler_new", client=cid), "Register traveler")
    if not quotes:
        return ("📝", "Prepare a first quotation", "The client has travelers registered; the next step is a price offer.", url_for("quotation_new", client=cid), "New quotation")
    for x in quotes:
        if x["quoteStatus"] == "Pending" and not x["issuedDate"]:
            return ("📨", f"Send quotation Q-{x['quotationId']}", "It has not been issued to the client yet.", url_for("quotation_detail", qid=x["quotationId"]), "Open quotation")
        if x["quoteStatus"] == "Confirmed" and not x["bookingId"]:
            return ("✈️", f"Book quotation Q-{x['quotationId']}", "The client confirmed it; turn it into a booking.", url_for("quotation_detail", qid=x["quotationId"]), "Create booking")
    for i in inv:
        if i["invoiceStatus"] != "Paid":
            return ("💳", f"Collect payment on invoice {i['invoiceNo']}", f"${money(i['amount'] - i['paid'])} is still due ({i['invoiceStatus'].lower()}).", url_for("payment_new", invoice=i["invoiceNo"]), "Record payment")
    for x in quotes:
        if x["quoteStatus"] == "Pending":
            return ("⏳", f"Waiting for the client on Q-{x['quotationId']}", f"Valid until {nice_date(x['validUntil'])}. Record the answer when the client calls back.", url_for("quotation_detail", qid=x["quotationId"]), "Open quotation")
    return ("✅", "Nothing pending", "All quotations are answered and all invoices are paid.", url_for("quotation_new", client=cid), "New quotation")


def quotation_next(qu):
    if qu["bookingId"]:
        return ("✅", f"Booked as #{qu['bookingId']}", "This quotation is complete.", url_for("booking_detail", bid=qu["bookingId"]), "Open booking")
    if qu["quoteStatus"] in ("Rejected", "Expired"):
        return ("🗂️", f"Quotation {qu['quoteStatus'].lower()}", "No further action. You can prepare a new offer for the client.", url_for("quotation_new", client=qu["clientId"]), "New quotation")
    if not qu["issuedDate"]:
        return ("📨", "Send it to the client", "Set the validity date and issue the quotation.", "#actions", "Go to actions")
    if qu["quoteStatus"] == "Pending":
        late = qu["validUntil"] < TODAY
        return ("⌛" if late else "⏳", "Validity has ended" if late else "Waiting for the client's answer",
                f"Valid until {nice_date(qu['validUntil'])}. When the client calls back, record Confirmed or Rejected." if not late
                else "The client did not answer in time. Call them, or mark the quotation Expired.", "#actions", "Record the answer")
    return ("✈️", "Create the booking", "The client confirmed. Choose the suppliers and travelers below.", "#book", "Go to booking form")


def booking_next(b, inv, last_day):
    bid = b["bookingId"]
    unpaid = [i for i in inv if i["invoiceStatus"] != "Paid"]
    if b["balanceDue"] < 0:
        return ("↩️", f"Refund ${money(-b['balanceDue'])} to the client",
                "The client paid more than the booking now costs. Pay the money back and record it as a refund.",
                url_for("refunds", booking=bid), "Record the refund", None)
    if b["bookingStatus"] == "Cancelled":
        if b["balanceDue"] > 0:
            return ("💳", "Collect the cancellation charges", f"${money(b['balanceDue'])} is still due.", url_for("payment_new", invoice=unpaid[0]["invoiceNo"]) if unpaid else None, "Record payment", None)
        return ("🗂️", "Booking cancelled", "Nothing else to do.", None, None, None)
    if b["paid"] == 0 and unpaid:
        return ("💳", "Collect a deposit", "No payment has been received yet. Take a deposit before issuing the tickets.", url_for("payment_new", invoice=unpaid[0]["invoiceNo"]), "Record payment", None)
    if b["bookingStatus"] == "Reserved":
        return ("🎫", "Issue the tickets and vouchers", "A payment was received; confirm the services with the suppliers and issue the documents.", None, "Mark as Issued", "Issued")
    if b["balanceDue"] > 0:
        return ("💳", "Collect the remaining balance", f"${money(b['balanceDue'])} is still due.", url_for("payment_new", invoice=unpaid[0]["invoiceNo"]) if unpaid else None, "Record payment", None)
    if b["bookingStatus"] == "Issued" and last_day and last_day < TODAY:
        return ("🏁", "The trip is over", f"The last service ended on {nice_date(last_day)}. Close the booking.", None, "Mark as Completed", "Completed")
    if b["bookingStatus"] == "Issued":
        return ("🧳", "Ready to travel", f"Everything is paid. The trip starts on {nice_date(b['tripStart'])}.", None, None, None)
    return ("✅", "Trip completed", "The booking is closed and settled.", None, None, None)


def booking_history(b):
    """Activity history built from the dates stored in the related tables."""
    qu = q("SELECT * FROM Quotation WHERE quotationId = ?", (b["quotationId"],), one=True)
    ev = [(qu["requestDate"], "📝", f"Quotation Q-{qu['quotationId']} requested by {qu['contactChannel'].lower()}")]
    if qu["issuedDate"]:
        ev.append((qu["issuedDate"], "📨", f"Quotation issued, valid until {nice_date(qu['validUntil'])}"))
    ev.append((b["bookingDate"], "✈️", f"Booking created by {b['agent']}"))
    for i in invoices("COALESCE(i.bookingId, m.bookingId) = :b", {"b": b["bookingId"]}):
        ev.append((i["issueDate"], "🧾", f"{i['invoiceType']} invoice {i['invoiceNo']} issued: ${money(i['amount'])}, due {nice_date(i['dueDate'])}"))
    for p in q("""SELECT p.* FROM Payment p JOIN Invoice i ON i.invoiceNo = p.invoiceNo LEFT JOIN Modification m ON m.modificationId = i.modificationId
                  WHERE COALESCE(i.bookingId, m.bookingId) = ?""", (b["bookingId"],)):
        ev.append((p["paymentDate"], "💳", f"{p['paymentType']} payment of ${money(p['amount'])} by {p['method'].lower()} (invoice {p['invoiceNo']})"))
    for m in q("SELECT * FROM Modification WHERE bookingId = ?", (b["bookingId"],)):
        ev.append((m["modDate"], "🔁" if m["modType"] == "Change" else "✖️", f"{m['modType']}: {m['reason']}"))
        if m["refundToClient"]:
            ev.append((m["refundDate"], "↩️", f"Refund of ${money(m['refundToClient'])} by {m['refundMethod'].lower()}"))
    return sorted(ev, key=lambda e: e[0], reverse=True)


# ------------------------------------------------------------------- pages
@app.route("/")
def dashboard():
    allb = bookings()
    open_b = [b for b in allb if b["bookingStatus"] in ("Reserved", "Issued")]
    inv = invoices()
    overdue = [i for i in inv if i["invoiceStatus"] == "Overdue"]
    kpi = {
        "clients": q("SELECT COUNT(*) n FROM Client", one=True)["n"],
        "travelers": q("SELECT COUNT(*) n FROM Traveler", one=True)["n"],
        "open_bookings": len(open_b),
        "fee_income": q("SELECT IFNULL(SUM(serviceFee),0) s FROM BookingService WHERE serviceStatus='Active'", one=True)["s"],
        "outstanding": sum(b["balanceDue"] for b in allb if b["balanceDue"] > 0),
        "overdue_n": len(overdue),
        "overdue_amt": sum(i["amount"] - i["paid"] for i in overdue),
        "pending_quotes": q("SELECT COUNT(*) n FROM Quotation WHERE quoteStatus='Pending'", one=True)["n"],
    }
    end = (date.fromisoformat(TODAY) + timedelta(days=45)).isoformat()
    upcoming = q("""
        SELECT s.bookingId, s.serviceType, s.startDate, s.endDate, sp.supplierName, c.clientName
        FROM BookingService s JOIN Supplier sp ON sp.supplierId = s.supplierId
        JOIN Booking b ON b.bookingId = s.bookingId JOIN Quotation qu ON qu.quotationId = b.quotationId
        JOIN Client c ON c.clientId = qu.clientId
        WHERE s.serviceStatus = 'Active' AND b.bookingStatus <> 'Cancelled'
          AND s.startDate BETWEEN ? AND ? ORDER BY s.startDate""", (TODAY, end))
    passport = passport_alerts()
    by_type = q("""SELECT serviceType, SUM(serviceFee) fee, COUNT(*) n FROM BookingService
                   WHERE serviceStatus='Active' GROUP BY serviceType ORDER BY fee DESC""")
    by_month = q("""SELECT substr(b.bookingDate,1,7) ym, SUM(s.serviceFee) fee FROM Booking b
                    JOIN BookingService s ON s.bookingId=b.bookingId AND s.serviceStatus='Active'
                    GROUP BY ym ORDER BY ym""")
    mine = g.me["employeeId"] if g.me["department"] in AGENTS else None
    kpi["my_clients"] = q("SELECT COUNT(*) n FROM Client WHERE employeeId = ?", (g.me["employeeId"],), one=True)["n"]
    return render_template("dashboard.html", kpi=kpi, upcoming=upcoming, passport=passport, followups=followups(mine), mine=mine,
                           overdue=overdue, by_type=by_type, by_month=by_month,
                           recent=allb[:5])


@app.route("/search")
def search():
    term = request.args.get("q", "").strip()
    like = f"%{term}%"
    res = {"clients": [], "travelers": [], "bookings": [], "suppliers": []}
    if term:
        res["clients"] = q("SELECT * FROM Client WHERE clientName LIKE ? OR email LIKE ? OR city LIKE ? ORDER BY clientName", (like,) * 3)
        res["travelers"] = q("""SELECT * FROM Traveler WHERE firstName || ' ' || lastName LIKE ? OR passportNo LIKE ?
                                OR email LIKE ? ORDER BY lastName""", (like,) * 3)
        res["suppliers"] = q("SELECT * FROM Supplier WHERE supplierName LIKE ? OR supplierType LIKE ?", (like,) * 2)
        num = term.lstrip("#")
        res["bookings"] = bookings("c.clientName LIKE ? OR CAST(b.bookingId AS TEXT) = ?", (like, num))
    return render_template("search.html", term=term, res=res)


# ---- clients
@app.route("/clients")
def clients():
    term = request.args.get("q", "").strip()
    ctype = request.args.get("type", "")
    mine = request.args.get("mine")
    where, args = ["1=1"], []
    if mine:
        where.append("c.employeeId = ?")
        args.append(g.me["employeeId"])
    if term:
        where.append("(c.clientName LIKE ? OR c.email LIKE ? OR c.city LIKE ?)")
        args += [f"%{term}%"] * 3
    if ctype:
        where.append("c.clientType = ?")
        args.append(ctype)
    rows = q(f"""
        SELECT c.*, e.firstName || ' ' || e.lastName AS agent,
               (SELECT GROUP_CONCAT(clientPhoneNo, ', ') FROM ClientPhone p WHERE p.clientId = c.clientId) AS phones,
               (SELECT COUNT(*) FROM Quotation qu JOIN Booking b ON b.quotationId = qu.quotationId
                 WHERE qu.clientId = c.clientId) AS nBookings,
               (SELECT COUNT(*) FROM ClientTraveler ct WHERE ct.clientId = c.clientId) AS nTravelers,
               (SELECT status FROM CreditAccount ca WHERE ca.clientId = c.clientId) AS credit
        FROM Client c JOIN Employee e ON e.employeeId = c.employeeId
        WHERE {' AND '.join(where)} ORDER BY c.clientName""", args)
    return render_template("clients.html", rows=rows, term=term, ctype=ctype, mine=mine,
                           n_mine=q("SELECT COUNT(*) n FROM Client WHERE employeeId = ?", (g.me["employeeId"],), one=True)["n"])


@app.route("/clients/<int:cid>")
def client_detail(cid):
    c = q("""SELECT c.*, e.firstName || ' ' || e.lastName AS agent, e.department, e.branch
             FROM Client c JOIN Employee e ON e.employeeId = c.employeeId WHERE c.clientId = ?""", (cid,), one=True)
    if not c:
        abort(404)
    phones = q("SELECT clientPhoneNo FROM ClientPhone WHERE clientId = ?", (cid,))
    credit = credit_accounts("ca.clientId = ?", (cid,))
    travelers = q("""SELECT t.* FROM Traveler t JOIN ClientTraveler ct ON ct.travelerId = t.travelerId
                     WHERE ct.clientId = ? ORDER BY t.lastName, t.firstName""", (cid,))
    quotes = q("""SELECT qu.*, (SELECT SUM(quotedPrice) FROM QuotationLine l WHERE l.quotationId = qu.quotationId) AS quotedTotal,
                         (SELECT bookingId FROM Booking b WHERE b.quotationId = qu.quotationId) AS bookingId
                  FROM Quotation qu WHERE qu.clientId = ? ORDER BY qu.requestDate DESC""", (cid,))
    bks = bookings("b.clientId = ?", (cid,))
    inv = invoices("c.clientId = :cid", {"cid": cid})
    return render_template("client_detail.html", c=c, phones=phones, credit=credit[0] if credit else None,
                           travelers=travelers, quotes=quotes, bookings=bks, invoices=inv,
                           nxt=client_next(c, travelers, quotes, bks, inv))


@app.route("/clients/new", methods=["GET", "POST"])
def client_new():
    employees = q("SELECT * FROM Employee WHERE department IN ('Owner','Ticketing','Packages') ORDER BY firstName")
    f = request.form
    if request.method == "POST":
        try:
            with Tx() as con:
                cid = next_id("Client", "clientId")
                con.execute("""INSERT INTO Client (clientId, clientName, clientType, email, street, city, country, employeeId)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                            (cid, f["clientName"].strip(), f["clientType"], f.get("email") or None,
                             f.get("street") or None, f.get("city") or None, f.get("country") or None,
                             int(f["employeeId"])))
                for ph in [p.strip() for p in f.get("phones", "").split(",") if p.strip()]:
                    con.execute("INSERT INTO ClientPhone (clientId, clientPhoneNo) VALUES (?, ?)", (cid, ph))
            flash(("ok", f"Client {cid} – {f['clientName']} was added."))
            return redirect(url_for("client_detail", cid=cid))
        except sqlite3.Error as e:
            db_error(e)
    return render_template("client_form.html", employees=employees, f=f)


@app.route("/clients/<int:cid>/edit", methods=["GET", "POST"])
def client_edit(cid):
    c = q("SELECT * FROM Client WHERE clientId = ?", (cid,), one=True)
    if not c:
        abort(404)
    employees = q("SELECT * FROM Employee WHERE department IN ('Owner','Ticketing','Packages') ORDER BY firstName")
    f = request.form
    if request.method == "POST":
        try:
            with Tx() as con:
                con.execute("""UPDATE Client SET clientName = ?, clientType = ?, email = ?, street = ?, city = ?,
                               country = ?, employeeId = ? WHERE clientId = ?""",
                            (f["clientName"].strip(), f["clientType"], f.get("email") or None, f.get("street") or None,
                             f.get("city") or None, f.get("country") or None, int(f["employeeId"]), cid))
                con.execute("DELETE FROM ClientPhone WHERE clientId = ?", (cid,))
                for ph in [p.strip() for p in f.get("phones", "").split(",") if p.strip()]:
                    con.execute("INSERT INTO ClientPhone (clientId, clientPhoneNo) VALUES (?, ?)", (cid, ph))
            flash(("ok", f"{f['clientName']} was updated."))
            return redirect(url_for("client_detail", cid=cid))
        except sqlite3.Error as e:
            db_error(e)
    else:
        f = dict(c)
        f["phones"] = ", ".join(r["clientPhoneNo"] for r in q("SELECT clientPhoneNo FROM ClientPhone WHERE clientId = ?", (cid,)))
    return render_template("client_form.html", employees=employees, f=f, editing=c)


@app.route("/clients/<int:cid>/delete", methods=["POST"])
def client_delete(cid):
    """Delete a client with its phone numbers and traveler links. The foreign keys of Quotation and
    CreditAccount block the delete when the client has quotations or a credit account."""
    try:
        with Tx() as con:
            con.execute("DELETE FROM ClientPhone WHERE clientId = ?", (cid,))
            con.execute("DELETE FROM ClientTraveler WHERE clientId = ?", (cid,))
            con.execute("DELETE FROM Client WHERE clientId = ?", (cid,))
        flash(("ok", "The client was deleted."))
        return redirect(url_for("clients"))
    except sqlite3.Error as e:
        db_error(e)
        return redirect(url_for("client_detail", cid=cid))


@app.route("/clients/<int:cid>/credit", methods=["POST"])
def credit_new(cid):
    f = request.form
    try:
        with Tx() as con:
            con.execute("""INSERT INTO CreditAccount (creditAccountId, creditLimit, paymentTerms, approvalDate, expiryDate, clientId)
                           VALUES (?, ?, ?, ?, ?, ?)""",
                        (next_id("CreditAccount", "creditAccountId"), float(f["creditLimit"]), int(f["paymentTerms"]),
                         TODAY, f.get("expiryDate") or None, cid))
        flash(("ok", "Credit account opened."))
    except (sqlite3.Error, ValueError) as e:
        db_error(e)
    return redirect(url_for("client_detail", cid=cid))


# ---- travelers
@app.route("/travelers")
def travelers():
    term = request.args.get("q", "").strip()
    risk = request.args.get("risk")
    where, args = ["1=1"], []
    if term:
        where.append("(t.firstName || ' ' || t.lastName LIKE ? OR t.passportNo LIKE ? OR t.nationality LIKE ?)")
        args += [f"%{term}%"] * 3
    if risk:
        where.append("t.passportExpiry < date(?, '+6 months')")
        args.append(TODAY)
    sql = f"""
        SELECT t.*, (SELECT GROUP_CONCAT(c.clientName, ', ') FROM ClientTraveler ct JOIN Client c ON c.clientId = ct.clientId
                      WHERE ct.travelerId = t.travelerId) AS clients,
               (SELECT COUNT(*) FROM BookingTraveler bt WHERE bt.travelerId = t.travelerId) AS nTrips,
               CAST((julianday(?) - julianday(t.dateOfBirth)) / 365.25 AS INT) AS age
        FROM Traveler t WHERE {' AND '.join(where)} ORDER BY t.lastName, t.firstName"""
    rows = q(sql, [TODAY] + args)
    soon = (date.fromisoformat(TODAY) + timedelta(days=183)).isoformat()
    return render_template("travelers.html", rows=rows, term=term, risk=risk, soon=soon)


@app.route("/travelers/new", methods=["GET", "POST"])
def traveler_new():
    allc = q("SELECT clientId, clientName FROM Client ORDER BY clientName")
    f = request.form
    if request.method == "POST":
        try:
            with Tx() as con:
                tid = next_id("Traveler", "travelerId")
                con.execute("""INSERT INTO Traveler (travelerId, passportNo, firstName, lastName, dateOfBirth,
                                                     nationality, passportExpiry, email)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                            (tid, f["passportNo"].strip().upper(), f["firstName"].strip(), f["lastName"].strip(),
                             f["dateOfBirth"], f["nationality"].strip().upper(), f["passportExpiry"],
                             f.get("email") or None))
                con.execute("INSERT INTO ClientTraveler (clientId, travelerId) VALUES (?, ?)", (int(f["clientId"]), tid))
                if f.get("phone", "").strip():
                    con.execute("INSERT INTO TravelerPhone (travelerId, travelerPhoneNo) VALUES (?, ?)", (tid, f["phone"].strip()))
            flash(("ok", f"Traveler {f['firstName']} {f['lastName']} was registered."))
            return redirect(url_for("client_detail", cid=int(f["clientId"])))
        except sqlite3.Error as e:
            db_error(e)
    return render_template("traveler_form.html", clients=allc, f=f,
                           preset=request.args.get("client", type=int))


# ---- quotations
@app.route("/quotations")
def quotations():
    status = request.args.get("status", "")
    rows = q(f"""
        SELECT qu.*, c.clientName, e.firstName || ' ' || e.lastName AS agent,
               (SELECT SUM(quotedPrice) FROM QuotationLine l WHERE l.quotationId = qu.quotationId) AS quotedTotal,
               (SELECT COUNT(*) FROM QuotationLine l WHERE l.quotationId = qu.quotationId) AS nLines,
               (SELECT bookingId FROM Booking b WHERE b.quotationId = qu.quotationId) AS bookingId
        FROM Quotation qu JOIN Client c ON c.clientId = qu.clientId JOIN Employee e ON e.employeeId = qu.employeeId
        WHERE {'qu.quoteStatus = ?' if status else '1=1'} ORDER BY qu.requestDate DESC""", (status,) if status else ())
    counts = {r["quoteStatus"]: r["n"] for r in q("SELECT quoteStatus, COUNT(*) n FROM Quotation GROUP BY quoteStatus")}
    fu = {f["quotationId"]: f for f in followups()}
    return render_template("quotations.html", rows=rows, status=status, sel=status, counts=counts, fu=fu)


@app.route("/quotations/<int:qid>")
def quotation_detail(qid):
    qu = q("""SELECT qu.*, c.clientName, c.clientType, e.firstName || ' ' || e.lastName AS agent,
                     (SELECT bookingId FROM Booking b WHERE b.quotationId = qu.quotationId) AS bookingId
              FROM Quotation qu JOIN Client c ON c.clientId = qu.clientId JOIN Employee e ON e.employeeId = qu.employeeId
              WHERE qu.quotationId = ?""", (qid,), one=True)
    if not qu:
        abort(404)
    lines = q("SELECT * FROM QuotationLine WHERE quotationId = ? ORDER BY lineNo", (qid,))
    suppliers = q("SELECT * FROM Supplier ORDER BY supplierName")
    travelers = q("""SELECT t.* FROM Traveler t JOIN ClientTraveler ct ON ct.travelerId = t.travelerId
                     WHERE ct.clientId = ? ORDER BY t.lastName""", (qu["clientId"],))
    return render_template("quotation_detail.html", qu=qu, lines=lines, suppliers=suppliers, nxt=quotation_next(qu),
                           travelers=travelers, total=sum(l["quotedPrice"] for l in lines),
                           valid_default=(date.fromisoformat(TODAY) + timedelta(days=10)).isoformat())


@app.route("/quotations/new", methods=["GET", "POST"])
def quotation_new():
    allc = q("SELECT clientId, clientName FROM Client ORDER BY clientName")
    employees = q("SELECT * FROM Employee WHERE department IN ('Owner','Ticketing','Packages') ORDER BY firstName")
    f = request.form
    if request.method == "POST":
        try:
            with Tx() as con:
                qid = next_id("Quotation", "quotationId")
                con.execute("""INSERT INTO Quotation (quotationId, requestDate, contactChannel, requestType, clientId, employeeId)
                               VALUES (?, ?, ?, ?, ?, ?)""",
                            (qid, TODAY, f["contactChannel"], f["requestType"], int(f["clientId"]), int(f["employeeId"])))
                n = 0
                for i in range(1, 8):
                    if not f.get(f"type{i}"):
                        continue
                    n += 1
                    con.execute("""INSERT INTO QuotationLine (quotationId, lineNo, serviceType, startDate, endDate, quotedPrice)
                                   VALUES (?, ?, ?, ?, ?, ?)""",
                                (qid, n, f[f"type{i}"], f[f"start{i}"], f.get(f"end{i}") or None, float(f[f"price{i}"] or 0)))
                if n == 0:
                    raise AppRule("A quotation must contain at least one line (minimum cardinality 1).")
            flash(("ok", f"Quotation {qid} was created with {n} line(s). Status: Pending."))
            return redirect(url_for("quotation_detail", qid=qid))
        except (sqlite3.Error, ValueError, AppRule) as e:
            db_error(e)
    return render_template("quotation_form.html", clients=allc, employees=employees, f=f, me_id=g.me["employeeId"],
                           preset=request.args.get("client", type=int))


@app.route("/quotations/<int:qid>/status", methods=["POST"])
def quotation_status(qid):
    action = request.form["action"]
    try:
        if action == "issue":
            db().execute("UPDATE Quotation SET issuedDate = ?, validUntil = ? WHERE quotationId = ?",
                         (TODAY, request.form["validUntil"], qid))
            flash(("ok", "Quotation issued to the client."))
        else:
            db().execute("UPDATE Quotation SET quoteStatus = ? WHERE quotationId = ?", (action, qid))
            flash(("ok", f"Quotation marked as {action}."))
    except sqlite3.Error as e:
        db_error(e)
    nxt = request.form.get("next", "")
    return redirect(nxt if nxt.startswith("/") else url_for("quotation_detail", qid=qid))


@app.route("/quotations/<int:qid>/book", methods=["POST"])
def quotation_book(qid):
    """Create the booking, its services, travelers and the original invoice in one transaction."""
    f = request.form
    lines = q("SELECT * FROM QuotationLine WHERE quotationId = ? ORDER BY lineNo", (qid,))
    qu = q("SELECT * FROM Quotation WHERE quotationId = ?", (qid,), one=True)
    try:
        trav = [int(t) for t in f.getlist("travelers")]
        if not trav:
            raise AppRule("A booking must include at least one traveler (minimum cardinality 1).")
        lead = int(f.get("lead") or trav[0])
        with Tx() as con:
            bid = next_id("Booking", "bookingId")
            con.execute("INSERT INTO Booking (bookingId, bookingDate, bookingStatus, quotationId) VALUES (?, ?, 'Reserved', ?)",
                        (bid, TODAY, qid))
            total = 0.0
            for n, l in enumerate(lines, 1):
                fee = float(f.get(f"fee{l['lineNo']}") or 0)
                cost = round(l["quotedPrice"] - fee, 2)
                total += cost + fee
                con.execute("""INSERT INTO BookingService (bookingId, serviceNo, serviceType, startDate, endDate,
                                                          supplierCost, serviceFee, supplierId)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                            (bid, n, l["serviceType"], l["startDate"], l["endDate"], cost, fee,
                             int(f[f"supplier{l['lineNo']}"])))
            for t in trav:
                con.execute("INSERT INTO BookingTraveler (bookingId, travelerId, isLeadTraveler) VALUES (?, ?, ?)",
                            (bid, t, 1 if t == lead else 0))
            terms = q("SELECT paymentTerms FROM CreditAccount WHERE clientId = ? AND status = 'Active'", (qu["clientId"],), one=True)
            due = (date.fromisoformat(TODAY) + timedelta(days=terms["paymentTerms"] if terms else 7)).isoformat()
            inv = next_id("Invoice", "invoiceNo")
            con.execute("""INSERT INTO Invoice (invoiceNo, issueDate, dueDate, invoiceType, amount, bookingId)
                           VALUES (?, ?, ?, 'Original', ?, ?)""", (inv, TODAY, due, round(total, 2), bid))
        flash(("ok", f"Booking {bid} was created with {len(lines)} service(s), {len(trav)} traveler(s) and invoice {inv}."))
        return redirect(url_for("booking_detail", bid=bid))
    except (sqlite3.Error, ValueError, KeyError, AppRule) as e:
        db_error(e)
        return redirect(url_for("quotation_detail", qid=qid))


# ---- bookings
@app.route("/bookings")
def bookings_page():
    status = request.args.get("status", "")
    term = request.args.get("q", "").strip()
    where, args = ["1=1"], []
    if status:
        where.append("b.bookingStatus = ?")
        args.append(status)
    if term:
        where.append("(c.clientName LIKE ? OR CAST(b.bookingId AS TEXT) = ?)")
        args += [f"%{term}%", term.lstrip('#')]
    rows = bookings(" AND ".join(where), args)
    counts = {r["bookingStatus"]: r["n"] for r in q("SELECT bookingStatus, COUNT(*) n FROM Booking GROUP BY bookingStatus")}
    return render_template("bookings.html", rows=rows, status=status, sel=status, term=term, counts=counts)


@app.route("/bookings/<int:bid>")
def booking_detail(bid):
    rows = bookings("b.bookingId = ?", (bid,))
    if not rows:
        abort(404)
    b = rows[0]
    services = q("""SELECT s.*, sp.supplierName, sp.supplierType, s.supplierCost + s.serviceFee AS price
                    FROM BookingService s JOIN Supplier sp ON sp.supplierId = s.supplierId
                    WHERE s.bookingId = ? ORDER BY s.serviceNo""", (bid,))
    trav = q("""SELECT t.*, bt.isLeadTraveler FROM BookingTraveler bt JOIN Traveler t ON t.travelerId = bt.travelerId
                WHERE bt.bookingId = ? ORDER BY bt.isLeadTraveler DESC, t.lastName""", (bid,))
    inv = invoices("COALESCE(i.bookingId, m.bookingId) = :b", {"b": bid})
    pays = q("""SELECT p.* FROM Payment p WHERE p.invoiceNo IN
                (SELECT invoiceNo FROM Invoice WHERE bookingId = ?
                 UNION SELECT i.invoiceNo FROM Invoice i JOIN Modification m ON m.modificationId = i.modificationId
                 WHERE m.bookingId = ?) ORDER BY p.paymentDate""", (bid, bid))
    mods = q("""SELECT m.*, IFNULL(supplierPenaltyFee,0) + IFNULL(agencyChangeFee,0) AS totalCharge
                FROM Modification m WHERE m.bookingId = ? ORDER BY m.modDate""", (bid,))
    last_day = max((s["endDate"] or s["startDate"] for s in services if s["serviceStatus"] == "Active"), default=None)
    journey = [("Booked", True), ("Deposit received", b["paid"] > 0),
               ("Tickets issued", b["bookingStatus"] in ("Issued", "Completed")),
               ("Fully paid", b["balanceDue"] <= 0 and b["paid"] > 0), ("Travelled", b["bookingStatus"] == "Completed")]
    return render_template("booking_detail.html", b=b, services=services, travelers=trav,
                           invoices=inv, payments=pays, mods=mods, nxt=booking_next(b, inv, last_day),
                           history=booking_history(b), journey=journey)


@app.route("/bookings/<int:bid>/modify", methods=["POST"])
def booking_modify(bid):
    """Record a change or a cancellation. Charges are billed on a Supplementary invoice that refers to the
    modification only (3NF design); a refund is recorded on the modification itself."""
    f = request.form
    try:
        mtype = f["modType"]
        penalty, agency = float(f.get("supplierPenaltyFee") or 0), float(f.get("agencyChangeFee") or 0)
        refund = float(f.get("refundToClient") or 0)
        services = [int(x) for x in f.getlist("services")]
        if mtype == "Cancellation" and not services and not refund:
            raise AppRule("Tick the service(s) the client cancels, or enter the refund to record.")
        with Tx() as con:
            mid = next_id("Modification", "modificationId")
            con.execute("""INSERT INTO Modification (modificationId, modDate, modType, reason, refundToClient, refundDate,
                                                     refundMethod, supplierPenaltyFee, agencyChangeFee, bookingId)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (mid, TODAY, mtype, f["reason"].strip(), refund or None, TODAY if refund else None,
                         f.get("refundMethod") if refund else None, penalty, agency, bid))
            if mtype == "Cancellation":
                for n in services:
                    con.execute("UPDATE BookingService SET serviceStatus = 'Cancelled' WHERE bookingId = ? AND serviceNo = ?", (bid, n))
                left = con.execute("SELECT COUNT(*) FROM BookingService WHERE bookingId = ? AND serviceStatus = 'Active'", (bid,)).fetchone()[0]
                if left == 0:
                    con.execute("UPDATE Booking SET bookingStatus = 'Cancelled' WHERE bookingId = ?", (bid,))
            increase = 0.0
            if mtype == "Change" and f.get("changeService"):
                sno = int(f["changeService"])
                if f.get("newStart"):
                    con.execute("UPDATE BookingService SET startDate = ?, endDate = COALESCE(?, endDate) WHERE bookingId = ? AND serviceNo = ?",
                                (f["newStart"], f.get("newEnd") or None, bid, sno))
                if f.get("newPrice"):
                    old = con.execute("SELECT supplierCost, serviceFee FROM BookingService WHERE bookingId = ? AND serviceNo = ?", (bid, sno)).fetchone()
                    new_price = float(f["newPrice"])
                    # UGW keeps its service fee; the supplier cost absorbs the new price
                    con.execute("UPDATE BookingService SET supplierCost = ? WHERE bookingId = ? AND serviceNo = ?",
                                (round(new_price - old[1], 2), bid, sno))
                    increase = round(new_price - (old[0] + old[1]), 2)
            msg = f"{mtype} recorded."
            # charges are billed on a Supplementary invoice, unless they are taken out of a refund (as for booking 6)
            deducted = bool(f.get("deduct")) and refund > 0 and penalty + agency > 0
            billed = round((0 if deducted else penalty + agency) + max(increase, 0), 2)
            if billed > 0:
                inv = next_id("Invoice", "invoiceNo")
                due = (date.fromisoformat(TODAY) + timedelta(days=7)).isoformat()
                con.execute("""INSERT INTO Invoice (invoiceNo, issueDate, dueDate, invoiceType, amount, modificationId)
                               VALUES (?, ?, ?, 'Supplementary', ?, ?)""", (inv, TODAY, due, billed, mid))
                msg += f" Supplementary invoice {inv} of ${billed:,.2f} was issued."
            if increase < 0:
                msg += f" The service is ${-increase:,.2f} cheaper."
            if deducted:
                msg += f" The ${penalty + agency:,.2f} charge was taken out of the refund."
            if refund:
                msg += f" Refund of ${refund:,.2f} recorded."
        flash(("ok", msg))
    except (sqlite3.Error, ValueError, KeyError, AppRule) as e:
        db_error(e)
    return redirect(url_for("booking_detail", bid=bid))


@app.route("/bookings/<int:bid>/status", methods=["POST"])
def booking_status(bid):
    try:
        db().execute("UPDATE Booking SET bookingStatus = ? WHERE bookingId = ?", (request.form["status"], bid))
        flash(("ok", f"Booking status changed to {request.form['status']}."))
    except sqlite3.Error as e:
        db_error(e)
    return redirect(url_for("booking_detail", bid=bid))


# ---- invoices and payments
@app.route("/invoices")
def invoices_page():
    status = request.args.get("status", "")
    rows = invoices()
    if status:
        rows = [r for r in rows if r["invoiceStatus"] == status]
    allrows = invoices()
    summary = {s: (sum(1 for r in allrows if r["invoiceStatus"] == s),
                   sum(r["amount"] - r["paid"] for r in allrows if r["invoiceStatus"] == s))
               for s in ("Paid", "Partially paid", "Unpaid", "Overdue")}
    return render_template("invoices.html", rows=rows, status=status, sel=status, summary=summary)


@app.route("/invoices/<int:no>")
def invoice_view(no):
    rows = invoices("i.invoiceNo = :n", {"n": no})
    if not rows:
        abort(404)
    i = rows[0]
    client = q("SELECT * FROM Client WHERE clientId = ?", (i["clientId"],), one=True)
    phones = q("SELECT clientPhoneNo FROM ClientPhone WHERE clientId = ?", (i["clientId"],))
    if i["invoiceType"] == "Original":
        lines = [dict(desc=f"{ICON_TXT.get(s['serviceType'], '')}{s['serviceType']} – {s['supplierName']}",
                      dates=nice_date(s["startDate"]) + (f" → {nice_date(s['endDate'])}" if s["endDate"] else ""), amount=s["price"])
                 for s in q("""SELECT s.*, sp.supplierName, s.supplierCost + s.serviceFee AS price FROM BookingService s
                               JOIN Supplier sp ON sp.supplierId = s.supplierId WHERE s.bookingId = ? AND s.serviceStatus = 'Active'
                               ORDER BY s.serviceNo""", (i["bookingId"],))]
        mod = None
    else:
        mod = q("SELECT * FROM Modification WHERE modificationId = ?", (i["modificationId"],), one=True)
        lines = [dict(desc=f"Supplier penalty – {mod['modType'].lower()}: {mod['reason']}", dates=nice_date(mod["modDate"]), amount=mod["supplierPenaltyFee"] or 0),
                 dict(desc="UGW change fee", dates=nice_date(mod["modDate"]), amount=mod["agencyChangeFee"] or 0)]
        extra = round(i["amount"] - (mod["supplierPenaltyFee"] or 0) - (mod["agencyChangeFee"] or 0), 2)
        if extra > 0:
            lines.append(dict(desc="Price difference after the change", dates=nice_date(mod["modDate"]), amount=extra))
        lines = [l for l in lines if l["amount"]]
    travelers = q("""SELECT t.firstName || ' ' || t.lastName AS name, bt.isLeadTraveler FROM BookingTraveler bt
                     JOIN Traveler t ON t.travelerId = bt.travelerId WHERE bt.bookingId = ? ORDER BY bt.isLeadTraveler DESC""", (i["forBooking"],))
    pays = q("SELECT * FROM Payment WHERE invoiceNo = ? ORDER BY paymentDate", (no,))
    return render_template("invoice_view.html", i=i, client=client, phones=phones, lines=lines, mod=mod,
                           travelers=travelers, payments=pays)


@app.route("/payments/new", methods=["GET", "POST"])
def payment_new():
    inv_no = request.values.get("invoice", type=int)
    open_inv = invoices("1=1", order="i.invoiceNo")
    f = request.form
    if request.method == "POST":
        try:
            with Tx() as con:
                pid = next_id("Payment", "paymentId")
                con.execute("""INSERT INTO Payment (paymentId, paymentDate, amount, method, paymentType, receiptReference, invoiceNo)
                               VALUES (?, ?, ?, ?, ?, ?, ?)""",
                            (pid, f["paymentDate"], float(f["amount"]), f["method"], f["paymentType"],
                             f.get("receiptReference") or None, int(f["invoiceNo"])))
            flash(("ok", f"Payment of ${float(f['amount']):,.2f} received from the client and recorded on invoice {f['invoiceNo']} (payment {pid})."))
            inv = invoices("i.invoiceNo = :n", {"n": int(f["invoiceNo"])})[0]
            return redirect(url_for("booking_detail", bid=inv["forBooking"]))
        except (sqlite3.Error, ValueError) as e:
            db_error(e)
            inv_no = int(f.get("invoiceNo") or 0) or inv_no
    return render_template("payment_form.html", invoices=open_inv, inv_no=inv_no, f=f)


# ---- suppliers
# ---- refunds: money UGW owes back to clients
BAL_SQL = "ROUND(b.totalAmount + b.charges - b.paid + b.refunds, 2)"


@app.route("/refunds")
def refunds():
    due = bookings(f"{BAL_SQL} < 0", order=f"{BAL_SQL}")
    paid = q("""SELECT m.*, c.clientName, c.clientId, b.bookingStatus
                FROM Modification m JOIN Booking b ON b.bookingId = m.bookingId
                JOIN Quotation qu ON qu.quotationId = b.quotationId JOIN Client c ON c.clientId = qu.clientId
                WHERE m.refundToClient IS NOT NULL ORDER BY m.refundDate DESC""")
    return render_template("refunds.html", due=due, paid=paid, focus=request.args.get("booking", type=int),
                           due_total=sum(-b["balanceDue"] for b in due), paid_total=sum(r["refundToClient"] for r in paid))


@app.route("/refunds/record", methods=["POST"])
def refund_record():
    """Pay back money the client overpaid. The schema stores refunds on a Modification row
    (refundToClient, refundDate, refundMethod); this one has no charges."""
    f = request.form
    try:
        bid = int(f["bookingId"])
        amount = round(float(f["amount"]), 2)
        owed = -bookings("b.bookingId = ?", (bid,))[0]["balanceDue"]
        if amount <= 0:
            raise AppRule("Enter the amount refunded to the client.")
        if amount > owed + 0.005:
            raise AppRule(f"The client is owed ${money(owed)}; a larger refund would leave the client owing UGW money.")
        has_cancel = q("SELECT COUNT(*) n FROM BookingService WHERE bookingId = ? AND serviceStatus = 'Cancelled'", (bid,), one=True)["n"]
        with Tx() as con:
            con.execute("""INSERT INTO Modification (modificationId, modDate, modType, reason, refundToClient, refundDate,
                                                     refundMethod, supplierPenaltyFee, agencyChangeFee, bookingId)
                           VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?)""",
                        (next_id("Modification", "modificationId"), TODAY, "Cancellation" if has_cancel else "Change",
                         (f.get("reason") or "Refund of the amount the client overpaid").strip(), amount, TODAY, f["refundMethod"], bid))
        flash(("ok", f"Refund of ${amount:,.2f} by {f['refundMethod'].lower()} recorded for booking #{bid}."))
    except (sqlite3.Error, ValueError, KeyError, IndexError, AppRule) as e:
        db_error(e)
    nxt = f.get("next", "")
    return redirect(nxt if nxt.startswith("/") else url_for("refunds"))


@app.route("/suppliers")
def suppliers():
    rows = q("""
        SELECT sp.*, (SELECT GROUP_CONCAT(supplierPhoneNo, ', ') FROM SupplierPhone p WHERE p.supplierId = sp.supplierId) AS phones,
               COUNT(s.serviceNo) AS nServices,
               IFNULL(SUM(s.supplierCost), 0) AS paidToSupplier,
               ROUND(IFNULL(SUM(s.supplierCost), 0) * IFNULL(sp.commissionRate, 0) / 100, 2) AS commission,
               GROUP_CONCAT(DISTINCT s.serviceType) AS types
        FROM Supplier sp LEFT JOIN BookingService s ON s.supplierId = sp.supplierId AND s.serviceStatus = 'Active'
        GROUP BY sp.supplierId ORDER BY paidToSupplier DESC""")
    return render_template("suppliers.html", rows=rows)


# ---- quick-view panels (opened beside a list without leaving the page)
@app.route("/peek/client/<int:cid>")
def peek_client(cid):
    c = q("""SELECT c.*, e.firstName || ' ' || e.lastName AS agent, e.department, e.branch
             FROM Client c JOIN Employee e ON e.employeeId = c.employeeId WHERE c.clientId = ?""", (cid,), one=True)
    if not c:
        abort(404)
    credit = credit_accounts("ca.clientId = ?", (cid,))
    return render_template("peek_client.html", c=c,
                           phones=q("SELECT clientPhoneNo FROM ClientPhone WHERE clientId = ?", (cid,)),
                           credit=credit[0] if credit else None,
                           travelers=q("""SELECT t.* FROM Traveler t JOIN ClientTraveler ct ON ct.travelerId = t.travelerId
                                          WHERE ct.clientId = ? ORDER BY t.lastName""", (cid,)),
                           bookings=bookings("b.clientId = ?", (cid,)),
                           quotes=q("""SELECT qu.*, (SELECT SUM(quotedPrice) FROM QuotationLine l WHERE l.quotationId = qu.quotationId) AS quotedTotal
                                       FROM Quotation qu WHERE qu.clientId = ? AND quoteStatus = 'Pending'""", (cid,)))


@app.route("/peek/booking/<int:bid>")
def peek_booking(bid):
    rows = bookings("b.bookingId = ?", (bid,))
    if not rows:
        abort(404)
    return render_template("peek_booking.html", b=rows[0],
                           services=q("""SELECT s.*, sp.supplierName, s.supplierCost + s.serviceFee AS price
                                         FROM BookingService s JOIN Supplier sp ON sp.supplierId = s.supplierId
                                         WHERE s.bookingId = ? ORDER BY s.serviceNo""", (bid,)),
                           travelers=q("""SELECT t.*, bt.isLeadTraveler FROM BookingTraveler bt JOIN Traveler t ON t.travelerId = bt.travelerId
                                          WHERE bt.bookingId = ? ORDER BY bt.isLeadTraveler DESC, t.lastName""", (bid,)),
                           invoices=invoices("COALESCE(i.bookingId, m.bookingId) = :b", {"b": bid}))


@app.route("/peek/traveler/<int:tid>")
def peek_traveler(tid):
    t = q("""SELECT t.*, CAST((julianday(?) - julianday(t.dateOfBirth)) / 365.25 AS INT) AS age
             FROM Traveler t WHERE t.travelerId = ?""", (TODAY, tid), one=True)
    if not t:
        abort(404)
    return render_template("peek_traveler.html", t=t,
                           phones=q("SELECT travelerPhoneNo FROM TravelerPhone WHERE travelerId = ?", (tid,)),
                           clients=q("""SELECT c.* FROM Client c JOIN ClientTraveler ct ON ct.clientId = c.clientId
                                        WHERE ct.travelerId = ?""", (tid,)),
                           trips=q(BALANCE_CTE + """
                               SELECT b.bookingId, b.bookingStatus, b.tripStart, c.clientName, bt.isLeadTraveler
                               FROM Bal b JOIN BookingTraveler bt ON bt.bookingId = b.bookingId
                               JOIN Client c ON c.clientId = b.clientId
                               WHERE bt.travelerId = ? ORDER BY b.tripStart DESC""", (tid,)),
                           soon=(date.fromisoformat(TODAY) + timedelta(days=183)).isoformat())


# ---- SQL reports: the exact queries of Chapter 7
@lru_cache(maxsize=1)
def load_blocks(filename, prefix):
    text = open(os.path.join(SQL_DIR, filename), encoding="utf-8").read()
    parts = re.split(rf"\n(?=-- {prefix}\d+\. )", text)
    out = []
    for p in parts[1:]:
        lines = p.strip().splitlines()
        m = re.match(rf"-- ({prefix}\d+)\. (.*)", lines[0])
        comments, code = [], []
        for ln in lines[1:]:
            (comments if ln.startswith("--") and not code else code).append(ln)
        purpose = " ".join(c[2:].strip() for c in comments).replace("Purpose: ", "").strip()
        out.append({"id": m.group(1), "title": m.group(2).strip(), "purpose": purpose,
                    "sql": "\n".join(code).strip()})
    return tuple(out)


@app.route("/reports")
def reports():
    run = request.args.get("q")
    blocks = load_blocks("ugw_queries.sql", "Q")
    result = None
    if run:
        blk = next((b for b in blocks if b["id"] == run), None)
        if not blk:
            abort(404)
        cur = db().execute(blk["sql"])
        result = {"blk": blk, "cols": [d[0] for d in cur.description], "rows": cur.fetchall()}
    return render_template("reports.html", blocks=blocks, result=result, run=run)


@app.route("/rules")
def rules():
    """Run every constraint test inside a savepoint and roll it back, so the data never changes."""
    tests = []
    for t in load_blocks("ugw_tests.sql", "T"):
        con = db()
        con.execute("SAVEPOINT rule_test")
        try:
            con.execute(t["sql"])
            outcome, msg = "accepted", "The statement was accepted (rolled back)."
        except sqlite3.Error as e:
            outcome, msg = "rejected", str(e)
        finally:
            con.execute("ROLLBACK TO rule_test")
            con.execute("RELEASE rule_test")
        tests.append(dict(t, outcome=outcome, msg=msg))
    return render_template("rules.html", tests=tests)


# ---- database explorer
@app.route("/explorer")
@app.route("/explorer/<table>")
def explorer(table=None):
    tables = [r["name"] for r in q("SELECT name FROM sqlite_master WHERE type='table' ORDER BY rowid")]
    info = [{"name": t, "rows": q(f"SELECT COUNT(*) n FROM {t}", one=True)["n"]} for t in tables]
    data = None
    if table:
        if table not in tables:
            abort(404)
        cols = q(f"PRAGMA table_info({table})")
        fks = q(f"PRAGMA foreign_key_list({table})")
        rows = q(f"SELECT * FROM {table}")
        data = {"name": table, "cols": cols, "fks": {fk["from"]: fk["table"] for fk in fks}, "rows": rows}
    return render_template("explorer.html", info=info, data=data)


@app.route("/about")
def about():
    return render_template("about.html")


@app.route("/reset", methods=["POST"])
def reset():
    close_db(None)
    build_database()
    flash(("ok", "The demo database was rebuilt from ugw_schema.sql and ugw_data.sql."))
    return redirect(url_for("dashboard"))


@app.errorhandler(404)
def not_found(_e):
    if "me" not in g and session.get("eid"):
        g.me = q("SELECT * FROM Employee WHERE employeeId = ?", (session["eid"],), one=True)
    return render_template("base.html", not_found=True), 404


if __name__ == "__main__":
    if not os.path.exists(DB_PATH):
        build_database()
    app.run(debug=True, port=int(os.environ.get("PORT", 5000)))
