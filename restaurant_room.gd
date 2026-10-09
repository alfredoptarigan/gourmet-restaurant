class_name RestaurantRoom
extends Node2D
## A restaurant drawn from the original data and art. RestaurantPlay runs it (customers
## come in, order, eat, and pay) and RestaurantEditor rearranges it.
##
## The room size counts the wall tiles: row 0 and column 0 hold the walls, which stand on
## the inner edge of their tile, and the floor is everything from tile (1, 1) on
## (WorldRestaurant.addDefaultWalls, fillBaseArea).

const LOGIN_SCENE := "res://login.tscn"
const EDITOR_MUSIC := "MusicEditor"
const LEVEL_UP_SOUND := "SfxLevelUp"
const WALL_ITEM := "White Walls"
const WALL_CORNER_ITEM := "Wall Corner"
## Item rotation is the timeline frame: 0 is a wall along x = 0, 1 a wall along y = 0.
const WEST_WALL_ROTATION := 0
const NORTH_WALL_ROTATION := 1
const DOOR_TYPE := "doorItem"
const TABLE_TYPE := "tableItem"
const CHAIR_TYPE := "chairItem"
const STACKABLE_TYPE := "stackable"
const SURFACE_TYPE := "surface"
const WALL_DECORATION_TYPE := "wallDecorationItem"
const CHAIR_OVERLAY_SUFFIX := "Overlay"
const EMOTION_SPRITE := "Emotions"
const EMOTION_NODE := "Emotion"
const TOILET_WATER_SPRITE := "ToiletWater"
const CLEANER_NEEDED_SPRITE := "CleanerNeeded"
## Entries of the profile's saved data.
const MENU_KEY := "menu"
const JOBS_KEY := "jobs"
const AVATAR_KEY := "avatar"
const ENERGY_KEY := "energy"
const MUSIC_KEY := "music"
## The music the shop sells, and the type of the furniture that plays it.
const MUSIC_GROUP := "Music"
const MUSIC_PLAYER_TYPE := "musicPlayer"
const ACHIEVEMENT_TYPE := "achievementItem"
## The perk group of the food that restores staff energy.
const STAFF_FOOD_GROUP := "Employee"
## WorldRecipeMenu.RECIPE_LEVEL_NAMES, from level 1.
const RECIPE_LEVEL_NAMES: Array[String] = ["Simple", "Standard", "Classic", "Tasty", "Delicious", "Luxurious", "Gourmet", "Sensational", "Ultimate", "Royal"]
const INGREDIENT_GROUP := "Ingredient"
## GardenPlot.GROW_TIME and SEED_COST.
const GROW_HOURS := 48
const SEED_COST := 2000
const GARDEN_LEAVE := "Leave it"
## Cash price -> coin price on the server's coin market (server/src/kitchen.ts).
const INGREDIENT_COIN_PRICES := {4: 1000, 6: 1500, 8: 2000}
## The group of the outdoor area sizes the shop sells, and the type of outdoor-only items.
const OUTSIDE_GROUP := "OutsideAreaSize"
const OUTDOOR_TYPE := "outdoor"
## The grass of the outdoor area: the base colour in WorldRestaurant.setOutsideAreaSize.
const GRASS := Color("a2c957")
## In the order of RestaurantPlay.Job.
const JOB_NAMES: Array[String] = ["Chef", "Waiter", "Cleaner", "Rest"]
## Above the head of a standing character, in original-game pixels from its tile.
const EMOTION_OFFSET := Vector2(0, -52)
## Where the middle of the floor sits on the 760 x 600 stage.
const FLOOR_CENTER_ON_SCREEN := Vector2(380, 310)
## Draw order inside one tile, on top of the item's own (see RoomActor.DRAW_ORDER_STEP).
const OVER_ACTOR := 2
const SCROLL_BUTTONS := MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE

## WorldRestaurant.DEFAULT_RESTAURANT_ITEMS as a layout: what every new player starts with.
## The server holds the same layout (server/src/shop.ts) and hands it to new accounts; this
## copy is for playing offline.
const STARTER_LAYOUT := {
	"items": [
		{"id": 3070000, "x": 6, "y": 2, "rotation": 3},
		{"id": 3010000, "x": 0, "y": 4, "rotation": 0},
		{"id": 3000011, "x": 0, "y": 2, "rotation": 0},
		{"id": 3000011, "x": 0, "y": 6, "rotation": 0},
		{"id": 3040001, "x": 2, "y": 3, "rotation": 0},
		{"id": 3040001, "x": 2, "y": 5, "rotation": 0},
		{"id": 3040001, "x": 5, "y": 5, "rotation": 0},
		{"id": 3030010, "x": 3, "y": 3, "rotation": 0},
		{"id": 3030010, "x": 3, "y": 5, "rotation": 0},
		{"id": 3030010, "x": 6, "y": 5, "rotation": 0},
		{"id": 3200000, "x": 2, "y": 0, "rotation": 1},
		{"id": 3300000, "x": 1, "y": 7, "rotation": 0},
		{"id": 3100000, "x": 4, "y": 0, "rotation": 1},
		{"id": 3020003, "x": 1, "y": 1, "rotation": 0},
		{"id": 3020003, "x": 7, "y": 1, "rotation": 0},
		{"id": 3020003, "x": 7, "y": 7, "rotation": 0},
	],
	"floor": 3050000,
	"wallpaper": 3060016,
}

@onready var floor_layer: Node2D = $Floor
@onready var wall_layer: Node2D = $Walls
@onready var item_layer: Node2D = $Items
@onready var hud: CanvasLayer = $Hud

