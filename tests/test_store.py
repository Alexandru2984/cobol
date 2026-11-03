"""Real native store, lossless migration and fail-closed rollback checks."""
from pathlib import Path
import subprocess
import sys

import pytest

from test_ledger import ROOT, client, workdir, login, add
from migrate_store import digest, migrate, native, parse_export, rollback
from store import connect


def test_deleted_ids_are_not_reused(client, workdir):
    _, headers = login(client)
    add(client, headers, "2026-01-01", "Hobby", "first", "1.01")
    client.post("/", headers=headers, data={"cmd": "del", "id": "000001"})
    add(client, headers, "2026-01-02", "Hobby", "second", "-2.02")
    with connect(workdir) as db:
        assert db.execute("SELECT id,amount_cents FROM ledger").fetchall() == [(2, -202)]


def test_sql_constraints_reject_invalid_dates_and_amounts(client, workdir):
    login(client)
    with connect(workdir) as db:
        for day, money in [("2026-02-30", 1), ("0000-01-01", 1), ("2026-01-01", 1.5), ("2026-01-01", 1000000000)]:
            import sqlite3
            with pytest.raises(sqlite3.IntegrityError):
                db.execute("INSERT INTO ledger(day,category,description,amount_cents) VALUES(?,'Hobby','invalid',?)", (day, money))


def test_health_detects_unavailable_store(client, workdir):
    login(client)
    (workdir / "data/ledger.sqlite3").write_bytes(b"broken SQL store")
    response = client.get("/health")
    assert response.status_code == 503 and response.json["checks"]["store"] is False


def test_seed_refuses_sqlite_and_corrupt_legacy_even_without_force(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    seed = tmp_path / "seed"
    subprocess.run(["cobc", "-x", "-free", str(Path(ROOT) / "seed.cbl"), "-o", str(seed)], check=True)
    for name in ("ledger.sqlite3", "ledger.dat"):
        path = data / name
        path.write_bytes(b"must not overwrite")
        result = subprocess.run([str(seed)], cwd=tmp_path, capture_output=True)
        assert result.returncode != 0 and path.read_bytes() == b"must not overwrite"
        path.unlink()


def test_legacy_presence_requires_explicit_migration(client, workdir):
    path = workdir / "data/ledger.dat"
    path.write_bytes(b"must not be replaced")
    response, _ = login(client)
    assert response.status_code == 503
    assert not (workdir / "data/ledger.sqlite3").exists()
    assert path.read_bytes() == b"must not be replaced"


def test_migration_preserves_records_and_original_files(workdir, tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    seed = tmp_path / "seed"
    subprocess.run(["cobc", "-x", "-free", str(Path(ROOT) / "seed.cbl"), "-o", str(seed)], check=True)
    subprocess.run([str(seed)], cwd=tmp_path, check=True, capture_output=True)
    before = {p.name: p.read_bytes() for p in data.glob("ledger.dat*")}
    rows = parse_export(native(workdir / "ledger.cgi", tmp_path, "legacy"))
    migrate(tmp_path, workdir / "ledger.cgi")
    assert rows and parse_export(native(workdir / "ledger.cgi", tmp_path, "export")) == rows
    assert before == {p.name: p.read_bytes() for p in data.glob("ledger.dat*")}
    assert all(p.stat().st_mode & 0o777 == 0o400 for p in data.glob("ledger.dat*"))
    migrate(tmp_path, workdir / "ledger.cgi")
    (data / ".deploying").touch()
    with connect(tmp_path) as db:
        db.execute("UPDATE ledger SET amount_cents=amount_cents+1 WHERE id=(SELECT min(id) FROM ledger)")
    with pytest.raises(ValueError, match="has changed"):
        rollback(tmp_path)
    assert (data / "ledger.sqlite3").exists()
    with connect(tmp_path) as db:
        db.execute("UPDATE ledger SET amount_cents=amount_cents-1 WHERE id=(SELECT min(id) FROM ledger)")
    rollback(tmp_path)
    assert not (data / "ledger.sqlite3").exists()
    assert before == {p.name: p.read_bytes() for p in data.glob("ledger.dat*")}


def test_migration_rejects_corrupt_legacy(workdir, tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data/ledger.dat").write_bytes(b"broken legacy store")
    with pytest.raises(subprocess.CalledProcessError):
        migrate(tmp_path, workdir / "ledger.cgi")
    assert not (tmp_path / "data/ledger.sqlite3").exists()


def test_native_roundtrip_preserves_utf8_quotes_and_formula_text(client, workdir):
    _, headers = login(client)
    for description in ['=1+1', 'Prânz, "acasă"', '@formula']:
        add(client, headers, "0001-01-01", "Mancare", description, "-9999999.99")
    rows = parse_export(native(workdir / "ledger.cgi", workdir, "export"))
    assert [row[3] for row in rows] == ['=1+1', 'Prânz, "acasă"', '@formula']
    assert all(row[4] == -999999999 for row in rows)
