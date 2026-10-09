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


## How many sheet pixels one original-game pixel covers.
func zoom() -> float:
	return _zoom


## Where the registration point sits inside a frame, in sheet pixels.
func origin(sprite_name: String) -> Vector2:
	var point: Array = _sprites.get(sprite_name, {}).get("origin", [0, 0])
	return Vector2(point[0], point[1])


## How far the first frame's art reaches right and down from the registration point, in
## original-game pixels. The original judged an item's tile footprint from this.
func extent(sprite_name: String) -> Vector2:
	var bounds: Array = _sprites.get(sprite_name, {}).get("bounds", [0, 0, 0, 0])
	return Vector2(bounds[2], bounds[3]) / _zoom


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
	sprite.scale = Vector2.ONE / _zoom
	return sprite
