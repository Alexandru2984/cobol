IDENTIFICATION DIVISION.
PROGRAM-ID. LEDGER-OF-AGES.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT TRANSACTIONS-FILE ASSIGN TO "data/ledger.dat"
        ORGANIZATION IS INDEXED
        ACCESS MODE IS DYNAMIC
        RECORD KEY IS TRANS-ID
        ALTERNATE RECORD KEY IS TRANS-DATE WITH DUPLICATES
        FILE STATUS IS FS-LEDGER.

DATA DIVISION.
FILE SECTION.
FD  TRANSACTIONS-FILE.
01  TRANS-RECORD.
    05  TRANS-ID            PIC 9(6).
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
01  W-LAST-ID               PIC 9(6) VALUE 0.

*> Variabile CGI
01  W-METHOD                PIC X(10).
01  W-CONTENT-LEN-STR       PIC X(10).
01  W-CONTENT-LEN           PIC 9(10).
01  W-POST-DATA             PIC X(2048).
01  W-QUERY-STRING          PIC X(1024).
01  W-COOKIE-ENV            PIC X(1024).

*> Variabile Parsare
01  W-RAW-FIELD             PIC X(200).
01  W-PART-1                PIC X(100).
01  W-PART-2                PIC X(100).
01  W-PART-3                PIC X(100).
01  W-PART-4                PIC X(100).
01  W-PART-5                PIC X(100).
01  W-PART-6                PIC X(100).

*> Login & Session
01  W-CMD-VAL               PIC X(10).
01  W-USER-VAL              PIC X(20).
01  W-PASS-VAL              PIC X(20).
01  W-LOGGED-IN             PIC X VALUE "N".
01  W-SET-COOKIE            PIC X VALUE "N".

*> Filtrare
01  W-FILTER-CAT            PIC X(15) VALUE "ALL".
01  W-SORT-BY               PIC X(10) VALUE "ID".

01  CAT-SUMMARY-TABLE.
    05  CAT-ENTRY           OCCURS 5 TIMES INDEXED BY CAT-IDX.
        10  CAT-NAME        PIC X(15).
        10  CAT-TOTAL       PIC S9(9)V99.

PROCEDURE DIVISION.
MAIN-LOGIC.
    DISPLAY "HTTP_COOKIE" UPON ENVIRONMENT-NAME.
    ACCEPT W-COOKIE-ENV FROM ENVIRONMENT-VALUE.
    IF W-COOKIE-ENV(1:12) = "session=micu"
        MOVE "Y" TO W-LOGGED-IN
    END-IF.

    DISPLAY "QUERY_STRING" UPON ENVIRONMENT-NAME.
    ACCEPT W-QUERY-STRING FROM ENVIRONMENT-VALUE.
    DISPLAY "REQUEST_METHOD" UPON ENVIRONMENT-NAME.
    ACCEPT W-METHOD FROM ENVIRONMENT-VALUE.

    IF W-QUERY-STRING NOT = SPACES
        PERFORM PARSE-QUERY-STRING
    END-IF.

    IF W-METHOD = "POST"
        PERFORM HANDLE-POST
    END-IF.

    PERFORM DISPLAY-PAGE.
    STOP RUN.

PARSE-QUERY-STRING.
    UNSTRING W-QUERY-STRING DELIMITED BY "&" INTO W-PART-1, W-PART-2
    UNSTRING W-PART-1 DELIMITED BY "=" INTO W-RAW-FIELD, W-FILTER-CAT
    UNSTRING W-PART-2 DELIMITED BY "=" INTO W-RAW-FIELD, W-SORT-BY.

