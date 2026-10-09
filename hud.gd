extends CanvasLayer
## Coins, level, and popularity, drawn over the restaurant.
##
## ponytail: plain Godot controls. The original HUD art is nested clips with live text
## fields, which flat sprite sheets do not carry; rebuild it panel by panel when the look
## matters more than the function.

signal sign_out_pressed
signal decorate_pressed

const MESSAGE_SECONDS := 4.0

@onready var coins_label: Label = %Coins
@onready var level_label: Label = %Level
@onready var level_bar: ProgressBar = %LevelBar
@onready var demand_label: Label = %Demand
@onready var message_label: Label = %Message
@onready var sign_out_button: Button = %SignOut
@onready var decorate_button: Button = %Decorate

var _message_time_left := 0.0


func _ready() -> void:
	sign_out_button.pressed.connect(func() -> void: sign_out_pressed.emit())
	decorate_button.pressed.connect(func() -> void: decorate_pressed.emit())
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


func set_demand(demand: float) -> void:
	demand_label.text = "Popularity: %d" % roundi(demand)


func set_signed_in(signed_in: bool) -> void:
	sign_out_button.text = "Sign out" if signed_in else "Exit"


## Shows a line under the bar for a few seconds.
func show_message(text: String) -> void:
	message_label.text = text
	_message_time_left = MESSAGE_SECONDS
