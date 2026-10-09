class_name Chef
extends RoomActor
## Cooks orders at one kitchen appliance. Port of ChefActor.as.
##
## ponytail: staff never tire here, so the cook time is the original's best case (a happy
## chef). Port the happiness scale in ChefActor.getCookTime when staff energy exists.

enum State { IDLE, COOKING }

## ChefActor.COOK_DURATION_MIN.
const COOK_DURATION := 16.0

var play: RestaurantPlay
var kitchen: RoomItem
var cooking_order: DishOrder
var state: int = State.IDLE

var _timer := 0.0


## The chef stands on the tile the appliance faces, looking back at it.
func start(restaurant_play: RestaurantPlay, at_kitchen: RoomItem) -> void:
	play = restaurant_play
	kitchen = at_kitchen
	place_on(RoomGrid.facing_tile(kitchen.tile, kitchen.rotation))
	var away := RestaurantPlay.actor_direction_for(kitchen.rotation)
	avatar.set_direction((away + DIRECTION_COUNT / 2) % DIRECTION_COUNT)


## A cooked dish sitting on the stove blocks it until a waiter takes it (isStoveAvailable).
func is_free() -> bool:
	return state == State.IDLE and kitchen.ready_order == null


func cook(order: DishOrder) -> void:
	cooking_order = order
	order.kitchen = kitchen
	order.customer.wait_for_food()
	_timer = COOK_DURATION
	avatar.play(Avatar.Animations.COOKING)
	state = State.COOKING


func discard_order(order: DishOrder) -> void:
	if state == State.COOKING and cooking_order == order:
		cooking_order = null
		avatar.play(Avatar.Animations.IDLE)
		state = State.IDLE


func tick(delta: float) -> void:
	super(delta)
	if state != State.COOKING:
		return
	_timer -= delta
	if _timer <= 0.0:
		avatar.play(Avatar.Animations.IDLE)
		kitchen.ready_order = cooking_order
		play.completed_orders.append(cooking_order)
		cooking_order = null
		state = State.IDLE
