class_name Customer
extends RoomActor
## A diner: comes in, takes a chair, orders, eats, pays, leaves. Port of Customer.as.
##
## Not ported yet: trash, toilets and sinks, drinks, arcade machines, and the outdoor area.

## Customer.EMOTION_*: the frame of the Emotions sprite shown over an unhappy customer.
enum Emotion { NONE = -1, NO_SEAT, DIRTY, WAIT_TOO_LONG, DECOR, NO_TABLE, NO_CLEAN_TABLE, NO_TOILET, WAIT_TOO_LONG_FOR_DRINK }

enum State { WAITING_TO_SIT, WALKING_TO_CHAIR, DECIDING, WAITING, WAITING_FOR_FOOD, EATING, PAYING, LEAVING, LEFT, NO_TABLE, NO_CLEAN_TABLE }

## Customer.as timers, in seconds.
const DECIDING_TIME := 1.0
const WAITING_FOR_CHAIR_TIME := 5.0
const WAITING_FOR_ORDER_TIME := 10.0
const WAITING_FOR_TABLE_TIME := 20.0
const WAITING_FOR_FOOD_TIME := 120.0
const EATING_TIME := 25.0
const PAYING_TIME := 2.0

var play: RestaurantPlay
var state: int = State.WAITING_TO_SIT
var chair: RoomItem
var order: DishOrder
var left_happy := false
var emotion: int = Emotion.NONE

var _timer := 0.0
var _door_tile: Vector2i


## ponytail: customers appear in the doorway. The original walks them in from the street,
## which does not exist here yet.
func enter(restaurant_play: RestaurantPlay, door_tile: Vector2i) -> void:
	play = restaurant_play
	_door_tile = door_tile
	place_on(door_tile)
	_timer = WAITING_FOR_CHAIR_TIME
	_walk_to_free_chair(not play.waiting_chair_queue.is_empty(), false)


func tick(delta: float) -> void:
	super(delta)
	match state:
		State.WAITING_TO_SIT:
			if _timer <= 0.0:
				leave_unhappy(Emotion.NO_SEAT)
			elif _walk_to_free_chair(not play.waiting_chair_queue.is_empty(), false):
				emotion = Emotion.NONE
			else:
				emotion = Emotion.NO_SEAT
		State.NO_TABLE:
			if _timer <= 0.0:
				leave_unhappy(Emotion.NO_TABLE)
			elif play.waiting_chair_queue.front() == self and _walk_to_free_chair(false, true):
				play.waiting_chair_queue.pop_front()
				emotion = Emotion.NONE
		State.NO_CLEAN_TABLE:
			var table := play.room.table_for_chair(chair)
			if _timer <= 0.0:
				leave_unhappy(Emotion.NO_CLEAN_TABLE)
			elif table != null and play.is_table_free(table):
				emotion = Emotion.NONE
				_place_order(table)
		State.WALKING_TO_CHAIR:
			if not is_walking():
				_sit()
		State.DECIDING:
			if _timer <= 0.0:
				_order()
		State.WAITING, State.WAITING_FOR_FOOD:
			if _timer <= 0.0:
				leave_unhappy(Emotion.WAIT_TOO_LONG)
		State.EATING:
			order.eaten = clampf(1.0 - _timer / EATING_TIME, 0.0, 1.0)
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


func is_seated() -> bool:
	return state in [State.DECIDING, State.WAITING, State.WAITING_FOR_FOOD, State.EATING, State.PAYING,
			State.NO_TABLE, State.NO_CLEAN_TABLE]


func eat_order() -> void:
	order.served = true
	avatar.play(Avatar.Animations.EAT)
	play.sound_wanted.emit("SfxEating")
	_timer = EATING_TIME
	state = State.EATING


func leave_happy() -> void:
	left_happy = true
	play.happy_customers += 1
	play.add_demand(RestaurantPlay.DEMAND_BONUS_HAPPY_CUSTOMER)
	_leave()


func leave_unhappy(why: int) -> void:
	emotion = why
	play.add_demand(RestaurantPlay.DEMAND_BONUS_UNHAPPY_CUSTOMER)
	_leave()


## Customer.walkToChair: gives up the current chair for this one.
func take_chair(new_chair: RoomItem) -> void:
	if chair != null:
		chair.occupant = null
	chair = new_chair
	chair.occupant = self
	state = State.WALKING_TO_CHAIR


## Customer.getPathToRandomValidEmptyChair: prefers a chair at a free table, then one at any
## table, then any chair at all. While others queue for a table, a newcomer skips the tables
## (`skip_tables`); the first in that queue takes nothing but a chair with a table (`tables_only`).
func _walk_to_free_chair(skip_tables: bool, tables_only: bool) -> bool:
	var choices: Array = []
	if not skip_tables:
		choices.append(play.empty_chairs(true, true))
		choices.append(play.empty_chairs(true, false))
	if not tables_only:
		choices.append(play.empty_chairs(false, false))
	for chairs: Array[RoomItem] in choices:
		for candidate in play.shuffled(chairs):
			var path := play.room.grid.find_path(tile, candidate.tile)
			if path.is_empty():
				continue
			take_chair(candidate)
			walk(path)
			return true
	return false


func _sit() -> void:
	avatar.set_direction(RestaurantPlay.actor_direction_for(chair.rotation))
	avatar.play(Avatar.Animations.SIT)
	_timer = DECIDING_TIME
	state = State.DECIDING


func _order() -> void:
	var table := play.room.table_for_chair(chair)
	if table == null:
		emotion = Emotion.NO_TABLE
		_timer = WAITING_FOR_TABLE_TIME
		state = State.NO_TABLE
		play.waiting_chair_queue.append(self)
	elif not play.is_table_free(table):
		emotion = Emotion.NO_CLEAN_TABLE
		_timer = WAITING_FOR_ORDER_TIME
		state = State.NO_CLEAN_TABLE
	else:
		_place_order(table)


func _place_order(table: RoomItem) -> void:
	order = play.create_order(self, table)
	_timer = WAITING_FOR_ORDER_TIME
	state = State.WAITING


func _finish_eating() -> void:
	avatar.play(Avatar.Animations.SIT)
	order.eaten = 1.0
	# The plate stays on the table, and is paid for, when a waiter clears it.
	play.empty_plates.append(order)
	order = null
	_timer = PAYING_TIME
	state = State.PAYING


func _leave() -> void:
	play.waiting_chair_queue.erase(self)
	if order != null:
		play.cancel_order(order)
		order = null
	if chair != null:
		chair.occupant = null
		chair = null
	walk(play.room.grid.find_path(tile, _door_tile))
	state = State.LEAVING
