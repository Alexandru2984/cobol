"""HTTP trust boundary for the fixed-width COBOL CGI protocol."""
from contextlib import contextmanager
from datetime import date
import fcntl
import hashlib
import hmac
import ipaddress
import os
from pathlib import Path
import re
import time
from urllib.parse import parse_qsl, urlsplit

from flask import abort, request
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

SESSION_COOKIE = "__Host-ledger-session"
CATEGORIES = {"Venituri", "Locuinta", "Mancare", "Hobby", "Utilitati"}
FORM_LIMITS = {"cmd": 20, "user": 40, "pass": 40, "date": 10, "cat": 15,
               "desc": 30, "amount": 20, "id": 6, "csrf_token": 300, "month": 7, "cycle": 7, "due": 10, "create_key": 32}
QUERY_LIMITS = {"filter": 15, "sort": 10, "from": 10, "to": 10,
                "view": 10, "export": 3, "edit": 6, "q": 30, "page": 5, "notice": 8,
                "kind": 7, "month": 7, "rule": 6}


def parse_fields(raw, limits):
    """Reject truncation, ambiguity and control bytes before invoking COBOL."""
    try:
        text = raw.decode("ascii")
        if re.search(r"%(?![0-9a-fA-F]{2})", text):
            abort(400, "Codificare URL invalida.")
        pairs = parse_qsl(text, keep_blank_values=True, strict_parsing=True,
                          encoding="utf-8", errors="strict", max_num_fields=20)
    except (ValueError, UnicodeError):
        abort(400, "Cerere invalida.")
    fields = {}
    for key, value in pairs:
        if key not in limits or key in fields:
            abort(400, "Camp necunoscut sau duplicat.")
        if len(value.encode("utf-8")) > limits[key]:
            abort(400, "Camp prea lung.")
        if any(ord(ch) < 32 or ord(ch) == 127 for ch in value):
            abort(400, "Caractere de control nepermise.")
        fields[key] = value
    for key in ("id", "edit", "page", "rule"):
        if fields.get(key) and not re.fullmatch(r"[0-9]+", fields[key]):
            abort(400, "ID sau pagina invalida.")
    if "month" in fields:
        try:
            if not re.fullmatch(r"[0-9]{4}-[0-9]{2}", fields["month"]):
                raise ValueError
            date.fromisoformat(fields["month"] + "-01")
        except ValueError:
            abort(400, "Luna invalida.")
    if "create_key" in fields and not re.fullmatch(r"[0-9a-f]{32}", fields["create_key"]):
        abort(400, "Cheie de cerere invalida.")
    return fields


def session_token():
    values = request.cookies.getlist(SESSION_COOKIE)
    if len(values) > 1:
        abort(400, "Cookie duplicat.")
    value = values[0] if values else ""
    return value if re.fullmatch(r"[0-9a-f]{32}", value) else ""


def csrf_token(secret, session):
    binding = hashlib.sha256(session.encode()).hexdigest()
    return URLSafeTimedSerializer(secret, salt="ledger-csrf-v1").dumps(binding)


def verify_csrf(secret, session, token, public_origin):
    if request.headers.get("Sec-Fetch-Site") in {"cross-site", "same-site"}:
        abort(403, "Cerere din alta origine refuzata.")
    origin = request.headers.get("Origin")
    referer = request.headers.get("Referer")
    if origin and origin != public_origin:
        abort(403, "Origine invalida.")
    if not origin and referer:
        parsed = urlsplit(referer)
        if f"{parsed.scheme}://{parsed.netloc}" != public_origin:
            abort(403, "Origine invalida.")
    try:
        binding = URLSafeTimedSerializer(secret, salt="ledger-csrf-v1").loads(
            token, max_age=28800)
        expected = hashlib.sha256(session.encode()).hexdigest()
        if not isinstance(binding, str) or not hmac.compare_digest(binding, expected):
            abort(403, "Token de securitate invalid. Reincarca pagina.")
    except (BadSignature, SignatureExpired):
        abort(403, "Token expirat sau absent. Reincarca pagina.")


def client_ip(trusted_proxies):
    peer = request.remote_addr or "127.0.0.1"
    try:
        addr = ipaddress.ip_address(peer)
        if any(addr in ipaddress.ip_network(net) for net in trusted_proxies):
            return str(ipaddress.ip_address(request.headers.get("X-Real-IP", peer)))
        return str(addr)
    except ValueError:
        return peer


@contextmanager
def ledger_lock(work_dir, timeout=2):
    path = Path(work_dir) / "data" / ".ledger.lock"
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("ledger busy") from None
                time.sleep(0.02)
        yield
    finally:
        os.close(descriptor)
