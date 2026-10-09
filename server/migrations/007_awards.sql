-- How far each player has got towards each award (GameAwards.AWARD_*). The trophies earned
-- are ordinary items in owned_items.
create table award_progress (
    user_id bigint not null references users (id) on delete cascade,
    award integer not null,
    value bigint not null check (value >= 0),
    primary key (user_id, award)
);
