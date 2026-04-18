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

    SELECT SESSION-FILE ASSIGN TO "data/session.dat"
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS FS-SESSION.

DATA DIVISION.
FILE SECTION.
FD  TRANSACTIONS-FILE.
01  TRANS-RECORD.
    05  TRANS-ID            PIC 9(6).
    05  TRANS-DATE          PIC X(10).
    05  TRANS-CAT           PIC X(15).
    05  TRANS-DESC          PIC X(30).
    05  TRANS-AMOUNT        PIC S9(7)V99.

FD  SESSION-FILE.
01  SESSION-REC             PIC X(32).

WORKING-STORAGE SECTION.
01  FS-LEDGER               PIC XX.
01  FS-SESSION              PIC XX.
01  W-EOF                   PIC X VALUE "N".
01  W-DISPLAY-AMOUNT        PIC -ZZZ,ZZ9.99.
01  W-TOTAL-BALANCE         PIC S9(9)V99 VALUE 0.
01  W-DISPLAY-TOTAL         PIC -ZZZ,ZZZ,ZZ9.99.
01  W-LAST-ID               PIC 9(6) VALUE 0.

*> CGI environment
01  W-METHOD                PIC X(10).
01  W-CONTENT-LEN-STR       PIC X(10).
01  W-CONTENT-LEN           PIC 9(10).
01  W-POST-DATA             PIC X(4096).
01  W-QUERY-STRING          PIC X(1024).
01  W-COOKIE-ENV            PIC X(1024).

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
01  W-STORED-TOKEN          PIC X(32) VALUE SPACES.
01  W-TOKEN-IDX             PIC 9(4).

01  W-SEED                  PIC 9(9).
01  W-RAND-VAL              PIC 9(3).
01  HEX-DIGITS              PIC X(16) VALUE "0123456789abcdef".

*> Credentials (configurable via env vars)
01  W-CFG-USER              PIC X(40).
01  W-CFG-PASS              PIC X(40).
01  W-LOGIN-USER            PIC X(40).
01  W-LOGIN-PASS            PIC X(40).

*> Query filters
01  W-FILTER-CAT            PIC X(15) VALUE "ALL".
01  W-SORT-BY               PIC X(10) VALUE "ID".

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
    PERFORM DISPLAY-PAGE.
    STOP RUN.

LOAD-CONFIG.
    DISPLAY "LEDGER_USER" UPON ENVIRONMENT-NAME.
    ACCEPT W-CFG-USER FROM ENVIRONMENT-VALUE.
    IF W-CFG-USER = SPACES OR LOW-VALUES
        MOVE "micu" TO W-CFG-USER
    END-IF.
    DISPLAY "LEDGER_PASS" UPON ENVIRONMENT-NAME.
    ACCEPT W-CFG-PASS FROM ENVIRONMENT-VALUE.
    IF W-CFG-PASS = SPACES OR LOW-VALUES
        MOVE "cobol2026" TO W-CFG-PASS
    END-IF.
    MOVE FUNCTION CURRENT-DATE TO W-CURRENT-DATE-STR.
    STRING W-CURRENT-DATE-STR(1:4) "-"
           W-CURRENT-DATE-STR(5:2) "-"
           W-CURRENT-DATE-STR(7:2)
           DELIMITED BY SIZE INTO W-TODAY-STR.

