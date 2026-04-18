IDENTIFICATION DIVISION.
PROGRAM-ID. LEDGER-OF-AGES.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT TRANSACTIONS-FILE ASSIGN TO "data/ledger.dat"
        ORGANIZATION IS INDEXED
        ACCESS MODE IS DYNAMIC
        RECORD KEY IS TRANS-ID
        FILE STATUS IS FS-LEDGER.

DATA DIVISION.
FILE SECTION.
FD  TRANSACTIONS-FILE.
01  TRANS-RECORD.
    05  TRANS-ID            PIC X(10).
    05  TRANS-DATE          PIC X(10).
    05  TRANS-CAT           PIC X(15).
    05  TRANS-DESC          PIC X(30).
    05  TRANS-AMOUNT        PIC S9(7)V99.

WORKING-STORAGE SECTION.
01  FS-LEDGER               PIC XX.
01  W-EOF                   PIC X     VALUE "N".
01  W-DISPLAY-AMOUNT        PIC ZZZ,ZZ9.99.
01  W-TOTAL-BALANCE         PIC S9(9)V99 VALUE 0.
01  W-DISPLAY-TOTAL         PIC ZZZ,ZZZ,ZZ9.99.

*> Variabile CGI
01  W-METHOD                PIC X(10).
01  W-CONTENT-LEN-STR       PIC X(10).
01  W-CONTENT-LEN           PIC 9(10).
01  W-POST-DATA             PIC X(2048).

*> Variabile Parsare
01  W-RAW-FIELD             PIC X(200).
01  W-ID-PART               PIC X(100).
01  W-CMD-PART              PIC X(100).
01  W-DATE-PART             PIC X(100).
01  W-CAT-PART              PIC X(100).
01  W-DESC-PART             PIC X(100).
01  W-AMT-PART              PIC X(100).
01  W-CMD-VAL               PIC X(10).

*> Tabel pentru Raport pe Categorii
01  CAT-SUMMARY-TABLE.
    05  CAT-ENTRY           OCCURS 5 TIMES INDEXED BY CAT-IDX.
        10  CAT-NAME        PIC X(15).
        10  CAT-TOTAL       PIC S9(9)V99.

PROCEDURE DIVISION.
MAIN-LOGIC.
    DISPLAY "REQUEST_METHOD" UPON ENVIRONMENT-NAME.
    ACCEPT W-METHOD FROM ENVIRONMENT-VALUE.

    IF W-METHOD = "POST"
        PERFORM HANDLE-POST
    END-IF.

    PERFORM DISPLAY-PAGE.
    STOP RUN.

HANDLE-POST.
    DISPLAY "CONTENT_LENGTH" UPON ENVIRONMENT-NAME.
    ACCEPT W-CONTENT-LEN-STR FROM ENVIRONMENT-VALUE.
    MOVE FUNCTION NUMVAL(W-CONTENT-LEN-STR) TO W-CONTENT-LEN.

    IF W-CONTENT-LEN > 0
        ACCEPT W-POST-DATA FROM SYSIN
        
        *> Detectam comanda: cmd=add sau cmd=del
        UNSTRING W-POST-DATA DELIMITED BY "&"
            INTO W-CMD-PART, W-ID-PART, W-DATE-PART, W-CAT-PART, W-DESC-PART, W-AMT-PART
        
        UNSTRING W-CMD-PART DELIMITED BY "=" INTO W-RAW-FIELD, W-CMD-VAL
        UNSTRING W-ID-PART DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-ID

        IF W-CMD-VAL = "del"
            OPEN I-O TRANSACTIONS-FILE
            DELETE TRANSACTIONS-FILE RECORD
            CLOSE TRANSACTIONS-FILE
        ELSE
            UNSTRING W-DATE-PART DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-DATE
            UNSTRING W-CAT-PART  DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-CAT
            UNSTRING W-DESC-PART DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-DESC
            UNSTRING W-AMT-PART  DELIMITED BY "=" INTO W-RAW-FIELD, W-RAW-FIELD
            
            INSPECT TRANS-CAT  REPLACING ALL "+" BY " "
            INSPECT TRANS-DESC REPLACING ALL "+" BY " "
            MOVE FUNCTION NUMVAL(W-RAW-FIELD) TO TRANS-AMOUNT
            
            OPEN I-O TRANSACTIONS-FILE
            WRITE TRANS-RECORD
                INVALID KEY REWRITE TRANS-RECORD
            END-WRITE
            CLOSE TRANSACTIONS-FILE
        END-IF
    END-IF.

