LOAD-RULES-VIEW.
    PERFORM INITIALIZE-SUMMARY.
    OPEN INPUT RULES-FILE.
    IF FS-RULES = "35"
        CALL STATIC "access" USING BY REFERENCE Z"data/recurring.dat"
            BY VALUE 0 RETURNING W-FILE-EXISTS END-CALL
        IF W-FILE-EXISTS = 0 PERFORM NATIVE-STORAGE-ERROR END-IF
        EXIT PARAGRAPH
    END-IF.
    IF FS-RULES NOT = "00" PERFORM NATIVE-STORAGE-ERROR EXIT PARAGRAPH END-IF.
    MOVE 0 TO RULE-ID.
    MOVE "N" TO R-EOF.
    START RULES-FILE KEY IS GREATER THAN RULE-ID
        INVALID KEY MOVE "Y" TO R-EOF
    END-START.
    PERFORM UNTIL R-EOF = "Y" OR W-STORAGE-ERROR = "Y"
        READ RULES-FILE NEXT
            AT END MOVE "Y" TO R-EOF
            NOT AT END
                PERFORM VALIDATE-STORED-RULE
                IF W-STORAGE-ERROR NOT = "Y" AND RULE-ARCHIVED NOT = "Y"
                    IF R-COUNT = 1000
                        PERFORM NATIVE-STORAGE-ERROR
                    ELSE
                        ADD 1 TO R-COUNT
                        MOVE RULE-RECORD TO R-ROW-RECORD(R-COUNT)
                        IF RULE-ID = R-EDIT MOVE RULE-RECORD TO R-EDIT-RECORD END-IF
                        IF RULE-ACTIVE = "Y"
                            ADD 1 TO R-ACTIVE
                            IF RULE-DATE <= W-TODAY-STR ADD 1 TO R-DUE-COUNT END-IF
                            IF RULE-AMOUNT > 0 ADD RULE-AMOUNT TO R-INCOME
                            ELSE ADD RULE-AMOUNT TO R-EXPENSE END-IF
                        END-IF
                    END-IF
                END-IF
        END-READ
    END-PERFORM.
    CLOSE RULES-FILE.

DISPLAY-RECURRING-VIEW.
    DISPLAY "<section class='metrics' aria-label='Rezumat recurente'>".
    MOVE R-ACTIVE TO R-COUNT-D.
    DISPLAY "<article class='metric metric-balance'><span class='metric-label'>Reguli active</span>"
            "<strong>" FUNCTION TRIM(R-COUNT-D) "</strong><small>Salariu, chirie sau abonamente</small></article>".
    MOVE R-DUE-COUNT TO R-COUNT-D.
    DISPLAY "<article class='metric'><span class='metric-label'>De inregistrat</span><strong>"
            FUNCTION TRIM(R-COUNT-D) "</strong><small>Reguli cu urmatoarea scadenta ajunsa</small></article>".
    MOVE R-INCOME TO W-DISPLAY-TOTAL.
    DISPLAY "<article class='metric'><span class='metric-label'>Venituri planificate</span>"
            "<strong class='pos'>" FUNCTION TRIM(W-DISPLAY-TOTAL)
            "</strong><small>Urmatoarea scadenta a fiecarei reguli active</small></article>".
    MOVE R-EXPENSE TO W-DISPLAY-TOTAL.
    DISPLAY "<article class='metric'><span class='metric-label'>Cheltuieli planificate</span>"
            "<strong>" FUNCTION TRIM(W-DISPLAY-TOTAL)
            "</strong><small>Urmatoarea scadenta a fiecarei reguli active</small></article></section>"
            "<p class='muted recurring-explainer'>Planurile sunt o previzualizare. "
            "Apasa Inregistreaza pentru a adauga o singura scadenta in registru. "
            "Cererea repetata nu dubleaza aceeasi scadenta.</p>".
    IF R-COUNT = 0
        DISPLAY "<div class='card empty-state'><h2>Mai putine lucruri de tinut minte.</h2>"
                "<p>Adauga primul venit sau prima cheltuiala recurenta.</p>"
                "<a class='btn secondary' href='#rule-form'>Creeaza o regula</a></div>"
    END-IF.
    DISPLAY "<section class='budget-grid recurring-grid' aria-label='Reguli recurente'>".
    PERFORM VARYING R-INDEX FROM 1 BY 1 UNTIL R-INDEX > R-COUNT
        MOVE R-ROW-RECORD(R-INDEX) TO RULE-RECORD
        PERFORM RENDER-RULE-CARD
    END-PERFORM.
    DISPLAY "</section>".
    PERFORM DISPLAY-RULE-FORM.

