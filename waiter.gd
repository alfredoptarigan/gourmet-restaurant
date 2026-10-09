class_name Waiter
extends RoomActor
## Carries cooked dishes to customers and clears empty plates. Port of Waitor.as.
##
## ponytail: staff never tire here, so delays are the original's best case (a happy
## waiter); port Waitor.getDelay and setWalkSpeed with staff energy.

enum State { IDLE, MOVING_TO_GET_ORDER, SERVING, MOVING_TO_GET_EMPTY_PLATE, MOVING_BACK, MOVING_TO_GET_DRINK }

## Waitor.ACTION_DELAY_MIN: the pause at the stove or table before moving on.
const ACTION_DELAY := 2.0
## Waitor.DRINK_MAKING_DELAY_MIN: how long making a drink takes at a plain dispenser.
const DRINK_MAKING_DELAY := 12.0
## Waitor.setInitialTilePosition: where a waiter may stand, relative to an unrotated kitchen.
const HOME_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(0, -1),
	Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 1),
]

var play: RestaurantPlay
var kitchen: RoomItem
var order: DishOrder
## The dispenser this waiter is making a drink at, or walking to.
var drink_item: RoomItem
var state: int = State.IDLE

var _home: Vector2i
var _timer := 0.0
var _at_work := false


func start(restaurant_play: RestaurantPlay, at_kitchen: RoomItem, taken_tiles: Array[Vector2i]) -> void:
	play = restaurant_play
	kitchen = at_kitchen
	_home = _pick_home(taken_tiles)
	place_on(_home)


func is_free() -> bool:
	return state == State.IDLE or state == State.MOVING_BACK


func get_order_from_kitchen(cooked: DishOrder) -> void:
	order = cooked
	_walk_next_to(cooked.kitchen.tile, State.MOVING_TO_GET_ORDER)


func get_empty_plate(plate: DishOrder) -> void:
	order = plate
	_walk_next_to(plate.table.tile, State.MOVING_TO_GET_EMPTY_PLATE)


## Waitor.getOrderFromDrinkItem: walk to the dispenser, make the drink there, then serve it.
func get_drink(ordered: DishOrder, dispenser: RoomItem, path: Array[Vector2i]) -> void:
	order = ordered
	drink_item = dispenser
	dispenser.waiter = self
	walk(path)
	_timer = dispenser.operate_time(DRINK_MAKING_DELAY)
	_at_work = false
	state = State.MOVING_TO_GET_DRINK
	ordered.customer.wait_for_food()


## The customer left: drop whatever this waiter was doing for that order.
func drop_order(dropped: DishOrder) -> void:
	if order == dropped:
		_move_back()


func tick(delta: float) -> void:
	super(delta)
	match state:
		State.MOVING_BACK:
			if not is_walking():
				avatar.play(Avatar.Animations.IDLE)
				state = State.IDLE
		State.MOVING_TO_GET_ORDER:
			if _worked_for(delta, order.kitchen.tile):
				_serve_customer()
		State.MOVING_TO_GET_DRINK:
			if _worked_for(delta, drink_item.tile):
				_serve_customer()
		State.MOVING_TO_GET_EMPTY_PLATE:
			if _worked_for(delta, order.table.tile):
				play.clear_empty_plate(order)
				_move_back()
		State.SERVING:
			if not is_walking():
				face_tile(order.table.tile)
				order.customer.eat_order()
				_move_back()


## Rotates a kitchen-relative offset by the kitchen's rotation (Waitor.rotateOffsets).
static func rotate_offset(offset: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 4):
		1:
			return Vector2i(-offset.y, offset.x)
		2:
			return -offset
		3:
			return Vector2i(offset.y, -offset.x)
	return offset


func _pick_home(taken_tiles: Array[Vector2i]) -> Vector2i:
	var fallback := kitchen.tile
	var found_fallback := false
	for offset in HOME_OFFSETS:
		var candidate := kitchen.tile + rotate_offset(offset, kitchen.rotation)
		if not play.room.grid.is_walkable(candidate):
			continue
		if candidate not in taken_tiles:
			return candidate
		if not found_fallback:
			fallback = candidate
			found_fallback = true
	return fallback


## Walks to the tile beside `target`, then counts down ACTION_DELAY there.
func _walk_next_to(target: Vector2i, next_state: int) -> void:
	var path := play.room.grid.find_path(tile, target)
	path.pop_back()
	walk(path)
	_timer = ACTION_DELAY
	_at_work = false
	state = next_state


## True once the waiter has arrived and spent ACTION_DELAY working at `target`.
func _worked_for(delta: float, target: Vector2i) -> bool:
	if is_walking():
		return false
	if not _at_work:
		_at_work = true
		face_tile(target)
		avatar.play(Avatar.Animations.WAITOR_WORKING)
	_timer -= delta
	return _timer <= 0.0


func _serve_customer() -> void:
	if order.kitchen != null:
		order.kitchen.ready_order = null
		order.kitchen = null
	_release_drink_item()
	var path := play.room.grid.find_path(tile, order.customer.chair.tile)
	path.pop_back()
	walk(path, Avatar.Animations.WAITOR_WALK)
	order.customer.wait_for_food()
	state = State.SERVING


func _release_drink_item() -> void:
	if drink_item != null:
		drink_item.waiter = null
		drink_item = null


func _move_back() -> void:
	order = null
	_release_drink_item()
	var path := play.room.grid.find_path(tile, _home)
	if path.is_empty():
		avatar.play(Avatar.Animations.IDLE)
		state = State.IDLE
		return
	walk(path)
	state = State.MOVING_BACK
