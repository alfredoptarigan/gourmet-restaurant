class_name RestaurantPlay
extends Node
## The running restaurant: lets customers in and hands their orders to the chef and the
## waiter. Port of the core of WorldRestaurantPlay.as.
##
## Runs itself every frame, or can be stepped by hand with tick() after set_process(false).

signal coins_changed(coins: int)
## A customer's meal was paid for (its plate was cleared).
signal dish_paid
## An arcade machine was paid for, or trash was picked up.
signal extra_paid
## Something happened that the original marks with a sound; the value is the sound's name.
signal sound_wanted(sound_name: String)

enum Job { CHEF, WAITER, CLEANER }

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
## Recipe.MENU_RECIPE_TYPE_NAMES. Drinks, the last course, unlock at GameWorld.DRINK_START_LEVEL.
const MENU_GROUPS: Array[String] = ["Starter", "Main", "Dessert", "Drink"]
const DRINK_GROUP := "Drink"
const DRINK_START_LEVEL := 15

## WorldRestaurantPlay.PEDESTRIAN_START_TILE_POSITION: where customers come into view, up
## or down the street outside the west wall.
const STREET_START_TILES: Array[Vector2i] = [Vector2i(-1, -20), Vector2i(-1, 35)]

const CHAIR_TYPE := "chairItem"
const DOOR_TYPE := "doorItem"
const KITCHEN_TYPE := "kitchen"
const TOILET_TYPE := "toilet"
const SINK_TYPE := "sink"
const INTERACTIVE_TYPE := "interactive"
const DRINK_TYPE := "drink"
## GameWorld.TOILET_START_LEVEL: customers start asking for a toilet at this level.
const TOILET_START_LEVEL := 8
## GameWorld.COINS_PAYOUT_FUNCTIONAL_ITEMS and GOURMET_POINTS_PER_FUNCTIONAL_ITEM_PAYOUT.
const COINS_PER_EXTRA := 1
## GameWorld.TRASH_APPEAR_RATE and its random delta, in seconds, and MAX_TRASH.
const TRASH_APPEAR_RATE := 3600.0
const TRASH_APPEAR_JITTER := 60.0
const MAX_TRASH := 15
## WorldRestaurantPlay.DEFAULT_TRASH_ITEMS.
const TRASH_SPRITES: Array[String] = ["BananaPeel", "PizzaSlice", "SodaCan", "ChickenLeg", "AppleCore"]
const GOURMET_POINTS_PER_EXTRA := 1.0
const SKIN_COLOURS: Array[Color] = [Color("ffece9"), Color("ffdbc0"), Color("e8b98f"), Color("a8703f")]
const SKIN_COLOUR_NAMES: Array[String] = ["Light", "Fair", "Tan", "Dark"]
const HAIR_COLOURS: Array[Color] = [Color("5a3a22"), Color("2b1b12"), Color("c9a25a"), Color("8a3b1f")]
const HAIR_COLOUR_NAMES: Array[String] = ["Brown", "Black", "Blonde", "Red"]
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
var cleaners: Array[Cleaner] = []
## Orders waiting for a chef, cooked dishes waiting for a waiter, plates waiting to be cleared.
var orders: Array[DishOrder] = []
var completed_orders: Array[DishOrder] = []
var empty_plates: Array[DishOrder] = []
## Customers on a chair with no table, waiting in turn for a chair that has one.
var waiting_chair_queue: Array[Customer] = []

var _arrival_timer := 0.0
## The job whose first employee is still to be dressed as the player, or -1.
var _player_job := -1


static func actor_direction_for(item_rotation: int) -> int:
	return ITEM_ROTATION_TO_ACTOR_DIRECTION[posmod(item_rotation, ITEM_ROTATION_TO_ACTOR_DIRECTION.size())]


## The courses customers order from at a level.
static func courses_for(level: int) -> Array[String]:
	return MENU_GROUPS.filter(func(course: String) -> bool: return course != DRINK_GROUP or level >= DRINK_START_LEVEL)


## The jobs dealt out when the player has not chosen: one chef per kitchen appliance, as long
## as one employee is left to wait tables, and every other employee is a waiter.
static func default_jobs(employee_limit: int, kitchen_count: int) -> Array[int]:
	var chef_count := clampi(employee_limit - 1, 1, maxi(1, kitchen_count))
	var jobs: Array[int] = []
	for index in maxi(2, employee_limit):
		jobs.append(Job.CHEF if index < chef_count else Job.WAITER)
	return jobs


