#!/usr/bin/env python3
"""Apply additive financial schema upgrades under the shared writer lock."""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3

from locking import ledger_lock
from store import connect

LATEST_VERSION = 2
MIGRATIONS = Path(__file__).resolve().parent / "migrations"


def ledger_digest(db):
    digest = hashlib.sha256()
    for row in db.execute("SELECT id,day,category,description,amount_cents FROM ledger ORDER BY id"):
        digest.update(json.dumps(tuple(row), ensure_ascii=False, separators=(",", ":")).encode()+b"\n")
    return digest.hexdigest()


def statements(source):
    pending = ""
    for line in source.splitlines(keepends=True):
        pending += line
        if sqlite3.complete_statement(pending):
            yield pending
            pending = ""
    if pending.strip():
        raise ValueError("Incomplete SQL migration")


def upgrade(work_dir, target=LATEST_VERSION):
    with ledger_lock(work_dir, timeout=30), connect(work_dir) as db:
        version = db.execute("PRAGMA user_version").fetchone()[0]
        if not version <= target <= LATEST_VERSION:
            raise ValueError("Unsupported upgrade target")
        original = ledger_digest(db)
        # ADD COLUMN with a non-NULL FK default requires FK enforcement disabled
        # outside the transaction. No other writer can enter while this lock is held.
        db.execute("PRAGMA foreign_keys=OFF")
        try:
            for next_version in range(version+1, target+1):
                source = next(MIGRATIONS.glob(f"{next_version:03d}_*.sql"))
                db.execute("BEGIN IMMEDIATE")
                for statement in statements(source.read_text()):
                    db.execute(statement)
                if db.execute("PRAGMA foreign_key_check").fetchall():
                    raise ValueError("Foreign key check failed")
                if ledger_digest(db) != original:
                    raise ValueError("Migration changed existing financial values")
                if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                    raise ValueError("Integrity check failed")
                db.execute(f"PRAGMA user_version={next_version}")
                db.commit()
        finally:
            if db.in_transaction:
                db.rollback()
            db.execute("PRAGMA foreign_keys=ON")
        print(f"FINANCE_SCHEMA_OK: version {target}; original transactions verified unchanged")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    upgrade(args.work_dir.resolve())
