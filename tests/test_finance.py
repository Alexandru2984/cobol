"""Real HTTP/native/SQLite invariants for accounts and internal transfers."""
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from pathlib import Path
import os
import re
import subprocess
from urllib.parse import urlencode

import pytest

from test_ledger import ROOT, USER, PASS, client, workdir, login, add, rule
from test_imports import upload, prepare, confirm
from finance import accounts
from store import connect


class Forms(HTMLParser):
    def __init__(self):
        super().__init__()
        self.forms, self.current = {}, None
    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if tag == "form":
            self.current = attributes.get("action")
            self.forms[self.current] = {}
        if tag == "input" and self.current and attributes.get("name"):
            self.forms[self.current][attributes["name"]] = attributes.get("value", "")
    def handle_endtag(self, tag):
        if tag == "form":
            self.current = None


def form_token(client, headers, action, page="/accounts"):
    parser = Forms()
    response = client.get(page, headers=headers)
    assert response.status_code == 200, response.data[:1000]
    parser.feed(response.get_data(as_text=True))
    return parser.forms[action]["nonce"]


def submit(client, headers, action, fields=None, nonce=None, page="/accounts"):
    nonce = nonce or form_token(client, headers, action, page)
    return client.post(action, headers=headers, data={"nonce": nonce, **(fields or {})})


def create_account(client, headers, name="Card zilnic", kind="card", opening="0"):
    return submit(client, headers, "/accounts/create", {"name": name, "kind": kind, "opening": opening})


def transfer(client, headers, **overrides):
    return submit(client, headers, "/transfers/create", {"source": "1", "destination": "2", "date": "2026-11-01", "description": "Transfer test", "amount": "25.10", **overrides})


def balances(workdir):
    with connect(workdir) as db:
        return {row["id"]: row["balance"] for row in accounts(db)}


def test_accounts_transfer_void_and_reports_keep_income_unchanged(client, workdir):
    _, headers = login(client)
    add(client, headers, "2026-11-01", "Venituri", "Venit real", "100")
    assert create_account(client, headers).status_code == 200
    before = client.get("/?export=csv", headers=headers).data
    assert transfer(client, headers).status_code == 200
    assert balances(workdir) == {1: 7490, 2: 2510}
    assert client.get("/?export=csv", headers=headers).data == before
    assert b"100.00" in client.get("/?view=REPORT", headers=headers).data
    assert b"Transfer test" not in client.get("/", headers=headers).data
    assert submit(client, headers, "/transfers/1/void").status_code == 200
    assert balances(workdir) == {1: 10000, 2: 0}
    with connect(workdir) as db:
        assert db.execute("SELECT voided FROM transfers").fetchone() == (1,)


def test_account_opening_does_not_create_income(client, workdir):
    _, headers = login(client)
    create_account(client, headers, opening="12.34")
    assert balances(workdir) == {1: 0, 2: 1234}
    with connect(workdir) as db:
        assert db.execute("SELECT count(*) FROM ledger").fetchone()[0] == 0


def test_manual_transactions_edit_filters_and_import_use_selected_account(client, workdir):
    _, headers = login(client)
    create_account(client, headers)
    response = client.post("/", headers=headers, data={"cmd": "add", "date": "2026-11-01", "cat": "Venituri", "desc": "Venit card", "amount": "12.34", "account": "2"})
    assert b"Venit card" in response.data and b"transaction-account" in response.data
    assert b"Venit card" not in client.get("/?account=1", headers=headers).data
    assert b"Venit card" in client.get("/?account=2&sort=DATE_DESC", headers=headers).data
    assert b"Venit card" not in client.get("/?account=1&export=csv", headers=headers).data
    assert b"Venit card" in client.get("/?account=2&view=REPORT", headers=headers).data or b"12.34" in client.get("/?account=2&view=REPORT", headers=headers).data
    response = client.get("/?edit=000001", headers=headers)
    assert re.search(rb'<option value="2" selected', response.data)
    client.post("/", headers=headers, data={"cmd": "update", "id": "1", "date": "2026-11-01", "cat": "Venituri", "desc": "Venit mutat", "amount": "12.34", "account": "1"})
    assert balances(workdir) == {1: 1234, 2: 0}
    _, token = upload(client, headers)
    prepare(client, headers, token, account="2")
    confirm(client, headers, token)
    assert balances(workdir) == {1: 1234, 2: 8999}


def test_duplicate_import_decision_is_per_account(client, workdir):
    _, headers = login(client)
    create_account(client, headers)
    _, token = upload(client, headers)
    prepare(client, headers, token)
    confirm(client, headers, token)
    _, next_token = upload(client, headers)
    assert b"Confirma importul (2)" in prepare(client, headers, next_token, account="2").data
    confirm(client, headers, next_token)
    assert balances(workdir) == {1: 8999, 2: 8999}


