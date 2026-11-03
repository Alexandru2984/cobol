# Revizuire de securitate: conturi, transferuri și obiective

Data: 2026-11-03. Aplică întrebările din skill-ul local `ciso-review` schimbărilor
din registrul personal, fără a pretinde certificarea întregului VPS.

## Model de amenințări și impact

Priorități: modificări repetate ori parțiale ale soldurilor; acces neautorizat la
conturi și obiective; epuizarea resurselor prin formulare și încărcări. Suprafața
rămâne o singură instanță personală autentificată. În cazul compromiterii complete
pot fi expuse tranzacțiile, denumirile conturilor și obiectivelor, sesiunile și
backupurile locale. Nu există integrare bancară, acces la procesatori de carduri
sau plăți reale. Costul incidentului și ALE nu sunt estimate fără date justificative.

## Măsuri și verificări înainte de activare

- Sesiunea nativă și originea/CSRF sunt verificate înaintea accesului financiar.
  Nu sunt preluate flag-uri administrative sau variabile arbitrare din HTTP.
- Nonce-urile sunt semnate și legate de sesiune și operație; același nonce cu
  valori diferite este respins. Rândurile, recipisa și auditul au același COMMIT.
- Transferurile sunt un singur obiect cu două FK-uri, sume întregi și conturi
  distincte. Alocările agregate și fondurile disponibile se verifică sub lock.
- Query-urile leagă parametri. Numele sunt limitate și escapate în HTML. Datele
  private au no-store/noindex și nu ajung în pagini publice, sitemap sau capturi reale.
- Migrations aditive cu comparație a câmpurilor financiare, integrity/FK check și
  rollback pe eroare. Release compatibil publicat înaintea migrării 2/3.
- Teste de replay, sesiuni diferite, CSRF, cereri paralele, eroare SQL și recuperarea
  unei scadențe înaintea unei tranzacții pe alt cont; browser mobil și accesibilitate.

## Detecție și răspuns

Auditul financiar este în SQLite; erorile operaționale sunt în journal și health
returnează 503 pentru stocare invalidă. Backupul zilnic verifică arhiva și baza
restaurată. Alertele externe și un MTTD măsurat nu sunt încă implementate; logurile
singure nu sunt prezentate drept alertare. Această limitare rămâne în backlog.

Runbook-ul este `OPERATIONS.md`, completat de `SQLITE.md` și `FINANCE.md`.
Exercițiul tehnic acoperă migrare eșuată fără pierderea tranzacțiilor, revenire de cod
la release compatibil, operație întreruptă înainte/după COMMIT și verificarea unui
backup după publicare. Nu este o simulare completă a unui incident organizațional.

Nu s-au stabilit un cadru de conformitate sau ferestre de notificare pentru această
instanță personală. Nu sunt inventate obligații, costuri sau evaluări legale.
Nu se adaugă furnizori cu acces la date; Cloudflare, GitHub și VPS-ul rămân traseele
existente. Nicio integrare nouă nu primește secrete sau tranzacții financiare.

Activarea este condiționată de verificările tehnice de mai sus, backup și readiness.
Autorizarea pentru continuarea și publicarea etapelor este cea din conversație.
