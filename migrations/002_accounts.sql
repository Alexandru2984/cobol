CREATE TABLE accounts(
    id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(id BETWEEN 1 AND 999999),
    name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name))>0 AND length(CAST(name AS BLOB))<=30),
    kind TEXT NOT NULL CHECK(kind IN ('cash','card','bank')),
    opening_cents INTEGER NOT NULL DEFAULT 0 CHECK(typeof(opening_cents)='integer' AND opening_cents BETWEEN -999999999 AND 999999999),
    active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),
    CHECK(id<>1 OR active=1)
);
INSERT INTO accounts(id,name,kind) VALUES(1,'Registru principal','cash');
ALTER TABLE ledger ADD COLUMN account_id INTEGER NOT NULL DEFAULT 1 REFERENCES accounts(id);
CREATE INDEX ledger_account_match ON ledger(account_id,day,category,description,amount_cents);
CREATE TABLE transfers(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id INTEGER NOT NULL REFERENCES accounts(id),
    destination_id INTEGER NOT NULL REFERENCES accounts(id),
    day TEXT NOT NULL CHECK(length(day)=10 AND day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND day>='0001-01-01' AND date(day,'+0 days') IS day),
    description TEXT NOT NULL CHECK(length(trim(description))>0 AND length(CAST(description AS BLOB))<=60),
    amount_cents INTEGER NOT NULL CHECK(typeof(amount_cents)='integer' AND amount_cents BETWEEN 1 AND 999999999),
    voided INTEGER NOT NULL DEFAULT 0 CHECK(voided IN (0,1)),
    created_at INTEGER NOT NULL,
    CHECK(source_id<>destination_id)
);
CREATE INDEX transfers_source ON transfers(source_id,voided);
CREATE INDEX transfers_destination ON transfers(destination_id,voided);
CREATE TABLE finance_requests(
    nonce TEXT PRIMARY KEY,
    owner TEXT NOT NULL,
    operation TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    result_json TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE TABLE finance_events(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation TEXT NOT NULL,
    object_id INTEGER NOT NULL,
    owner TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
