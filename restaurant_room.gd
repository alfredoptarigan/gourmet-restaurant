class_name RestaurantRoom
extends Node2D
## A restaurant drawn from the original data and art. RestaurantPlay runs it (customers
## come in, order, eat, and pay) and RestaurantEditor rearranges it.
##
## The room size counts the wall tiles: row 0 and column 0 hold the walls, which stand on
## the inner edge of their tile, and the floor is everything from tile (1, 1) on
## (WorldRestaurant.addDefaultWalls, fillBaseArea).

const LOGIN_SCENE := "res://login.tscn"
const STREET_SCENE := "res://street.tscn"
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
const HIRED_KEY := "hired"
const MUSIC_KEY := "music"
## The music the shop sells, and the type of the furniture that plays it.
const MUSIC_GROUP := "Music"
const MUSIC_PLAYER_TYPE := "musicPlayer"
const ACHIEVEMENT_TYPE := "achievementItem"
const MAIL_TYPE := "mailItem"
## FoodkingActor.RESOURCE_NAMES[STATE_PICNIC]: Greg sitting on his picnic blanket.
const FOOD_KING_SPRITE := "GregPicnic"
## The perk group of the food that restores staff energy.
const STAFF_FOOD_GROUP := "Employee"
## The perk group of the things that help the whole restaurant for some hours.
const RESTAURANT_PERK_GROUP := "Restaurant"
const NOTHING := "(nothing)"
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
## Where the Food King sits today, and the rewards he offers; no tile while he is away.
var food_king_tile := Vector2i(-1, -1)
var food_king_rewards: Array = []
var _food_king_sprite: Sprite2D
## Restaurant perks in effect: kind ("clean", "demand", "gourmet") -> {"value", "until"},
## with `until` in unix seconds.
var perks: Dictionary = {}
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

var forms := RoomForms.new(self)
var social := RoomSocial.new(self)
## The friend's restaurant being visited, as the server sent it; empty at home.
var host: Dictionary = {}
## The player's friends (RoomSocial.valid_friends), and the friend hired as each employee
## (a user id, or 0 for a stranger).
var friends: Array = []
var hired: Array[int] = []
var overlays := RoomOverlays.new(self)
var _sprites := SpriteLibrary.load_group("indoor")
var _game_sprites := SpriteLibrary.load_group("game")
var _sync: EarningsSync
## Gourmet points from earlier openings this session, when playing offline.
var _offline_points := 0


func _ready() -> void:
	if not Api.visiting.is_empty():
		_ready_as_visitor()
		return
	var points := int(Api.profile.get("gourmetPoints", 0)) if Api.is_signed_in() else 0
	level = Levels.level_for(points)
	if Api.is_signed_in():
		var saved: Dictionary = Api.profile.get("data", {})
		jobs = ProfileRules.valid_jobs(saved.get(JOBS_KEY))
		menu = ProfileRules.valid_menu(saved.get(MENU_KEY))
		look = ProfileRules.valid_look(saved.get(AVATAR_KEY))
		energy = ProfileRules.rested_energy(saved.get(ENERGY_KEY), jobs, Time.get_unix_time_from_system())
		var kitchen := await Api.fetch_kitchen()
		if kitchen["ok"]:
			_take_kitchen(kitchen["data"])
		var inventory := await Api.fetch_inventory()
		if inventory["ok"] and inventory["data"].get("items") is Dictionary:
			var owned := {}
			for item_id: String in inventory["data"]["items"]:
				owned[int(item_id)] = int(inventory["data"]["items"][item_id])
			outside_size = ProfileRules.best_outside_size(owned)
			for item_id: int in owned:
				if GameData.interior_items.get_group_name_by_id(item_id) == MUSIC_GROUP:
					owned_music[item_id] = true
		var saved_music: Variant = saved.get(MUSIC_KEY)
		music_id = int(saved_music) if saved_music is float else 0
		hired = ProfileRules.valid_jobs(saved.get(HIRED_KEY), false)
		var friend_list := await Api.fetch_friends()
		if friend_list["ok"]:
			friends = RoomSocial.valid_friends(friend_list["data"].get("friends"))
	build(_saved_layout())
	_connect_hud()
	start_play()
	if Api.is_signed_in():
		_look_for_food_king()
		_take_perks(await Api.fetch_perks())


## The layout the server holds for this player, or the starting one when playing offline.
func _saved_layout() -> Dictionary:
	if Api.is_signed_in():
		var saved: Variant = Api.profile.get("data", {}).get("layout")
		if saved is Dictionary and saved.get("items") is Array:
			return saved
	return STARTER_LAYOUT


## WorldRestaurantPlay in visit mode: a friend's restaurant runs as it would for them, but
## nothing earned there is the visitor's. Only their garden can be helped with.
## ponytail: the friend's own staff and menu run with every recipe at level 1; their
## energy, trash, and perks stay theirs and are not shown.
func _ready_as_visitor() -> void:
	host = Api.visiting
	Api.visiting = {}
	level = clampi(int(host.get("level", 1)), 1, Levels.count())
	jobs = ProfileRules.valid_jobs(host.get("jobs"))
	menu = ProfileRules.valid_menu(host.get("menu"))
	look = ProfileRules.valid_look(host.get("avatar"))
	var layout: Variant = host.get("layout")
	build(layout if layout is Dictionary and layout.get("items") is Array else STARTER_LAYOUT)
	hud.set_visiting(str(host.get("username", "")))
	hud.sign_out_pressed.connect(_go_home)
	hud.garden_pressed.connect(func() -> void: social.choose_friend_garden(host))
	start_play()
	Api.visit_friend(int(host.get("id", 0)))


