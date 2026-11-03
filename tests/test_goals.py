"""Savings allocations reserve existing money; they never create income or expense."""
from concurrent.futures import ThreadPoolExecutor
import sqlite3

import pytest

from test_ledger import client, workdir, login, add
from test_finance import create_account, submit, form_token, balances, transfer
from finance import accounts, goals
from store import connect


def create_goal(client, headers, **overrides):
    return submit(client, headers, "/goals/create", {"name": "Fond rezerva", "account": "2", "target": "100", "deadline": "", **overrides}, page="/goals")


def allocation(client, headers, amount="25", direction="allocate", key=1, nonce=None):
    return submit(client, headers, f"/goals/{key}/contribute", {"direction": direction, "amount": amount, "note": "Test alocare"}, nonce=nonce, page="/goals")


def snapshot(workdir):
    with connect(workdir) as db:
        return goals(db), accounts(db)


def setup_goal(client, opening="200"):
    _, headers = login(client)
    create_account(client, headers, opening=opening)
    assert create_goal(client, headers).status_code == 200
    return headers


def test_goal_funding_release_and_completion_do_not_change_cash_or_income(client, workdir):
    headers = setup_goal(client)
    assert allocation(client, headers, "75.25").status_code == 200
    goal_rows, account_rows = snapshot(workdir)
    assert goal_rows[0]["saved"] == 7525
    assert account_rows[1]["reserved"] == 7525 and account_rows[1]["available"] == 12475
    assert allocation(client, headers, "25.25", direction="release").status_code == 200
    allocation(client, headers, "50")
    assert submit(client, headers, "/goals/1/status", {"state": "completed"}, page="/goals").status_code == 200
    goal_rows, account_rows = snapshot(workdir)
    assert goal_rows[0]["state"] == "completed" and goal_rows[0]["saved"] == 10000
    assert account_rows[1]["reserved"] == 0 and account_rows[1]["available"] == 20000
    assert balances(workdir) == {1: 0, 2: 20000}
    with connect(workdir) as db:
        assert db.execute("SELECT count(*) FROM ledger").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM transfers").fetchone()[0] == 0


def test_reserved_funds_are_unavailable_to_transfers_and_other_goals(client, workdir):
    headers = setup_goal(client, opening="100")
    allocation(client, headers, "80")
    assert transfer(client, headers, source="2", destination="1", amount="25").status_code == 409
    assert create_goal(client, headers, name="Al doilea").status_code == 200
    assert allocation(client, headers, "21", key=2).status_code == 409
    assert allocation(client, headers, "20", key=2).status_code == 200
    assert snapshot(workdir)[1][1]["available"] == 0


def test_repeated_allocation_after_completion_does_not_resurrect_reservation(client, workdir):
    headers = setup_goal(client)
    nonce = form_token(client, headers, "/goals/1/contribute", "/goals")
    allocation(client, headers, "100", nonce=nonce)
    submit(client, headers, "/goals/1/status", {"state": "completed"}, page="/goals")
    assert allocation(client, headers, "100", nonce=nonce).status_code == 200
    assert snapshot(workdir)[1][1]["reserved"] == 0
    with connect(workdir) as db:
        assert db.execute("SELECT count(*) FROM goal_contributions").fetchone() == (1,)


@pytest.mark.parametrize("amount,direction", [("101","allocate"),("0","allocate"),("-1","allocate"),("1.001","allocate"),("1","release")])
def test_invalid_contributions_leave_no_allocations(client, workdir, amount, direction):
    headers = setup_goal(client)
    assert allocation(client, headers, amount, direction).status_code in {400,409}
    assert snapshot(workdir)[0][0]["saved"] == 0


