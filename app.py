"""Flask/WSGI bridge for the COBOL ledger, with a strict HTTP trust boundary."""
from datetime import datetime
from contextlib import closing
import logging
import os
from pathlib import Path
import re
import secrets
import sqlite3
import subprocess
from urllib.parse import urlencode
from zoneinfo import ZoneInfo
from xml.etree.ElementTree import Element, SubElement, tostring

from flask import Flask, Response, abort, g, jsonify, redirect, render_template, request
from werkzeug.security import check_password_hash

from security import (FORM_LIMITS, QUERY_LIMITS, SESSION_COOKIE, client_ip,
                      csrf_token, ledger_lock, parse_fields, session_token,
                      verify_csrf)
from store import APPLICATION_ID, SUPPORTED_VERSIONS, connect

BASE_DIR = Path(__file__).resolve().parent
BIN_PATH = os.environ.get("LEDGER_BIN", str(BASE_DIR / "ledger.cgi"))
WORK_DIR = os.environ.get("LEDGER_DIR", str(BASE_DIR))
SUBPROCESS_TIMEOUT = 20
MAX_OUTPUT = 16 * 1024 * 1024
app = Flask(__name__)
app.config.update(
    MAX_CONTENT_LENGTH=4096,
    SECRET_KEY=os.environ.get("LEDGER_CSRF_SECRET", ""),
    TRUSTED_HOSTS=os.environ.get(
        "LEDGER_TRUSTED_HOSTS", "cobol.micutu.com,localhost,127.0.0.1").split(","),
)
logger = logging.getLogger("ledger")
logging.basicConfig(level=logging.INFO)


def configured():
    password_hash = os.environ.get("LEDGER_PASSWORD_HASH", "")
    if password_hash:
        credentials = bool(re.fullmatch(
            r"scrypt:131072:8:1\$[A-Za-z0-9]+\$[0-9a-f]{128}", password_hash))
    else:
        legacy = os.environ.get("LEDGER_PASS_HASH", "")
        credentials = bool(re.fullmatch(r"[0-9a-fA-F]{64}", legacy)) if legacy else bool(
            os.environ.get("LEDGER_PASS"))
    return credentials and len(app.config["SECRET_KEY"]) >= 32


@app.before_request
def identify_request():
    g.request_id = secrets.token_hex(8)


@app.after_request
def security_headers(response):
    response.headers.update({
        "Cache-Control": "no-store, private", "Pragma": "no-cache",
        "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
        "Referrer-Policy": "same-origin", "X-Robots-Tag": (
            "index, follow" if response.status_code == 200 and (
                request.endpoint == "about" or request.path == "/static/public-card.png")
            else "noindex, nofollow"),
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
        "Content-Security-Policy": "default-src 'self'; base-uri 'none'; "
            "object-src 'none'; frame-ancestors 'none'; form-action 'self'; "
            "script-src 'self'; "
            "style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; "
            "connect-src 'self'",
        "X-Request-ID": getattr(g, "request_id", ""),
    })
    response.vary.add("Cookie")
    return response


def public_base():
    return os.environ.get("LEDGER_PUBLIC_ORIGIN", "https://cobol.micutu.com").rstrip("/")


@app.get("/about")
def about():
    # This page is static product information, independent of credentials and ledger data.
    return render_template("about.html", public_base=public_base())


@app.get("/about/")
def about_redirect():
    return redirect("/about", code=308)


@app.get("/robots.txt")
def robots():
    return Response("User-agent: *\nAllow: /\nDisallow: /health\nDisallow: /data/\n"
                    "Disallow: /cgi-bin/\nSitemap: " + public_base() + "/sitemap.xml\n",
                    content_type="text/plain; charset=utf-8")


