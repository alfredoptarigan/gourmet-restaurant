-- Every change to a player's cash, the paid currency, with the balance after it and why:
-- what was bought with it, or where it came from (a purchase, an admin grant).
create table cash_ledger (
    id bigint generated always as identity primary key,
    user_id bigint not null references users (id) on delete cascade,
    amount bigint not null check (amount <> 0),
    balance bigint not null check (balance >= 0),
    reason text not null,
    created_at timestamptz not null default now()
);

create index cash_ledger_user_id_idx on cash_ledger (user_id, created_at);
