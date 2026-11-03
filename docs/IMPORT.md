# Import CSV

După autentificare, deschide **Import CSV** din meniu. Poți descărca un fișier model.
Sunt acceptate UTF-8 cu sau fără BOM, maximum 64 KiB, 200 de tranzacții și 20 de coloane.
Fișierul trebuie să aibă antet. Nu este necesară o anumită extensie sau un anumit nume;
conținutul este verificat, iar numele primit nu este folosit pentru salvarea pe disc.

1. Alege separatorul de coloane, separatorul zecimal și formatul datei. Detectarea
   automată încearcă virgulă, punct și virgulă sau tab; poți selecta explicit.
2. Asociază coloanele pentru dată, descriere și sumă. Pentru categorie poți alege
   o coloană sau aceeași categorie implicită pentru întregul fișier.
3. Verifică fiecare rând. Datele trebuie să fie reale; descrierea are maximum
   30 bytes UTF-8, iar suma maximum 7 cifre și două zecimale, fără separatori de mii.
   De exemplu, `-125.50` sau `-125,50`, conform alegerii inițiale. Pozitiv înseamnă
   venit, negativ cheltuială; moneda este aceeași ca în registrul existent.
4. Confirmă după rezolvarea tuturor erorilor. Lotul este salvat integral sau deloc.

Duplicatele au exact aceeași dată, categorie, descriere și sumă, fie în fișier, fie
în registru. Implicit sunt omise. Pentru tranzacții legitime identice, selectează
explicit includerea duplicatelor. Se ignoră ID-urile din fișier; registrul alocă
ID-uri noi, fără coliziuni cu plățile recurente sau reutilizarea ID-urilor șterse.
Spațiile de la începutul și sfârșitul celulelor mapate sunt eliminate.

Dacă imporți propriul export Ledger, bifează opțiunea dedicată pentru a elimina
apostroful de protecție Excel din descrierile care încep cu `=`, `+`, `-` sau `@`.
Pentru alte fișiere, descrierea rămâne text și nu se execută formule.

Previzualizările sunt private și legate de sesiunea curentă. Expiră după 30 de
minute; conținutul unui draft expirat este eliminat la acces sau la următoarea
încărcare de fișier. Sunt păstrate cel mult trei drafturi în lucru per sesiune.
La confirmare, CSV-ul brut și detaliile previzualizării sunt eliminate; rămân
rezultatul și numărul de rânduri pentru 30 de zile. Sursa poate exista încă într-un
backup privat creat în timp ce draftul era activ, conform retenției backupurilor.

Repetarea confirmării aceluiași lot returnează rezultatul deja salvat. Dacă registrul
s-a schimbat între previzualizare și confirmare și se modifică rândurile de omis,
primești o previzualizare actualizată și trebuie să confirmi din nou. Încărcarea
aceluiași fișier într-un lot nou aplică din nou politica de duplicate selectată.
Interfața principală și importul necesită autentificare, CSRF și aceeași origine;
nu expun date financiare în pagina publică, sitemap sau motoare de căutare.