def test_archive_and_target_validation_preserve_allocations(client, workdir):
    headers = setup_goal(client)
    status_nonce = form_token(client, headers, "/goals/1/status", "/goals")
    allocation(client, headers, "50")
    assert submit(client, headers, "/goals/1/status", {"state": "archived"}, nonce=status_nonce, page="/goals").status_code == 409
    assert submit(client, headers, "/goals/1/status", {"state": "completed"}, nonce=status_nonce, page="/goals").status_code == 409
    assert submit(client, headers, "/goals/1/save", {"name": "Edited", "target": "49", "deadline": ""}, page="/goals?edit=1").status_code == 409
    allocation(client, headers, "50", direction="release")
    assert submit(client, headers, "/goals/1/status", {"state": "archived"}, page="/goals").status_code == 200
    assert snapshot(workdir)[0][0]["state"] == "archived"
    submit(client, headers, "/goals/1/status", {"state": "active"}, page="/goals")
    assert snapshot(workdir)[0][0]["state"] == "active"


def test_spending_warns_of_underfunded_allocations_without_fake_adjustments(client, workdir):
    headers = setup_goal(client, opening="100")
    allocation(client, headers, "80")
    client.post("/", headers=headers, data={"cmd": "add", "date": "2026-11-01", "cat": "Hobby", "desc": "Cheltuiala reala", "amount": "-60", "account": "2"})
    response = client.get("/goals", headers=headers)
    assert b"alocarile depasesc soldul" in response.data
    goal_rows, account_rows = snapshot(workdir)
    assert goal_rows[0]["saved"] == 8000 and account_rows[1]["balance"] == 4000
    assert allocation(client, headers, "1").status_code == 409
    allocation(client, headers, "40", direction="release")
    assert snapshot(workdir)[1][1]["reserved"] == 4000


def test_parallel_goals_cannot_reserve_the_same_money(client, workdir):
    import app
    headers = setup_goal(client, opening="100")
    create_goal(client, headers, name="Alt obiectiv")
    nonces = {key: form_token(client, headers, f"/goals/{key}/contribute", "/goals") for key in (1,2)}
    def send(key):
        with app.app.test_client(use_cookies=False) as isolated:
            return allocation(isolated, headers, "80", key=key, nonce=nonces[key]).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(send, (1,2))) == [200,409]
    assert snapshot(workdir)[1][1]["reserved"] == 8000


def test_goal_sql_failure_rolls_back_and_history_is_append_only(client, workdir):
    headers = setup_goal(client)
    with connect(workdir) as db:
        db.execute("CREATE TRIGGER fail_goal_receipt BEFORE INSERT ON finance_requests BEGIN SELECT RAISE(ABORT,'failure'); END")
    assert allocation(client, headers).status_code == 503
    assert snapshot(workdir)[0][0]["saved"] == 0
    with connect(workdir) as db:
        db.execute("DROP TRIGGER fail_goal_receipt")
    allocation(client, headers)
    with connect(workdir) as db:
        with pytest.raises(sqlite3.IntegrityError):
            db.execute("DELETE FROM goal_contributions")


def test_goal_routes_are_private_and_reject_cross_session_nonce(client, workdir):
    assert client.get("/goals").status_code == 302
    headers = setup_goal(client)
    nonce = form_token(client, headers, "/goals/1/contribute", "/goals")
    _, other = login(client)
    assert allocation(client, other, nonce=nonce).status_code == 403
    assert client.get("/goals", headers=headers).headers["X-Robots-Tag"] == "noindex, nofollow"


def test_deadlines_are_calendar_valid_and_suggestions_use_integer_money(client, workdir):
    headers = setup_goal(client)
    assert create_goal(client, headers, name="Invalid", deadline="2027-02-29").status_code == 400
    assert create_goal(client, headers, name="Termen vechi", deadline="2000-01-01").status_code == 200
    assert b"Termen depasit" in client.get("/goals", headers=headers).data
    assert create_goal(client, headers, name="In viitor", deadline="9999-12-31", target="9999999.99").status_code == 200
    assert all(goal["monthly"] is None or isinstance(goal["monthly"], int) for goal in snapshot(workdir)[0])
