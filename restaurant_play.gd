class_name RestaurantPlay
extends Node
## The running restaurant: lets customers in and hands their orders to the chef and the
## waiter. Port of the core of WorldRestaurantPlay.as.
##
## Runs itself every frame, or can be stepped by hand with tick() after set_process(false).

signal coins_changed(coins: int)
## A customer's meal was paid for (its plate was cleared).
signal dish_paid

## WorldRestaurantPlay and GameWorld constants.
const CUSTOMERS_PER_MINUTE_PER_DEMAND := 0.05
const DEFAULT_DEMAND := 120.0
const MIN_DEMAND := 40.0
const MAX_DEMAND := 550.0
const DEMAND_BONUS_HAPPY_CUSTOMER := 1.0
const DEMAND_BONUS_UNHAPPY_CUSTOMER := -1.0
## Customers arrive this many seconds early or late, at random.
const ARRIVAL_JITTER := 3.0
const GOURMET_POINTS_PER_DISH := 1.0
## WorldRestaurant.ITEM_ROTATION_TO_ACTOR_DIRECTION_MAP: the way an item at each rotation faces.
const ITEM_ROTATION_TO_ACTOR_DIRECTION: Array[int] = [1, 7, 5, 3]
## Recipe.MENU_RECIPE_TYPE_NAMES without drinks, which unlock at level 15.
const MENU_GROUPS: Array[String] = ["Starter", "Main", "Dessert"]

const CHAIR_TYPE := "chairItem"
const KITCHEN_TYPE := "kitchen"
const SKIN_COLOURS: Array[Color] = [Color("ffece9"), Color("ffdbc0"), Color("e8b98f"), Color("a8703f")]
const HAIR_COLOURS: Array[Color] = [Color("5a3a22"), Color("2b1b12"), Color("c9a25a"), Color("8a3b1f")]
const LOOK_GROUPS: Array[String] = ["Hair", "Shirt", "Pants", "Eyes", "Mouth"]
const CHEF_HAT := {"name": "Chef Hat", "group": "Hat"}

var room: RestaurantRoom
var rng := RandomNumberGenerator.new()
var coins := 0
var gourmet_points := 0.0
var demand := DEFAULT_DEMAND
var happy_customers := 0

var customers: Array[Customer] = []
var chefs: Array[Chef] = []
var waiters: Array[Waiter] = []
## Orders waiting for a chef, cooked dishes waiting for a waiter, plates waiting to be cleared.
var orders: Array[DishOrder] = []
var completed_orders: Array[DishOrder] = []
var empty_plates: Array[DishOrder] = []

var _door_tile: Vector2i
var _arrival_timer := 0.0


static func actor_direction_for(item_rotation: int) -> int:
	return ITEM_ROTATION_TO_ACTOR_DIRECTION[posmod(item_rotation, ITEM_ROTATION_TO_ACTOR_DIRECTION.size())]


## Staffs the first kitchen with one chef and one waiter and opens the door.
func start(restaurant_room: RestaurantRoom, door_tile: Vector2i) -> void:
	room = restaurant_room
	_door_tile = door_tile
	_arrival_timer = _next_arrival_delay()
	var kitchens := room.items_of_type(KITCHEN_TYPE)
	if kitchens.is_empty():
		push_warning("RestaurantPlay: no kitchen, so nothing can be cooked")
		return
	var chef := Chef.new()
	_add_actor(chef, [CHEF_HAT])
	chef.start(self, kitchens[0])
	chefs.append(chef)
	var waiter := Waiter.new()
	_add_actor(waiter, [])
	waiter.start(self, kitchens[0], [chef.tile])
	waiters.append(waiter)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	for chef in chefs:
		chef.tick(delta)
	for waiter in waiters:
		waiter.tick(delta)
	# A customer can remove itself from the list while ticking.
	for customer in customers.duplicate():
		customer.tick(delta)
	_let_customers_in(delta)
	_send_waiters_for_cooked_dishes()
	_send_waiters_for_empty_plates()
	_give_orders_to_chefs()


