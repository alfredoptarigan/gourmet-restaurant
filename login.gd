extends Control
## First screen: sign in or register, then open the restaurant. A saved session skips the form.

const RESTAURANT_SCENE := "res://restaurant_room.tscn"

@onready var username_edit: LineEdit = %Username
@onready var password_edit: LineEdit = %Password
@onready var login_button: Button = %Login
@onready var register_button: Button = %Register
@onready var offline_button: Button = %Offline
@onready var message_label: Label = %Message


func _ready() -> void:
	login_button.pressed.connect(_submit.bind(false))
	register_button.pressed.connect(_submit.bind(true))
	offline_button.pressed.connect(_play_offline)
	password_edit.text_submitted.connect(func(_text: String) -> void: _submit(false))
	if Api.is_signed_in():
		_resume_session()


func _resume_session() -> void:
	_set_busy(true, "Signing in...")
	var result := await Api.fetch_profile()
	if result["ok"]:
		_open_restaurant()
		return
	# A 401 just means the saved session ended; anything else is worth showing.
	_set_busy(false, "" if result["status"] == Api.UNAUTHORIZED else result["error"])


func _submit(is_new_account: bool) -> void:
	var username := username_edit.text.strip_edges()
	var password := password_edit.text
	if username.is_empty() or password.is_empty():
		message_label.text = "Enter a username and a password."
		return
	_set_busy(true, "Creating your account..." if is_new_account else "Signing in...")
	var result: Dictionary
	if is_new_account:
		result = await Api.register(username, password)
	else:
		result = await Api.login(username, password)
	if result["ok"]:
		_open_restaurant()
	else:
		_set_busy(false, result["error"])


## Runs the restaurant without a server: nothing is saved.
func _play_offline() -> void:
	Api.token = ""
	_open_restaurant()


func _open_restaurant() -> void:
	get_tree().change_scene_to_file(RESTAURANT_SCENE)


func _set_busy(busy: bool, message: String) -> void:
	for control: BaseButton in [login_button, register_button, offline_button]:
		control.disabled = busy
	username_edit.editable = not busy
	password_edit.editable = not busy
	message_label.text = message
