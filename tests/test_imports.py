"""Authenticated HTTP -> native auth -> real SQLite import and crash semantics."""
import io
import json
import re
import sqlite3
import subprocess
import sys
import time

import pytest

from test_ledger import client, workdir, login, add, rule, book
from imports import read_csv
from store import connect

CSV = b'data,categorie,descriere,suma\n2026-02-01,Venituri,Import salariu,100.01\n2026-02-02,Mancare,Import cumparaturi,-10.02\n'


def upload(client, headers, raw=CSV, **options):
    response = client.post("/import", headers=headers, data={"file": (io.BytesIO(raw), "example.csv"),
        "delimiter": ",", "decimal": ".", "date_format": "iso", **options})
    if response.status_code != 200:
        return response, ""
    token = re.search(rb'action="/import/([0-9a-f]{32})/preview"', response.data)
    return response, token[1].decode() if token else ""


def prepare(client, headers, token, **options):
    return client.post(f"/import/{token}/preview", headers=headers, data={"day": "0", "category": "1",
        "description": "2", "amount": "3", "default_category": "Hobby", "duplicates": "skip", **options})


def confirm(client, headers, token):
    return client.post(f"/import/{token}/confirm", headers=headers, data={})


def count(workdir):
    with connect(workdir) as db:
        return db.execute("SELECT count(*) FROM ledger").fetchone()[0]


def test_import_preview_commit_and_replay_after_deletion(client, workdir):
    _, headers = login(client)
    response, token = upload(client, headers)
    assert token and b"Fiecare coloana" in response.data
    assert count(workdir) == 0
    response = prepare(client, headers, token)
    assert response.status_code == 200 and b"Confirma importul (2)" in response.data
    assert b"89.99" in response.data
    assert count(workdir) == 0
    assert b"Import incheiat" in confirm(client, headers, token).data
    with connect(workdir) as db:
        assert db.execute("SELECT amount_cents FROM ledger ORDER BY id").fetchall() == [(10001,), (-1002,)]
        assert db.execute("SELECT source_json,rows_json FROM import_batches").fetchone() == ("[]", "[]")
    client.post("/", headers=headers, data={"cmd": "del", "id": "000001"})
    assert confirm(client, headers, token).status_code == 200
    assert count(workdir) == 1
    assert "index" not in client.get(f"/import/{token}", headers=headers).headers["X-Robots-Tag"].replace("noindex", "")


def test_duplicates_inside_file_and_ledger_are_skipped(client, workdir):
    _, headers = login(client)
    add(client, headers, "2026-02-01", "Venituri", "Import salariu", "100.01")
    raw = CSV + b"2026-02-02,Mancare,Import cumparaturi,-10.02\n"
    _, token = upload(client, headers, raw)
    response = prepare(client, headers, token)
    assert b"Confirma importul (1)" in response.data
    assert response.data.count("Duplicat · omis".encode()) == 2
    confirm(client, headers, token)
    assert count(workdir) == 2


def test_legitimate_identical_rows_can_be_included(client, workdir):
    _, headers = login(client)
    _, token = upload(client, headers, CSV + CSV.splitlines(keepends=True)[1])
    assert b"Confirma importul (3)" in prepare(client, headers, token, duplicates="include").data
    confirm(client, headers, token)
    assert count(workdir) == 3


def test_commit_refreshes_changed_duplicate_decisions(client, workdir):
    _, headers = login(client)
    _, token = upload(client, headers)
    prepare(client, headers, token)
    add(client, headers, "2026-02-01", "Venituri", "Import salariu", "100.01")
    response = confirm(client, headers, token)
    assert response.status_code == 409 and b"Confirma importul (1)" in response.data
    assert count(workdir) == 1
    confirm(client, headers, token)
    assert count(workdir) == 2


