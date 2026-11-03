"""Private CSV import: bounded upload, explicit mapping, preview, atomic commit."""
from contextlib import contextmanager
import csv
from datetime import date
from decimal import Decimal
import hashlib
import io
import json
import logging
import os
from pathlib import Path
import re
import secrets
import sqlite3
import subprocess
import time

from flask import Blueprint, Response, abort, current_app, redirect, render_template, request, url_for

from security import CATEGORIES, csrf_token, ledger_lock, session_token, verify_csrf
from store import connect

MAX_FILE = 64 * 1024
MAX_ROWS = 200
DRAFT_TTL = 1800
RECEIPT_TTL = 30 * 86400
logger = logging.getLogger("ledger")


def read_csv(raw, delimiter):
    if not raw or len(raw) > MAX_FILE:
        raise ValueError("Fisierul trebuie sa aiba intre 1 byte si 64 KiB.")
    try:
        text = raw.decode("utf-8-sig", errors="strict")
        if any(ord(c) < 32 and c not in "\r\n\t" or ord(c) == 127 for c in text):
            raise ValueError("Fisierul contine caractere de control.")
        if delimiter == "auto":
            delimiter = csv.Sniffer().sniff(text[:8192], delimiters=",;\t").delimiter
        elif delimiter not in {",", ";", "\t"}:
            raise ValueError("Separator invalid.")
        table = []
        for row in csv.reader(io.StringIO(text, newline=""), delimiter=delimiter, strict=True):
            if not any(cell.strip() for cell in row):
                continue
            if len(table) >= MAX_ROWS + 1:
                raise ValueError("Importa cel mult 200 de tranzactii intr-un fisier.")
            if not 1 <= len(row) <= 20 or any(len(cell.encode()) > 2000 for cell in row):
                raise ValueError("Cel mult 20 de coloane si 2000 bytes pe celula.")
            table.append(row)
        if len(table) < 2 or len(table[0]) < 3:
            raise ValueError("Sunt necesare antetul si cel putin o tranzactie, cu minimum 3 coloane.")
        headers = [h.strip() for h in table[0]]
        if any(not h or len(h.encode()) > 128 or any(ord(c) < 32 for c in h) for h in headers):
            raise ValueError("Antetul contine nume de coloane invalide.")
        if any(len(row) != len(headers) for row in table[1:]):
            raise ValueError("Randurile trebuie sa aiba acelasi numar de coloane ca antetul.")
        return [headers, *table[1:]]
    except (UnicodeError, csv.Error) as exc:
        raise ValueError("CSV invalid. Foloseste UTF-8 si selecteaza separatorul potrivit.") from exc


def normalized(row, mapping, options):
    day, category, description, amount = (
        row[mapping[key]].strip() if mapping[key] >= 0 else options["category"]
        for key in ("day", "category", "description", "amount"))
    if options["date_format"] == "dmy":
        if not re.fullmatch(r"[0-9]{2}([./])[0-9]{2}\1[0-9]{4}", day):
            raise ValueError("Data trebuie sa fie ZZ.LL.AAAA sau ZZ/LL/AAAA.")
        day = day[6:10] + "-" + day[3:5] + "-" + day[:2]
    try:
        if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", day):
            raise ValueError
        date.fromisoformat(day)
    except ValueError as exc:
        raise ValueError("Data calendaristica invalida.") from exc
    if category not in CATEGORIES:
        raise ValueError("Categorie necunoscuta; alege o categorie implicita la mapare.")
    if options["ledger_export"] and len(description) > 1 and description[0] == "'" and description[1] in "=+-@":
        description = description[1:]
    if not description or len(description.encode()) > 30 or any(ord(c) < 32 or ord(c) == 127 for c in description):
        raise ValueError("Descriere obligatorie, maximum 30 bytes UTF-8, fara caractere de control.")
    separator = options["decimal"]
    if not re.fullmatch(r"[+-]?[0-9]{1,7}(?:" + re.escape(separator) + r"[0-9]{1,2})?", amount):
        raise ValueError("Suma invalida: maximum 7 cifre si 2 zecimale, fara separatori de mii.")
    cents = int(Decimal(amount.replace(",", ".")) * 100)
    return [day, category, description, cents]


