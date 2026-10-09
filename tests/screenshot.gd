extends Node
## Renders a scene and saves a picture of it: godot --path . res://tests/screenshot.tscn -- <scene> <png>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Api.token = ""
	add_child(load(args[0]).instantiate())
	for frame in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[1])
	get_tree().quit()