READ-CGI-ENV.
    DISPLAY "HTTP_COOKIE" UPON ENVIRONMENT-NAME.
    ACCEPT W-COOKIE-ENV FROM ENVIRONMENT-VALUE.
    DISPLAY "QUERY_STRING" UPON ENVIRONMENT-NAME.
    ACCEPT W-QUERY-STRING FROM ENVIRONMENT-VALUE.
    DISPLAY "REQUEST_METHOD" UPON ENVIRONMENT-NAME.
    ACCEPT W-METHOD FROM ENVIRONMENT-VALUE.

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
    OPEN INPUT SESSION-FILE.
    IF FS-SESSION = "00"
        READ SESSION-FILE
            AT END CONTINUE
            NOT AT END MOVE SESSION-REC TO W-STORED-TOKEN
        END-READ
        CLOSE SESSION-FILE
    END-IF.
    IF W-COOKIE-TOKEN NOT = SPACES
       AND W-STORED-TOKEN NOT = SPACES
       AND W-COOKIE-TOKEN = W-STORED-TOKEN
        MOVE "Y" TO W-LOGGED-IN
    END-IF.

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
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 20
        IF W-PAIR(W-I) NOT = SPACES
            MOVE SPACES TO W-PAIR-KEY
            MOVE SPACES TO W-PAIR-VAL
            UNSTRING W-PAIR(W-I) DELIMITED BY "="
                INTO W-PAIR-KEY, W-PAIR-VAL
            END-UNSTRING
            MOVE W-PAIR-VAL TO W-URL-IN
            PERFORM URL-DECODE
            EVALUATE W-PAIR-KEY
                WHEN "filter"
                    MOVE W-URL-OUT TO W-FILTER-CAT
                WHEN "sort"
                    MOVE W-URL-OUT TO W-SORT-BY
            END-EVALUATE
        END-IF
    END-PERFORM.

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
    IF W-HEX-NUM < 32 AND W-HEX-NUM NOT = 0
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
    COMPUTE W-SEED = FUNCTION SECONDS-PAST-MIDNIGHT * 1000
                   + FUNCTION RANDOM(1) * 1000000.
    COMPUTE W-RAND-VAL = FUNCTION INTEGER(FUNCTION RANDOM(W-SEED) * 16).
    IF W-RAND-VAL > 15
        MOVE 15 TO W-RAND-VAL
    END-IF.
    COMPUTE W-J = W-RAND-VAL + 1.
    MOVE HEX-DIGITS(W-J:1) TO W-NEW-TOKEN(1:1).
    PERFORM VARYING W-I FROM 2 BY 1 UNTIL W-I > 32
        COMPUTE W-RAND-VAL = FUNCTION INTEGER(FUNCTION RANDOM * 16)
        IF W-RAND-VAL > 15
            MOVE 15 TO W-RAND-VAL
        END-IF
        COMPUTE W-J = W-RAND-VAL + 1
        MOVE HEX-DIGITS(W-J:1) TO W-NEW-TOKEN(W-I:1)
    END-PERFORM.

HANDLE-ACTION.
    MOVE "cmd" TO W-KEY-LOOKUP.
    PERFORM GET-FORM-VALUE.
    MOVE W-VALUE-OUT TO W-CMD.
    EVALUATE TRUE
        WHEN W-CMD(1:5) = "login"
            PERFORM DO-LOGIN
        WHEN W-CMD(1:6) = "logout"
            IF W-LOGGED-IN = "Y"
                PERFORM DO-LOGOUT
            END-IF
        WHEN W-CMD(1:3) = "add" AND W-LOGGED-IN = "Y"
            PERFORM DO-ADD
        WHEN W-CMD(1:3) = "del" AND W-LOGGED-IN = "Y"
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
    IF FUNCTION TRIM(W-LOGIN-USER) = FUNCTION TRIM(W-CFG-USER)
       AND FUNCTION TRIM(W-LOGIN-PASS) = FUNCTION TRIM(W-CFG-PASS)
        PERFORM GENERATE-TOKEN
        MOVE W-NEW-TOKEN TO W-STORED-TOKEN
        MOVE W-NEW-TOKEN TO W-COOKIE-TOKEN
        OPEN OUTPUT SESSION-FILE
        MOVE W-NEW-TOKEN TO SESSION-REC
        WRITE SESSION-REC
        CLOSE SESSION-FILE
        MOVE "Y" TO W-LOGGED-IN
        MOVE "Y" TO W-SET-COOKIE
    ELSE
        MOVE "User sau parola incorecte." TO W-ERROR-MSG
        MOVE "Y" TO W-HAS-ERROR
    END-IF.