def test_transfer_replay_and_parallel_requests_do_not_move_twice(client, workdir):
    import app
    _, headers = login(client)
    add(client, headers, "2026-11-01", "Venituri", "Balance", "100")
    create_account(client, headers)
    action = "/transfers/create"
    nonce = form_token(client, headers, action)
    fields = {"source": "1", "destination": "2", "date": "2026-11-01", "description": "Once", "amount": "10"}
    def send(_):
        with app.app.test_client(use_cookies=False) as isolated:
            return submit(isolated, headers, action, fields, nonce).status_code
    with ThreadPoolExecutor(max_workers=3) as pool:
        assert list(pool.map(send, range(3))) == [200]*3
    assert balances(workdir) == {1: 9000, 2: 1000}
    assert submit(client, headers, action, {**fields, "amount": "20"}, nonce).status_code == 409
    submit(client, headers, "/transfers/1/void")
    assert submit(client, headers, action, fields, nonce).status_code == 200
    assert balances(workdir) == {1: 10000, 2: 0}


@pytest.mark.parametrize("overrides", [{"source": "1", "destination": "1"}, {"amount": "0"}, {"amount": "-2"}, {"amount": "1.001"}, {"date": "2026-02-30"}, {"destination": "999999"}, {"amount": "999"}])
def test_invalid_or_unfunded_transfer_changes_nothing(client, workdir, overrides):
    _, headers = login(client)
    create_account(client, headers)
    response = transfer(client, headers, **overrides)
    assert response.status_code in {400, 404, 409}
    assert balances(workdir) == {1: 0, 2: 0}
    with connect(workdir) as db:
        assert db.execute("SELECT count(*) FROM transfers").fetchone()[0] == 0


def test_archived_accounts_keep_history_and_reject_new_posts(client, workdir):
    _, headers = login(client)
    create_account(client, headers, opening="50")
    submit(client, headers, "/accounts/2/status", {"active": "0"})
    assert balances(workdir) == {1: 0, 2: 5000}
    assert transfer(client, headers).status_code == 409
    client.post("/", headers=headers, data={"cmd": "add", "date": "2026-11-01", "cat": "Hobby", "desc": "must not insert", "amount": "2", "account": "2"})
    with connect(workdir) as db:
        assert db.execute("SELECT count(*) FROM ledger").fetchone()[0] == 0
    assert submit(client, headers, "/accounts/1/status", {"active": "0"}, nonce=form_token(client, headers, "/accounts/2/status")).status_code == 403


def test_finance_auth_csrf_scope_and_database_error_rollback(client, workdir):
    assert client.get("/accounts").status_code == 302
    _, headers = login(client)
    nonce = form_token(client, headers, "/accounts/create")
    _, another = login(client)
    assert submit(client, another, "/accounts/create", {"name": "Denied", "kind": "cash", "opening": "0"}, nonce).status_code == 403
    assert client.post("/accounts/create", csrf=False, headers=headers, data={"nonce": nonce}).status_code == 403
    assert client.get("/accounts", headers=headers).headers["X-Robots-Tag"] == "noindex, nofollow"
    with connect(workdir) as db:
        db.execute("CREATE TRIGGER fail_finance_event BEFORE INSERT ON finance_events BEGIN SELECT RAISE(ABORT,'failure'); END")
    response = submit(client, headers, "/accounts/create", {"name": "Not saved", "kind": "cash", "opening": "0"}, nonce)
    assert response.status_code == 503 and balances(workdir) == {1: 0}


def test_recovery_uses_primary_account_before_manual_add_to_another(client, workdir):
    _, headers = login(client)
    create_account(client, headers)
    rule(client, headers)
    data = urlencode({"cmd": "rule-book", "id": "000001", "due": "2026-01-31"}).encode()
    env = {"PATH": "/usr/bin:/bin", "REQUEST_METHOD": "POST", "QUERY_STRING": "", "HTTP_COOKIE": "session="+headers["Cookie"].split("=",1)[1], "CONTENT_LENGTH": str(len(data)), "LEDGER_USER": USER, "LEDGER_PASS": PASS, "LEDGER_TEST_FAULT": "after-intent"}
    result = subprocess.run([str(workdir/"ledger.cgi")], input=data, capture_output=True, cwd=workdir, env=env)
    assert result.returncode == 97
    client.post("/", headers=headers, data={"cmd": "add", "date": "2026-11-01", "cat": "Hobby", "desc": "Another account", "amount": "1", "account": "2"})
    with connect(workdir) as db:
        assert db.execute("SELECT id,account_id FROM ledger ORDER BY id").fetchall() == [(1,1),(2,2)]