var grid: RoomGrid
var items: Array[RoomItem] = []
var play: RestaurantPlay
var editor: RestaurantEditor
var level := 1
var floor_id := 0
var wallpaper_id := 0
var outside_size := Vector2i.ZERO
## The music the player chose (an item of the Music group), or 0 for the default.
var music_id := 0
## Music the player has bought: item id -> true.
var owned_music: Dictionary = {}
## Floor tiles painted over the base floor: tile -> floor item id.
var floor_tiles: Dictionary = {}
## The job the player gave each employee (RestaurantPlay.Job); see staff_jobs().
var jobs: Array[int] = []
## The working time each employee has left, in seconds (RestaurantPlay.MAX_WORK_TIME when
## rested). It is saved with the time of saving, so time away counts too.
## ponytail: saved when the staff change or are fed, on decorating, and on signing out, not
## on quitting.
var energy: Array[float] = []
## How the player looks: {"items": {group: item name}, "skin": index, "hair": index} with the
## indexes into RestaurantPlay.SKIN_COLOURS and HAIR_COLOURS. Empty until the player chooses.
var look: Dictionary = {}
## Signed in: the recipes the player knows (recipe id -> level) and the ingredients they hold
## (ingredient id -> quantity), as the server last said. Offline every recipe is known.
var known_recipes: Dictionary = {}
var ingredients: Dictionary = {}
## The dish the player serves for each course: course name -> recipe id; see recipe_for().
var menu: Dictionary = {}
## Trash on the floor: tile -> sprite name. It stays while the restaurant is redecorated.
## ponytail: trash lasts for the session only. The original saves the count with the
## profile and adds what piled up while the player was away.
var trash: Dictionary = {}
var trash_timer := RestaurantPlay.TRASH_APPEAR_RATE

var _sprites := SpriteLibrary.load_group("indoor")
var _game_sprites := SpriteLibrary.load_group("game")
var _sync: EarningsSync
var _dish_sprites: Dictionary = {}
var _chair_overlays: Dictionary = {}
## Broken item -> the sprites that mark it as broken.
var _broken_marks: Dictionary = {}
## Tile -> the sprite of the trash lying there.
var _trash_sprites: Dictionary = {}
## Gourmet points from earlier openings this session, when playing offline.
var _offline_points := 0


func _ready() -> void:
	var points := int(Api.profile.get("gourmetPoints", 0)) if Api.is_signed_in() else 0
	level = Levels.level_for(points)
	if Api.is_signed_in():
		var saved: Dictionary = Api.profile.get("data", {})
		jobs = valid_jobs(saved.get(JOBS_KEY))
		menu = valid_menu(saved.get(MENU_KEY))
		look = valid_look(saved.get(AVATAR_KEY))
		energy = rested_energy(saved.get(ENERGY_KEY), jobs, Time.get_unix_time_from_system())
		var kitchen := await Api.fetch_kitchen()
		if kitchen["ok"]:
			_take_kitchen(kitchen["data"])
		var inventory := await Api.fetch_inventory()
		if inventory["ok"] and inventory["data"].get("items") is Dictionary:
			var owned := {}
			for item_id: String in inventory["data"]["items"]:
				owned[int(item_id)] = int(inventory["data"]["items"][item_id])
			outside_size = best_outside_size(owned)
			for item_id: int in owned:
				if GameData.interior_items.get_group_name_by_id(item_id) == MUSIC_GROUP:
					owned_music[item_id] = true
		var saved_music: Variant = saved.get(MUSIC_KEY)
		music_id = int(saved_music) if saved_music is float else 0
	build(_saved_layout())
	_connect_hud()
	start_play()


## The layout the server holds for this player, or the starting one when playing offline.
func _saved_layout() -> Dictionary:
	if Api.is_signed_in():
		var saved: Variant = Api.profile.get("data", {}).get("layout")
		if saved is Dictionary and saved.get("items") is Array:
			return saved
	return STARTER_LAYOUT


## Saved jobs as the game can use them: empty unless every entry is a known job.
static func valid_jobs(saved: Variant) -> Array[int]:
	var checked: Array[int] = []
	if not saved is Array:
		return checked
	for entry: Variant in saved:
		if not (entry is float or entry is int) or int(entry) not in RestaurantPlay.Job.values():
			return []
		checked.append(int(entry))
	return checked


## Saved energy as it stands `now` (unix seconds): every employee kept working or resting
## while the player was away. Empty unless the save is well-formed.
static func rested_energy(saved: Variant, staff_jobs: Array[int], now: float) -> Array[float]:
	var left: Array[float] = []
	if not saved is Dictionary or not saved.get("left") is Array or not saved.get("at") is float:
		return left
	for entry: Variant in saved["left"]:
		if not (entry is float or entry is int):
			return []
		left.append(clampf(entry, 0.0, RestaurantPlay.MAX_WORK_TIME))
	var working: Array[int] = staff_jobs.duplicate()
	while working.size() < left.size():
		working.append(RestaurantPlay.Job.WAITER)
	RestaurantPlay.spend_energy(left, working, maxf(0.0, now - float(saved["at"])))
	return left


func _save_energy() -> void:
	await _save(ENERGY_KEY, {"left": energy, "at": Time.get_unix_time_from_system()})


## A saved look as the game can use it: empty unless every part of it is something wearable.
static func valid_look(saved: Variant) -> Dictionary:
	if not saved is Dictionary or not saved.get("items") is Dictionary:
		return {}
	var items := {}
	for group_name in RestaurantPlay.LOOK_GROUPS:
		var item_name: Variant = saved["items"].get(group_name)
		var known := RestaurantPlay.wearable(group_name).any(func(item: Dictionary) -> bool: return item.get("name") == item_name)
		if not item_name is String or not known:
			return {}
		items[group_name] = item_name
	var colours := {}
	for part: Array in [["skin", RestaurantPlay.SKIN_COLOURS.size()], ["hair", RestaurantPlay.HAIR_COLOURS.size()]]:
		var index: Variant = saved.get(part[0])
		if not (index is float or index is int) or int(index) < 0 or int(index) >= part[1]:
			return {}
		colours[part[0]] = int(index)
	return {"items": items, "skin": colours["skin"], "hair": colours["hair"]}


## A saved menu as the game can use it: only courses whose recipe really is of that course.
static func valid_menu(saved: Variant) -> Dictionary:
	var checked := {}
	if not saved is Dictionary:
		return checked
	for course in RestaurantPlay.MENU_GROUPS:
		var recipe_id: Variant = saved.get(course)
		if (recipe_id is float or recipe_id is int) and GameData.recipe_items.get_group_name_by_id(int(recipe_id)) == course:
			checked[course] = int(recipe_id)
	return checked


