# 📜 The Ledger of Ages

O aplicație web (CGI) scrisă în **COBOL pur**, folosind baze de date indexate (**ISAM**) și standardul CGI pentru generarea interfeței.

---

## 🛠️ Stack Tehnologic
*   **Limbaj:** [GnuCOBOL](https://gnucobol.sourceforge.io/) (cobc)
*   **Baza de date:** **ISAM** (Indexed Sequential Access Method) nativ COBOL via `ORGANIZATION IS INDEXED`.
*   **Interfață:** **CGI** (Common Gateway Interface) - Generare HTML direct în `stdout`.
*   **Server (Wrapper):** Python `http.server --cgi` sau Flask (pentru testare locală rapidă).

---

## 📂 Structura Proiectului
*   `ledger.cbl`: Programul principal de raportare (generare tabel HTML din ISAM).
*   `seed.cbl`: Utilitate pentru popularea inițială a bazei de date cu tranzacții.
*   `hello.cbl`: Test de concept CGI "Hello World".
*   `data/ledger.dat`: Fișierul bazei de date indexate (creat automat la prima rulare).
*   `run_demo.sh`: Script de automatizare pentru compilare și execuție demo.

---

## 🚀 Cum rulez?

### 1. Instalare (pe sisteme bazate pe Debian/Ubuntu)
```bash
sudo apt update && sudo apt install -y gnucobol
```

### 2. Compilare și Populare (Seed)
```bash
cobc -x -free seed.cbl -o seed
./seed
```

### 3. Compilare Raport Web
```bash
cobc -x -free ledger.cbl -o ledger.cgi
```

### 4. Vizualizare Rezultat (Local)
Puteți rula binarul direct pentru a vedea HTML-ul generat:
```bash
./ledger.cgi
```

Sau rulați scriptul de demo complet:
```bash
chmod +x run_demo.sh
./run_demo.sh
```

---

## 🏗️ Ce urmează?
- [ ] Implementarea gestionării input-ului **POST** direct în COBOL (pentru adăugarea de tranzacții dintr-un formular web).
- [ ] Adăugarea unei rutine de calcul pentru soldul total (Balance).
- [ ] Stil HTML/CSS minimal integrat în binar.

---
*Acest proiect a fost creat ca o demonstrație de programare "vint-age modernă" în cadrul unei sesiuni Gemini CLI.*
