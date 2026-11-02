# Persistență și evoluția produsului

## Baza de date actuală

ISAM este o bază de date indexată: registrul are cheie ID
și index secundar de dată. Flask delimitează HTTP și pornește COBOL; calculele,
validarea financiară, sesiunile și paginile registrului rămân în COBOL.
În această etapă se adaugă fișiere separate pentru recurente; schema tranzacțiilor
și valorile existente nu sunt migrate sau rescrise.

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
ID-urile rezervate sunt luate în calcul și la adăugările manuale. Înaintea altei
modificări autentificate se recuperează intențiile P; o tranzacție diferită aflată
la ID-ul rezervat oprește operația, fără suprascriere. Intențiile D se păstrează și
după ștergerea tranzacției, pentru a nu o recrea la repetarea unei cereri vechi.
Dacă procesul cade după D, repetarea confirmării avansează regula fără altă tranzacție.

Zilele 29/30/31 se limitează la ultima zi a lunii, păstrând ancora inițială pentru
lunile următoare. Datele regulilor sunt în intervalul 1601–9999, pentru compatibilitate
cu aritmetica calendaristică GnuCOBOL. Sunt testate anul bisect și trecerea între ani.

Aceasta este recuperare la nivelul aplicației peste ISAM, nu o promisiune de tranzacții
ACID între fișiere. O corupere fizică impune restaurarea setului complet dintr-un
snapshot verificat. Nu combina reguli, jurnal și registru din copii făcute la momente diferite.

## Deploy și rollback

În timpul comutării, `data/.deploying` oprește POST-urile cu 503; GET-urile și health
rămân disponibile. Markerul nu intră în backup. Înainte de rollback, binarul nou
recuperează intențiile confirmate sub flock; dacă recuperarea eșuează, se păstrează
release-ul și markerul pentru investigație, în loc să pornească un writer incompatibil.
Comanda administrativă `LEDGER_RECOVER_ONLY=1 ledger.cgi`, rulată din directorul datelor
sub lock, execută doar această recuperare. Bridge-ul HTTP nu transmite acest flag sau
flag-ul de fault injection din testele CGI.

## Când trecem la SQLite

Pentru importuri în lot cu rollback integral, conturi multiple și autorizare pe obiect,
SQLite este următorul candidat: tranzacții SQL, constrângeri și un format local fără
un serviciu nou de administrat. PostgreSQL devine relevant dacă produsul ajunge la
mai mulți utilizatori și writers independenți. SQLite se potrivește etapelor cu un singur VPS și writer coordonat.

Migrarea va avea o etapă separată: schemă versionată, export ISAM izolat, încărcare cu
ID-uri și sume în cenți păstrate, comparație rând cu rând și pe totaluri, test de
restaurare și regulă explicită pentru rollback după apariția unor scrieri noi. CI și
SEO nu depind de această migrare.

Referință pentru alegerea SQLite: https://www.sqlite.org/whentouse.html
