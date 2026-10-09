extends CanvasLayer
## Coins, level, and popularity, drawn over the restaurant.
##
## ponytail: plain Godot controls. The original HUD art is nested clips with live text
## fields, which flat sprite sheets do not carry; rebuild it panel by panel when the look
## matters more than the function.

signal sign_out_pressed
signal decorate_pressed
signal menu_pressed
signal staff_pressed
signal avatar_pressed
signal feed_pressed
signal recipes_pressed
signal garden_pressed

const MESSAGE_SECONDS := 4.0

@onready var coins_label: Label = %Coins
@onready var level_label: Label = %Level
@onready var level_bar: ProgressBar = %LevelBar
@onready var demand_label: Label = %Demand
@onready var message_label: Label = %Message
@onready var sign_out_button: Button = %SignOut
@onready var decorate_button: Button = %Decorate
@onready var menu_button: Button = %Menu
@onready var staff_button: Button = %Staff
@onready var avatar_button: Button = %Avatar
@onready var feed_button: Button = %Feed
@onready var recipes_button: Button = %Recipes
@onready var garden_button: Button = %Garden

var _message_time_left := 0.0
var _choices: ChoicePanel


func _ready() -> void:
	sign_out_button.pressed.connect(func() -> void: sign_out_pressed.emit())
	decorate_button.pressed.connect(func() -> void: decorate_pressed.emit())
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	staff_button.pressed.connect(func() -> void: staff_pressed.emit())
	avatar_button.pressed.connect(func() -> void: avatar_pressed.emit())
	feed_button.pressed.connect(func() -> void: feed_pressed.emit())
	recipes_button.pressed.connect(func() -> void: recipes_pressed.emit())
	garden_button.pressed.connect(func() -> void: garden_pressed.emit())
	message_label.text = ""


func _process(delta: float) -> void:
	if _message_time_left <= 0.0:
		return
	_message_time_left -= delta
	if _message_time_left <= 0.0:
		message_label.text = ""


func set_coins(coins: int) -> void:
	coins_label.text = "Coins: %d" % coins


func set_gourmet_points(points: int) -> void:
	var level := Levels.level_for(points)
	level_label.text = "Level %d" % level
	level_bar.value = Levels.progress(points) * level_bar.max_value
	level_bar.tooltip_text = "%d gourmet points" % points


## A closed restaurant lets no customers in: it needs a chef and a waiter with energy left.
func set_demand(demand: float, closed: bool = false) -> void:
	demand_label.text = "Popularity: %d%s" % [roundi(demand), " (closed: staff need rest)" if closed else ""]


func set_signed_in(signed_in: bool) -> void:
	sign_out_button.text = "Sign out" if signed_in else "Exit"


## Shows a line under the bar for a few seconds.
func show_message(text: String) -> void:
	message_label.text = text
	_message_time_left = MESSAGE_SECONDS


## Opens a form in the middle of the screen, replacing any form already open.
func open_choices(title: String, rows: Array) -> ChoicePanel:
	if is_instance_valid(_choices):
		_choices.queue_free()
	_choices = ChoicePanel.new()
	_choices.setup(title, rows)
	add_child(_choices)
	_choices.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	return _choices
