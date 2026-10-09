class_name RestaurantPlay
extends Node
## The running restaurant: lets customers in and hands their orders to the chef and the
## waiter. Port of the core of WorldRestaurantPlay.as.
##
## Runs itself every frame, or can be stepped by hand with tick() after set_process(false).

signal coins_changed(coins: int)
## A customer's meal was paid for (its plate was cleared).
signal dish_paid
## An arcade machine was paid for.
signal extra_paid
## Something happened that the original marks with a sound; the value is the sound's name.
signal sound_wanted(sound_name: String)

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
const TOILET_TYPE := "toilet"
const SINK_TYPE := "sink"
const INTERACTIVE_TYPE := "interactive"
## GameWorld.TOILET_START_LEVEL: customers start asking for a toilet at this level.
const TOILET_START_LEVEL := 8
## GameWorld.COINS_PAYOUT_FUNCTIONAL_ITEMS and GOURMET_POINTS_PER_FUNCTIONAL_ITEM_PAYOUT.
const COINS_PER_EXTRA := 1
const GOURMET_POINTS_PER_EXTRA := 1.0
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
## Customers on a chair with no table, waiting in turn for a chair that has one.
var waiting_chair_queue: Array[Customer] = []

var _door_tile: Vector2i
var _has_door := false
var _arrival_timer := 0.0


static func actor_direction_for(item_rotation: int) -> int:
	return ITEM_ROTATION_TO_ACTOR_DIRECTION[posmod(item_rotation, ITEM_ROTATION_TO_ACTOR_DIRECTION.size())]


## Opens the restaurant with as many staff as the level allows.
## ponytail: the original lets the player hire friends and give each a job. Until hiring
## exists the roles are dealt out by rule: one chef per kitchen appliance, as long as one
## employee is left to wait tables, and every other employee is a waiter.
func start(restaurant_room: RestaurantRoom, door: RoomItem, employee_limit: int = 2) -> void:
	room = restaurant_room
	_has_door = door != null
	if not _has_door:
		push_warning("RestaurantPlay: no door, so no customers can come in")
	else:
		_door_tile = door.tile
	_arrival_timer = _next_arrival_delay()
	var kitchens := room.items_of_type(KITCHEN_TYPE)
	if kitchens.is_empty():
		push_warning("RestaurantPlay: no kitchen, so nothing can be cooked")
		return
	var chef_count := clampi(employee_limit - 1, 1, kitchens.size())
	var taken_tiles: Array[Vector2i] = []
	for index in chef_count:
		var chef := Chef.new()
		_add_actor(chef, [CHEF_HAT])
		chef.start(self, kitchens[index])
		chefs.append(chef)
		taken_tiles.append(chef.tile)
	for index in maxi(1, employee_limit - chef_count):
		var waiter := Waiter.new()
		_add_actor(waiter, [])
		waiter.start(self, kitchens[index % kitchens.size()], taken_tiles)
		waiters.append(waiter)
		taken_tiles.append(waiter.tile)


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


## WorldRestaurantPlay.getEmptyChairs: chairs nobody sits on or walks to, optionally only
## those facing a table, or a table with nothing on it.
func empty_chairs(with_table: bool, with_free_table: bool) -> Array[RoomItem]:
	var chairs: Array[RoomItem] = []
	for chair in room.items_of_type(CHAIR_TYPE):
		if chair.occupant != null or chair.has_type(TOILET_TYPE):
			continue
		var table := room.table_for_chair(chair)
		if with_table and (table == null or (with_free_table and not is_table_free(table))):
			continue
		chairs.append(chair)
	return chairs


## Toilets, sinks, or arcade machines nobody is using, and that still work.
func empty_items(type: String) -> Array[RoomItem]:
	var free: Array[RoomItem] = []
	for item in room.items_of_type(type):
		if item.occupant == null and not item.is_broken():
			free.append(item)
	return free


## WorldRestaurant.getInteractiveItemUserTile: where a customer stands to play a machine.
static func interactive_user_tile(item: RoomItem) -> Vector2i:
	match posmod(item.rotation, 4):
		0:
			return item.tile + Vector2i(item.footprint.x, 0)
		1:
			return item.tile + Vector2i(0, item.footprint.y)
		2:
			return item.tile + Vector2i(-1, 0)
	return item.tile + Vector2i(0, -1)


## WorldRestaurantPlay.setRoomItemUsageCount: every use brings a breakable item closer to breaking.
func use_item(item: RoomItem) -> void:
	item.usage_count += 1


## WorldRestaurantPlay.fixBreakableItem.
func fix_item(item: RoomItem) -> void:
	item.usage_count = 0


## WorldRestaurantPlay.onCustomerPayForFunctional.
func pay_for_functional() -> void:
	_pay_extra()


func _pay_extra() -> void:
	coins += COINS_PER_EXTRA
	gourmet_points += GOURMET_POINTS_PER_EXTRA
	coins_changed.emit(coins)
	extra_paid.emit()
	sound_wanted.emit("SfxCash")


## WorldRestaurant.isTableFree.
func is_table_free(table: RoomItem) -> bool:
	return table.table_top_order == null


## A shuffled copy, drawn with this object's generator so a seeded run is repeatable.
func shuffled(things: Array) -> Array:
	var mixed := things.duplicate()
	for index in range(mixed.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swapped: Variant = mixed[index]
		mixed[index] = mixed[other]
		mixed[other] = swapped
	return mixed


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
	sound_wanted.emit("SfxCash")


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
	if _arrival_timer > 0.0 or not _has_door:
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
