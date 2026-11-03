"""Private accounts and transfers with integer money and durable request receipts."""
from contextlib import contextmanager
from datetime import date, datetime
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import subprocess
import time
from zoneinfo import ZoneInfo

from flask import Blueprint, abort, current_app, redirect, render_template, request
from itsdangerous import BadSignature, URLSafeTimedSerializer

from locking import ledger_lock
from security import csrf_token, parse_fields, session_token, verify_csrf
from store import connect

KINDS = {"cash": "Numerar", "card": "Card", "bank": "Cont bancar"}


class FinanceError(Exception):
    def __init__(self, message, status=400):
        self.message, self.status = message, status


def money(raw, positive=False):
    if not re.fullmatch(r"[+-]?[0-9]{1,7}(?:[.,][0-9]{1,2})?", raw):
        raise FinanceError("Suma invalida. Foloseste maximum 7 cifre si doua zecimale.")
    negative = raw.startswith("-")
    parts = raw.lstrip("+-").replace(",", ".").split(".")
    value = int(parts[0])*100 + int((parts[1] if len(parts)>1 else "").ljust(2, "0"))
    value = -value if negative else value
    if positive and value <= 0:
        raise FinanceError("Suma trebuie sa fie mai mare decat zero.")
    return value


def day_value(raw):
    try:
        if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", raw):
            raise ValueError
        date.fromisoformat(raw)
    except ValueError as exc:
        raise FinanceError("Alege o data calendaristica valida.") from exc
    return raw


def text_value(raw, maximum=30):
    value = raw.strip()
    if not value or len(value.encode()) > maximum:
        raise FinanceError("Textul este gol sau prea lung. Foloseste un nume ori o descriere mai scurta.")
    return value


def accounts(db):
    db.row_factory = sqlite3.Row
    rows = db.execute("""SELECT a.*,
        a.opening_cents + coalesce((SELECT sum(amount_cents) FROM ledger WHERE account_id=a.id),0)
        + coalesce((SELECT sum(amount_cents) FROM transfers WHERE destination_id=a.id AND voided=0),0)
        - coalesce((SELECT sum(amount_cents) FROM transfers WHERE source_id=a.id AND voided=0),0) AS balance
        FROM accounts a ORDER BY a.active DESC,a.id""").fetchall()
    reserved = {}
    if db.execute("PRAGMA user_version").fetchone()[0] >= 3:
        reserved = {row[0]: row[1] for row in db.execute("""SELECT g.account_id,coalesce(sum(c.amount_cents),0)
            FROM savings_goals g LEFT JOIN goal_contributions c ON c.goal_id=g.id
            WHERE g.state='active' GROUP BY g.account_id""")}
    return [{**dict(row), "reserved": reserved.get(row["id"], 0),
             "available": max(0, row["balance"]-reserved.get(row["id"], 0))} for row in rows]


