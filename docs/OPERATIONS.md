# Operare, restaurare și incidente

## Instanța curentă

- Repo: `/srv/canary/cobol.micutu.com/app`, GitHub `Alexandru2984/cobol`.
- Cod activ și binar: symlink atomic `../current` spre un folder din `../releases`.
- Date: `app/data/ledger.sqlite3` pentru tranzacții; originalele ISAM sunt păstrate numai pentru arhivă, mod 0400.
- Bugete: `data/budgets.dat`, cheie lună + categorie, creat la prima salvare.
  Backup-ul verifică toate fișierele `*.dat*`, inclusiv fișierele noi.
- Conturi, transferuri, obiective, alocări și recipise: în același SQLite, schema 3.
  `upgrade_store.py` aplică migrările aditive sub lock după backup și înainte de activare.
  Rollback-ul acestei etape cere release-ul de compatibilitate `c2055db` sau mai nou.
- Python: `../current/runtime` pointează spre mediul versionat al release-ului; serviciu: `cobol-canary.service`, loopback port 9001.
- Traseu verificat: Cloudflare → vhost nginx → gunicorn → binar COBOL → SQLite / ISAM.
  Mai există nginx-uri pentru alte aplicații; nu sunt un al doilea backend al acestui proiect.
  Configurația remote a tunelului Cloudflare nu este versionată aici.
- `ops/nginx.conf` depinde de zonele globale `cobol_limit` și `from_cloudflare_origin`.
- Datele și fișierele `.env` nu intră în Git, release sau screenshot-uri de test.

## Configurație

`EnvironmentFile=app/.env`, mod 0600. Variabile suportate:

| Variabilă | Rol |
|---|---|
| `LEDGER_USER` | Utilizator, cel mult 40 bytes; implicit `micu` |
| `LEDGER_PASSWORD_HASH` | scrypt 131072:8:1, preferat; generat prin `manage.py` |
| `LEDGER_PASS_HASH` | SHA-256 legacy; necesită rotație pentru migrare la scrypt |
| `LEDGER_PASS` | Compatibilitate/dezvoltare; fără parolă implicită |
| `LEDGER_CSRF_SECRET` | Secret aleator de cel puțin 32 caractere, persistent |
| `LEDGER_SESSION_TTL` | 1–86400 secunde; implicit 28800 |
| `LEDGER_PUBLIC_ORIGIN` | Implicit `https://cobol.micutu.com`; explicit pentru dezvoltare |
| `LEDGER_TRUSTED_HOSTS` | Hosturi separate prin virgulă; implicit domeniul și loopback |
| `LEDGER_TRUSTED_PROXIES` | CIDR-uri; implicit doar loopback; nginx suprascrie X-Real-IP |
| `LEDGER_TIMEZONE` | Ziua formularului; implicit Europe/Bucharest; sesiunile și auditul folosesc UTC |

Nu transmite parola în argv sau într-un URL. `../current/runtime/bin/python manage.py`
solicită parola fără afișare, salvează scrypt în `.env` atomic și păstrează permisiuni 0600.
Schimbarea parolei necesită restart. Pentru revocare globală: oprește serviciul,
fă backup, mută `data/sessions.dat*` într-un director privat în afara `data/`, schimbă
parola și secretul CSRF, apoi pornește serviciul. Nu șterge registrul financiar.
CGI trebuie expus exclusiv prin bridge-ul Flask, care verifică CSRF și limitele HTTP.

## Deploy

`./deploy.sh` cere repo curat, `../releases` și `../current` provisionate. Compilează
într-un release nou, rulează toate testele izolat, face backup verificat, schimbă
symlink-ul atomic, repornește serviciul și verifică health + formularul cu CSRF.
Dacă readiness sau smoke check eșuează, revine automat la release-ul anterior.
Datele nu se restaurează la rollback de cod. Prima migrare SQLite verifică toate rândurile și poate reveni automat numai cât timp registrul migrat nu a fost modificat. După activare, rollback-ul de cod trebuie să folosească un release compatibil SQLite; vezi [procedura de migrare](SQLITE.md).
Configurațiile systemd/nginx se instalează separat, cu backup al configurației precedente,
`systemd-analyze verify` / `nginx -t` și apoi reload. Dependențele Python se pregătesc într-un mediu separat, cu versiunile fixate în requirements.
`LEDGER_RUNTIME_ENV=/cale/catre/venv ./deploy.sh` leagă mediul de noul release; scriptul
verifică versiunile instalate. Rollback-ul symlink-ului readuce și mediul anterior. Nu șterge release-ul anterior până după validare.

Provisionarea inițială folosește un snapshot al commitului anterior și binarul vechi în
`releases/baseline-*`, cu `runtime` spre vechiul venv; apoi `releases/current` indică acel snapshot și `../current` indică `releases/current`.
Primul deploy folosește helperul vechi de backup (oprește serviciul), până când toate
cererile live trec prin noul lock. Helperul nou se instalează după activarea noului release. Nu folosi un symlink spre
checkout-ul de lucru: un edit în repo nu trebuie să schimbe codul servit.