DO-LOGOUT.
    OPEN OUTPUT SESSION-FILE.
    MOVE SPACES TO SESSION-REC.
    WRITE SESSION-REC.
    CLOSE SESSION-FILE.
    MOVE "N" TO W-LOGGED-IN.
    MOVE SPACES TO W-COOKIE-TOKEN.
    MOVE SPACES TO W-STORED-TOKEN.
    MOVE "L" TO W-SET-COOKIE.

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
    COMPUTE TRANS-ID = W-LAST-ID + 1.
    MOVE W-DATE-RAW TO TRANS-DATE.
    MOVE W-CAT-RAW TO TRANS-CAT.
    MOVE W-DESC-RAW TO TRANS-DESC.
    MOVE W-AMOUNT-NUM TO TRANS-AMOUNT.
    WRITE TRANS-RECORD
        INVALID KEY
            MOVE "Eroare la scriere (ID duplicat)." TO W-ERROR-MSG
            MOVE "Y" TO W-HAS-ERROR
    END-WRITE.
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
                DELETE TRANSACTIONS-FILE RECORD
        END-READ
        CLOSE TRANSACTIONS-FILE
    END-IF.

VALIDATE-AMOUNT.
    MOVE "Y" TO W-VALID.
    IF FUNCTION TRIM(W-AMOUNT-RAW) = SPACES
        MOVE "N" TO W-VALID
        EXIT PARAGRAPH
    END-IF.
    PERFORM VARYING W-I FROM 1 BY 1 UNTIL W-I > 20
        IF W-AMOUNT-RAW(W-I:1) NOT = SPACE
            EVALUATE W-AMOUNT-RAW(W-I:1)
                WHEN "0" THRU "9" CONTINUE
                WHEN "." CONTINUE
                WHEN "-"
                    IF W-I > 1 MOVE "N" TO W-VALID END-IF
                WHEN "+"
                    IF W-I > 1 MOVE "N" TO W-VALID END-IF
                WHEN OTHER MOVE "N" TO W-VALID
            END-EVALUATE
        END-IF
    END-PERFORM.
    IF W-VALID = "Y"
        COMPUTE W-AMOUNT-NUM = FUNCTION NUMVAL(W-AMOUNT-RAW)
        IF W-AMOUNT-NUM > 9999999.99 OR W-AMOUNT-NUM < -9999999.99
            MOVE "N" TO W-VALID
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
    END-IF.
    IF W-SET-COOKIE = "L"
        DISPLAY "Set-Cookie: session=; Path=/; HttpOnly; Secure; "
                "SameSite=Strict; Max-Age=0"
    END-IF.
    DISPLAY " ".
    DISPLAY "<!DOCTYPE html><html><head><meta charset='utf-8'>".
    DISPLAY "<title>Ledger Pro v4.0</title>".
    DISPLAY "<style>body{font-family:sans-serif;"
            "background:#f8fafc;padding:2rem;}".
    DISPLAY ".card{background:white;border-radius:12px;padding:1.5rem;"
            "margin:1rem auto;max-width:1000px;"
            "box-shadow:0 2px 4px rgba(0,0,0,0.1);}".
    DISPLAY "table{width:100%;border-collapse:collapse;}".
    DISPLAY "th{text-align:left;background:#f1f5f9;padding:8px;}".
    DISPLAY "td{padding:8px;border-bottom:1px solid #eee;}".
    DISPLAY ".btn{background:#1e293b;color:white;border:none;"
            "padding:8px 16px;border-radius:6px;cursor:pointer;}".
    DISPLAY ".btn-del{background:#ef4444;}".
    DISPLAY ".err{background:#fee2e2;color:#991b1b;padding:12px;"
            "border-radius:8px;margin:1rem auto;max-width:1000px;}".
    DISPLAY "input,select{padding:6px;border:1px solid #cbd5e1;"
            "border-radius:4px;}".
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
        MOVE W-CFG-USER TO W-ESC-IN
        PERFORM HTML-ESCAPE
        DISPLAY "<div class='card'><h1>Ledger of Ages</h1>"
                "<p>Logat ca: <b>" FUNCTION TRIM(W-ESC-OUT) "</b> "
                "<form method='POST' style='display:inline'>"
                "<input type='hidden' name='cmd' value='logout'>"
                "<button type='submit' class='btn'>Logout</button>"
                "</form></p></div>"
        PERFORM DISPLAY-TOOLBAR
        MOVE 0 TO W-TOTAL-BALANCE
        MOVE "N" TO W-EOF
        PERFORM INITIALIZE-SUMMARY
        PERFORM OPEN-LEDGER-FILE
        IF FS-LEDGER = "00"
            PERFORM DISPLAY-TABLE
            PERFORM CLOSE-LEDGER-FILE
            PERFORM DISPLAY-SUMMARY
        END-IF
        PERFORM DISPLAY-ADD-FORM
    END-IF.
    DISPLAY "</body></html>".