## Opens the restaurant with one employee for every entry of `jobs` (a Job each).
## ponytail: a chef with no kitchen appliance of their own is left out. The original shows
## them idle with a "need a stove" bubble.
func start(restaurant_room: RestaurantRoom, jobs: Array[int]) -> void:
	room = restaurant_room
	if room.items_of_type(DOOR_TYPE).is_empty():
		push_warning("RestaurantPlay: no door, so no customers can come in")
	_arrival_timer = _next_arrival_delay()
	var kitchens := room.items_of_type(KITCHEN_TYPE)
	if kitchens.is_empty():
		push_warning("RestaurantPlay: no kitchen, so nothing can be cooked")
	# The first employee is the player, and wears the look the player chose.
	_player_job = jobs[0] if not jobs.is_empty() and not room.look.is_empty() else -1
	var taken_tiles: Array[Vector2i] = []
	for index in mini(jobs.count(Job.CHEF), kitchens.size()):
		var chef := Chef.new()
		_add_staff(chef, Job.CHEF, [CHEF_HAT])
		chef.start(self, kitchens[index])
		chefs.append(chef)
		taken_tiles.append(chef.tile)
	for index in (jobs.count(Job.WAITER) if not kitchens.is_empty() else 0):
		var waiter := Waiter.new()
		_add_staff(waiter, Job.WAITER, [])
		waiter.start(self, kitchens[index % kitchens.size()], taken_tiles)
		waiters.append(waiter)
		taken_tiles.append(waiter.tile)
	for index in jobs.count(Job.CLEANER):
		var cleaner := Cleaner.new()
		_add_staff(cleaner, Job.CLEANER, [])
		cleaner.start(self, taken_tiles)
		cleaners.append(cleaner)
		taken_tiles.append(cleaner.tile)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	for chef in chefs:
		chef.tick(delta)
	for waiter in waiters:
		waiter.tick(delta)
	for cleaner in cleaners:
		cleaner.tick(delta)
	# A customer can remove itself from the list while ticking.
	for customer in customers.duplicate():
		customer.tick(delta)
	_let_customers_in(delta)
	_send_waiters_for_cooked_dishes()
	_send_waiters_for_empty_plates()
	_send_waiters_for_drinks()
	_give_orders_to_chefs()
	_drop_trash(delta)


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


## WorldRestaurantPlay.onCustomerPayForFunctional and the payout of removeTrashObject.
func pay_extra() -> void:
	coins += COINS_PER_EXTRA
	gourmet_points += GOURMET_POINTS_PER_EXTRA
	coins_changed.emit(coins)
	extra_paid.emit()
	sound_wanted.emit("SfxCash")


## Floor tiles with nothing standing on them.
func free_floor_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in room.grid.bounds().y:
		for x in room.grid.bounds().x:
			var tile := Vector2i(x, y)
			if room.grid.is_walkable(tile) and not room.grid.is_wall(tile):
				tiles.append(tile)
	return tiles


## WorldRestaurantPlay.addRandomTrash: one more piece on a free floor tile.
func add_random_trash() -> void:
	var clean_tiles := free_floor_tiles().filter(func(tile: Vector2i) -> bool: return not room.trash.has(tile))
	if room.trash.size() < MAX_TRASH and not clean_tiles.is_empty():
		room.trash[_pick(clean_tiles)] = _pick(TRASH_SPRITES)


## WorldRestaurantPlay.removeTrashObject: picking trash up pays a little.
func remove_trash(tile: Vector2i) -> void:
	if room.trash.erase(tile):
		pay_extra()


func _drop_trash(delta: float) -> void:
	room.trash_timer -= delta
	if room.trash_timer <= 0.0:
		room.trash_timer = TRASH_APPEAR_RATE + rng.randf_range(-TRASH_APPEAR_JITTER, TRASH_APPEAR_JITTER)
		add_random_trash()


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


