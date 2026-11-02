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

    SELECT SESSIONS-FILE ASSIGN TO "data/sessions.dat"
        ORGANIZATION IS INDEXED
        ACCESS MODE IS DYNAMIC
        RECORD KEY IS SESS-TOKEN
        FILE STATUS IS FS-SESSIONS.

    SELECT LOCKOUT-FILE ASSIGN TO "data/lockout.dat"
        ORGANIZATION IS INDEXED
        ACCESS MODE IS DYNAMIC
        RECORD KEY IS LOCK-IP
        FILE STATUS IS FS-LOCKOUT.

    SELECT OPTIONAL AUDIT-FILE ASSIGN TO "data/audit.log"
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS FS-AUDIT.

DATA DIVISION.
FILE SECTION.
FD  TRANSACTIONS-FILE.
01  TRANS-RECORD.
    05  TRANS-ID            PIC 9(6).
    05  TRANS-DATE          PIC X(10).
    05  TRANS-CAT           PIC X(15).
    05  TRANS-DESC          PIC X(30).
    05  TRANS-AMOUNT        PIC S9(7)V99.

FD  SESSIONS-FILE.
01  SESS-RECORD.
    05  SESS-TOKEN          PIC X(32).
    05  SESS-EXP            PIC 9(12).
    05  SESS-IP             PIC X(45).

FD  LOCKOUT-FILE.
01  LOCK-RECORD.
    05  LOCK-IP             PIC X(45).
    05  LOCK-FAILS          PIC 9(3).
    05  LOCK-WIN-EXP        PIC 9(12).

FD  AUDIT-FILE.
01  AUDIT-REC               PIC X(160).

WORKING-STORAGE SECTION.
01  FS-LEDGER               PIC XX.
01  FS-SESSIONS             PIC XX.
01  FS-LOCKOUT              PIC XX.
01  FS-AUDIT                PIC XX.
01  W-EOF                   PIC X VALUE "N".
01  W-DISPLAY-AMOUNT        PIC --,---,--9.99.
01  W-TOTAL-BALANCE         PIC S9(9)V99 VALUE 0.
01  W-DISPLAY-TOTAL         PIC --,---,---,--9.99.
01  W-LAST-ID               PIC 9(6) VALUE 0.

*> CGI environment
01  W-METHOD                PIC X(10).
01  W-CONTENT-LEN-STR       PIC X(10).
01  W-CONTENT-LEN           PIC 9(10).
01  W-POST-DATA             PIC X(4096).
01  W-QUERY-STRING          PIC X(1024).
01  W-COOKIE-ENV            PIC X(1024).
01  W-REMOTE-ADDR           PIC X(45) VALUE SPACES.

*> Parsed form fields (by name, not position)
01  FORM-TABLE.
    05  FORM-COUNT          PIC 9(2) VALUE 0.
    05  FORM-ENTRY OCCURS 20 TIMES.
        10  FORM-KEY        PIC X(20).
        10  FORM-VALUE      PIC X(500).

01  W-PAIRS.
    05  W-PAIR OCCURS 20 TIMES PIC X(500).

01  W-PAIR-KEY              PIC X(20).
01  W-PAIR-VAL              PIC X(500).
01  W-KEY-LOOKUP            PIC X(20).
01  W-VALUE-OUT             PIC X(500).

*> URL-decode buffers
01  W-URL-IN                PIC X(500).
01  W-URL-IN-LEN            PIC 9(4).
01  W-URL-OUT               PIC X(500).
01  W-URL-OUT-LEN           PIC 9(4).
01  W-HEX-PAIR              PIC XX.
01  W-HEX-NUM               PIC 9(3).
01  W-HEX-CHAR              PIC X.

*> HTML escape buffers
01  W-ESC-IN                PIC X(500).
01  W-ESC-OUT               PIC X(2500).
01  W-ESC-IN-LEN            PIC 9(4).
01  W-ESC-OUT-LEN           PIC 9(4).
01  W-CH                    PIC X.

01  W-I                     PIC 9(4).
01  W-J                     PIC 9(4).
01  W-UD-I                  PIC 9(4).
01  W-UD-J                  PIC 9(4).
01  W-ESC-I                 PIC 9(4).
01  W-ESC-J                 PIC 9(4).

*> Auth / session
01  W-LOGGED-IN             PIC X VALUE "N".
01  W-SET-COOKIE            PIC X VALUE "N".
01  W-NEW-TOKEN             PIC X(32).
01  W-COOKIE-TOKEN          PIC X(32) VALUE SPACES.
01  W-TOKEN-IDX             PIC 9(4).

*> Server-side session expiry (absolute seconds)
01  W-SESSION-TTL           PIC 9(6) VALUE 28800.
01  W-TTL-RAW               PIC X(10).
01  W-ABS-NOW               PIC 9(12) VALUE 0.

*> Brute-force lockout (per IP)
01  W-LOCKED                PIC X VALUE "N".
01  W-MAX-FAILS             PIC 9(3) VALUE 5.
01  W-LOCK-WINDOW           PIC 9(6) VALUE 900.

*> Password hashing (SHA-256, modul separat sha256.cbl)
01  W-CFG-HASH              PIC X(64).
01  W-HASH-IN               PIC X(64).
01  W-HASH-LEN              USAGE BINARY-LONG.
01  W-HASH-OUT              PIC X(64).

*> Audit log
01  W-AUDIT-ACTION          PIC X(10).
01  W-AUDIT-DETAIL          PIC X(80).
01  AUDIT-RING.
    05  AR-LINE             OCCURS 30 TIMES PIC X(160).
01  W-AR-TOTAL              PIC 9(6) VALUE 0.
01  W-AR-IDX                PIC 9(4).
01  W-AR-K                  PIC 9(6).
01  W-AR-FROM               PIC 9(6).
01  W-AUD-TS                PIC X(19).
01  W-AUD-IP                PIC X(45).
01  W-AUD-ACT               PIC X(12).
01  W-AUD-DET               PIC X(90).

01  W-RANDOM-BYTES          PIC X(16).
01  W-RANDOM-COUNT          USAGE BINARY-LONG SIGNED.
01  W-RANDOM-BYTE           USAGE BINARY-LONG.
01  W-TOKEN-OK              PIC X VALUE "N".
01  W-SESSION-STORED        PIC X VALUE "N".
01  W-AUTH-MODE             PIC X(10).
01  W-AUTH-VERIFIED         PIC X.
01  W-CSRF-TOKEN            PIC X(300).
01  W-QUERY-I               PIC 9(4).
01  W-DATE-NUM              PIC 9(8).
01  W-AMOUNT-WIDE           PIC S9(18)V9(9).
01  W-AMOUNT-DIGITS         PIC 9(3).
01  W-AMOUNT-DECIMALS       PIC 9(3).
01  W-AMOUNT-DOT            PIC X.
01  W-AMOUNT-LEN            PIC 9(3).
01  HEX-DIGITS              PIC X(16) VALUE "0123456789abcdef".

*> Credentials (configurable via env vars)
01  W-CFG-USER              PIC X(40).
01  W-CFG-PASS              PIC X(40).
01  W-LOGIN-USER            PIC X(40).
01  W-LOGIN-PASS            PIC X(40).

*> Query filters
01  W-FILTER-CAT            PIC X(15) VALUE "ALL".
01  W-SORT-BY               PIC X(10) VALUE "ID".
01  W-FROM-DATE             PIC X(10) VALUE SPACES.
01  W-TO-DATE               PIC X(10) VALUE SPACES.
01  W-VIEW                  PIC X(10) VALUE "LEDGER".
01  W-EXPORT                PIC X VALUE "N".
01  W-ROW-MATCH             PIC X VALUE "N".
01  W-ROW-COUNT             PIC 9(6) VALUE 0.
01  W-DISPLAY-COUNT         PIC ZZZZZ9.

*> Text search in descriptions
01  W-SEARCH-Q              PIC X(30) VALUE SPACES.
01  W-Q-LC                  PIC X(30).
01  W-Q-LEN                 PIC 9(4) VALUE 0.
01  W-Q-CNT                 PIC 9(4).
01  W-DESC-LC               PIC X(30).

*> Pagination
01  W-PAGE                  PIC 9(4) VALUE 1.
01  W-PAGE-RAW              PIC X(10).
01  W-PAGE-SIZE             PIC 9(3) VALUE 20.
01  W-PAGE-START            PIC 9(6).
01  W-PAGE-END              PIC 9(6).
01  W-TOTAL-PAGES           PIC 9(4).
01  W-PAGE-D                PIC ZZZ9.
01  W-PAGES-D               PIC ZZZ9.
01  W-PGLNK-D               PIC ZZZ9.

*> URL-encode buffers (pentru linkurile de paginare)
01  W-ENC-IN                PIC X(60).
01  W-ENC-OUT               PIC X(200).
01  W-ENC-OUT-LEN           PIC 9(4).
01  W-ENC-IN-LEN            PIC 9(4).
01  W-ENC-I                 PIC 9(4).
01  W-ENC-BYTE              PIC 9(3).
01  W-ENC-HI                PIC 9(3).
01  W-ENC-LO                PIC 9(3).
01  W-QS                    PIC X(500).

*> Edit mode
01  W-EDIT-ID-RAW           PIC X(10).
01  W-EDIT-ID               PIC 9(6) VALUE 0.
01  W-EDIT-MODE             PIC X VALUE "N".
01  W-EDIT-DATE             PIC X(10).
01  W-EDIT-CAT              PIC X(15).
01  W-EDIT-DESC             PIC X(30).
01  W-EDIT-AMT-STR          PIC -------9.99.
01  W-UPD-ID                PIC 9(6).

*> CSV export
01  W-CSV-IN                PIC X(60).
01  W-CSV-OUT               PIC X(130).
01  W-CSV-IN-LEN            PIC 9(4).
01  W-CSV-OUT-LEN           PIC 9(4).
01  W-CSV-I                 PIC 9(4).
01  W-CSV-AMT               PIC -------9.99.

*> Monthly report
01  MONTH-TABLE.
    05  MONTH-COUNT         PIC 9(3) VALUE 0.
    05  MONTH-ENTRY         OCCURS 120 TIMES.
        10  MONTH-KEY       PIC X(7).
        10  MONTH-INCOME    PIC S9(9)V99.
        10  MONTH-EXPENSE   PIC S9(9)V99.
01  W-M-IDX                 PIC 9(3).
01  W-MAX-FLOW              PIC 9(9)V99 VALUE 0.
01  W-NET-AMT               PIC S9(9)V99.
01  W-ABS-EXP               PIC 9(9)V99.
01  W-BAR-PCT               PIC 9(3).
01  W-BAR-PCT-D             PIC ZZ9.

*> Input validation
01  W-VALID                 PIC X VALUE "N".
01  W-AMOUNT-RAW            PIC X(20).
01  W-AMOUNT-NUM            PIC S9(7)V99.
01  W-DATE-RAW              PIC X(10).
01  W-DESC-RAW              PIC X(30).
01  W-CAT-RAW               PIC X(15).

01  W-ERROR-MSG             PIC X(200) VALUE SPACES.
01  W-HAS-ERROR             PIC X VALUE "N".

