-- What each player owns, placed or not. Item ids are the original game's (restaurant.json).
create table owned_items (
    user_id bigint not null references users (id) on delete cascade,
    item_id integer not null,
    quantity integer not null check (quantity > 0),
    primary key (user_id, item_id)
);
