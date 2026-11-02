# Audit tehnic și de securitate — 2 noiembrie 2026

## Scop și dovezi

Revizie surse COBOL/Python, teste izolate prin binarul real, configurație nginx/systemd,
headere publice și inventarul copiei locale a vechiului VPS. Fără probe distructive pe
baza de date de producție. Baseline: `4d5f13b`, 18 teste trecute.

Repo activ: `/srv/canary/cobol.micutu.com/app`, origin `Alexandru2984/cobol`.
GitHub main are același commit. Comparația rsync cu checksum față de
`/srv/ovh-migration/rootfs/home/micu/cobol` nu arată surse sau fișiere auxiliare
lipsă (excluzând Git, venv, cache și datele live). Proiectul vechi este păstrat
integral în arhiva migrării; runtime-ul nou este separat intenționat.
Scripturile și README-ul nu au fost însă adaptate căilor și serviciilor noi.
Nu există dovezi aici despre fișiere care nu au ajuns niciodată în copia migrată.

## Constatări la începutul auditului

| ID | Severitate | Problemă și impact | Acțiune |
|---|---|---|---|
| S01 | Ridicată | Credentiale implicite în COBOL; configurația absentă permite login cu secret public | Eliminare, fail closed |
| S02 | Ridicată | SHA-256 rapid, nesărat pentru parole | Suport scrypt; rotație necesară pentru parola existentă |
| S03 | Ridicată | Token temporar partajat + fallback PRNG predictibil | Entropie OS, fără shell/fallback |
| S04 | Ridicată | Lipsă CSRF; SameSite nu izolează subdomeniile aceluiași site | Token semnat legat de sesiune + Origin + Fetch Metadata |
| S05 | Ridicată | Acces ISAM fără coordonare între procese; un worker maschează problema | Lock comun cu timeout pentru request/backup |
| S06 | Ridicată | Overflow la suma individuală înainte de verificare, precizie și date calendaristice incomplete | Validare înainte de conversie, teste pentru limite |
| S07 | Medie | Prefixe de comenzi și ID-uri trunchiate; câmpuri duplicate/control/NUL | Validare strictă a cererii și a ID-urilor |
| S08 | Medie | CSV quoting fără protecție contra formulelor | Neutralizare text care începe cu = + - @ |
| S09 | Medie | Timeout omoară copilul fără reap; mediu complet transmis binarului | communicate după kill, mediu minim |
| S10 | Medie | Lipsă no-store pe pagini/date; CSP permite JavaScript inline | Headere în aplicație și CSP fără unsafe-inline pentru scripturi |
| S11 | Medie | X-Real-IP acceptat fără verificarea peer-ului | Acceptare doar de la proxy loopback configurat |
| S12 | Medie | Raport >120 luni adună lunile noi în ultima lună; totaluri prea mici | Limită explicită și sume mai largi |
| S13 | Medie | Deploy/backup din repo indică vechiul VPS; health nu verifică configurația | Scripturi actualizate + rollback + documentație |
| S14 | Medie | Fișiere financiare cu permisiuni de citire pentru alți utilizatori locali | data 0700, fișiere 0600 |
| S15 | Mică | Parsarea paginii/editării refolosește indexul buclei de query | Indici separați; teste de ordine a filtrelor |

## Limite și riscuri operaționale

Sistemul are un singur utilizator logic și un singur registru. Compromiterea sesiunii
poate expune și modifica întreg registrul financiar și jurnalul IP. Serviciul rulează
ca `micu`, identitate partajată cu alte aplicații; un cont de serviciu dedicat rămâne
necesar pentru izolare completă. Nu am auditat celelalte aplicații ale VPS-ului.
Nu se poate afirma absența tuturor vulnerabilităților dintr-o revizie punctuală.

## CISO review

Cele mai importante amenințări: spoofing (sesiune/CSRF), tampering (ISAM/concurență),
information disclosure (cache/cont Unix partajat). Impact ridicat, probabilitate medie.
Număr de persoane fizice afectate și pierderi financiare anuale: necunoscute; nu există
date pentru o estimare FAIR onestă. Vendorii existenți: VPS, Cloudflare și GitHub;
analiticele sunt găzduite pe domeniul propriu. Fără vendori noi în această etapă.
Alertele și timpul real până la detecție nu au fost demonstrate; țintă propusă: 15 minute
pentru indisponibilitate și 1 oră pentru anomalii de login. Runbook: `docs/OPERATIONS.md`.
Aspectele contractuale, obligațiile legale și procesele organizaționale nu sunt verificate
prin acest audit de cod. Verdict: remediere înainte de extinderea accesului.

