class_name ArcadeCave
extends Control
## The Deep Sea Arcade's game: a fish swims through an endless cave, rising while the button
## is held and sinking when it is let go. Port of WorldArcadeCave.as on a 320 x 240 screen.
##
## ponytail: the cave and the fish only. The original also has food to eat, bubbles,
## sparkles, and fish in the background.

signal game_over(score: int)

const SCREEN_SIZE := Vector2(320, 240)
## CaveMap2: the cave is strips 20 pixels wide; the gap narrows from 220 to 80 pixels.
const STRIP_WIDTH := 20.0
const START_GAP := 220.0
const MIN_GAP := 80.0
const GAP_RANDOM := 10.0
const STRIPS_PER_SEGMENT := 10
## PlayerFish, per frame at the original's 25 frames a second.
const FRAME_TIME := 1.0 / 25.0
const GRAVITY := 0.8
const THRUST := 1.8
const TERMINAL_VELOCITY := 6.0
const SPEED := 8.0
const FISH_X := 80.0
const FISH_SIZE := Vector2(21, 15)
const ROCK := Color("4a4f39")
const WATER := Color("0d2a4a")
const FISH := Color("f0b040")
const TEXT := Color("cfe8ff")

var rng := RandomNumberGenerator.new()
var playing := false
var holding := false
var distance := 0.0
var fish_y := SCREEN_SIZE.y / 2.0
var velocity := 0.0
## The top and bottom of the cave's opening, one entry per strip.
var tops: Array[float] = []
var bottoms: Array[float] = []

var _timer := 0.0


func _ready() -> void:
	custom_minimum_size = SCREEN_SIZE
	focus_mode = Control.FOCUS_ALL
	reset()


func reset() -> void:
	distance = 0.0
	fish_y = SCREEN_SIZE.y / 2.0
	velocity = 0.0
	tops.clear()
	bottoms.clear()
	_extend_cave()
	playing = true


## One strip passed is one point.
func score() -> int:
	return int(distance / STRIP_WIDTH)


## CaveMap2.createSegments: the opening drifts towards a new height every few strips, and
## narrows the further the fish has come.
func _extend_cave() -> void:
	while tops.size() * STRIP_WIDTH < distance + SCREEN_SIZE.x * 2.0:
		var index := tops.size()
		var gap := maxf(START_GAP - index / 10.0, MIN_GAP) + rng.randf_range(0.0, GAP_RANDOM)
		var from := tops[index - 1] if index > 0 else (SCREEN_SIZE.y - gap) / 2.0
		var target := rng.randf_range(0.0, SCREEN_SIZE.y - gap)
		for strip in STRIPS_PER_SEGMENT:
			var top := lerpf(from, target, float(strip + 1) / STRIPS_PER_SEGMENT)
			tops.append(top)
			bottoms.append(top + gap)


## PlayerFish.tick: one frame of swimming.
func step() -> void:
	if not playing:
		return
	velocity = clampf(velocity + GRAVITY - (THRUST if holding else 0.0), -TERMINAL_VELOCITY, TERMINAL_VELOCITY)
	fish_y += velocity
	distance += SPEED
	_extend_cave()
	var strip := int((distance + FISH_X) / STRIP_WIDTH)
	if fish_y - FISH_SIZE.y / 2.0 < tops[strip] or fish_y + FISH_SIZE.y / 2.0 > bottoms[strip]:
		playing = false
		game_over.emit(score())
	queue_redraw()


func _process(delta: float) -> void:
	if not playing:
		return
	_timer += delta
	while _timer >= FRAME_TIME and playing:
		_timer -= FRAME_TIME
		step()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		holding = event.pressed
	elif event is InputEventKey and event.keycode in [KEY_SPACE, KEY_UP, KEY_W]:
		holding = event.pressed
		if event.pressed and not playing:
			reset()
	else:
		return
	accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN_SIZE), WATER)
	var first := int(distance / STRIP_WIDTH)
	var offset := fmod(distance, STRIP_WIDTH)
	for index in range(first, mini(first + int(SCREEN_SIZE.x / STRIP_WIDTH) + 2, tops.size())):
		var x := (index - first) * STRIP_WIDTH - offset
		draw_rect(Rect2(x, 0, STRIP_WIDTH, tops[index]), ROCK)
		draw_rect(Rect2(x, bottoms[index], STRIP_WIDTH, SCREEN_SIZE.y - bottoms[index]), ROCK)
	draw_rect(Rect2(Vector2(FISH_X, fish_y) - FISH_SIZE / 2.0, FISH_SIZE), FISH)
	var font := get_theme_default_font()
	draw_string(font, Vector2(4, 12), "SCORE %d" % score(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT)
	if not playing:
		draw_string(font, Vector2(0, SCREEN_SIZE.y / 2), "GAME OVER - PRESS SPACE", HORIZONTAL_ALIGNMENT_CENTER, SCREEN_SIZE.x, 16, TEXT)
