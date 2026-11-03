CREATE TABLE savings_goals(
    id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(id BETWEEN 1 AND 999999),
    name TEXT NOT NULL CHECK(length(trim(name))>0 AND length(CAST(name AS BLOB))<=30),
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    target_cents INTEGER NOT NULL CHECK(typeof(target_cents)='integer' AND target_cents BETWEEN 1 AND 999999999),
    deadline TEXT CHECK(deadline IS NULL OR (length(deadline)=10 AND deadline GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND deadline>='0001-01-01' AND date(deadline,'+0 days') IS deadline)),
    state TEXT NOT NULL DEFAULT 'active' CHECK(state IN ('active','completed','archived')),
    created_at INTEGER NOT NULL
);
CREATE TABLE goal_contributions(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    goal_id INTEGER NOT NULL REFERENCES savings_goals(id),
    amount_cents INTEGER NOT NULL CHECK(typeof(amount_cents)='integer' AND amount_cents<>0 AND amount_cents BETWEEN -999999999 AND 999999999),
    note TEXT NOT NULL CHECK(length(trim(note))>0 AND length(CAST(note AS BLOB))<=60),
    created_at INTEGER NOT NULL
);
CREATE INDEX goal_contributions_goal ON goal_contributions(goal_id,id);
CREATE INDEX savings_goals_account ON savings_goals(account_id,state);
CREATE TRIGGER immutable_goal_contribution_update BEFORE UPDATE ON goal_contributions
BEGIN SELECT RAISE(ABORT,'Goal contributions are append only'); END;
CREATE TRIGGER immutable_goal_contribution_delete BEFORE DELETE ON goal_contributions
BEGIN SELECT RAISE(ABORT,'Goal contributions are append only'); END;
