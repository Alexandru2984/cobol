# Stocare și migrare SQLite

Tranzacțiile sunt în `data/ledger.sqlite3`, mod 0600, application_id 1279543122,
user_version 1. Sumele sunt întregi în bani, niciodată float; ID-urile 1–999999 nu
se reutilizează după ștergere. Datele, categoriile și limitele sumelor au constrângeri
SQL. COBOL păstrează validarea, calculele, rapoartele și interfața; adaptorul C
folosește exclusiv statement-uri pregătite și parametri legați. Importurile au o
tabelă separată pentru previzualizări și confirmări idempotente.

Sesiunile, lockout-ul, bugetele, regulile și jurnalul recurentelor rămân ISAM.
Jurnalul P/D continuă să rezerve ID-uri și să recupereze tranzacțiile confirmate;
toți cititorii/scriitorii administrativi trebuie să respecte `data/.ledger.lock`.
SQLite folosește journal DELETE, synchronous FULL și busy timeout. Backup-ul ține
lock-ul pe durata verificării și copierii, include eventualul jurnal SQLite și
verifică din nou baza extrasă. O copie efectuată arbitrar în timpul scrierilor nu
este un backup verificat. Vezi și documentația oficială despre
[atomic commit](https://www.sqlite.org/atomiccommit.html) și [backup](https://www.sqlite.org/backup.html).

## Prima migrare

1. Release-ul de pregătire verifică `.deploying` și după obținerea lock-ului.
2. Deploy-ul activează poarta de mentenanță, termină recuperările deja confirmate
   cu binarul vechi și face backup verificat.
3. `migrate_store.py` ține lock-ul, citește ISAM prin binarul nativ și creează o
   bază într-un director temporar privat pe același filesystem. Compară fiecare
   ID, dată, categorie, descriere și sumă, inclusiv printr-un export nativ SQLite.
4. Verifică integritatea, face fsync și instalează atomic baza. Originalele
   `ledger.dat*` rămân identice, cu mod 0400 pentru a împiedica scrierile accidentale
   ale unui binar vechi. Activează release-ul și verifică readiness.

Repetarea migrării verifică baza existentă fără să importe din nou originalele.
Un SQLite lipsă lângă un ISAM existent sau o bază coruptă produce indisponibilitate,
fără recreare sau suprascriere. Modul administrativ `LEDGER_STORE_ADMIN` nu este
transmis niciodată de bridge-ul HTTP; accesul direct la executabil presupune deja
acces Unix la date. `LEDGER_AUTH_ONLY` este de asemenea exclusiv intern.

## Revenire și restaurare

Dacă prima activare eșuează, deploy-ul revine la ISAM numai sub poarta de mentenanță
și numai dacă hash-ul tuturor rândurilor SQLite corespunde exact migrării. Altfel
păstrează poarta și noul release pentru intervenție; nu abandonează scrieri noi.
La deploy-urile următoare revine numai la release-uri care folosesc tot SQLite.

După primele modificări în SQLite, originalele ISAM sunt istorie. Nu porni un
release ISAM și nu executa `seed` peste date. Pentru un incident: oprește serviciul,
păstrează toate fișierele curente, verifică arhiva cu `ops/verify-backup.py` și
restaurează împreună SQLite și fișierele ISAM auxiliare din același snapshot.
Restaurează proprietarul, directoare 0700 și fișiere private înainte de repornire.
O revenire la ISAM după modificări SQLite ar necesita o migrare inversă explicită,
verificată separat; simpla schimbare a symlink-ului nu este o asemenea migrare.
