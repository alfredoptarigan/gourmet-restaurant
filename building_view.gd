class_name BuildingView
extends Node2D
## A restaurant's front on the street, drawn from its pieces. Port of StreetBuilding.as.
##
## A building is {"items": [{"id", "x", "y"}], "banner": String}: pieces of front.json placed
## relative to the middle of the bottom of the building's base. The body is the base, the
## wall tile pattern fills it, the roof is scaled to sit on top of it, and the banner shows
## the restaurant's name.
##
## ponytail: the flat sprite sheets keep the clips the original hid or filled in at run time:
## a roof's measuring rectangle shows as black corners, and a banner's text field shows its
## placeholder under the name. Skip those clips in tools/extract_sprites.py to clean them up.

const BODY_GROUP := "Body"
const ROOF_GROUP := "Roof"
const TILE_GROUP := "Tile"
const BANNER_GROUP := "Banner"
const BANNER_FONT_SIZE := 16
const BANNER_TEXT_COLOUR := Color("3b2412")

var _sprites := SpriteLibrary.load_group("outdoor")


## The pieces of one group in a building.
static func pieces_of(building: Dictionary, group_name: String) -> Array:
	return building.get("items", []).filter(func(entry: Dictionary) -> bool:
		return GameData.building_items.get_group_name_by_id(int(entry.get("id", 0))) == group_name)


func show_building(building: Dictionary) -> void:
	for child in get_children():
		child.free()
	var bodies := pieces_of(building, BODY_GROUP)
	var body_sprite := _piece_sprite(bodies[0]) if not bodies.is_empty() else null
	var body_area := Rect2()
	if body_sprite != null:
		add_child(body_sprite)
		body_area = _sprites.bounds(_class_of(bodies[0]))
		var tiles := pieces_of(building, TILE_GROUP)
		if not tiles.is_empty():
			_fill_with_tile(body_sprite, _class_of(tiles[0]))
	for entry: Dictionary in building.get("items", []):
		var group_name := GameData.building_items.get_group_name_by_id(int(entry.get("id", 0)))
		if group_name in [BODY_GROUP, TILE_GROUP]:
			continue
		var sprite := _piece_sprite(entry)
		if sprite == null:
			continue
		if group_name == ROOF_GROUP and body_sprite != null:
			# StreetBuilding.positionRoof: on top of the body, as wide as it.
			var roof_area := _sprites.bounds(_class_of(entry))
			sprite.position = Vector2(0, body_area.position.y)
			if roof_area.size.x > 0.0:
				sprite.scale *= body_area.size.x / roof_area.size.x
		add_child(sprite)
		if group_name == BANNER_GROUP:
			_write_banner(sprite.position, str(building.get("banner", "")))


func _class_of(entry: Dictionary) -> String:
	return GameData.building_items.get_item_by_id(int(entry.get("id", 0))).get("className", "")


func _piece_sprite(entry: Dictionary) -> Sprite2D:
	var piece_class := _class_of(entry)
	if not _sprites.has_sprite(piece_class):
		return null
	var sprite := _sprites.make_sprite(piece_class)
	sprite.position = Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))
	var group := GameData.building_items.get_group(GameData.building_items.get_group_name_by_id(int(entry.get("id", 0))))
	sprite.z_index = int(group.get("drawPriority", 0))
	return sprite


## StreetBuilding.setWallTile: the tile pattern repeated over the body, clipped to its shape.
func _fill_with_tile(body: Sprite2D, tile_class: String) -> void:
	var image := _sprites.make_image(tile_class)
	if image == null:
		return
	body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var tile := Sprite2D.new()
	tile.texture = ImageTexture.create_from_image(image)
	tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tile.centered = false
	tile.region_enabled = true
	tile.region_rect = Rect2(Vector2.ZERO, body.texture.get_size() / Vector2(body.hframes, body.vframes))
	tile.position = body.offset
	body.add_child(tile)


func _write_banner(at: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	label.add_theme_color_override("font_color", BANNER_TEXT_COLOUR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(200, 30)
	label.position = at - label.size / 2.0
	label.z_index = 10
	add_child(label)
