# Ledger of Ages

Personal finance in COBOL: an ISAM ledger with a responsive web interface,
filtered reports and CSV export.
Public presentation: [cobol.micutu.com/about](https://cobol.micutu.com/about). Live at [cobol.micutu.com](https://cobol.micutu.com).

The transaction engine, validation, sessions, audit and reports run in GnuCOBOL.
Flask provides the HTTP/CGI security boundary; scrypt verification uses Werkzeug.
No database service, CDN fonts or JavaScript framework is required.

## Features

- Add, edit and delete transactions with confirmation and redirect after saving.
- Income, expenses, net balance, savings rate and category summaries.
- Weekly/monthly/yearly recurring plans, previews, pause/resume and occurrence deduplication.
- Monthly expense budgets with category limits, progress, alerts and month navigation.
- Description search, category/type/date filters, four sort orders and pagination.
- Quick date ranges, monthly reports sharing the active filters, CSV export.
- Mobile transaction cards, light/dark theme, keyboard shortcuts, print layout.
- Server-side expiring sessions, lockout, signed session-bound CSRF, secure host cookies.
- Strict byte limits and calendar/decimal validation; spreadsheet formula protection.
- Shared ISAM locking, private responses, strict script CSP, isolated regression tests.
- Atomic code releases, health/smoke checks, rollback and verified snapshots.

## Develop

```bash
sudo apt install gnucobol python3-venv db5.3-util
python3 -m venv venv
venv/bin/pip install -r requirements.txt -r requirements-dev.txt
make build
mkdir -m 700 -p data
venv/bin/python manage.py   # interactive password + persistent CSRF secret
set -a
source .env                # generated scrypt value is quoted
set +a
export LEDGER_PUBLIC_ORIGIN=http://127.0.0.1:5000
venv/bin/python app.py
```

Production cookies require HTTPS; Chromium treats loopback as a secure development
context. For other hosts, use local HTTPS. `./run_demo.sh` builds demo data in a disposable
directory; `./seed` refuses to overwrite an existing ledger unless explicitly forced.
`make test` compiles its own binary and keeps all test data outside production.

## Production and audit

The repository is in `app/`; the active snapshot is `../current`, and persistent data
stays in `app/data/`. Cloudflare and nginx proxy to loopback gunicorn. `./deploy.sh`
compiles, tests, backs up, switches releases and verifies readiness, with rollback.

Read [operations and incident response](docs/OPERATIONS.md), the
[security audit and migration findings](docs/AUDIT.md), and the
[product roadmap](docs/ROADMAP.md) before provisioning a new instance.
Templates in `ops/` describe this VPS and depend on its global nginx Cloudflare maps.
No credentials, financial data or personal session tokens are tracked in Git.

The current legacy SHA-256 password remains supported to preserve access. Rotate it
with `manage.py` to enable scrypt; SHA-256 alone is unsuitable for password storage.
A dedicated Unix service identity, offsite backups, connected alerts and stronger
login factors remain planned work; this audit does not certify the whole VPS.

Optional browser verification: install Playwright + Chromium in a tooling environment,
then run `venv/bin/python tests/run_browser.py`. The runner creates disposable data,
starts a loopback server and checks desktop/mobile workflows. Screenshots are saved in
ignored `artifacts/`. `PLAYWRIGHT_MODULE` and `LEDGER_CHROMIUM` can point to existing tools.


[Continuous checks](docs/CI.md) cover two Python versions, browser workflows,
accessibility and dependency audits. Public discovery uses `/about`, canonical and
social metadata, `/robots.txt` and `/sitemap.xml`. Private ledger pages retain noindex.
