extends Node
## Run: tests/check_game.sh
## Checks the data pipeline, the FPS setting, and the restaurant room.
## It runs as a scene, not with -s, because scripts that name an autoload only compile
## inside the running project. The shell wrapper decides pass or fail: see its comment.

const SIMULATED_SECONDS := 300
const SIMULATION_STEP := 0.1
const BIND_TURN_TOLERANCE := 0.02
const BIND_OFFSET_TOLERANCE := 1.0

var failures: Array[String] = []


func _ready() -> void:
	# Run offline whatever session is saved on this machine; the token is not written back.
	Api.token = ""
	_check_data()
	_check_fps_setting()
	await _check_room()
	await _check_login_screen()
	for failure in failures:
		printerr("FAIL: " + failure)
	print("check_game: %s" % ("OK" if failures.is_empty() else "%d failed" % failures.size()))
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _check_data() -> void:
	var game_data := get_tree().root.get_node_or_null("GameData")
	_expect(game_data != null, "GameData autoload is missing")
	if game_data == null:
		return
	var recipes: ItemDatabase = game_data.recipe_items
	_expect(recipes.groups.size() == 4, "recipe.json should have 4 groups, got %d" % recipes.groups.size())
	_expect(recipes.get_items("Starter").size() > 0, "Starter group has no recipes")
	_expect(recipes.get_item("Garden Salad").get("cost") == "2", "Garden Salad should cost \"2\"")
	_expect(recipes.get_items("No Such Group").is_empty(), "unknown group should return no items")
	for database_name: String in ["building_items", "avatar_items", "interior_items", "perk_items",
			"ingredient_items", "quiz_items", "appointment_items"]:
		_expect(not game_data.get(database_name).groups.is_empty(), "%s is empty" % database_name)


func _check_fps_setting() -> void:
	var settings := get_tree().root.get_node_or_null("Settings")
	_expect(settings != null, "Settings autoload is missing")
	if settings == null:
		return
	var saved_fps: int = settings.fps
	_expect(settings.DEFAULT_FPS == 30, "default FPS should be 30")
	settings.set_fps(60)
	_expect(Engine.max_fps == 60, "set_fps(60) should cap the engine at 60")
	settings.set_fps(25)
	_expect(Engine.max_fps == 30, "an unsupported FPS should fall back to 30, got %d" % Engine.max_fps)
	settings.set_fps(saved_fps)


