# Verificări automate

Workflow-ul rulează la push pe main, pull request, declanșare manuală și săptămânal.
Nu are acces la secrete de producție și nu face deploy. Permisiunile GitHub sunt
limitate la citirea codului; Actions sunt fixate la SHA-uri de commit.

## Verificări

- Matrice Python 3.12 / 3.14 cu binarul COBOL compilat și teste de autentificare,
  validare, bugete, recurente, migrare SQLite 1–3, import CSV, conturi, transferuri,
  obiective, concurență/replay, recuperare, backup și rollback.
- Shellcheck, sintaxă Python/JavaScript și actionlint pentru workflow.
- Audit pip-audit al tuturor pachetelor runtime/test fixate și npm audit pentru tooling.
- Chromium cu date sintetice, la lățimi între 320 și 1440 px: login, CRUD, filtre,
  rapoarte, bugete, recurente, mapare/previzualizare/import CSV, conturi, transferuri,
  finanțarea/finalizarea obiectivelor, ghidul public, dialoguri și logout.
- Adaptorul C este verificat cu GCC `-Wall -Wextra -Werror` înaintea compilării native.
- Axe pentru reguli WCAG 2 A/AA și 2.1 AA pe fluxurile principale. Scanarea automată
  completează verificările manuale; nu constituie certificare de accesibilitate.
- Rapoarte JUnit, audit JSON, accesibilitate JSON și capturi păstrate 7 zile.

Un test de timeout folosește acum interpreterul testat (`sys.executable`), inclusiv
în imagini unde Python nu se află în `/usr/bin/python3`.

## Rulare locală

```bash
make test
shellcheck backup.sh deploy.sh run_demo.sh
npm ci --prefix tools/browser --ignore-scripts
tools/browser/node_modules/.bin/playwright install chromium
PLAYWRIGHT_MODULE="$PWD/tools/browser/node_modules/playwright" ../current/runtime/bin/python tests/run_browser.py
```

`LEDGER_CHROMIUM` poate indica un Chromium deja instalat. Pentru audit folosește
un venv separat cu `requirements-ci.txt`, apoi `pip-audit -r requirements.txt
-r requirements-dev.txt --no-deps --disable-pip`. Pentru workflow, versiunea
și checksum-ul actionlint sunt fixate în YAML.

Constantele SQL native se verifică față de fișierele de migrare înainte de compilare.
Testele SEO verifică titluri și H1 unice, canonical/OG, sitemap, legături interne și
absența numelor private de cont/obiectiv din paginile publice. Dependabot este configurat
să propună săptămânal actualizări Python/npm/GitHub Actions, fără merge automat.

Rapoartele locale sunt în `artifacts/`, ignorat de Git. Rulările GitHub apar după
publicarea commiturilor sau declanșarea workflow-ului pe versiunea publicată.