## The outdoor area the player has: the biggest of the sizes they own (item id -> quantity),
## or zero when they own none.
static func best_outside_size(owned: Dictionary) -> Vector2i:
	var best := {}
	for area: Dictionary in GameData.interior_items.get_items(OUTSIDE_GROUP):
		if int(owned.get(int(area["id"]), 0)) > 0 and (best.is_empty() or int(area["sizeX"]) > int(best["sizeX"])):
			best = area
	return Vector2i(int(best["sizeX"]), int(best["sizeY"])) if not best.is_empty() else Vector2i.ZERO


## ponytail: outdoor furniture keeps its tile when the room grows with the level, so a row
## of it can end up indoors. Shift it south with the area if that bothers anyone.
func set_outside_size(new_size: Vector2i) -> void:
	if new_size == outside_size:
		return
	outside_size = new_size
	grid.set_outside(new_size)
	_rebuild_shell()


## One job for every employee the level allows: the player's choices first, the default
## split for the rest. A saved list longer than the level allows is cut short.
func staff_jobs() -> Array[int]:
	var staff := RestaurantPlay.default_jobs(int(Levels.row(level)["employees"]), items_of_type(RestaurantPlay.KITCHEN_TYPE).size())
	for index in mini(jobs.size(), staff.size()):
		staff[index] = jobs[index]
	return staff


## The recipes a course can be served with.
## Signed in, only the recipes the player has learned; offline, every visible one.
func menu_choices(course: String) -> Array:
	return GameData.recipe_items.get_items(course).filter(func(recipe: Dictionary) -> bool:
		if not known_recipes.is_empty():
			return known_recipes.has(int(recipe["id"]))
		return recipe.get("invisible") != true)


## The dish served for a course: the player's choice, or the first recipe of the course.
## ponytail: one dish per course. The original lets a higher level put two or three on the
## menu (numDishes), and a recipe's level adds 0.2 gourmet points a dish, which the server
## does not pay yet.
func recipe_for(course: String) -> Dictionary:
	if menu.has(course) and menu_choices(course).any(func(recipe: Dictionary) -> bool: return int(recipe["id"]) == menu[course]):
		return GameData.recipe_items.get_item_by_id(menu[course])
	var recipes := menu_choices(course)
	return recipes[0] if not recipes.is_empty() else {}


func build(layout: Dictionary) -> void:
	grid = RoomGrid.new(Levels.room_size(level))
	grid.set_outside(outside_size)
	floor_id = int(layout.get("floor", STARTER_LAYOUT["floor"]))
	wallpaper_id = int(layout.get("wallpaper", STARTER_LAYOUT["wallpaper"]))
	floor_tiles = {}
	for entry: Variant in layout.get("tiles", []):
		if entry is Dictionary:
			floor_tiles[Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))] = int(entry.get("id", 0))
	_build_shell()
	for entry: Dictionary in layout["items"]:
		place_item(int(entry["id"]), Vector2i(int(entry["x"]), int(entry["y"])), int(entry["rotation"]))


## The restaurant as it stands, in the form the server stores.
func to_layout() -> Dictionary:
	var placed: Array = []
	for item in items:
		placed.append({"id": item.item_id, "x": item.tile.x, "y": item.tile.y, "rotation": item.turns})
	var described := {"items": placed, "floor": floor_id, "wallpaper": wallpaper_id}
	if not floor_tiles.is_empty():
		var painted: Array = []
		for tile: Vector2i in floor_tiles:
			painted.append({"id": floor_tiles[tile], "x": tile.x, "y": tile.y})
		described["tiles"] = painted
	return described


func _process(_delta: float) -> void:
	if play == null:
		return
	_sync_dishes()
	_sync_chair_overlays()
	_sync_emotions()
	_sync_broken_marks()
	_sync_trash()
	hud.set_demand(play.demand, play.is_closed())


## Dragging with the right or middle button scrolls a restaurant bigger than the screen.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & SCROLL_BUTTONS != 0:
		position += event.relative
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and play != null:
		click_tile(RoomGrid.screen_to_tile(get_local_mouse_position()))


## A click while the restaurant is open picks up the trash on that tile, or repairs the
## broken toilet or arcade machine there.
## ponytail: both are instant and the click goes by floor tile, not by the art. The
## original queues a task for the player's own avatar, which is not in the room yet.
func click_tile(tile: Vector2i) -> void:
	if trash.has(tile):
		play.remove_trash(tile)
		return
	var item := item_at(tile)
	for standing in items_at(tile):
		if standing.has_type(MUSIC_PLAYER_TYPE):
			choose_music()
			return
		if standing.has_type(ACHIEVEMENT_TYPE):
			open_awards()
			return
	if item != null and item.is_broken():
		play.fix_item(item)


## WorldRestaurantPlay.getPlayingMusicForUser: the chosen music if it is free or bought,
## otherwise the default (the second Music item; the first is silence).
func playing_music() -> Dictionary:
	var chosen := GameData.interior_items.get_item_by_id(music_id)
	if GameData.interior_items.get_group_name_by_id(music_id) == MUSIC_GROUP and (int(chosen.get("cost", 0)) == 0 or owned_music.has(music_id)):
		return chosen
	return GameData.interior_items.get_items(MUSIC_GROUP)[1]


func music_choices() -> Array:
	return GameData.interior_items.get_items(MUSIC_GROUP).filter(func(music: Dictionary) -> bool:
		return int(music.get("cost", 0)) == 0 or owned_music.has(int(music["id"])))


## Clicking a jukebox or stereo picks the music. More music is sold in the Decorate shop.
func choose_music() -> ChoicePanel:
	var choices := music_choices()
	var panel: ChoicePanel = hud.open_choices("Music", [{
		"label": "Play",
		"options": choices.map(func(music: Dictionary) -> String: return music.get("name", "")),
		"selected": maxi(0, choices.find(playing_music())),
	}])
	panel.chosen.connect(func(selections: Array[int]) -> void:
		if selections[0] >= 0 and selections[0] < choices.size():
			set_music(int(choices[selections[0]]["id"])))
	return panel


## The achievement panel on the wall shows how far the player has got with each award.
func open_awards() -> void:
	if not Api.is_signed_in():
		hud.show_message("Sign in to win awards.")
		return
	var result := await Api.fetch_awards()
	if not result["ok"]:
		hud.show_message(result["error"])
		return
	show_awards(result["data"].get("progress", {}))


