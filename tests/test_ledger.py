"""Teste end-to-end: Flask -> subprocess -> binar COBOL -> ISAM.

Binarul este compilat intr-un director temporar, deci datele reale
din data/ nu sunt atinse niciodata de teste.
"""

import importlib
import os
import re
import subprocess
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

USER = "tester"
PASS = "secret123"


@pytest.fixture(scope="session")
def workdir(tmp_path_factory):
    wd = tmp_path_factory.mktemp("ledger")
    (wd / "data").mkdir()
    subprocess.run(
        ["cobc", "-x", "-free", os.path.join(ROOT, "ledger.cbl"),
         os.path.join(ROOT, "sha256.cbl"),
         "-o", str(wd / "ledger.cgi")],
        check=True,
    )
    return wd


@pytest.fixture()
def client(workdir, monkeypatch):
    monkeypatch.setenv("LEDGER_BIN", str(workdir / "ledger.cgi"))
    monkeypatch.setenv("LEDGER_DIR", str(workdir))
    monkeypatch.setenv("LEDGER_USER", USER)
    monkeypatch.setenv("LEDGER_PASS", PASS)
    monkeypatch.delenv("LEDGER_PASS_HASH", raising=False)
    monkeypatch.delenv("LEDGER_SESSION_TTL", raising=False)
    for name in ("ledger.dat", "sessions.dat", "lockout.dat",
                 "audit.log"):
        p = workdir / "data" / name
        if p.exists():
            p.unlink()

    import app as app_module
    importlib.reload(app_module)
    app_module.app.config["TESTING"] = True
    # fara cookie jar: jar-ul ar suprascrie header-ele Cookie explicite,
    # iar testele de multi-sesiune au nevoie de control per-request
    return app_module.app.test_client(use_cookies=False)


def login(client, user=USER, password=PASS):
    resp = client.post("/", data={"cmd": "login", "user": user,
                                  "pass": password})
    set_cookie = resp.headers.get("Set-Cookie", "")
    m = re.search(r"session=([0-9a-f]{32})", set_cookie)
    return resp, ({"Cookie": f"session={m.group(1)}"} if m else {})


