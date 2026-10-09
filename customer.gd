class_name Customer
extends RoomActor
## A diner: comes in, takes a chair, orders, eats, pays, leaves. Port of Customer.as.
##
## Not ported yet: trash, toilets and sinks, drinks, arcade machines, the outdoor area, and
## waiting for a table to free up (a customer with no usable table just leaves unhappy).

enum State { WAITING_TO_SIT, WALKING_TO_CHAIR, DECIDING, WAITING, WAITING_FOR_FOOD, EATING, PAYING, LEAVING, LEFT }

## Customer.as timers, in seconds.
const DECIDING_TIME := 1.0
const WAITING_FOR_CHAIR_TIME := 5.0
const WAITING_FOR_ORDER_TIME := 10.0
const WAITING_FOR_FOOD_TIME := 120.0
const EATING_TIME := 25.0
const PAYING_TIME := 2.0

var play: RestaurantPlay
var state: int = State.WAITING_TO_SIT
var chair: RoomItem
var order: DishOrder
var left_happy := false

var _timer := 0.0
var _door_tile: Vector2i


## ponytail: customers appear in the doorway. The original walks them in from the street,
## which does not exist here yet.
func enter(restaurant_play: RestaurantPlay, door_tile: Vector2i) -> void:
	play = restaurant_play
	_door_tile = door_tile
	place_on(door_tile)
	_timer = WAITING_FOR_CHAIR_TIME
	_walk_to_free_chair()


func tick(delta: float) -> void:
	super(delta)
	match state:
		State.WAITING_TO_SIT:
			if not _walk_to_free_chair() and _timer <= 0.0:
				leave_unhappy()
		State.WALKING_TO_CHAIR:
			if not is_walking():
				_sit()
		State.DECIDING:
			if _timer <= 0.0:
				_order()
		State.WAITING, State.WAITING_FOR_FOOD:
			if _timer <= 0.0:
				leave_unhappy()
		State.EATING:
			if _timer <= 0.0:
				_finish_eating()
		State.PAYING:
			if _timer <= 0.0:
				leave_happy()
		State.LEAVING:
			if not is_walking():
				state = State.LEFT
				play.remove_customer(self)
	_timer -= delta


## A chef or waiter has taken the order: the customer now waits much longer before giving up.
func wait_for_food() -> void:
	_timer = WAITING_FOR_FOOD_TIME
	state = State.WAITING_FOR_FOOD


func eat_order() -> void:
	avatar.play(Avatar.Animations.EAT)
	_timer = EATING_TIME
	state = State.EATING


func leave_happy() -> void:
	left_happy = true
	play.happy_customers += 1
	play.add_demand(RestaurantPlay.DEMAND_BONUS_HAPPY_CUSTOMER)
	_leave()


func leave_unhappy() -> void:
	play.add_demand(RestaurantPlay.DEMAND_BONUS_UNHAPPY_CUSTOMER)
	_leave()


func _walk_to_free_chair() -> bool:
	for candidate in play.free_chairs_in_random_order():
		var path := play.room.grid.find_path(tile, candidate.tile)
		if path.is_empty():
			continue
		chair = candidate
		chair.occupant = self
		walk(path)
		state = State.WALKING_TO_CHAIR
		return true
	return false


func _sit() -> void:
	avatar.set_direction(RestaurantPlay.actor_direction_for(chair.rotation))
	avatar.play(Avatar.Animations.SIT)
	_timer = DECIDING_TIME
	state = State.DECIDING


func _order() -> void:
	var table := play.room.table_for_chair(chair)
	if table == null or table.table_top_order != null:
		leave_unhappy()
		return
	order = play.create_order(self, table)
	_timer = WAITING_FOR_ORDER_TIME
	state = State.WAITING


func _finish_eating() -> void:
	avatar.play(Avatar.Animations.SIT)
	# The plate stays on the table, and is paid for, when a waiter clears it.
	play.empty_plates.append(order)
	order = null
	_timer = PAYING_TIME
	state = State.PAYING


func _leave() -> void:
	if order != null:
		play.cancel_order(order)
		order = null
	if chair != null:
		chair.occupant = null
		chair = null
	walk(play.room.grid.find_path(tile, _door_tile))
	state = State.LEAVING