*> Current date
01  W-CURRENT-DATE-STR      PIC X(21).
01  W-TODAY-STR             PIC X(10).

01  CAT-SUMMARY-TABLE.
    05  CAT-ENTRY           OCCURS 5 TIMES INDEXED BY CAT-IDX.
        10  CAT-NAME        PIC X(15).
        10  CAT-TOTAL       PIC S9(9)V99.

01  W-CMD                   PIC X(20).
01  W-DEL-ID-RAW            PIC X(10).
01  W-DEL-ID                PIC 9(6).
01  W-OPT-CURRENT           PIC X(15).

PROCEDURE DIVISION.
MAIN-LOGIC.
    PERFORM LOAD-CONFIG.
    PERFORM READ-CGI-ENV.
    PERFORM CHECK-SESSION.
    PERFORM PARSE-QUERY-STRING.
    IF W-METHOD = "POST"
        PERFORM READ-POST-BODY
        PERFORM PARSE-POST-BODY
        PERFORM HANDLE-ACTION
    END-IF.
    IF W-LOGGED-IN = "Y" AND W-EXPORT = "Y"
        PERFORM EXPORT-CSV
    ELSE
        PERFORM DISPLAY-PAGE
    END-IF.
    STOP RUN.

COMPUTE-ABS-NOW.
    MOVE FUNCTION CURRENT-DATE TO W-CURRENT-DATE-STR.
    COMPUTE W-ABS-NOW =
        FUNCTION INTEGER-OF-DATE(
            FUNCTION NUMVAL(W-CURRENT-DATE-STR(1:8))) * 86400
      + FUNCTION NUMVAL(W-CURRENT-DATE-STR(9:2)) * 3600
      + FUNCTION NUMVAL(W-CURRENT-DATE-STR(11:2)) * 60
      + FUNCTION NUMVAL(W-CURRENT-DATE-STR(13:2)).

LOAD-CONFIG.
    ACCEPT W-AUTH-MODE FROM ENVIRONMENT "LEDGER_AUTH_MODE".
    ACCEPT W-AUTH-VERIFIED FROM ENVIRONMENT "LEDGER_AUTH_VERIFIED".
    ACCEPT W-CSRF-TOKEN FROM ENVIRONMENT "LEDGER_CSRF_TOKEN".
    DISPLAY "LEDGER_USER" UPON ENVIRONMENT-NAME.
    ACCEPT W-CFG-USER FROM ENVIRONMENT-VALUE.
    IF W-CFG-USER = SPACES OR LOW-VALUES
        MOVE "micu" TO W-CFG-USER
    END-IF.
    DISPLAY "LEDGER_PASS" UPON ENVIRONMENT-NAME.
    ACCEPT W-CFG-PASS FROM ENVIRONMENT-VALUE.
    IF W-CFG-PASS = SPACES OR LOW-VALUES
        MOVE SPACES TO W-CFG-PASS
    END-IF.
*>  Daca LEDGER_PASS_HASH (SHA-256 hex) e setat, are prioritate
*>  si parola in clar nu mai e necesara in mediu.
    DISPLAY "LEDGER_PASS_HASH" UPON ENVIRONMENT-NAME.
    ACCEPT W-CFG-HASH FROM ENVIRONMENT-VALUE.
    IF W-CFG-HASH = LOW-VALUES
        MOVE SPACES TO W-CFG-HASH
    END-IF.
    DISPLAY "LEDGER_SESSION_TTL" UPON ENVIRONMENT-NAME.
    ACCEPT W-TTL-RAW FROM ENVIRONMENT-VALUE.
    IF W-TTL-RAW NOT = SPACES AND W-TTL-RAW NOT = LOW-VALUES
        IF FUNCTION TRIM(W-TTL-RAW) IS NUMERIC
            COMPUTE W-SESSION-TTL = FUNCTION MIN(86400,
                FUNCTION MAX(1, FUNCTION NUMVAL(W-TTL-RAW)))
        END-IF
    END-IF.
    MOVE FUNCTION CURRENT-DATE TO W-CURRENT-DATE-STR.
    STRING W-CURRENT-DATE-STR(1:4) "-"
           W-CURRENT-DATE-STR(5:2) "-"
           W-CURRENT-DATE-STR(7:2)
           DELIMITED BY SIZE INTO W-TODAY-STR.
    PERFORM COMPUTE-ABS-NOW.

READ-CGI-ENV.
    DISPLAY "HTTP_COOKIE" UPON ENVIRONMENT-NAME.
    ACCEPT W-COOKIE-ENV FROM ENVIRONMENT-VALUE.
    DISPLAY "QUERY_STRING" UPON ENVIRONMENT-NAME.
    ACCEPT W-QUERY-STRING FROM ENVIRONMENT-VALUE.
    DISPLAY "REQUEST_METHOD" UPON ENVIRONMENT-NAME.
    ACCEPT W-METHOD FROM ENVIRONMENT-VALUE.
    DISPLAY "REMOTE_ADDR" UPON ENVIRONMENT-NAME.
    ACCEPT W-REMOTE-ADDR FROM ENVIRONMENT-VALUE.
    IF W-REMOTE-ADDR = SPACES OR LOW-VALUES
        MOVE "-" TO W-REMOTE-ADDR
    END-IF.

CHECK-SESSION.
    MOVE SPACES TO W-COOKIE-TOKEN.
    MOVE 0 TO W-TOKEN-IDX.
    INSPECT W-COOKIE-ENV TALLYING W-TOKEN-IDX
            FOR CHARACTERS BEFORE INITIAL "session=".
    IF W-TOKEN-IDX < 1016
        COMPUTE W-I = W-TOKEN-IDX + 9
        IF W-I + 31 <= 1024
            MOVE W-COOKIE-ENV(W-I:32) TO W-COOKIE-TOKEN
        END-IF
    END-IF.
    IF W-COOKIE-TOKEN = SPACES
        EXIT PARAGRAPH
    END-IF.
    OPEN I-O SESSIONS-FILE.
    IF FS-SESSIONS NOT = "00"
        EXIT PARAGRAPH
    END-IF.
    MOVE W-COOKIE-TOKEN TO SESS-TOKEN.
    READ SESSIONS-FILE
        INVALID KEY CONTINUE
        NOT INVALID KEY
            IF W-ABS-NOW <= SESS-EXP
                MOVE "Y" TO W-LOGGED-IN
            ELSE
                DELETE SESSIONS-FILE RECORD
            END-IF
    END-READ.
    CLOSE SESSIONS-FILE.

PARSE-QUERY-STRING.
    IF W-QUERY-STRING = SPACES
        EXIT PARAGRAPH
    END-IF.
    MOVE SPACES TO W-PAIRS.
    UNSTRING W-QUERY-STRING DELIMITED BY "&"
        INTO W-PAIR(1), W-PAIR(2), W-PAIR(3), W-PAIR(4), W-PAIR(5),
             W-PAIR(6), W-PAIR(7), W-PAIR(8), W-PAIR(9), W-PAIR(10),
             W-PAIR(11), W-PAIR(12), W-PAIR(13), W-PAIR(14), W-PAIR(15),
             W-PAIR(16), W-PAIR(17), W-PAIR(18), W-PAIR(19), W-PAIR(20)
    END-UNSTRING.
    PERFORM VARYING W-QUERY-I FROM 1 BY 1 UNTIL W-QUERY-I > 20
        IF W-PAIR(W-QUERY-I) NOT = SPACES
            MOVE SPACES TO W-PAIR-KEY
            MOVE SPACES TO W-PAIR-VAL
            UNSTRING W-PAIR(W-QUERY-I) DELIMITED BY "="
                INTO W-PAIR-KEY, W-PAIR-VAL
            END-UNSTRING
            MOVE W-PAIR-VAL TO W-URL-IN
            PERFORM URL-DECODE
            EVALUATE W-PAIR-KEY
                WHEN "filter"
                    MOVE W-URL-OUT TO W-FILTER-CAT
                WHEN "sort"
                    MOVE W-URL-OUT TO W-SORT-BY
                WHEN "from"
                    MOVE W-URL-OUT(1:10) TO W-FROM-DATE
                WHEN "to"
                    MOVE W-URL-OUT(1:10) TO W-TO-DATE
                WHEN "view"
                    MOVE W-URL-OUT(1:10) TO W-VIEW
                WHEN "export"
                    IF W-URL-OUT(1:3) = "csv"
                        MOVE "Y" TO W-EXPORT
                    END-IF
                WHEN "edit"
                    MOVE W-URL-OUT(1:10) TO W-EDIT-ID-RAW
                    PERFORM PARSE-EDIT-ID
                WHEN "q"
                    MOVE W-URL-OUT(1:30) TO W-SEARCH-Q
                WHEN "page"
                    MOVE W-URL-OUT(1:10) TO W-PAGE-RAW
                    PERFORM PARSE-PAGE
            END-EVALUATE
        END-IF
    END-PERFORM.
    PERFORM SANITIZE-RANGE-DATES.
    IF FUNCTION TRIM(W-SEARCH-Q) = SPACES
        MOVE SPACES TO W-SEARCH-Q
        MOVE 0 TO W-Q-LEN
    ELSE
        MOVE FUNCTION LOWER-CASE(FUNCTION TRIM(W-SEARCH-Q))
            TO W-Q-LC
        COMPUTE W-Q-LEN =
            FUNCTION LENGTH(FUNCTION TRIM(W-SEARCH-Q))
    END-IF.

PARSE-PAGE.
    MOVE "Y" TO W-VALID.
    IF FUNCTION TRIM(W-PAGE-RAW) = SPACES
        MOVE "N" TO W-VALID
    END-IF.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 10
        IF W-PAGE-RAW(W-I:1) NOT = SPACE
            EVALUATE W-PAGE-RAW(W-I:1)
                WHEN "0" THRU "9" CONTINUE
                WHEN OTHER MOVE "N" TO W-VALID
            END-EVALUATE
        END-IF
    END-PERFORM.
    IF W-VALID = "Y"
        COMPUTE W-PAGE = FUNCTION MIN(
            FUNCTION MAX(FUNCTION NUMVAL(W-PAGE-RAW), 1), 9999)
    ELSE
        MOVE 1 TO W-PAGE
    END-IF.

PARSE-EDIT-ID.
    MOVE "Y" TO W-VALID.
    IF FUNCTION TRIM(W-EDIT-ID-RAW) = SPACES
        MOVE "N" TO W-VALID
    END-IF.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 10
        IF W-EDIT-ID-RAW(W-I:1) NOT = SPACE
            EVALUATE W-EDIT-ID-RAW(W-I:1)
                WHEN "0" THRU "9" CONTINUE
                WHEN OTHER MOVE "N" TO W-VALID
            END-EVALUATE
        END-IF
    END-PERFORM.
    IF W-VALID = "Y"
        COMPUTE W-EDIT-ID = FUNCTION NUMVAL(W-EDIT-ID-RAW)
    ELSE
        MOVE 0 TO W-EDIT-ID
    END-IF.