## WorldRestaurantPlay.createOrderForCustomer and addOrderFromCustomer. The course is drawn
## at random unless one is named.
## ponytail: the order is made up at the table. The original makes it up as the customer
## walks in and steers them to a chair staff can serve that kind of order at; here every
## chair is taken to be reachable.
func create_order(customer: Customer, table: RoomItem, course: String = "") -> DishOrder:
	if course.is_empty():
		course = _pick(courses_for(room.level))
	var order := DishOrder.new(room.recipe_for(course), customer, table)
	order.drink = course == DRINK_GROUP
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


## WorldRestaurantPlay.getValidDoors: the doors with a free tile inside them.
func entrances() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for door in room.items_of_type(DOOR_TYPE):
		if room.grid.is_walkable(RoomGrid.facing_tile(door.tile, door.rotation)):
			tiles.append(door.tile)
	return tiles


## WorldRestaurantPlay.getValidOutsideAreaEntrances: the outdoor area is entered from the
## street along its west edge, wherever the tile just inside is free.
func outside_entrances() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for row in room.grid.outside.y:
		var y := room.grid.size.y + row
		if room.grid.is_walkable(Vector2i(1, y)):
			tiles.append(Vector2i(0, y))
	return tiles


## ponytail: only customers walk the street. The original also sends passers-by along it.
func _let_customers_in(delta: float) -> void:
	_arrival_timer -= delta
	if _arrival_timer > 0.0:
		return
	_arrival_timer = _next_arrival_delay()
	var doors := entrances()
	var outside := outside_entrances()
	if doors.is_empty() and outside.is_empty():
		return
	# Half the customers use a door and half the outdoor area, when there are both.
	var through_door := not doors.is_empty() and (outside.is_empty() or rng.randi_range(0, 1) == 0)
	var customer := Customer.new()
	_add_actor(customer, [])
	customers.append(customer)
	customer.enter(self, _pick(doors if through_door else outside), _pick(STREET_START_TILES))


func _add_actor(actor: RoomActor, extra_items: Array) -> void:
	room.item_layer.add_child(actor)
	actor.avatar.setup(_random_look() + extra_items, _pick(SKIN_COLOURS), _pick(HAIR_COLOURS))


func _add_staff(actor: RoomActor, job: int, extra_items: Array) -> void:
	if job != _player_job:
		_add_actor(actor, extra_items)
		return
	_player_job = -1
	room.item_layer.add_child(actor)
	var worn: Array = []
	for group_name: String in room.look["items"]:
		worn.append({"name": room.look["items"][group_name], "group": group_name})
	actor.avatar.setup(worn + extra_items, SKIN_COLOURS[room.look["skin"]], HAIR_COLOURS[room.look["hair"]])


func _pick(options: Array) -> Variant:
	return options[rng.randi_range(0, options.size() - 1)]


## The items of a clothing or face group that can be seen and worn.
static func wearable(group_name: String) -> Array:
	return GameData.avatar_items.get_items(group_name).filter(
		func(item: Dictionary) -> bool: return item.get("invisible") != true)


## One wearable item from each clothing and face group.
func _random_look() -> Array:
	var look: Array = []
	for group_name in LOOK_GROUPS:
		var choices := wearable(group_name)
		if not choices.is_empty():
			look.append({"name": _pick(choices)["name"], "group": group_name})
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
		if order.drink:
			continue
		for chef in chefs:
			if chef.is_free():
				orders.erase(order)
				chef.cook(order)
				break


## WorldRestaurantPlay.getWaiterForDrinkOrder: the free waiter and free dispenser with the
## shortest walk between them make each drink.
func _send_waiters_for_drinks() -> void:
	for order in orders.duplicate():
		if not order.drink:
			continue
		var best_waiter: Waiter = null
		var best_dispenser: RoomItem = null
		var best_path: Array[Vector2i] = []
		for waiter in waiters:
			if not waiter.is_free():
				continue
			for dispenser in room.items_of_type(DRINK_TYPE):
				var stand := RoomGrid.facing_tile(dispenser.tile, dispenser.rotation)
				if dispenser.waiter != null or not room.grid.is_walkable(stand):
					continue
				var path := room.grid.find_path(waiter.tile, stand)
				if path.is_empty() and waiter.tile != stand:
					continue
				if best_waiter == null or path.size() < best_path.size():
					best_waiter = waiter
					best_dispenser = dispenser
					best_path = path
		if best_waiter != null:
			orders.erase(order)
			best_waiter.get_drink(order, best_dispenser, best_path)
