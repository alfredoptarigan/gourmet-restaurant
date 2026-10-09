-- Garden plots. A plot row exists only while something grows in it. Growing only advances
-- while the soil is wet, so the stored state is the growth up to `checked_at` and how long
-- after that the soil stays wet (`wet_until`).
create table garden_plots (
    user_id bigint not null references users (id) on delete cascade,
    plot integer not null check (plot >= 0),
    ingredient_id integer not null,
    grown_seconds double precision not null default 0,
    checked_at timestamptz not null default now(),
    wet_until timestamptz not null,
    primary key (user_id, plot)
);