SANITIZE-RANGE-DATES.
    IF W-FROM-DATE NOT = SPACES
        MOVE W-FROM-DATE TO W-DATE-RAW
        PERFORM VALIDATE-DATE
        IF W-VALID NOT = "Y"
            MOVE SPACES TO W-FROM-DATE
        END-IF
    END-IF.
    IF W-TO-DATE NOT = SPACES
        MOVE W-TO-DATE TO W-DATE-RAW
        PERFORM VALIDATE-DATE
        IF W-VALID NOT = "Y"
            MOVE SPACES TO W-TO-DATE
        END-IF
    END-IF.

READ-POST-BODY.
    DISPLAY "CONTENT_LENGTH" UPON ENVIRONMENT-NAME.
    ACCEPT W-CONTENT-LEN-STR FROM ENVIRONMENT-VALUE.
    IF W-CONTENT-LEN-STR = SPACES OR LOW-VALUES
        MOVE 0 TO W-CONTENT-LEN
    ELSE
        MOVE FUNCTION NUMVAL(W-CONTENT-LEN-STR) TO W-CONTENT-LEN
    END-IF.
    IF W-CONTENT-LEN > 4096
        MOVE 4096 TO W-CONTENT-LEN
    END-IF.
    IF W-CONTENT-LEN > 0
        ACCEPT W-POST-DATA FROM SYSIN
    END-IF.

PARSE-POST-BODY.
    MOVE 0 TO FORM-COUNT.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 20
        MOVE SPACES TO FORM-KEY(W-I)
        MOVE SPACES TO FORM-VALUE(W-I)
    END-PERFORM.
    IF W-POST-DATA = SPACES
        EXIT PARAGRAPH
    END-IF.
    MOVE SPACES TO W-PAIRS.
    UNSTRING W-POST-DATA DELIMITED BY "&"
        INTO W-PAIR(1), W-PAIR(2), W-PAIR(3), W-PAIR(4), W-PAIR(5),
             W-PAIR(6), W-PAIR(7), W-PAIR(8), W-PAIR(9), W-PAIR(10),
             W-PAIR(11), W-PAIR(12), W-PAIR(13), W-PAIR(14), W-PAIR(15),
             W-PAIR(16), W-PAIR(17), W-PAIR(18), W-PAIR(19), W-PAIR(20)
    END-UNSTRING.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 20
        IF W-PAIR(W-I) NOT = SPACES
            MOVE SPACES TO W-PAIR-KEY
            MOVE SPACES TO W-PAIR-VAL
            UNSTRING W-PAIR(W-I) DELIMITED BY "="
                INTO W-PAIR-KEY, W-PAIR-VAL
            END-UNSTRING
            MOVE W-PAIR-VAL TO W-URL-IN
            PERFORM URL-DECODE
            ADD 1 TO FORM-COUNT
            MOVE W-PAIR-KEY TO FORM-KEY(FORM-COUNT)
            MOVE W-URL-OUT TO FORM-VALUE(FORM-COUNT)
        END-IF
    END-PERFORM.

GET-FORM-VALUE.
    MOVE SPACES TO W-VALUE-OUT.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > FORM-COUNT
        IF FORM-KEY(W-I) = W-KEY-LOOKUP
            MOVE FORM-VALUE(W-I) TO W-VALUE-OUT
            EXIT PERFORM
        END-IF
    END-PERFORM.

URL-DECODE.
    MOVE SPACES TO W-URL-OUT.
    MOVE 0 TO W-URL-OUT-LEN.
    MOVE 0 TO W-URL-IN-LEN.
    PERFORM VARYING W-UD-I FROM 500 BY -1
            UNTIL W-UD-I = 0 OR W-URL-IN(W-UD-I:1) NOT = SPACE
        CONTINUE
    END-PERFORM.
    MOVE W-UD-I TO W-URL-IN-LEN.
    MOVE 1 TO W-UD-I.
    PERFORM UNTIL W-UD-I > W-URL-IN-LEN
        EVALUATE W-URL-IN(W-UD-I:1)
            WHEN "+"
                ADD 1 TO W-URL-OUT-LEN
                MOVE " " TO W-URL-OUT(W-URL-OUT-LEN:1)
                ADD 1 TO W-UD-I
            WHEN "%"
                IF W-UD-I + 2 <= W-URL-IN-LEN
                    COMPUTE W-UD-J = W-UD-I + 1
                    MOVE W-URL-IN(W-UD-J:2) TO W-HEX-PAIR
                    PERFORM HEX-TO-CHAR
                    ADD 1 TO W-URL-OUT-LEN
                    MOVE W-HEX-CHAR TO W-URL-OUT(W-URL-OUT-LEN:1)
                    ADD 3 TO W-UD-I
                ELSE
                    ADD 1 TO W-URL-OUT-LEN
                    MOVE W-URL-IN(W-UD-I:1)
                        TO W-URL-OUT(W-URL-OUT-LEN:1)
                    ADD 1 TO W-UD-I
                END-IF
            WHEN OTHER
                ADD 1 TO W-URL-OUT-LEN
                MOVE W-URL-IN(W-UD-I:1)
                    TO W-URL-OUT(W-URL-OUT-LEN:1)
                ADD 1 TO W-UD-I
        END-EVALUATE
    END-PERFORM.

HEX-TO-CHAR.
    MOVE 0 TO W-HEX-NUM.
    PERFORM VARYING W-UD-J FROM 1 BY 1 UNTIL W-UD-J > 2
        IF W-UD-J > 1
            MULTIPLY 16 BY W-HEX-NUM
        END-IF
        EVALUATE W-HEX-PAIR(W-UD-J:1)
            WHEN "0" CONTINUE
            WHEN "1" ADD 1 TO W-HEX-NUM
            WHEN "2" ADD 2 TO W-HEX-NUM
            WHEN "3" ADD 3 TO W-HEX-NUM
            WHEN "4" ADD 4 TO W-HEX-NUM
            WHEN "5" ADD 5 TO W-HEX-NUM
            WHEN "6" ADD 6 TO W-HEX-NUM
            WHEN "7" ADD 7 TO W-HEX-NUM
            WHEN "8" ADD 8 TO W-HEX-NUM
            WHEN "9" ADD 9 TO W-HEX-NUM
            WHEN "a" WHEN "A" ADD 10 TO W-HEX-NUM
            WHEN "b" WHEN "B" ADD 11 TO W-HEX-NUM
            WHEN "c" WHEN "C" ADD 12 TO W-HEX-NUM
            WHEN "d" WHEN "D" ADD 13 TO W-HEX-NUM
            WHEN "e" WHEN "E" ADD 14 TO W-HEX-NUM
            WHEN "f" WHEN "F" ADD 15 TO W-HEX-NUM
            WHEN OTHER CONTINUE
        END-EVALUATE
    END-PERFORM.
    IF W-HEX-NUM < 32 OR W-HEX-NUM = 127
        MOVE "?" TO W-HEX-CHAR
    ELSE
        MOVE FUNCTION CHAR(W-HEX-NUM + 1) TO W-HEX-CHAR
    END-IF.

HTML-ESCAPE.
    MOVE SPACES TO W-ESC-OUT.
    MOVE 0 TO W-ESC-OUT-LEN.
    MOVE 0 TO W-ESC-IN-LEN.
    PERFORM VARYING W-ESC-I FROM 500 BY -1
            UNTIL W-ESC-I = 0 OR W-ESC-IN(W-ESC-I:1) NOT = SPACE
        CONTINUE
    END-PERFORM.
    MOVE W-ESC-I TO W-ESC-IN-LEN.
    PERFORM VARYING W-ESC-I FROM 1 BY 1
            UNTIL W-ESC-I > W-ESC-IN-LEN
        MOVE W-ESC-IN(W-ESC-I:1) TO W-CH
        EVALUATE W-CH
            WHEN "&"
                COMPUTE W-ESC-J = W-ESC-OUT-LEN + 1
                MOVE "&amp;" TO W-ESC-OUT(W-ESC-J:5)
                ADD 5 TO W-ESC-OUT-LEN
            WHEN "<"
                COMPUTE W-ESC-J = W-ESC-OUT-LEN + 1
                MOVE "&lt;" TO W-ESC-OUT(W-ESC-J:4)
                ADD 4 TO W-ESC-OUT-LEN
            WHEN ">"
                COMPUTE W-ESC-J = W-ESC-OUT-LEN + 1
                MOVE "&gt;" TO W-ESC-OUT(W-ESC-J:4)
                ADD 4 TO W-ESC-OUT-LEN
            WHEN '"'
                COMPUTE W-ESC-J = W-ESC-OUT-LEN + 1
                MOVE "&quot;" TO W-ESC-OUT(W-ESC-J:6)
                ADD 6 TO W-ESC-OUT-LEN
            WHEN "'"
                COMPUTE W-ESC-J = W-ESC-OUT-LEN + 1
                MOVE "&#39;" TO W-ESC-OUT(W-ESC-J:5)
                ADD 5 TO W-ESC-OUT-LEN
            WHEN OTHER
                ADD 1 TO W-ESC-OUT-LEN
                MOVE W-CH TO W-ESC-OUT(W-ESC-OUT-LEN:1)
        END-EVALUATE
    END-PERFORM.

GENERATE-TOKEN.
*> Linux getrandom blocks until OS entropy is available; no weak fallback.
    MOVE "N" TO W-TOKEN-OK.
    MOVE SPACES TO W-NEW-TOKEN.
    CALL STATIC "getrandom" USING
        BY REFERENCE W-RANDOM-BYTES
        BY VALUE 16 BY VALUE 0 RETURNING W-RANDOM-COUNT
    END-CALL.
    IF W-RANDOM-COUNT NOT = 16
        EXIT PARAGRAPH
    END-IF.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 16
        COMPUTE W-RANDOM-BYTE =
            FUNCTION ORD(W-RANDOM-BYTES(W-I:1)) - 1
        COMPUTE W-J = (W-I - 1) * 2 + 1
        COMPUTE W-ENC-HI = FUNCTION INTEGER(W-RANDOM-BYTE / 16) + 1
        COMPUTE W-ENC-LO = FUNCTION MOD(W-RANDOM-BYTE, 16) + 1
        MOVE HEX-DIGITS(W-ENC-HI:1) TO W-NEW-TOKEN(W-J:1)
        ADD 1 TO W-J
        MOVE HEX-DIGITS(W-ENC-LO:1) TO W-NEW-TOKEN(W-J:1)
    END-PERFORM.
    MOVE "Y" TO W-TOKEN-OK.

HANDLE-ACTION.
    MOVE "cmd" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT TO W-CMD.
    EVALUATE TRUE
        WHEN W-CMD = "login"
            PERFORM DO-LOGIN
        WHEN W-CMD = "logout"
            IF W-LOGGED-IN = "Y"
                PERFORM DO-LOGOUT
            END-IF
        WHEN W-CMD = "update" AND W-LOGGED-IN = "Y"
            PERFORM DO-UPDATE
        WHEN W-CMD = "add" AND W-LOGGED-IN = "Y"
            PERFORM DO-ADD
        WHEN W-CMD = "del" AND W-LOGGED-IN = "Y"
            PERFORM DO-DELETE
        WHEN OTHER
            CONTINUE
    END-EVALUATE.

