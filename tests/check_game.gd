extends Node
## Run: tests/check_game.sh
## Checks the data pipeline, the FPS setting, and the restaurant room.
## It runs as a scene, not with -s, because scripts that name an autoload only compile
## inside the running project. The shell wrapper decides pass or fail: see its comment.

var failures: Array[String] = []


func _ready() -> void:
	_check_data()
	_check_fps_setting()
	await _check_room()
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
	_expect(RestaurantRoom.tile_to_screen(Vector2i(0, 0)) == Vector2.ZERO, "tile (0, 0) is the room origin")
	_expect(RestaurantRoom.tile_to_screen(Vector2i(3, 1)) == Vector2(80, 80), "tile (3, 1) should be at (80, 80)")
	_expect(RestaurantRoom.tile_draw_order(Vector2i(2, 1)) == 22, "tile (2, 1) should draw at index 22")
	var room: Node = load("res://restaurant_room.tscn").instantiate()
	add_child(room)
	await get_tree().process_frame
	_expect(room.get_node("Floor").get_child_count() == 64, "an 8x8 room has 64 floor tiles")
	_expect(room.get_node("Walls").get_child_count() == 16, "two 8-tile walls have 16 wallpaper pieces")
	# The items layer also holds the placeholder avatar.
	_expect(room.get_node("Items").get_child_count() == RestaurantRoom.DEFAULT_ITEMS.size() + 1,
			"every default item should be placed, got %d" % room.get_node("Items").get_child_count())
	_expect(RestaurantRoom.tile_center(Vector2i(0, 0)) == Vector2(0, 20), "a tile's centre is half a tile down")
	_check_avatar(room.get_node_or_null("Items/Avatar"))
	room.queue_free()


func _check_avatar(avatar: Avatar) -> void:
	_expect(avatar != null, "the room should contain an avatar")
	if avatar == null:
		return
	var hidden := avatar.find_child("hat01", true, false) as Node3D
	var shown := avatar.find_child("shirt01", true, false) as Node3D
	_expect(hidden != null and not hidden.visible, "a hat the avatar does not wear should be hidden")
	_expect(shown != null and shown.visible, "the shirt the avatar wears should be visible")
	avatar.set_direction(9)
	_expect(avatar.direction == 1, "direction 9 should wrap to 1")
	avatar.play(Avatar.Animations.WAITOR_WALK)
	var tray := avatar.find_child("tray", true, false) as Node3D
	_expect(tray != null and tray.visible, "the tray should show while a waiter walks")
	avatar.play(Avatar.Animations.IDLE)
	_expect(tray != null and not tray.visible, "the tray should hide when idle")
	var order: Array[Dictionary] = [{"priority": 2, "id": "a"}, {"priority": 0, "id": "b"}, {"priority": 2, "id": "c"}]
	var sorted := Avatar.sort_by_priority(order).map(func(entry: Dictionary) -> String: return entry["id"])
	_expect(sorted == ["b", "c", "a"], "texture pieces sort by priority, later equals first, got %s" % [sorted])
