class_name RoomActor
extends Node2D
## A character that walks the restaurant tile by tile. Ports the movement of
## RestaurantActor and AvatarActor. The node sits on the top corner of its tile, as the
## original actor did; the avatar's feet are half a tile lower, in the middle of the diamond.

signal arrived

## AvatarActor.DEFAULT_MOVE_SPEED_X / Y are 0.06 and 0.03 pixels per millisecond.
const MOVE_SPEED := Vector2(60.0, 30.0)
const DIRECTION_COUNT := 8
## Actors draw just in front of an item on the same tile.
const DRAW_ORDER_STEP := 2

var tile: Vector2i
var avatar := Avatar.new()

var _path: Array[Vector2i] = []
var _target: Vector2
var _moving := false


## AvatarActor.moveTo: the facing comes from the sign of the screen movement.
static func direction_for(movement: Vector2) -> int:
	var angle := atan2(signf(movement.y), signf(movement.x)) + PI / 2.0
	return posmod(roundi(angle / (TAU / DIRECTION_COUNT)), DIRECTION_COUNT)


func _init() -> void:
	avatar.position = Vector2(0, RoomGrid.TILE_HEIGHT / 2.0)
	add_child(avatar)


func place_on(new_tile: Vector2i) -> void:
	_path = []
	_moving = false
	position = RoomGrid.tile_to_screen(new_tile)
	_update_tile()


func is_walking() -> bool:
	return _moving or not _path.is_empty()


## Follows the tiles in order. An empty path is ignored.
func walk(path: Array[Vector2i]) -> void:
	if path.is_empty():
		return
	_path = path.duplicate()
	_moving = false
	avatar.play(Avatar.Animations.WALK)


func _process(delta: float) -> void:
	if not is_walking():
		return
	if not _moving:
		_target = RoomGrid.tile_to_screen(_path.pop_front())
		_moving = true
		if _target != position:
			avatar.set_direction(direction_for(_target - position))
	# Each axis moves at its own speed and stops on its own, as in RestaurantActor.tick.
	position = Vector2(
		move_toward(position.x, _target.x, MOVE_SPEED.x * delta),
		move_toward(position.y, _target.y, MOVE_SPEED.y * delta))
	_update_tile()
	if position == _target:
		_moving = false
		if _path.is_empty():
			avatar.play(Avatar.Animations.IDLE)
			arrived.emit()


func _update_tile() -> void:
	tile = RoomGrid.screen_to_tile(position + Vector2(0, RoomGrid.TILE_HEIGHT / 2.0))
	z_index = RoomGrid.tile_draw_order(tile) * DRAW_ORDER_STEP + 1