DISPLAY-LOGIN.
    DISPLAY "<div class='card' style='max-width:400px;margin-top:80px;'>"
            "<h2>Login</h2>"
            "<form method='POST'>"
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
    DISPLAY "<div class='card'><form method='GET'>"
            "Filtru: <select name='filter'>"
            "<option value='ALL'>Toate</option>"
            "<option value='Venituri'>Venituri</option>"
            "<option value='Locuinta'>Locuinta</option>"
            "<option value='Mancare'>Mancare</option>"
            "<option value='Hobby'>Hobby</option>"
            "<option value='Utilitati'>Utilitati</option>"
            "</select> "
            "Sort: <select name='sort'>"
            "<option value='ID'>ID</option>"
            "<option value='DATE'>Data</option>"
            "</select> "
            "<button type='submit' class='btn'>Aplica</button>"
            "</form></div>".

DISPLAY-ADD-FORM.
    DISPLAY "<div class='card'><h2>Adauga tranzactie</h2>"
            "<form method='POST'>"
            "<input type='hidden' name='cmd' value='add'>"
            "Data: <input type='date' name='date' value='"
            W-TODAY-STR "' required> "
            "Cat: <select name='cat'>"
            "<option value='Venituri'>Venituri</option>"
            "<option value='Locuinta'>Locuinta</option>"
            "<option value='Mancare'>Mancare</option>"
            "<option value='Hobby'>Hobby</option>"
            "<option value='Utilitati'>Utilitati</option>"
            "</select> "
            "Desc: <input type='text' name='desc' required "
            "maxlength='30'> "
            "Suma: <input type='number' name='amount' "
            "step='0.01' required min='-9999999.99' "
            "max='9999999.99'> "
            "<button type='submit' class='btn'>Salveaza</button>"
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
    PERFORM UNTIL W-EOF = "Y"
        READ TRANSACTIONS-FILE NEXT
            AT END MOVE "Y" TO W-EOF
            NOT AT END
                IF (W-FILTER-CAT = "ALL")
                   OR (W-FILTER-CAT = TRANS-CAT)
                    PERFORM RENDER-ROW
                    ADD TRANS-AMOUNT TO W-TOTAL-BALANCE
                    PERFORM UPDATE-CAT-TOTAL
                END-IF
        END-READ
    END-PERFORM.
    MOVE W-TOTAL-BALANCE TO W-DISPLAY-TOTAL.
    DISPLAY "</tbody><tfoot><tr>"
            "<td colspan='4'><b>Total</b></td>"
            "<td style='text-align:right'><b>"
            W-DISPLAY-TOTAL "</b></td><td></td></tr></tfoot>"
            "</table></div>".

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
    DISPLAY "<td style='text-align:right'>"
            W-DISPLAY-AMOUNT "</td>".
    DISPLAY "<td><form method='POST' style='margin:0'>"
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
        MOVE CAT-TOTAL(CAT-IDX) TO W-DISPLAY-AMOUNT
        MOVE CAT-NAME(CAT-IDX) TO W-ESC-IN
        PERFORM HTML-ESCAPE
        DISPLAY "<div class='card' style='flex:1;text-align:center;"
                "margin:0;'><div>" FUNCTION TRIM(W-ESC-OUT) "</div>"
                "<strong>" W-DISPLAY-AMOUNT "</strong></div>"
    END-PERFORM.
    DISPLAY "</div>".

OPEN-LEDGER-FILE.
    OPEN I-O TRANSACTIONS-FILE.
    IF FS-LEDGER = "35"
        OPEN OUTPUT TRANSACTIONS-FILE
        CLOSE TRANSACTIONS-FILE
        OPEN I-O TRANSACTIONS-FILE
    END-IF.

CLOSE-LEDGER-FILE.
    CLOSE TRANSACTIONS-FILE.
