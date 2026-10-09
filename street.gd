class_name Street
extends Node2D
## The street outside: the player's building between the original's "invite a friend"
## houses. Port of a part of WorldStreet.as.
##
## Friends' buildings stand in the row, alternately right and left of the player's, with the
## invite houses at the ends. Clicking a friend's building visits their restaurant.

const RESTAURANT_SCENE := "res://restaurant_room.tscn"
const STREET_MUSIC := "MusicStreet"
const BUILDING_KEY := "building"
## WorldStreet.BUILDING_GAP: the distance between the middles of two buildings.
const BUILDING_GAP := 420.0
## Where the bottom of the buildings stands on the 760 x 600 stage.
const GROUND_ON_SCREEN := Vector2(380, 430)
const SKY := Color("9fd3f0")
## WorldStreet.STREET_ROAD_COLOUR for a friends' street, and the pavement.
const ROAD := Color("848480")
const PAVEMENT := Color("c8c2b4")
const INVITE_HOUSES: Array[int] = [2080000, 2080001]
## The pieces the customise form can swap, by front.json group.
const SWAPPABLE: Array[String] = ["Body", "Roof", "Tile", "Door", "Banner"]
const MAX_BANNER_LENGTH := 40

## WorldCustomiseBuilding.DEFAULT_BUILDING_ITEMS: the server gives new players the same.
const STARTER_BUILDING := {
	"items": [
		{"id": 2060000, "x": 0, "y": 0}, {"id": 2020001, "x": 0, "y": 0}, {"id": 2010012, "x": 0, "y": 0},
		{"id": 2070000, "x": 0, "y": -100}, {"id": 2000014, "x": 60, "y": -23}, {"id": 2000014, "x": -60, "y": -23},
		{"id": 2050008, "x": 0, "y": 0}, {"id": 2040002, "x": 70, "y": 0}, {"id": 2040002, "x": -70, "y": 0},
		{"id": 2040017, "x": 30, "y": 0}, {"id": 2040011, "x": 120, "y": 0},
	],
	"banner": "My Restaurant",
}

var building: Dictionary = STARTER_BUILDING.duplicate(true)
## Item id -> how many the player owns, as the server last said.
var owned: Dictionary = {}

var _view := BuildingView.new()
var _layer := CanvasLayer.new()
var _message := Label.new()
var _choices: ChoicePanel
## Slot (buildings right of the player's are positive) -> the friend whose building is there.
var _neighbours: Dictionary = {}
var _neighbour_views: Array[Node2D] = []


func _ready() -> void:
	position = GROUND_ON_SCREEN
	_draw_street()
	add_child(_view)
	_build_buttons()
	Sounds.play_music(STREET_MUSIC)
	if Api.is_signed_in():
		var saved := valid_building(Api.profile.get("data", {}).get(BUILDING_KEY))
		if not saved.is_empty():
			building = saved
		var inventory := await Api.fetch_inventory()
		if inventory["ok"] and inventory["data"].get("items") is Dictionary:
			for item_id: String in inventory["data"]["items"]:
				owned[int(item_id)] = int(inventory["data"]["items"][item_id])
	_view.show_building(building)
	if Api.is_signed_in():
		var friend_list := await Api.fetch_friends()
		if friend_list["ok"]:
			show_neighbours(RoomSocial.valid_friends(friend_list["data"].get("friends")))
	else:
		show_neighbours([])


## The slot of the `index`th friend: 1, -1, 2, -2, and so on.
static func slot_of(index: int) -> int:
	return (index / 2 + 1) * (1 if index % 2 == 0 else -1)


func show_neighbours(friends: Array) -> void:
	for view in _neighbour_views:
		view.queue_free()
	_neighbour_views.clear()
	_neighbours.clear()
	var library := SpriteLibrary.load_group("outdoor")
	for index in friends.size():
		var their := valid_building(friends[index].get("building"))
		var view := BuildingView.new()
		view.position = Vector2(slot_of(index) * BUILDING_GAP, 0)
		add_child(view)
		view.show_building(their if not their.is_empty() else STARTER_BUILDING)
		_neighbours[slot_of(index)] = friends[index]
		_neighbour_views.append(view)
	# The invite houses fill the next lot on each side.
	for index in INVITE_HOUSES.size():
		var house_class: String = GameData.building_items.get_item_by_id(INVITE_HOUSES[index]).get("className", "")
		if not library.has_sprite(house_class):
			continue
		var side := 1 if index == 0 else -1
		var slot := side
		while _neighbours.has(slot):
			slot += side
		var house := library.make_sprite(house_class)
		house.position = Vector2(slot * BUILDING_GAP, 0)
		add_child(house)
		_neighbour_views.append(house)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE) != 0:
		position.x += event.relative.x
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var slot := roundi(get_local_mouse_position().x / BUILDING_GAP)
		if _neighbours.has(slot):
			_say("Visiting %s..." % _neighbours[slot]["username"])
			var error := await RoomSocial.visit_friend(get_tree(), int(_neighbours[slot]["id"]))
			if not error.is_empty():
				_say(error)