RENDER-RULE-CARD.
    DISPLAY "<article class='card rule-card' data-rule='" RULE-ID "'>"
            "<div class='section-heading'><span class='category'>"
            FUNCTION TRIM(RULE-CAT) "</span>".
    EVALUATE TRUE
        WHEN RULE-ACTIVE NOT = "Y" DISPLAY "<span class='budget-status unset'>In pauza</span>"
        WHEN RULE-DATE <= W-TODAY-STR DISPLAY "<span class='budget-status near'>De inregistrat</span>"
        WHEN OTHER DISPLAY "<span class='budget-status'>Planificata</span>"
    END-EVALUATE.
    MOVE RULE-DESC TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "</div><h2>" FUNCTION TRIM(W-ESC-OUT) "</h2>".
    MOVE RULE-AMOUNT TO W-DISPLAY-AMOUNT.
    DISPLAY "<p class='rule-amount'>" FUNCTION TRIM(W-DISPLAY-AMOUNT) "</p>"
            "<p class='muted'>Urmatoarea scadenta: <b>" RULE-DATE "</b> &middot; ".
    EVALUATE RULE-CYCLE
        WHEN "WEEKLY" DISPLAY "Saptamanal"
        WHEN "YEARLY" DISPLAY "Anual"
        WHEN OTHER DISPLAY "Lunar"
    END-EVALUATE.
    DISPLAY "</p><div class='rule-actions'>".
    IF RULE-ACTIVE = "Y" AND RULE-DATE <= W-TODAY-STR
        DISPLAY "<form method='POST' action='?view=RECURRING' data-book>"
                "<input type='hidden' name='cmd' value='rule-book'>"
                "<input type='hidden' name='due' value='" RULE-DATE "'>"
        PERFORM RULE-HIDDEN-FIELDS
        DISPLAY "<button class='btn' type='submit'>Inregistreaza scadenta</button></form>"
    END-IF.
    DISPLAY "<a class='btn secondary' href='?view=RECURRING&amp;rule=" RULE-ID
            "#rule-form'>Editeaza</a><form method='POST' action='?view=RECURRING'>"
            "<input type='hidden' name='cmd' value='rule-toggle'>".
    PERFORM RULE-HIDDEN-FIELDS.
    IF RULE-ACTIVE = "Y"
        DISPLAY "<button class='btn secondary' type='submit'>Pune in pauza</button>"
    ELSE
        DISPLAY "<button class='btn secondary' type='submit'>Reia regula</button>"
    END-IF.
    DISPLAY "</form><form method='POST' action='?view=RECURRING' data-delete='rule'>"
            "<input type='hidden' name='cmd' value='rule-archive'>".
    PERFORM RULE-HIDDEN-FIELDS.
    DISPLAY "<button class='budget-remove' type='submit'>Arhiveaza</button></form></div></article>".

RULE-HIDDEN-FIELDS.
    DISPLAY "<input type='hidden' name='csrf_token' value='"
            FUNCTION TRIM(W-CSRF-TOKEN) "'>"
            "<input type='hidden' name='id' value='" RULE-ID "'>".