def add(client, headers, date, cat, desc, amount):
    return client.post("/", data={"cmd": "add", "date": date, "cat": cat,
                                  "desc": desc, "amount": amount},
                       headers=headers)


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_login_page_when_logged_out(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert b"<h2>Login</h2>" in resp.data


def test_bad_login_rejected(client):
    resp, headers = login(client, password="gresit")
    assert not headers
    assert "User sau parola incorecte".encode() in resp.data


def test_actions_require_auth(client):
    resp = add(client, {}, "2026-07-01", "Mancare", "neautorizat", "-5.00")
    assert b"<h2>Login</h2>" in resp.data
    _, headers = login(client)
    resp = client.get("/", headers=headers)
    assert b"neautorizat" not in resp.data


def test_full_crud_flow(client):
    _, headers = login(client)
    assert headers, "login-ul trebuie sa emita cookie de sesiune"

    resp = add(client, headers, "2026-07-01", "Venituri", "Salariu", "5000")
    assert b"Salariu" in resp.data

    resp = add(client, headers, "2026-07-02", "Mancare", "Piata", "-150.25")
    assert b"-150.25" in resp.data
    assert b"4,849.75" in resp.data  # total

    # editare: formular precompletat
    resp = client.get("/?edit=000002", headers=headers)
    assert b"Editeaza tranzactia #000002" in resp.data
    assert b"value='-150.25'" in resp.data

    # update
    resp = client.post("/", data={"cmd": "update", "id": "000002",
                                  "date": "2026-07-03", "cat": "Hobby",
                                  "desc": "Carti", "amount": "-100"},
                       headers=headers)
    assert b"Carti" in resp.data
    assert b"4,900.00" in resp.data

    # delete
    resp = client.post("/", data={"cmd": "del", "id": "000002"},
                       headers=headers)
    assert b"Carti" not in resp.data
    assert b"5,000.00" in resp.data


def test_filters_and_csv_export(client):
    _, headers = login(client)
    add(client, headers, "2026-06-15", "Venituri", "Salariu", "3000")
    add(client, headers, "2026-07-01", "Mancare", "Cina, oras \"X\"", "-80")

    resp = client.get("/?filter=Mancare", headers=headers)
    assert b"Total (1 tranzactii)" in resp.data

    resp = client.get("/?from=2026-07-01&to=2026-07-31", headers=headers)
    assert b"Salariu" not in resp.data

    resp = client.get("/?export=csv", headers=headers)
    assert resp.content_type.startswith("text/csv")
    assert b'000002,2026-07-01,Mancare,"Cina, oras ""X""",-80.00' in resp.data


def test_csv_requires_auth(client):
    resp = client.get("/?export=csv")
    assert not resp.content_type.startswith("text/csv")
    assert b"<h2>Login</h2>" in resp.data


def test_monthly_report(client):
    _, headers = login(client)
    add(client, headers, "2026-06-15", "Venituri", "Salariu", "3000")
    add(client, headers, "2026-06-20", "Mancare", "Piata", "-500")
    add(client, headers, "2026-07-01", "Venituri", "Salariu", "3100")

    resp = client.get("/?view=REPORT", headers=headers)
    assert b"Raport lunar" in resp.data
    assert b"2026-06" in resp.data
    assert b"2026-07" in resp.data
    assert b"bar-in" in resp.data
    assert b"2,500.00" in resp.data  # net iunie


def test_audit_log(client):
    login(client, password="gresit")
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Hobby", "Sah", "-20")

    resp = client.get("/?view=AUDIT", headers=headers)
    assert b"LOGIN-FAIL" in resp.data
    assert b"LOGIN" in resp.data
    assert b"ADD" in resp.data


def test_xss_is_escaped(client):
    _, headers = login(client)
    resp = add(client, headers, "2026-07-01", "Hobby",
               "<script>alert(1)</script>", "-1")
    assert b"<script>alert(1)</script>" not in resp.data
    assert b"&lt;script&gt;" in resp.data


def test_invalid_inputs_rejected(client):
    _, headers = login(client)
    resp = add(client, headers, "2026-13-99", "Hobby", "x", "-1")
    assert b"Data invalida" in resp.data
    resp = add(client, headers, "2026-07-01", "NuExista", "x", "-1")
    assert b"Categorie invalida" in resp.data
    resp = add(client, headers, "2026-07-01", "Hobby", "x", "1.2.3")
    assert b"Suma invalida" in resp.data
    resp = add(client, headers, "2026-07-01", "Hobby", "   ", "-1")
    assert b"Descrierea este obligatorie" in resp.data


def test_session_expiry(client, monkeypatch):
    import time
    monkeypatch.setenv("LEDGER_SESSION_TTL", "1")
    _, headers = login(client)
    resp = client.get("/", headers=headers)
    assert b"<h2>Login</h2>" not in resp.data
    time.sleep(2.1)
    resp = client.get("/", headers=headers)
    assert b"<h2>Login</h2>" in resp.data


def test_logout_invalidates_session(client):
    _, headers = login(client)
    resp = client.post("/", data={"cmd": "logout"}, headers=headers)
    assert "Max-Age=0" in resp.headers.get("Set-Cookie", "")
    resp = client.get("/", headers=headers)
    assert b"<h2>Login</h2>" in resp.data


def test_multi_session(client):
    _, h1 = login(client)
    _, h2 = login(client)
    assert h1 != h2
    # ambele sesiuni sunt valide simultan
    assert b"<h2>Login</h2>" not in client.get("/", headers=h1).data
    assert b"<h2>Login</h2>" not in client.get("/", headers=h2).data
    # logout pe prima nu o invalideaza pe a doua
    client.post("/", data={"cmd": "logout"}, headers=h1)
    assert b"<h2>Login</h2>" in client.get("/", headers=h1).data
    assert b"<h2>Login</h2>" not in client.get("/", headers=h2).data


def test_password_hash_login(client, monkeypatch):
    import hashlib
    monkeypatch.setenv("LEDGER_PASS_HASH",
                       hashlib.sha256(PASS.encode()).hexdigest())
    monkeypatch.setenv("LEDGER_PASS", "alta-parola-care-nu-conteaza")
    resp, headers = login(client)  # parola reala, verificata prin hash
    assert headers, "login prin hash SHA-256 trebuie sa functioneze"
    resp, headers = login(client, password="alta-parola-care-nu-conteaza")
    assert not headers, "parola in clar nu mai e acceptata cand exista hash"


def test_brute_force_lockout(client):
    ip = {"X-Real-IP": "203.0.113.7"}
    for _ in range(5):
        client.post("/", data={"cmd": "login", "user": USER,
                               "pass": "gresit"}, headers=ip)
    # a 6-a incercare e blocata chiar si cu parola corecta
    resp = client.post("/", data={"cmd": "login", "user": USER,
                                  "pass": PASS}, headers=ip)
    assert "Prea multe incercari".encode() in resp.data
    assert "session=" not in resp.headers.get("Set-Cookie", "")
    # alt IP nu e afectat
    resp, headers = login(client)
    assert headers


def test_pagination(client):
    _, headers = login(client)
    for i in range(1, 26):
        add(client, headers, f"2026-07-{i:02d}", "Hobby", f"tx{i:02d}", "-1")

    resp = client.get("/", headers=headers)
    assert resp.data.count(b"<tr><td>#") == 20
    assert b"Pagina 1 din 2" in resp.data
    assert b"Total (25 tranzactii)" in resp.data  # totalul ramane global
    assert b"-25.00" in resp.data

    resp = client.get("/?page=2", headers=headers)
    assert resp.data.count(b"<tr><td>#") == 5
    assert b"Pagina 2 din 2" in resp.data
    assert b"tx25" in resp.data


def test_search(client):
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Mancare", "Piata Obor", "-50")
    add(client, headers, "2026-07-02", "Mancare", "Kaufland", "-80")

    resp = client.get("/?q=PIATA", headers=headers)  # case-insensitive
    assert b"Piata Obor" in resp.data
    assert b"Kaufland" not in resp.data
    assert b"Total (1 tranzactii)" in resp.data
