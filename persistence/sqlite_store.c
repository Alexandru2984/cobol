/* Small typed persistence boundary. COBOL owns financial logic and rendering.
 * All callers, including imports/backups, also hold data/.ledger.lock. */
#define _POSIX_C_SOURCE 200809L
#include <sqlite3.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "schema.h"

static sqlite3 *db;
static sqlite3_stmt *cursor;
#define APP_ID 1279543122


static int pragma_number(const char *sql) {
    sqlite3_stmt *s = NULL;
    int value = -1;
    if (sqlite3_prepare_v2(db, sql, -1, &s, NULL) == SQLITE_OK && sqlite3_step(s) == SQLITE_ROW)
        value = sqlite3_column_int(s, 0);
    sqlite3_finalize(s);
    return value;
}

static int open_store(void) {
    struct stat st;
    if (db) return SQLITE_OK;
    int exists = lstat("data/ledger.sqlite3", &st) == 0;
    if (exists && (!S_ISREG(st.st_mode) || st.st_nlink != 1)) return SQLITE_CANTOPEN;
    if (!exists && lstat("data/ledger.dat", &st) == 0) return SQLITE_CANTOPEN;
    if (sqlite3_open_v2("data/ledger.sqlite3", &db,
            SQLITE_OPEN_READWRITE | (exists ? 0 : SQLITE_OPEN_CREATE) | SQLITE_OPEN_NOFOLLOW, NULL) != SQLITE_OK)
        return SQLITE_CANTOPEN;
    sqlite3_busy_timeout(db, 1000);
    sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
    sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 0, NULL);
    sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 1024 * 1024);
    sqlite3_limit(db, SQLITE_LIMIT_ATTACHED, 0);
    if (sqlite3_exec(db, "PRAGMA trusted_schema=OFF; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL; PRAGMA journal_mode=DELETE;", NULL, NULL, NULL) != SQLITE_OK)
        return SQLITE_ERROR;
    if (!exists) {
        if (chmod("data/ledger.sqlite3", 0600) || sqlite3_exec(db, ledger_schema_1, NULL, NULL, NULL) != SQLITE_OK)
            return SQLITE_ERROR;
        if (sqlite3_exec(db, "PRAGMA foreign_keys=OFF; BEGIN IMMEDIATE;", NULL, NULL, NULL) != SQLITE_OK
            || sqlite3_exec(db, ledger_schema_2, NULL, NULL, NULL) != SQLITE_OK
            || sqlite3_exec(db, "PRAGMA user_version=2; COMMIT; PRAGMA foreign_keys=ON;", NULL, NULL, NULL) != SQLITE_OK)
            return SQLITE_ERROR;
        if (sqlite3_exec(db, "BEGIN IMMEDIATE;", NULL, NULL, NULL) != SQLITE_OK
            || sqlite3_exec(db, ledger_schema_3, NULL, NULL, NULL) != SQLITE_OK
            || sqlite3_exec(db, "PRAGMA user_version=3; COMMIT;", NULL, NULL, NULL) != SQLITE_OK)
            return SQLITE_ERROR;
    }
    int version = pragma_number("PRAGMA user_version");
    if (pragma_number("PRAGMA application_id") != APP_ID || version < 1 || version > 3)
        return SQLITE_NOTADB;
    return SQLITE_OK;
}

static void bind_text(sqlite3_stmt *s, int n, const char *text, int length) {
    while (length && text[length-1] == ' ') --length;
    sqlite3_bind_text(s, n, text, length, SQLITE_TRANSIENT);
}

static int account_env(const char *name) {
    const char *raw = getenv(name);
    if (!raw || !*raw) return 0;
    int value = 0, count = 0;
    for (; *raw; raw++) {
        if (*raw < '0' || *raw > '9' || ++count > 6) return -1;
        value = value * 10 + *raw - '0';
    }
    return value;
}

static int copy_row(sqlite3_stmt *s, int32_t *id, char *day, char *cat, char *desc, int64_t *cents) {
    const int sizes[] = {10, 15, 30};
    char *outputs[] = {day, cat, desc};
    if (sqlite3_column_type(s, 0) != SQLITE_INTEGER || sqlite3_column_type(s, 4) != SQLITE_INTEGER)
        return SQLITE_CORRUPT;
    sqlite3_int64 key = sqlite3_column_int64(s, 0), money = sqlite3_column_int64(s, 4);
    if (key < 1 || key > 999999 || money < -999999999 || money > 999999999) return SQLITE_CORRUPT;
    for (int i = 0; i < 3; i++) {
        if (sqlite3_column_type(s, i+1) != SQLITE_TEXT) return SQLITE_CORRUPT;
        const unsigned char *value = sqlite3_column_text(s, i+1);
        int length = sqlite3_column_bytes(s, i+1);
        if (length < 1 || length > sizes[i] || (i == 0 && length != 10)) return SQLITE_CORRUPT;
        for (int j = 0; j < length; j++) if (value[j] < 32 || value[j] == 127) return SQLITE_CORRUPT;
        memset(outputs[i], ' ', sizes[i]);
        memcpy(outputs[i], value, length);
    }
    *id = (int32_t)key; *cents = money;
    return SQLITE_OK;
}

