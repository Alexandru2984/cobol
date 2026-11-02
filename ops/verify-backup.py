#!/usr/bin/env python3
"""Offline restore drill: verify checksum, extract safely, verify every ISAM file."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("archive", type=Path)
args = parser.parse_args()
archive = args.archive.resolve(strict=True)
expected = Path(str(archive) + ".sha256").read_text().split()[0]
if not re.fullmatch(r"[0-9a-f]{64}", expected):
    raise SystemExit("Invalid checksum file")
with archive.open("rb") as stream:
    actual = hashlib.file_digest(stream, "sha256").hexdigest()
if actual != expected:
    raise SystemExit("Checksum mismatch")
with tempfile.TemporaryDirectory(prefix="ledger-restore-check-") as scratch:
    with tarfile.open(archive) as source:
        members = source.getmembers()
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "data":
                raise SystemExit("Unexpected archive path")
            if not (member.isfile() or member.isdir()):
                raise SystemExit("Links/devices are not accepted")
        source.extractall(scratch, filter="data")
    files = sorted((Path(scratch) / "data").glob("*.dat*"))
    if not (Path(scratch) / "data" / "ledger.dat").is_file():
        raise SystemExit("Ledger missing from backup")
    for path in files:
        subprocess.run(["db5.3_verify", "-q", str(path)], check=True)
    print(f"RESTORE_CHECK_OK: checksum and {len(files)} ISAM files verified; production untouched")
