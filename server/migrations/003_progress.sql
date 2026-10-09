-- Gourmet points decide the player's level. Like coins, only the server changes them.
alter table profiles add column gourmet_points integer not null default 0 check (gourmet_points >= 0);
