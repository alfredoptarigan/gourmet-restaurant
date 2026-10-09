class_name ProfileRules
extends RefCounted
## Checks on what comes back from the server's profile data before the game uses it, and
## the small rules that go with it. Anything malformed is treated as missing.


## Saved jobs as the game can use them: empty unless every entry is a known job.
## With `jobs_only` false it checks a list of whole numbers instead (the hired friends' ids).
static func valid_jobs(saved: Variant, jobs_only: bool = true) -> Array[int]:
	var checked: Array[int] = []
	if not saved is Array:
		return checked
	for entry: Variant in saved:
		if not (entry is float or entry is int) or (jobs_only and int(entry) not in RestaurantPlay.Job.values()):
			return []
		checked.append(int(entry))
	return checked


## Saved energy as it stands `now` (unix seconds): every employee kept working or resting
## while the player was away. Empty unless the save is well-formed.
static func rested_energy(saved: Variant, staff_jobs: Array[int], now: float) -> Array[float]:
	var left: Array[float] = []
	if not saved is Dictionary or not saved.get("left") is Array or not saved.get("at") is float:
		return left
	for entry: Variant in saved["left"]:
		if not (entry is float or entry is int):
			return []
		left.append(clampf(entry, 0.0, RestaurantPlay.MAX_WORK_TIME))
	var working: Array[int] = staff_jobs.duplicate()
	while working.size() < left.size():
		working.append(RestaurantPlay.Job.WAITER)
	RestaurantPlay.spend_energy(left, working, maxf(0.0, now - float(saved["at"])))
	return left


## A saved look as the game can use it: empty unless every part of it is something wearable.
static func valid_look(saved: Variant) -> Dictionary:
	if not saved is Dictionary or not saved.get("items") is Dictionary:
		return {}
	var items := {}
	for group_name in RestaurantPlay.LOOK_GROUPS:
		var item_name: Variant = saved["items"].get(group_name)
		var known := RestaurantPlay.wearable(group_name).any(func(item: Dictionary) -> bool: return item.get("name") == item_name)
		if not item_name is String or not known:
			return {}
		items[group_name] = item_name
	var colours := {}
	for part: Array in [["skin", RestaurantPlay.SKIN_COLOURS.size()], ["hair", RestaurantPlay.HAIR_COLOURS.size()]]:
		var index: Variant = saved.get(part[0])
		if not (index is float or index is int) or int(index) < 0 or int(index) >= part[1]:
			return {}
		colours[part[0]] = int(index)
	return {"items": items, "skin": colours["skin"], "hair": colours["hair"]}


## A saved menu as the game can use it: only courses whose recipe really is of that course.
static func valid_menu(saved: Variant) -> Dictionary:
	var checked := {}
	if not saved is Dictionary:
		return checked
	for course in RestaurantPlay.MENU_GROUPS:
		var recipe_id: Variant = saved.get(course)
		if (recipe_id is float or recipe_id is int) and GameData.recipe_items.get_group_name_by_id(int(recipe_id)) == course:
			checked[course] = int(recipe_id)
	return checked


## The outdoor area the player has: the biggest of the sizes they own (item id -> quantity),
## or zero when they own none.
static func best_outside_size(owned: Dictionary) -> Vector2i:
	var best := {}
	for area: Dictionary in GameData.interior_items.get_items(RestaurantRoom.OUTSIDE_GROUP):
		if int(owned.get(int(area["id"]), 0)) > 0 and (best.is_empty() or int(area["sizeX"]) > int(best["sizeX"])):
			best = area
	return Vector2i(int(best["sizeX"]), int(best["sizeY"])) if not best.is_empty() else Vector2i.ZERO


## Recipe's constructor: ingredient id -> how many one level of the recipe takes.
static func ingredients_of(recipe: Dictionary) -> Dictionary:
	var needed := {}
	for ingredient_name: String in str(recipe.get("ingredients", "")).split(","):
		var ingredient := GameData.ingredient_items.get_item_from_group(ingredient_name.strip_edges(), RestaurantRoom.INGREDIENT_GROUP)
		if not ingredient.is_empty():
			needed[int(ingredient["id"])] = needed.get(int(ingredient["id"]), 0) + 1
	return needed
