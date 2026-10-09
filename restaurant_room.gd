class_name RestaurantRoom
extends Node2D
## A restaurant drawn from the original data and art. RestaurantPlay runs it (customers
## come in, order, eat, and pay) and RestaurantEditor rearranges it.
##
## The room size counts the wall tiles: row 0 and column 0 hold the walls, which stand on
## the inner edge of their tile, and the floor is everything from tile (1, 1) on
## (WorldRestaurant.addDefaultWalls, fillBaseArea).

const LOGIN_SCENE := "res://login.tscn"
const RESTAURANT_MUSIC := "MusicRestaurant"
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
const WALL_DECORATION_TYPE := "wallDecorationItem"
const CHAIR_OVERLAY_SUFFIX := "Overlay"
const EMOTION_SPRITE := "Emotions"
const EMOTION_NODE := "Emotion"
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

var _sprites := SpriteLibrary.load_group("indoor")
var _game_sprites := SpriteLibrary.load_group("game")
var _sync: EarningsSync
var _dish_sprites: Dictionary = {}
var _chair_overlays: Dictionary = {}
## Gourmet points from earlier openings this session, when playing offline.
var _offline_points := 0


func _ready() -> void:
	var points := int(Api.profile.get("gourmetPoints", 0)) if Api.is_signed_in() else 0
	level = Levels.level_for(points)
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


func build(layout: Dictionary) -> void:
	grid = RoomGrid.new(Levels.room_size(level))
	floor_id = int(layout.get("floor", STARTER_LAYOUT["floor"]))
	wallpaper_id = int(layout.get("wallpaper", STARTER_LAYOUT["wallpaper"]))
	_build_shell()
	for entry: Dictionary in layout["items"]:
		place_item(int(entry["id"]), Vector2i(int(entry["x"]), int(entry["y"])), int(entry["rotation"]))


## The restaurant as it stands, in the form the server stores.
func to_layout() -> Dictionary:
	var placed: Array = []
	for item in items:
		placed.append({"id": item.item_id, "x": item.tile.x, "y": item.tile.y, "rotation": item.turns})
	return {"items": placed, "floor": floor_id, "wallpaper": wallpaper_id}


func _process(_delta: float) -> void:
	if play == null:
		return
	_sync_dishes()
	_sync_chair_overlays()
	_sync_emotions()
	hud.set_demand(play.demand)


## Dragging with the right or middle button scrolls a restaurant bigger than the screen.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & SCROLL_BUTTONS != 0:
		position += event.relative


func items_of_type(type: String) -> Array[RoomItem]:
	var matching: Array[RoomItem] = []
	for item in items:
		if item.has_type(type):
			matching.append(item)
	return matching


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
## bare wall tiles, everything else on free floor.
func can_place(item_id: int, tile: Vector2i, turns: int) -> bool:
	var on_wall := WALL_DECORATION_TYPE in GameData.interior_items.get_types_by_id(item_id)
	var footprint := footprint_of(item_id, turns)
	for x in footprint.x:
		for y in footprint.y:
			var covered := tile + Vector2i(x, y)
			if not grid.contains(covered) or covered == Vector2i.ZERO:
				return false
			if grid.is_wall(covered) != on_wall or item_at(covered) != null:
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
	grid.add_item(tile, item.footprint, item.has_type(DOOR_TYPE))
	items.append(item)
	return item


func remove_item(item: RoomItem) -> void:
	grid.remove_item(item.tile, item.footprint, item.has_type(DOOR_TYPE))
	items.erase(item)
	item.sprite.queue_free()


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
	var doors := items_of_type(DOOR_TYPE)
	play.start(self, doors[0] if not doors.is_empty() else null, int(Levels.row(level)["employees"]))
	play.sound_wanted.connect(Sounds.play)
	Sounds.play_music(RESTAURANT_MUSIC)
	if _sync != null:
		play.dish_paid.connect(_sync.add_dish)
	else:
		play.coins_changed.connect(hud.set_coins)
		play.dish_paid.connect(func() -> void: _on_progress(_offline_points + int(play.gourmet_points)))


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


## Signed in, coins and progress are the server's; offline, they are this session's count.
func _connect_hud() -> void:
	hud.set_signed_in(Api.is_signed_in())
	hud.sign_out_pressed.connect(_sign_out)
	hud.decorate_pressed.connect(_decorate)
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
	stop_play()
	hud.decorate_button.disabled = true
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
	start_play()


func _sign_out() -> void:
	Sounds.stop_music()
	if Api.is_signed_in():
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
	var floor_sprite := sprite_name_of(floor_id)
	for y in range(1, size.y):
		for x in range(1, size.x):
			_place(floor_layer, floor_sprite, Vector2i(x, y), 0)
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
