# Conturi, transferuri și versiuni de stocare

Schema 2 adaugă `accounts`, `transfers`, `finance_requests` și `finance_events`.
Toate tranzacțiile existente primesc `account_id=1`, Registru principal, sold inițial
zero. ID-urile, datele, descrierile și sumele istorice rămân identice. Fișierele SQL
din `migrations/` sunt sursa comună pentru upgrade și constantele native generate;
`python3 ops/generate-schema.py --check` detectează diferențele dintre ele.

Soldul unui cont este sold inițial + tranzacții + transferuri primite − transferuri
trimise, fără transferurile anulate. Soldul inițial nu este venit. Un transfer este
un singur rând cu două referințe de cont și nu apare în registrul de venituri și
cheltuieli, rapoartele pe categorii sau bugete. Transferurile nu execută plăți bancare.
Toate conturile folosesc moneda registrului existent; nu există schimb valutar implicit.

Conturile se redenumesc și se arhivează; nu se șterg împreună cu istoricul. Contul
principal rămâne activ pentru plățile recurente. Acestea folosesc contul principal;
o tranzacție deja înregistrată poate fi mutată prin editare. Recuperarea unei scadențe
nu preia contul unei alte tranzacții introduse în aceeași cerere. CSV-ul primește un
cont destinație explicit, iar duplicatele sunt verificate în acel cont. Exportul
CSV respectă filtrul de cont; pentru restaurarea completă se folosesc backupurile SQL.

Confirmările de cont/transfer folosesc, pe lângă CSRF, un nonce semnat, legat de
sesiune și operație. Datele, rezultatul și evenimentul de audit sunt salvate în
același BEGIN IMMEDIATE / COMMIT. Repetarea aceleiași cereri returnează rezultatul
salvat, inclusiv după anularea transferului. Alte valori cu același nonce sunt
respinse. Corecțiile transferurilor folosesc anulare și o operație nouă, păstrând
istoricul. Anularea este refuzată dacă suma nu mai este disponibilă la destinație.

Migrarea rulează sub `.ledger.lock` și poarta de mentenanță, după backup. Pentru
ADD COLUMN cu FK și default nenul, verificarea FK este suspendată numai pe conexiunea
de migrare, în afara tranzacției; înainte de COMMIT se verifică toate referințele,
integritatea și hash-ul câmpurilor financiare originale. Vezi documentația oficială
[ALTER TABLE](https://www.sqlite.org/lang_altertable.html) și
[foreign keys](https://www.sqlite.org/foreignkeys.html).

Release-ul de compatibilitate `c2055db` acceptă schemele aditive 1–3. După upgrade,
rollback-ul de cod folosește acest release sau unul mai nou; originalele ISAM și
release-urile SQLite care acceptă numai versiunea 1 nu sunt alternative de rollback.
Datele noi rămân în bază la revenirea de cod. Backupul și restaurarea includ întregul
set SQLite/ISAM, verificat împreună. Nu se combină fișiere din momente diferite.
