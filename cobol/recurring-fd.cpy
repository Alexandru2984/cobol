FD RULES-FILE.
01 RULE-RECORD.
    05 RULE-ID            PIC 9(6).
    05 RULE-DATE          PIC X(10).
    05 RULE-CAT           PIC X(15).
    05 RULE-DESC          PIC X(30).
    05 RULE-AMOUNT        PIC S9(7)V99.
    05 RULE-CYCLE         PIC X(7).
    05 RULE-ANCHOR        PIC 99.
    05 RULE-ACTIVE        PIC X.
    05 RULE-ARCHIVED      PIC X.
    05 RULE-CREATE-KEY    PIC X(32).
FD OCCURRENCES-FILE.
01 OCC-RECORD.
    05 OCC-KEY.
        10 OCC-RULE       PIC 9(6).
        10 OCC-DATE       PIC X(10).
    05 OCC-STATE          PIC X.
    05 OCC-TRANSACTION.
        10 OCC-TX-ID      PIC 9(6).
        10 OCC-TX-DATE    PIC X(10).
        10 OCC-TX-CAT     PIC X(15).
        10 OCC-TX-DESC    PIC X(30).
        10 OCC-TX-AMOUNT  PIC S9(7)V99.
