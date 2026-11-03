BEGIN IMMEDIATE;
CREATE TABLE ledger(id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(id BETWEEN 1 AND 999999),day TEXT NOT NULL CHECK(length(day)=10 AND day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND day>='0001-01-01' AND date(day,'+0 days') IS day),category TEXT NOT NULL CHECK(category IN ('Venituri','Locuinta','Mancare','Hobby','Utilitati')),description TEXT NOT NULL CHECK(length(trim(description))>0 AND length(CAST(description AS BLOB))<=30),amount_cents INTEGER NOT NULL CHECK(typeof(amount_cents)='integer' AND amount_cents BETWEEN -999999999 AND 999999999));
CREATE INDEX ledger_day ON ledger(day,id);
CREATE INDEX ledger_match ON ledger(day,category,description,amount_cents);
CREATE TABLE import_batches(token TEXT PRIMARY KEY,owner TEXT NOT NULL,expires INTEGER NOT NULL,source_json TEXT NOT NULL,options_json TEXT NOT NULL,preview_json TEXT NOT NULL DEFAULT '[]',rows_json TEXT NOT NULL DEFAULT '[]',state TEXT NOT NULL DEFAULT 'staged' CHECK(state IN ('staged','ready','done')),added INTEGER NOT NULL DEFAULT 0,skipped INTEGER NOT NULL DEFAULT 0);
CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
PRAGMA application_id=1279543122;
 PRAGMA user_version=1;
 COMMIT;
