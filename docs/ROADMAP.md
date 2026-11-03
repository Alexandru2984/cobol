# Plan de produs — Ledger of Ages

## Etapa 1: fundație sigură

Închidere S01–S11, S14–S15, regresii automate prin COBOL real, păstrarea formatului
ISAM și a datelor. Parole scrypt disponibile fără schimbarea forțată a parolei existente.
Fără introducerea unor servicii externe.

## Etapa 2: experiență utilizabilă zilnic

Interfață responsive cu navigare clară, formulare etichetate, contrast și focus vizibil,
carduri mobile pentru tranzacții, temă luminoasă/întunecată, stare goală utilă,
confirmare la ștergere, indicatori venituri/cheltuieli/net și rată de economisire,
filtru venituri/cheltuieli, intervale rapide, filtre păstrate în rapoarte și export,
sortare cronologică inversă, scurtături de tastatură, imprimare și feedback la salvare.
Corectarea limitelor raportului lunar și testare desktop/mobile cu browser real.

## Etapa 3: operare reproductibilă

Scripturi de backup/deploy/rollback adaptate runtime-ului, configurații de producție
versionate fără secrete, verificare backup și integritate ISAM, runbook de incidente,
health și smoke checks pe domeniul public. Commit distinct după fiecare etapă.

## Etapa 4: extinderi propuse, în ordinea utilității

1. Import CSV cu mapare, validare, previzualizare și rollback integral.
2. Conturi multiple, transferuri și reconciliere sold bancar.
3. Categorii editabile, etichete și reguli automate de clasificare.
4. Obiective de economisire și prognoză de cash flow.
5. Comparații lună/an, distribuția cheltuielilor și raport anual exportabil.
6. Gestionarea sesiunilor active și revocare globală; TOTP/passkeys.
7. Istoric de modificări și recuperare tranzacții șterse.
8. Monede multiple cu rată explicită, fără conversii ascunse.
9. Export JSON și API autentificat, cu permisiuni separate.
10. PWA instalabilă; cache doar pentru assets, niciodată date financiare.
11. Cont Unix dedicat, directoare release și backup criptat în afara VPS-ului.
12. Alerte efective pentru erori, login suspect, spațiu disc și backup expirat.
13. Documentație utilizator, demo public izolat și teste de accesibilitate.

Etapa 4 este backlog, nu funcționalitate livrată. Funcțiile care schimbă schema ISAM
necesită migrare versionată și test de restaurare înainte de activare. Multi-user
necesită model de ownership, autorizare pe fiecare obiect și teste de izolare.

## Livrat în etapele 1–2

CSRF semnat, cookie `__Host-`, entropie OS, validare strictă, serializare ISAM,
protecție CSV și scrypt opțional. UI responsive, temă persistentă, KPI-uri și rată
de economisire, filtrare venit/cheltuială, patru sortări, intervale rapide,
rapoarte filtrate, carduri pe mobil, confirmare accesibilă, scurtături, print,
stări goale, feedback și redirect după salvare. Data formularului folosește
Europe/Bucharest; expirarea sesiunilor se calculează în UTC.

Etapa 3 este activă în producție: releases cu runtime asociat, rollback verificat,
backup cu flock și probă de restaurare offline, configurații versionate și runbook.
Urmează prioritar: rotație scrypt, identitate Unix dedicată, copie offsite/alerte,
apoi recurente și import CSV cu previzualizare.


## Etapa 4.1 livrată: bugete lunare

Limite pe cele patru categorii de cheltuieli, progres și avertizare la 80% / depășire,
planificat/cheltuit/disponibil/fără buget, navigare între luni, modificare și eliminare
cu confirmare. Stocare ISAM separată și inclusă în backup. Veniturile nu se scad din
cheltuielile urmărite. Eliminarea unei limite nu modifică tranzacțiile.


## Etapa 4.2 livrată: recurente

Salariu, chirie și abonamente săptămânale/lunare/anuale; previzualizare, editare,
pauză/reluare și arhivare. Înregistrare explicită a scadenței cu rezervare de ID,
jurnal de recuperare și protecție la repetarea cererii. Vezi `ARCHITECTURE.md` pentru
persistență, limite și criteriile unei migrări SQLite.


## Etapa 5 livrată: CI și prezentare publică

Matrice Python 3.12/3.14, audit Python/npm, verificări de sintaxă și workflow,
Chromium desktop/mobile, scanare automată de accesibilitate și rapoarte de depanare.
Pagina `/about` prezintă funcțiile cu date demonstrative; canonical, Open Graph,
Twitter Card, imagine socială, sitemap și robots pentru descoperire. Registrul,
rapoartele, bugetele și recurentele rămân autentificate și noindex.

## Etapa 6 livrată: SQLite și import CSV

Migrare verificată rând cu rând, sume în bani și păstrarea originalelor. Import CSV
cu maparea coloanelor, formate de dată/sumă, categorie implicită, erori pe rând,
duplicate din fișier și registru, confirmare atomică și reîncercare idempotentă.
Previzualizare cu carduri pe mobil, temă luminoasă/întunecată și rezultate ale
importurilor din sesiunea curentă. Teste de întrerupere de proces înainte/după COMMIT,
cereri paralele, rollback, sesiuni, CSRF și verificări reale în Chromium/Axe.

Urmează: conturi numerar/card și transferuri care nu umflă veniturile sau cheltuielile;
apoi obiective de economisire cu progres și contribuții. Fiecare are migrare versionată,
validarea soldurilor și commit separat. CI și SEO continuă să acopere funcțiile livrate.