@app.get("/sitemap.xml")
def sitemap():
    root = Element("urlset", xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")
    url = SubElement(root, "url")
    SubElement(url, "loc").text = public_base() + "/about"
    return Response(tostring(root, encoding="utf-8", xml_declaration=True),
                    content_type="application/xml; charset=utf-8")


@app.route("/health")
def health():
    database = Path(WORK_DIR, "data/ledger.sqlite3")
    store_ok = not Path(WORK_DIR, "data/ledger.dat").exists() and not database.exists()
    if database.is_file() and not database.is_symlink():
        try:
            with closing(sqlite3.connect(database.absolute().as_uri() + "?mode=ro", uri=True, timeout=1)) as db:
                store_ok = (db.execute("PRAGMA application_id").fetchone()[0] == APPLICATION_ID
                            and db.execute("PRAGMA user_version").fetchone()[0] == 3)
                db.execute("SELECT id,day,category,description,amount_cents FROM ledger LIMIT 0")
        except (OSError, sqlite3.Error):
            store_ok = False
    checks = {
        "binary": os.access(BIN_PATH, os.X_OK),
        "data_dir": os.path.isdir(os.path.join(WORK_DIR, "data")) and os.access(
            os.path.join(WORK_DIR, "data"), os.R_OK | os.W_OK | os.X_OK),
        "configuration": configured(),
        "store": store_ok,
    }
    ok = all(checks.values())
    return jsonify(status="ok" if ok else "degraded", checks=checks), 200 if ok else 503


@app.route("/", methods=["GET", "POST"])
def index():
    if not configured():
        abort(503, "Configuratia de securitate este incompleta.")
    if len(request.query_string) > 1024:
        abort(414)
    query = parse_fields(request.query_string, QUERY_LIMITS)
    session = session_token()
    form = {}
    if request.method == "POST":
        if request.mimetype != "application/x-www-form-urlencoded":
            abort(415)
        form = parse_fields(request.get_data(), FORM_LIMITS)
        verify_csrf(app.config["SECRET_KEY"], session, form.pop("csrf_token", ""),
                    os.environ.get("LEDGER_PUBLIC_ORIGIN", "https://cobol.micutu.com"))
        if form.get("cmd") not in {"login", "logout", "add", "update", "del", "budget-save", "budget-del", "rule-save", "rule-toggle", "rule-archive", "rule-book"}:
            abort(400, "Comanda invalida.")
        if Path(WORK_DIR, "data", ".deploying").exists():
            abort(503, "Actualizare in curs. Reincearca in cateva secunde.")
        if form["cmd"] in {"budget-save", "budget-del"} and "month" not in form:
            abort(400, "Luna este obligatorie.")
    env = native_environment(session, query)
    if form.get("cmd") in {"add", "update"} and form.get("account"):
        env["LEDGER_TARGET_ACCOUNT"] = form["account"]
    input_data = urlencode(form).encode("ascii") if request.method == "POST" else None
    env["CONTENT_LENGTH"] = str(len(input_data or b""))
    try:
        with ledger_lock(WORK_DIR):
            # A request may have waited behind the deployment's snapshot lock.
            # Check again here so it cannot write to the previous store afterward.
            if request.method == "POST" and Path(WORK_DIR, "data", ".deploying").exists():
                abort(503, "Actualizare in curs. Reincearca in cateva secunde.")
            password_hash = os.environ.get("LEDGER_PASSWORD_HASH")
            if password_hash:
                env["LEDGER_AUTH_MODE"] = "scrypt"
                if form.get("cmd") == "login":
                    valid = check_password_hash(password_hash, form.get("pass", ""))
                    env["LEDGER_AUTH_VERIFIED"] = "Y" if valid else "N"
            process = subprocess.Popen(
                [BIN_PATH], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, env=env, cwd=WORK_DIR)
            try:
                stdout, stderr = process.communicate(input=input_data, timeout=SUBPROCESS_TIMEOUT)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()  # reap the child and release its file descriptors
                logger.error("backend_timeout request=%s", g.request_id)
                abort(504, "Backend-ul nu a raspuns la timp.")
            if process.returncode != 0 or len(stdout) > MAX_OUTPUT:
                logger.error("backend_failed request=%s exit=%s", g.request_id, process.returncode)
                abort(502, "Backend-ul a esuat.")
            if stderr:
                logger.warning("backend_stderr request=%s bytes=%s", g.request_id, len(stderr))
            return cgi_response(stdout, env["LEDGER_CSRF_TOKEN"], form)
    except TimeoutError:
        response = Response("Registrul este ocupat. Reincearca.", status=503)
        response.headers["Retry-After"] = "2"
        return response
    except sqlite3.Error:
        abort(503, "Registrul nu este disponibil.")
    except OSError:
        logger.exception("backend_unavailable request=%s", g.request_id)
        abort(502, "Backend indisponibil.")


def native_environment(session, query=None):
    query = query or {}
    # Never forward the host process environment or unverified client cookies.
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "TZ": "UTC"}
    for key in ("LEDGER_USER", "LEDGER_PASS", "LEDGER_PASS_HASH", "LEDGER_SESSION_TTL"):
        if key in os.environ:
            env[key] = os.environ[key]
    env.update({
        "REQUEST_METHOD": request.method, "QUERY_STRING": urlencode(query),
        "HTTP_COOKIE": f"session={session}" if session else "",
        "REMOTE_ADDR": client_ip(os.environ.get(
            "LEDGER_TRUSTED_PROXIES", "127.0.0.1/32,::1/128").split(",")),
        "LEDGER_CSRF_TOKEN": csrf_token(app.config["SECRET_KEY"], session),
        "LEDGER_AUTH_MODE": "legacy", "LEDGER_AUTH_VERIFIED": "N",
        "LEDGER_NOTICE": query.get("notice", ""),
        "LEDGER_ACCOUNT_FILTER": query.get("account", "") if query.get("view", "LEDGER") in {"LEDGER", "REPORT"} else "",
        "LEDGER_RULE_KEY": secrets.token_hex(16),
        "LEDGER_LOCAL_TODAY": datetime.now(ZoneInfo(
            os.environ.get("LEDGER_TIMEZONE", "Europe/Bucharest"))).date().isoformat(),
    })
    return env