def goals(db):
    db.row_factory = sqlite3.Row
    rows = db.execute("""SELECT g.*,a.name AS account_name,a.active AS account_active,
        coalesce(sum(c.amount_cents),0) AS saved FROM savings_goals g
        JOIN accounts a ON a.id=g.account_id LEFT JOIN goal_contributions c ON c.goal_id=g.id
        GROUP BY g.id ORDER BY CASE g.state WHEN 'active' THEN 0 WHEN 'completed' THEN 1 ELSE 2 END,g.id DESC""").fetchall()
    today = datetime.now(ZoneInfo(os.environ.get("LEDGER_TIMEZONE", "Europe/Bucharest"))).date()
    result = []
    for row in rows:
        goal = dict(row)
        if not 0 <= goal["saved"] <= goal["target_cents"]:
            raise sqlite3.IntegrityError("Invalid goal allocation total")
        goal.update(remaining=goal["target_cents"]-goal["saved"], progress=goal["saved"]*100//goal["target_cents"], overdue=False, monthly=None)
        if goal["deadline"]:
            due = date.fromisoformat(goal["deadline"])
            goal["overdue"] = due < today and goal["remaining"] > 0 and goal["state"] == "active"
            if due >= today and goal["remaining"]:
                months = max(1,(due.year-today.year)*12+due.month-today.month+int(due.day>=today.day))
                goal["monthly"] = (goal["remaining"]+months-1)//months
        result.append(goal)
    return result


def find_goal(db, key, active=False):
    goal = next((row for row in goals(db) if row["id"] == key), None)
    if goal is None:
        raise FinanceError("Obiectivul nu exista.", 404)
    if active and goal["state"] != "active":
        raise FinanceError("Reia obiectivul inainte de a modifica alocarea.", 409)
    return goal


def find_account(db, key, active=False):
    value = next((row for row in accounts(db) if row["id"] == key), None)
    if value is None:
        raise FinanceError("Contul nu exista.", 404)
    if active and not value["active"]:
        raise FinanceError("Contul este arhivat. Reactiveaza-l inainte de aceasta operatie.", 409)
    return value


def owner(session):
    return hashlib.sha256(session.encode()).hexdigest()


def signer():
    return URLSafeTimedSerializer(current_app.config["SECRET_KEY"], salt="ledger-finance-request-v1")


def operation_token(session, operation):
    return signer().dumps({"owner": owner(session), "operation": operation, "nonce": secrets.token_hex(16)})


def mutate(db, session, operation, fields, action):
    try:
        signed = signer().loads(request.form.get("nonce", ""), max_age=28800)
        if (not isinstance(signed, dict) or signed.get("owner") != owner(session)
                or signed.get("operation") != operation or not re.fullmatch(r"[0-9a-f]{32}", signed.get("nonce", ""))):
            raise BadSignature("Invalid request binding")
    except BadSignature as exc:
        raise FinanceError("Formular expirat sau invalid. Reincarca pagina.", 403) from exc
    fingerprint = hashlib.sha256(json.dumps(fields, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    db.execute("BEGIN IMMEDIATE")
    previous = db.execute("SELECT owner,operation,payload_hash,result_json FROM finance_requests WHERE nonce=?", (signed["nonce"],)).fetchone()
    if previous:
        if tuple(previous[:3]) != (owner(session), operation, fingerprint):
            raise FinanceError("Acest formular a fost deja folosit cu alte valori. Reincarca pagina.", 409)
        db.commit()
        return json.loads(previous[3])
    result = action(db)
    now = int(time.time())
    db.execute("INSERT INTO finance_requests VALUES(?,?,?,?,?,?)", (signed["nonce"], owner(session), operation, fingerprint, json.dumps(result), now))
    db.execute("INSERT INTO finance_events(operation,object_id,owner,created_at) VALUES(?,?,?,?)", (operation.split(":", 1)[0], result["object_id"], owner(session), now))
    db.commit()
    return result


def create_finance_blueprint(authorize, configured, work_dir):
    bp = Blueprint("finance", __name__)

    @bp.errorhandler(401)
    def login_required(error):
        return redirect("/") if request.method == "GET" else ("Sesiunea a expirat. Autentifica-te din nou.", 401)

    @bp.errorhandler(FinanceError)
    def invalid(error):
        session = session_token()
        is_goal = request.path.startswith("/goals")
        return render_template("finance_error.html", active="goals" if is_goal else "accounts", csrf=csrf_token(current_app.config["SECRET_KEY"], session),
                               message=error.message, back="/goals" if is_goal else "/accounts"), error.status

    @contextmanager
    def access(limits=None):
        if not configured():
            abort(503)
        session = session_token()
        fields = {}
        if request.method == "POST":
            if request.query_string or request.mimetype != "application/x-www-form-urlencoded":
                abort(415 if request.mimetype != "application/x-www-form-urlencoded" else 400)
            fields = parse_fields(request.get_data(), {"csrf_token": 300, "nonce": 600, **(limits or {})})
            verify_csrf(current_app.config["SECRET_KEY"], session, fields.pop("csrf_token", ""),
                        os.environ.get("LEDGER_PUBLIC_ORIGIN", "https://cobol.micutu.com"))
            fields.pop("nonce", None)
        try:
            with ledger_lock(work_dir):
                if request.method == "POST" and Path(work_dir, "data/.deploying").exists():
                    abort(503, "Actualizare in curs. Reincearca in cateva secunde.")
                authorize(session, recover=request.method == "POST")
                with connect(work_dir) as db:
                    db.row_factory = sqlite3.Row
                    yield session, fields, db
        except TimeoutError:
            abort(503, "Registrul este ocupat. Reincearca.")
        except (OSError, sqlite3.Error, subprocess.SubprocessError):
            current_app.logger.error("finance_store_unavailable")
            abort(503, "Registrul nu este disponibil. Reincarca pagina inainte sa reincerci.")

    def page(session, template, **context):
        return render_template(template, csrf=csrf_token(current_app.config["SECRET_KEY"], session),
            nonce=lambda operation: operation_token(session, operation), kinds=KINDS,
            today=datetime.now(ZoneInfo(os.environ.get("LEDGER_TIMEZONE", "Europe/Bucharest"))).date().isoformat(), **context)

    @bp.get("/accounts")
    def overview():
        query = parse_fields(request.query_string, {"edit": 6, "page": 5, "notice": 12})
        with access() as (session, _, db):
            rows = accounts(db)
            edit = find_account(db, int(query["edit"])) if query.get("edit") else None
            total = db.execute("SELECT count(*) FROM transfers").fetchone()[0]
            pages = max(1, (total+19)//20)
            selected = min(max(1, int(query.get("page") or 1)), pages)
            transfers = db.execute("""SELECT t.*,s.name AS source,d.name AS destination
                FROM transfers t JOIN accounts s ON s.id=t.source_id JOIN accounts d ON d.id=t.destination_id
                ORDER BY t.id DESC LIMIT 20 OFFSET ?""", ((selected-1)*20,)).fetchall()
            return page(session, "accounts.html", active="accounts", accounts=rows, edit=edit, transfers=transfers,
                        balance=sum(a["balance"] for a in rows), opening=sum(a["opening_cents"] for a in rows),
                        selected_page=selected, pages=pages, notice=query.get("notice", ""))

    @bp.post("/accounts/create")
    def create_account():
        with access({"name": 30, "kind": 8, "opening": 20}) as (session, fields, db):
            name, kind = text_value(fields.get("name", "")), fields.get("kind", "")
            opening = money(fields.get("opening", "0"))
            if kind not in KINDS:
                raise FinanceError("Tip de cont invalid.")
            def action(connection):
                if connection.execute("SELECT count(*) FROM accounts").fetchone()[0] >= 20:
                    raise FinanceError("Poti pastra maximum 20 de conturi.", 409)
                if connection.execute("SELECT 1 FROM accounts WHERE name=?", (name,)).fetchone():
                    raise FinanceError("Exista deja un cont cu acest nume.", 409)
                key = connection.execute("INSERT INTO accounts(name,kind,opening_cents) VALUES(?,?,?)", (name, kind, opening)).lastrowid
                return {"object_id": key}
            mutate(db, session, "account-create", fields, action)
            return redirect("/accounts?notice=saved", code=303)

    @bp.post("/accounts/<int:key>/save")
    def save_account(key):
        with access({"name": 30, "kind": 8}) as (session, fields, db):
            name, kind = text_value(fields.get("name", "")), fields.get("kind", "")
            if kind not in KINDS:
                raise FinanceError("Tip de cont invalid.")
            def action(connection):
                find_account(connection, key)
                if connection.execute("SELECT 1 FROM accounts WHERE name=? AND id<>?", (name, key)).fetchone():
                    raise FinanceError("Exista deja un cont cu acest nume.", 409)
                connection.execute("UPDATE accounts SET name=?,kind=? WHERE id=?", (name, kind, key))
                return {"object_id": key}
            mutate(db, session, f"account-save:{key}", fields, action)
            return redirect("/accounts?notice=saved", code=303)

    @bp.post("/accounts/<int:key>/status")
    def account_status(key):
        with access({"active": 1}) as (session, fields, db):
            if fields.get("active") not in {"0", "1"}:
                abort(400)
            def action(connection):
                find_account(connection, key)
                if key == 1 and fields["active"] == "0":
                    raise FinanceError("Registrul principal ramane activ pentru tranzactiile recurente.", 409)
                connection.execute("UPDATE accounts SET active=? WHERE id=?", (int(fields["active"]), key))
                return {"object_id": key}
            mutate(db, session, f"account-status:{key}", fields, action)
            return redirect("/accounts?notice=saved", code=303)

    @bp.post("/transfers/create")
    def create_transfer():
        with access({"source": 6, "destination": 6, "date": 10, "description": 60, "amount": 20}) as (session, fields, db):
            if not all(re.fullmatch(r"[0-9]{1,6}", fields.get(key, "")) for key in ("source", "destination")):
                raise FinanceError("Alege conturile transferului.")
            source, destination = int(fields["source"]), int(fields["destination"])
            if source == destination:
                raise FinanceError("Alege doua conturi diferite.")
            amount = money(fields.get("amount", ""), positive=True)
            day, description = day_value(fields.get("date", "")), text_value(fields.get("description", ""), 60)
            def action(connection):
                origin = find_account(connection, source, active=True)
                find_account(connection, destination, active=True)
                if origin["available"] < amount:
                    raise FinanceError("Sold disponibil insuficient in contul sursa.", 409)
                before = sum(a["balance"] for a in accounts(connection))
                key = connection.execute("INSERT INTO transfers(source_id,destination_id,day,description,amount_cents,created_at) VALUES(?,?,?,?,?,?)",
                    (source, destination, day, description, amount, int(time.time()))).lastrowid
                if sum(a["balance"] for a in accounts(connection)) != before:
                    raise sqlite3.IntegrityError("Transfer changed total balance")
                return {"object_id": key}
            mutate(db, session, "transfer-create", fields, action)
            return redirect("/accounts?notice=transferred", code=303)

    @bp.post("/transfers/<int:key>/void")
    def void_transfer(key):
        with access() as (session, fields, db):
            def action(connection):
                transfer = connection.execute("SELECT * FROM transfers WHERE id=?", (key,)).fetchone()
                if transfer is None:
                    raise FinanceError("Transferul nu exista.", 404)
                if not transfer["voided"]:
                    destination = find_account(connection, transfer["destination_id"])
                    if destination["available"] < transfer["amount_cents"]:
                        raise FinanceError("Banii nu mai sunt disponibili in contul destinatie. Corecteaza soldul sau alocarile inainte de anulare.", 409)
                    connection.execute("UPDATE transfers SET voided=1 WHERE id=?", (key,))
                return {"object_id": key}
            mutate(db, session, f"transfer-void:{key}", fields, action)
            return redirect("/accounts?notice=voided", code=303)

    @bp.get("/goals")
    def goals_overview():
        query = parse_fields(request.query_string, {"edit": 6, "state": 10, "notice": 12})
        state = query.get("state", "all")
        if state not in {"all", "active", "completed", "archived"}:
            abort(400)
        with access() as (session, _, db):
            all_goals, account_rows = goals(db), accounts(db)
            edit = find_goal(db, int(query["edit"]), active=True) if query.get("edit") else None
            history = db.execute("""SELECT c.*,g.name AS goal_name FROM goal_contributions c
                JOIN savings_goals g ON g.id=c.goal_id ORDER BY c.id DESC LIMIT 20""").fetchall()
            current = [goal for goal in all_goals if goal["state"] == "active"]
            return page(session, "goals.html", active="goals", state=state,
                        goals=[goal for goal in all_goals if state == "all" or goal["state"] == state],
                        accounts=account_rows, edit=edit, history=history, notice=query.get("notice", ""),
                        reserved=sum(g["saved"] for g in current), target=sum(g["target_cents"] for g in current),
                        completed=sum(g["state"] == "completed" for g in all_goals),
                        deficits=[a for a in account_rows if a["reserved"] > max(0,a["balance"])])

    @bp.post("/goals/create")
    def create_goal():
        with access({"name": 30, "account": 6, "target": 20, "deadline": 10}) as (session, fields, db):
            name, target = text_value(fields.get("name", "")), money(fields.get("target", ""), positive=True)
            deadline = day_value(fields["deadline"]) if fields.get("deadline") else None
            if not re.fullmatch(r"[0-9]{1,6}", fields.get("account", "")):
                raise FinanceError("Alege contul obiectivului.")
            account = int(fields["account"])
            def action(connection):
                find_account(connection, account, active=True)
                if connection.execute("SELECT count(*) FROM savings_goals").fetchone()[0] >= 50:
                    raise FinanceError("Poti pastra maximum 50 de obiective.", 409)
                key = connection.execute("INSERT INTO savings_goals(name,account_id,target_cents,deadline,created_at) VALUES(?,?,?,?,?)",
                    (name, account, target, deadline, int(time.time()))).lastrowid
                return {"object_id": key}
            mutate(db, session, "goal-create", fields, action)
            return redirect("/goals?notice=saved", code=303)

    @bp.post("/goals/<int:key>/save")
    def save_goal(key):
        with access({"name": 30, "target": 20, "deadline": 10}) as (session, fields, db):
            name, target = text_value(fields.get("name", "")), money(fields.get("target", ""), positive=True)
            deadline = day_value(fields["deadline"]) if fields.get("deadline") else None
            def action(connection):
                goal = find_goal(connection, key, active=True)
                if target < goal["saved"]:
                    raise FinanceError("Tinta nu poate fi mai mica decat suma deja alocata.", 409)
                connection.execute("UPDATE savings_goals SET name=?,target_cents=?,deadline=? WHERE id=?", (name,target,deadline,key))
                return {"object_id": key}
            mutate(db, session, f"goal-save:{key}", fields, action)
            return redirect("/goals?notice=saved", code=303)

    @bp.post("/goals/<int:key>/contribute")
    def contribute(key):
        with access({"direction": 8, "amount": 20, "note": 60}) as (session, fields, db):
            direction = fields.get("direction")
            if direction not in {"allocate", "release"}:
                abort(400)
            amount = money(fields.get("amount", ""), positive=True)
            note = text_value(fields.get("note") or ("Alocare" if direction == "allocate" else "Eliberare"), 60)
            def action(connection):
                goal = find_goal(connection, key, active=True)
                account = find_account(connection, goal["account_id"], active=direction=="allocate")
                if direction == "allocate" and (account["available"] < amount or goal["remaining"] < amount):
                    raise FinanceError("Suma depaseste disponibilul contului sau ce mai ramane pana la tinta.", 409)
                if direction == "release" and goal["saved"] < amount:
                    raise FinanceError("Nu poti elibera mai mult decat suma alocata.", 409)
                connection.execute("INSERT INTO goal_contributions(goal_id,amount_cents,note,created_at) VALUES(?,?,?,?)",
                    (key, amount if direction == "allocate" else -amount, note, int(time.time())))
                return {"object_id": key}
            mutate(db, session, f"goal-contribute:{key}", fields, action)
            return redirect("/goals?notice=allocated", code=303)

    @bp.post("/goals/<int:key>/status")
    def goal_status(key):
        with access({"state": 10}) as (session, fields, db):
            state = fields.get("state")
            if state not in {"active", "completed", "archived"}:
                abort(400)
            def action(connection):
                goal = find_goal(connection, key)
                if state == "archived" and goal["saved"]:
                    raise FinanceError("Elibereaza alocarea inainte de arhivare, sau finalizeaza obiectivul finantat integral.", 409)
                if state == "completed" and goal["remaining"]:
                    raise FinanceError("Atinge tinta inainte de a finaliza obiectivul.", 409)
                if state == "active" and goal["state"] != "active":
                    account = find_account(connection, goal["account_id"], active=True)
                    if account["available"] < goal["saved"]:
                        raise FinanceError("Soldul nu acopera alocarea istorica. Nu poti relua inca obiectivul.", 409)
                connection.execute("UPDATE savings_goals SET state=? WHERE id=?", (state,key))
                return {"object_id": key}
            mutate(db, session, f"goal-status:{key}", fields, action)
            return redirect("/goals?notice=saved", code=303)

    return bp