func show_awards(progress: Dictionary) -> ChoicePanel:
	var rows: Array = []
	for award: int in Awards.TABLE:
		rows.append({"label": Awards.TABLE[award][0], "options": [Awards.describe(award, int(progress.get(str(award), 0)))], "selected": 0})
	return hud.open_choices("Awards", rows)


func set_music(item_id: int) -> void:
	music_id = item_id
	if play != null:
		_play_music()
	_save(MUSIC_KEY, music_id)


func _play_music() -> void:
	var track: String = playing_music().get("className", "")
	if track.is_empty():
		Sounds.stop_music()
	else:
		Sounds.play_music(track)


func items_of_type(type: String) -> Array[RoomItem]:
	var matching: Array[RoomItem] = []
	for item in items:
		if item.has_type(type):
			matching.append(item)
	return matching


## Everything standing on the tile, bottom first: at most a table and a decoration on it.
func items_at(tile: Vector2i) -> Array[RoomItem]:
	var found: Array[RoomItem] = []
	for item in items:
		if Rect2i(item.tile, item.footprint).has_point(tile):
			found.append(item)
	return found


## The surface (a table) the item stands on, or null when it stands on the floor.
func surface_under(item: RoomItem) -> RoomItem:
	var below := items_at(item.tile)
	return below[0] if below.size() > 1 and below[0] != item and below[0].has_type(SURFACE_TYPE) else null


## WorldRestaurant.getItemAtTile: the first item placed on the tile, or null.
func item_at(tile: Vector2i) -> RoomItem:
	for item in items:
		if Rect2i(item.tile, item.footprint).has_point(tile):
			return item
	return null


## WorldRestaurant.getTableForChair: the table on the tile the chair faces, or null.
func table_for_chair(chair: RoomItem) -> RoomItem:
	var faced := item_at(RoomGrid.facing_tile(chair.tile, chair.rotation))
	return faced if faced != null and faced.has_type(TABLE_TYPE) else null


func sprite_name_of(item_id: int) -> String:
	return GameData.interior_items.get_item_by_id(item_id).get("className", "")


## The tiles an item would cover at this many turns.
func footprint_of(item_id: int, turns: int) -> Vector2i:
	var config := GameData.interior_items.get_item_by_id(item_id)
	var footprint := RoomGrid.footprint_from_extent(_sprites.extent(sprite_name_of(item_id)))
	# The data can overrule the size judged from the art (RoomItem's constructor).
	if config.get("sizeX") != null:
		footprint.x = int(config["sizeX"])
	if config.get("sizeY") != null:
		footprint.y = int(config["sizeY"])
	return RoomGrid.rotated_footprint(footprint, turns)


## WorldRestaurant.isValid, without stacking decorations on tables: wall decorations go on
## bare wall tiles, everything else on free floor or (if stackable) on a table, and outdoor
## items only outdoors.
func can_place(item_id: int, tile: Vector2i, turns: int) -> bool:
	var types := GameData.interior_items.get_types_by_id(item_id)
	var on_wall := WALL_DECORATION_TYPE in types
	var footprint := footprint_of(item_id, turns)
	for x in footprint.x:
		for y in footprint.y:
			var covered := tile + Vector2i(x, y)
			if not grid.contains(covered) or covered == Vector2i.ZERO:
				return false
			if grid.is_wall(covered) != on_wall:
				return false
			# WorldRestaurant.isValid: a stackable item may stand on a lone surface.
			var below := items_at(covered)
			if not below.is_empty() and not (STACKABLE_TYPE in types and below.size() == 1 and below[0].has_type(SURFACE_TYPE)):
				return false
			if OUTDOOR_TYPE in types and not grid.is_outside(covered):
				return false
	return true


## Puts an item into the room. Does not check can_place: a saved layout is taken as it is.
func place_item(item_id: int, tile: Vector2i, turns: int) -> RoomItem:
	var sprite_name := sprite_name_of(item_id)
	if sprite_name.is_empty():
		push_error("RestaurantRoom: no item %d in the data" % item_id)
		return null
	var sprite := _place(item_layer, sprite_name, tile, turns)
	if sprite == null:
		return null
	var item := RoomItem.new()
	item.item_id = item_id
	item.config = GameData.interior_items.get_item_by_id(item_id)
	item.item_name = item.config.get("name", "")
	item.types = GameData.interior_items.get_types_by_id(item_id)
	item.tile = tile
	item.turns = turns
	# The shown frame wraps at the art's frame count, but the footprint turns every time:
	# the default stove is asked for 3 turns, shows frame 0, and still ends up 1 x 2.
	item.rotation = sprite.frame
	item.footprint = footprint_of(item_id, turns)
	item.top_height = _sprites.item_height(sprite_name, RoomGrid.footprint_from_extent(_sprites.extent(sprite_name)).y)
	item.sprite = sprite
	sprite.z_index = RoomGrid.tile_draw_order(tile) * RoomActor.DRAW_ORDER_STEP
	var surface := item_at(tile)
	if item.has_type(STACKABLE_TYPE) and surface != null and surface.has_type(SURFACE_TYPE):
		sprite.position.y -= surface.top_height
		sprite.z_index = surface.sprite.z_index + OVER_ACTOR
	grid.add_item(tile, item.footprint, item.has_type(DOOR_TYPE))
	# Trash under furniture could not be seen or swept, yet would still put customers off.
	for x in item.footprint.x:
		for y in item.footprint.y:
			trash.erase(tile + Vector2i(x, y))
	items.append(item)
	return item


func remove_item(item: RoomItem) -> void:
	grid.remove_item(item.tile, item.footprint, item.has_type(DOOR_TYPE))
	items.erase(item)
	item.sprite.queue_free()


## WorldRestaurantEditor's floor painting: one floor item covers one tile of the room.
func can_paint(tile: Vector2i) -> bool:
	return tile.x >= 1 and tile.y >= 1 and tile.x < grid.size.x and tile.y < grid.size.y


func floor_at(tile: Vector2i) -> int:
	return floor_tiles.get(tile, floor_id)


func paint_floor(tile: Vector2i, item_id: int) -> void:
	if item_id == floor_id:
		floor_tiles.erase(tile)
	else:
		floor_tiles[tile] = item_id
	_rebuild_shell()


func set_floor(item_id: int) -> void:
	floor_id = item_id
	_rebuild_shell()


