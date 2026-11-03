"""Teste end-to-end: Flask -> subprocess -> binar COBOL -> ISAM.

Binarul este compilat intr-un director temporar, deci datele reale
din data/ nu sunt atinse niciodata de teste.
"""

import importlib
import os
import re
import shutil
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
    tested_binary = os.environ.get("LEDGER_TEST_BIN")
    if tested_binary:
        shutil.copy2(tested_binary, wd / "ledger.cgi")
    else:
        subprocess.run(
            ["cobc", "-x", "-free", "-I", ROOT, os.path.join(ROOT, "ledger.cbl"),
             os.path.join(ROOT, "sha256.cbl"),
             os.path.join(ROOT, "persistence/sqlite_store.c"), "-lsqlite3",
             "-o", str(wd / "ledger.cgi")],
            check=True,
        )
    return wd


@pytest.fixture()
def client(workdir, monkeypatch):
    monkeypatch.setenv("LEDGER_BIN", str(workdir / "ledger.cgi"))
    monkeypatch.setenv("LEDGER_DIR", str(workdir))
    monkeypatch.setenv("LEDGER_CSRF_SECRET", "test-csrf-secret-with-at-least-32-bytes")
    monkeypatch.setenv("LEDGER_USER", USER)
    monkeypatch.delenv("LEDGER_PASSWORD_HASH", raising=False)
    monkeypatch.setenv("LEDGER_PASS", PASS)
    monkeypatch.delenv("LEDGER_PASS_HASH", raising=False)
    monkeypatch.delenv("LEDGER_SESSION_TTL", raising=False)
    for name in ("ledger.dat", "ledger.dat.1", "ledger.sqlite3", "ledger.sqlite3-journal", "sessions.dat", "lockout.dat",
                 "audit.log", "budgets.dat", "budgets.dat.1", "recurring.dat", "recurring.dat.1", "occurrences.dat",
                 "occurrences.dat.1", "occurrences.dat.2"):
        p = workdir / "data" / name
        if p.exists():
            p.unlink()

    import app as app_module
    importlib.reload(app_module)
    app_module.app.config["TESTING"] = True
    # fara cookie jar: jar-ul ar suprascrie header-ele Cookie explicite,
    # iar testele de multi-sesiune au nevoie de control per-request
    from flask.testing import FlaskClient

    class SecureClient(FlaskClient):
        def post(self, *args, **kwargs):
            if kwargs.pop("csrf", True):
                fields = kwargs.get("data", {})
                creating_rule = isinstance(fields, dict) and fields.get("cmd") == "rule-save" and not fields.get("id")
                page = self.get("/?view=RECURRING" if creating_rule else "/", headers=kwargs.get("headers", {}))
                if creating_rule and "create_key" not in fields:
                    key = re.search(rb"name='create_key' value='([^']+)'", page.data)
                    if key:
                        kwargs["data"] = {**fields, "create_key": key[1].decode()}
                match = re.search(rb"name='csrf_token' value='([^']+)'", page.data)
                if match and isinstance(kwargs.get("data"), dict):
                    kwargs["data"] = {**kwargs["data"], "csrf_token": match[1].decode()}
            response = super().post(*args, **kwargs)
            if response.status_code == 303:
                headers = dict(kwargs.get("headers", {}))
                for cookie in response.headers.getlist("Set-Cookie"):
                    if cookie.startswith("__Host-ledger-session="):
                        headers["Cookie"] = cookie.split(";", 1)[0]
                page = self.get(response.headers["Location"], headers=headers)
                for cookie in response.headers.getlist("Set-Cookie"):
                    page.headers.add("Set-Cookie", cookie)
                return page
            return response

    app_module.app.test_client_class = SecureClient
    return app_module.app.test_client(use_cookies=False)


def login(client, user=USER, password=PASS):
    resp = client.post("/", data={"cmd": "login", "user": user,
                                  "pass": password})
    set_cookie = resp.headers.get("Set-Cookie", "")
    m = re.search(r"__Host-ledger-session=([0-9a-f]{32})", set_cookie)
    return resp, ({"Cookie": f"__Host-ledger-session={m.group(1)}"} if m else {})


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
    assert resp.data.count(b"data-transaction=") == 20
    assert b"Pagina 1 din 2" in resp.data
    assert b"Total (25 tranzactii)" in resp.data  # totalul ramane global
    assert b"-25.00" in resp.data

    resp = client.get("/?page=2", headers=headers)
    assert resp.data.count(b"data-transaction=") == 5
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


