-- Recipes the player has learned, at the level they reached (1 to 10), and the ingredients
-- they hold. Ids are the original game's (recipe.json, ingredient.json).
create table known_recipes (
    user_id bigint not null references users (id) on delete cascade,
    recipe_id integer not null,
    level integer not null check (level between 1 and 10),
    primary key (user_id, recipe_id)
);

create table owned_ingredients (
    user_id bigint not null references users (id) on delete cascade,
    ingredient_id integer not null,
    quantity integer not null check (quantity > 0),
    primary key (user_id, ingredient_id)
);