## Referințe

- https://flask.palletsprojects.com/en/stable/web-security/
- https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html

## Etapa 1 implementată

S01, S03–S11 și S15 au remedieri în surse și teste de regresie. 46 teste trecute,
inclusiv scrieri concurente, token CSRF între sesiuni și reap după timeout.
Cookie-ul de sesiune folosește acum prefixul `__Host-`; sesiunile browser vechi
necesită autentificare din nou. CSRF este verificat în bridge-ul HTTP, care rămâne
singurul punct de expunere a binarului CGI. Rularea CGI directă nu este o interfață
publică suportată. S02: scrypt 131072:8:1 disponibil prin `manage.py`; hash-ul existent
nu poate fi convertit în scrypt(parola) fără parola originală, deci rotația rămâne
restantă. S14 și schimbările de nginx vor fi aplicate odată cu deploy-ul verificat.

## Etapa 2 implementată

S12: totaluri extinse la 15 cifre întregi; raportul distinge 1200 luni și refuză
explicit un interval mai mare, fără a amesteca luni sau a afișa totaluri parțiale.
Regresii pentru >1 miliard și 121 luni. Aceleași filtre se aplică listei, KPI-urilor,
raportului și exportului. Paginarea este limitată la paginile existente.
Interfața a fost verificată în Chromium la 320, 375, 390, 768 și 1440 px fără overflow
al paginii; login, adăugare/editare/ștergere, dialog, temă persistentă, rapoarte,
filtre rapide, tastatură și logout trec în browser fără erori JS/CSP în mediul izolat.
După mutații, redirect 303 previne repetarea POST-ului la refresh. Nu este o garanție
de idempotency pentru retry de rețea; aceasta rămâne o extensie separată.

## Etapa 3: operare și supply chain

Setul de pachete efectiv instalat a fost scanat cu pip-audit. A fost identificat
`GHSA-g6x2-hccm-hh4m` / `CVE-2026-102598` în Werkzeug 3.1.8. Advisory-ul privește
Windows/NTFS, deci nu demonstrează un exploit pe acest VPS Linux. Versiunea 3.1.9
este fixată și pregătită într-un venv separat. Sursa primară:
https://github.com/pallets/werkzeug/security/advisories/GHSA-g6x2-hccm-hh4m

Dependențele runtime și testele au versiuni fixate. Deploy-ul leagă codul, binarul
și mediul Python într-un singur snapshot, verifică versiunile și testează chiar
binarul pregătit pentru producție. Backup-ul coordonat prin flock este extras și
verificat, inclusiv fiecare fișier BDB; o arhivă alterată este refuzată înainte de
extragere. Scripturile trec shellcheck. Analytics injectat în paginile financiare
este eliminat și CSP pentru scripturi permite numai originea proprie.

Validare înainte de activare: 53 teste trecute în mediul Python nou; browser smoke
reproductibil trecut în același mediu; setul runtime fixat are zero vulnerabilități
cunoscute raportate de pip-audit la momentul verificării. Aceasta nu înlocuiește
reviziile viitoare și nu certifică pachetele OS sau celelalte proiecte ale VPS-ului.

## Validare în producție — 3 noiembrie, ora locală

- Release activat cu cod/binar/venv versionate; health și smoke test trecute.
- `/`, `/health`, CSS și JS: 200 pe domeniul public. `.env`: 403; fișierele ISAM și
  ruta CGI directă: 404. POST fără CSRF: 403 înainte de executarea COBOL.
- Headere no-store și CSP stricte confirmate; analytics nu mai este injectat.
- `ledger.dat` și `ledger.dat.1` au exact aceleași SHA-256 înainte și după deploy.
- Datele live au directoare 0700 și fișiere 0600; vhost-ul trece `nginx -t`.
- Rollback exercitat izolat cu readiness eșuat: codul și runtime-ul anterior restaurate.
- Backup executat prin serviciul systemd real, fără oprirea aplicației; checksum,
  extragere offline și toate cele trei fișiere ISAM prezente verificate cu succes.
