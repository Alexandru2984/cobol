# 📜 The Ledger of Ages

A web application (CGI) written in **pure COBOL**, using indexed databases (**ISAM**) and the CGI standard for interface generation.

---

## 🛠️ Technology Stack
*   **Language:** [GnuCOBOL](https://gnucobol.sourceforge.io/) (cobc)
*   **Database:** **ISAM** (Indexed Sequential Access Method), native to COBOL via `ORGANIZATION IS INDEXED`.
*   **Interface:** **CGI** (Common Gateway Interface) — HTML generated directly to `stdout`.
*   **Server (Wrapper):** Python `http.server --cgi` or Flask (for quick local testing).

---

## 📂 Project Structure
*   `ledger.cbl`: Main reporting program (generates the HTML table from ISAM).
*   `seed.cbl`: Utility for initial population of the database with transactions.
*   `hello.cbl`: "Hello World" CGI proof of concept.
*   `data/ledger.dat`: The indexed database file (created automatically on first run).
*   `run_demo.sh`: Automation script for compilation and demo execution.

---

## 🚀 How do I run it?

### 1. Install (on Debian/Ubuntu-based systems)
```bash
sudo apt update && sudo apt install -y gnucobol
```

### 2. Compile and Populate (Seed)
```bash
cobc -x -free seed.cbl -o seed
./seed
```

### 3. Compile the Web Report
```bash
cobc -x -free ledger.cbl -o ledger.cgi
```

### 4. View the Result (Local)
You can run the binary directly to see the generated HTML:
```bash
./ledger.cgi
```

Or run the full demo script:
```bash
chmod +x run_demo.sh
./run_demo.sh
```

---

## 🏗️ What's next?
- [ ] Implement **POST** input handling directly in COBOL (to add transactions from a web form).
- [ ] Add a routine to compute the total balance.
- [ ] Minimal HTML/CSS styling embedded in the binary.

---
*This project was built as a demonstration of "modern vint-age" programming during a Gemini CLI session.*