func _check_room() -> void:
	var sprites := SpriteLibrary.load_group("indoor")
	_expect(sprites.frame_count("Chair02") == 4, "Chair02 should have 4 rotation frames")
	var chair := sprites.make_sprite("Chair02", 5)
	_expect(chair != null and chair.frame == 1, "frame 5 of a 4-frame sprite should wrap to 1")
	if chair != null:
		chair.free()
	_check_grid()
	var room: RestaurantRoom = load("res://restaurant_room.tscn").instantiate()
	add_child(room)
	await get_tree().process_frame
	_expect(room.get_node("Floor").get_child_count() == 49, "an 8x8 room has a 7x7 floor inside its walls")
	_expect(room.get_node("Walls").get_child_count() == 29, "14 wall pieces, 14 wallpapers, and a corner")
	_expect(room.items.size() == 16, "every item of the starting layout should be placed, got %d" % room.items.size())
	_expect(room.to_layout() == RestaurantRoom.STARTER_LAYOUT, "a freshly built room should describe itself as the starting layout")
	_expect(not room.grid.is_walkable(Vector2i(3, 3)), "a table blocks its tile")
	_expect(not room.grid.is_walkable(Vector2i(0, 3)), "a wall blocks its tile")
	_expect(room.grid.is_walkable(Vector2i(0, 4)), "the door opens the wall tile it is on")
	_expect(room.grid.is_walkable(Vector2i(1, 4)), "the tile inside the door is free")
	_expect(not room.grid.is_walkable(Vector2i(6, 3)), "the rotated stove covers the tile below it")
	var seat := room.item_at(Vector2i(2, 3))
	_expect(seat != null and seat.has_type("chairItem"), "the item on (2, 3) is a chair")
	_expect(seat != null and room.table_for_chair(seat) == room.item_at(Vector2i(3, 3)), "that chair faces the table on (3, 3)")
	_expect(room.item_at(Vector2i(6, 3)) == room.item_at(Vector2i(6, 2)), "the stove also covers (6, 3)")
	_expect(room.item_at(Vector2i(4, 4)) == null, "an empty tile has no item")
	var path := room.grid.find_path(Vector2i(0, 4), Vector2i(4, 4))
	_expect(not path.is_empty() and path.all(func(step: Vector2i) -> bool: return room.grid.is_walkable(step)),
			"the path to (4, 4) should only cross free tiles, got %s" % [path])
	_expect(room.get_node_or_null("EarningsSync") == null, "offline, the room should not sync earnings")
	_expect(room.hud.coins_label.text == "Coins: 0", "offline, the label starts at this session's 0 coins")
	_expect(room.hud.level_label.text == "Level 1", "a new restaurant is level 1")
	var sync := EarningsSync.new()
	sync.add_dish()
	sync.add_dish()
	_expect(sync.shown_coins() == 4, "two unconfirmed dishes should show as 4 coins, got %d" % sync.shown_coins())
	_expect(sync.shown_points() == 2, "two unconfirmed dishes should show as 2 gourmet points")
	sync.add_extra()
	_expect(sync.shown_coins() == 5 and sync.shown_points() == 3, "an arcade play should show as 1 coin and 1 gourmet point")
	sync.free()
	var sounds_wanted := {}
	room.play.sound_wanted.connect(func(sound_name: String) -> void: sounds_wanted[sound_name] = true)
	_check_avatar(room.play.waiters[0].avatar)
	_check_simulation(room)
	for sound_name: String in ["SfxCooking", "SfxEating", "SfxCash"]:
		_expect(sounds_wanted.has(sound_name), "the simulation should ask for %s" % sound_name)
		_expect(Sounds.has_sound(sound_name), "%s should have been extracted" % sound_name)
	_expect(Sounds.has_sound("MusicRestaurant") and not Sounds.has_sound("NoSuchSound"), "sounds are found by class name")
	Sounds.play("NoSuchSound")
	_check_staffing(room)
	_check_waiting_for_a_table(room)
	_check_functional_items(room)
	_check_trash_and_cleaner(room)
	_check_menu_and_staff_choices(room)
	await _check_editor(room)
	room.queue_free()


