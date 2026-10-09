class_name Avatar
extends Node2D
## A character, drawn the way the original client drew it (Avatar3D.as and IsoCacher.as):
## the shared 3D model is dressed, textured, posed on one animation frame, and rendered
## isometrically. The node's origin is the character's feet.
##
## ponytail: the original cached every frame as a bitmap; this renders one live SubViewport
## per avatar. Cache frames into textures if a full restaurant makes that too slow.

## Avatar3D.ANIMATION_* ids.
enum Animations {
	IDLE, WALK, SIT, EAT, WAITOR_WALK, COOKING, EDITOR_IDLE, EDITOR_OUTFIT_CHANGE,
	EDITOR_HEAD_CHANGE, EDITOR_PANTS_CHANGE, DEAD, HIRE_TRASHCAN, HIRE_BUS, HIRE_BENCH,
	WAITOR_WORKING, STREET_WALK, STREET_IDLE, CLEAN, CLEANER_WALK, CLEANER_IDLE,
	CLEANER_DEAD, CLEANER_REPAIR,
}

const MODEL_PATH := "res://assets/avatar/avatar.dae"
const MODEL_ANIMATION := "default"
const SKINS_PATH := "res://assets/avatar/skins.json"
## Avatar3D.ANIMATION_FRAME_RANGE: first and last frame of each animation on the one timeline.
const FRAME_RANGES: Array[int] = [
	20, 23, 0, 3, 35, 35, 36, 39, 10, 13, 30, 33, 45, 68, 72, 90, 92, 101, 103, 129, 133, 133,
	132, 132, 131, 131, 130, 130, 30, 33, 0, 3, 20, 23, 136, 140, 10, 13, 20, 23, 133, 133, 141, 144,
]
## Avatar3D.ANIMATION_FRAME_DELAY_MULTIPLIER.
const FRAME_DELAY_MULTIPLIERS: Array[float] = [
	2, 1.75, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 2, 2, 1, 1,
]
## Avatar3D.ANIMATION_SHOW_OBJECTS: props that appear only during some animations.
const ANIMATION_PROPS := {
	Animations.WAITOR_WALK: ["tray"],
	Animations.CLEAN: ["bucket", "brush"],
	Animations.CLEANER_WALK: ["bucket", "brush"],
	Animations.CLEANER_IDLE: ["bucket", "brush"],
	Animations.CLEANER_DEAD: ["bucket", "brush"],
	Animations.CLEANER_REPAIR: ["repair"],
}
const PROP_NAMES: Array[String] = ["tray", "bucket", "brush", "repair"]
const CUSTOMISABLE_PREFIXES: Array[String] = ["pants", "dress", "shirt", "hat", "hair", "armleft", "armright"]
const TIMELINE_FPS := 10.0
const DEFAULT_FRAME_DELAY := 0.08
const DIRECTION_COUNT := 8
## Directions run clockwise from 0 = walking up the screen, so 4 walks toward the camera
## and shows the face (AvatarActor.moveTo).
const FACING_CAMERA_DIRECTION := 4
const ISO_PITCH_DEGREES := 30.0
const TEXTURE_SIZE := 256
const BODY_MATERIAL := "texture"
const HAIR_MATERIAL := "hair"
## IsoCacher puts the light at (-100000, 9000, -84000) in Away3D's left-handed space.
const LIGHT_DIRECTION := Vector3(100, -9, -84)
const AMBIENT_ENERGY := 0.5

## Calibration, in original-game pixels. The Away3D camera scale could not be derived from
## the source, so these were tuned by eye against the furniture: adjust here if the
## character looks too big or small, or floats above the floor.
const PIXELS_PER_UNIT := 0.4
const VIEW_SIZE := Vector2i(160, 160)
const FEET_FROM_TOP := 130

var direction := FACING_CAMERA_DIRECTION
var animation: int = Animations.IDLE

var _sprites := SpriteLibrary.load_group("avatar")
var _viewport: SubViewport
var _yaw: Node3D
var _model: Node3D
var _player: AnimationPlayer
var _frame := 0
var _frame_time := 0.0


## `items` are {"group", "name"} pairs naming entries in the avatar item database.
func setup(items: Array, skin_colour: Color, hair_colour: Color) -> void:
	if _model == null and not _build_view():
		return
	var configs: Array[Dictionary] = []
	for entry: Dictionary in items:
		var config := GameData.avatar_items.get_item_from_group(entry["name"], entry["group"])
		if not config.is_empty():
			var priority := int(GameData.avatar_items.get_group(entry["group"]).get("priority", 0))
			configs.append({"config": config, "priority": int(config.get("priority", priority))})
	_show_objects(configs)
	_apply_materials(_build_texture(configs, skin_colour), hair_colour)
	play(animation)
	set_direction(direction)


func set_direction(value: int) -> void:
	direction = posmod(value, DIRECTION_COUNT)
	if _yaw != null:
		_yaw.rotation_degrees.y = (FACING_CAMERA_DIRECTION - direction) * 360.0 / DIRECTION_COUNT


func play(value: int) -> void:
	animation = value
	_frame_time = 0.0
	if _model == null:
		return
	for prop in PROP_NAMES:
		_set_object_visible(prop, prop in ANIMATION_PROPS.get(animation, []))
	_set_frame(FRAME_RANGES[animation * 2])


func _process(delta: float) -> void:
	if _model == null:
		return
	_frame_time += delta
	var delay := DEFAULT_FRAME_DELAY * FRAME_DELAY_MULTIPLIERS[animation]
	while _frame_time >= delay:
		_frame_time -= delay
		var last := FRAME_RANGES[animation * 2 + 1]
		_set_frame(FRAME_RANGES[animation * 2] if _frame >= last else _frame + 1)


