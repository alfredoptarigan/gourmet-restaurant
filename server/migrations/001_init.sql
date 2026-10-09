create table users (
    id bigint generated always as identity primary key,
    username text not null,
    password_hash text not null,
    created_at timestamptz not null default now()
);

-- Usernames are unique regardless of case: "Anna" and "anna" are the same player.
create unique index users_username_lower_key on users (lower(username));

create table sessions (
    -- SHA-256 of the bearer token; the token itself is never stored.
    token_hash bytea primary key,
    user_id bigint not null references users (id) on delete cascade,
    expires_at timestamptz not null,
    created_at timestamptz not null default now()
);

create index sessions_user_id_idx on sessions (user_id);

create table profiles (
    user_id bigint primary key references users (id) on delete cascade,
    -- Currency lives in its own columns so only the server can change it;
    -- the client-writable part of the profile is `data`.
    coins bigint not null default 0 check (coins >= 0),
    cash bigint not null default 0 check (cash >= 0),
    data jsonb not null default '{}',
    -- Incremented on every save; a save must name the version it was based on.
    version integer not null default 0,
    updated_at timestamptz not null default now()
);