DO-LOGIN.
    MOVE "user" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:40) TO W-LOGIN-USER.
    MOVE "pass" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:40) TO W-LOGIN-PASS.

    PERFORM CHECK-LOCKOUT.
    IF W-LOCKED = "Y"
        MOVE "Prea multe incercari esuate. Reincearca in 15 minute."
            TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        MOVE "LOCKOUT" TO W-AUDIT-ACTION
        MOVE "login blocat (fereastra activa)" TO W-AUDIT-DETAIL
        PERFORM WRITE-AUDIT
        EXIT PARAGRAPH
    END-IF.

    PERFORM VERIFY-CREDENTIALS.
    IF W-VALID = "Y"
        PERFORM GENERATE-TOKEN
        IF W-TOKEN-OK NOT = "Y"
            MOVE "Generatorul de sesiuni este indisponibil."
                TO W-ERROR-MSG
            MOVE "Y" TO W-HAS-ERROR
            EXIT PARAGRAPH
        END-IF
        MOVE W-NEW-TOKEN TO W-COOKIE-TOKEN
        PERFORM STORE-SESSION
        IF W-SESSION-STORED NOT = "Y"
            MOVE "Sesiunea nu a putut fi salvata." TO W-ERROR-MSG
            MOVE "Y" TO W-HAS-ERROR
            EXIT PARAGRAPH
        END-IF
        PERFORM CLEAR-LOCKOUT
        MOVE "Y" TO W-LOGGED-IN
        MOVE "Y" TO W-SET-COOKIE
        MOVE "LOGIN" TO W-AUDIT-ACTION
        MOVE "autentificare reusita" TO W-AUDIT-DETAIL
        PERFORM WRITE-AUDIT
    ELSE
        PERFORM RECORD-LOGIN-FAIL
        MOVE "User sau parola incorecte." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        MOVE "LOGIN-FAIL" TO W-AUDIT-ACTION
        MOVE SPACES TO W-AUDIT-DETAIL
        STRING "user incercat: "
               FUNCTION TRIM(W-LOGIN-USER)
            DELIMITED BY SIZE INTO W-AUDIT-DETAIL
        PERFORM WRITE-AUDIT
    END-IF.

VERIFY-CREDENTIALS.
*>  Cu LEDGER_PASS_HASH setat se compara SHA-256(parola introdusa);
*>  altfel se cade pe compararea in clar cu LEDGER_PASS.
    MOVE "N" TO W-VALID.
    IF FUNCTION TRIM(W-LOGIN-USER) NOT = FUNCTION TRIM(W-CFG-USER)
        EXIT PARAGRAPH
    END-IF.
    IF W-AUTH-MODE = "scrypt"
        IF W-AUTH-VERIFIED = "Y"
            MOVE "Y" TO W-VALID
        END-IF
        EXIT PARAGRAPH
    END-IF.
    IF W-CFG-HASH NOT = SPACES
        MOVE SPACES TO W-HASH-IN
        MOVE FUNCTION TRIM(W-LOGIN-PASS) TO W-HASH-IN
        COMPUTE W-HASH-LEN =
            FUNCTION LENGTH(FUNCTION TRIM(W-LOGIN-PASS))
        IF FUNCTION TRIM(W-LOGIN-PASS) = SPACES
            MOVE 0 TO W-HASH-LEN
        END-IF
        CALL "SHA256" USING W-HASH-IN W-HASH-LEN W-HASH-OUT
        IF W-HASH-OUT =
           FUNCTION LOWER-CASE(FUNCTION TRIM(W-CFG-HASH))
            MOVE "Y" TO W-VALID
        END-IF
    ELSE
        IF W-CFG-PASS NOT = SPACES AND LOW-VALUES
           AND FUNCTION TRIM(W-LOGIN-PASS) = FUNCTION TRIM(W-CFG-PASS)
            MOVE "Y" TO W-VALID
        END-IF
    END-IF.

STORE-SESSION.
    MOVE "N" TO W-SESSION-STORED.
    OPEN I-O SESSIONS-FILE.
    IF FS-SESSIONS = "35"
        OPEN OUTPUT SESSIONS-FILE
        CLOSE SESSIONS-FILE
        OPEN I-O SESSIONS-FILE
    END-IF.
    IF FS-SESSIONS NOT = "00"
        EXIT PARAGRAPH
    END-IF.
    PERFORM PURGE-EXPIRED-SESSIONS.
    MOVE W-NEW-TOKEN TO SESS-TOKEN.
    COMPUTE SESS-EXP = W-ABS-NOW + W-SESSION-TTL.
    MOVE W-REMOTE-ADDR TO SESS-IP.
    WRITE SESS-RECORD
        INVALID KEY CONTINUE
        NOT INVALID KEY MOVE "Y" TO W-SESSION-STORED
    END-WRITE.
    CLOSE SESSIONS-FILE.

PURGE-EXPIRED-SESSIONS.
*>  Curatare lenesa: la fiecare login se sterg sesiunile expirate.
*>  Fisierul e deja deschis I-O de catre STORE-SESSION.
    MOVE LOW-VALUES TO SESS-TOKEN.
    START SESSIONS-FILE KEY IS GREATER THAN SESS-TOKEN
        INVALID KEY EXIT PARAGRAPH
    END-START.
    MOVE "N" TO W-EOF.
    PERFORM UNTIL W-EOF = "Y"
        READ SESSIONS-FILE NEXT
            AT END MOVE "Y" TO W-EOF
            NOT AT END
                IF SESS-EXP < W-ABS-NOW
                    DELETE SESSIONS-FILE RECORD
                END-IF
        END-READ
    END-PERFORM.
    MOVE "N" TO W-EOF.

CHECK-LOCKOUT.
    MOVE "N" TO W-LOCKED.
    OPEN I-O LOCKOUT-FILE.
    IF FS-LOCKOUT NOT = "00"
        EXIT PARAGRAPH
    END-IF.
    MOVE W-REMOTE-ADDR TO LOCK-IP.
    READ LOCKOUT-FILE
        INVALID KEY CONTINUE
        NOT INVALID KEY
            IF W-ABS-NOW <= LOCK-WIN-EXP
                IF LOCK-FAILS >= W-MAX-FAILS
                    MOVE "Y" TO W-LOCKED
                END-IF
            ELSE
                DELETE LOCKOUT-FILE RECORD
            END-IF
    END-READ.
    CLOSE LOCKOUT-FILE.

RECORD-LOGIN-FAIL.
    OPEN I-O LOCKOUT-FILE.
    IF FS-LOCKOUT = "35"
        OPEN OUTPUT LOCKOUT-FILE
        CLOSE LOCKOUT-FILE
        OPEN I-O LOCKOUT-FILE
    END-IF.
    IF FS-LOCKOUT NOT = "00"
        EXIT PARAGRAPH
    END-IF.
    MOVE W-REMOTE-ADDR TO LOCK-IP.
    READ LOCKOUT-FILE
        INVALID KEY
            MOVE W-REMOTE-ADDR TO LOCK-IP
            MOVE 1 TO LOCK-FAILS
            COMPUTE LOCK-WIN-EXP = W-ABS-NOW + W-LOCK-WINDOW
            WRITE LOCK-RECORD
                INVALID KEY CONTINUE
            END-WRITE
        NOT INVALID KEY
            IF W-ABS-NOW > LOCK-WIN-EXP
                MOVE 1 TO LOCK-FAILS
                COMPUTE LOCK-WIN-EXP = W-ABS-NOW + W-LOCK-WINDOW
            ELSE
                ADD 1 TO LOCK-FAILS
            END-IF
            REWRITE LOCK-RECORD
                INVALID KEY CONTINUE
            END-REWRITE
    END-READ.
    CLOSE LOCKOUT-FILE.

CLEAR-LOCKOUT.
    OPEN I-O LOCKOUT-FILE.
    IF FS-LOCKOUT NOT = "00"
        EXIT PARAGRAPH
    END-IF.
    MOVE W-REMOTE-ADDR TO LOCK-IP.
    READ LOCKOUT-FILE
        INVALID KEY CONTINUE
        NOT INVALID KEY DELETE LOCKOUT-FILE RECORD
    END-READ.
    CLOSE LOCKOUT-FILE.

DO-LOGOUT.
    OPEN I-O SESSIONS-FILE.
    IF FS-SESSIONS = "00"
        MOVE W-COOKIE-TOKEN TO SESS-TOKEN
        READ SESSIONS-FILE
            INVALID KEY CONTINUE
            NOT INVALID KEY DELETE SESSIONS-FILE RECORD
        END-READ
        CLOSE SESSIONS-FILE
    END-IF.
    MOVE "N" TO W-LOGGED-IN.
    MOVE SPACES TO W-COOKIE-TOKEN.
    MOVE "L" TO W-SET-COOKIE.
    MOVE "LOGOUT" TO W-AUDIT-ACTION.
    MOVE "sesiune inchisa" TO W-AUDIT-DETAIL.
    PERFORM WRITE-AUDIT.

DO-ADD.
    MOVE "date" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:10) TO W-DATE-RAW.

    MOVE "cat" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:15) TO W-CAT-RAW.

    MOVE "desc" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:30) TO W-DESC-RAW.

    MOVE "amount" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:20) TO W-AMOUNT-RAW.

    PERFORM VALIDATE-DATE.
    IF W-VALID NOT = "Y"
        MOVE "Data invalida (format YYYY-MM-DD)." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.

    PERFORM VALIDATE-CATEGORY.
    IF W-VALID NOT = "Y"
        MOVE "Categorie invalida." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.

    IF FUNCTION TRIM(W-DESC-RAW) = SPACES
        MOVE "Descrierea este obligatorie." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.

    PERFORM VALIDATE-AMOUNT.
    IF W-VALID NOT = "Y"
        MOVE "Suma invalida (ex: 123.45 sau -50.00)." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.

    PERFORM WRITE-TRANSACTION.

WRITE-TRANSACTION.
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "35"
        OPEN OUTPUT TRANSACTIONS-FILE
        CLOSE TRANSACTIONS-FILE
        OPEN I-O TRANSACTIONS-FILE
    END-IF.
    IF FS-LEDGER NOT = "00"
        MOVE "Eroare la deschiderea fisierului." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.
    MOVE 0 TO W-LAST-ID.
    MOVE HIGH-VALUES TO TRANS-ID.
    START TRANSACTIONS-FILE KEY IS LESS THAN TRANS-ID
        INVALID KEY MOVE 0 TO W-LAST-ID
        NOT INVALID KEY
            READ TRANSACTIONS-FILE PREVIOUS
                AT END MOVE 0 TO W-LAST-ID
                NOT AT END MOVE TRANS-ID TO W-LAST-ID
            END-READ
    END-START.
    IF W-LAST-ID = 999999
        CLOSE TRANSACTIONS-FILE
        MOVE "Limita de tranzactii a fost atinsa." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.
    COMPUTE TRANS-ID = W-LAST-ID + 1.
    MOVE W-DATE-RAW TO TRANS-DATE.
    MOVE W-CAT-RAW TO TRANS-CAT.
    MOVE W-DESC-RAW TO TRANS-DESC.
    MOVE W-AMOUNT-NUM TO TRANS-AMOUNT.
    WRITE TRANS-RECORD
        INVALID KEY
            MOVE "Eroare la scriere (ID duplicat)." TO W-ERROR-MSG
            MOVE "Y" TO W-HAS-ERROR
        NOT INVALID KEY
            MOVE "ADD" TO W-AUDIT-ACTION
            MOVE SPACES TO W-AUDIT-DETAIL
            STRING "id=" TRANS-ID " "
                   FUNCTION TRIM(W-DESC-RAW)
                DELIMITED BY SIZE INTO W-AUDIT-DETAIL
            PERFORM WRITE-AUDIT
    END-WRITE.
    CLOSE TRANSACTIONS-FILE.