/* op: 0 open, 1 close, 2 read, 3 insert, 4 update, 5 delete,
 * 6/7 id asc/desc, 8/9 date asc/desc, 10 date >= bound,
 * 11 next, 12 durable ID high-water mark. */
int ledger_store(int32_t *op, int32_t *id, char *day, char *cat, char *desc,
                 int64_t *cents, char *status, int32_t *force_default) {
    int rc = SQLITE_OK;
    sqlite3_stmt *s = NULL;
    memcpy(status, "30", 2);
    if (*op == 1) {
        sqlite3_finalize(cursor); cursor = NULL;
        if (db) { rc = sqlite3_close(db); if (rc == SQLITE_OK) db = NULL; }
    } else if ((rc = open_store()) != SQLITE_OK) {
        /* Keep an unsuccessful open from being mistaken for a valid connection. */
        if (db) sqlite3_close(db);
        db = NULL;
        return 0;
    } else if (*op >= 6 && *op <= 10) {
        const char *queries[] = {
            "SELECT id,day,category,description,amount_cents FROM ledger WHERE (?1=0 OR account_id=?1) ORDER BY id",
            "SELECT id,day,category,description,amount_cents FROM ledger WHERE (?1=0 OR account_id=?1) ORDER BY id DESC",
            "SELECT id,day,category,description,amount_cents FROM ledger WHERE (?1=0 OR account_id=?1) ORDER BY day,id",
            "SELECT id,day,category,description,amount_cents FROM ledger WHERE (?1=0 OR account_id=?1) ORDER BY day DESC,id DESC",
            "SELECT id,day,category,description,amount_cents FROM ledger WHERE (?1=0 OR account_id=?1) AND day>=?2 ORDER BY day,id"};
        sqlite3_finalize(cursor); cursor = NULL;
        int filter = account_env("LEDGER_ACCOUNT_FILTER");
        if (filter < 0) return 0;
        rc = sqlite3_prepare_v2(db, queries[*op-6], -1, &cursor, NULL);
        if (rc == SQLITE_OK) sqlite3_bind_int(cursor, 1, filter);
        if (rc == SQLITE_OK && *op == 10) bind_text(cursor, 2, day, 10);
    } else if (*op == 11) {
        rc = cursor ? sqlite3_step(cursor) : SQLITE_MISUSE;
        if (rc == SQLITE_DONE) { memcpy(status, "10", 2); return 0; }
        if (rc == SQLITE_ROW) rc = copy_row(cursor, id, day, cat, desc, cents);
    } else if (*op == 12) {
        rc = sqlite3_prepare_v2(db, "SELECT max(coalesce((SELECT max(id) FROM ledger),0),coalesce((SELECT seq FROM sqlite_sequence WHERE name='ledger'),0))", -1, &s, NULL);
        if (rc == SQLITE_OK && sqlite3_step(s) == SQLITE_ROW) *id = sqlite3_column_int(s, 0);
        else rc = SQLITE_ERROR;
    } else if (*op >= 2 && *op <= 5) {
        const char *queries[] = {
            "SELECT id,day,category,description,amount_cents FROM ledger WHERE id=?",
            "INSERT INTO ledger(id,day,category,description,amount_cents,account_id) SELECT ?1,?2,?3,?4,?5,?6 WHERE EXISTS(SELECT 1 FROM accounts WHERE id=?6 AND active=1)",
            "UPDATE ledger SET day=?2,category=?3,description=?4,amount_cents=?5,account_id=CASE WHEN ?6=0 THEN account_id ELSE ?6 END WHERE id=?1 AND (?6=0 OR ?6=account_id OR EXISTS(SELECT 1 FROM accounts WHERE id=?6 AND active=1))",
            "DELETE FROM ledger WHERE id=?"};
        rc = sqlite3_prepare_v2(db, queries[*op-2], -1, &s, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_int(s, 1, *id);
            if (*op == 3 || *op == 4) {
                int account = account_env("LEDGER_TARGET_ACCOUNT");
                if (*force_default) account = 1;
                if (account < 0) { sqlite3_finalize(s); return 0; }
                if (*op == 3 && account == 0) account = 1;
                bind_text(s, 2, day, 10); bind_text(s, 3, cat, 15); bind_text(s, 4, desc, 30);
                sqlite3_bind_int64(s, 5, *cents);
                sqlite3_bind_int(s, 6, account);
            }
            rc = sqlite3_step(s);
            if (*op == 2) {
                if (rc == SQLITE_DONE) { memcpy(status, "23", 2); sqlite3_finalize(s); return 0; }
                if (rc == SQLITE_ROW) rc = copy_row(s, id, day, cat, desc, cents);
            } else if (rc == SQLITE_DONE) {
                rc = SQLITE_OK;
                if (sqlite3_changes(db) != 1) { memcpy(status, "23", 2); sqlite3_finalize(s); return 0; }
            }
        }
    }
    sqlite3_finalize(s);
    if (rc == SQLITE_OK) memcpy(status, "00", 2);
    return 0;
}
