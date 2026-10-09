extends Node
## User settings, persisted to user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"
const DISPLAY_SECTION := "display"
const FPS_KEY := "fps"
const FPS_OPTIONS: Array[int] = [30, 60]
const DEFAULT_FPS := 30

var fps: int = DEFAULT_FPS


func _ready() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Settings: cannot read %s (%s), using defaults" % [SETTINGS_PATH, error_string(error)])
	_apply_fps(config.get_value(DISPLAY_SECTION, FPS_KEY, DEFAULT_FPS))


func set_fps(value: int) -> void:
	_apply_fps(value)
	var config := ConfigFile.new()
	config.set_value(DISPLAY_SECTION, FPS_KEY, fps)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Settings: cannot save %s (%s)" % [SETTINGS_PATH, error_string(error)])


func _apply_fps(value: Variant) -> void:
	# The settings file is user-editable, so anything outside FPS_OPTIONS falls back to the default.
	fps = value if value is int and value in FPS_OPTIONS else DEFAULT_FPS
	Engine.max_fps = fps