HANDLE-POST.
    DISPLAY "CONTENT_LENGTH" UPON ENVIRONMENT-NAME.
    ACCEPT W-CONTENT-LEN-STR FROM ENVIRONMENT-VALUE.
    MOVE FUNCTION NUMVAL(W-CONTENT-LEN-STR) TO W-CONTENT-LEN.
    IF W-CONTENT-LEN > 0
        ACCEPT W-POST-DATA FROM SYSIN
        UNSTRING W-POST-DATA DELIMITED BY "&"
            INTO W-PART-1, W-PART-2, W-PART-3, W-PART-4, W-PART-5, W-PART-6
        
        UNSTRING W-PART-1 DELIMITED BY "=" INTO W-RAW-FIELD, W-CMD-VAL

        IF W-CMD-VAL = "login"
            UNSTRING W-PART-2 DELIMITED BY "=" INTO W-RAW-FIELD, W-USER-VAL
            UNSTRING W-PART-3 DELIMITED BY "=" INTO W-RAW-FIELD, W-PASS-VAL
            IF W-USER-VAL = "micu" AND W-PASS-VAL = "cobol2026"
                MOVE "Y" TO W-LOGGED-IN
                MOVE "Y" TO W-SET-COOKIE
            END-IF
        ELSE
            IF W-LOGGED-IN = "Y"
                IF W-CMD-VAL = "del"
                    UNSTRING W-PART-2 DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-ID
                    OPEN I-O TRANSACTIONS-FILE
                    DELETE TRANSACTIONS-FILE RECORD
                    CLOSE TRANSACTIONS-FILE
                ELSE
                    PERFORM GENERATE-ID
                    UNSTRING W-PART-2 DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-DATE
                    UNSTRING W-PART-3 DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-CAT
                    UNSTRING W-PART-4 DELIMITED BY "=" INTO W-RAW-FIELD, TRANS-DESC
                    UNSTRING W-PART-5 DELIMITED BY "=" INTO W-RAW-FIELD, W-RAW-FIELD
                    
                    INSPECT TRANS-CAT  REPLACING ALL "+" BY " "
                    INSPECT TRANS-DESC REPLACING ALL "+" BY " "
                    MOVE FUNCTION NUMVAL(W-RAW-FIELD) TO TRANS-AMOUNT
                    
                    OPEN I-O TRANSACTIONS-FILE
                    WRITE TRANS-RECORD
                    CLOSE TRANSACTIONS-FILE
                END-IF
            END-IF
        END-IF
    END-IF.

GENERATE-ID.
    OPEN I-O TRANSACTIONS-FILE.
    MOVE 0 TO W-LAST-ID.
    MOVE HIGH-VALUES TO TRANS-ID.
    START TRANSACTIONS-FILE KEY IS LESS THAN TRANS-ID
        INVALID KEY MOVE 0 TO W-LAST-ID
        NOT INVALID KEY
            READ TRANSACTIONS-FILE PREVIOUS
            MOVE TRANS-ID TO W-LAST-ID
    END-START.
    ADD 1 TO W-LAST-ID GIVING TRANS-ID.
    CLOSE TRANSACTIONS-FILE.

DISPLAY-PAGE.
    DISPLAY "Content-type: text/html".
    IF W-SET-COOKIE = "Y"
        DISPLAY "Set-Cookie: session=micu; Path=/; HttpOnly"
    END-IF.
    DISPLAY " ".
    DISPLAY "<html><head><title>Ledger Pro v3.6</title>".
    DISPLAY "<style>body{font-family:sans-serif; background:#f8fafc; padding:2rem;}".
    DISPLAY ".card{background:white; border-radius:12px; padding:1.5rem; margin-bottom:2rem;".
    DISPLAY "max-width:1000px; margin:auto; box-shadow:0 2px 4px rgba(0,0,0,0.1);}".
    DISPLAY "table{width:100%; border-collapse:collapse;}".
    DISPLAY "th{text-align:left; background:#f1f5f9; padding:8px;}".
    DISPLAY "td{padding:8px; border-bottom:1px solid #eee;}".
    DISPLAY ".btn{background:#1e293b; color:white; border:none; padding:8px 16px;".
    DISPLAY "border-radius:6px; cursor:pointer;} .btn-del{background:#ef4444;}</style></head><body>".
    
    IF W-LOGGED-IN = "N"
        PERFORM DISPLAY-LOGIN
    ELSE
        DISPLAY "<div class='card'><h1>📜 Ledger of Ages</h1><p>Logat ca: micu</p></div>"
        PERFORM DISPLAY-TOOLBAR
        PERFORM OPEN-FILE
        IF FS-LEDGER = "00"
            PERFORM INITIALIZE-SUMMARY
            PERFORM DISPLAY-TABLE
            PERFORM CLOSE-FILE
            PERFORM DISPLAY-SUMMARY
        END-IF
        PERFORM DISPLAY-ADD-FORM
    END-IF.
    DISPLAY "</body></html>".

DISPLAY-LOGIN.
    DISPLAY "<div class='card' style='max-width:400px; margin-top:100px;'><h2>🔐 Login</h2>".
    DISPLAY "<form method='POST'><input type='hidden' name='cmd' value='login'>".
    DISPLAY "<p>User:<br><input type='text' name='user' style='width:100%'></p>".
    DISPLAY "<p>Pass:<br><input type='password' name='pass' style='width:100%'></p>".
    DISPLAY "<button type='submit' class='btn'>Intra</button></form></div>".