func _go_home() -> void:
	get_tree().change_scene_to_file(RoomSocial.RESTAURANT_SCENE)


## How an employee is dressed: the player's look for the first, a hired friend's for the
## others, or nothing (a random stranger).
func look_of(employee: int) -> Dictionary:
	if employee == 0:
		return look
	var friend_id := hired[employee] if employee < hired.size() else 0
	for friend: Dictionary in friends:
		if int(friend["id"]) == friend_id:
			return ProfileRules.valid_look(friend.get("avatar"))
	return {}


func _save_energy() -> void:
	await _save(ENERGY_KEY, {"left": energy, "at": Time.get_unix_time_from_system()})


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
	overlays.sync()
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
	if tile == food_king_tile:
		forms.choose_food_king_reward()
		return
	var item := item_at(tile)
	for standing in items_at(tile):
		if standing.has_type(MUSIC_PLAYER_TYPE):
			forms.choose_music()
			return
		if standing.has_type(ACHIEVEMENT_TYPE):
			forms.open_awards()
			return
		if standing.has_type(MAIL_TYPE):
			social.open_mailbox()
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


## FoodKing.addToRestaurant: on the days the server says he visits, Greg sits somewhere in
## the restaurant until the player finds him.
## ponytail: he sits still on his blanket; the original sometimes walks him in instead.
func _look_for_food_king() -> void:
	var result := await Api.fetch_food_king()
	if result["ok"] and result["data"].get("visiting") == true and result["data"].get("claimed") != true:
		seat_food_king(result["data"].get("rewards", []))


func seat_food_king(rewards: Array) -> void:
	var spots := play.free_floor_tiles() if play != null else []
	if spots.is_empty() or rewards.is_empty():
		return
	food_king_rewards = rewards
	food_king_tile = spots[randi() % spots.size()]
	_food_king_sprite = _sprites.make_sprite(FOOD_KING_SPRITE)
	if _food_king_sprite != null:
		_food_king_sprite.position = RoomGrid.tile_center(food_king_tile)
		_food_king_sprite.z_index = RoomGrid.tile_draw_order(food_king_tile) * RoomActor.DRAW_ORDER_STEP + OVER_ACTOR
		item_layer.add_child(_food_king_sprite)


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
	if not host.is_empty():
		return
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
	overlays.clear_service()
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
	hud.menu_pressed.connect(forms.choose_menu)
	hud.staff_pressed.connect(forms.choose_staff)
	hud.avatar_pressed.connect(forms.choose_avatar)
	hud.feed_pressed.connect(forms.choose_food)
	hud.recipes_pressed.connect(forms.choose_recipe)
	hud.garden_pressed.connect(forms.open_garden)
	hud.street_pressed.connect(_go_outside)
	hud.friends_pressed.connect(social.open_friends)
	hud.cash_pressed.connect(forms.choose_cash)
	hud.set_cash(int(Api.profile.get("cash", 0)))
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


## Spending or exchanging cash changed its balance.
func set_confirmed_cash(cash: int) -> void:
	Api.profile["cash"] = cash
	hud.set_cash(cash)


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


func _take_kitchen(data: Dictionary) -> void:
	if data.get("recipes") is Dictionary:
		known_recipes = {}
		for recipe_id: String in data["recipes"]:
			known_recipes[int(recipe_id)] = int(data["recipes"][recipe_id])
	if data.get("ingredients") is Dictionary:
		ingredients = {}
		for ingredient_id: String in data["ingredients"]:
			ingredients[int(ingredient_id)] = int(data["ingredients"][ingredient_id])


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


## Every ingredient is for sale: for coins on the coin market, or else for cash.
func market_ingredients() -> Array:
	return GameData.ingredient_items.get_items(INGREDIENT_GROUP).filter(func(ingredient: Dictionary) -> bool:
		return int(ingredient.get("cash", 0)) > 0)


## The coin price of an ingredient on the coin market, or 0 when it is sold only for cash.
static func ingredient_coin_price(ingredient: Dictionary) -> int:
	if ingredient.get("noCoinShop") == true:
		return 0
	return INGREDIENT_COIN_PRICES.get(int(ingredient.get("cash", 0)), 0)


## The food that restores staff energy, as the Employee perks describe it.
## How strong a restaurant perk is right now, or 0 when it is not in effect.
func perk_value(kind: String) -> int:
	var perk: Dictionary = perks.get(kind, {})
	return int(perk.get("value", 0)) if float(perk.get("until", 0.0)) > Time.get_unix_time_from_system() else 0


func _take_perks(result: Dictionary) -> void:
	if not result.get("ok", false) or not result["data"].get("perks") is Dictionary:
		return
	var now := Time.get_unix_time_from_system()
	perks = {}
	for kind: String in result["data"]["perks"]:
		var perk: Dictionary = result["data"]["perks"][kind]
		perks[kind] = {"value": int(perk.get("value", 0)), "until": now + float(perk.get("secondsLeft", 0))}


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


func _go_outside() -> void:
	if Api.is_signed_in():
		await _save_energy()
	get_tree().change_scene_to_file(STREET_SCENE)


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

