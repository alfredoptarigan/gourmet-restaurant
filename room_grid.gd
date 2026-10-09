class_name RoomGrid
extends RefCounted
## The tile grid of a restaurant: projection, which tiles are occupied, and paths between
## them. Pure logic with no nodes, so it can be checked headless.
## Ports WorldRestaurant's itemMap/wallMap, isWalkable, isWalkableFrom, and PathFinder.

const TILE_WIDTH := 80
const TILE_HEIGHT := 40
## WorldRestaurant.MAX_NUM_TILES_X: the tile index is y * 20 + x.
const MAX_NUM_TILES_X := 20

var size: Vector2i

var _item_counts: Dictionary = {}
var _walls: Dictionary = {}
var _doors: Dictionary = {}
var _astar := AStarGrid2D.new()


## WorldRestaurant.getScreenX / getScreenY: the top corner of the tile's diamond.
static func tile_to_screen(tile: Vector2i) -> Vector2:
	return Vector2((tile.x - tile.y) * TILE_WIDTH / 2.0, (tile.x + tile.y) * TILE_HEIGHT / 2.0)


## Where a character standing on the tile puts its feet: the middle of the diamond.
static func tile_center(tile: Vector2i) -> Vector2:
	return tile_to_screen(tile) + Vector2(0, TILE_HEIGHT / 2.0)


## WorldRestaurant.getTileIndexX / getTileIndexY: the tile whose diamond holds the point.
static func screen_to_tile(point: Vector2) -> Vector2i:
	return Vector2i(
		floori((point.x + 2.0 * point.y) / TILE_WIDTH),
		floori((2.0 * point.y - point.x) / TILE_WIDTH))


## WorldRestaurant.getTileIndex: things on a higher index are drawn in front.
static func tile_draw_order(tile: Vector2i) -> int:
	return tile.y * MAX_NUM_TILES_X + tile.x


## WorldRestaurant.getFacingTile: the tile an item at this rotation looks at.
static func facing_tile(tile: Vector2i, rotation: int) -> Vector2i:
	const FACING_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	return tile + FACING_OFFSETS[posmod(rotation, FACING_OFFSETS.size())]


## RoomItem's constructor: how many tiles an item covers, judged from how far its art
## reaches right and down from the registration point (in original-game pixels).
static func footprint_from_extent(extent: Vector2) -> Vector2i:
	var tiles_x := maxi(1, roundi(extent.x / (TILE_WIDTH / 2.0)))
	var tiles_y := maxi(1, roundi(extent.y / (TILE_HEIGHT / 2.0)) - tiles_x)
	return Vector2i(tiles_x, tiles_y)


## RoomItem.rotate swaps the footprint on every step, whatever the art does.
static func rotated_footprint(footprint: Vector2i, rotation: int) -> Vector2i:
	return Vector2i(footprint.y, footprint.x) if rotation % 2 == 1 else footprint


func _init(room_size: Vector2i) -> void:
	size = room_size
	_astar.region = Rect2i(Vector2i.ZERO, size)
	# PathFinder: straight steps cost 10, diagonal 14, Manhattan estimate, and a diagonal
	# step needs both tiles beside it free (isWalkableFrom).
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()


func contains(tile: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, size).has_point(tile)


## WorldRestaurant.addToItemMap. A door only matters on a wall tile, where it opens the wall.
func add_item(tile: Vector2i, footprint: Vector2i = Vector2i.ONE, is_door: bool = false) -> void:
	for x in footprint.x:
		for y in footprint.y:
			var covered := tile + Vector2i(x, y)
			if not contains(covered):
				continue
			_item_counts[covered] = _item_counts.get(covered, 0) + 1
			if is_door:
				_doors[covered] = true
			_refresh(covered)


func add_wall(tile: Vector2i) -> void:
	if _walls.has(tile):
		return
	_walls[tile] = true
	add_item(tile)


## Grows the room. Everything already placed stays where it is.
func resize(new_size: Vector2i) -> void:
	size = new_size
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.update()
	for x in size.x:
		for y in size.y:
			_refresh(Vector2i(x, y))


## WorldRestaurant.isWalkable.
func is_walkable(tile: Vector2i) -> bool:
	if not contains(tile):
		return false
	if _walls.has(tile):
		return _doors.has(tile)
	return _item_counts.get(tile, 0) == 0


## The tiles to step through from `from` to `to`, without `from`. Empty if there is no way.
## Like PathFinder, the destination itself may be occupied: that is how an actor reaches a chair.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not contains(from) or not contains(to):
		return []
	var from_was_solid := _astar.is_point_solid(from)
	var to_was_solid := _astar.is_point_solid(to)
	_astar.set_point_solid(from, false)
	_astar.set_point_solid(to, false)
	var path := _astar.get_id_path(from, to)
	_astar.set_point_solid(from, from_was_solid)
	_astar.set_point_solid(to, to_was_solid)
	return path.slice(1)


func _refresh(tile: Vector2i) -> void:
	_astar.set_point_solid(tile, not is_walkable(tile))