def test_csrf_required_for_login_and_mutation(client):
    assert client.post("/", data={"cmd": "login", "user": USER, "pass": PASS},
                       csrf=False).status_code == 403
    _, headers = login(client)
    assert add(client, headers, "2026-07-01", "Hobby", "valid", "1").status_code == 200
    assert client.post("/", data={"cmd": "del", "id": "000001"},
                       headers=headers, csrf=False).status_code == 403
    page = client.get("/", headers=headers)
    token = re.search(rb"name='csrf_token' value='([^']+)'", page.data)[1].decode()
    assert client.post("/", data={"cmd": "del", "id": "000001", "csrf_token": token},
                       headers={**headers, "Origin": "https://evil.micutu.com"},
                       csrf=False).status_code == 403
    # A valid token for one session cannot authorize another session.
    _, other = login(client)
    assert client.post("/", data={"cmd": "logout", "csrf_token": token},
                       headers=other, csrf=False).status_code == 403


def test_cookie_and_cache_headers(client):
    resp, _ = login(client)
    cookie = resp.headers["Set-Cookie"]
    for flag in ("__Host-ledger-session=", "Secure", "HttpOnly", "SameSite=Strict", "Path=/"):
        assert flag in cookie
    assert "Domain=" not in cookie
    assert "no-store" in resp.headers["Cache-Control"]
    assert "'unsafe-inline'" not in resp.headers["Content-Security-Policy"].split("script-src")[1].split(";")[0]
    assert client.get("/", headers={"Host": "attacker.example"}).status_code == 400


def test_missing_credentials_fail_closed(client, monkeypatch):
    monkeypatch.delenv("LEDGER_PASS")
    assert client.get("/").status_code == 503
    assert client.get("/health").status_code == 503


def test_scrypt_credentials(client, monkeypatch):
    from werkzeug.security import generate_password_hash
    monkeypatch.setenv("LEDGER_PASSWORD_HASH", generate_password_hash(PASS, method="scrypt:131072:8:1"))
    assert login(client)[1]
    assert not login(client, password="wrong")[1]
    monkeypatch.setenv("LEDGER_PASSWORD_HASH", "invalid")
    assert client.get("/").status_code == 503  # no downgrade to the legacy password


@pytest.mark.parametrize("amount", [".", "+", "-", "1.234", "10000000.01", "-10000000", "99999999999999999999", "1 2"])
def test_amounts_rejected_before_truncation(client, amount):
    _, headers = login(client)
    resp = add(client, headers, "2026-07-01", "Hobby", "invalid amount", amount)
    assert b"Suma invalida" in resp.data
    assert b"Total (0 tranzactii)" in resp.data


@pytest.mark.parametrize("date", ["2026-02-29", "2026-04-31", "0000-01-01"])
def test_real_calendar_validation(client, date):
    _, headers = login(client)
    assert b"Data invalida" in add(client, headers, date, "Hobby", "invalid date", "1").data
    assert b"leap year" in add(client, headers, "2024-02-29", "Hobby", "leap year", "1").data


@pytest.mark.parametrize("query", ["q=a&q=b", "q=%00", "q=%0a", "q=%GG", "edit=1000001", "page=abc"])
def test_ambiguous_query_rejected(client, query):
    assert client.get("/?" + query).status_code == 400


def test_request_limits(client):
    assert client.get("/?q=" + "x" * 1030).status_code == 414
    assert client.post("/", data=b"x" * 4097, content_type="application/x-www-form-urlencoded",
                       csrf=False).status_code == 413
    assert client.post("/", json={"cmd": "add"}, csrf=False).status_code == 415


def test_csv_formula_neutralized(client):
    _, headers = login(client)
    for desc in ("=1+1", "+1+1", "-1+1", "@SUM(1)"):
        add(client, headers, "2026-07-01", "Hobby", desc, "1")
    exported = client.get("/?export=csv", headers=headers).data
    assert b'"\'=1+1"' in exported
    assert b'"\'@SUM(1)"' in exported