func set_wallpaper(item_id: int) -> void:
	wallpaper_id = item_id
	_rebuild_shell()


## WorldRestaurant.setRoomSize: a higher level gives a bigger floor. Furniture stays put.
func resize(new_size: Vector2i) -> void:
	if new_size == grid.size:
		return
	grid.resize(new_size)
	_rebuild_shell()


## Opens the restaurant: staff take their places and customers start arriving.
func start_play() -> void:
	play = RestaurantPlay.new()
	play.name = "Play"
	add_child(play)
	var staff := staff_jobs()
	energy.resize(mini(energy.size(), staff.size()))
	while energy.size() < staff.size():
		energy.append(RestaurantPlay.MAX_WORK_TIME)
	play.start(self, staff)
	play.sound_wanted.connect(Sounds.play)
	_play_music()
	if _sync != null:
		play.award_progressed.connect(func(award: int) -> void: Api.report_award(award))
		play.dish_paid.connect(_sync.add_dish)
		play.extra_paid.connect(_sync.add_extra)
	else:
		var show_progress := func() -> void: _on_progress(_offline_points + int(play.gourmet_points))
		play.coins_changed.connect(hud.set_coins)
		play.dish_paid.connect(show_progress)
		play.extra_paid.connect(show_progress)


## Closes it: everyone leaves at once and the furniture forgets them.
func stop_play() -> void:
	if play == null:
		return
	_offline_points += int(play.gourmet_points)
	play.free()
	play = null
	for child in item_layer.get_children():
		if child is RoomActor:
			child.free()
	for sprite: Sprite2D in _dish_sprites.values() + _chair_overlays.values():
		sprite.queue_free()
	_dish_sprites.clear()
	_chair_overlays.clear()
	for item in items:
		item.occupant = null
		item.table_top_order = null
		item.ready_order = null
		item.cleaner = null
		item.waiter = null


## Signed in, coins and progress are the server's; offline, they are this session's count.
func _connect_hud() -> void:
	hud.set_signed_in(Api.is_signed_in())
	hud.sign_out_pressed.connect(_sign_out)
	hud.decorate_pressed.connect(_decorate)
	hud.menu_pressed.connect(choose_menu)
	hud.staff_pressed.connect(choose_staff)
	hud.avatar_pressed.connect(choose_avatar)
	hud.feed_pressed.connect(choose_food)
	hud.recipes_pressed.connect(choose_recipe)
	hud.garden_pressed.connect(open_garden)
	if not Api.is_signed_in():
		hud.set_coins(0)
		_on_progress(0)
		return
	_sync = EarningsSync.new()
	_sync.name = "EarningsSync"
	add_child(_sync)
	_sync.coins_changed.connect(hud.set_coins)
	_sync.progress_changed.connect(_on_progress)
	_sync.leveled_up.connect(func(new_level: int, reward: int) -> void:
		hud.show_message("Level %d! You earned %d coins." % [new_level, reward]))
	_sync.start()


## The shop changed the balance.
func set_confirmed_coins(coins: int) -> void:
	if _sync != null:
		_sync.set_confirmed_coins(coins)


func _on_progress(gourmet_points: int) -> void:
	hud.set_gourmet_points(gourmet_points)
	var reached := Levels.level_for(gourmet_points)
	if reached <= level:
		return
	level = reached
	Sounds.play(LEVEL_UP_SOUND)
	if not Api.is_signed_in():
		hud.show_message("Level %d!" % level)
	resize(Levels.room_size(level))


func _decorate() -> void:
	if editor != null:
		return
	_save_energy()
	stop_play()
	hud.decorate_button.disabled = true
	hud.staff_button.disabled = true
	hud.avatar_button.disabled = true
	editor = RestaurantEditor.new()
	editor.name = "Editor"
	add_child(editor)
	editor.finished.connect(_on_editor_finished)
	Sounds.play_music(EDITOR_MUSIC)
	editor.start(self)


func _on_editor_finished() -> void:
	editor.queue_free()
	editor = null
	hud.decorate_button.disabled = false
	hud.staff_button.disabled = false
	hud.avatar_button.disabled = false
	start_play()


func choose_menu() -> ChoicePanel:
	var rows: Array = []
	for course in RestaurantPlay.courses_for(level):
		var recipes := menu_choices(course)
		rows.append({
			"label": course,
			"options": recipes.map(func(recipe: Dictionary) -> String: return recipe.get("name", "")),
			"selected": maxi(0, recipes.find(recipe_for(course))),
		})
	var panel: ChoicePanel = hud.open_choices("Menu", rows)
	panel.chosen.connect(_on_menu_chosen)
	return panel


func _on_menu_chosen(selections: Array[int]) -> void:
	var courses := RestaurantPlay.courses_for(level)
	var picked := menu.duplicate()
	for index in mini(courses.size(), selections.size()):
		var recipes := menu_choices(courses[index])
		if selections[index] >= 0 and selections[index] < recipes.size():
			picked[courses[index]] = int(recipes[selections[index]]["id"])
	menu = picked
	_save(MENU_KEY, menu)


## ponytail: the staff are the game's own characters. The original has the player hire
## friends (WorldHire), which needs a friends list this game does not have.
func choose_staff() -> ChoicePanel:
	var staff := staff_jobs()
	var rows: Array = []
	for index in staff.size():
		var percent := roundi(energy[index] / RestaurantPlay.MAX_WORK_TIME * 100.0) if index < energy.size() else 100
		rows.append({"label": "Employee %d (%d%% energy)" % [index + 1, percent], "options": JOB_NAMES, "selected": staff[index]})
	var panel: ChoicePanel = hud.open_choices("Staff", rows)
	panel.chosen.connect(_on_staff_chosen)
	return panel


## New jobs take effect at once: the restaurant closes and reopens with the new staff.
func _on_staff_chosen(selections: Array[int]) -> void:
	jobs = selections
	_reopen()
	_save(JOBS_KEY, jobs)
	_save_energy()


