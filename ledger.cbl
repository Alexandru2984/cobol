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
01  W-HTML-HEADER           PIC X(50) VALUE "Content-type: text/html".
01  W-EMPTY-LINE            PIC X     VALUE " ".
01  W-EOF                   PIC X     VALUE "N".
01  W-DISPLAY-AMOUNT        PIC ZZZ,ZZ9.99.

PROCEDURE DIVISION.
MAIN-LOGIC.
    DISPLAY W-HTML-HEADER.
    DISPLAY W-EMPTY-LINE.
    DISPLAY "<html><head><title>Ledger of Ages</title></head>".
    DISPLAY "<body><h1>The Ledger of Ages</h1>".
    
    PERFORM OPEN-FILE.
    IF FS-LEDGER = "00"
        PERFORM DISPLAY-TRANSACTIONS
        PERFORM CLOSE-FILE
    ELSE
        DISPLAY "<p>Eroare la deschiderea bazei de date (FS=" FS-LEDGER ").</p>"
    END-IF.

    DISPLAY "</body></html>".
    STOP RUN.

OPEN-FILE.
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "35"
        OPEN OUTPUT TRANSACTIONS-FILE
        CLOSE TRANSACTIONS-FILE
        OPEN I-O TRANSACTIONS-FILE
    END-IF.

CLOSE-FILE.
    CLOSE TRANSACTIONS-FILE.

DISPLAY-TRANSACTIONS.
    DISPLAY "<table border='1'>".
    DISPLAY "<tr><th>ID</th><th>Data</th><th>Descriere</th><th>Suma</th></tr>".
    
    MOVE LOW-VALUES TO TRANS-ID.
    START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-ID
        INVALID KEY 
            MOVE "Y" TO W-EOF
            DISPLAY "<tr><td colspan='4'>Nicio tranzactie gasita.</td></tr>"
    END-START.
    
    PERFORM UNTIL W-EOF = "Y"
        READ TRANSACTIONS-FILE NEXT
            AT END
                MOVE "Y" TO W-EOF
            NOT AT END
                IF FS-LEDGER = "00"
                    DISPLAY "<tr>"
                    DISPLAY "<td>" TRANS-ID "</td>"
                    DISPLAY "<td>" TRANS-DATE "</td>"
                    DISPLAY "<td>" TRANS-DESC "</td>"
                    MOVE TRANS-AMOUNT TO W-DISPLAY-AMOUNT
                    DISPLAY "<td>" W-DISPLAY-AMOUNT "</td>"
                    DISPLAY "</tr>"
                ELSE
                    MOVE "Y" TO W-EOF
                END-IF
        END-READ
    END-PERFORM.
    DISPLAY "</table>".