def test_proxy_headers_only_from_trusted_peers(client):
    # Arbitrary internet peers cannot pick the audit/lockout address.
    from security import client_ip
    import app
    with app.app.test_request_context("/", headers={"X-Real-IP": "203.0.113.99"},
                                     environ_base={"REMOTE_ADDR": "198.51.100.4"}):
        assert client_ip(["127.0.0.1/32"]) == "198.51.100.4"


def test_query_order_does_not_skip_filters(client):
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Hobby", "yes", "1")
    add(client, headers, "2026-07-01", "Mancare", "no", "2")
    page = client.get("/?page=1&filter=Hobby&q=yes", headers=headers)
    assert b"Total (1 tranzactii)" in page.data


def test_parallel_writes_preserve_all_rows(client):
    from concurrent.futures import ThreadPoolExecutor
    import app
    _, headers = login(client)

    def write(index):
        with app.app.test_client(use_cookies=False) as worker:
            response = add(worker, headers, "2026-07-01", "Hobby", f"parallel{index}", "1")
            assert response.status_code == 200

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(write, range(8)))
    assert b"Total (8 tranzactii)" in client.get("/", headers=headers).data


def test_subprocess_timeout_is_reaped(client, monkeypatch, tmp_path):
    import app
    executable = tmp_path / "slow.cgi"
    executable.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(3)\n")
    executable.chmod(0o700)
    monkeypatch.setattr(app, "BIN_PATH", str(executable))
    monkeypatch.setattr(app, "SUBPROCESS_TIMEOUT", 0.02)
    real_popen = subprocess.Popen
    children = []

    def capture(*args, **kwargs):
        process = real_popen(*args, **kwargs)
        children.append(process)
        return process

    monkeypatch.setattr(subprocess, "Popen", capture)
    assert client.get("/").status_code == 504
    assert children[0].returncode is not None
    with pytest.raises(ChildProcessError):
        os.waitpid(children[0].pid, os.WNOHANG)


def test_login_response_has_token_bound_to_new_session(client):
    response, headers = login(client)
    token = re.search(rb"name='csrf_token' value='([^']+)'", response.data)[1].decode()
    response = client.post("/", data={"cmd": "add", "date": "2026-07-01", "cat": "Hobby",
                                      "desc": "first action", "amount": "1", "csrf_token": token},
                           headers=headers, csrf=False)
    assert response.status_code == 200
    assert b"first action" in response.data


def test_financial_metrics_and_type_filters(client):
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Venituri", "salary", "1000")
    add(client, headers, "2026-07-02", "Mancare", "groceries", "-250")
    page = client.get("/", headers=headers)
    assert b"75.0%" in page.data
    assert b"Sold net" in page.data
    expenses = client.get("/?kind=EXPENSE", headers=headers)
    assert b"groceries" in expenses.data and b"salary" not in expenses.data
    assert b"Total (1 tranzactii)" in expenses.data
    csv = client.get("/?kind=EXPENSE&export=csv", headers=headers)
    assert b"groceries" in csv.data and b"salary" not in csv.data


def test_descending_sort_and_page_clamp(client):
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Hobby", "older", "1")
    add(client, headers, "2026-07-03", "Hobby", "newer", "1")
    response = client.get("/?sort=DATE_DESC&page=50000", headers=headers)
    assert response.data.index(b">newer") < response.data.index(b">older")
    assert b"Total (2 tranzactii)" in response.data


def test_report_respects_filters(client):
    _, headers = login(client)
    add(client, headers, "2026-06-01", "Venituri", "salary", "1000")
    add(client, headers, "2026-07-01", "Hobby", "books", "-100")
    response = client.get("/?view=REPORT&from=2026-07-01&kind=EXPENSE", headers=headers)
    assert b"2026-06</b>" not in response.data
    assert b"2026-07</b>" in response.data
    assert b"-100.00" in response.data


def test_aggregates_exceed_old_capacity(client):
    _, headers = login(client)
    for i in range(101):
        add(client, headers, "2026-07-01", "Venituri", f"large{i}", "9999999.99")
    page = client.get("/", headers=headers)
    assert b"1,009,999,998.99" in page.data
    report = client.get("/?view=REPORT", headers=headers)
    assert b"1,009,999,998.99" in report.data


