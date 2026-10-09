class_name ArcadeSnake
extends Control
## The Retro Arcade Machine's game: a snake that grows with every bite and must not hit a
## wall or itself. Port of WorldArcadeSnake.as on a 320 x 240 screen.
##
## The game only moves when step() is called, so it can be played by a test as well as by
## the clock (see _process).

signal game_over(score: int)

const NUM_TILES := Vector2i(20, 14)
const TILE_SIZE := 16
const HUD_HEIGHT := 16
const SCREEN_SIZE := Vector2(320, 240)
const START_LENGTH := 4
const FOOD_SCORE := 10
const MAX_FOOD := 8
## Seconds between moves: slower at first, quicker each level, never quicker than the minimum.
const START_DELAY := 0.2
const MIN_DELAY := 0.05
const DELAY_STEP := 0.01
## WorldArcadeSnake.LEVEL_MAP: the walls inside the border, a list per level.
const LEVEL_WALLS: Array = [
	[],
	[Vector2i(3, 3), Vector2i(9, 3), Vector2i(10, 3), Vector2i(16, 3), Vector2i(6, 6), Vector2i(13, 6),
		Vector2i(6, 7), Vector2i(13, 7), Vector2i(3, 10), Vector2i(9, 10), Vector2i(10, 10), Vector2i(16, 10)],
	[Vector2i(3, 3), Vector2i(7, 3), Vector2i(12, 3), Vector2i(16, 3), Vector2i(3, 6), Vector2i(7, 6),
		Vector2i(12, 6), Vector2i(16, 6), Vector2i(3, 7), Vector2i(7, 7), Vector2i(12, 7), Vector2i(16, 7),
		Vector2i(3, 10), Vector2i(7, 10), Vector2i(12, 10), Vector2i(16, 10)],
]
const BACKGROUND := Color("1d2b1d")
const WALL := Color("6b8f3a")
const SNAKE := Color("d8f0a0")
const FOOD := Color("f06a4a")
const TEXT := Color("d8f0a0")

var rng := RandomNumberGenerator.new()
var score := 0
var level := 0
var playing := false
## Head first.
var snake: Array[Vector2i] = []
var foods: Array[Vector2i] = []
var walls: Dictionary = {}

var _direction := Vector2i.RIGHT
var _next_direction := Vector2i.RIGHT
var _food_count := 1
var _delay := START_DELAY
var _timer := 0.0


func _ready() -> void:
	custom_minimum_size = SCREEN_SIZE
	focus_mode = Control.FOCUS_ALL
	reset()


## WorldArcadeSnake.resetGame.
func reset() -> void:
	score = 0
	level = 0
	_food_count = 1
	_delay = START_DELAY
	_load_level(0)
	playing = true


## WorldArcadeSnake.loadMap: the border, the level's walls, and the snake along the bottom.
func _load_level(index: int) -> void:
	walls.clear()
	for x in NUM_TILES.x:
		walls[Vector2i(x, 0)] = true
		walls[Vector2i(x, NUM_TILES.y - 1)] = true
	for y in NUM_TILES.y:
		walls[Vector2i(0, y)] = true
		walls[Vector2i(NUM_TILES.x - 1, y)] = true
	for wall: Vector2i in LEVEL_WALLS[index % LEVEL_WALLS.size()]:
		walls[wall] = true
	snake.clear()
	for part in START_LENGTH:
		snake.append(Vector2i(NUM_TILES.x / 2 - part, NUM_TILES.y - 2))
	_direction = Vector2i.RIGHT
	_next_direction = Vector2i.RIGHT
	foods.clear()
	_add_food()


## Turning back on itself is not allowed.
func steer(direction: Vector2i) -> void:
	if direction != -_direction:
		_next_direction = direction


## WorldArcadeSnake.moveSnake: one move. A bite grows the snake; a wall or itself ends it.
func step() -> void:
	if not playing:
		return
	_direction = _next_direction
	var head := snake[0] + _direction
	var eating := head in foods
	# Without a bite the tail moves on, so the head may take its place.
	var body := snake if eating else snake.slice(0, snake.size() - 1)
	if walls.has(head) or head in body:
		playing = false
		game_over.emit(score)
		queue_redraw()
		return
	snake.push_front(head)
	if eating:
		foods.erase(head)
		_add_score(FOOD_SCORE)
		_add_food()
	else:
		snake.pop_back()
	queue_redraw()


## WorldArcadeSnake.getScoreThreshold: the points needed to finish each level grow by 50
## a level, up to 400 more each time.
static func score_threshold(levels: int) -> int:
	var needed := 0
	var step_size := 0
	for index in levels:
		step_size = mini(step_size + 50, 400)
		needed += step_size
	return needed


func _add_score(points: int) -> void:
	var before := score
	score += points
	var threshold := score_threshold(level + 1)
	if before < threshold and score >= threshold:
		# WorldArcadeSnake.levelUp: quicker, more food, the next map.
		_delay = maxf(_delay - DELAY_STEP, MIN_DELAY)
		_food_count = mini(_food_count + 1, MAX_FOOD)
		level += 1
		_load_level(level)


## WorldArcadeSnake.createFoods: food on random empty tiles until there is enough.
func _add_food() -> void:
	var empty: Array[Vector2i] = []
	for x in NUM_TILES.x:
		for y in NUM_TILES.y:
			var tile := Vector2i(x, y)
			if not walls.has(tile) and tile not in snake and tile not in foods:
				empty.append(tile)
	while foods.size() < _food_count and not empty.is_empty():
		foods.append(empty.pop_at(rng.randi_range(0, empty.size() - 1)))


func _process(delta: float) -> void:
	if not playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _delay
		step()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_LEFT, KEY_A:
			steer(Vector2i.LEFT)
		KEY_RIGHT, KEY_D:
			steer(Vector2i.RIGHT)
		KEY_UP, KEY_W:
			steer(Vector2i.UP)
		KEY_DOWN, KEY_S:
			steer(Vector2i.DOWN)
		KEY_SPACE, KEY_ENTER:
			if not playing:
				reset()
	accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN_SIZE), BACKGROUND)
	for tile: Vector2i in walls:
		draw_rect(_tile_rect(tile), WALL)
	for tile in foods:
		draw_rect(_tile_rect(tile).grow(-3), FOOD)
	for tile in snake:
		draw_rect(_tile_rect(tile).grow(-1), SNAKE)
	var font := get_theme_default_font()
	draw_string(font, Vector2(4, 12), "SCORE %d   LEVEL %d" % [score, level + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT)
	if not playing:
		draw_string(font, Vector2(0, SCREEN_SIZE.y / 2), "GAME OVER - PRESS SPACE", HORIZONTAL_ALIGNMENT_CENTER, SCREEN_SIZE.x, 16, TEXT)


func _tile_rect(tile: Vector2i) -> Rect2:
	return Rect2(Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE + HUD_HEIGHT), Vector2(TILE_SIZE, TILE_SIZE))