DISPLAY-RULE-FORM.
    DISPLAY "<section class='card transaction-form' id='rule-form'>".
    IF RE-ID > 0
        DISPLAY "<h2>Editeaza regula #" RE-ID "</h2>"
        MOVE RE-DATE TO W-DATE-RAW
        MOVE RE-CAT TO W-OPT-CURRENT
        MOVE RE-DESC TO W-DESC-RAW
        MOVE RE-AMOUNT TO W-EDIT-AMT-STR
        MOVE RE-CYCLE TO R-CYCLE
    ELSE
        DISPLAY "<h2>Adauga o regula recurenta</h2>"
        IF W-HAS-ERROR NOT = "Y"
            MOVE W-TODAY-STR TO W-DATE-RAW
            MOVE SPACES TO W-DESC-RAW W-AMOUNT-RAW W-CAT-RAW
            MOVE "MONTHLY" TO R-CYCLE
        END-IF
        MOVE W-CAT-RAW TO W-OPT-CURRENT
    END-IF.
    DISPLAY "<p class='muted'>Pentru lunile scurte, ziua 29/30/31 devine ultima zi a lunii. "
            "Luna urmatoare revine la ziua initiala.</p>"
            "<form method='POST' action='?view=RECURRING' class='entry-grid'>"
            "<input type='hidden' name='csrf_token' value='"
            FUNCTION TRIM(W-CSRF-TOKEN) "'><input type='hidden' name='cmd' value='rule-save'>".
    IF RE-ID > 0
        DISPLAY "<input type='hidden' name='id' value='" RE-ID "'>"
    ELSE
        DISPLAY "<input type='hidden' name='create_key' value='" R-CREATE-KEY "'>"
    END-IF.
    MOVE W-DATE-RAW TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "<label for='rule-date'>Urmatoarea scadenta<input type='date' min='1601-01-01' "
            "id='rule-date' name='date' value='" FUNCTION TRIM(W-ESC-OUT) "' required></label>"
            "<label for='rule-cat'>Categorie<select id='rule-cat' name='cat'>".
    PERFORM DISPLAY-CAT-OPTIONS.
    MOVE W-DESC-RAW TO W-ESC-IN.
    PERFORM HTML-ESCAPE.
    DISPLAY "</select></label><label for='rule-desc' class='description-field'>Descriere"
            "<input id='rule-desc' name='desc' maxlength='30' required value='"
            FUNCTION TRIM(W-ESC-OUT) "' placeholder='De exemplu, abonament lunar'></label>"
            "<label for='rule-amount'>Suma<input type='number' step='0.01' name='amount' "
            "id='rule-amount' min='-9999999.99' max='9999999.99' required value='" WITH NO ADVANCING.
    IF RE-ID > 0
        DISPLAY FUNCTION TRIM(W-EDIT-AMT-STR) "'></label>"
    ELSE
        MOVE W-AMOUNT-RAW TO W-ESC-IN
        PERFORM HTML-ESCAPE
        DISPLAY FUNCTION TRIM(W-ESC-OUT) "'></label>"
    END-IF.
    DISPLAY "<label for='rule-cycle'>Frecventa<select id='rule-cycle' name='cycle'>".
    IF R-CYCLE = "WEEKLY"
        DISPLAY "<option value='MONTHLY'>Lunar</option><option value='WEEKLY' selected>Saptamanal</option>"
    ELSE
        DISPLAY "<option value='MONTHLY'>Lunar</option><option value='WEEKLY'>Saptamanal</option>"
    END-IF.
    IF R-CYCLE = "YEARLY"
        DISPLAY "<option value='YEARLY' selected>Anual</option>"
    ELSE DISPLAY "<option value='YEARLY'>Anual</option>" END-IF.
    DISPLAY "</select></label><div class='entry-actions'><button type='submit' class='btn'>"
            "Salveaza regula</button>".
    IF RE-ID > 0 DISPLAY "<a class='btn secondary' href='?view=RECURRING#rule-form'>Anuleaza</a>" END-IF.
    DISPLAY "</div></form></section>".