## ponytail: a form of drop-downs with no preview, and every item is free to wear. The
## original has a dressing room that sells clothes (WorldCustomiseAvatar).
func choose_avatar() -> ChoicePanel:
	var rows: Array = []
	for group_name in RestaurantPlay.LOOK_GROUPS:
		var names: Array = RestaurantPlay.wearable(group_name).map(func(item: Dictionary) -> String: return item.get("name", ""))
		rows.append({"label": group_name, "options": names, "selected": maxi(0, names.find(look.get("items", {}).get(group_name)))})
	rows.append({"label": "Skin", "options": RestaurantPlay.SKIN_COLOUR_NAMES, "selected": look.get("skin", 0)})
	rows.append({"label": "Hair colour", "options": RestaurantPlay.HAIR_COLOUR_NAMES, "selected": look.get("hair", 0)})
	var panel: ChoicePanel = hud.open_choices("Avatar (worn by your first employee)", rows)
	panel.chosen.connect(_on_avatar_chosen)
	return panel


func _on_avatar_chosen(selections: Array[int]) -> void:
	var groups := RestaurantPlay.LOOK_GROUPS
	var items := {}
	for index in groups.size():
		var choices := RestaurantPlay.wearable(groups[index])
		if selections[index] < 0 or selections[index] >= choices.size():
			return
		items[groups[index]] = choices[selections[index]]["name"]
	look = valid_look({"items": items, "skin": selections[groups.size()], "hair": selections[groups.size() + 1]})
	_reopen()
	_save(AVATAR_KEY, look)


func _take_kitchen(data: Dictionary) -> void:
	if data.get("recipes") is Dictionary:
		known_recipes = {}
		for recipe_id: String in data["recipes"]:
			known_recipes[int(recipe_id)] = int(data["recipes"][recipe_id])
	if data.get("ingredients") is Dictionary:
		ingredients = {}
		for ingredient_id: String in data["ingredients"]:
			ingredients[int(ingredient_id)] = int(data["ingredients"][ingredient_id])


## Recipe's constructor: ingredient id -> how many one level of the recipe takes.
static func ingredients_of(recipe: Dictionary) -> Dictionary:
	var needed := {}
	for ingredient_name: String in str(recipe.get("ingredients", "")).split(","):
		var ingredient := GameData.ingredient_items.get_item_from_group(ingredient_name.strip_edges(), INGREDIENT_GROUP)
		if not ingredient.is_empty():
			needed[int(ingredient["id"])] = needed.get(int(ingredient["id"]), 0) + 1
	return needed


## The recipes that can be learned or improved: every course, known ones first.
func learnable_recipes() -> Array:
	var recipes: Array = []
	for course in RestaurantPlay.MENU_GROUPS:
		for recipe: Dictionary in GameData.recipe_items.get_items(course):
			var level := int(known_recipes.get(int(recipe["id"]), 0))
			if level < RECIPE_LEVEL_NAMES.size() and (level > 0 or (recipe.get("invisible") != true and not recipe.has("expireDate"))):
				recipes.append(recipe)
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return known_recipes.has(int(a["id"])) and not known_recipes.has(int(b["id"])))
	return recipes


func market_ingredients() -> Array:
	return GameData.ingredient_items.get_items(INGREDIENT_GROUP).filter(func(ingredient: Dictionary) -> bool:
		return ingredient.get("noCoinShop") != true and INGREDIENT_COIN_PRICES.has(int(ingredient.get("cash", 0))))


## How a recipe reads in the form: its level and what the next one takes, with what is held.
func describe_recipe(recipe: Dictionary) -> String:
	var level := int(known_recipes.get(int(recipe["id"]), 0))
	var parts: Array = []
	var needed := ingredients_of(recipe)
	for ingredient_id: int in needed:
		var name: String = GameData.ingredient_items.get_item_by_id(ingredient_id).get("name", "?")
		parts.append("%s %d/%d" % [name, ingredients.get(ingredient_id, 0), needed[ingredient_id]])
	var standing := "%s (level %d)" % [RECIPE_LEVEL_NAMES[level - 1], level] if level > 0 else "not learned"
	return "%s, %s; needs %s" % [recipe.get("name", ""), standing, ", ".join(parts)]


## WorldRecipeMenu and the ingredient market in one form: pick a recipe to learn or improve,
## or an ingredient to buy, or both.
## ponytail: drop-downs with no pictures; the original is a cookbook with a page per course.
func choose_recipe() -> ChoicePanel:
	var recipes: Array = learnable_recipes()
	var market: Array = market_ingredients()
	var panel: ChoicePanel = hud.open_choices("Recipes", [
		{"label": "Learn or improve", "options": ["(nothing)"] + recipes.map(describe_recipe), "selected": 0},
		{"label": "Buy an ingredient", "options": ["(nothing)"] + market.map(func(ingredient: Dictionary) -> String:
			return "%s, %d coins (have %d)" % [ingredient.get("name", ""), INGREDIENT_COIN_PRICES[int(ingredient["cash"])], ingredients.get(int(ingredient["id"]), 0)]),
			"selected": 0},
	])
	panel.chosen.connect(func(selections: Array[int]) -> void: _on_recipe_chosen(selections, recipes, market))
	return panel


func _on_recipe_chosen(selections: Array[int], recipes: Array, market: Array) -> void:
	if selections[0] <= 0 and selections[1] <= 0:
		return
	if not Api.is_signed_in():
		hud.show_message("Sign in to learn recipes and buy ingredients.")
		return
	if selections[1] > 0 and selections[1] <= market.size():
		var bought := await Api.buy_ingredient(int(market[selections[1] - 1]["id"]))
		if not bought["ok"]:
			hud.show_message(bought["error"])
			return
		ingredients[int(market[selections[1] - 1]["id"])] = int(bought["data"].get("quantity", 1))
		set_confirmed_coins(int(bought["data"].get("coins", 0)))
	if selections[0] > 0 and selections[0] <= recipes.size():
		var recipe: Dictionary = recipes[selections[0] - 1]
		var learned := await Api.learn_recipe(int(recipe["id"]))
		if not learned["ok"]:
			hud.show_message(learned["error"])
			return
		_take_kitchen(learned["data"])
		set_confirmed_coins(int(learned["data"].get("coins", 0)))
		if _sync != null:
			_sync.set_confirmed_points(int(learned["data"].get("gourmetPoints", 0)))
		hud.show_message("%s is now %s." % [recipe.get("name", ""), RECIPE_LEVEL_NAMES[int(learned["data"].get("level", 1)) - 1]])


