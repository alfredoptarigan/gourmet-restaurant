class_name Cleaner
extends RoomActor
## Picks up trash and repairs broken toilets and arcade machines. Port of CleanerEmployee.as.
##
## ponytail: staff never tire here, so the delay is the original's best case (a happy
## cleaner); port CleanerEmployee.getActionDelay and setWalkSpeed with staff energy.

enum State { IDLE, WALKING, CLEANING }

## CleanerEmployee.ACTION_DELAY_MIN: how long one job takes.
const ACTION_DELAY := 6.0
## The pause between jobs.
const REST_TIME := 2.0

var play: RestaurantPlay
var state: int = State.IDLE
## The broken item being repaired, or null when sweeping the floor.
var cleaning_item: RoomItem

var _timer := 0.0


## WorldRestaurantPlay.addCleaner: a cleaner starts in front of a toilet if there is one.
func start(restaurant_play: RestaurantPlay, taken_tiles: Array[Vector2i]) -> void:
	play = restaurant_play
	place_on(_pick_start(taken_tiles))
	avatar.play(Avatar.Animations.CLEANER_IDLE)


func tick(delta: float) -> void:
	super(delta)
	_timer -= delta
	match state:
		State.IDLE:
			if _timer <= 0.0:
				_find_work()
		State.WALKING:
			if not is_walking():
				_start_cleaning()
		State.CLEANING:
			if _timer <= 0.0:
				_finish_cleaning()


func _pick_start(taken_tiles: Array[Vector2i]) -> Vector2i:
	var grid := play.room.grid
	for toilet: RoomItem in play.shuffled(play.room.items_of_type(RestaurantPlay.TOILET_TYPE)):
		var stand := RoomGrid.facing_tile(toilet.tile, toilet.rotation)
		if grid.is_walkable(stand) and not grid.is_wall(stand) and stand not in taken_tiles:
			return stand
	for free_tile: Vector2i in play.shuffled(play.free_floor_tiles()):
		if free_tile not in taken_tiles:
			return free_tile
	return Vector2i.ONE


## Broken toilets first, then broken machines, then the nearest trash; with nothing to do
## the cleaner sweeps a random spot, as the original does.
func _find_work() -> void:
	var grid := play.room.grid
	for type: String in [RestaurantPlay.TOILET_TYPE, RestaurantPlay.INTERACTIVE_TYPE]:
		for item in play.room.items_of_type(type):
			if item.cleaner != null or not item.is_broken():
				continue
			var path := grid.find_path(tile, item.tile)
			if path.is_empty():
				continue
			path.pop_back()
			item.cleaner = self
			cleaning_item = item
			_walk(path)
			return
	var targets: Array = play.room.trash.keys()
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _steps_to(a) < _steps_to(b))
	targets.append_array(play.shuffled(play.free_floor_tiles()))
	for target: Vector2i in targets:
		var path := grid.find_path(tile, target)
		if not path.is_empty() or target == tile:
			_walk(path)
			return
	_timer = REST_TIME


func _steps_to(target: Vector2i) -> int:
	return absi(target.x - tile.x) + absi(target.y - tile.y)


func _walk(path: Array[Vector2i]) -> void:
	walk(path, Avatar.Animations.CLEANER_WALK)
	state = State.WALKING


func _start_cleaning() -> void:
	var repairing := cleaning_item != null and cleaning_item.has_type(RestaurantPlay.INTERACTIVE_TYPE)
	if cleaning_item != null:
		face_tile(cleaning_item.tile)
	avatar.play(Avatar.Animations.CLEANER_REPAIR if repairing else Avatar.Animations.CLEAN)
	_timer = ACTION_DELAY
	state = State.CLEANING


func _finish_cleaning() -> void:
	if cleaning_item != null:
		play.fix_item(cleaning_item)
		cleaning_item.cleaner = null
		cleaning_item = null
	else:
		play.remove_trash(tile)
	avatar.play(Avatar.Animations.CLEANER_IDLE)
	_timer = REST_TIME
	state = State.IDLE
