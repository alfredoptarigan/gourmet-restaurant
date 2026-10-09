class_name RestaurantRoom
extends Node2D
## A new player's restaurant, drawn from the original data and art. Static for now:
## one idle character, no editing, no walls beyond the wallpaper.

const TILE_WIDTH := 80
const TILE_HEIGHT := 40
## WorldRestaurant.MAX_NUM_TILES_X: draw order follows the tile index y * 20 + x.
const MAX_NUM_TILES_X := 20
## GameWorld.LEVEL_THRESHOLDS[0].
const ROOM_SIZE := Vector2i(8, 8)
const FLOOR_SPRITE := "FloorTile"
const WALLPAPER_ITEM := "Neutral Blue"
## Item rotation is the timeline frame: 0 faces the wall along x = 0, 1 the wall along y = 0.
const WEST_WALL_ROTATION := 0
const NORTH_WALL_ROTATION := 1

## WorldRestaurant.DEFAULT_RESTAURANT_ITEMS, minus the two wallpaper entries (see _build_wallpaper).
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

## GameUser.DEFAULT_MALE_AVATAR_ITEMS plus the free face pieces the original picks by user id.
const PLACEHOLDER_AVATAR_ITEMS: Array[Dictionary] = [
	{"name": "Classic", "group": "Hair"},
	{"name": "Blue Fish Shirt", "group": "Shirt"},
	{"name": "Classic Pants", "group": "Pants"},
	{"name": "Simple Eyes", "group": "Eyes"},
	{"name": "Happy Mouth", "group": "Mouth"},
	{"name": "Classic EyeBrow", "group": "Eyebrows"},
]
const PLACEHOLDER_AVATAR_TILE := Vector2i(4, 7)
const PLACEHOLDER_SKIN_COLOUR := Color("ffdbc0")
const PLACEHOLDER_HAIR_COLOUR := Color("5a3a22")

@onready var floor_layer: Node2D = $Floor
@onready var wall_layer: Node2D = $Walls
@onready var item_layer: Node2D = $Items

var _sprites := SpriteLibrary.load_group("indoor")


## WorldRestaurant.getScreenX / getScreenY: the top corner of the tile's diamond.
static func tile_to_screen(tile: Vector2i) -> Vector2:
	return Vector2((tile.x - tile.y) * TILE_WIDTH / 2.0, (tile.x + tile.y) * TILE_HEIGHT / 2.0)


## Where a character standing on the tile puts its feet: the middle of the diamond.
static func tile_center(tile: Vector2i) -> Vector2:
	return tile_to_screen(tile) + Vector2(0, TILE_HEIGHT / 2.0)


## WorldRestaurant.getTileIndex: items on a higher index are drawn in front.
static func tile_draw_order(tile: Vector2i) -> int:
	return tile.y * MAX_NUM_TILES_X + tile.x


func _ready() -> void:
	_build_floor()
	_build_wallpaper()
	_build_items()
	_build_avatar()


func _place(layer: Node2D, sprite_name: String, tile: Vector2i, frame: int) -> void:
	var sprite := _sprites.make_sprite(sprite_name, frame)
	if sprite == null:
		return
	sprite.position = tile_to_screen(tile)
	layer.add_child(sprite)


func _build_floor() -> void:
	for y in ROOM_SIZE.y:
		for x in ROOM_SIZE.x:
			_place(floor_layer, FLOOR_SPRITE, Vector2i(x, y), 0)


func _build_wallpaper() -> void:
	# ponytail: the original hangs wallpaper on per-tile wall items (WorldRestaurant.setWallPaper).
	# Wall items are not ported yet, so the wallpaper is drawn straight onto both back walls.
	var sprite_name: String = GameData.interior_items.get_item(WALLPAPER_ITEM).get("className", "")
	if sprite_name.is_empty():
		return
	# A wall piece on tile n covers the edge of tile n - 1, so pieces run from 1 to the room
	# size and tile (0, 0) stays empty, as in setWallPaper.
	for x in range(1, ROOM_SIZE.x + 1):
		_place(wall_layer, sprite_name, Vector2i(x, 0), NORTH_WALL_ROTATION)
	for y in range(1, ROOM_SIZE.y + 1):
		_place(wall_layer, sprite_name, Vector2i(0, y), WEST_WALL_ROTATION)


func _build_items() -> void:
	var ordered := DEFAULT_ITEMS.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return tile_draw_order(a["tile"]) < tile_draw_order(b["tile"]))
	for entry: Dictionary in ordered:
		var sprite_name: String = GameData.interior_items.get_item(entry["name"]).get("className", "")
		if sprite_name.is_empty():
			push_error("RestaurantRoom: item %s has no className" % entry["name"])
			continue
		_place(item_layer, sprite_name, entry["tile"], entry["rotation"])


func _build_avatar() -> void:
	# ponytail: a stand-in until actors exist. It is added last, so it draws over every item;
	# real actors must be sorted into the item order by tile.
	var avatar := Avatar.new()
	avatar.name = "Avatar"
	avatar.position = tile_center(PLACEHOLDER_AVATAR_TILE)
	item_layer.add_child(avatar)
	avatar.setup(PLACEHOLDER_AVATAR_ITEMS, PLACEHOLDER_SKIN_COLOUR, PLACEHOLDER_HAIR_COLOUR)
