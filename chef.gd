class_name Chef
extends RoomActor
## Cooks orders at one kitchen appliance. Port of ChefActor.as.
##
## A tired chef cooks more slowly, and one with no energy left does not cook at all.

enum State { IDLE, COOKING }

## ChefActor.COOK_DURATION_MIN and COOK_DURATION_MAX: rested and worn out.
const COOK_DURATION := 16.0
const COOK_DURATION_TIRED := 32.0

var play: RestaurantPlay
var kitchen: RoomItem
var cooking_order: DishOrder
var state: int = State.IDLE

var _timer := 0.0
var _worn_out := false


## The chef stands on the tile the appliance faces, looking back at it.
func start(restaurant_play: RestaurantPlay, at_kitchen: RoomItem) -> void:
	play = restaurant_play
	kitchen = at_kitchen
	place_on(RoomGrid.facing_tile(kitchen.tile, kitchen.rotation))
	var away := RestaurantPlay.actor_direction_for(kitchen.rotation)
	avatar.set_direction((away + DIRECTION_COUNT / 2) % DIRECTION_COUNT)


## A cooked dish sitting on the stove blocks it until a waiter takes it (isStoveAvailable).
func is_free() -> bool:
	return state == State.IDLE and kitchen.ready_order == null and play.has_energy(employee)


func cook(order: DishOrder) -> void:
	cooking_order = order
	order.kitchen = kitchen
	order.customer.wait_for_food()
	_timer = kitchen.operate_time(play.tired(employee, COOK_DURATION, COOK_DURATION_TIRED))
	avatar.play(Avatar.Animations.COOKING)
	play.sound_wanted.emit("SfxCooking")
	state = State.COOKING


func discard_order(order: DishOrder) -> void:
	if state == State.COOKING and cooking_order == order:
		cooking_order = null
		avatar.play(Avatar.Animations.IDLE)
		state = State.IDLE


func tick(delta: float) -> void:
	super(delta)
	if state != State.COOKING:
		if _worn_out == play.has_energy(employee):
			_worn_out = not _worn_out
			avatar.play(Avatar.Animations.DEAD if _worn_out else Avatar.Animations.IDLE)
		return
	_timer -= delta
	if _timer <= 0.0:
		avatar.play(Avatar.Animations.IDLE)
		kitchen.ready_order = cooking_order
		play.completed_orders.append(cooking_order)
		cooking_order = null
		state = State.IDLE
