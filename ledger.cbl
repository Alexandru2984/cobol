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
    05  TRANS-DESC          PIC X(30).
    05  TRANS-AMOUNT        PIC S9(7)V99.

WORKING-STORAGE SECTION.
01  FS-LEDGER               PIC XX.
01  W-EOF                   PIC X     VALUE "N".
01  W-DISPLAY-AMOUNT        PIC ZZZ,ZZ9.99.
01  W-TOTAL-BALANCE         PIC S9(9)V99 VALUE 0.
01  W-DISPLAY-TOTAL         PIC ZZZ,ZZZ,ZZ9.99.

01  W-METHOD                PIC X(10).
01  W-CONTENT-LEN-STR       PIC X(10).
01  W-CONTENT-LEN           PIC 9(10).
01  W-POST-DATA             PIC X(1024).

01  W-RAW-FIELD             PIC X(100).
01  W-ID-PART               PIC X(100).
01  W-DATE-PART             PIC X(100).
01  W-DESC-PART             PIC X(100).
01  W-AMT-PART              PIC X(100).

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
        UNSTRING W-POST-DATA DELIMITED BY "&"
            INTO W-ID-PART, W-DATE-PART, W-DESC-PART, W-AMT-PART
        
        UNSTRING W-ID-PART DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-ID
        UNSTRING W-DATE-PART DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-DATE
        UNSTRING W-DESC-PART DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-DESC
        UNSTRING W-AMT-PART DELIMITED BY "=" INTO W-RAW-FIELD, W-RAW-FIELD
        
        INSPECT TRANS-DESC REPLACING ALL "+" BY " "
        
        MOVE FUNCTION NUMVAL(W-RAW-FIELD) TO TRANS-AMOUNT
        
        OPEN I-O TRANSACTIONS-FILE
        WRITE TRANS-RECORD
            INVALID KEY REWRITE TRANS-RECORD
        END-WRITE
        CLOSE TRANSACTIONS-FILE
    END-IF.

DISPLAY-PAGE.
    DISPLAY "Content-type: text/html".
    DISPLAY " ".
    DISPLAY "<html><head><title>Ledger of Ages - Production</title>".
    DISPLAY "<style>".
    DISPLAY "  body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #eceff1; color: #37474f; }".
    DISPLAY "  .container { max-width: 900px; margin: auto; background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }".
    DISPLAY "  h1 { color: #263238; border-bottom: 2px solid #607d8b; padding-bottom: 10px; }".
    DISPLAY "  table { width: 100%; border-collapse: collapse; margin-top: 20px; }".
    DISPLAY "  th { background: #607d8b; color: white; padding: 12px; text-align: left; }".
    DISPLAY "  td { padding: 12px; border-bottom: 1px solid #cfd8dc; }".
    DISPLAY "  tr:hover { background: #f5f5f5; }".
    DISPLAY "  .total-row { font-weight: bold; background: #cfd8dc; }".
    DISPLAY "  form { margin-top: 30px; padding: 20px; border: 1px solid #b0bec5; border-radius: 8px; background: #fafafa; }".
    DISPLAY "  input[type=text], input[type=number] { padding: 8px; border: 1px solid #ccc; border-radius: 4px; width: 200px; }".
    DISPLAY "  input[type=submit] { padding: 10px 20px; background: #455a64; color: white; border: none; border-radius: 4px; cursor: pointer; }".
    DISPLAY "  input[type=submit]:hover { background: #263238; }".
    DISPLAY "</style></head><body>".
    DISPLAY "<div class='container'>".
    DISPLAY "<h1>📜 The Ledger of Ages</h1>".
    
    PERFORM OPEN-FILE.
    IF FS-LEDGER = "00"
        PERFORM DISPLAY-TABLE
        PERFORM CLOSE-FILE
    ELSE
        DISPLAY "<p>Baza de date este momentan indisponibila.</p>"
    END-IF.

    DISPLAY "<h2>Adauga Tranzactie</h2>".
    DISPLAY "<form method='POST' action='ledger.cgi'>".
    DISPLAY "  ID: <input type='text' name='id' placeholder='Ex: 0001' required> ".
    DISPLAY "  Data: <input type='text' name='date' value='2026-04-18'> <br><br>".
    DISPLAY "  Descriere: <input type='text' name='desc' placeholder='Ex: Cumparaturi' required> <br><br>".
    DISPLAY "  Suma: <input type='text' name='amount' placeholder='Ex: 150.50' required> ".
    DISPLAY "  <input type='submit' value='Inregistreaza in Ledger'>".
    DISPLAY "</form>".
    DISPLAY "</div></body></html>".

OPEN-FILE.
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "35"
        OPEN OUTPUT TRANSACTIONS-FILE
        CLOSE TRANSACTIONS-FILE
        OPEN I-O TRANSACTIONS-FILE
    END-IF.

CLOSE-FILE.
    CLOSE TRANSACTIONS-FILE.

DISPLAY-TABLE.
    DISPLAY "<table><thead><tr><th>ID</th><th>Data</th><th>Descriere</th><th>Suma</th></tr></thead><tbody>".
    
    MOVE LOW-VALUES TO TRANS-ID.
    START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-ID.
    
    PERFORM UNTIL W-EOF = "Y"
        READ TRANSACTIONS-FILE NEXT
            AT END MOVE "Y" TO W-EOF
            NOT AT END
                IF FS-LEDGER = "00"
                    DISPLAY "<tr>"
                    DISPLAY "<td>" TRANS-ID "</td>"
                    DISPLAY "<td>" TRANS-DATE "</td>"
                    DISPLAY "<td>" TRANS-DESC "</td>"
                    MOVE TRANS-AMOUNT TO W-DISPLAY-AMOUNT
                    DISPLAY "<td>" W-DISPLAY-AMOUNT "</td>"
                    DISPLAY "</tr>"
                    ADD TRANS-AMOUNT TO W-TOTAL-BALANCE
                END-IF
        END-READ
    END-PERFORM.
    
    MOVE W-TOTAL-BALANCE TO W-DISPLAY-TOTAL.
    DISPLAY "<tr class='total-row'><td colspan='3'>TOTAL BALANTA</td><td>" W-DISPLAY-TOTAL "</td></tr>".
    DISPLAY "</tbody></table>".