def preview(db, rows, include_duplicates=False, account_id=1):
    seen = set()
    result = []
    for row in rows:
        key = tuple(row)
        duplicate = key in seen or db.execute(
            "SELECT 1 FROM ledger WHERE day=? AND category=? AND description=? AND amount_cents=? AND account_id=? LIMIT 1", (*row, account_id)).fetchone() is not None
        seen.add(key)
        result.append({"row": row, "duplicate": duplicate,
                       "skip": duplicate and not include_duplicates, "error": ""})
    return result


def create_import_blueprint(authorize, configured, work_dir):
    bp = Blueprint("csv_import", __name__)

    @bp.app_template_filter("cents")
    def cents(value):
        value = int(value)
        return ("-" if value < 0 else "") + f"{abs(value)//100}.{abs(value)%100:02d}"

    @bp.errorhandler(401)
    def login_required(error):
        return redirect("/") if request.method == "GET" else ("Sesiunea a expirat. Autentifica-te din nou.", 401)

    @contextmanager
    def access(fields=(), upload=False, recover=False):
        if not configured():
            abort(503)
        if request.query_string:
            abort(400)
        request.max_content_length = 96 * 1024 if upload else 4096
        request.max_form_memory_size = 96 * 1024
        request.max_form_parts = 12
        session = session_token()
        if request.method == "POST":
            if request.mimetype != ("multipart/form-data" if upload else "application/x-www-form-urlencoded"):
                abort(415)
            allowed = {*fields, "csrf_token"}
            if set(request.form) - allowed or any(len(request.form.getlist(k)) != 1 for k in request.form):
                abort(400, "Camp necunoscut sau duplicat.")
            if any(len(v.encode()) > 300 or any(ord(c) < 32 and c != "\t" or ord(c) == 127 for c in v) for v in request.form.values()):
                abort(400)
            verify_csrf(current_app.config["SECRET_KEY"], session, request.form.get("csrf_token", ""),
                        os.environ.get("LEDGER_PUBLIC_ORIGIN", "https://cobol.micutu.com"))
            if set(request.files) != ({"file"} if upload else set()) or (upload and len(request.files.getlist("file")) != 1):
                abort(400, "Alege un singur fisier CSV.")
        try:
            with ledger_lock(work_dir):
                if request.method == "POST" and Path(work_dir, "data/.deploying").exists():
                    abort(503, "Actualizare in curs. Reincearca in cateva secunde.")
                reserved = authorize(session, recover=recover)
                yield session, reserved
        except TimeoutError:
            abort(503, "Registrul este ocupat. Reincearca.")
        except (OSError, sqlite3.Error, subprocess.SubprocessError):
            logger.error("csv_store_unavailable")
            abort(503, "Importul nu este disponibil. Nicio confirmare partiala nu este acceptata.")

    def binding(session):
        return hashlib.sha256(session.encode()).hexdigest()

    def load_batch(db, token, session):
        if not re.fullmatch(r"[0-9a-f]{32}", token):
            abort(404)
        db.row_factory = sqlite3.Row
        batch = db.execute("SELECT * FROM import_batches WHERE token=? AND owner=?", (token, binding(session))).fetchone()
        if batch is None:
            abort(404)
        if batch["expires"] < int(time.time()):
            db.execute("DELETE FROM import_batches WHERE token=?", (token,))
            abort(410, "Previzualizarea a expirat. Incarca din nou fisierul.")
        return batch

    def page(session, stage="upload", **kwargs):
        return render_template("import.html", stage=stage, csrf=csrf_token(current_app.config["SECRET_KEY"], session),
                               categories=sorted(CATEGORIES), **kwargs)

    def mapped_page(session, batch, error=""):
        table = json.loads(batch["source_json"])
        options = json.loads(batch["options_json"])
        synonyms = {"day": {"data", "date", "day"}, "category": {"categorie", "category", "cat"},
                    "description": {"descriere", "description", "desc", "detalii"}, "amount": {"suma", "amount", "value", "valoare"}}
        defaults = {key: next((i for i, header in enumerate(table[0]) if header.lower() in names), -1 if key == "category" else "") for key, names in synonyms.items()}
        defaults.update(options.get("mapping", {}))
        with connect(work_dir) as choices_db:
            account_choices = choices_db.execute("SELECT id,name FROM accounts WHERE active=1 ORDER BY id").fetchall()
        account_choices = [{"id": row[0], "name": row[1]} for row in account_choices]
        return page(session, "mapping", token=batch["token"], table=table, options=options, mapping=defaults, error=error, account_choices=account_choices)

    def preview_page(session, batch, message=""):
        result = json.loads(batch["preview_json"])
        return page(session, "preview", token=batch["token"], rows=result, message=message,
                    valid=not any(r["error"] for r in result),
                    added=sum(not r["skip"] and not r["error"] for r in result),
                    skipped=sum(r["skip"] for r in result),
                    net=sum(r["row"][3] for r in result if not r["skip"] and not r["error"]))

    @bp.route("/import", methods=["GET", "POST"])
    def upload():
        with access(fields=("delimiter", "decimal", "date_format"), upload=request.method == "POST") as (session, _):
            if request.method == "GET":
                with connect(work_dir) as db:
                    db.row_factory = sqlite3.Row
                    recent = db.execute("SELECT token,state,added,skipped FROM import_batches WHERE owner=? AND expires>=? ORDER BY rowid DESC LIMIT 6", (binding(session), int(time.time()))).fetchall()
                return page(session, recent=recent)
            options = {"decimal": request.form.get("decimal", "."), "date_format": request.form.get("date_format", "iso")}
            if options["decimal"] not in {".", ","} or options["date_format"] not in {"iso", "dmy"}:
                abort(400)
            try:
                table = read_csv(request.files["file"].stream.read(MAX_FILE + 1), request.form.get("delimiter", "auto"))
            except ValueError as exc:
                return page(session, error=str(exc)), 400
            token = secrets.token_hex(16)
            with connect(work_dir) as db:
                now = int(time.time())
                db.execute("BEGIN IMMEDIATE")
                db.execute("DELETE FROM import_batches WHERE expires<?", (now,))
                pending = db.execute("SELECT token FROM import_batches WHERE owner=? AND state!='done' ORDER BY expires DESC", (binding(session),)).fetchall()
                db.executemany("DELETE FROM import_batches WHERE token=?", pending[2:])
                db.execute("INSERT INTO import_batches(token,owner,expires,source_json,options_json) VALUES(?,?,?,?,?)",
                           (token, binding(session), now+DRAFT_TTL, json.dumps(table), json.dumps(options)))
                db.commit()
            return redirect(url_for("csv_import.mapping", token=token), code=303)

    @bp.get("/import/<token>/mapping")
    def mapping(token):
        with access() as (session, _), connect(work_dir) as db:
            batch = load_batch(db, token, session)
            if batch["state"] == "done":
                return redirect(url_for("csv_import.receipt", token=token))
            return mapped_page(session, batch)

    @bp.post("/import/<token>/preview")
    def prepare(token):
        fields = ("day", "category", "description", "amount", "default_category", "duplicates", "ledger_export", "account")
        with access(fields=fields) as (session, _), connect(work_dir) as db:
            batch = load_batch(db, token, session)
            if batch["state"] == "done":
                return redirect(url_for("csv_import.receipt", token=token), code=303)
            table, options = json.loads(batch["source_json"]), json.loads(batch["options_json"])
            selected = {}
            for key in ("day", "category", "description", "amount"):
                value = request.form.get(key, "")
                if not re.fullmatch(r"-1|[0-9]{1,2}", value):
                    return mapped_page(session, batch, "Alege o coloana pentru fiecare camp."), 400
                selected[key] = int(value)
                if not (-1 if key == "category" else 0) <= selected[key] < len(table[0]):
                    abort(400)
            columns = [n for n in selected.values() if n >= 0]
            if len(set(columns)) != len(columns):
                return mapped_page(session, batch, "Fiecare camp trebuie asociat unei coloane diferite."), 400
            options.update(mapping=selected, category=request.form.get("default_category", "Hobby"),
                           duplicates=request.form.get("duplicates", "skip"), ledger_export=request.form.get("ledger_export") == "yes")
            if options["category"] not in CATEGORIES or options["duplicates"] not in {"skip", "include"} or request.form.get("ledger_export", "no") not in {"no", "yes"}:
                abort(400)
            account_raw = request.form.get("account", "1")
            if not re.fullmatch(r"[0-9]{1,6}", account_raw):
                abort(400)
            options["account_id"] = int(account_raw)
            if not db.execute("SELECT 1 FROM accounts WHERE id=? AND active=1", (options["account_id"],)).fetchone():
                return mapped_page(session, batch, "Alege un cont activ pentru import."), 409
            result, valid_rows = [], []
            for number, raw in enumerate(table[1:], start=2):
                try:
                    row = normalized(raw, selected, options)
                    valid_rows.append(row)
                    result.append({"row": row, "error": "", "line": number})
                except ValueError as exc:
                    result.append({"row": [raw[selected["day"]], "", raw[selected["description"]], 0], "error": str(exc), "line": number, "skip": False, "duplicate": False})
            decisions = iter(preview(db, valid_rows, options["duplicates"] == "include", options["account_id"]))
            for item in result:
                if not item["error"]:
                    item.update(next(decisions))
            state = "ready" if all(not item["error"] for item in result) else "staged"
            db.execute("UPDATE import_batches SET options_json=?,preview_json=?,rows_json=?,state=? WHERE token=?",
                       (json.dumps(options), json.dumps(result), json.dumps(valid_rows), state, token))
            return redirect(url_for("csv_import.receipt", token=token), code=303)

    @bp.get("/import/<token>")
    def receipt(token):
        with access() as (session, _), connect(work_dir) as db:
            batch = load_batch(db, token, session)
            if batch["state"] == "done":
                return page(session, "done", added=batch["added"], skipped=batch["skipped"])
            if batch["preview_json"] == "[]":
                return redirect(url_for("csv_import.mapping", token=token))
            return preview_page(session, batch)

    @bp.post("/import/<token>/confirm")
    def confirm(token):
        with access(recover=True) as (session, reserved), connect(work_dir) as db:
            db.execute("BEGIN IMMEDIATE")
            batch = load_batch(db, token, session)
            if batch["state"] == "done":
                return redirect(url_for("csv_import.receipt", token=token), code=303)
            if batch["state"] != "ready":
                abort(409, "Corecteaza erorile si verifica previzualizarea.")
            options = json.loads(batch["options_json"])
            rows = json.loads(batch["rows_json"])
            account_id = options.get("account_id", 1)
            if not db.execute("SELECT 1 FROM accounts WHERE id=? AND active=1", (account_id,)).fetchone():
                abort(409, "Contul importului este arhivat. Alege un cont activ la mapare.")
            current = preview(db, rows, options["duplicates"] == "include", account_id)
            old = json.loads(batch["preview_json"])
            if [r["skip"] for r in current] != [r["skip"] for r in old]:
                for fresh, previous in zip(current, old):
                    fresh["line"] = previous["line"]
                db.execute("UPDATE import_batches SET preview_json=? WHERE token=?", (json.dumps(current), token))
                db.commit()
                return preview_page(session, load_batch(db, token, session), "Registrul s-a schimbat. Verifica noua previzualizare si confirma din nou."), 409
            accepted = [r["row"] for r in current if not r["skip"]]
            last = max(reserved, db.execute("SELECT coalesce(max(id),0) FROM ledger").fetchone()[0],
                       (db.execute("SELECT seq FROM sqlite_sequence WHERE name='ledger'").fetchone() or [0])[0])
            if last + len(accepted) > 999999:
                abort(409, "Importul depaseste limita de ID-uri a registrului.")
            for offset, row in enumerate(accepted, start=1):
                db.execute("INSERT INTO ledger(id,day,category,description,amount_cents,account_id) VALUES(?,?,?,?,?,?)", (last+offset, *row, account_id))
            skipped = len(current) - len(accepted)
            db.execute("UPDATE import_batches SET state='done',added=?,skipped=?,expires=?,source_json='[]',rows_json='[]',preview_json='[]',options_json='{}' WHERE token=?",
                       (len(accepted), skipped, int(time.time())+RECEIPT_TTL, token))
            db.commit()
            logger.info("csv_import_committed added=%s skipped=%s", len(accepted), skipped)
            return redirect(url_for("csv_import.receipt", token=token), code=303)

    @bp.get("/import/example.csv")
    def example():
        with access():
            return Response("data,categorie,descriere,suma\n2026-01-15,Venituri,Salariu demonstrativ,5000.00\n2026-01-16,Mancare,Cumparaturi demo,-125.50\n",
                            content_type="text/csv; charset=utf-8", headers={"Content-Disposition": "attachment; filename=ledger-model.csv"})

    return bp