func _check_simulation(room: RestaurantRoom) -> void:
	var play := room.play
	play.set_process(false)
	play.rng.seed = 7
	_expect(play.chefs.size() == 1 and play.chefs[0].tile == Vector2i(7, 2), "the chef stands on the mat in front of the stove")
	_expect(play.waiters.size() == 1 and play.waiters[0].tile == Vector2i(5, 2), "the waiter waits beside the stove")
	_expect(play.chefs[0].avatar.direction == 5, "the chef faces the stove")
	var states_seen := {}
	var most_dishes := 0
	var most_overlays := 0
	var saw_empty_plate := false
	var saw_emotion := false
	var seconds := 0.0
	while seconds < SIMULATED_SECONDS:
		play.tick(SIMULATION_STEP)
		seconds += SIMULATION_STEP
		# No frames pass in this loop, so draw the room's state by hand to check the view too.
		room._process(0.0)
		most_dishes = maxi(most_dishes, room._dish_sprites.size())
		most_overlays = maxi(most_overlays, room._chair_overlays.size())
		for order: DishOrder in room._dish_sprites:
			var last_frame: int = room._game_sprites.frame_count(order.recipe["className"]) - 1
			if room._dish_sprites[order].frame == last_frame:
				saw_empty_plate = true
		for customer in play.customers:
			if customer.emotion != Customer.Emotion.NONE and customer.has_node("Emotion"):
				saw_emotion = true
			states_seen[customer.state] = true
			if customer.state == Customer.State.DECIDING:
				_expect(customer.tile == customer.chair.tile, "a seated customer should be on its chair's tile")
	for state: int in [Customer.State.WALKING_TO_CHAIR, Customer.State.WAITING_FOR_FOOD, Customer.State.EATING, Customer.State.PAYING, Customer.State.LEAVING]:
		_expect(states_seen.has(state), "some customer should reach state %s" % Customer.State.keys()[state])
	_expect(play.happy_customers > 0, "at least one customer should leave happy in %d simulated seconds" % SIMULATED_SECONDS)
	_expect(play.coins > 0 and play.coins == int(play.gourmet_points) * 2, "each cleared plate should pay its recipe's 2 coins, got %d coins for %d dishes" % [play.coins, int(play.gourmet_points)])
	_expect(play.customers.size() <= room.items_of_type("chairItem").size() + 2, "customers should not pile up, got %d" % play.customers.size())
	_expect(saw_emotion, "a customer who gives up should leave with an emotion bubble")
	_expect(most_dishes > 0, "a served dish should be drawn on its table")
	_expect(saw_empty_plate, "a dish should end on its last frame, the empty plate")
	_expect(most_overlays > 0, "a seated customer should get the chair's backrest drawn over them")
	_expect(room.hud.level_label.text == "Level 1" and room.hud.level_bar.value > 0.0, "serving dishes should fill the level bar")
	room.resize(Levels.room_size(4))
	_expect(room.grid.size == Vector2i(9, 8) and room.get_node("Floor").get_child_count() == 56, "level 4 has a 9 x 8 room with an 8 x 7 floor")
	_expect(room.grid.is_walkable(Vector2i(8, 4)) and not room.grid.is_walkable(Vector2i(3, 3)), "the new floor is walkable and the furniture still blocks")
	_expect(room.grid.is_walkable(Vector2i(0, 4)), "the door still opens its wall after resizing")
	_expect(play.demand != RestaurantPlay.DEFAULT_DEMAND, "leaving customers should move the demand")


