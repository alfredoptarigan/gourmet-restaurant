class_name RestaurantRoom
extends Node2D
## A restaurant drawn from the original data and art, with RestaurantPlay running it:
## customers come in, order, eat, and pay. No editing yet.
##
## The room size counts the wall tiles: row 0 and column 0 hold the walls, which stand on
## the inner edge of their tile, and the floor is everything from tile (1, 1) on
## (WorldRestaurant.addDefaultWalls, fillBaseArea).

const LOGIN_SCENE := "res://login.tscn"
const WALL_ITEM := "White Walls"
const WALL_CORNER_ITEM := "Wall Corner"
## Item rotation is the timeline frame: 0 is a wall along x = 0, 1 a wall along y = 0.
const WEST_WALL_ROTATION := 0
const NORTH_WALL_ROTATION := 1
const DOOR_TYPE := "doorItem"
const TABLE_TYPE := "tableItem"
const CHAIR_TYPE := "chairItem"
const CHAIR_OVERLAY_SUFFIX := "Overlay"
## Where the middle of the floor sits on the 760 x 600 stage.
const FLOOR_CENTER_ON_SCREEN := Vector2(380, 310)
## Draw order inside one tile, on top of the item's own (see RoomActor.DRAW_ORDER_STEP).
const OVER_ACTOR := 2

## WorldRestaurant.DEFAULT_RESTAURANT_ITEMS, minus the two wallpaper entries: the wallpaper
## is a property of the layout here.
const DEFAULT_ITEMS: Array[Dictionary] = [
	{"name": "Stove", "tile": Vector2i(6, 2), "rotation": 3},
	{"name": "Simple Door", "tile": Vector2i(0, 4), "rotation": 0},
	{"name": "Basic Window", "tile": Vector2i(0, 2), "rotation": 0},
	{"name": "Basic Window", "tile": Vector2i(0, 6), "rotation": 0},
	{"name": "Classic Chair", "tile": Vector2i(2, 3), "rotation": 0},
	{"name": "Classic Chair", "tile": Vector2i(2, 5), "rotation": 0},
	{"name": "Classic Chair", "tile": Vector2i(5, 5), "rotation": 0},
	{"name": "White Cloth Table", "tile": Vector2i(3, 3), "rotation": 0},
	{"name": "White Cloth Table", "tile": Vector2i(3, 5), "rotation": 0},
	{"name": "White Cloth Table", "tile": Vector2i(6, 5), "rotation": 0},
	{"name": "Achievement Panel", "tile": Vector2i(2, 0), "rotation": 1},
	{"name": "Letter Box", "tile": Vector2i(1, 7), "rotation": 0},
	{"name": "Menu Holder", "tile": Vector2i(4, 0), "rotation": 1},
	{"name": "DelicateBush", "tile": Vector2i(1, 1), "rotation": 0},
	{"name": "DelicateBush", "tile": Vector2i(7, 1), "rotation": 0},
	{"name": "DelicateBush", "tile": Vector2i(7, 7), "rotation": 0},
]
const DEFAULT_DOOR_TILE := Vector2i(0, 4)

@onready var floor_layer: Node2D = $Floor
@onready var wall_layer: Node2D = $Walls
@onready var item_layer: Node2D = $Items
@onready var hud: CanvasLayer = $Hud

var grid: RoomGrid
var items: Array[RoomItem] = []
var play: RestaurantPlay
var level := 1

var _sprites := SpriteLibrary.load_group("indoor")
var _game_sprites := SpriteLibrary.load_group("game")
var _floor_sprite: String
var _wallpaper_item: String
var _dish_sprites: Dictionary = {}
var _chair_overlays: Dictionary = {}


## A new player's restaurant, at the size its level allows (GameWorld.LEVEL_THRESHOLDS).
static func default_layout(at_level: int = 1) -> Dictionary:
	return {
		"size": Levels.room_size(at_level),
		"floor": "FloorTile",
		"wallpaper": "Neutral Blue",
		"items": DEFAULT_ITEMS,
		"door": DEFAULT_DOOR_TILE,
	}


func _ready() -> void:
	var points := int(Api.profile.get("gourmetPoints", 0)) if Api.is_signed_in() else 0
	level = Levels.level_for(points)
	build(default_layout(level))


func build(layout: Dictionary) -> void:
	grid = RoomGrid.new(layout["size"])
	_floor_sprite = layout["floor"]
	_wallpaper_item = layout["wallpaper"]
	_build_shell()
	_build_items(layout["items"])
	play = RestaurantPlay.new()
	play.name = "Play"
	add_child(play)
	play.start(self, layout["door"])
	_connect_hud()


func _process(_delta: float) -> void:
	_sync_dishes()
	_sync_chair_overlays()
	hud.set_demand(play.demand)


## Dragging with a mouse button held scrolls a restaurant that is bigger than the screen.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask != 0:
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


## WorldRestaurant.setRoomSize: a higher level gives a bigger floor. Furniture stays put.
func resize(new_size: Vector2i) -> void:
	if new_size == grid.size:
		return
	grid.resize(new_size)
	for layer: Node2D in [floor_layer, wall_layer]:
		for child in layer.get_children():
			child.free()
	_build_shell()


