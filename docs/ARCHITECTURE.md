# Persistență și evoluția produsului

## Baza de date actuală

Tranzacțiile sunt în SQLite, cu ID stabil și sume întregi în bani. Adaptorul C
leagă COBOL de SQLite; bugetele, sesiunile și jurnalul recurentelor rămân fișiere
indexate ISAM. Flask delimitează HTTP, autentifică importurile prin sesiunea nativă
și confirmă loturile CSV într-o singură tranzacție SQL. Calculele, rapoartele și
paginile principale rămân în COBOL. [Migrarea](SQLITE.md) păstrează originalele ISAM.

## Recurente și recuperare

O regulă poate fi săptămânală, lunară sau anuală. Este o previzualizare până la
confirmarea unei scadențe ajunse. Fiecare confirmare înregistrează o singură dată;
nu există un scheduler care să modifice automat registrul.

`recurring.dat` păstrează regulile, inclusiv ziua inițială și o cheie unică de creare
pentru reîncercarea aceluiași formular. Pauza și arhivarea nu șterg tranzacțiile.
`occurrences.dat` are cheie unică (regulă, scadență), index unic pe ID tranzacție și
index pe stare. O scadență confirmată trece prin:

1. rezervarea unui ID și scrierea intenției P, cu întreaga tranzacție;
2. scrierea tranzacției la ID-ul rezervat, sau verificarea că este deja aceeași;
3. marcarea intenției D și avansarea regulii.

Fișierele sunt închise între etape. Toate aceste operații folosesc lock-ul comun.
ID-urile rezervate sunt luate în calcul la adăugările manuale și la import. Înaintea altei
modificări autentificate se recuperează intențiile P; o tranzacție diferită aflată
la ID-ul rezervat oprește operația, fără suprascriere. Intențiile D se păstrează și
după ștergerea tranzacției, pentru a nu o recrea la repetarea unei cereri vechi.
Dacă procesul cade după D, repetarea confirmării avansează regula fără altă tranzacție.

Zilele 29/30/31 se limitează la ultima zi a lunii, păstrând ancora inițială pentru
lunile următoare. Datele regulilor sunt în intervalul 1601–9999, pentru compatibilitate
cu aritmetica calendaristică GnuCOBOL. Sunt testate anul bisect și trecerea între ani.

Aceasta este recuperare la nivelul aplicației între SQLite și ISAM, nu o promisiune
de tranzacții ACID între fișiere. Loturile CSV sunt atomice în SQLite. O corupere fizică impune restaurarea setului complet dintr-un
snapshot verificat. Nu combina reguli, jurnal și registru din copii făcute la momente diferite.

## Deploy și rollback

În timpul comutării, `data/.deploying` oprește POST-urile cu 503; GET-urile și health
rămân disponibile. Markerul nu intră în backup. Înainte de rollback, binarul nou
recuperează intențiile confirmate sub flock; dacă recuperarea eșuează, se păstrează
release-ul și markerul pentru investigație, în loc să pornească un writer incompatibil.
Comanda administrativă `LEDGER_RECOVER_ONLY=1 ledger.cgi`, rulată din directorul datelor
sub lock, execută doar această recuperare. Bridge-ul HTTP nu transmite acest flag sau
flag-ul de fault injection din testele CGI.

## Import CSV și evoluție

Importul leagă un draft aleator de sesiunea autentificată, verifică CSRF și stochează
privat conținutul pentru maximum 30 de minute. Maparea produce rânduri normalizate,
erori explicite și decizii privind duplicatele. Confirmarea revalidează sesiunea,
recuperează intențiile recurente, reverifică duplicatele și salvează lotul plus
rezultatul idempotent în același BEGIN IMMEDIATE / COMMIT. Dacă deciziile de omitere
s-au schimbat, utilizatorul primește o nouă previzualizare și trebuie să confirme
din nou. Orice eroare sau întrerupere înainte de COMMIT lasă zero rânduri importate.
După COMMIT, repetarea confirmării returnează rezultatul, inclusiv dacă o tranzacție
importată a fost ulterior ștearsă. Conținutul CSV este șters la confirmare; rezultatele
cu numărul de rânduri sunt păstrate 30 de zile. Curățarea drafturilor expirate are loc
la următoarea încărcare de fișier; citirea unui draft expirat îl elimină și răspunde 410.

Importul acceptă 64 KiB, 200 de rânduri și 20 de coloane; date ISO sau zi/lună/an,
zecimale cu punct sau virgulă și o categorie implicită opțională. Nu execută SQL
din fișier, formule sau plăți bancare. Fiecare cale SQL folosește parametri legați.
Conturile/transferurile și obiectivele de economisire sunt următoarele etape de produs.
PostgreSQL rămâne o opțiune pentru mai mulți writers independenți; schema actuală
este un registru personal cu writer coordonat, fără ownership pentru multi-user.

Referință pentru alegerea SQLite: https://www.sqlite.org/whentouse.html