- A fost corectată incompatibilitatea GNU tar/openat2 cu RestrictSUIDSGID folosind
  arhivarea Python; restricția systemd este păstrată. Testul dedicat de backup și
  detecție a alterării arhivei trece după această corecție.

Jurnalul timerului vechi avea și rulări eșuate (30 octombrie și 2 noiembrie), deși
existau copii valide mai vechi. Execuția reală a noului helper este verificată; timerul
rămâne activ zilnic. În producție, Cloudflare refuză unele cereri cu fingerprint de
client Python; smoke checks publice au folosit curl, iar protecția Cloudflare a fost
păstrată. Dovezi pentru dependențe: `docs/evidence/dependencies.json`.

## Restanțe explicite

Parola existentă este păstrată și nu coincide cu parola implicită publică eliminată
din cod. Migrarea la scrypt necesită rotație interactivă prin `manage.py`. Contul Unix
dedicat, backup-ul în afara VPS-ului și integrarea alertelor necesită etape ulterioare.
Funcțiile din etapa 4 a roadmap-ului sunt propuneri; nu sunt prezentate drept livrate.

### Ajustare Cloudflare după verificarea cu browser public

Cloudflare injecta automat beacon și JavaScript Detections, ambele blocate de CSP.
Vhost-ul transmite acum `Cache-Control: no-store, private, no-transform`, păstrând
politica pentru scripturi. Browser-ul public confirmă lipsa scripturilor injectate
și absența erorilor CSP/JavaScript. Documentația furnizorului descrie respectarea
no-transform pentru aceste injecții:
https://developers.cloudflare.com/web-analytics/faq/
https://developers.cloudflare.com/cloudflare-challenges/challenge-types/javascript-detections/

## Etapa 4.1 — bugete și tratarea indisponibilității ISAM

Bugetele sunt date suplimentare în `budgets.dat`; înregistrările tranzacțiilor și
schema lor rămân aceleași. Citirea și modificarea bugetelor folosesc același lock,
autentificare, CSRF, limite de bytes, categorii și validare decimală. Cheia combină
luna și categoria. Backup-ul verifică acum dinamic toate fișierele ISAM.

Regresii noi: separare între luni, sumarea cheltuielilor fără compensare prin
venituri, praguri și depășiri, limite invalide, calendar, autentificare/CSRF și
eliminare fără modificarea exportului tranzacțiilor. Un fișier ISAM existent care
nu poate fi deschis nu este recreat ca bază goală. Registrul indisponibil oprește
răspunsurile financiare/exporturile cu 503; un lockout store defect nu permite
downgrade la login fără protecție. Testele păstrează explicit octeții fișierelor
corupte, fără operații distructive pe datele live.

Validarea acestei etape: 74 teste automate trecute; fluxul de bugete trecut în
Chromium (salvare, actualizare, depășire, schimbare lună, eliminare și verificarea
că tranzacțiile rămân), împreună cu regresiile desktop/mobile existente. Snapshot-ul
cu bugete este extras și verificat offline. Nu au fost create bugete demo în producție.

## Etapa 4.2 — recurente

Reguli săptămânale/lunare/anuale cu previzualizare și confirmare individuală,
editare, pauză/reluare și arhivare. Cheia de creare împiedică repetarea aceluiași
formular. Un jurnal de intenții rezervă ID-ul înainte de scriere și păstrează
scadențele finalizate inclusiv după ștergerea tranzacției. Testele injectează
întreruperi după rezervare, după scriere și după finalizare; reîncercarea și o altă
modificare recuperează fără duplicate. Detalii și limite: `ARCHITECTURE.md`.

Validare: 88 teste pentru aplicație și snapshot-uri, plus două exerciții izolate de
rollback (recuperare reușită și recuperare refuzată). Browser-ul verifică desktop și
mobil, crearea/editarea regulii, confirmarea, replay, pauză/reluare și arhivarea.
POST-urile sunt suspendate numai în timpul comutării release-ului; markerul tranzitoriu
este exclus din backup. Flag-urile administrative/de test nu sunt transmise prin HTTP.
