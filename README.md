# Gourmet Street

A fan remake of a 2010 isometric restaurant game, built with Godot 4 and a small
Hono + PostgreSQL backend. Early work in progress: a new player's restaurant runs on its
own from the original data and art: customers walk in from the street, wait for a table,
order, eat, and pay. You sign in to the backend, which keeps your account, credits the coins
you earn, and holds your furniture.

- **Decorate** moves furniture and buys more with your coins, including toilets, sinks,
  arcade machines, drink dispensers, and (from level 10) an outdoor area.
- **Recipes** learns and improves recipes with ingredients (up to level 10, Royal), and
  buys ingredients for coins. A new player knows three recipes.
- **Garden** (from level 7) grows an ingredient from a 2000 coin seed. A plant needs
  48 hours of wet soil; water it every few hours.
- **Menu** sets the dish served for each course, from the recipes you know. Drinks join
  the menu at level 15.
- **Staff** makes each employee a chef, a waiter, or a cleaner, or lets them rest. Staff tire
  as they work and slow down; without a rested chef and waiter the restaurant closes.
- **Perks** buys food that restores an employee's energy, and help for the whole restaurant
  for some hours: cleaning (no trash), adverts (a popularity floor), or a consultant
  (double gourmet points).
- **Street** goes outside to your building; **Customise** there changes its body, roof,
  walls, door, and banner, and the name on it.
- **Avatar** sets how you look. Your first employee is you.
- Click trash on the floor to pick it up, and a broken toilet or arcade machine to repair it.
  A cleaner does both for you.

## No game assets in this repository

The original game's art, sound, and data files are not distributed here. To run the
project you need your own copy of the original resource files in `raw/` (git-ignored):

- `indoor_asset.swf`, `avatar_asset.swf`, `game_asset.swf`, `outdoor_asset.swf`, `ingredient_asset.swf`, `perk_asset.swf`, `sound_asset.swf`
- `front.bin`, `avatar.bin`, `restaurant.bin`, `perk.bin`, `ingredient.bin`, `recipe.bin`,
  `quiz.bin`, `appointment.bin`, `challenge.bin`, `lang_en.bin`, `lang_fr.bin`, `model.bin`
- `newsletter.xml`

Everything the game loads is generated from those files and is also git-ignored.

## Setup

Requirements: Godot 4.7, Python 3.9+ with Pillow, Java, and
[JPEXS Free Flash Decompiler](https://github.com/jindrapetrik/jpexs-decompiler)
(`ffdec.jar`, used to rasterise the vector art).

```bash
python3 tools/extract_data.py      # raw/*.bin -> data/*.json, assets/avatar/avatar.dae
python3 tools/extract_sprites.py indoor avatar game outdoor ingredient perk   # -> assets/sprites/ (several minutes, about 300 MB)
python3 tools/extract_sounds.py    # raw/sound_asset.swf -> assets/sounds/
```

`extract_sprites.py` reads the `JAVA` and `FFDEC_JAR` environment variables if Java or JPEXS
are not in the default locations listed at the top of the script.

Then start the server (see Backend below), open the folder in Godot, and press F5. Create an
account on the first screen, or choose "Play offline" to run without a server.

The game talks to `http://localhost:3000`. Set the `GOURMET_SERVER_URL` environment variable
to use another address.

## Checks

```bash
python3 -m unittest discover tools   # asset tools
tests/check_game.sh                  # headless Godot check (needs the generated assets)
                                     # after adding a script with a class_name, run once:
                                     #   godot --headless --path . --import
tests/check_online.sh                # the game's client against a real server (needs PostgreSQL)
godot --path . res://tests/screenshot.tscn -- res://street.tscn out.png   # picture of a scene
```

## Backend

`server/` is a Hono app on Node 24 (TypeScript runs directly, no build step) with PostgreSQL.

```bash
cd server
npm install
cp .env.example .env                 # then create the two databases it names
npm run dev                          # http://localhost:3000
npm test                             # needs the _test database
```

Endpoints so far: `GET /health`, `GET /time`, `POST /auth/register`, `POST /auth/login`,
`POST /auth/logout`, `GET /profile`, `PUT /profile`, `POST /profile/earnings`,
`GET /shop/inventory`, `POST /shop/buy`, `POST /shop/sell`, `POST /shop/use`, `GET /kitchen`, `POST /kitchen/learn`, `POST /kitchen/buy-ingredient`, `GET /garden`, `POST /garden/plant`, `POST /garden/water`, `POST /garden/harvest`, `GET /awards`, `POST /awards/progress`, `GET /quiz`, `POST /quiz/answer`, `GET /foodking`, `POST /foodking/claim`, `GET /shop/perks`, `GET /friends`, `POST /friends/request`, `POST /friends/accept`, `POST /friends/remove`, `GET /friends/:id/restaurant`, `POST /friends/:id/visit`, `POST /friends/:id/water`, `GET /mail`, `POST /mail/send`, `POST /mail/:id/open`.

Coins and cash are server-owned. A profile save can only change the `data` blob, and the
client reports how many dishes and extras (arcade plays, trash picked up) were paid for,
never how many coins: the server pays 2 coins a dish and 1 an extra, up to the rate a full
restaurant could serve in the time since the last report.
The shop takes its prices and unlock levels from `data/restaurant.json`, and a saved layout
may only place furniture the player owns. The menu and the staff's jobs are saved in the
profile's free-form `data`; they only steer the client's simulation, so the server does not
check them.

## Layout

| Path | What |
|---|---|
| `*.gd`, `*.tscn` | Godot client |
| `tools/` | Asset extraction scripts and their tests |
| `tests/` | Headless Godot check |
| `server/` | Backend |
| `raw/`, `data/`, `assets/` | Original and generated assets (git-ignored) |
