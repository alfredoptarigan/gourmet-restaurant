class_name RestaurantRoom
extends Node2D
## A restaurant drawn from the original data and art. One character walks to the tile you
## click. No customers, staff, or editing yet.
##
## The room size counts the wall tiles: row 0 and column 0 hold the walls, which stand on
## the inner edge of their tile, and the floor is everything from tile (1, 1) on
## (WorldRestaurant.addDefaultWalls, fillBaseArea).

const WALL_ITEM := "White Walls"
const WALL_CORNER_ITEM := "Wall Corner"
## Item rotation is the timeline frame: 0 is a wall along x = 0, 1 a wall along y = 0.
const WEST_WALL_ROTATION := 0
const NORTH_WALL_ROTATION := 1
const DOOR_TYPE := "doorItem"

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

## GameUser.DEFAULT_MALE_AVATAR_ITEMS plus the free face pieces the original picks by user id.
const PLACEHOLDER_AVATAR_ITEMS: Array[Dictionary] = [
	{"name": "Classic", "group": "Hair"},
	{"name": "Blue Fish Shirt", "group": "Shirt"},
	{"name": "Classic Pants", "group": "Pants"},
	{"name": "Simple Eyes", "group": "Eyes"},
	{"name": "Happy Mouth", "group": "Mouth"},
	{"name": "Classic EyeBrow", "group": "Eyebrows"},
]
const PLACEHOLDER_SKIN_COLOUR := Color("ffdbc0")
const PLACEHOLDER_HAIR_COLOUR := Color("5a3a22")

@onready var floor_layer: Node2D = $Floor
@onready var wall_layer: Node2D = $Walls
@onready var item_layer: Node2D = $Items

var grid: RoomGrid
var actor: RoomActor

var _sprites := SpriteLibrary.load_group("indoor")


## A new player's restaurant. GameWorld.LEVEL_THRESHOLDS[0] gives the 8 x 8 size.
static func default_layout() -> Dictionary:
	return {
		"size": Vector2i(8, 8),
		"floor": "FloorTile",
		"wallpaper": "Neutral Blue",
		"items": DEFAULT_ITEMS,
		"door": DEFAULT_DOOR_TILE,
	}


func _ready() -> void:
	build(default_layout())


func build(layout: Dictionary) -> void:
	grid = RoomGrid.new(layout["size"])
	_build_floor(layout["floor"])
	_build_walls(layout["wallpaper"])
	_build_items(layout["items"])
	_spawn_actor(layout["door"])


## Sends the character to a tile. False if the tile cannot be stood on or reached.
func walk_actor_to(tile: Vector2i) -> bool:
	if not grid.is_walkable(tile):
		return false
	var path := grid.find_path(actor.tile, tile)
	if path.is_empty():
		return false
	actor.walk(path)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		walk_actor_to(RoomGrid.screen_to_tile(get_local_mouse_position()))


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


func _build_floor(floor_sprite: String) -> void:
	for y in range(1, grid.size.y):
		for x in range(1, grid.size.x):
			_place(floor_layer, floor_sprite, Vector2i(x, y), 0)


## WorldRestaurant.addDefaultWalls and setWallPaper.
func _build_walls(wallpaper_item: String) -> void:
	var wall := _sprite_name_of(WALL_ITEM)
	var wallpaper := _sprite_name_of(wallpaper_item)
	var segments: Array[Dictionary] = []
	for x in range(1, grid.size.x):
		segments.append({"tile": Vector2i(x, 0), "rotation": NORTH_WALL_ROTATION})
	for y in range(1, grid.size.y):
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


func _build_items(items: Array) -> void:
	for entry: Dictionary in items:
		var sprite_name := _sprite_name_of(entry["name"])
		if sprite_name.is_empty():
			continue
		var tile: Vector2i = entry["tile"]
		var sprite := _place(item_layer, sprite_name, tile, entry["rotation"])
		if sprite == null:
			continue
		sprite.z_index = RoomGrid.tile_draw_order(tile) * RoomActor.DRAW_ORDER_STEP
		var config := GameData.interior_items.get_item(entry["name"])
		var is_door := DOOR_TYPE in GameData.interior_items.get_item_types(entry["name"])
		grid.add_item(tile, _footprint(config, sprite_name, entry["rotation"]), is_door)


func _spawn_actor(door_tile: Vector2i) -> void:
	actor = RoomActor.new()
	actor.name = "Actor"
	item_layer.add_child(actor)
	actor.place_on(door_tile)
	actor.avatar.setup(PLACEHOLDER_AVATAR_ITEMS, PLACEHOLDER_SKIN_COLOUR, PLACEHOLDER_HAIR_COLOUR)