func _set_frame(frame: int) -> void:
	_frame = frame
	_player.seek(frame / TIMELINE_FPS, true)


func _build_view() -> bool:
	var scene: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	if scene == null:
		push_error("Avatar: %s is missing. Run: python3 tools/extract_data.py" % MODEL_PATH)
		return false
	var zoom := _sprites.zoom()
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(Vector2(VIEW_SIZE) * zoom)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# IsoCacher pitches the model, then turns it around its own (now tilted) up axis.
	var pitch := Node3D.new()
	pitch.rotation_degrees.x = ISO_PITCH_DEGREES
	_yaw = Node3D.new()
	_model = scene.instantiate()
	_yaw.add_child(_model)
	pitch.add_child(_yaw)
	_viewport.add_child(pitch)
	_bind_meshes()
	_player = _model.get_node("AnimationPlayer")
	_player.play(MODEL_ANIMATION)
	_player.pause()

	# The original camera sits 80000 units away, which is orthographic in all but name.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW_SIZE.y / PIXELS_PER_UNIT
	camera.far = 4000.0
	camera.position = Vector3(0, (FEET_FROM_TOP - VIEW_SIZE.y / 2.0) / PIXELS_PER_UNIT, 2000)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = AMBIENT_ENERGY
	camera.environment = environment
	_viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.basis = Basis.looking_at(LIGHT_DIRECTION)
	_viewport.add_child(light)

	var sprite := Sprite2D.new()
	sprite.texture = _viewport.get_texture()
	sprite.centered = false
	sprite.offset = -Vector2(VIEW_SIZE.x / 2.0, FEET_FROM_TOP) * zoom
	sprite.scale = Vector2.ONE / zoom
	add_child(sprite)
	return true


## Godot's Collada importer keeps each mesh's bone weights but drops its bind poses, so the
## meshes come in rigid and the animation moves nothing. This rebuilds every mesh's Skin
## from the bind poses tools/extract_data.py saved.
func _bind_meshes() -> void:
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	var skins: Variant = JSON.parse_string(FileAccess.get_file_as_string(SKINS_PATH)) if FileAccess.file_exists(SKINS_PATH) else null
	if skeleton == null or not skins is Dictionary:
		push_error("Avatar: %s is missing, so the model cannot animate. Run: python3 tools/extract_data.py" % SKINS_PATH)
		return
	for mesh: MeshInstance3D in _meshes():
		if not skins.has(String(mesh.name)):
			continue
		var skin := Skin.new()
		# The meshes index bones by their place in the skeleton, so bind i must be bone i.
		for bone in skeleton.get_bone_count():
			skin.add_bind(bone, Transform3D.IDENTITY)
		for bind: Dictionary in skins[String(mesh.name)]:
			var bone := skeleton.find_bone(bind["bone"])
			if bone >= 0:
				skin.set_bind_pose(bone, Transform3D(
					Basis(_vector(bind["x"]), _vector(bind["y"]), _vector(bind["z"])), _vector(bind["origin"])))
		mesh.skin = skin
		mesh.skeleton = mesh.get_path_to(skeleton)


static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


func _meshes() -> Array[Node]:
	return _model.find_children("*", "MeshInstance3D", true, false)


func _set_object_visible(object_name: String, shown: bool) -> void:
	# The bucket is a plain node holding its mesh; everything else is the mesh itself.
	var node := _model.find_child(object_name, true, false)
	if node is Node3D:
		node.visible = shown


## Avatar3D.refreshObjects: hide every wearable mesh, then show the ones the items name.
func _show_objects(configs: Array[Dictionary]) -> void:
	for mesh in _meshes():
		if CUSTOMISABLE_PREFIXES.any(func(prefix: String) -> bool: return mesh.name.begins_with(prefix)):
			mesh.visible = false
	for entry in configs:
		var objects: String = entry["config"].get("object", "")
		for object_name in objects.to_lower().split(",", false):
			_set_object_visible(object_name.strip_edges(), true)


## Avatar3D.sortItemsByPriority: ascending, and among equals the later item goes first.
static func sort_by_priority(configs: Array[Dictionary]) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = []
	for entry in configs:
		var index := 0
		while index < sorted.size() and entry["priority"] > sorted[index]["priority"]:
			index += 1
		sorted.insert(index, entry)
	return sorted


## Avatar3D.constructTextureBitmapData: skin colour, then each item's texture piece on top.
func _build_texture(configs: Array[Dictionary], skin_colour: Color) -> ImageTexture:
	var size := int(TEXTURE_SIZE * _sprites.zoom())
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(skin_colour)
	for entry in sort_by_priority(configs):
		var piece_name: Variant = entry["config"].get("texture")
		if piece_name == null or piece_name == "":
			continue
		var piece := _sprites.make_image(piece_name)
		if piece != null:
			var top_left := Vector2i((-_sprites.origin(piece_name)).round())
			image.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), top_left)
	return ImageTexture.create_from_image(image)


func _apply_materials(body_texture: ImageTexture, hair_colour: Color) -> void:
	var body := StandardMaterial3D.new()
	body.albedo_texture = body_texture
	var hair := StandardMaterial3D.new()
	hair.albedo_color = hair_colour
	for mesh: MeshInstance3D in _meshes():
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			var material_name := original.resource_name if original != null else ""
			if material_name == BODY_MATERIAL:
				mesh.set_surface_override_material(surface, body)
			elif material_name == HAIR_MATERIAL:
				mesh.set_surface_override_material(surface, hair)