def test_report_does_not_mix_month_121_into_month_120(client):
    _, headers = login(client)
    for i in range(121):
        year, month = 2010 + i // 12, i % 12 + 1
        add(client, headers, f"{year}-{month:02d}-01", "Hobby", f"month{i}", "-1")
    report = client.get("/?view=REPORT", headers=headers)
    assert b"2019-12</b>" in report.data
    assert b"2020-01</b>" in report.data
    assert b"-2.00" not in report.data


def test_raw_success_redirect_prevents_refresh_resubmission(client):
    import app
    # Bypass the convenience client that follows redirects for legacy tests.
    from flask.testing import FlaskClient
    raw = FlaskClient(app.app, use_cookies=False)
    response = raw.get("/")
    token = re.search(rb"name='csrf_token' value='([^']+)'", response.data)[1].decode()
    response = raw.post("/", data={"cmd": "login", "user": USER, "pass": PASS, "csrf_token": token})
    assert response.status_code == 303
    assert response.headers["Location"] == "/"


def test_backup_restore_and_tampering_detection(client, workdir, tmp_path):
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Hobby", "restore proof", "-12.34")
    destination = tmp_path / "snapshots"
    env = {**os.environ, "LEDGER_APP_DIR": str(workdir), "LEDGER_BACKUP_DIR": str(destination)}
    subprocess.run([os.path.join(ROOT, "backup.sh")], env=env, check=True, capture_output=True)
    archive = next(destination.glob("*.tar.gz"))
    verifier = [sys.executable, os.path.join(ROOT, "ops", "verify-backup.py"), str(archive)]
    check = subprocess.run(verifier, capture_output=True, check=True)
    assert b"RESTORE_CHECK_OK" in check.stdout
    # A corrupted archive is rejected before extraction.
    with archive.open("ab") as stream:
        stream.write(b"tampered")
    assert subprocess.run(verifier, capture_output=True).returncode != 0
    assert b"restore proof" in client.get("/", headers=headers).data


def save_budget(client, headers, month="2026-07", category="Mancare", amount="100"):
    return client.post("/?view=BUDGET&month=" + month, headers=headers,
                       data={"cmd": "budget-save", "month": month, "cat": category, "amount": amount})


def test_budget_save_update_delete_does_not_modify_transactions(client):
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Mancare", "groceries", "-80")
    before = client.get("/?export=csv", headers=headers).data
    response = save_budget(client, headers)
    assert response.status_code == 200
    assert b"Buget lunar salvat" in response.data
    assert b"Aproape de limita" in response.data
    assert b"value='100.00'" in response.data
    response = save_budget(client, headers, amount="50")
    assert b"Limita depasita" in response.data
    assert b"-30.00" in response.data
    response = client.post("/?view=BUDGET&month=2026-07", headers=headers,
        data={"cmd": "budget-del", "month": "2026-07", "cat": "Mancare"})
    assert b"Limita de buget eliminata" in response.data
    assert b"value='50.00'" not in response.data
    assert before == client.get("/?export=csv", headers=headers).data
    assert b"BUDGET-DEL" in client.get("/?view=AUDIT", headers=headers).data


def test_budgets_separate_months_and_do_not_net_income(client):
    _, headers = login(client)
    add(client, headers, "2026-07-01", "Mancare", "expense", "-80")
    add(client, headers, "2026-07-02", "Mancare", "positive adjustment", "20")
    add(client, headers, "2026-06-30", "Mancare", "other month", "-300")
    save_budget(client, headers, month="2026-06", amount="500")
    response = save_budget(client, headers, month="2026-07", amount="100")
    card = re.search(rb"data-budget='Mancare'([\s\S]+?)</article>", response.data)[1]
    assert b"80.00" in card and b"60.00" not in card and b"300.00" not in card
    assert b"value='100.00'" in card
    june = client.get("/?view=BUDGET&month=2026-06", headers=headers)
    assert b"value='500.00'" in june.data
    august = client.get("/?view=BUDGET&month=2026-08", headers=headers)
    assert b"value='100.00'" not in august.data