Rollback manual, înlocuind calea cu un release anterior verificat și compatibil SQLite:

```bash
ln -s /srv/canary/cobol.micutu.com/releases/RELEASE_ANTERIOR ../releases/.current-next
mv -Tf ../releases/.current-next ../releases/current
sudo systemctl restart cobol-canary.service
curl --fail http://127.0.0.1:9001/health
```

## Backup și restaurare

Timerul `cobol-ledger-backup.timer` rulează zilnic la 03:05 UTC, cu jitter de până la
5 minute. Helperul root-owned `/usr/local/sbin/cobol-ledger-backup` este instalat din
`backup.sh`. Folosește același flock ca aplicația, verifică BDB, creează arhiva cu
ledger/index/sesiuni/lockout/audit, apoi extrage și verifică din nou. Nu oprește site-ul. Serviciul root are doar CAP_DAC_OVERRIDE/CAP_CHOWN pentru citirea
fișierelor private și owner-ul lock-ului; sandbox-ul permite scriere numai în data/
și directorul de backup, iar familia de socket-uri este limitată la AF_UNIX.
Arhivarea folosește tarfile din Python pentru compatibilitate cu RestrictSUIDSGID;
GNU tar de pe acest VPS cere openat2, refuzat de acel sandbox.
Backup-urile sunt private în `/srv/backups/cobol-ledger`, retenție 14 zile. Lock-ul activ
și backup-urile vechi nu intră în arhivă. `.env` și configurațiile se salvează separat,
cu acces restrâns. Un backup pe același VPS nu asigură recuperarea dacă VPS-ul este pierdut.

```bash
sudo systemctl start cobol-ledger-backup.service
sudo journalctl -u cobol-ledger-backup.service -n 15 --no-pager
sudo /srv/canary/cobol.micutu.com/current/runtime/bin/python ops/verify-backup.py /srv/backups/cobol-ledger/ARHIVA.tar.gz
```

Restaurare reală: oprește serviciul, păstrează o copie a datelor curente, verifică checksum
și arhiva offline, restaurează într-un director nou (fără symlink-uri), verifică fiecare
fișier BDB și apoi înlocuiește întreg setul ISAM împreună. Reaplică owner `micu`, mod 0700
pentru director / 0600 pentru fișiere. Nu combina `ledger.dat` dintr-o dată cu
`ledger.dat.1` din alta. Revocă sesiunile vechi, pornește serviciul, verifică health și
compară exportul cu copia restaurată. Nu a fost efectuată o restaurare peste datele live.

## Detecție și răspuns

Comenzi utile: `journalctl -u cobol-canary`, `/health`, jurnalul din aplicație și
`systemctl list-timers cobol-ledger-backup.timer`. Erorile bridge-ului au X-Request-ID,
fără parole sau corpuri POST în log. Jurnalul financiar nu este imuabil și nu poate
ține locul unui sistem extern de detecție.

Reguli propuse pentru monitorul existent (conectarea alertelor rămâne restantă):
health non-200 de două ori / minut; backup mai vechi de 26h; orice backend_timeout sau
backend_failed; cinci LOGIN-FAIL în 15 minute și orice LOCKOUT. Destinatar: administratorul
VPS-ului. MTTD măsurat nu este disponibil; nu pretindem alerte funcționale fără integrare.

La suspiciune de compromitere:

1. Restricționează accesul la vhost sau oprește doar `cobol-canary`; păstrează logurile,
   configurația, commitul și o copie privată a datelor. Nu șterge dovezile.
2. Stabilește dacă e afectată sesiunea, parola, codul sau contul Unix. Deoarece `micu`
   este partajat, investighează și procesele aceluiași utilizator înainte de redeschidere.
3. Dintr-un mediu de încredere, schimbă parola și secretul CSRF și revocă sesiunile.
4. Revino la release verificat; restaurează date numai dacă există dovezi de modificări
   neautorizate și o copie validă. Compară exporturi, număr de înregistrări și audit.
5. Verifică health, fluxul de login, permisiunile și backup-ul; documentează incidentul
   și evaluează cu persoana responsabilă obligațiile de notificare aplicabile.

Exercițiu efectuat în mediu izolat: token absent/reutilizat între sesiuni refuzat,
cereri concurente păstrate, proces blocat oprit și reap, CRUD/export verificate în browser.
Verificarea restaurării offline este descrisă mai sus; răspunsul organizațional și
notificările către utilizatori nu au fost simulate.

## Recurente

`recurring.dat` și `occurrences.dat` (plus indexurile lor `.dat.*`) se salvează și se
restaurează împreună cu registrul. Confirmați fiecare scadență din interfață; nu există
un job care să înregistreze automat bani. Descrierea recuperării și a rollback-ului
este în `docs/ARCHITECTURE.md`. Nu ștergeți jurnalul de scadențe pentru a curăța lista.
Arhivați regula din UI. Backup-ul verifică dinamic toate fișierele ISAM.