func _check_grid() -> void:
	_expect(Levels.count() == 66 and Levels.level_for(0) == 1 and Levels.level_for(50) == 2 and Levels.level_for(99) == 3, "levels follow the gourmet point thresholds")
	_expect(Levels.room_size(1) == Vector2i(8, 8) and Levels.room_size(4) == Vector2i(9, 8), "levels set the room size")
	_expect(is_equal_approx(Levels.progress(25), 0.5) and Levels.progress(99999999) == 1.0, "progress runs from one threshold to the next")
	_expect(RoomGrid.tile_to_screen(Vector2i(3, 1)) == Vector2(80, 80), "tile (3, 1) should be at (80, 80)")
	_expect(RoomGrid.tile_center(Vector2i(0, 0)) == Vector2(0, 20), "a tile's centre is half a tile down")
	_expect(RoomGrid.tile_draw_order(Vector2i(2, 1)) == 22, "tile (2, 1) should draw at index 22")
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(0, 5), Vector2i(7, 7)]:
		_expect(RoomGrid.screen_to_tile(RoomGrid.tile_center(tile)) == tile, "the centre of %s should map back to it" % tile)
	_expect(RoomGrid.footprint_from_extent(Vector2(80, 60)) == Vector2i(2, 1), "the stove's art covers 2x1 tiles")
	_expect(RoomGrid.footprint_from_extent(Vector2(19.5, 30.4)) == Vector2i(1, 1), "a chair covers one tile")
	_expect(RoomGrid.rotated_footprint(Vector2i(2, 1), 3) == Vector2i(1, 2), "an odd rotation swaps the footprint")
	_expect(RoomActor.direction_for(Vector2(0, 20)) == 0, "moving down the screen faces the camera: direction 0")
	_expect(RoomActor.direction_for(Vector2(40, 20)) == 1, "a step along +x (right and down) is direction 1")
	_expect(RoomActor.direction_for(Vector2(-40, 20)) == 7, "a step along +y (left and down) is direction 7")
	_expect(RoomActor.direction_for(Vector2(0, -20)) == 4, "moving up the screen is direction 4")
	_expect(RoomActor.direction_for(Vector2(80, 5), false) == 2, "facing a point to the right is direction 2")
	_expect(RoomGrid.facing_tile(Vector2i(2, 3), 0) == Vector2i(3, 3), "rotation 0 faces +x")
	_expect(RoomGrid.facing_tile(Vector2i(2, 3), 3) == Vector2i(2, 2), "rotation 3 faces -y")
	_expect(RestaurantPlay.actor_direction_for(0) == 1 and RestaurantPlay.actor_direction_for(1) == 7, "item rotations map to the directions they face")
	_expect(Waiter.rotate_offset(Vector2i(-1, 0), 1) == Vector2i(0, -1), "a quarter turn rotates a home offset")

	var grid := RoomGrid.new(Vector2i(4, 4))
	grid.add_item(Vector2i(1, 0), Vector2i(1, 3))
	_expect(not grid.is_walkable(Vector2i(1, 2)), "an item blocks every tile of its footprint")
	_expect(not grid.is_walkable(Vector2i(4, 0)), "a tile outside the room is not walkable")
	var around := grid.find_path(Vector2i(0, 0), Vector2i(2, 0))
	_expect(around.size() == 8 and around.back() == Vector2i(2, 0),
			"the path should go around the barrier without cutting its corner, got %s" % [around])
	_expect(grid.find_path(Vector2i(0, 0), Vector2i(1, 1)) == [Vector2i(0, 1), Vector2i(1, 1)],
			"a blocked destination is still reachable, without cutting the corner")
	grid.add_item(Vector2i(1, 3))
	_expect(grid.find_path(Vector2i(0, 0), Vector2i(3, 0)).is_empty(), "a sealed-off tile has no path")


func _check_avatar(avatar: Avatar) -> void:
	_expect(avatar != null, "the actor should have an avatar")
	if avatar == null:
		return
	var hidden := avatar.find_child("hat01", true, false) as Node3D
	var shown := avatar.find_child("shirt01", true, false) as Node3D
	_expect(hidden != null and not hidden.visible, "a hat the avatar does not wear should be hidden")
	_expect(shown != null and shown.visible, "the shirt the avatar wears should be visible")
	# Without a skin the mesh ignores the skeleton and every animation frame looks the same.
	var shirt := shown as MeshInstance3D
	_expect(shirt != null and shirt.skin != null and not shirt.skeleton.is_empty(),
			"the shirt mesh should be bound to the skeleton")
	var skeleton := avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if shirt != null and shirt.skin != null and skeleton != null:
		var spine := skeleton.find_bone("Bip01_Spine")
		var at_rest := skeleton.get_bone_global_rest(spine) * shirt.skin.get_bind_pose(spine)
		# The model's rest pose and bind pose were exported a hair apart (under half a unit on a
		# 170-unit character), so this allows for that. A wrong axis or scale is off by far more.
		var turned := at_rest.basis.x.distance_to(Vector3.RIGHT) + at_rest.basis.y.distance_to(Vector3.UP)
		_expect(turned < BIND_TURN_TOLERANCE and at_rest.origin.length() < BIND_OFFSET_TOLERANCE,
				"a bone at rest times its bind pose should leave the mesh where it is, got %s" % at_rest)
	var facing := avatar.direction
	avatar.set_direction(9)
	_expect(avatar.direction == 1, "direction 9 should wrap to 1")
	avatar.set_direction(facing)
	avatar.play(Avatar.Animations.WAITOR_WALK)
	var tray := avatar.find_child("tray", true, false) as Node3D
	_expect(tray != null and tray.visible, "the tray should show while a waiter walks")
	avatar.play(Avatar.Animations.IDLE)
	_expect(tray != null and not tray.visible, "the tray should hide when idle")
	var order: Array[Dictionary] = [{"priority": 2, "id": "a"}, {"priority": 0, "id": "b"}, {"priority": 2, "id": "c"}]
	var sorted := Avatar.sort_by_priority(order).map(func(entry: Dictionary) -> String: return entry["id"])
	_expect(sorted == ["b", "c", "a"], "texture pieces sort by priority, later equals first, got %s" % [sorted])


