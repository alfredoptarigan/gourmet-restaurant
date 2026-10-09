-- Friends. A request waits until the other player accepts it (or asks back); a friendship is
-- stored once, with the lower user id first.
create table friend_requests (
    from_id bigint not null references users (id) on delete cascade,
    to_id bigint not null references users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (from_id, to_id),
    check (from_id <> to_id)
);

create table friendships (
    user_a bigint not null references users (id) on delete cascade,
    user_b bigint not null references users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_a, user_b),
    check (user_a < user_b)
);

-- One visit, and one watering of each plot, counts per friend per day.
create table friend_visits (
    visitor_id bigint not null references users (id) on delete cascade,
    host_id bigint not null references users (id) on delete cascade,
    day date not null default current_date,
    primary key (visitor_id, host_id, day)
);

create table friend_waterings (
    visitor_id bigint not null references users (id) on delete cascade,
    host_id bigint not null references users (id) on delete cascade,
    plot integer not null,
    day date not null default current_date,
    primary key (visitor_id, host_id, plot, day)
);

-- Mail between friends: a free daily gift, an ingredient sent from the sender's own stock,
-- or a message. Whatever it carries is the recipient's once they open it.
create table mail (
    id bigint generated always as identity primary key,
    to_id bigint not null references users (id) on delete cascade,
    from_id bigint references users (id) on delete set null,
    kind text not null check (kind in ('gift', 'ingredient', 'message')),
    item_id integer,
    text text not null default '',
    created_at timestamptz not null default now(),
    opened_at timestamptz
);

create index mail_to_id_idx on mail (to_id, opened_at);