DISPLAY-PAGE.
    DISPLAY "Content-type: text/html".
    DISPLAY " ".
    DISPLAY "<html><head><title>Ledger of Ages Pro</title>".
    DISPLAY "<style>".
    DISPLAY "  body { font-family: 'Segoe UI', sans-serif; margin: 0; padding: 20px; background: #f0f2f5; }".
    DISPLAY "  .card { max-width: 1000px; margin: auto; background: white; padding: 25px; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.1); }".
    DISPLAY "  h1 { color: #1a237e; border-left: 5px solid #1a237e; padding-left: 15px; }".
    DISPLAY "  table { width: 100%; border-collapse: collapse; margin: 20px 0; }".
    DISPLAY "  th { background: #1a237e; color: white; padding: 12px; }".
    DISPLAY "  td { padding: 12px; border-bottom: 1px solid #ddd; }".
    DISPLAY "  .positive { color: #2e7d32; font-weight: bold; }".
    DISPLAY "  .negative { color: #c62828; font-weight: bold; }".
    DISPLAY "  .btn-del { background: #ff5252; color: white; border: none; border-radius: 4px; padding: 5px 10px; cursor: pointer; }".
    DISPLAY "  .form-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #f8f9fa; padding: 20px; border-radius: 10px; }".
    DISPLAY "  .summary-box { display: flex; justify-content: space-around; background: #e8eaf6; padding: 15px; border-radius: 10px; margin-top: 20px; }".
    DISPLAY "</style></head><body>".
    DISPLAY "<div class='card'>".
    DISPLAY "<h1>📜 Ledger of Ages <small>(Pro v2.0)</small></h1>".
    
    PERFORM OPEN-FILE.
    IF FS-LEDGER = "00"
        PERFORM INITIALIZE-SUMMARY
        PERFORM DISPLAY-TABLE
        PERFORM CLOSE-FILE
        PERFORM DISPLAY-SUMMARY
    ELSE
        DISPLAY "<p>Database offline.</p>"
    END-IF.

    DISPLAY "<h2>+ Adauga Operatiune</h2>".
    DISPLAY "<form method='POST' action='ledger.cgi' class='form-grid'>".
    DISPLAY "  <input type='hidden' name='cmd' value='add'>".
    DISPLAY "  <div>ID: <br><input type='text' name='id' required style='width:100%'></div>".
    DISPLAY "  <div>Data: <br><input type='text' name='date' value='2026-04-18' style='width:100%'></div>".
    DISPLAY "  <div>Categorie: <br><select name='cat' style='width:100%; padding:8px;'>".
    DISPLAY "    <option value='Venituri'>Venituri</option>".
    DISPLAY "    <option value='Locuinta'>Locuinta</option>".
    DISPLAY "    <option value='Mancare'>Mancare</option>".
    DISPLAY "    <option value='Hobby'>Hobby</option>".
    DISPLAY "    <option value='Utilitati'>Utilitati</option>".
    DISPLAY "  </select></div>".
    DISPLAY "  <div style='grid-column: span 2'>Descriere: <br><input type='text' name='desc' required style='width:100%'></div>".
    DISPLAY "  <div>Suma (+/-): <br><input type='text' name='amount' required style='width:100%'></div>".
    DISPLAY "  <div style='grid-column: span 3'><input type='submit' value='Salveaza in ISAM' style='width:100%; padding:12px; background:#1a237e; color:white; border:none; border-radius:5px; cursor:pointer;'></div>".
    DISPLAY "</form>".
    DISPLAY "</div></body></html>".

