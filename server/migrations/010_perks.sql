-- Restaurant perks in effect (perk.json's Restaurant group): what kind, how strong, and until when.
create table active_perks (
    user_id bigint not null references users (id) on delete cascade,
    kind text not null check (kind in ('clean', 'demand', 'gourmet')),
    value integer not null,
    until timestamptz not null,
    primary key (user_id, kind)
);