func _check_login_screen() -> void:
	var screen: Control = load("res://login.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	var message := screen.get_node("%Message") as Label
	var login_button := screen.get_node("%Login") as Button
	_expect(message != null and login_button != null and not login_button.disabled, "signed out, the login form should be ready to use")
	login_button.pressed.emit()
	await get_tree().process_frame
	_expect(message != null and message.text == "Enter a username and a password.", "an empty form should ask for both fields, got '%s'" % (message.text if message else ""))
	screen.queue_free()


func _check_staffing(room: RestaurantRoom) -> void:
	const STOVE := 3070000
	room.stop_play()
	room.place_item(STOVE, Vector2i(4, 1), 3)
	room.level = 4   # three employees
	room.start_play()
	_expect(room.play.chefs.size() == 2 and room.play.waiters.size() == 1, "three employees and two stoves make two chefs and a waiter, got %d and %d" % [room.play.chefs.size(), room.play.waiters.size()])
	var tiles := {}
	for actor: RoomActor in room.play.chefs + room.play.waiters:
		tiles[actor.tile] = true
	_expect(tiles.size() == 3, "staff should each stand on their own tile")
	room.stop_play()
	room.remove_item(room.item_at(Vector2i(4, 1)))
	room.level = 1
	room.start_play()
	_expect(room.play.chefs.size() == 1 and room.play.waiters.size() == 1, "level 1 has one chef and one waiter")


## Ticks the customer in small steps until it reaches `state`, for at most `seconds`.
func _tick_until(customer: Customer, state: int, seconds: float = 60.0) -> bool:
	var waited := 0.0
	while customer.state != state and waited < seconds:
		customer.tick(SIMULATION_STEP)
		waited += SIMULATION_STEP
	return customer.state == state


func _check_functional_items(room: RestaurantRoom) -> void:
	const TOILET := 3500021
	const SINK := 3020053
	const ARCADE := 3020043
	room.stop_play()
	var toilet := room.place_item(TOILET, Vector2i(5, 7), 0)
	var sink := room.place_item(SINK, Vector2i(3, 1), 0)
	var arcade := room.place_item(ARCADE, Vector2i(2, 7), 0)
	room.level = RestaurantPlay.TOILET_START_LEVEL
	room.start_play()
	var play := room.play
	play.set_process(false)
	_expect(toilet not in play.empty_chairs(false, false), "a toilet is not a seat to eat on")

	var visitor := _seated_customer(room, room.item_at(Vector2i(2, 3)))
	visitor.go_to_toilet()
	_expect(_tick_until(visitor, Customer.State.ON_TOILET) and visitor.chair == toilet and visitor.is_seated(), "a customer should walk to the toilet and sit on it")
	_expect(_tick_until(visitor, Customer.State.WALKING_TO_SINK, Customer.TOILET_TIME + 1.0) and toilet.usage_count == 1 and toilet.occupant == null,
			"after the toilet the customer should head for the sink, having used the toilet once")
	_expect(_tick_until(visitor, Customer.State.USING_SINK) and sink.occupant == visitor, "the customer should wash at the sink")
	_expect(_tick_until(visitor, Customer.State.LEAVING, Customer.SINK_TIME + 1.0) and visitor.left_happy and sink.occupant == null, "and then leave happy")

	toilet.usage_count = int(toilet.config["breakCount"])
	room._process(0.0)
	_expect(toilet.is_broken() and room._broken_marks.has(toilet), "a toilet used %s times is broken and marked" % toilet.config["breakCount"])
	var unlucky := _seated_customer(room, room.item_at(Vector2i(2, 5)))
	unlucky.go_to_toilet()
	_expect(unlucky.state == Customer.State.LEAVING and unlucky.emotion == Customer.Emotion.NO_TOILET, "with the only toilet broken a customer leaves complaining")
	room.click_tile(toilet.tile)
	room._process(0.0)
	_expect(not toilet.is_broken() and room._broken_marks.is_empty(), "clicking the broken toilet repairs it")

	var coins_before := play.coins
	var points_before := play.gourmet_points
	var player := _new_customer(room)
	_expect(player.walk_to_arcade() and arcade.occupant == player, "a customer can head for a free arcade machine")
	_expect(_tick_until(player, Customer.State.PLAYING) and player.tile == Vector2i(3, 7), "and plays it from the tile in front")
	_expect(_tick_until(player, Customer.State.LEAVING, Customer.PLAYING_TIME + 1.0), "then leaves")
	_expect(play.coins == coins_before + 1 and play.gourmet_points == points_before + 1.0 and arcade.usage_count == 1 and arcade.occupant == null,
			"a play pays 1 coin and 1 gourmet point and wears the machine")

	room.stop_play()
	for item: RoomItem in [toilet, sink, arcade]:
		room.remove_item(item)
	room.level = 1
	room.start_play()


func _check_trash_and_cleaner(room: RestaurantRoom) -> void:
	const TOILET := 3500021
	room.stop_play()
	var toilet := room.place_item(TOILET, Vector2i(5, 7), 0)
	room.level = 4   # three employees
	room.jobs = [RestaurantPlay.Job.CHEF, RestaurantPlay.Job.WAITER, RestaurantPlay.Job.CLEANER]
	room.start_play()
	var play := room.play
	play.set_process(false)
	play.rng.seed = 11
	_expect(play.chefs.size() == 1 and play.waiters.size() == 1 and play.cleaners.size() == 1, "the chosen jobs decide the staff")
	if play.cleaners.is_empty():
		return
	var cleaner := play.cleaners[0]
	_expect(cleaner.tile == Vector2i(6, 7), "a cleaner starts in front of the toilet, got %s" % cleaner.tile)

	play.add_random_trash()
	room._process(0.0)
	_expect(room.trash.size() == 1 and room._trash_sprites.size() == 1 and room.grid.is_walkable(room.trash.keys()[0]), "trash lands on a free floor tile and is drawn")
	var coins_before := play.coins
	toilet.usage_count = int(toilet.config["breakCount"])
	var seconds := 0.0
	while seconds < 120.0 and (toilet.is_broken() or not room.trash.is_empty()):
		cleaner.tick(SIMULATION_STEP)
		seconds += SIMULATION_STEP
	_expect(not toilet.is_broken() and toilet.cleaner == null, "the cleaner should repair the broken toilet")
	_expect(room.trash.is_empty() and play.coins == coins_before + 1, "the cleaner should pick the trash up, which pays 1 coin")

	room.trash[Vector2i(4, 4)] = "SodaCan"
	room.click_tile(Vector2i(4, 4))
	_expect(room.trash.is_empty() and play.coins == coins_before + 2, "clicking trash picks it up")
	room.trash_timer = 0.05
	play.tick(SIMULATION_STEP)
	_expect(room.trash.size() == 1 and room.trash_timer > 3000.0, "trash appears when its timer runs out, about once an hour")

	for index in Customer.TRASH_ODDS:
		room.trash[Vector2i(100 + index, 100)] = "SodaCan"
	var disgusted := _new_customer(room)
	_expect(disgusted.state == Customer.State.TOO_MUCH_TRASH and disgusted.emotion == Customer.Emotion.DIRTY, "a filthy restaurant turns customers away at the door")
	_expect(_tick_until(disgusted, Customer.State.LEAVING, Customer.TOO_MUCH_TRASH_TIME + 1.0), "and they leave")

	room.stop_play()
	room.trash.clear()
	room.remove_item(toilet)
	room.jobs = []
	room.level = 1
	room.start_play()
	_expect(room.play.cleaners.is_empty(), "the default jobs have no cleaner")


func _check_menu_and_staff_choices(room: RestaurantRoom) -> void:
	_expect(RestaurantRoom.valid_jobs([0.0, 2.0, 1.0]) == [0, 2, 1], "saved jobs arrive from JSON as numbers")
	_expect(RestaurantRoom.valid_jobs([0.0, 7.0]).is_empty() and RestaurantRoom.valid_jobs("chef").is_empty(), "jobs the game does not know are ignored")
	_expect(RestaurantRoom.valid_menu({"Starter": 5000008.0, "Main": 5000008.0, "Dessert": "cake"}) == {"Starter": 5000008},
			"a saved menu keeps only recipes that belong to their course")
	room.jobs = [2, 2, 2, 2, 2, 2]
	_expect(room.staff_jobs() == [2, 2], "level 1 has two employees however many jobs were saved")
	room.jobs = []

	var staff_panel := room.choose_staff()
	staff_panel.select(0, RestaurantPlay.Job.CLEANER)
	staff_panel.finish()
	_expect(room.jobs == [RestaurantPlay.Job.CLEANER, RestaurantPlay.Job.WAITER], "the staff form sets each employee's job")
	_expect(room.play.chefs.is_empty() and room.play.cleaners.size() == 1, "and the restaurant reopens with that staff")

	_expect(room.recipe_for("Starter").get("name") == "Tomato and Basil Soup", "by default a course is served with its first recipe")
	var menu_panel := room.choose_menu()
	menu_panel.select(0, 1)
	menu_panel.finish()
	var second_starter: Dictionary = room.menu_choices("Starter")[1]
	_expect(room.menu.get("Starter") == int(second_starter["id"]) and room.recipe_for("Starter") == second_starter, "the menu form sets the dish of a course")
	room.play.set_process(false)
	var table := room.item_at(Vector2i(3, 3))
	var starters := 0
	for attempt in 30:
		var order := room.play.create_order(null, table)
		_expect(order.recipe == room.recipe_for(GameData.recipe_items.get_group_name_by_id(int(order.recipe["id"]))), "orders are for dishes on the menu")
		starters += int(order.recipe == second_starter)
		room.play.cancel_order(order)
	_expect(starters > 0, "customers should order the chosen starter")

	room.stop_play()
	room.jobs = []
	room.menu = {}
	room.start_play()


func _new_customer(room: RestaurantRoom) -> Customer:
	var customer := Customer.new()
	room.play._add_actor(customer, [])
	room.play.customers.append(customer)
	customer.enter(room.play, Vector2i(0, 4))
	return customer


func _seated_customer(room: RestaurantRoom, chair: RoomItem) -> Customer:
	var customer := _new_customer(room)
	customer.take_chair(chair)
	customer.place_on(chair.tile)
	customer.tick(0.0)
	customer.tick(Customer.DECIDING_TIME + 0.1)
	customer.tick(0.0)
	return customer


func _check_waiting_for_a_table(room: RestaurantRoom) -> void:
	const CHAIR := 3040001
	var play := room.play
	play.set_process(false)
	var table := room.item_at(Vector2i(3, 3))
	table.table_top_order = DishOrder.new({}, null, table)
	var waiting := _seated_customer(room, room.item_at(Vector2i(2, 3)))
	_expect(waiting.state == Customer.State.NO_CLEAN_TABLE and waiting.emotion == Customer.Emotion.NO_CLEAN_TABLE,
			"a customer at a table still in use should wait for it, got state %d" % waiting.state)
	table.table_top_order = null
	waiting.tick(0.1)
	_expect(waiting.state == Customer.State.WAITING and waiting.order != null and waiting.emotion == Customer.Emotion.NONE,
			"once the table is cleared the waiting customer should order")
	# A chair facing the stove has no table: its customer queues for a chair that has one.
	var lone_chair := room.place_item(CHAIR, Vector2i(5, 3), 0)
	var queued := _seated_customer(room, lone_chair)
	_expect(queued.state == Customer.State.NO_TABLE and play.waiting_chair_queue == [queued],
			"a customer on a chair with no table should join the queue, got state %d" % queued.state)
	queued.tick(0.1)
	_expect(queued.state == Customer.State.WALKING_TO_CHAIR and play.waiting_chair_queue.is_empty() and lone_chair.occupant == null,
			"the first in the queue should move to a chair with a table")
	_expect(queued.chair != null and room.table_for_chair(queued.chair) != null, "the new chair should face a table")
	room.stop_play()
	room.remove_item(lone_chair)
	room.start_play()


func _check_editor(room: RestaurantRoom) -> void:
	const CHAIR := 3040001
	const WINDOW := 3000011
	_expect(room.can_place(CHAIR, Vector2i(4, 4), 0), "a chair fits on free floor")
	_expect(not room.can_place(CHAIR, Vector2i(3, 3), 0), "a chair does not fit on a table")
	_expect(not room.can_place(CHAIR, Vector2i(0, 3), 0), "a chair does not fit on a wall tile")
	_expect(not room.can_place(CHAIR, Vector2i(40, 4), 0), "a chair does not fit outside the room")
	_expect(room.can_place(WINDOW, Vector2i(0, 3), 0), "a window fits on a bare wall tile")
	_expect(not room.can_place(WINDOW, Vector2i(0, 2), 0), "a window does not fit where one already hangs")
	_expect(not room.can_place(WINDOW, Vector2i(4, 4), 0), "a window does not fit on the floor")
	_expect(not room.can_place(WINDOW, Vector2i(0, 0), 0), "nothing fits on the corner pillar")

	room.hud.decorate_pressed.emit()
	await get_tree().process_frame
	var editor := room.editor
	_expect(editor != null and room.play == null, "decorating closes the restaurant")
	if editor == null:
		return
	_expect(editor.available(CHAIR) == 0, "all three starting chairs are placed, so none are spare")
	var chair := room.item_at(Vector2i(2, 3))
	editor.pick_up(chair)
	_expect(editor.held_id == CHAIR and room.item_at(Vector2i(2, 3)) == null, "picking a chair up takes it out of the room")
	_expect(room.grid.is_walkable(Vector2i(2, 3)), "the tile a chair left is free again")
	_expect(not editor.place_at(Vector2i(3, 3)), "the held chair cannot go onto a table")
	editor.rotate_held()
	_expect(editor.place_at(Vector2i(4, 4)), "the held chair can go onto free floor")
	var moved := room.item_at(Vector2i(4, 4))
	_expect(moved != null and moved.item_id == CHAIR and moved.turns == 1 and not editor.is_holding(), "the chair now stands turned on (4, 4)")
	_expect(not room.grid.is_walkable(Vector2i(4, 4)), "the tile under the moved chair is blocked")
	editor.pick_up(room.item_at(Vector2i(4, 4)))
	editor.store_held()
	_expect(editor.available(CHAIR) == 1 and room.items.size() == 15, "a stored chair is spare and no longer in the room")
	editor.hold(CHAIR)
	editor.place_at(Vector2i(2, 3))
	await editor.finish()
	await get_tree().process_frame
	_expect(room.editor == null and room.play != null, "pressing Done reopens the restaurant")
	_expect(room.to_layout()["items"].size() == 16, "the layout still has all sixteen items")