DISPLAY-TOOLBAR.
    DISPLAY "<div class='card'><form method='GET'>Filtru: <select name='filter'>".
    DISPLAY "<option value='ALL'>Toate</option><option value='Venituri'>Venituri</option></select>".
    DISPLAY " Sort: <select name='sort'><option value='ID'>ID</option><option value='DATE'>Data</option></select>".
    DISPLAY " <button type='submit' class='btn'>Aplica</button></form></div>".

DISPLAY-ADD-FORM.
    DISPLAY "<div class='card'><h2>+ Adauga</h2><form method='POST'><input type='hidden' name='cmd' value='add'>".
    DISPLAY "Data: <input type='text' name='date' value='2026-04-18'> Cat: <select name='cat'>".
    DISPLAY "<option value='Venituri'>Venituri</option><option value='Locuinta'>Locuinta</option></select>".
    DISPLAY " Desc: <input type='text' name='desc' required> Suma: <input type='text' name='amount' required>".
    DISPLAY " <button type='submit' class='btn'>Salveaza</button></form></div>".

INITIALIZE-SUMMARY.
    MOVE "Venituri" TO CAT-NAME(1).
    MOVE "Locuinta" TO CAT-NAME(2).
    MOVE "Mancare" TO CAT-NAME(3).
    MOVE "Hobby" TO CAT-NAME(4).
    MOVE "Utilitati" TO CAT-NAME(5).
    MOVE 0 TO CAT-TOTAL(1) CAT-TOTAL(2) CAT-TOTAL(3) CAT-TOTAL(4) CAT-TOTAL(5).

DISPLAY-TABLE.
    DISPLAY "<div class='card' style='padding:0;'><table><thead><tr>".
    DISPLAY "<th>ID</th><th>Data</th><th>Cat</th><th>Desc</th><th>Suma</th><th></th></tr></thead><tbody>".
    IF W-SORT-BY = "DATE"
        MOVE LOW-VALUES TO TRANS-DATE
        START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-DATE
    ELSE
        MOVE 0 TO TRANS-ID
        START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-ID
    END-IF.
    PERFORM UNTIL W-EOF = "Y"
        READ TRANSACTIONS-FILE NEXT
            AT END MOVE "Y" TO W-EOF
            NOT AT END
                IF (W-FILTER-CAT = "ALL") OR (W-FILTER-CAT = TRANS-CAT)
                    DISPLAY "<tr><td>#" TRANS-ID "</td><td>" TRANS-DATE "</td>"
                    DISPLAY "<td>" TRANS-CAT "</td><td>" TRANS-DESC "</td>"
                    MOVE TRANS-AMOUNT TO W-DISPLAY-AMOUNT
                    DISPLAY "<td>" W-DISPLAY-AMOUNT "</td><td>"
                    DISPLAY "<form method='POST'><input type='hidden' name='cmd' value='del'>"
                    DISPLAY "<input type='hidden' name='id' value='" TRANS-ID "'>"
                    DISPLAY "<button type='submit' class='btn btn-del'>&times;</button></form></td></tr>"
                    ADD TRANS-AMOUNT TO W-TOTAL-BALANCE
                    PERFORM UPDATE-CAT-TOTAL
                END-IF
        END-READ
    END-PERFORM.
    MOVE W-TOTAL-BALANCE TO W-DISPLAY-TOTAL.
    DISPLAY "</tbody><tfoot><tr><td colspan='4'>Total</td><td colspan='2'>" W-DISPLAY-TOTAL "</td></tr></tfoot></table></div>".

UPDATE-CAT-TOTAL.
    SET CAT-IDX TO 1.
    SEARCH CAT-ENTRY WHEN CAT-NAME(CAT-IDX) = TRANS-CAT ADD TRANS-AMOUNT TO CAT-TOTAL(CAT-IDX) END-SEARCH.

DISPLAY-SUMMARY.
    DISPLAY "<div style='display:flex; gap:1rem; max-width:1000px; margin:auto;'>".
    PERFORM VARYING CAT-IDX FROM 1 BY 1 UNTIL CAT-IDX > 5
        MOVE CAT-TOTAL(CAT-IDX) TO W-DISPLAY-AMOUNT
        DISPLAY "<div class='card' style='flex:1; text-align:center;'><div>" CAT-NAME(CAT-IDX) "</div><strong>" W-DISPLAY-AMOUNT "</strong></div>"
    END-PERFORM.
    DISPLAY "</div>".

OPEN-FILE.
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "35" OPEN OUTPUT TRANSACTIONS-FILE CLOSE TRANSACTIONS-FILE OPEN I-O TRANSACTIONS-FILE END-IF.
CLOSE-FILE.
    CLOSE TRANSACTIONS-FILE.
