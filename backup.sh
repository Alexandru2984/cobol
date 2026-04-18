#!/bin/bash
set -euo pipefail

cd /home/micu/cobol
mkdir -p data/backups

STAMP=$(date +%Y%m%d-%H%M%S)

for f in data/ledger.dat data/ledger.dat.1; do
    if [ -f "$f" ]; then
        cp "$f" "data/backups/$(basename "$f").$STAMP"
    fi
done

# Retain 7 days
find data/backups -name 'ledger.dat*' -type f -mtime +7 -delete