DO-UPDATE.
    MOVE "id" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:10) TO W-EDIT-ID-RAW.
    PERFORM PARSE-EDIT-ID.
    IF W-EDIT-ID = 0
        MOVE "ID invalid pentru actualizare." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.
    MOVE W-EDIT-ID TO W-UPD-ID.
    MOVE 0 TO W-EDIT-ID.

    MOVE "date" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:10) TO W-DATE-RAW.

    MOVE "cat" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:15) TO W-CAT-RAW.

    MOVE "desc" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:30) TO W-DESC-RAW.

    MOVE "amount" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:20) TO W-AMOUNT-RAW.

    PERFORM VALIDATE-DATE.
    IF W-VALID NOT = "Y"
        MOVE "Data invalida (format YYYY-MM-DD)." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.
    PERFORM VALIDATE-CATEGORY.
    IF W-VALID NOT = "Y"
        MOVE "Categorie invalida." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.
    IF FUNCTION TRIM(W-DESC-RAW) = SPACES
        MOVE "Descrierea este obligatorie." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.
    PERFORM VALIDATE-AMOUNT.
    IF W-VALID NOT = "Y"
        MOVE "Suma invalida (ex: 123.45 sau -50.00)." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.

    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER NOT = "00"
        MOVE "Eroare la deschiderea fisierului." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
        EXIT PARAGRAPH
    END-IF.
    MOVE W-UPD-ID TO TRANS-ID.
    READ TRANSACTIONS-FILE
        INVALID KEY
            MOVE "Tranzactia nu exista." TO W-ERROR-MSG
            MOVE "Y" TO W-HAS-ERROR
        NOT INVALID KEY
            MOVE W-DATE-RAW TO TRANS-DATE
            MOVE W-CAT-RAW TO TRANS-CAT
            MOVE W-DESC-RAW TO TRANS-DESC
            MOVE W-AMOUNT-NUM TO TRANS-AMOUNT
            REWRITE TRANS-RECORD
                INVALID KEY
                    MOVE "Eroare la actualizare." TO W-ERROR-MSG
                    MOVE "Y" TO W-HAS-ERROR
                NOT INVALID KEY
                    MOVE "UPDATE" TO W-AUDIT-ACTION
                    MOVE SPACES TO W-AUDIT-DETAIL
                    STRING "id=" TRANS-ID " "
                           FUNCTION TRIM(W-DESC-RAW)
                        DELIMITED BY SIZE INTO W-AUDIT-DETAIL
                    PERFORM WRITE-AUDIT
            END-REWRITE
    END-READ.
    CLOSE TRANSACTIONS-FILE.

DO-DELETE.
    MOVE "id" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT(1:10) TO W-DEL-ID-RAW.
    IF FUNCTION TRIM(W-DEL-ID-RAW) = SPACES
        EXIT PARAGRAPH
    END-IF.
    MOVE "Y" TO W-VALID.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 10
        IF W-DEL-ID-RAW(W-I:1) NOT = SPACE
            EVALUATE W-DEL-ID-RAW(W-I:1)
                WHEN "0" THRU "9" CONTINUE
                WHEN OTHER MOVE "N" TO W-VALID
            END-EVALUATE
        END-IF
    END-PERFORM.
    IF W-VALID NOT = "Y"
        EXIT PARAGRAPH
    END-IF.
    COMPUTE W-DEL-ID = FUNCTION NUMVAL(W-DEL-ID-RAW).
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "00"
        MOVE W-DEL-ID TO TRANS-ID
        READ TRANSACTIONS-FILE
            INVALID KEY CONTINUE
            NOT INVALID KEY
                MOVE "DELETE" TO W-AUDIT-ACTION
                MOVE SPACES TO W-AUDIT-DETAIL
                STRING "id=" TRANS-ID " "
                       FUNCTION TRIM(TRANS-DESC)
                    DELIMITED BY SIZE INTO W-AUDIT-DETAIL
                DELETE TRANSACTIONS-FILE RECORD
                PERFORM WRITE-AUDIT
        END-READ
        CLOSE TRANSACTIONS-FILE
    END-IF.

WRITE-AUDIT.
    OPEN EXTEND AUDIT-FILE.
    IF FS-AUDIT NOT = "00" AND FS-AUDIT NOT = "05"
        EXIT PARAGRAPH
    END-IF.
    MOVE FUNCTION CURRENT-DATE TO W-CURRENT-DATE-STR.
    MOVE SPACES TO AUDIT-REC.
    STRING W-CURRENT-DATE-STR(1:4) "-"
           W-CURRENT-DATE-STR(5:2) "-"
           W-CURRENT-DATE-STR(7:2) " "
           W-CURRENT-DATE-STR(9:2) ":"
           W-CURRENT-DATE-STR(11:2) ":"
           W-CURRENT-DATE-STR(13:2)
           " | " FUNCTION TRIM(W-REMOTE-ADDR)
           " | " FUNCTION TRIM(W-AUDIT-ACTION)
           " | " FUNCTION TRIM(W-AUDIT-DETAIL)
        DELIMITED BY SIZE INTO AUDIT-REC.
    WRITE AUDIT-REC.
    CLOSE AUDIT-FILE.

VALIDATE-AMOUNT.
    MOVE "Y" TO W-VALID.
    COMPUTE W-AMOUNT-LEN =
        FUNCTION LENGTH(FUNCTION TRIM(W-AMOUNT-RAW)).
    MOVE 0 TO W-AMOUNT-DIGITS W-AMOUNT-DECIMALS.
    MOVE "N" TO W-AMOUNT-DOT.
    IF W-AMOUNT-LEN = 0
        MOVE "N" TO W-VALID
        EXIT PARAGRAPH
    END-IF.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > W-AMOUNT-LEN
        EVALUATE W-AMOUNT-RAW(W-I:1)
            WHEN "0" THRU "9"
                ADD 1 TO W-AMOUNT-DIGITS
                IF W-AMOUNT-DOT = "Y"
                    ADD 1 TO W-AMOUNT-DECIMALS
                END-IF
            WHEN "."
                IF W-AMOUNT-DOT = "Y"
                    MOVE "N" TO W-VALID
                END-IF
                MOVE "Y" TO W-AMOUNT-DOT
            WHEN "+" WHEN "-"
                IF W-I NOT = 1 MOVE "N" TO W-VALID END-IF
            WHEN OTHER MOVE "N" TO W-VALID
        END-EVALUATE
    END-PERFORM.
    IF W-AMOUNT-DIGITS = 0 OR W-AMOUNT-DECIMALS > 2
        MOVE "N" TO W-VALID
    END-IF.
    IF W-VALID = "Y"
        COMPUTE W-AMOUNT-WIDE = FUNCTION NUMVAL(W-AMOUNT-RAW)
            ON SIZE ERROR MOVE "N" TO W-VALID
        END-COMPUTE
        IF W-AMOUNT-WIDE > 9999999.99
           OR W-AMOUNT-WIDE < -9999999.99
            MOVE "N" TO W-VALID
        END-IF
        IF W-VALID = "Y"
            MOVE W-AMOUNT-WIDE TO W-AMOUNT-NUM
        END-IF
    END-IF.

VALIDATE-DATE.
    MOVE "Y" TO W-VALID.
    IF FUNCTION TRIM(W-DATE-RAW) = SPACES
        MOVE "N" TO W-VALID
        EXIT PARAGRAPH
    END-IF.
    IF W-DATE-RAW(5:1) NOT = "-" OR W-DATE-RAW(8:1) NOT = "-"
        MOVE "N" TO W-VALID
        EXIT PARAGRAPH
    END-IF.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 10
        IF W-I NOT = 5 AND W-I NOT = 8
            EVALUATE W-DATE-RAW(W-I:1)
                WHEN "0" THRU "9" CONTINUE
                WHEN OTHER MOVE "N" TO W-VALID
            END-EVALUATE
        END-IF
    END-PERFORM.
    IF W-VALID = "Y"
        IF W-DATE-RAW(6:2) < "01" OR W-DATE-RAW(6:2) > "12"
            MOVE "N" TO W-VALID
        END-IF
        IF W-DATE-RAW(9:2) < "01" OR W-DATE-RAW(9:2) > "31"
            MOVE "N" TO W-VALID
        END-IF
    END-IF.
    IF W-VALID = "Y"
        STRING W-DATE-RAW(1:4) W-DATE-RAW(6:2)
               W-DATE-RAW(9:2) INTO W-DATE-NUM
        END-STRING
        IF FUNCTION TEST-DATE-YYYYMMDD(W-DATE-NUM) NOT = 0
            MOVE "N" TO W-VALID
        END-IF
    END-IF.

VALIDATE-CATEGORY.
    MOVE "N" TO W-VALID.
    EVALUATE FUNCTION TRIM(W-CAT-RAW)
        WHEN "Venituri" MOVE "Y" TO W-VALID
        WHEN "Locuinta" MOVE "Y" TO W-VALID
        WHEN "Mancare" MOVE "Y" TO W-VALID
        WHEN "Hobby" MOVE "Y" TO W-VALID
        WHEN "Utilitati" MOVE "Y" TO W-VALID
        WHEN OTHER MOVE "N" TO W-VALID
    END-EVALUATE.

