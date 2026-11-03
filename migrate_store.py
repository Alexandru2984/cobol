#!/usr/bin/env python3
"""Lossless, locked migration; original ISAM files are retained byte for byte."""
import argparse
import csv
from datetime import date
from decimal import Decimal
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from locking import ledger_lock
from store import CATEGORIES, connect


def native(binary, work, mode):
    result = subprocess.run([str(binary)], cwd=work,
        env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LEDGER_STORE_ADMIN": mode},
        capture_output=True, timeout=30, check=True)
    return result.stdout.decode("utf-8", errors="strict")


def parse_export(raw):
    rows = []
    for row in csv.reader(io.StringIO(raw), strict=True):
        if len(row) != 5:
            raise ValueError("Invalid legacy row")
        key, day, category, description, amount = row
        if not re.fullmatch(r"[0-9]{6}", key) or not 1 <= int(key) <= 999999:
            raise ValueError("Invalid legacy ID")
        if date.fromisoformat(day).isoformat() != day or category not in CATEGORIES:
            raise ValueError("Invalid legacy date/category")
        if not description.strip() or len(description.encode()) > 30 or any(
                ord(ch) < 32 or ord(ch) == 127 for ch in description):
            raise ValueError("Invalid legacy description")
        if not re.fullmatch(r"-?[0-9]{1,7}\.[0-9]{2}", amount):
            raise ValueError("Invalid legacy amount")
        rows.append((int(key), day, category, description, int(Decimal(amount) * 100)))
    if len({row[0] for row in rows}) != len(rows):
        raise ValueError("Duplicate legacy IDs")
    return sorted(rows)


def digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def migrate(work, binary):
    target = work / "data/ledger.sqlite3"
    with ledger_lock(work, timeout=30):
        if target.exists() or target.is_symlink():
            with connect(work) as db:
                if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                    raise ValueError("SQLite integrity check failed")
            print("SQLite store already verified; no data rewritten")
            return
        legacy = work / "data/ledger.dat"
        rows = parse_export(native(binary, work, "legacy")) if legacy.exists() else []
        # Temp storage is on the same filesystem for atomic installation.
        with tempfile.TemporaryDirectory(prefix=".sql-migration-", dir=work / "data") as scratch:
            stage = Path(scratch)
            (stage / "data").mkdir(mode=0o700)
            native(binary, stage, "init")
            with connect(stage) as db:
                db.execute("BEGIN IMMEDIATE")
                db.executemany("INSERT INTO ledger VALUES(?,?,?,?,?)", rows)
                db.execute("INSERT INTO metadata VALUES('migration_rows_sha256',?)", (digest(rows),))
                db.commit()
                copied = db.execute("SELECT id,day,category,description,amount_cents FROM ledger ORDER BY id").fetchall()
                if copied != rows or db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                    raise ValueError("Migration comparison failed")
            if parse_export(native(binary, stage, "export")) != rows:
                raise ValueError("Native round-trip comparison failed")
            source = stage / "data/ledger.sqlite3"
            with source.open("rb") as stream:
                os.fsync(stream.fileno())
            os.replace(source, target)
            directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        for path in work.joinpath("data").glob("ledger.dat*"):
            if path.is_symlink() or not path.is_file():
                raise ValueError("Unsafe legacy file")
            path.chmod(0o400)
        print(f"SQLITE_MIGRATION_OK: {len(rows)} rows compared exactly; original ISAM files retained")


def rollback(work):
    """Only for an unactivated first cutover, while the maintenance gate is held."""
    with ledger_lock(work, timeout=30):
        if not (work / "data/.deploying").is_file():
            raise ValueError("Rollback requires the maintenance gate")
        target = work / "data/ledger.sqlite3"
        if target.exists():
            with connect(work) as db:
                rows = db.execute("SELECT id,day,category,description,amount_cents FROM ledger ORDER BY id").fetchall()
                expected = db.execute("SELECT value FROM metadata WHERE key='migration_rows_sha256'").fetchone()
                if expected != (digest(rows),):
                    raise ValueError("SQLite has changed; refusing legacy rollback")
            target.unlink()
        for path in work.joinpath("data").glob("ledger.dat*"):
            if path.is_symlink():
                raise ValueError("Unsafe legacy file")
            path.chmod(0o600)
        print("Unactivated SQLite cutover reverted; legacy store preserved")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--rollback", action="store_true")
    args = parser.parse_args()
    if args.rollback:
        rollback(args.work_dir.resolve())
    elif args.binary:
        migrate(args.work_dir.resolve(), args.binary.resolve())
    else:
        parser.error("--binary is required for migration")
