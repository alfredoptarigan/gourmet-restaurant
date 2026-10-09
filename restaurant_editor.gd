class_name RestaurantEditor
extends Node
## Decorating mode: move, turn, store, buy, and sell furniture. Core of WorldRestaurantEditor.as.
##
## Click a piece to pick it up, click a tile to put it down; double-click a row in the list
## to take it from the inventory or buy it. Buying and selling go through
## the server, which owns the coins; the new layout is saved when the player presses Done.
##
## Not ported yet: stacking decorations on tables, gifts, cash items, saved layouts, the
## outdoor area, and painting single floor tiles (a floor or wallpaper covers the whole room).

signal finished

const INVENTORY := "Inventory"
## The shop's shelves, in the order shown (group names from restaurant.json).
const SHOP_GROUPS: Array[String] = [
	"Table", "Chair", "Decoration", "Wall Decoration", "Door", "Kitchen Appliance",
	"Functional", "Floor Tile", "Wallpaper", "Outdoor Only", RestaurantRoom.OUTSIDE_GROUP,
]
const FLOOR_GROUP := "Floor Tile"
const WALLPAPER_GROUP := "Wallpaper"
const PANEL_WIDTH := 240
const ICON_SIZE := Vector2i(40, 40)
const VALID_TINT := Color(0.7, 1.0, 0.7, 0.85)
const INVALID_TINT := Color(1.0, 0.5, 0.5, 0.85)
const TURN_COUNT := 4
const PLACE_SOUND := "SfxPlaceItem"

var room: RestaurantRoom
## Item id -> how many the player owns, placed or not.
var owned: Dictionary = {}
var held_id := 0
var held_turns := 0

var _ghost: Sprite2D
var _sprites := SpriteLibrary.load_group("indoor")
var _layer: CanvasLayer
var _shelf: OptionButton
var _list: ItemList
var _message: Label
var _busy := false


func start(restaurant_room: RestaurantRoom) -> void:
	room = restaurant_room
	_build_panel()
	owned = _count(room.to_layout())
	if Api.is_signed_in():
		var result := await Api.fetch_inventory()
		if result["ok"] and result["data"].get("items") is Dictionary:
			owned = {}
			for item_id: String in result["data"]["items"]:
				owned[int(item_id)] = int(result["data"]["items"][item_id])
		else:
			_say("Could not load your inventory: %s" % result["error"])
	_refresh_list()


## How many of each item a layout uses, floor and wallpaper included.
static func _count(layout: Dictionary) -> Dictionary:
	var counts := {}
	var ids: Array = layout["items"].map(func(entry: Dictionary) -> int: return int(entry["id"]))
	for item_id: int in ids + [int(layout["floor"]), int(layout["wallpaper"])]:
		counts[item_id] = counts.get(item_id, 0) + 1
	return counts


## Owned copies that are neither placed nor in hand.
func available(item_id: int) -> int:
	var in_use: int = _count(room.to_layout()).get(item_id, 0) + (1 if held_id == item_id else 0)
	return int(owned.get(item_id, 0)) - in_use


func is_holding() -> bool:
	return held_id != 0


## Takes an item into the hand, from the inventory or straight after buying it.
func hold(item_id: int, turns: int = 0) -> void:
	_drop_ghost()
	held_id = item_id
	held_turns = turns
	_ghost = _sprites.make_sprite(room.sprite_name_of(item_id), turns)
	if _ghost != null:
		_ghost.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
		room.item_layer.add_child(_ghost)
	_refresh_list()


## Picks up a placed item.
func pick_up(item: RoomItem) -> void:
	var item_id := item.item_id
	var turns := item.turns
	room.remove_item(item)
	hold(item_id, turns)


## Puts the held item on a tile. False, and nothing changes, if it does not fit there.
func place_at(tile: Vector2i) -> bool:
	if not is_holding() or not room.can_place(held_id, tile, _turns_at(tile)):
		return false
	room.place_item(held_id, tile, _turns_at(tile))
	Sounds.play(PLACE_SOUND)
	_release()
	return true


func rotate_held() -> void:
	if is_holding():
		hold(held_id, (held_turns + 1) % TURN_COUNT)


## Puts the held item back in the inventory.
func store_held() -> void:
	_release()


func sell_held() -> void:
	if not is_holding() or _busy:
		return
	if not Api.is_signed_in():
		_say("Sign in to sell furniture.")
		return
	_busy = true
	var item_id := held_id
	var result := await Api.sell(item_id)
	_busy = false
	if not result["ok"]:
		_say(result["error"])
		return
	owned[item_id] = int(result["data"].get("quantity", 0))
	room.set_confirmed_coins(int(result["data"].get("coins", 0)))
	_release()


func buy(item_id: int) -> void:
	if _busy:
		return
	if not Api.is_signed_in():
		_say("Sign in to buy furniture.")
		return
	var unlock_level := int(GameData.interior_items.get_item_by_id(item_id).get("unlockLevel", 0))
	if unlock_level > room.level:
		_say("Reach level %d to buy this." % unlock_level)
		return
	_busy = true
	var result := await Api.buy(item_id)
	_busy = false
	if not result["ok"]:
		_say(result["error"])
		return
	owned[item_id] = int(result["data"].get("quantity", 1))
	room.set_confirmed_coins(int(result["data"].get("coins", 0)))
	_use(item_id)