DISPLAY-PAGE.
    DISPLAY "Content-type: text/html; charset=utf-8".
    IF W-SET-COOKIE = "Y"
        DISPLAY "Set-Cookie: session=" W-NEW-TOKEN
                "; Path=/; HttpOnly; Secure; SameSite=Strict"
                "; Max-Age=" W-SESSION-TTL
    END-IF.
    IF W-SET-COOKIE = "L"
        DISPLAY "Set-Cookie: session=; Path=/; HttpOnly; Secure; "
                "SameSite=Strict; Max-Age=0"
    END-IF.
    DISPLAY " ".
    DISPLAY "<!DOCTYPE html><html lang='ro'><head><meta charset='utf-8'>".
    DISPLAY "<meta name='viewport' content='width=device-width, "
            "initial-scale=1'>".
    DISPLAY "<title>Ledger of Ages</title>".
    DISPLAY "<style>body{font-family:sans-serif;"
            "background:#f8fafc;padding:2rem;}".
    DISPLAY ".card{background:white;border-radius:12px;padding:1.5rem;"
            "margin:1rem auto;max-width:1000px;"
            "box-shadow:0 2px 4px rgba(0,0,0,0.1);}".
    DISPLAY "table{width:100%;border-collapse:collapse;}".
    DISPLAY "th{text-align:left;background:#f1f5f9;padding:8px;}".
    DISPLAY "td{padding:8px;border-bottom:1px solid #eee;}".
    DISPLAY ".btn{background:#1e293b;color:white;border:none;"
            "padding:8px 16px;border-radius:6px;cursor:pointer;"
            "display:inline-block;font-size:0.9rem;}".
    DISPLAY ".btn-del{background:#ef4444;}".
    DISPLAY ".btn-edit{background:#0ea5e9;text-decoration:none;"
            "padding:6px 12px;}".
    DISPLAY ".err{background:#fee2e2;color:#991b1b;padding:12px;"
            "border-radius:8px;margin:1rem auto;max-width:1000px;}".
    DISPLAY "input,select{padding:6px;border:1px solid #cbd5e1;"
            "border-radius:4px;}".
    DISPLAY ".pos{color:#16a34a;}.neg{color:#dc2626;}".
    DISPLAY "nav a{margin-right:14px;color:#1e293b;font-weight:600;"
            "text-decoration:none;}nav a:hover{"
            "text-decoration:underline;}".
    DISPLAY ".barwrap{background:#f1f5f9;border-radius:4px;"
            "overflow:hidden;height:8px;margin:3px 0;}".
    DISPLAY ".bar-in{background:#16a34a;height:8px;}".
    DISPLAY ".bar-ex{background:#dc2626;height:8px;}".
    DISPLAY "@media (prefers-color-scheme: dark){".
    DISPLAY "body{background:#0f172a;color:#e2e8f0;}".
    DISPLAY ".card{background:#1e293b;box-shadow:0 2px 4px "
            "rgba(0,0,0,0.4);}".
    DISPLAY "th{background:#334155;color:#e2e8f0;}".
    DISPLAY "td{border-bottom:1px solid #334155;}".
    DISPLAY "input,select{background:#0f172a;color:#e2e8f0;"
            "border-color:#475569;}".
    DISPLAY "nav a{color:#e2e8f0;}".
    DISPLAY ".btn{background:#475569;}".
    DISPLAY ".btn-del{background:#b91c1c;}".
    DISPLAY ".btn-edit{background:#0369a1;}".
    DISPLAY ".err{background:#450a0a;color:#fecaca;}".
    DISPLAY ".pos{color:#4ade80;}.neg{color:#f87171;}".
    DISPLAY ".barwrap{background:#334155;}".
    DISPLAY "}".
    DISPLAY "</style></head><body>".

    IF W-HAS-ERROR = "Y"
        MOVE W-ERROR-MSG TO W-ESC-IN
        PERFORM HTML-ESCAPE
        DISPLAY "<div class='err'>&#9888; "
                FUNCTION TRIM(W-ESC-OUT) "</div>"
    END-IF.

    IF W-LOGGED-IN = "N"
        PERFORM DISPLAY-LOGIN
    ELSE
        PERFORM DISPLAY-HEADER
        EVALUATE FUNCTION TRIM(W-VIEW)
            WHEN "REPORT"
                PERFORM DISPLAY-REPORT-VIEW
            WHEN "AUDIT"
                PERFORM DISPLAY-AUDIT-VIEW
            WHEN OTHER
                PERFORM DISPLAY-LEDGER-VIEW
        END-EVALUATE
    END-IF.
    DISPLAY "</body></html>".

DISPLAY-HEADER.
    MOVE W-CFG-USER TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<div class='card'><div style='display:flex;"
            "justify-content:space-between;align-items:center;"
            "flex-wrap:wrap;gap:8px;'>"
            "<h1 style='margin:0'>Ledger of Ages</h1>"
            "<nav><a href='?'>Tranzactii</a>"
            "<a href='?view=REPORT'>Raport lunar</a>"
            "<a href='?view=AUDIT'>Audit</a></nav>"
            "<span>Logat ca <b>" FUNCTION TRIM(W-ESC-OUT) "</b> "
            "<form method='POST' style='display:inline'>"
            "<input type='hidden' name='csrf_token' value='"
            FUNCTION TRIM(W-CSRF-TOKEN) "'>"
            "<input type='hidden' name='cmd' value='logout'>"
            "<button type='submit' class='btn'>Logout</button>"
            "</form></span></div></div>".

DISPLAY-LEDGER-VIEW.
    PERFORM INITIALIZE-SUMMARY.
    PERFORM DISPLAY-TOOLBAR.
    MOVE 0 TO W-TOTAL-BALANCE.
    MOVE 0 TO W-ROW-COUNT.
    MOVE "N" TO W-EOF.
    PERFORM OPEN-LEDGER-FILE.
    IF FS-LEDGER = "00"
        PERFORM LOAD-EDIT-RECORD
        PERFORM DISPLAY-TABLE
        PERFORM CLOSE-LEDGER-FILE
        PERFORM DISPLAY-SUMMARY
    END-IF.
    PERFORM DISPLAY-ADD-FORM.

LOAD-EDIT-RECORD.
    MOVE "N" TO W-EDIT-MODE.
    IF W-EDIT-ID > 0
        MOVE W-EDIT-ID TO TRANS-ID
        READ TRANSACTIONS-FILE
            INVALID KEY CONTINUE
            NOT INVALID KEY
                MOVE "Y" TO W-EDIT-MODE
                MOVE TRANS-DATE TO W-EDIT-DATE
                MOVE TRANS-CAT TO W-EDIT-CAT
                MOVE TRANS-DESC TO W-EDIT-DESC
                MOVE TRANS-AMOUNT TO W-EDIT-AMT-STR
        END-READ
    END-IF.

DISPLAY-LOGIN.
    DISPLAY "<div class='card' style='max-width:400px;margin-top:80px;'>"
            "<h2>Login</h2>"
            "<form method='POST'>"
            "<input type='hidden' name='csrf_token' value='"
            FUNCTION TRIM(W-CSRF-TOKEN) "'>"
            "<input type='hidden' name='cmd' value='login'>"
            "<p>User:<br>"
            "<input type='text' name='user' required "
            "maxlength='40' style='width:100%'></p>"
            "<p>Parola:<br>"
            "<input type='password' name='pass' required "
            "maxlength='40' style='width:100%'></p>"
            "<button type='submit' class='btn'>Intra</button>"
            "</form></div>".

DISPLAY-TOOLBAR.
    DISPLAY "<div class='card'><form method='GET' "
            "style='display:flex;gap:10px;flex-wrap:wrap;"
            "align-items:center;'>".
    DISPLAY "Filtru: <select name='filter'>".
    IF W-FILTER-CAT = "ALL"
        DISPLAY "<option value='ALL' selected>Toate</option>"
    ELSE
        DISPLAY "<option value='ALL'>Toate</option>"
    END-IF.
    MOVE W-FILTER-CAT TO W-OPT-CURRENT.
    PERFORM DISPLAY-CAT-OPTIONS.
    DISPLAY "</select>".
    DISPLAY "Sort: <select name='sort'>".
    IF W-SORT-BY(1:4) = "DATE"
        DISPLAY "<option value='ID'>ID</option>"
                "<option value='DATE' selected>Data</option>"
    ELSE
        DISPLAY "<option value='ID' selected>ID</option>"
                "<option value='DATE'>Data</option>"
    END-IF.
    DISPLAY "</select>".
    DISPLAY "De la: <input type='date' name='from' value='"
            FUNCTION TRIM(W-FROM-DATE) "'>".
    DISPLAY "Pana la: <input type='date' name='to' value='"
            FUNCTION TRIM(W-TO-DATE) "'>".
    MOVE W-SEARCH-Q TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "Cauta: <input type='text' name='q' maxlength='30' "
            "placeholder='descriere...' value='"
            FUNCTION TRIM(W-ESC-OUT) "'>".
    DISPLAY "<button type='submit' class='btn'>Aplica</button>".
    DISPLAY "<button type='submit' class='btn' name='export' "
            "value='csv'>Export CSV</button>".
    DISPLAY "</form></div>".

DISPLAY-CAT-OPTIONS.
    PERFORM VARYING CAT-IDX FROM 1 BY 1 UNTIL CAT-IDX > 5
        IF CAT-NAME(CAT-IDX) = W-OPT-CURRENT
            DISPLAY "<option value='"
                    FUNCTION TRIM(CAT-NAME(CAT-IDX)) "' selected>"
                    FUNCTION TRIM(CAT-NAME(CAT-IDX)) "</option>"
        ELSE
            DISPLAY "<option value='"
                    FUNCTION TRIM(CAT-NAME(CAT-IDX)) "'>"
                    FUNCTION TRIM(CAT-NAME(CAT-IDX)) "</option>"
        END-IF
    END-PERFORM.

DISPLAY-ADD-FORM.
    IF W-EDIT-MODE = "Y"
        PERFORM DISPLAY-EDIT-FORM
        EXIT PARAGRAPH
    END-IF.
    DISPLAY "<div class='card'><h2>Adauga tranzactie</h2>"
            "<form method='POST'>"
            "<input type='hidden' name='csrf_token' value='"
            FUNCTION TRIM(W-CSRF-TOKEN) "'>"
            "<input type='hidden' name='cmd' value='add'>"
            "Data: <input type='date' name='date' value='"
            W-TODAY-STR "' required> "
            "Cat: <select name='cat'>".
    MOVE SPACES TO W-OPT-CURRENT.
    PERFORM DISPLAY-CAT-OPTIONS.
    DISPLAY "</select> "
            "Desc: <input type='text' name='desc' required "
            "maxlength='30'> "
            "Suma: <input type='number' name='amount' "
            "step='0.01' required min='-9999999.99' "
            "max='9999999.99'> "
            "<button type='submit' class='btn'>Salveaza</button>"
            "</form></div>".

DISPLAY-EDIT-FORM.
    MOVE W-EDIT-DESC TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<div class='card'><h2>Editeaza tranzactia #"
            W-EDIT-ID "</h2>"
            "<form method='POST'>"
            "<input type='hidden' name='csrf_token' value='"
            FUNCTION TRIM(W-CSRF-TOKEN) "'>"
            "<input type='hidden' name='cmd' value='update'>"
            "<input type='hidden' name='id' value='" W-EDIT-ID "'>"
            "Data: <input type='date' name='date' value='"
            W-EDIT-DATE "' required> "
            "Cat: <select name='cat'>".
    MOVE W-EDIT-CAT TO W-OPT-CURRENT.
    PERFORM DISPLAY-CAT-OPTIONS.
    DISPLAY "</select> "
            "Desc: <input type='text' name='desc' required "
            "maxlength='30' value='" FUNCTION TRIM(W-ESC-OUT) "'> "
            "Suma: <input type='number' name='amount' "
            "step='0.01' required min='-9999999.99' "
            "max='9999999.99' value='"
            FUNCTION TRIM(W-EDIT-AMT-STR) "'> "
            "<button type='submit' class='btn'>Actualizeaza</button> "
            "<a href='?' class='btn' style='background:#64748b;"
            "text-decoration:none'>Anuleaza</a>"
            "</form></div>".

INITIALIZE-SUMMARY.
    MOVE "Venituri"  TO CAT-NAME(1).
    MOVE "Locuinta"  TO CAT-NAME(2).
    MOVE "Mancare"   TO CAT-NAME(3).
    MOVE "Hobby"     TO CAT-NAME(4).
    MOVE "Utilitati" TO CAT-NAME(5).
    MOVE 0 TO CAT-TOTAL(1) CAT-TOTAL(2) CAT-TOTAL(3)
              CAT-TOTAL(4) CAT-TOTAL(5).

