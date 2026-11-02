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