## A saved building as the game can use it: empty unless every piece is a known front piece.
static func valid_building(saved: Variant) -> Dictionary:
	if not saved is Dictionary or not saved.get("items") is Array or not saved.get("banner") is String:
		return {}
	var items: Array = []
	for entry: Variant in saved["items"]:
		if not entry is Dictionary or GameData.building_items.get_item_by_id(int(entry.get("id", 0))).is_empty():
			return {}
		items.append({"id": int(entry["id"]), "x": int(entry.get("x", 0)), "y": int(entry.get("y", 0))})
	return {"items": items, "banner": saved["banner"]}


## The building with the piece of `group_name` swapped for `item_id` (added if it had none).
static func with_piece(from: Dictionary, group_name: String, item_id: int) -> Dictionary:
	var changed: Dictionary = from.duplicate(true)
	for entry: Dictionary in changed["items"]:
		if GameData.building_items.get_group_name_by_id(int(entry["id"])) == group_name:
			entry["id"] = item_id
			return changed
	changed["items"].append({"id": item_id, "x": 0, "y": -100 if group_name == BuildingView.BANNER_GROUP else 0})
	return changed


func _draw_street() -> void:
	var sky := ColorRect.new()
	sky.color = SKY
	sky.position = -GROUND_ON_SCREEN - Vector2(400, 200)
	sky.size = Vector2(1600, 1000)
	sky.z_index = -10
	add_child(sky)
	for band: Array in [[PAVEMENT, 0.0, 40.0], [ROAD, 40.0, 140.0]]:
		var strip := ColorRect.new()
		strip.color = band[0]
		strip.position = Vector2(-GROUND_ON_SCREEN.x - 400, band[1])
		strip.size = Vector2(1600, band[2])
		strip.z_index = -5
		add_child(strip)


func _build_buttons() -> void:
	add_child(_layer)
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 8)
	_layer.add_child(bar)
	for action: Array in [["Enter restaurant", _enter_restaurant], ["Customise", customise]]:
		var button := Button.new()
		button.text = action[0]
		button.pressed.connect(action[1])
		bar.add_child(button)
	_message.position = Vector2(12, 48)
	_layer.add_child(_message)


func _enter_restaurant() -> void:
	get_tree().change_scene_to_file(RESTAURANT_SCENE)


func _say(text: String) -> void:
	_message.text = text


## WorldCustomiseBuilding as a form: the body, roof, wall tiles, door, and banner, and the
## name on the banner. Pieces not owned yet are bought when chosen.
## ponytail: windows and decorations keep their places; the original drags them about.
func customise() -> ChoicePanel:
	if is_instance_valid(_choices):
		_choices.queue_free()
	var rows: Array = []
	for group_name in SWAPPABLE:
		var pieces := _for_sale(group_name)
		var current := BuildingView.pieces_of(building, group_name)
		var current_id := int(current[0]["id"]) if not current.is_empty() else 0
		rows.append({
			"label": group_name,
			"options": pieces.map(func(piece: Dictionary) -> String:
				var note := "owned" if owned.get(int(piece["id"]), 0) > 0 else "%s coins" % piece.get("cost", "?")
				return "%s (%s)" % [piece.get("name", ""), note]),
			"selected": maxi(0, pieces.map(func(piece: Dictionary) -> int: return int(piece["id"])).find(current_id)),
		})
	rows.append({"label": "Name", "text": building.get("banner", "")})
	_choices = ChoicePanel.new()
	_choices.setup("Customise your building", rows)
	_layer.add_child(_choices)
	_choices.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var panel := _choices
	_choices.chosen.connect(func(selections: Array[int]) -> void: _on_customised(selections, panel.text_of(SWAPPABLE.size())))
	return _choices


## The pieces of a group that can be had: those owned and those the shop sells for coins.
func _for_sale(group_name: String) -> Array:
	return GameData.building_items.get_items(group_name).filter(func(piece: Dictionary) -> bool:
		return owned.get(int(piece["id"]), 0) > 0 or (int(piece.get("cost", 0)) > 0 and int(piece.get("cash", 0)) == 0 and piece.get("invisible") != true))


func _on_customised(selections: Array[int], banner_text: String) -> void:
	if not Api.is_signed_in():
		_say("Sign in to customise your building.")
		return
	var changed: Dictionary = building.duplicate(true)
	changed["banner"] = banner_text.strip_edges().left(MAX_BANNER_LENGTH)
	for index in SWAPPABLE.size():
		var pieces := _for_sale(SWAPPABLE[index])
		if selections[index] < 0 or selections[index] >= pieces.size():
			continue
		var piece_id := int(pieces[selections[index]]["id"])
		var current := BuildingView.pieces_of(changed, SWAPPABLE[index])
		if not current.is_empty() and int(current[0]["id"]) == piece_id:
			continue
		if owned.get(piece_id, 0) <= 0:
			var bought := await Api.buy(piece_id)
			if not bought["ok"]:
				_say(bought["error"])
				return
			owned[piece_id] = int(bought["data"].get("quantity", 1))
		changed = with_piece(changed, SWAPPABLE[index], piece_id)
	var saved := await Api.save_data(BUILDING_KEY, changed)
	if not saved["ok"]:
		_say("Could not save: %s" % saved["error"])
		return
	building = changed
	_view.show_building(building)
	_say("Your building is saved.")