@pytest.mark.parametrize("amount", ["0", "-1", "10000000", "1.234", "."])
def test_budget_invalid_limits_rejected(client, amount):
    _, headers = login(client)
    assert b"Buget invalid" in save_budget(client, headers, amount=amount).data
    page = client.get("/?view=BUDGET&month=2026-07", headers=headers)
    assert b"data-delete='budget'" not in page.data


@pytest.mark.parametrize("month", ["2026-13", "0000-01", "26-01", "2026-1", "2026-00"])
def test_budget_month_validation(client, month):
    assert client.get("/?view=BUDGET&month=" + month).status_code == 400


def test_budget_auth_and_csrf(client):
    response = save_budget(client, {}, amount="50")
    assert b"<h2>Login</h2>" in response.data
    _, headers = login(client)
    assert b"data-delete='budget'" not in client.get("/?view=BUDGET&month=2026-07", headers=headers).data
    response = client.post("/", headers=headers, csrf=False,
        data={"cmd": "budget-save", "month": "2026-07", "cat": "Mancare", "amount": "100"})
    assert response.status_code == 403


def test_budget_database_in_verified_snapshot(client, workdir, tmp_path):
    import tarfile
    _, headers = login(client)
    save_budget(client, headers)
    destination = tmp_path / "budgets-backup"
    subprocess.run([os.path.join(ROOT, "backup.sh")], check=True, capture_output=True,
        env={**os.environ,"LEDGER_APP_DIR":str(workdir),"LEDGER_BACKUP_DIR":str(destination)})
    archive = next(destination.glob("*.tar.gz"))
    with tarfile.open(archive) as source:
        assert "data/budgets.dat" in source.getnames()
    subprocess.run([sys.executable,os.path.join(ROOT,"ops/verify-backup.py"),str(archive)],
                   check=True,capture_output=True)


@pytest.mark.parametrize("month", ["0001-01", "9999-12"])
def test_budget_calendar_boundaries(client, month):
    _, headers = login(client)
    assert client.get("/?view=BUDGET&month=" + month, headers=headers).status_code == 200


def test_corrupt_budget_storage_fails_without_overwriting(client, workdir):
    _, headers = login(client)
    path = workdir / "data/budgets.dat"
    broken = b"not a BDB database"
    path.write_bytes(broken)
    page = client.get("/?view=BUDGET&month=2026-07", headers=headers)
    assert page.status_code == 503
    assert b"name='cmd' value='budget-save'" not in page.data
    assert save_budget(client, headers).status_code == 503
    assert path.read_bytes() == broken


@pytest.mark.parametrize("name", ["ledger.sqlite3", "sessions.dat", "lockout.dat"])
def test_existing_corrupt_isam_is_never_recreated(client, workdir, name):
    _, headers = login(client)
    token = re.search(rb"name='csrf_token' value='([^']+)'", client.get("/", headers=headers).data)[1].decode()
    path = workdir / "data" / name
    broken = b"invalid database must be preserved"
    path.write_bytes(broken)
    if name == "ledger.sqlite3":
        response = client.post("/", headers=headers, csrf=False, data={"cmd": "add", "date": "2026-07-01", "cat": "Hobby", "desc": "must not write", "amount": "1", "csrf_token": token})
        assert client.get("/?export=csv", headers=headers).status_code == 503
    else:
        response, issued = login(client)
        assert not issued
    assert response.status_code == 503
    assert path.read_bytes() == broken


def test_budget_requires_expense_category_and_month(client):
    _, headers = login(client)
    assert b"categorie de cheltuieli" in save_budget(client, headers, category="Venituri").data
    response = client.post("/", headers=headers,
        data={"cmd": "budget-save", "cat": "Mancare", "amount": "100"})
    assert response.status_code == 400
    assert client.get("/?view=BUDGET&month=", headers=headers).status_code == 400


def rule(client, headers, **overrides):
    fields = {"cmd":"rule-save","date":"2026-01-31","cat":"Utilitati", "desc":"Abonament", "amount":"-40", "cycle":"MONTHLY"}
    return client.post("/?view=RECURRING", headers=headers, data={**fields, **overrides})


def book(client, headers, due="2026-01-31", id="000001"):
    return client.post("/?view=RECURRING",headers=headers,data={"cmd":"rule-book","id":id,"due":due})