@pytest.mark.parametrize("row", [
    "2026-02-30,Hobby,bad date,1", "0000-01-01,Hobby,bad date,1", "2026-02-01,Other,bad category,1",
    "2026-02-01,Hobby,bad sum,1.001", "2026-02-01,Hobby,bad sum,1e2", "2026-02-01,Hobby,bad sum,10000000",
    "2026-02-01,Hobby," + "ă"*16 + ",1", "2026-02-01,Hobby,,1",
])
def test_invalid_rows_block_entire_batch(client, workdir, row):
    _, headers = login(client)
    _, token = upload(client, headers, CSV + (row+"\n").encode())
    response = prepare(client, headers, token)
    assert b"disabled" in response.data and b"Importul este blocat" in response.data
    assert confirm(client, headers, token).status_code == 409
    assert count(workdir) == 0


def test_mapping_decimal_comma_calendar_and_default_category(client, workdir):
    _, headers = login(client)
    raw = 'Cand;Detalii;Valoare\n29.02.2024;Prânz;"-12,34"\n'.encode()
    _, token = upload(client, headers, raw, delimiter=";", decimal=",", date_format="dmy")
    response = prepare(client, headers, token, day="0", category="-1", description="1", amount="2", default_category="Mancare")
    assert b"Confirma importul (1)" in response.data
    confirm(client, headers, token)
    with connect(workdir) as db:
        assert db.execute("SELECT day,category,description,amount_cents FROM ledger").fetchone() == ("2024-02-29", "Mancare", "Prânz", -1234)


def test_database_failure_rolls_back_entire_batch_and_can_retry(client, workdir):
    _, headers = login(client)
    _, token = upload(client, headers)
    prepare(client, headers, token)
    with connect(workdir) as db:
        db.execute("CREATE TRIGGER simulate_failure BEFORE INSERT ON ledger WHEN new.amount_cents<0 BEGIN SELECT RAISE(ABORT,'simulated failure'); END")
    assert confirm(client, headers, token).status_code == 503
    assert count(workdir) == 0
    with connect(workdir) as db:
        assert db.execute("SELECT state FROM import_batches").fetchone() == ("ready",)
        db.execute("DROP TRIGGER simulate_failure")
    assert confirm(client, headers, token).status_code == 200
    assert count(workdir) == 2


def test_import_is_session_bound_csrf_protected_and_private(client, workdir):
    assert client.get("/import").status_code == 302
    _, headers = login(client)
    _, token = upload(client, headers)
    _, another = login(client)
    assert client.get(f"/import/{token}/mapping", headers=another).status_code == 404
    assert prepare(client, another, token).status_code == 404
    assert client.post(f"/import/{token}/confirm", headers=headers, csrf=False, content_type="application/x-www-form-urlencoded", data={}).status_code == 403
    assert client.post(f"/import/{token}/preview", headers={**headers, "Origin": "https://evil.example"}, data={}).status_code == 403
    response = client.get("/import", headers=headers)
    assert response.headers["X-Robots-Tag"] == "noindex, nofollow"
    assert "no-store" in response.headers["Cache-Control"]
    client.post("/", headers=headers, data={"cmd": "logout"})
    assert confirm(client, headers, token).status_code == 401


def test_expired_draft_is_rejected(client, workdir):
    _, headers = login(client)
    _, token = upload(client, headers)
    prepare(client, headers, token)
    with connect(workdir) as db:
        db.execute("UPDATE import_batches SET expires=0")
    assert confirm(client, headers, token).status_code == 410
    assert count(workdir) == 0


def test_csv_limits_and_escaping(client, workdir):
    _, headers = login(client)
    assert upload(client, headers, b"data,x,y,z\n" + b"a"*65536)[0].status_code == 400
    assert upload(client, headers, CSV + b"x\x00,y,z,1\n")[0].status_code == 400
    assert upload(client, headers, b"a,b,c,d\n" + b"x,y,z,1\n"*201)[0].status_code == 400
    assert upload(client, headers, b"a,b,c,d\n\xff,y,z,1\n")[0].status_code == 400
    _, token = upload(client, headers, b'data,categorie,descriere,suma\n2026-02-01,Hobby,<script>x</script>,1\n')
    response = prepare(client, headers, token)
    assert b"<script>x</script>" not in response.data and b"&lt;script&gt;" in response.data


