-- When the player was last credited for served dishes. Reports are paid out against the time
-- that has passed since, so a client cannot claim more than a restaurant could have served.
alter table profiles add column last_earned_at timestamptz not null default now();