## Signed in, coins and progress are the server's; offline, they are this session's count.
func _connect_hud() -> void:
	hud.set_signed_in(Api.is_signed_in())
	hud.sign_out_pressed.connect(_sign_out)
	if not Api.is_signed_in():
		play.coins_changed.connect(hud.set_coins)
		play.dish_paid.connect(func() -> void: _on_progress(int(play.gourmet_points)))
		hud.set_coins(play.coins)
		_on_progress(0)
		return
	var sync := EarningsSync.new()
	sync.name = "EarningsSync"
	add_child(sync)
	sync.coins_changed.connect(hud.set_coins)
	sync.progress_changed.connect(_on_progress)
	sync.leveled_up.connect(func(new_level: int, reward: int) -> void:
		hud.show_message("Level %d! You earned %d coins." % [new_level, reward]))
	sync.start(play)


func _on_progress(gourmet_points: int) -> void:
	hud.set_gourmet_points(gourmet_points)
	var reached := Levels.level_for(gourmet_points)
	if reached <= level:
		return
	level = reached
	if not Api.is_signed_in():
		hud.show_message("Level %d!" % level)
	resize(Levels.room_size(level))


func _sign_out() -> void:
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


func _sprite_name_of(item_name: String) -> String:
	var sprite_name: String = GameData.interior_items.get_item(item_name).get("className", "")
	if sprite_name.is_empty():
		push_error("RestaurantRoom: item %s has no className" % item_name)
	return sprite_name


## Floor, walls, and wallpaper for the current size, with the floor centred on the stage.
func _build_shell() -> void:
	var size := grid.size
	position = FLOOR_CENTER_ON_SCREEN - RoomGrid.tile_to_screen(size) / 2.0
	for y in range(1, size.y):
		for x in range(1, size.x):
			_place(floor_layer, _floor_sprite, Vector2i(x, y), 0)
	# WorldRestaurant.addDefaultWalls and setWallPaper.
	var wall := _sprite_name_of(WALL_ITEM)
	var wallpaper := _sprite_name_of(_wallpaper_item)
	var segments: Array[Dictionary] = []
	for x in range(1, size.x):
		segments.append({"tile": Vector2i(x, 0), "rotation": NORTH_WALL_ROTATION})
	for y in range(1, size.y):
		segments.append({"tile": Vector2i(0, y), "rotation": WEST_WALL_ROTATION})
	for segment in segments:
		_place(wall_layer, wall, segment["tile"], segment["rotation"])
		_place(wall_layer, wallpaper, segment["tile"], segment["rotation"])
		grid.add_wall(segment["tile"])
	_place(wall_layer, _sprite_name_of(WALL_CORNER_ITEM), Vector2i.ZERO, 0)
	grid.add_wall(Vector2i.ZERO)


func _footprint(config: Dictionary, sprite_name: String, rotation: int) -> Vector2i:
	var footprint := RoomGrid.footprint_from_extent(_sprites.extent(sprite_name))
	# The data can overrule the size judged from the art (RoomItem's constructor).
	if config.get("sizeX") != null:
		footprint.x = int(config["sizeX"])
	if config.get("sizeY") != null:
		footprint.y = int(config["sizeY"])
	return RoomGrid.rotated_footprint(footprint, rotation)


func _build_items(entries: Array) -> void:
	for entry: Dictionary in entries:
		var sprite_name := _sprite_name_of(entry["name"])
		if sprite_name.is_empty():
			continue
		var turns: int = entry["rotation"]
		var sprite := _place(item_layer, sprite_name, entry["tile"], turns)
		if sprite == null:
			continue
		var item := RoomItem.new()
		item.item_name = entry["name"]
		item.config = GameData.interior_items.get_item(entry["name"])
		item.types = GameData.interior_items.get_item_types(entry["name"])
		item.tile = entry["tile"]
		# The shown frame wraps at the art's frame count, but the footprint turns every time:
		# the default stove is asked for 3 turns, shows frame 0, and still ends up 1 x 2.
		item.rotation = sprite.frame
		item.footprint = _footprint(item.config, sprite_name, turns)
		item.top_height = _sprites.item_height(sprite_name, RoomGrid.footprint_from_extent(_sprites.extent(sprite_name)).y)
		item.sprite = sprite
		sprite.z_index = RoomGrid.tile_draw_order(item.tile) * RoomActor.DRAW_ORDER_STEP
		grid.add_item(item.tile, item.footprint, item.has_type(DOOR_TYPE))
		items.append(item)


## Keeps one dish sprite on every table that has a served order, showing how much is eaten.
## The simulation only tracks the order; this draws it (DishOrder was an AnimatedObject).
func _sync_dishes() -> void:
	var on_tables := {}
	for table in items_of_type(TABLE_TYPE):
		var order := table.table_top_order
		if order == null or not order.served:
			continue
		on_tables[order] = true
		var dish: Sprite2D = _dish_sprites.get(order)
		if dish == null:
			var sprite_name: String = order.recipe.get("className", "")
			if not _game_sprites.has_sprite(sprite_name):
				continue
			dish = _game_sprites.make_sprite(sprite_name)
			dish.position = RoomGrid.tile_center(table.tile) - Vector2(0, table.top_height)
			dish.z_index = table.sprite.z_index + OVER_ACTOR
			item_layer.add_child(dish)
			_dish_sprites[order] = dish
		# The dish's timeline runs from a full plate to an empty one.
		dish.frame = roundi(order.eaten * (_game_sprites.frame_count(order.recipe.get("className", "")) - 1))
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