func free_chairs_in_random_order() -> Array[RoomItem]:
	var chairs: Array[RoomItem] = []
	for chair in room.items_of_type(CHAIR_TYPE):
		if chair.occupant == null:
			chairs.append(chair)
	# Shuffled with this object's generator so a seeded run is repeatable.
	for index in range(chairs.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swapped := chairs[index]
		chairs[index] = chairs[other]
		chairs[other] = swapped
	return chairs


## WorldRestaurantPlay.createOrderForCustomer and addOrderFromCustomer.
func create_order(customer: Customer, table: RoomItem) -> DishOrder:
	var recipes := GameData.recipe_items.get_items(MENU_GROUPS[rng.randi_range(0, MENU_GROUPS.size() - 1)])
	# ponytail: the first recipe of the course stands in for the player's chosen menu.
	var recipe: Dictionary = recipes[0] if not recipes.is_empty() else {}
	var order := DishOrder.new(recipe, customer, table)
	table.table_top_order = order
	orders.append(order)
	return order


## The customer walked out: forget the order wherever it had got to.
func cancel_order(order: DishOrder) -> void:
	orders.erase(order)
	completed_orders.erase(order)
	for chef in chefs:
		chef.discard_order(order)
	for waiter in waiters:
		waiter.drop_order(order)
	if order.kitchen != null and order.kitchen.ready_order == order:
		order.kitchen.ready_order = null
	if order.table.table_top_order == order:
		order.table.table_top_order = null


## WorldRestaurantPlay.clearEmptyPlate: this is the moment the meal is paid for.
func clear_empty_plate(order: DishOrder) -> void:
	order.table.table_top_order = null
	coins += order.cost()
	gourmet_points += GOURMET_POINTS_PER_DISH
	coins_changed.emit(coins)
	dish_paid.emit()


func add_demand(change: float) -> void:
	demand = clampf(demand + change, MIN_DEMAND, MAX_DEMAND)


func remove_customer(customer: Customer) -> void:
	customers.erase(customer)
	customer.queue_free()


func _next_arrival_delay() -> float:
	var per_minute := minf(demand, MAX_DEMAND) * CUSTOMERS_PER_MINUTE_PER_DEMAND
	return 60.0 / per_minute + rng.randf_range(-ARRIVAL_JITTER, ARRIVAL_JITTER)


func _let_customers_in(delta: float) -> void:
	_arrival_timer -= delta
	if _arrival_timer > 0.0:
		return
	_arrival_timer = _next_arrival_delay()
	var customer := Customer.new()
	_add_actor(customer, [])
	customers.append(customer)
	customer.enter(self, _door_tile)


func _add_actor(actor: RoomActor, extra_items: Array) -> void:
	room.item_layer.add_child(actor)
	actor.avatar.setup(_random_look() + extra_items, _pick(SKIN_COLOURS), _pick(HAIR_COLOURS))


func _pick(options: Array) -> Variant:
	return options[rng.randi_range(0, options.size() - 1)]


## One visible, wearable item from each clothing and face group.
func _random_look() -> Array:
	var look: Array = []
	for group_name in LOOK_GROUPS:
		var wearable := GameData.avatar_items.get_items(group_name).filter(
			func(item: Dictionary) -> bool: return item.get("invisible") != true)
		if not wearable.is_empty():
			look.append({"name": _pick(wearable)["name"], "group": group_name})
	return look


## The free waiter with the shortest walk to `target`, or null.
func _closest_free_waiter(target: Vector2i) -> Waiter:
	var closest: Waiter = null
	var shortest := -1
	for waiter in waiters:
		if not waiter.is_free():
			continue
		var steps := room.grid.find_path(waiter.tile, target).size()
		if steps == 0 and waiter.tile != target:
			continue
		if closest == null or steps < shortest:
			closest = waiter
			shortest = steps
	return closest


func _send_waiters_for_cooked_dishes() -> void:
	for order in completed_orders.duplicate():
		var waiter := _closest_free_waiter(order.kitchen.tile)
		if waiter != null:
			completed_orders.erase(order)
			waiter.get_order_from_kitchen(order)


func _send_waiters_for_empty_plates() -> void:
	for plate in empty_plates.duplicate():
		var waiter := _closest_free_waiter(plate.table.tile)
		if waiter != null:
			empty_plates.erase(plate)
			waiter.get_empty_plate(plate)


func _give_orders_to_chefs() -> void:
	for order in orders.duplicate():
		for chef in chefs:
			if chef.is_free():
				orders.erase(order)
				chef.cook(order)
				break