DISPLAY-TABLE.
    DISPLAY "<div class='card' style='padding:0;'><table><thead><tr>"
            "<th>ID</th><th>Data</th><th>Cat</th><th>Desc</th>"
            "<th style='text-align:right'>Suma</th><th></th>"
            "</tr></thead><tbody>".
    IF W-SORT-BY(1:4) = "DATE"
        MOVE LOW-VALUES TO TRANS-DATE
        START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-DATE
            INVALID KEY MOVE "Y" TO W-EOF
        END-START
    ELSE
        MOVE 0 TO TRANS-ID
        START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-ID
            INVALID KEY MOVE "Y" TO W-EOF
        END-START
    END-IF.
    COMPUTE W-PAGE-START = (W-PAGE - 1) * W-PAGE-SIZE + 1.
    COMPUTE W-PAGE-END = W-PAGE * W-PAGE-SIZE.
    PERFORM UNTIL W-EOF = "Y"
        READ TRANSACTIONS-FILE NEXT
            AT END MOVE "Y" TO W-EOF
            NOT AT END
                PERFORM CHECK-ROW-MATCH
                IF W-ROW-MATCH = "Y"
                    ADD 1 TO W-ROW-COUNT
                    IF W-ROW-COUNT >= W-PAGE-START
                       AND W-ROW-COUNT <= W-PAGE-END
                        PERFORM RENDER-ROW
                    END-IF
                    ADD TRANS-AMOUNT TO W-TOTAL-BALANCE
                    PERFORM UPDATE-CAT-TOTAL
                END-IF
        END-READ
    END-PERFORM.
    MOVE W-TOTAL-BALANCE TO W-DISPLAY-TOTAL.
    MOVE W-ROW-COUNT TO W-DISPLAY-COUNT.
    DISPLAY "</tbody><tfoot><tr>"
            "<td colspan='4'><b>Total ("
            FUNCTION TRIM(W-DISPLAY-COUNT) " tranzactii)</b></td>"
            "<td style='text-align:right'><b>"
            W-DISPLAY-TOTAL "</b></td><td></td></tr></tfoot>"
            "</table></div>".
    PERFORM DISPLAY-PAGINATION.

DISPLAY-PAGINATION.
    COMPUTE W-TOTAL-PAGES =
        (W-ROW-COUNT + W-PAGE-SIZE - 1) / W-PAGE-SIZE.
    IF W-TOTAL-PAGES < 2
        EXIT PARAGRAPH
    END-IF.
    PERFORM BUILD-NAV-QS.
    MOVE W-PAGE TO W-PAGE-D.
    MOVE W-TOTAL-PAGES TO W-PAGES-D.
    DISPLAY "<div class='card' style='display:flex;gap:14px;"
            "align-items:center;justify-content:center;'>".
    IF W-PAGE > 1
        COMPUTE W-PGLNK-D = W-PAGE - 1
        DISPLAY "<a class='btn' style='text-decoration:none' href='?"
                FUNCTION TRIM(W-QS) "&page="
                FUNCTION TRIM(W-PGLNK-D) "'>&laquo; Inapoi</a>"
    END-IF.
    DISPLAY "<span>Pagina " FUNCTION TRIM(W-PAGE-D)
            " din " FUNCTION TRIM(W-PAGES-D) "</span>".
    IF W-PAGE < W-TOTAL-PAGES
        COMPUTE W-PGLNK-D = W-PAGE + 1
        DISPLAY "<a class='btn' style='text-decoration:none' href='?"
                FUNCTION TRIM(W-QS) "&page="
                FUNCTION TRIM(W-PGLNK-D) "'>Inainte &raquo;</a>"
    END-IF.
    DISPLAY "</div>".

BUILD-NAV-QS.
*>  Query string cu filtrele curente pentru linkurile de paginare.
*>  Valorile libere (filter, sort, q) sunt percent-encodate.
    MOVE SPACES TO W-QS.
    MOVE W-FILTER-CAT TO W-ENC-IN.
    PERFORM URL-ENCODE.
    STRING "filter=" FUNCTION TRIM(W-ENC-OUT)
        DELIMITED BY SIZE INTO W-QS.
    MOVE W-SORT-BY TO W-ENC-IN.
    PERFORM URL-ENCODE.
    STRING FUNCTION TRIM(W-QS)
           "&sort=" FUNCTION TRIM(W-ENC-OUT)
           "&from=" FUNCTION TRIM(W-FROM-DATE)
           "&to=" FUNCTION TRIM(W-TO-DATE)
        DELIMITED BY SIZE INTO W-QS.
    IF W-Q-LEN > 0
        MOVE W-SEARCH-Q TO W-ENC-IN
        PERFORM URL-ENCODE
        STRING FUNCTION TRIM(W-QS)
               "&q=" FUNCTION TRIM(W-ENC-OUT)
            DELIMITED BY SIZE INTO W-QS
    END-IF.

URL-ENCODE.
*>  Percent-encoding RFC 3986: pastreaza doar caracterele nerezervate.
    MOVE SPACES TO W-ENC-OUT.
    MOVE 0 TO W-ENC-OUT-LEN.
    MOVE 0 TO W-ENC-IN-LEN.
    PERFORM VARYING W-ENC-I FROM 60 BY -1
            UNTIL W-ENC-I = 0 OR W-ENC-IN(W-ENC-I:1) NOT = SPACE
        CONTINUE
    END-PERFORM.
    MOVE W-ENC-I TO W-ENC-IN-LEN.
    PERFORM VARYING W-ENC-I FROM 1 BY 1
            UNTIL W-ENC-I > W-ENC-IN-LEN
        EVALUATE W-ENC-IN(W-ENC-I:1)
            WHEN "a" THRU "z"
            WHEN "A" THRU "Z"
            WHEN "0" THRU "9"
            WHEN "." WHEN "-" WHEN "_" WHEN "~"
                ADD 1 TO W-ENC-OUT-LEN
                MOVE W-ENC-IN(W-ENC-I:1)
                    TO W-ENC-OUT(W-ENC-OUT-LEN:1)
            WHEN OTHER
                COMPUTE W-ENC-BYTE =
                    FUNCTION ORD(W-ENC-IN(W-ENC-I:1)) - 1
                COMPUTE W-ENC-HI = W-ENC-BYTE / 16
                COMPUTE W-ENC-LO = FUNCTION MOD(W-ENC-BYTE, 16)
                ADD 1 TO W-ENC-OUT-LEN
                MOVE "%" TO W-ENC-OUT(W-ENC-OUT-LEN:1)
                ADD 1 TO W-ENC-OUT-LEN
                MOVE HEX-DIGITS(W-ENC-HI + 1:1)
                    TO W-ENC-OUT(W-ENC-OUT-LEN:1)
                ADD 1 TO W-ENC-OUT-LEN
                MOVE HEX-DIGITS(W-ENC-LO + 1:1)
                    TO W-ENC-OUT(W-ENC-OUT-LEN:1)
        END-EVALUATE
    END-PERFORM.

CHECK-ROW-MATCH.
    MOVE "Y" TO W-ROW-MATCH.
    IF W-FILTER-CAT NOT = "ALL" AND W-FILTER-CAT NOT = TRANS-CAT
        MOVE "N" TO W-ROW-MATCH
    END-IF.
    IF W-FROM-DATE NOT = SPACES AND TRANS-DATE < W-FROM-DATE
        MOVE "N" TO W-ROW-MATCH
    END-IF.
    IF W-TO-DATE NOT = SPACES AND TRANS-DATE > W-TO-DATE
        MOVE "N" TO W-ROW-MATCH
    END-IF.
    IF W-Q-LEN > 0 AND W-ROW-MATCH = "Y"
        MOVE FUNCTION LOWER-CASE(TRANS-DESC) TO W-DESC-LC
        MOVE 0 TO W-Q-CNT
        INSPECT W-DESC-LC TALLYING W-Q-CNT
            FOR ALL W-Q-LC(1:W-Q-LEN)
        IF W-Q-CNT = 0
            MOVE "N" TO W-ROW-MATCH
        END-IF
    END-IF.

RENDER-ROW.
    DISPLAY "<tr><td>#" TRANS-ID "</td>".
    MOVE TRANS-DATE TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<td>" FUNCTION TRIM(W-ESC-OUT) "</td>".
    MOVE TRANS-CAT TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<td>" FUNCTION TRIM(W-ESC-OUT) "</td>".
    MOVE TRANS-DESC TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<td>" FUNCTION TRIM(W-ESC-OUT) "</td>".
    MOVE TRANS-AMOUNT TO W-DISPLAY-AMOUNT.
    IF TRANS-AMOUNT < 0
        DISPLAY "<td class='neg' style='text-align:right'>"
                W-DISPLAY-AMOUNT "</td>"
    ELSE
        DISPLAY "<td class='pos' style='text-align:right'>"
                W-DISPLAY-AMOUNT "</td>"
    END-IF.
    DISPLAY "<td style='white-space:nowrap'>"
            "<a class='btn btn-edit' href='?edit=" TRANS-ID
            "'>Edit</a> "
            "<form method='POST' style='margin:0;display:inline'>"
            "<input type='hidden' name='csrf_token' value='"
            FUNCTION TRIM(W-CSRF-TOKEN) "'>"
            "<input type='hidden' name='cmd' value='del'>"
            "<input type='hidden' name='id' value='" TRANS-ID "'>"
            "<button type='submit' class='btn btn-del' "
            "onclick='return confirm(&quot;Sterg aceasta "
            "tranzactie?&quot;)'>X</button>"
            "</form></td></tr>".

UPDATE-CAT-TOTAL.
    SET CAT-IDX TO 1.
    SEARCH CAT-ENTRY
        WHEN CAT-NAME(CAT-IDX) = TRANS-CAT
            ADD TRANS-AMOUNT TO CAT-TOTAL(CAT-IDX)
    END-SEARCH.

DISPLAY-SUMMARY.
    DISPLAY "<div style='display:flex;gap:1rem;max-width:1000px;"
            "margin:1rem auto;'>".
    PERFORM VARYING CAT-IDX FROM 1 BY 1 UNTIL CAT-IDX > 5
        MOVE CAT-TOTAL(CAT-IDX) TO W-DISPLAY-TOTAL
        MOVE CAT-NAME(CAT-IDX) TO W-ESC-IN
        PERFORM HTML-ESCAPE
        DISPLAY "<div class='card' style='flex:1;text-align:center;"
                "margin:0;'><div>" FUNCTION TRIM(W-ESC-OUT) "</div>"
                "<strong>" FUNCTION TRIM(W-DISPLAY-TOTAL)
                "</strong></div>"
    END-PERFORM.
    DISPLAY "</div>".

