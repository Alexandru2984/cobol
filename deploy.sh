#!/bin/bash
# Deploy: compileaza, ruleaza testele, instaleaza binarele atomic,
# reporneste serviciul si verifica health endpoint-ul.
set -euo pipefail
cd "$(dirname "$0")"

echo "1/5 Compilare..."
cobc -x -free ledger.cbl -o ledger.cgi.new
cobc -x -free seed.cbl -o seed.new

echo "2/5 Teste (binar compilat separat, date izolate)..."
venv/bin/python -m pytest tests/ -q

echo "3/5 Instalare binare..."
mv ledger.cgi.new ledger.cgi
mv seed.new seed

echo "4/5 Restart serviciu..."
sudo systemctl restart cobol.service
sleep 1

echo "5/5 Verificare health..."
curl -sf http://127.0.0.1:9001/health
echo
echo "Deploy OK."
