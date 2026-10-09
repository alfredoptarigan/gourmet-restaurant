class_name RoomActor
extends Node2D
## A character that walks the restaurant tile by tile. Ports the movement of
## RestaurantActor and AvatarActor. The node sits on the top corner of its tile, as the
## original actor did; the avatar's feet are half a tile lower, in the middle of the diamond.
##
## Actors do not run on their own: whoever owns them calls tick(), so the simulation can be
## stepped without real time passing.

## AvatarActor.DEFAULT_MOVE_SPEED_X / Y are 0.06 and 0.03 pixels per millisecond.
const MOVE_SPEED := Vector2(60.0, 30.0)
const DIRECTION_COUNT := 8
## Draw order within one tile: the item, then an actor on it, then anything laid over the
## actor (a chair's backrest, a dish).
const DRAW_ORDER_STEP := 4

var tile: Vector2i
var avatar := Avatar.new()
## Staff: which employee this is (the index of their job and energy), and how fast they
## walk for how tired they are.
var employee := -1
var speed_scale := 1.0

var _path: Array[Vector2i] = []
var _target: Vector2
var _moving := false


## AvatarActor.moveTo and face. Directions run counter-clockwise on screen from 0 = toward
## the camera: 2 is right, 4 is away, 6 is left. `by_sign` reads only the sign of each axis,
## as moveTo does for a step; without it the true angle is used, as face does for a target.
static func direction_for(movement: Vector2, by_sign: bool = true) -> int:
	var heading := Vector2(signf(movement.x), signf(movement.y)) if by_sign else movement
	# Engine.getAngle measures with y pointing up, hence the flipped sign.
	var angle := atan2(-heading.y, heading.x) + PI / 2.0
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
func walk(path: Array[Vector2i], animation: int = Avatar.Animations.WALK) -> void:
	if path.is_empty():
		return
	_path = path.duplicate()
	_moving = false
	avatar.play(animation)


func face_tile(target: Vector2i) -> void:
	var toward := RoomGrid.tile_to_screen(target) - position
	if toward != Vector2.ZERO:
		avatar.set_direction(direction_for(toward, false))


func tick(delta: float) -> void:
	if not is_walking():
		return
	if not _moving:
		_target = RoomGrid.tile_to_screen(_path.pop_front())
		_moving = true
		if _target != position:
			avatar.set_direction(direction_for(_target - position))
	# Each axis moves at its own speed and stops on its own, as in RestaurantActor.tick.
	position = Vector2(
		move_toward(position.x, _target.x, MOVE_SPEED.x * speed_scale * delta),
		move_toward(position.y, _target.y, MOVE_SPEED.y * speed_scale * delta))
	_update_tile()
	if position == _target:
		_moving = false


func _update_tile() -> void:
	tile = RoomGrid.screen_to_tile(position + Vector2(0, RoomGrid.TILE_HEIGHT / 2.0))
	z_index = RoomGrid.tile_draw_order(tile) * DRAW_ORDER_STEP + 1