INITIALIZE-SUMMARY.
    MOVE "Venituri"  TO CAT-NAME(1).
    MOVE "Locuinta"  TO CAT-NAME(2).
    MOVE "Mancare"   TO CAT-NAME(3).
    MOVE "Hobby"     TO CAT-NAME(4).
    MOVE "Utilitati" TO CAT-NAME(5).
    MOVE 0 TO CAT-TOTAL(1) CAT-TOTAL(2) CAT-TOTAL(3) CAT-TOTAL(4) CAT-TOTAL(5).

DISPLAY-TABLE.
    DISPLAY "<table><thead><tr><th>ID</th><th>Data</th><th>Categorie</th><th>Descriere</th><th>Suma</th><th>Actiuni</th></tr></thead><tbody>".
    MOVE LOW-VALUES TO TRANS-ID.
    START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-ID.
    PERFORM UNTIL W-EOF = "Y"
        READ TRANSACTIONS-FILE NEXT
            AT END MOVE "Y" TO W-EOF
            NOT AT END
                DISPLAY "<tr>"
                DISPLAY "<td>" TRANS-ID "</td>"
                DISPLAY "<td>" TRANS-DATE "</td>"
                DISPLAY "<td>" TRANS-CAT "</td>"
                DISPLAY "<td>" TRANS-DESC "</td>"
                MOVE TRANS-AMOUNT TO W-DISPLAY-AMOUNT
                IF TRANS-AMOUNT < 0
                    DISPLAY "<td class='negative'>" W-DISPLAY-AMOUNT "</td>"
                ELSE
                    DISPLAY "<td class='positive'>" W-DISPLAY-AMOUNT "</td>"
                END-IF
                DISPLAY "<td><form method='POST' style='margin:0'><input type='hidden' name='cmd' value='del'><input type='hidden' name='id' value='" TRANS-ID "'><input type='submit' class='btn-del' value='X'></form></td>"
                DISPLAY "</tr>"
                ADD TRANS-AMOUNT TO W-TOTAL-BALANCE
                PERFORM UPDATE-CAT-TOTAL
        END-READ
    END-PERFORM.
    MOVE W-TOTAL-BALANCE TO W-DISPLAY-TOTAL.
    DISPLAY "<tr style='background:#1a237e; color:white; font-weight:bold;'><td colspan='4'>BALANTA FINALA</td><td colspan='2'>" W-DISPLAY-TOTAL "</td></tr>".
    DISPLAY "</tbody></table>".

UPDATE-CAT-TOTAL.
    SET CAT-IDX TO 1.
    SEARCH CAT-ENTRY
        WHEN CAT-NAME(CAT-IDX) = TRANS-CAT
            ADD TRANS-AMOUNT TO CAT-TOTAL(CAT-IDX)
    END-SEARCH.

DISPLAY-SUMMARY.
    DISPLAY "<div class='card' style='margin-top:20px;'><h3>📊 Rezumat pe Categorii</h3><div class='summary-box'>".
    PERFORM VARYING CAT-IDX FROM 1 BY 1 UNTIL CAT-IDX > 5
        MOVE CAT-TOTAL(CAT-IDX) TO W-DISPLAY-AMOUNT
        DISPLAY "<div><strong>" CAT-NAME(CAT-IDX) "</strong><br>" W-DISPLAY-AMOUNT "</div>"
    END-PERFORM.
    DISPLAY "</div></div>".

OPEN-FILE.
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "35"
        OPEN OUTPUT TRANSACTIONS-FILE
        CLOSE TRANSACTIONS-FILE
        OPEN I-O TRANSACTIONS-FILE
    END-IF.

CLOSE-FILE.
    CLOSE TRANSACTIONS-FILE.
