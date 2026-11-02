"""Flask/WSGI bridge for the COBOL ledger, with a strict HTTP trust boundary."""
import logging
import os
from pathlib import Path
import re
import secrets
import subprocess
from urllib.parse import urlencode

from flask import Flask, Response, abort, g, jsonify, request
from werkzeug.security import check_password_hash

from security import (FORM_LIMITS, QUERY_LIMITS, SESSION_COOKIE, client_ip,
                      csrf_token, ledger_lock, parse_fields, session_token,
                      verify_csrf)

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
        "Referrer-Policy": "same-origin", "X-Robots-Tag": "noindex, nofollow",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
        "Content-Security-Policy": "default-src 'self'; base-uri 'none'; "
            "object-src 'none'; frame-ancestors 'none'; form-action 'self'; "
            "script-src 'self' https://analytics.micutu.com https://static.cloudflareinsights.com; "
            "style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; "
            "connect-src 'self' https://analytics.micutu.com https://cloudflareinsights.com",
        "X-Request-ID": getattr(g, "request_id", ""),
    })
    response.vary.add("Cookie")
    return response


@app.route("/health")
def health():
    checks = {
        "binary": os.access(BIN_PATH, os.X_OK),
        "data_dir": os.path.isdir(os.path.join(WORK_DIR, "data")),
        "configuration": configured(),
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
        if form.get("cmd") not in {"login", "logout", "add", "update", "del"}:
            abort(400, "Comanda invalida.")
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
    })
    input_data = urlencode(form).encode("ascii") if request.method == "POST" else None
    env["CONTENT_LENGTH"] = str(len(input_data or b""))
    try:
        with ledger_lock(WORK_DIR):
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
    except TimeoutError:
        response = Response("Registrul este ocupat. Reincearca.", status=503)
        response.headers["Retry-After"] = "2"
        return response
    except OSError:
        logger.exception("backend_unavailable request=%s", g.request_id)
        abort(502, "Backend indisponibil.")
    if process.returncode != 0 or len(stdout) > MAX_OUTPUT:
        logger.error("backend_failed request=%s exit=%s", g.request_id, process.returncode)
        abort(502, "Backend-ul a esuat.")
    if stderr:
        logger.warning("backend_stderr request=%s bytes=%s", g.request_id, len(stderr))
    return cgi_response(stdout, env["LEDGER_CSRF_TOKEN"])


def cgi_response(stdout, current_csrf):
    raw = stdout.decode("utf-8", errors="replace")
    separator = next((sep for sep in ("\r\n\r\n", "\n\n", "\n \n") if sep in raw), None)
    if not separator:
        abort(502, "Raspuns CGI invalid.")
    head, body = raw.split(separator, 1)
    response = Response(body, content_type="text/html; charset=utf-8")
    for line in head.replace("\r\n", "\n").split("\n"):
        if ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        if key.lower() in {"content-type", "content-disposition"}:
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
    return response


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
