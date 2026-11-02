# Descoperire publică și limitele indexării

`/about` este pagina publică de prezentare, cu informații despre funcțiile efectiv
livrate și exemple demonstrative. Nu interoghează binarul COBOL sau baza de date și
rămâne identică inclusiv când vizitatorul este autentificat.

Are titlu și descriere proprii, canonical fără query string, Open Graph, Twitter
Card și imagine PNG 1200×630. Marcajul SoftwareApplication descrie aplicația, fără
ratinguri, recenzii sau oferte inventate. Nu promitem eligibilitate pentru rich results.

Sitemap-ul conține numai URL-ul public canonical. `robots.txt` permite citirea paginilor
pentru ca motoarele să poată observa directivele noindex ale registrului și exclude
rutele de sănătate/date. Vhost-ul folosește robots.txt din aplicație, separat de cel
comun celorlalte domenii de pe VPS.

Doar pagina publică și imaginea sa de distribuire primesc `X-Robots-Tag: index, follow`.
Login-ul, paginile financiare, health și erorile rămân noindex. Autentificarea protejează
datele; noindex controlează doar descoperirea în motoarele care respectă această directivă.
Headerele no-store/no-transform și politica CSP rămân active pe domeniu.

Imaginea socială se regenerează din `tools/social-card.html` cu
`node tools/render_social_card.cjs` după instalarea tooling-ului din `tools/browser`.
Nu folosește capturi sau valori din registrul real.

Teste: metadate și canonical, redirect, sitemap/robots, dimensiunile imaginii, separarea
datelor private, neexecutarea backend-ului pe pagina publică, viewport 320–1440 și Axe.
Indexarea și poziția în căutări nu au fost măsurate. Search Console și trimiterea
sitemap-ului nu au fost configurate în această etapă.

Surse primare:
- https://developers.google.com/search/docs/crawling-indexing/block-indexing
- https://developers.google.com/search/docs/appearance/structured-data/software-app
