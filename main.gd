extends VBoxContainer
## Debug screen: proves the data pipeline end to end and exposes the FPS setting.

@onready var fps_option: OptionButton = $FpsOption
@onready var recipe_list: ItemList = $RecipeList


func _ready() -> void:
	for fps in Settings.FPS_OPTIONS:
		fps_option.add_item("%d FPS" % fps, fps)
	fps_option.select(fps_option.get_item_index(Settings.fps))
	fps_option.item_selected.connect(_on_fps_selected)
	for group: Dictionary in GameData.recipe_items.groups:
		for item: Dictionary in group["items"]:
			recipe_list.add_item("%s: %s (%s coins)" % [group["name"], item["name"], item["cost"]])


func _on_fps_selected(index: int) -> void:
	Settings.set_fps(fps_option.get_item_id(index))
