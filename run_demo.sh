#!/bin/bash
echo "=== LEDGER OF AGES DEMO ==="
echo "1. Curatare date vechi..."
rm -f data/ledger.dat

echo "2. Compilare Seed (Populare ISAM)..."
cobc -x -free seed.cbl -o seed

echo "3. Compilare Ledger (Core logic)..."
cobc -x -free ledger.cbl -o ledger.cgi

echo "4. Executie Populare Baza de Date..."
./seed

echo "5. Generare Raport Web (COBOL CGI Output)..."
echo "------------------------------------------------"
./ledger.cgi
echo "------------------------------------------------"
echo "DEMO COMPLET."
