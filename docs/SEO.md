# Descoperire publică și confidențialitate

`/about` prezintă produsul, iar `/guide` explică tranzacțiile, conturile, transferurile,
obiectivele, CSV-ul și planificarea, numai cu exemple demonstrative. Ambele rămân
independente de autentificare și baza financiară. Titlurile, descrierile și H1 sunt
distincte; canonical și OG folosesc originea configurată, nu Host sau parametri UTM.
Fragmentele de metadata sunt partajate pentru a evita diferențe între pagini.

Sitemap-ul listează exclusiv aceste două pagini. Redirecturile finale cu slash sunt
308 spre varianta canonical. OG/Twitter folosesc imaginea existentă 1200×630, iar
microdata descrie aplicația fără ratinguri, recenzii sau prețuri inventate.

Paginile private, exporturile și erorile păstrează `X-Robots-Tag: noindex, nofollow`
și no-store. Conturile, obiectivele și tranzacțiile nu ajung în metadata sau sitemap.
Robots.txt nu înlocuiește autentificarea și nu este tratat ca mecanism de securitate.
Nu blocăm citirea paginilor care trebuie să poată prezenta instrucțiunea noindex;
vezi [documentația Google](https://developers.google.com/search/docs/crawling-indexing/block-indexing).

Testele verifică aceste reguli și legăturile interne; browserul verifică ghidul pe
mobil și accesibilitatea automată. Implementarea urmează principiile de conținut
util din [ghidul Google](https://developers.google.com/search/docs/fundamentals/seo-starter-guide).
Search Console nu a fost conectat și nu s-au trimis verificări DNS, cereri de indexare
sau date private către servicii SEO. Indexarea și pozițiile nu sunt garantate de
metadata; ele se observă ulterior prin instrumentele proprietarului domeniului.