def native_authorize(session, recover=False):
    """Called only while holding ledger_lock; no admin switches come from HTTP."""
    env = native_environment(session)
    env.update(LEDGER_AUTH_ONLY="2" if recover else "1", CONTENT_LENGTH="0")
    result = subprocess.run([BIN_PATH], input=b"", capture_output=True, env=env,
                            cwd=WORK_DIR, timeout=SUBPROCESS_TIMEOUT)
    if result.returncode or len(result.stdout) > 1024:
        abort(503, "Autentificarea registrului este indisponibila.")
    match = re.search(rb"^Status: (204|401|503)\b", result.stdout)
    if not match:
        abort(503)
    status = int(match[1])
    if status != 204:
        abort(status)
    reserved = re.search(rb"X-Ledger-Reserved: ([0-9]{6})", result.stdout)
    if not reserved:
        abort(503)
    return int(reserved[1])


def cgi_response(stdout, current_csrf, form):
    if b"\x1eLEDGER_STORAGE_ERROR" in stdout:
        abort(503, "Datele nu pot fi accesate in siguranta.")
    raw = stdout.decode("utf-8", errors="replace")
    separator = next((sep for sep in ("\r\n\r\n", "\n\n", "\n \n") if sep in raw), None)
    if not separator:
        abort(502, "Raspuns CGI invalid.")
    head, body = raw.split(separator, 1)
    response = Response(body, content_type="text/html; charset=utf-8")
    result = ""
    for line in head.replace("\r\n", "\n").split("\n"):
        if ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        if key.lower() == "x-ledger-result":
            result = value
        elif key.lower() in {"content-type", "content-disposition"}:
            response.headers[key] = value
        elif key.lower() == "status":
            if not re.fullmatch(r"[1-5][0-9]{2}(?: .*)?", value):
                abort(502)
            response.status_code = int(value[:3])
        elif key.lower() == "set-cookie" and value.startswith("session="):
            response.headers.add("Set-Cookie", value.replace("session=", SESSION_COOKIE + "=", 1))
            new_session = value.split(";", 1)[0].split("=", 1)[1]
            response.set_data(response.get_data(as_text=True).replace(
                current_csrf, csrf_token(app.config["SECRET_KEY"], new_session)))
    if response.status_code < 400 and request.method == "POST" and result in {"added", "updated", "deleted", "login", "logout", "budgeted", "unbudget", "rulesave", "rulemode", "booked", "already", "ruledupe"}:
        target = {key: value for key, value in request.args.items()
                  if key in QUERY_LIMITS and key not in {"edit", "export", "notice"}}
        if result in {"added", "updated", "deleted"}:
            target["notice"] = result
        if result in {"budgeted", "unbudget"}:
            target = {"view": "BUDGET", "month": form["month"], "notice": result}
        if result in {"rulesave", "rulemode", "booked", "already", "ruledupe"}:
            target = {"view": "RECURRING", "notice": result}
        if result in {"login", "logout"}:
            target = {}
        response.status_code = 303
        response.headers["Location"] = "/" + ("?" + urlencode(target) if target else "")
        response.set_data("")
    if response.status_code == 200 and response.mimetype == "text/html":
        response = account_fields(response, form)
    return response


def account_fields(response, form):
    body = response.get_data(as_text=True)
    if "<!--LEDGER_ACCOUNT_" not in body:
        return response
    from html import escape
    with connect(WORK_DIR) as db:
        db.row_factory = sqlite3.Row
        choices = db.execute("SELECT id,name,active FROM accounts ORDER BY active DESC,id").fetchall()
        selected = int(form.get("account") or request.args.get("account") or 1)
        if request.args.get("edit"):
            record = db.execute("SELECT account_id FROM ledger WHERE id=?", (int(request.args["edit"]),)).fetchone()
            if record:
                selected = record[0]
        entry = render_template("_account_select.html", choices=choices, selected=selected, mode="entry")
        filter_field = render_template("_account_select.html", choices=choices, selected=int(request.args.get("account") or 0), mode="filter")
        body = body.replace("<!--LEDGER_ACCOUNT_SELECT-->", entry).replace("<!--LEDGER_ACCOUNT_FILTER-->", filter_field)
        ids = {int(value) for value in re.findall(r"<!--LEDGER_ACCOUNT_LABEL:([0-9]{6})-->", body)}
        labels = {}
        if ids:
            placeholders = ",".join("?" for _ in ids)
            labels = {row[0]: row[1] for row in db.execute("SELECT l.id,a.name FROM ledger l JOIN accounts a ON a.id=l.account_id WHERE l.id IN ("+placeholders+")", tuple(ids))}
        body = re.sub(r"<!--LEDGER_ACCOUNT_LABEL:([0-9]{6})-->", lambda match: "<small class='transaction-account'>"+escape(labels.get(int(match[1]), ""))+"</small>", body)
    response.set_data(body)
    return response


from imports import create_import_blueprint
app.register_blueprint(create_import_blueprint(native_authorize, configured, WORK_DIR))


from finance import create_finance_blueprint
app.register_blueprint(create_finance_blueprint(native_authorize, configured, WORK_DIR))


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
