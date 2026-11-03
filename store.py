"""Typed access to the transaction store shared with the native COBOL adapter."""
from contextlib import contextmanager
from pathlib import Path
import sqlite3
import stat

APPLICATION_ID = 1279543122
CATEGORIES = {"Venituri", "Locuinta", "Mancare", "Hobby", "Utilitati"}


@contextmanager
def connect(work_dir):
    path = Path(work_dir) / "data/ledger.sqlite3"
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise sqlite3.DatabaseError("Unsafe database file")
    connection = sqlite3.connect(path.as_uri() + "?mode=rw", uri=True, timeout=1,
                                 isolation_level=None)
    try:
        connection.setlimit(sqlite3.SQLITE_LIMIT_LENGTH, 1024 * 1024)
        connection.setlimit(sqlite3.SQLITE_LIMIT_ATTACHED, 0)
        connection.enable_load_extension(False)
        connection.execute("PRAGMA trusted_schema=OFF")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA synchronous=FULL")
        if connection.execute("PRAGMA application_id").fetchone()[0] != APPLICATION_ID or (
                connection.execute("PRAGMA user_version").fetchone()[0] != 1):
            raise sqlite3.DatabaseError("Unsupported ledger schema")
        yield connection
    finally:
        if connection.in_transaction:
            connection.rollback()
        connection.close()
