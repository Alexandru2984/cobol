"""Versioned upgrades must preserve money and survive retries and bad schemas."""
from pathlib import Path
import sqlite3
import subprocess
import sys

import pytest

from test_ledger import ROOT
from upgrade_store import ledger_digest, upgrade
from store import connect


def legacy_sql(tmp_path):
    (tmp_path / "data").mkdir()
    path = tmp_path / "data/ledger.sqlite3"
    with sqlite3.connect(path) as db:
        db.executescript((Path(ROOT)/"migrations/001_core.sql").read_text())
        db.execute("INSERT INTO ledger VALUES(7,'2026-01-01','Hobby','Legacy exact',-1234)")
    return path


def test_upgrade_preserves_ids_money_and_assigns_primary_account(tmp_path):
    legacy_sql(tmp_path)
    with connect(tmp_path) as db:
        original = ledger_digest(db)
    upgrade(tmp_path)
    upgrade(tmp_path)
    with connect(tmp_path) as db:
        assert ledger_digest(db) == original
        assert db.execute("SELECT id,account_id,amount_cents FROM ledger").fetchall() == [(7,1,-1234)]
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        # Previous compatible release writes only the original five fields.
        db.execute("INSERT INTO ledger(id,day,category,description,amount_cents) VALUES(8,'2026-01-02','Hobby','Old writer',42)")
        assert db.execute("SELECT account_id FROM ledger WHERE id=8").fetchone() == (1,)


def test_failed_upgrade_rolls_back_without_partial_tables(tmp_path, monkeypatch):
    legacy_sql(tmp_path)
    import upgrade_store
    broken = tmp_path / "migrations"
    broken.mkdir()
    (broken / "002_bad.sql").write_text("CREATE TABLE partial(id INTEGER);\nSELECT * FROM missing_table;\n")
    monkeypatch.setattr(upgrade_store, "MIGRATIONS", broken)
    with pytest.raises(sqlite3.Error):
        upgrade(tmp_path)
    with connect(tmp_path) as db:
        assert db.execute("PRAGMA user_version").fetchone() == (1,)
        assert not db.execute("SELECT name FROM sqlite_schema WHERE name='partial'").fetchall()
        assert db.execute("SELECT amount_cents FROM ledger").fetchone() == (-1234,)


def test_generated_native_schema_matches_versioned_sources():
    subprocess.run([sys.executable, str(Path(ROOT)/"ops/generate-schema.py"), "--check"], check=True)
