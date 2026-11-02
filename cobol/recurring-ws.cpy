01 FS-RULES               PIC XX.
01 FS-OCC                 PIC XX.
01 R-ID                   PIC 9(6).
01 R-EDIT                 PIC 9(6) VALUE 0.
01 R-LAST                 PIC 9(6).
01 R-CYCLE                PIC X(7).
01 R-DUE                  PIC X(10).
01 R-STATE                PIC X.
01 R-EOF                  PIC X.
01 R-COUNT                PIC 9(6) VALUE 0.
01 R-COUNT-D              PIC ZZZZZ9.
01 R-ACTIVE               PIC 9(6) VALUE 0.
01 R-DUE-COUNT            PIC 9(6) VALUE 0.
01 R-INCOME               PIC S9(15)V99 VALUE 0.
01 R-EXPENSE              PIC S9(15)V99 VALUE 0.
01 R-LOOPS                BINARY-LONG.
01 R-YEAR                 PIC 9(4).
01 R-MONTH                PIC 99.
01 R-DAY                  PIC 99.
01 R-INT-DATE             BINARY-LONG.
01 R-DATE-NUM             PIC 9(8).
01 R-NEXT                 PIC X(10).
01 R-FAULT                PIC X(20).
01 R-ADMIN                PIC X.
01 R-READY                PIC X VALUE "N".
01 R-SAVED-RULE            PIC X(113).
01 R-SAVED-INTENT.
    05 R-OCC-KEY.
        10 R-OCC-RULE      PIC 9(6).
        10 R-OCC-DATE      PIC X(10).
    05 R-OCC-STATE         PIC X.
    05 R-OCC-TX.
        10 R-OCC-ID        PIC 9(6).
        10 R-OCC-DATE-TX   PIC X(10).
        10 R-OCC-CAT       PIC X(15).
        10 R-OCC-DESC      PIC X(30).
        10 R-OCC-AMOUNT    PIC S9(7)V99.
01 R-EDIT-RECORD.
    05 RE-ID              PIC 9(6).
    05 RE-DATE            PIC X(10).
    05 RE-CAT             PIC X(15).
    05 RE-DESC            PIC X(30).
    05 RE-AMOUNT          PIC S9(7)V99.
    05 RE-CYCLE           PIC X(7).
    05 RE-ANCHOR          PIC 99.
    05 RE-ACTIVE          PIC X.
    05 RE-ARCHIVED        PIC X.
    05 RE-CREATE-KEY      PIC X(32).
01 R-ROWS.
    05 R-ROW OCCURS 1000 TIMES.
        10 R-ROW-RECORD     PIC X(113).
01 R-INDEX                 BINARY-LONG.

01 R-CREATE-KEY            PIC X(32).
