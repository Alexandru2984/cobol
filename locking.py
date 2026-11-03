"""Shared Unix lock for HTTP, native storage, migration and administrative tools."""
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import time


@contextmanager
def ledger_lock(work_dir, timeout=2):
    path = Path(work_dir) / "data" / ".ledger.lock"
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("ledger busy") from None
                time.sleep(0.02)
        yield
    finally:
        os.close(descriptor)