def test_recurring_is_preview_until_booked(client):
    _, headers=login(client)
    response=rule(client,headers)
    assert response.status_code==200 and b"Regula recurenta salvata" in response.data
    assert b"Abonament" in response.data and b"2026-01-31" in response.data
    assert b"Abonament" not in client.get("/?export=csv",headers=headers).data
    response=book(client,headers)
    assert response.status_code==200 and b"Scadenta inregistrata o singura data" in response.data
    assert b"2026-02-28" in response.data
    assert client.get("/?export=csv",headers=headers).data.count(b"Abonament")==1
    assert b"Scadenta era deja inregistrata" in book(client,headers).data
    assert client.get("/?export=csv",headers=headers).data.count(b"Abonament")==1
    assert b"2026-03-31" in book(client,headers,due="2026-02-28").data


def test_recurring_pause_edit_archive_preserves_ledger(client):
    _,headers=login(client)
    rule(client,headers)
    client.post("/",headers=headers,data={"cmd":"rule-toggle","id":"000001"})
    assert b"In pauza" in client.get("/?view=RECURRING",headers=headers).data
    assert b"nu mai este disponibila" in book(client,headers).data
    client.post("/",headers=headers,data={"cmd":"rule-toggle","id":"000001"})
    rule(client,headers,id="000001",desc="Internet",amount="-80")
    assert b"value='-80.00'" in client.get("/?view=RECURRING&rule=000001",headers=headers).data
    book(client,headers)
    before=client.get("/?export=csv",headers=headers).data
    client.post("/",headers=headers,data={"cmd":"rule-archive","id":"000001"})
    assert b"data-rule='000001'" not in client.get("/?view=RECURRING",headers=headers).data
    assert before==client.get("/?export=csv",headers=headers).data


def test_recurring_deletion_is_a_tombstone(client):
    _,headers=login(client)
    rule(client,headers);book(client,headers)
    client.post("/",headers=headers,data={"cmd":"del","id":"000001"})
    book(client,headers)
    assert b"Abonament" not in client.get("/?export=csv",headers=headers).data
    add(client,headers,"2026-01-31","Hobby","manual","1")
    assert b"000002" in client.get("/?export=csv",headers=headers).data


@pytest.mark.parametrize("cycle,start,next_date",[("WEEKLY","2026-01-31","2026-02-07"),("YEARLY","2024-02-29","2025-02-28")])
def test_recurring_calendar(client,cycle,start,next_date):
    _,headers=login(client)
    rule(client,headers,cycle=cycle,date=start)
    assert next_date.encode() in book(client,headers,due=start).data


def test_recurring_future_and_invalid_forms(client):
    _,headers=login(client)
    assert b"Frecventa invalida" in rule(client,headers,cycle="BAD").data
    assert b"diferita de zero" in rule(client,headers,amount="0").data
    rule(client,headers,date="2099-01-01")
    assert b"nu mai este disponibila" in book(client,headers,due="2099-01-01").data
    assert b"Abonament" not in client.get("/?export=csv",headers=headers).data


def test_recurring_auth_csrf_and_duplicate_requests(client):
    assert b"<h2>Login</h2>" in rule(client,{}).data
    _,headers=login(client)
    assert client.post("/",csrf=False,headers=headers,data={"cmd":"rule-save"}).status_code==403
    rule(client,headers)
    from concurrent.futures import ThreadPoolExecutor
    import app
    def retry(_):
        with app.app.test_client(use_cookies=False) as c:
            assert book(c,headers).status_code==200
    with ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(retry,range(8)))
    assert client.get("/?export=csv",headers=headers).data.count(b"Abonament")==1


