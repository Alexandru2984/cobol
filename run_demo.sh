#!/bin/bash
# Compileaza si ruleaza demo-ul intr-un director temporar,
# fara sa atinga baza de date reala din data/.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(mktemp -d /tmp/ledger-demo.XXXXXX)"
trap 'rm -rf "$DEMO_DIR"' EXIT

echo "=== LEDGER OF AGES DEMO (sandbox: $DEMO_DIR) ==="
mkdir -p "$DEMO_DIR/data"
cd "$DEMO_DIR"

echo "1. Compilare Seed (Populare ISAM)..."
cobc -x -free "$SRC_DIR/seed.cbl" -o seed

echo "2. Compilare Ledger (Core logic)..."
cobc -x -free "$SRC_DIR/ledger.cbl" "$SRC_DIR/sha256.cbl" -o ledger.cgi

echo "3. Executie Populare Baza de Date..."
./seed

echo "4. Generare Raport Web (COBOL CGI Output)..."
echo "------------------------------------------------"
REQUEST_METHOD=GET QUERY_STRING="" HTTP_COOKIE="" ./ledger.cgi
echo "------------------------------------------------"
echo "DEMO COMPLET."