## What can be done with a plot, for the garden form: the first is always to leave it be.
static func plot_actions(plot: Dictionary) -> Array[String]:
	if plot.is_empty():
		return [GARDEN_LEAVE, "Plant a seed (%d coins)" % SEED_COST]
	if plot.get("ripe") == true:
		return [GARDEN_LEAVE, "Harvest"]
	return [GARDEN_LEAVE, "Water"]


static func describe_plot(index: int, plot: Dictionary) -> String:
	if plot.is_empty():
		return "Plot %d: empty" % (index + 1)
	var plant: String = GameData.ingredient_items.get_item_by_id(int(plot.get("ingredientId", 0))).get("name", "?")
	return "Plot %d: %s, %d of %d wet hours, soil wet for %.1f h" % [
		index + 1, plant, int(plot.get("grownSeconds", 0)) / 3600, GROW_HOURS, float(plot.get("wetSeconds", 0)) / 3600.0]


## GardenPlot and GardenPlotActor as a form: one row per plot the level has.
## ponytail: plots are rows in a form, not beds drawn beside the restaurant, and a friend
## cannot water them yet.
func open_garden() -> void:
	if not Api.is_signed_in():
		hud.show_message("Sign in to garden.")
		return
	var result := await Api.fetch_garden()
	if not result["ok"]:
		hud.show_message(result["error"])
		return
	var garden: Dictionary = result["data"]
	if int(garden.get("plotCount", 0)) == 0:
		hud.show_message("Your first garden plot opens at level 7.")
		return
	choose_garden(garden)


func choose_garden(garden: Dictionary) -> ChoicePanel:
	var plots := {}
	for plot: Dictionary in garden.get("plots", []):
		plots[int(plot.get("plot", -1))] = plot
	var rows: Array = []
	for index in int(garden.get("plotCount", 0)):
		rows.append({"label": describe_plot(index, plots.get(index, {})), "options": plot_actions(plots.get(index, {})), "selected": 0})
	var panel: ChoicePanel = hud.open_choices("Garden", rows)
	panel.chosen.connect(func(selections: Array[int]) -> void: _on_garden_chosen(selections, plots))
	return panel


func _on_garden_chosen(selections: Array[int], plots: Dictionary) -> void:
	for index in selections.size():
		if selections[index] <= 0:
			continue
		var plot: Dictionary = plots.get(index, {})
		var action := "plant" if plot.is_empty() else ("harvest" if plot.get("ripe") == true else "water")
		var result := await Api.tend_plot(action, index)
		if not result["ok"]:
			hud.show_message(result["error"])
			return
		if result["data"].get("coins") is float:
			set_confirmed_coins(int(result["data"]["coins"]))
		if action == "harvest":
			var harvested := int(result["data"].get("ingredientId", 0))
			ingredients[harvested] = ingredients.get(harvested, 0) + 1
			hud.show_message("You harvested %s." % GameData.ingredient_items.get_item_by_id(harvested).get("name", "?"))


## The food that restores staff energy, as the Employee perks describe it.
func choose_food() -> ChoicePanel:
	var staff: Array = []
	for index in energy.size():
		staff.append("Employee %d (%d%% energy)" % [index + 1, roundi(energy[index] / RestaurantPlay.MAX_WORK_TIME * 100.0)])
	var foods: Array = GameData.perk_items.get_items(STAFF_FOOD_GROUP).map(
		func(food: Dictionary) -> String: return "%s, %s coins: %s" % [food.get("name", ""), food.get("cost", "?"), food.get("text", "")])
	var panel: ChoicePanel = hud.open_choices("Feed your staff", [
		{"label": "Who", "options": staff, "selected": 0}, {"label": "Food", "options": foods, "selected": 0}])
	panel.chosen.connect(_on_food_chosen)
	return panel


func _on_food_chosen(selections: Array[int]) -> void:
	var foods := GameData.perk_items.get_items(STAFF_FOOD_GROUP)
	if selections[0] < 0 or selections[0] >= energy.size() or selections[1] < 0 or selections[1] >= foods.size():
		return
	if not Api.is_signed_in():
		hud.show_message("Sign in to buy food.")
		return
	var food: Dictionary = foods[selections[1]]
	var result := await Api.use_item(int(food["id"]))
	if not result["ok"]:
		hud.show_message(result["error"])
		return
	set_confirmed_coins(int(result["data"].get("coins", 0)))
	give_energy(selections[0], float(food.get("workTime", 0)))
	_save_energy()


## GameUserEmployee.addPerk: food tops an employee's energy up, to no more than full.
func give_energy(employee: int, seconds: float) -> void:
	energy[employee] = minf(energy[employee] + seconds, RestaurantPlay.MAX_WORK_TIME)


func _reopen() -> void:
	if play != null:
		stop_play()
		start_play()


func _save(key: String, value: Variant) -> void:
	if not Api.is_signed_in():
		return
	var result := await Api.save_data(key, value)
	if not result["ok"]:
		hud.show_message("Could not save: %s" % result["error"])


func _sign_out() -> void:
	Sounds.stop_music()
	if Api.is_signed_in():
		await _save_energy()
		await Api.logout()
	get_tree().change_scene_to_file(LOGIN_SCENE)


func _place(layer: Node2D, sprite_name: String, tile: Vector2i, frame: int) -> Sprite2D:
	var sprite := _sprites.make_sprite(sprite_name, frame)
	if sprite == null:
		return null
	sprite.position = RoomGrid.tile_to_screen(tile)
	layer.add_child(sprite)
	return sprite


func _sprite_name_of_named(item_name: String) -> String:
	return GameData.interior_items.get_item(item_name).get("className", "")


func _rebuild_shell() -> void:
	for layer: Node2D in [floor_layer, wall_layer]:
		for child in layer.get_children():
			child.free()
	_build_shell()