@pytest.mark.parametrize("fault",["after-intent","after-ledger","after-done"])
def test_recurring_crash_recovery(client,workdir,fault):
    from urllib.parse import urlencode
    _,headers=login(client);rule(client,headers)
    token=headers["Cookie"].split("=",1)[1]
    data=urlencode({"cmd":"rule-book","id":"000001","due":"2026-01-31"}).encode()
    env={"PATH":"/usr/bin:/bin","TZ":"UTC","REQUEST_METHOD":"POST","QUERY_STRING":"view=RECURRING", "HTTP_COOKIE":"session="+token,"CONTENT_LENGTH":str(len(data)),"LEDGER_USER":USER,"LEDGER_PASS":PASS, "LEDGER_TEST_FAULT":fault,"LEDGER_LOCAL_TODAY":"2026-11-03"}
    crashed=subprocess.run([str(workdir/"ledger.cgi")],input=data,capture_output=True,cwd=workdir,env=env)
    assert crashed.returncode==97,crashed.stderr
    # A different action first must recover the committed intent before it allocates IDs.
    add(client,headers,"2026-01-31","Hobby","manual","1")
    response=book(client,headers)
    assert response.status_code==200
    exported=client.get("/?export=csv",headers=headers).data
    assert exported.count(b"Abonament")==1 and exported.count(b"manual")==1
    assert b"2026-02-28" in response.data


def test_recurring_recovery_before_deleting_interrupted_occurrence(client,workdir):
    from urllib.parse import urlencode
    _,headers=login(client);rule(client,headers)
    data=urlencode({"cmd":"rule-book","id":"000001","due":"2026-01-31"}).encode()
    env={"PATH":"/usr/bin:/bin","REQUEST_METHOD":"POST","QUERY_STRING":"", "HTTP_COOKIE":"session="+headers["Cookie"].split("=",1)[1],"CONTENT_LENGTH":str(len(data)),"LEDGER_USER":USER,"LEDGER_PASS":PASS,"LEDGER_TEST_FAULT":"after-ledger"}
    assert subprocess.run([str(workdir/"ledger.cgi")],input=data,capture_output=True,cwd=workdir,env=env).returncode==97
    client.post("/",headers=headers,data={"cmd":"del","id":"000001"})
    book(client,headers)
    assert b"Abonament" not in client.get("/?export=csv",headers=headers).data


def test_waiting_request_rechecks_maintenance_under_lock(client, workdir, monkeypatch):
    from contextlib import contextmanager
    import app
    _, headers = login(client)
    gate = workdir / "data/.deploying"
    original_lock = app.ledger_lock

    @contextmanager
    def deployment_started_while_waiting(*args, **kwargs):
        with original_lock(*args, **kwargs):
            if app.request.method == "POST":
                gate.touch()
            yield

    monkeypatch.setattr(app, "ledger_lock", deployment_started_while_waiting)
    try:
        response = add(client, headers, "2026-07-01", "Hobby", "blocked during deploy", "1")
        assert response.status_code == 503
    finally:
        gate.unlink(missing_ok=True)
    assert b"blocked during deploy" not in client.get("/", headers=headers).data


def test_maintenance_gate_refuses_mutations(client,workdir):
    _,headers=login(client)
    gate=workdir/"data/.deploying";gate.touch()
    try: assert add(client,headers,"2026-01-01","Hobby","not written","1").status_code==503
    finally:gate.unlink()
    assert b"not written" not in client.get("/?export=csv",headers=headers).data


def test_repeated_rule_creation_remains_idempotent_after_booking(client):
    _,headers=login(client)
    key="a"*32
    rule(client,headers,create_key=key)
    book(client,headers)
    response=rule(client,headers,create_key=key)
    assert b"Regula era deja salvata" in response.data
    assert response.data.count(b"data-rule=")==1
    assert b"2026-02-28" in response.data


def test_recurring_data_is_in_a_verified_backup(client,workdir,tmp_path):
    import tarfile
    _,headers=login(client);rule(client,headers);book(client,headers)
    target=tmp_path/"recurring-snapshot"
    subprocess.run([os.path.join(ROOT,"backup.sh")],check=True,capture_output=True,
        env={**os.environ,"LEDGER_APP_DIR":str(workdir),"LEDGER_BACKUP_DIR":str(target)})
    archive=next(target.glob("*.tar.gz"))
    with tarfile.open(archive) as tar:
        assert {"data/recurring.dat","data/occurrences.dat"}.issubset(tar.getnames())
        assert "data/.ledger.lock" not in tar.getnames()
        assert "data/.deploying" not in tar.getnames()
    subprocess.run([sys.executable,os.path.join(ROOT,"ops/verify-backup.py"),str(archive)],check=True,capture_output=True)