EXPORT-CSV.
    DISPLAY "Content-Type: text/csv; charset=utf-8".
    DISPLAY "Content-Disposition: attachment; "
            "filename=ledger-export.csv".
    DISPLAY " ".
    DISPLAY "id,data,categorie,descriere,suma".
    PERFORM OPEN-LEDGER-FILE.
    IF FS-LEDGER = "00"
        MOVE "N" TO W-EOF
        MOVE 0 TO TRANS-ID
        START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-ID
            INVALID KEY MOVE "Y" TO W-EOF
        END-START
        PERFORM UNTIL W-EOF = "Y"
            READ TRANSACTIONS-FILE NEXT
                AT END MOVE "Y" TO W-EOF
                NOT AT END
                    PERFORM CHECK-ROW-MATCH
                    IF W-ROW-MATCH = "Y"
                        PERFORM RENDER-CSV-ROW
                    END-IF
            END-READ
        END-PERFORM
        PERFORM CLOSE-LEDGER-FILE
    END-IF.
    MOVE "EXPORT" TO W-AUDIT-ACTION.
    MOVE "export CSV" TO W-AUDIT-DETAIL.
    PERFORM WRITE-AUDIT.

RENDER-CSV-ROW.
    MOVE TRANS-DESC TO W-CSV-IN.
    PERFORM CSV-ESCAPE.
    MOVE TRANS-AMOUNT TO W-CSV-AMT.
    DISPLAY TRANS-ID "," TRANS-DATE ","
            FUNCTION TRIM(TRANS-CAT) ',"'
            FUNCTION TRIM(W-CSV-OUT) '",'
            FUNCTION TRIM(W-CSV-AMT).

CSV-ESCAPE.
    MOVE SPACES TO W-CSV-OUT.
    MOVE 0 TO W-CSV-OUT-LEN.
    IF W-CSV-IN(1:1) = "=" OR "+" OR "-" OR "@"
        MOVE "'" TO W-CSV-OUT(1:1)
        MOVE 1 TO W-CSV-OUT-LEN
    END-IF.
    MOVE 0 TO W-CSV-IN-LEN.
    PERFORM VARYING W-CSV-I FROM 60 BY -1
            UNTIL W-CSV-I = 0 OR W-CSV-IN(W-CSV-I:1) NOT = SPACE
        CONTINUE
    END-PERFORM.
    MOVE W-CSV-I TO W-CSV-IN-LEN.
    PERFORM VARYING W-CSV-I FROM 1 BY 1
            UNTIL W-CSV-I > W-CSV-IN-LEN
        IF W-CSV-IN(W-CSV-I:1) = '"'
            ADD 1 TO W-CSV-OUT-LEN
            MOVE '"' TO W-CSV-OUT(W-CSV-OUT-LEN:1)
        END-IF
        ADD 1 TO W-CSV-OUT-LEN
        MOVE W-CSV-IN(W-CSV-I:1) TO W-CSV-OUT(W-CSV-OUT-LEN:1)
    END-PERFORM.

DISPLAY-REPORT-VIEW.
    MOVE 0 TO MONTH-COUNT.
    MOVE 0 TO W-MAX-FLOW.
    PERFORM OPEN-LEDGER-FILE.
    IF FS-LEDGER = "00"
        PERFORM BUILD-REPORT
        PERFORM CLOSE-LEDGER-FILE
    END-IF.
    DISPLAY "<div class='card'><h2>Raport lunar</h2>".
    IF MONTH-COUNT = 0
        DISPLAY "<p>Nu exista tranzactii.</p>"
    ELSE
        DISPLAY "<table><thead><tr><th>Luna</th>"
                "<th style='text-align:right'>Venituri</th>"
                "<th style='text-align:right'>Cheltuieli</th>"
                "<th style='text-align:right'>Net</th>"
                "<th style='width:35%'>Grafic</th>"
                "</tr></thead><tbody>"
        PERFORM VARYING W-M-IDX FROM 1 BY 1
                UNTIL W-M-IDX > MONTH-COUNT
            PERFORM RENDER-REPORT-ROW
        END-PERFORM
        DISPLAY "</tbody></table>"
    END-IF.
    DISPLAY "</div>".

BUILD-REPORT.
    MOVE "N" TO W-EOF.
    MOVE LOW-VALUES TO TRANS-DATE.
    START TRANSACTIONS-FILE KEY IS GREATER THAN TRANS-DATE
        INVALID KEY MOVE "Y" TO W-EOF
    END-START.
    PERFORM UNTIL W-EOF = "Y"
        READ TRANSACTIONS-FILE NEXT
            AT END MOVE "Y" TO W-EOF
            NOT AT END PERFORM ACCUMULATE-MONTH
        END-READ
    END-PERFORM.
    PERFORM VARYING W-M-IDX FROM 1 BY 1 UNTIL W-M-IDX > MONTH-COUNT
        IF MONTH-INCOME(W-M-IDX) > W-MAX-FLOW
            MOVE MONTH-INCOME(W-M-IDX) TO W-MAX-FLOW
        END-IF
        COMPUTE W-ABS-EXP = MONTH-EXPENSE(W-M-IDX) * -1
        IF W-ABS-EXP > W-MAX-FLOW
            MOVE W-ABS-EXP TO W-MAX-FLOW
        END-IF
    END-PERFORM.

ACCUMULATE-MONTH.
    IF MONTH-COUNT = 0
        PERFORM START-NEW-MONTH
    ELSE
        IF TRANS-DATE(1:7) NOT = MONTH-KEY(MONTH-COUNT)
            PERFORM START-NEW-MONTH
        END-IF
    END-IF.
    IF MONTH-COUNT = 0
        EXIT PARAGRAPH
    END-IF.
    IF TRANS-AMOUNT >= 0
        ADD TRANS-AMOUNT TO MONTH-INCOME(MONTH-COUNT)
    ELSE
        ADD TRANS-AMOUNT TO MONTH-EXPENSE(MONTH-COUNT)
    END-IF.

START-NEW-MONTH.
    IF MONTH-COUNT < 120
        ADD 1 TO MONTH-COUNT
        MOVE TRANS-DATE(1:7) TO MONTH-KEY(MONTH-COUNT)
        MOVE 0 TO MONTH-INCOME(MONTH-COUNT)
        MOVE 0 TO MONTH-EXPENSE(MONTH-COUNT)
    END-IF.

RENDER-REPORT-ROW.
    MOVE MONTH-KEY(W-M-IDX) TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<tr><td><b>" FUNCTION TRIM(W-ESC-OUT) "</b></td>".
    MOVE MONTH-INCOME(W-M-IDX) TO W-DISPLAY-TOTAL.
    DISPLAY "<td class='pos' style='text-align:right'>"
            W-DISPLAY-TOTAL "</td>".
    MOVE MONTH-EXPENSE(W-M-IDX) TO W-DISPLAY-TOTAL.
    DISPLAY "<td class='neg' style='text-align:right'>"
            W-DISPLAY-TOTAL "</td>".
    COMPUTE W-NET-AMT = MONTH-INCOME(W-M-IDX)
                      + MONTH-EXPENSE(W-M-IDX).
    MOVE W-NET-AMT TO W-DISPLAY-TOTAL.
    IF W-NET-AMT < 0
        DISPLAY "<td class='neg' style='text-align:right'><b>"
                W-DISPLAY-TOTAL "</b></td>"
    ELSE
        DISPLAY "<td class='pos' style='text-align:right'><b>"
                W-DISPLAY-TOTAL "</b></td>"
    END-IF.
    DISPLAY "<td>".
    IF W-MAX-FLOW > 0
        COMPUTE W-BAR-PCT ROUNDED =
            MONTH-INCOME(W-M-IDX) * 100 / W-MAX-FLOW
        MOVE W-BAR-PCT TO W-BAR-PCT-D
        DISPLAY "<div class='barwrap'><div class='bar-in' "
                "style='width:" FUNCTION TRIM(W-BAR-PCT-D)
                "%'></div></div>"
        COMPUTE W-ABS-EXP = MONTH-EXPENSE(W-M-IDX) * -1
        COMPUTE W-BAR-PCT ROUNDED = W-ABS-EXP * 100 / W-MAX-FLOW
        MOVE W-BAR-PCT TO W-BAR-PCT-D
        DISPLAY "<div class='barwrap'><div class='bar-ex' "
                "style='width:" FUNCTION TRIM(W-BAR-PCT-D)
                "%'></div></div>"
    END-IF.
    DISPLAY "</td></tr>".

DISPLAY-AUDIT-VIEW.
    MOVE 0 TO W-AR-TOTAL.
    OPEN INPUT AUDIT-FILE.
    IF FS-AUDIT = "00"
        MOVE "N" TO W-EOF
        PERFORM UNTIL W-EOF = "Y"
            READ AUDIT-FILE
                AT END MOVE "Y" TO W-EOF
                NOT AT END
                    ADD 1 TO W-AR-TOTAL
                    COMPUTE W-AR-IDX =
                        FUNCTION MOD(W-AR-TOTAL - 1, 30) + 1
                    MOVE AUDIT-REC TO AR-LINE(W-AR-IDX)
            END-READ
        END-PERFORM
        CLOSE AUDIT-FILE
    END-IF.
    DISPLAY "<div class='card'><h2>Jurnal de audit</h2>"
            "<p>Ultimele 30 de actiuni, cele mai recente primele."
            "</p>".
    IF W-AR-TOTAL = 0
        DISPLAY "<p>Nicio intrare inca.</p>"
    ELSE
        DISPLAY "<table><thead><tr><th>Timp</th><th>IP</th>"
                "<th>Actiune</th><th>Detalii</th>"
                "</tr></thead><tbody>"
        IF W-AR-TOTAL > 30
            COMPUTE W-AR-FROM = W-AR-TOTAL - 29
        ELSE
            MOVE 1 TO W-AR-FROM
        END-IF
        PERFORM VARYING W-AR-K FROM W-AR-TOTAL BY -1
                UNTIL W-AR-K < W-AR-FROM
            COMPUTE W-AR-IDX = FUNCTION MOD(W-AR-K - 1, 30) + 1
            PERFORM RENDER-AUDIT-ROW
        END-PERFORM
        DISPLAY "</tbody></table>"
    END-IF.
    DISPLAY "</div>".

RENDER-AUDIT-ROW.
    MOVE SPACES TO W-AUD-TS W-AUD-IP W-AUD-ACT W-AUD-DET.
    UNSTRING AR-LINE(W-AR-IDX) DELIMITED BY " | "
        INTO W-AUD-TS, W-AUD-IP, W-AUD-ACT, W-AUD-DET
    END-UNSTRING.
    DISPLAY "<tr>".
    MOVE W-AUD-TS TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<td style='white-space:nowrap'>"
            FUNCTION TRIM(W-ESC-OUT) "</td>".
    MOVE W-AUD-IP TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<td>" FUNCTION TRIM(W-ESC-OUT) "</td>".
    MOVE W-AUD-ACT TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<td><b>" FUNCTION TRIM(W-ESC-OUT) "</b></td>".
    MOVE W-AUD-DET TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<td>" FUNCTION TRIM(W-ESC-OUT) "</td>".
    DISPLAY "</tr>".

OPEN-LEDGER-FILE.
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "35"
        OPEN OUTPUT TRANSACTIONS-FILE
        CLOSE TRANSACTIONS-FILE
        OPEN I-O TRANSACTIONS-FILE
    END-IF.

CLOSE-LEDGER-FILE.
    CLOSE TRANSACTIONS-FILE.
