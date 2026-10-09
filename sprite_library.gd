class_name SpriteLibrary
extends RefCounted
## Sprite sheets written by tools/extract_sprites.py, addressed by the original SWF class name.
## Replaces Engine.getMovieClip(className): a sprite's origin lands where Flash put the
## MovieClip's registration point, and `frame` is the 0-based timeline frame.

var _group: String
var _zoom := 1.0
var _sprites: Dictionary = {}


static func load_group(group: String) -> SpriteLibrary:
	var library := SpriteLibrary.new()
	library._group = group
	var path := "res://assets/sprites/%s.json" % group
	if not FileAccess.file_exists(path):
		push_error("SpriteLibrary: %s is missing. Run: python3 tools/extract_sprites.py %s" % [path, group])
		return library
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("sprites") is Dictionary:
		push_error("SpriteLibrary: %s is not sprite metadata" % path)
		return library
	library._zoom = float(parsed.get("zoom", 1.0))
	library._sprites = parsed["sprites"]
	return library


func has_sprite(sprite_name: String) -> bool:
	return _sprites.has(sprite_name)


func frame_count(sprite_name: String) -> int:
	return int(_sprites.get(sprite_name, {}).get("frames", 0))


## How many sheet pixels one original-game pixel covers, for the group as a whole.
func zoom() -> float:
	return _zoom


## The same for one sprite: long animations are stored smaller than the rest of their group.
func sprite_zoom(sprite_name: String) -> float:
	return float(_sprites.get(sprite_name, {}).get("zoom", _zoom))


## The first frame's drawn area around the registration point, in original-game pixels.
func bounds(sprite_name: String) -> Rect2:
	var edges: Array = _sprites.get(sprite_name, {}).get("bounds", [0, 0, 0, 0])
	var scale := sprite_zoom(sprite_name)
	return Rect2(edges[0] / scale, edges[1] / scale, (edges[2] - edges[0]) / scale, (edges[3] - edges[1]) / scale)


## RoomItem.itemHeight: how far above the floor the top of an item is, e.g. a table top.
func item_height(sprite_name: String, footprint_y: int) -> float:
	var area := bounds(sprite_name)
	return -area.position.y + (RoomGrid.TILE_HEIGHT * footprint_y - area.end.y)


## Where the registration point sits inside a frame, in sheet pixels.
func origin(sprite_name: String) -> Vector2:
	var point: Array = _sprites.get(sprite_name, {}).get("origin", [0, 0])
	return Vector2(point[0], point[1])


## How far the first frame's art reaches right and down from the registration point, in
## original-game pixels. The original judged an item's tile footprint from this.
func extent(sprite_name: String) -> Vector2:
	return bounds(sprite_name).end


## The first frame as a texture, for lists and buttons. Null if the sprite is missing.
func icon(sprite_name: String) -> Texture2D:
	if not has_sprite(sprite_name):
		return null
	var sheet: Texture2D = load("res://assets/sprites/%s/%s.png" % [_group, sprite_name])
	if sheet == null:
		return null
	var info: Dictionary = _sprites[sprite_name]
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, int(info["width"]), int(info["height"]))
	return atlas


## The first frame as an RGBA8 image, for compositing. Returns null (after logging) if missing.
func make_image(sprite_name: String) -> Image:
	if not has_sprite(sprite_name):
		push_error("SpriteLibrary: no sprite %s in group %s" % [sprite_name, _group])
		return null
	var texture: Texture2D = load("res://assets/sprites/%s/%s.png" % [_group, sprite_name])
	if texture == null:
		push_error("SpriteLibrary: texture for %s failed to load" % sprite_name)
		return null
	var info: Dictionary = _sprites[sprite_name]
	var image := texture.get_image().get_region(Rect2i(0, 0, int(info["width"]), int(info["height"])))
	image.convert(Image.FORMAT_RGBA8)
	return image


## Returns null (after logging) when the sprite or its texture does not exist.
func make_sprite(sprite_name: String, frame: int = 0) -> Sprite2D:
	if not has_sprite(sprite_name):
		push_error("SpriteLibrary: no sprite %s in group %s" % [sprite_name, _group])
		return null
	var info: Dictionary = _sprites[sprite_name]
	var texture: Texture2D = load("res://assets/sprites/%s/%s.png" % [_group, sprite_name])
	if texture == null:
		push_error("SpriteLibrary: texture for %s failed to load" % sprite_name)
		return null
	var frames := int(info["frames"])
	var columns := int(info["columns"])
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = false
	sprite.hframes = columns
	sprite.vframes = ceili(float(frames) / columns)
	# Flash rotation wraps around the timeline (RoomItem.rotate), so wrap here too.
	sprite.frame = posmod(frame, frames)
	sprite.offset = -Vector2(info["origin"][0], info["origin"][1])
	# Sheets are rendered at `zoom` times the original size to stay sharp when the window grows.
	sprite.scale = Vector2.ONE / sprite_zoom(sprite_name)
	return sprite