## Floor, walls, and wallpaper for the current size, with the floor centred on the stage.
func _build_shell() -> void:
	var size := grid.size
	position = FLOOR_CENTER_ON_SCREEN - RoomGrid.tile_to_screen(size) / 2.0
	if outside_size != Vector2i.ZERO:
		var corner := Vector2i(0, size.y)
		var grass := Polygon2D.new()
		grass.name = "Grass"
		grass.color = GRASS
		grass.polygon = PackedVector2Array([
			RoomGrid.tile_to_screen(corner), RoomGrid.tile_to_screen(corner + Vector2i(outside_size.x, 0)),
			RoomGrid.tile_to_screen(corner + outside_size), RoomGrid.tile_to_screen(corner + Vector2i(0, outside_size.y)),
		])
		floor_layer.add_child(grass)
	for y in range(1, size.y):
		for x in range(1, size.x):
			_place(floor_layer, sprite_name_of(floor_at(Vector2i(x, y))), Vector2i(x, y), 0)
	# WorldRestaurant.addDefaultWalls and setWallPaper.
	var wall := _sprite_name_of_named(WALL_ITEM)
	var wallpaper := sprite_name_of(wallpaper_id)
	var segments: Array[Dictionary] = []
	for x in range(1, size.x):
		segments.append({"tile": Vector2i(x, 0), "rotation": NORTH_WALL_ROTATION})
	for y in range(1, size.y):
		segments.append({"tile": Vector2i(0, y), "rotation": WEST_WALL_ROTATION})
	for segment in segments:
		_place(wall_layer, wall, segment["tile"], segment["rotation"])
		_place(wall_layer, wallpaper, segment["tile"], segment["rotation"])
		grid.add_wall(segment["tile"])
	_place(wall_layer, _sprite_name_of_named(WALL_CORNER_ITEM), Vector2i.ZERO, 0)
	grid.add_wall(Vector2i.ZERO)


## Keeps one dish sprite on every table that has a served order, showing how much is eaten.
## The simulation only tracks the order; this draws it (DishOrder was an AnimatedObject).
func _sync_dishes() -> void:
	var on_tables := {}
	for table in items_of_type(TABLE_TYPE):
		var order := table.table_top_order
		if order == null or not order.served:
			continue
		var sprite_name: String = order.recipe.get("className", "")
		on_tables[order] = true
		var dish: Sprite2D = _dish_sprites.get(order)
		if dish == null:
			if not _game_sprites.has_sprite(sprite_name):
				continue
			dish = _game_sprites.make_sprite(sprite_name)
			dish.position = RoomGrid.tile_center(table.tile) - Vector2(0, table.top_height)
			dish.z_index = table.sprite.z_index + OVER_ACTOR
			item_layer.add_child(dish)
			_dish_sprites[order] = dish
		# The dish's timeline runs from a full plate to an empty one.
		dish.frame = roundi(order.eaten * (_game_sprites.frame_count(sprite_name) - 1))
	for order: DishOrder in _dish_sprites.keys():
		if not on_tables.has(order):
			_dish_sprites[order].queue_free()
			_dish_sprites.erase(order)


## Draws a chair's backrest over whoever sits on it (Customer.sitOnChair's chairOverlay).
func _sync_chair_overlays() -> void:
	for chair in items_of_type(CHAIR_TYPE):
		var seated := chair.occupant != null and chair.occupant.is_seated()
		var overlay: Sprite2D = _chair_overlays.get(chair)
		if seated and overlay == null:
			var sprite_name: String = chair.config.get("className", "") + CHAIR_OVERLAY_SUFFIX
			if not _sprites.has_sprite(sprite_name):
				continue
			overlay = _place(item_layer, sprite_name, chair.tile, chair.rotation)
			overlay.z_index = chair.sprite.z_index + OVER_ACTOR
			_chair_overlays[chair] = overlay
		elif not seated and overlay != null:
			overlay.queue_free()
			_chair_overlays.erase(chair)


## Shows what a customer is unhappy about, as the original's bubble over their head.
func _sync_emotions() -> void:
	for customer in play.customers:
		var bubble: Sprite2D = customer.get_node_or_null(EMOTION_NODE)
		if customer.emotion == Customer.Emotion.NONE:
			if bubble != null:
				bubble.free()
			continue
		if bubble == null:
			bubble = _game_sprites.make_sprite(EMOTION_SPRITE)
			if bubble == null:
				continue
			bubble.name = EMOTION_NODE
			bubble.position = EMOTION_OFFSET
			customer.add_child(bubble)
		bubble.frame = customer.emotion


## Marks broken toilets and arcade machines until someone repairs them
## (WorldRestaurantPlay.setRoomItemUsageCount).
## ponytail: the "cleaner needed" sign is its first frame, not the original's animation, and
## a broken arcade machine keeps its working look: flat sheets do not carry its "broken" clip.
func _sync_broken_marks() -> void:
	for item: RoomItem in _broken_marks.keys():
		if item not in items or not item.is_broken():
			for mark: Sprite2D in _broken_marks[item]:
				mark.queue_free()
			_broken_marks.erase(item)
	for item in items:
		if not item.is_broken() or _broken_marks.has(item):
			continue
		var marks: Array[Sprite2D] = []
		if item.has_type(RestaurantPlay.TOILET_TYPE) and _sprites.has_sprite(TOILET_WATER_SPRITE):
			var water := _place(item_layer, TOILET_WATER_SPRITE, item.tile, 0)
			water.z_index = item.sprite.z_index - 1
			marks.append(water)
		var sign_sprite := _game_sprites.make_sprite(CLEANER_NEEDED_SPRITE)
		if sign_sprite != null:
			sign_sprite.position = RoomGrid.tile_to_screen(item.tile) - Vector2(0, RoomGrid.TILE_HEIGHT)
			sign_sprite.z_index = item.sprite.z_index + OVER_ACTOR
			item_layer.add_child(sign_sprite)
			marks.append(sign_sprite)
		_broken_marks[item] = marks


## Draws the trash lying on the floor.
func _sync_trash() -> void:
	for tile: Vector2i in _trash_sprites.keys():
		if not trash.has(tile):
			_trash_sprites[tile].queue_free()
			_trash_sprites.erase(tile)
	for tile: Vector2i in trash:
		if _trash_sprites.has(tile):
			continue
		var sprite := _sprites.make_sprite(trash[tile])
		if sprite == null:
			continue
		sprite.position = RoomGrid.tile_center(tile)
		sprite.z_index = RoomGrid.tile_draw_order(tile) * RoomActor.DRAW_ORDER_STEP
		item_layer.add_child(sprite)
		_trash_sprites[tile] = sprite
