extends Node
## Run: tests/check_game.sh
## Checks the data pipeline, the FPS setting, and the restaurant room.
## It runs as a scene, not with -s, because scripts that name an autoload only compile
## inside the running project. The shell wrapper decides pass or fail: see its comment.

const BIND_TURN_TOLERANCE := 0.02
const BIND_OFFSET_TOLERANCE := 1.0

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
	_check_grid()
	var room: RestaurantRoom = load("res://restaurant_room.tscn").instantiate()
	add_child(room)
	await get_tree().process_frame
	_expect(room.get_node("Floor").get_child_count() == 49, "an 8x8 room has a 7x7 floor inside its walls")
	_expect(room.get_node("Walls").get_child_count() == 29, "14 wall pieces, 14 wallpapers, and a corner")
	# The items layer also holds the actor.
	_expect(room.get_node("Items").get_child_count() == RestaurantRoom.DEFAULT_ITEMS.size() + 1,
			"every default item should be placed, got %d" % room.get_node("Items").get_child_count())
	_expect(not room.grid.is_walkable(Vector2i(3, 3)), "a table blocks its tile")
	_expect(not room.grid.is_walkable(Vector2i(0, 3)), "a wall blocks its tile")
	_expect(room.grid.is_walkable(Vector2i(0, 4)), "the door opens the wall tile it is on")
	_expect(room.grid.is_walkable(Vector2i(1, 4)), "the tile inside the door is free")
	_expect(not room.grid.is_walkable(Vector2i(6, 3)), "the rotated stove covers the tile below it")
	_expect(room.actor.tile == RestaurantRoom.DEFAULT_DOOR_TILE, "the actor starts in the doorway")
	_expect(not room.walk_actor_to(Vector2i(3, 3)), "the actor refuses to walk onto a table")
	_expect(room.walk_actor_to(Vector2i(4, 4)), "the actor accepts a free tile")
	_expect(room.actor.is_walking(), "the actor should be walking after accepting a tile")
	var path := room.grid.find_path(RestaurantRoom.DEFAULT_DOOR_TILE, Vector2i(4, 4))
	_expect(not path.is_empty() and path.all(func(step: Vector2i) -> bool: return room.grid.is_walkable(step)),
			"the path to (4, 4) should only cross free tiles, got %s" % [path])
	_check_avatar(room.actor.avatar)
	room.queue_free()


func _check_grid() -> void:
	_expect(RoomGrid.tile_to_screen(Vector2i(3, 1)) == Vector2(80, 80), "tile (3, 1) should be at (80, 80)")
	_expect(RoomGrid.tile_center(Vector2i(0, 0)) == Vector2(0, 20), "a tile's centre is half a tile down")
	_expect(RoomGrid.tile_draw_order(Vector2i(2, 1)) == 22, "tile (2, 1) should draw at index 22")
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(0, 5), Vector2i(7, 7)]:
		_expect(RoomGrid.screen_to_tile(RoomGrid.tile_center(tile)) == tile, "the centre of %s should map back to it" % tile)
	_expect(RoomGrid.footprint_from_extent(Vector2(80, 60)) == Vector2i(2, 1), "the stove's art covers 2x1 tiles")
	_expect(RoomGrid.footprint_from_extent(Vector2(19.5, 30.4)) == Vector2i(1, 1), "a chair covers one tile")
	_expect(RoomGrid.rotated_footprint(Vector2i(2, 1), 3) == Vector2i(1, 2), "an odd rotation swaps the footprint")
	_expect(RoomActor.direction_for(Vector2(0, -20)) == 0, "moving up the screen is direction 0")
	_expect(RoomActor.direction_for(Vector2(40, 20)) == 3, "moving right and down is direction 3")
	_expect(RoomActor.direction_for(Vector2(-40, 20)) == 5, "moving left and down is direction 5")

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