## Saves the layout and leaves decorating mode. Stays in it if the save is refused.
func finish() -> void:
	if _busy:
		return
	store_held()
	if Api.is_signed_in():
		_busy = true
		var result := await Api.save_layout(room.to_layout())
		_busy = false
		if not result["ok"]:
			_say("Could not save: %s" % result["error"])
			return
	_layer.queue_free()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_move_ghost()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_holding():
			if not place_at(_mouse_tile()):
				_say("That does not fit there.")
		else:
			var item := _item_under_mouse()
			if item != null:
				pick_up(item)
				_move_ghost()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		rotate_held()
		_move_ghost()


func _mouse_tile() -> Vector2i:
	return RoomGrid.screen_to_tile(room.get_local_mouse_position())


## A wall decoration turns to face the room from whichever wall it hangs on.
func _turns_at(tile: Vector2i) -> int:
	if RestaurantRoom.WALL_DECORATION_TYPE in GameData.interior_items.get_types_by_id(held_id):
		return RestaurantRoom.NORTH_WALL_ROTATION if tile.y == 0 else RestaurantRoom.WEST_WALL_ROTATION
	return held_turns


func _move_ghost() -> void:
	if _ghost == null:
		return
	var tile := _mouse_tile()
	_ghost.position = RoomGrid.tile_to_screen(tile)
	_ghost.frame = posmod(_turns_at(tile), _ghost.hframes * _ghost.vframes)
	_ghost.modulate = VALID_TINT if room.can_place(held_id, tile, _turns_at(tile)) else INVALID_TINT


## The frontmost item whose art, not just its tile, is under the pointer.
func _item_under_mouse() -> RoomItem:
	var found: RoomItem = null
	for item in room.items:
		var point := item.sprite.to_local(room.get_global_mouse_position())
		if item.sprite.get_rect().has_point(point) and item.sprite.is_pixel_opaque(point):
			if found == null or item.sprite.z_index >= found.sprite.z_index:
				found = item
	return found


func _drop_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


func _release() -> void:
	held_id = 0
	_drop_ghost()
	_refresh_list()


## Floors and wallpaper cover the whole room; everything else goes into the hand.
func _use(item_id: int) -> void:
	match GameData.interior_items.get_group_name_by_id(item_id):
		FLOOR_GROUP:
			room.set_floor(item_id)
			_refresh_list()
		WALLPAPER_GROUP:
			room.set_wallpaper(item_id)
			_refresh_list()
		RestaurantRoom.OUTSIDE_GROUP:
			room.set_outside_size(RestaurantRoom.best_outside_size(owned))
			_say("Your outdoor area is %d x %d tiles." % [room.outside_size.x, room.outside_size.y])
			_refresh_list()
		_:
			hold(item_id)


func _say(text: String) -> void:
	_message.text = text


func _build_panel() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	panel.offset_top = 48
	_layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)

	_shelf = OptionButton.new()
	for shelf_name in [INVENTORY] + SHOP_GROUPS:
		_shelf.add_item(shelf_name)
	_shelf.item_selected.connect(func(_index: int) -> void: _refresh_list())
	column.add_child(_shelf)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = ICON_SIZE
	# Double-click, so a stray click cannot spend coins.
	_list.item_activated.connect(_on_list_item_activated)
	column.add_child(_list)

	var actions := HBoxContainer.new()
	column.add_child(actions)
	for action: Array in [["Turn (R)", rotate_held], ["Store", store_held], ["Sell", sell_held]]:
		var button := Button.new()
		button.text = action[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(action[1])
		actions.add_child(button)

	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(finish)
	column.add_child(done)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(0, 44)
	_message.text = "Click furniture to move it. Double-click a row to use or buy it."
	column.add_child(_message)


func _on_list_item_activated(index: int) -> void:
	var item_id: int = _list.get_item_metadata(index)
	_list.deselect_all()
	_say("")
	if _shelf.get_item_text(_shelf.selected) == INVENTORY or available(item_id) > 0:
		_use(item_id)
	else:
		buy(item_id)


func _refresh_list() -> void:
	if _list == null:
		return
	_list.clear()
	var shelf := _shelf.get_item_text(_shelf.selected)
	if shelf == INVENTORY:
		for item_id: int in owned:
			if available(item_id) > 0:
				_add_row(item_id, "x%d" % available(item_id))
		return
	for config: Dictionary in GameData.interior_items.get_items(shelf):
		# The shop sells what coins can buy: no awards, cash items, or hidden items.
		if int(config.get("cost", 0)) > 0 and int(config.get("cash", 0)) == 0 and config.get("invisible") != true:
			var spare := available(int(config["id"]))
			_add_row(int(config["id"]), "%d coins" % int(config["cost"]) if spare <= 0 else "owned x%d" % spare)


func _add_row(item_id: int, note: String) -> void:
	var config := GameData.interior_items.get_item_by_id(item_id)
	var index := _list.add_item("%s (%s)" % [config.get("name", str(item_id)), note], _sprites.icon(config.get("className", "")))
	_list.set_item_metadata(index, item_id)
