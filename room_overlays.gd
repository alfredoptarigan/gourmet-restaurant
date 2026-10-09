class_name RoomOverlays
extends RefCounted
## What is drawn over the restaurant's furniture while it is open: dishes on tables, chair
## backs over seated customers, emotion bubbles, broken-item marks, and trash. The
## simulation only tracks state; this keeps the sprites in step with it every frame.

var room: RestaurantRoom
## Order -> the dish sprite on its table.
var dish_sprites: Dictionary = {}
## Chair -> the backrest drawn over whoever sits on it.
var chair_overlays: Dictionary = {}
## Broken item -> the sprites that mark it as broken.
var broken_marks: Dictionary = {}
## Tile -> the sprite of the trash lying there.
var trash_sprites: Dictionary = {}


func _init(restaurant_room: RestaurantRoom) -> void:
	room = restaurant_room


func sync() -> void:
	sync_dishes()
	sync_chair_overlays()
	sync_emotions()
	sync_broken_marks()
	sync_trash()


## The restaurant closed: its dishes and seated customers are gone.
func clear_service() -> void:
	for sprite: Sprite2D in dish_sprites.values() + chair_overlays.values():
		sprite.queue_free()
	dish_sprites.clear()
	chair_overlays.clear()


## Keeps one dish sprite on every table that has a served order, showing how much is eaten.
## The simulation only tracks the order; this draws it (DishOrder was an AnimatedObject).
func sync_dishes() -> void:
	var on_tables := {}
	for table in room.items_of_type(RestaurantRoom.TABLE_TYPE):
		var order := table.table_top_order
		if order == null or not order.served:
			continue
		var sprite_name: String = order.recipe.get("className", "")
		on_tables[order] = true
		var dish: Sprite2D = dish_sprites.get(order)
		if dish == null:
			if not room._game_sprites.has_sprite(sprite_name):
				continue
			dish = room._game_sprites.make_sprite(sprite_name)
			dish.position = RoomGrid.tile_center(table.tile) - Vector2(0, table.top_height)
			dish.z_index = table.sprite.z_index + RestaurantRoom.OVER_ACTOR
			room.item_layer.add_child(dish)
			dish_sprites[order] = dish
		# The dish's timeline runs from a full plate to an empty one.
		dish.frame = roundi(order.eaten * (room._game_sprites.frame_count(sprite_name) - 1))
	for order: DishOrder in dish_sprites.keys():
		if not on_tables.has(order):
			dish_sprites[order].queue_free()
			dish_sprites.erase(order)


## Draws a chair's backrest over whoever sits on it (Customer.sitOnChair's chairOverlay).
func sync_chair_overlays() -> void:
	for chair in room.items_of_type(RestaurantRoom.CHAIR_TYPE):
		var seated := chair.occupant != null and chair.occupant.is_seated()
		var overlay: Sprite2D = chair_overlays.get(chair)
		if seated and overlay == null:
			var sprite_name: String = chair.config.get("className", "") + RestaurantRoom.CHAIR_OVERLAY_SUFFIX
			if not room._sprites.has_sprite(sprite_name):
				continue
			overlay = room._place(room.item_layer, sprite_name, chair.tile, chair.rotation)
			overlay.z_index = chair.sprite.z_index + RestaurantRoom.OVER_ACTOR
			chair_overlays[chair] = overlay
		elif not seated and overlay != null:
			overlay.queue_free()
			chair_overlays.erase(chair)


## Shows what a customer is unhappy about, as the original's bubble over their head.
func sync_emotions() -> void:
	for customer in room.play.customers:
		var bubble: Sprite2D = customer.get_node_or_null(RestaurantRoom.EMOTION_NODE)
		if customer.emotion == Customer.Emotion.NONE:
			if bubble != null:
				bubble.free()
			continue
		if bubble == null:
			bubble = room._game_sprites.make_sprite(RestaurantRoom.EMOTION_SPRITE)
			if bubble == null:
				continue
			bubble.name = RestaurantRoom.EMOTION_NODE
			bubble.position = RestaurantRoom.EMOTION_OFFSET
			customer.add_child(bubble)
		bubble.frame = customer.emotion


## Marks broken toilets and arcade machines until someone repairs them
## (WorldRestaurantPlay.setRoomItemUsageCount).
## ponytail: the "cleaner needed" sign is its first frame, not the original's animation, and
## a broken arcade machine keeps its working look: flat sheets do not carry its "broken" clip.
func sync_broken_marks() -> void:
	for item: RoomItem in broken_marks.keys():
		if item not in room.items or not item.is_broken():
			for mark: Sprite2D in broken_marks[item]:
				mark.queue_free()
			broken_marks.erase(item)
	for item in room.items:
		if not item.is_broken() or broken_marks.has(item):
			continue
		var marks: Array[Sprite2D] = []
		if item.has_type(RestaurantPlay.TOILET_TYPE) and room._sprites.has_sprite(RestaurantRoom.TOILET_WATER_SPRITE):
			var water := room._place(room.item_layer, RestaurantRoom.TOILET_WATER_SPRITE, item.tile, 0)
			water.z_index = item.sprite.z_index - 1
			marks.append(water)
		var sign_sprite := room._game_sprites.make_sprite(RestaurantRoom.CLEANER_NEEDED_SPRITE)
		if sign_sprite != null:
			sign_sprite.position = RoomGrid.tile_to_screen(item.tile) - Vector2(0, RoomGrid.TILE_HEIGHT)
			sign_sprite.z_index = item.sprite.z_index + RestaurantRoom.OVER_ACTOR
			room.item_layer.add_child(sign_sprite)
			marks.append(sign_sprite)
		broken_marks[item] = marks


## Draws the trash lying on the floor.
func sync_trash() -> void:
	for tile: Vector2i in trash_sprites.keys():
		if not room.trash.has(tile):
			trash_sprites[tile].queue_free()
			trash_sprites.erase(tile)
	for tile: Vector2i in room.trash:
		if trash_sprites.has(tile):
			continue
		var sprite := room._sprites.make_sprite(room.trash[tile])
		if sprite == null:
			continue
		sprite.position = RoomGrid.tile_center(tile)
		sprite.z_index = RoomGrid.tile_draw_order(tile) * RoomActor.DRAW_ORDER_STEP
		room.item_layer.add_child(sprite)
		trash_sprites[tile] = sprite
