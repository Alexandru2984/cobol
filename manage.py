#!/usr/bin/env python3
"""Provision credentials interactively; never accept a password in argv."""
import getpass
import os
from pathlib import Path
import secrets
import tempfile

from werkzeug.security import generate_password_hash


def main():
    password = getpass.getpass("Parola noua (12-40 bytes UTF-8): ")
    if not 12 <= len(password.encode("utf-8")) <= 40:
        raise SystemExit("Parola trebuie sa aiba intre 12 si 40 bytes UTF-8.")
    if any(ord(char) < 32 or ord(char) == 127 for char in password):
        raise SystemExit("Parola contine caractere de control.")
    if password != getpass.getpass("Confirma parola: "):
        raise SystemExit("Parolele nu coincid.")
    path = Path(__file__).resolve().parent / ".env"
    lines = path.read_text().splitlines() if path.exists() else ["LEDGER_USER=micu"]
    lines = [line for line in lines if not line.startswith((
        "LEDGER_PASS=", "LEDGER_PASS_HASH=", "LEDGER_PASSWORD_HASH="))]
    lines.append("LEDGER_PASSWORD_HASH=" + generate_password_hash(password, method="scrypt:131072:8:1"))
    if not any(line.startswith("LEDGER_CSRF_SECRET=") for line in lines):
        lines.append("LEDGER_CSRF_SECRET=" + secrets.token_hex(32))
    descriptor, name = tempfile.mkstemp(prefix=".env-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write("\n".join(lines) + "\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    print("Credentiale scrypt salvate in .env (0600). Reporneste serviciul pentru activare.")
    print("Pentru revocarea sesiunilor existente, urmeaza docs/OPERATIONS.md.")


if __name__ == "__main__":
    main()