def test_export_roundtrip_formula_prefix_is_explicit(client, workdir):
    _, headers = login(client)
    add(client, headers, "2026-02-01", "Hobby", "=1+1", "-1.25")
    raw = client.get("/?export=csv", headers=headers).data
    _, token = upload(client, headers, raw)
    response = prepare(client, headers, token, day="1", category="2", description="3", amount="4", ledger_export="yes")
    assert b"Confirma importul (0)" in response.data
    confirm(client, headers, token)
    assert count(workdir) == 1


def test_recurring_reservation_and_import_ids_do_not_collide(client, workdir):
    _, headers = login(client)
    rule(client, headers)
    book(client, headers)
    client.post("/", headers=headers, data={"cmd": "del", "id": "000001"})
    _, token = upload(client, headers)
    prepare(client, headers, token)
    confirm(client, headers, token)
    with connect(workdir) as db:
        assert db.execute("SELECT id FROM ledger ORDER BY id").fetchall() == [(2,), (3,)]
    assert b"deja inregistrata" in book(client, headers).data


def test_upload_above_old_four_kilobyte_limit(client):
    _, headers = login(client)
    raw = b"data,categorie,descriere,suma\n" + b"2026-02-01,Hobby,Descriere suficient de lunga,1\n"*180
    assert len(raw) > 4096
    assert upload(client, headers, raw)[0].status_code == 200


@pytest.mark.parametrize("after_commit", [False, True])
def test_process_interruption_leaves_batch_atomic(client, workdir, after_commit):
    _, headers = login(client)
    _, token = upload(client, headers)
    prepare(client, headers, token)
    csrf = re.search(rb"name='csrf_token' value='([^']+)'", client.get("/", headers=headers).data)[1].decode()
    script = r'''
from contextlib import contextmanager
import os, sys
import imports
from app import app
real_connect = imports.connect
@contextmanager
def interrupted_connect(*args, **kwargs):
    with real_connect(*args, **kwargs) as db:
        inserts = 0
        def trace(sql):
            nonlocal inserts
            if sql.startswith('INSERT INTO ledger('):
                inserts += 1
                if inserts == 2:
                    os._exit(97)
        if sys.argv[4] == 'False':
            db.set_trace_callback(trace)
        yield db
imports.connect = interrupted_connect
original_redirect = imports.redirect
def interrupted_redirect(*args, **kwargs):
    if sys.argv[4] == 'True':
        os._exit(97)
    return original_redirect(*args, **kwargs)
imports.redirect = interrupted_redirect
app.test_client(use_cookies=False).post('/import/'+sys.argv[1]+'/confirm',
    headers={'Cookie':sys.argv[2]}, data={'csrf_token':sys.argv[3]})
'''
    result = subprocess.run([sys.executable, "-c", script, token, headers["Cookie"], csrf, str(after_commit)], capture_output=True)
    assert result.returncode == 97
    assert count(workdir) == (2 if after_commit else 0)
    assert confirm(client, headers, token).status_code == 200
    assert count(workdir) == 2


def test_parallel_confirmations_import_once(client, workdir):
    from concurrent.futures import ThreadPoolExecutor
    import app
    _, headers = login(client)
    _, token = upload(client, headers)
    prepare(client, headers, token)
    def submit(_):
        with app.app.test_client(use_cookies=False) as isolated:
            return confirm(isolated, headers, token).status_code
    with ThreadPoolExecutor(max_workers=3) as pool:
        assert list(pool.map(submit, range(3))) == [200, 200, 200]
    assert count(workdir) == 2
