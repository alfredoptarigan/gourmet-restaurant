class_name RoomForms
extends RefCounted
## The small forms over the restaurant: what the HUD buttons and clickable furniture open,
## and what happens when the player presses Done. The restaurant keeps the state.

var room: RestaurantRoom


func _init(restaurant_room: RestaurantRoom) -> void:
	room = restaurant_room


## Clicking a jukebox or stereo picks the music. More music is sold in the Decorate shop.
func choose_music() -> ChoicePanel:
	var choices := room.music_choices()
	var panel: ChoicePanel = room.hud.open_choices("Music", [{
		"label": "Play",
		"options": choices.map(func(music: Dictionary) -> String: return music.get("name", "")),
		"selected": maxi(0, choices.find(room.playing_music())),
	}])
	panel.chosen.connect(func(selections: Array[int]) -> void:
		if selections[0] >= 0 and selections[0] < choices.size():
			room.set_music(int(choices[selections[0]]["id"])))
	return panel


## The achievement panel on the wall shows how far the player has got with each award.
func open_awards() -> void:
	if not Api.is_signed_in():
		room.hud.show_message("Sign in to win awards.")
		return
	var result := await Api.fetch_awards()
	if not result["ok"]:
		room.hud.show_message(result["error"])
		return
	show_awards(result["data"].get("progress", {}))


func show_awards(progress: Dictionary) -> ChoicePanel:
	var rows: Array = []
	for award: int in Awards.TABLE:
		rows.append({"label": Awards.TABLE[award][0], "options": [Awards.describe(award, int(progress.get(str(award), 0)))], "selected": 0})
	return room.hud.open_choices("Awards", rows)


func ask_quiz(quiz: Dictionary) -> ChoicePanel:
	Tips.show_once(room.hud, "TutorialQuiz1")
	var reward: String = GameData.ingredient_items.get_item_by_id(int(quiz.get("rewardIngredientId", 0))).get("name", "an ingredient")
	var panel: ChoicePanel = room.hud.open_choices("Daily quiz: answer right to win %s" % reward, [
		{"label": quiz.get("question", ""), "options": quiz.get("choices", []), "selected": 0}])
	panel.chosen.connect(func(selections: Array[int]) -> void: _on_quiz_answered(selections[0], quiz))
	return panel


func _on_quiz_answered(choice: int, quiz: Dictionary) -> void:
	var result := await Api.answer_quiz(choice)
	if not result["ok"]:
		room.hud.show_message(result["error"])
		return
	if result["data"].get("correct") == true:
		var won := int(result["data"].get("rewardIngredientId", 0))
		room.ingredients[won] = room.ingredients.get(won, 0) + 1
		room.hud.show_message("Right! You won %s." % GameData.ingredient_items.get_item_by_id(won).get("name", "an ingredient"))
	else:
		var choices: Array = quiz.get("choices", [])
		var correct := int(result["data"].get("correctChoice", 0))
		room.hud.show_message("Not quite: it was %s." % (choices[correct] if correct < choices.size() else "another answer"))


static func describe_reward(reward: Dictionary) -> String:
	var database: ItemDatabase = {"ingredient": GameData.ingredient_items, "recipe": GameData.recipe_items}.get(reward.get("kind"), GameData.interior_items)
	return "%s (%s)" % [database.get_item_by_id(int(reward.get("id", 0))).get("name", "?"), reward.get("kind", "item")]


## FoodKingPopUp: finding Greg lets the player pick one of his rewards.
func choose_food_king_reward() -> ChoicePanel:
	var panel: ChoicePanel = room.hud.open_choices("You found the Food King! Pick a reward", [
		{"label": "Reward", "options": room.food_king_rewards.map(describe_reward), "selected": 0}])
	panel.chosen.connect(func(selections: Array[int]) -> void: _claim_food_king(selections[0]))
	return panel


func _claim_food_king(choice: int) -> void:
	var result := await Api.claim_food_king(choice)
	if not result["ok"]:
		room.hud.show_message(result["error"])
		return
	var reward: Dictionary = result["data"].get("reward", {})
	match reward.get("kind"):
		"ingredient":
			room.ingredients[int(reward["id"])] = room.ingredients.get(int(reward["id"]), 0) + 1
		"recipe":
			if not room.known_recipes.has(int(reward["id"])):
				room.known_recipes[int(reward["id"])] = 1
	room.hud.show_message("The Food King gave you %s." % describe_reward(reward))
	room.food_king_tile = Vector2i(-1, -1)
	if room._food_king_sprite != null:
		room._food_king_sprite.queue_free()
		room._food_king_sprite = null


func choose_menu() -> ChoicePanel:
	var rows: Array = []
	for course in RestaurantPlay.courses_for(room.level):
		var recipes := room.menu_choices(course)
		rows.append({
			"label": course,
			"options": recipes.map(func(recipe: Dictionary) -> String: return recipe.get("name", "")),
			"selected": maxi(0, recipes.find(room.recipe_for(course))),
		})
	var panel: ChoicePanel = room.hud.open_choices("Menu", rows)
	panel.chosen.connect(_on_menu_chosen)
	return panel


func _on_menu_chosen(selections: Array[int]) -> void:
	var courses := RestaurantPlay.courses_for(room.level)
	var picked := room.menu.duplicate()
	for index in mini(courses.size(), selections.size()):
		var recipes := room.menu_choices(courses[index])
		if selections[index] >= 0 and selections[index] < recipes.size():
			picked[courses[index]] = int(recipes[selections[index]]["id"])
	room.menu = picked
	room._save(RestaurantRoom.MENU_KEY, room.menu)


## ponytail: the staff are the game's own characters. The original has the player hire
## friends (WorldHire), which needs a friends list this game does not have.
func choose_staff() -> ChoicePanel:
	var staff := room.staff_jobs()
	var rows: Array = []
	for index in staff.size():
		var percent := roundi(room.energy[index] / RestaurantPlay.MAX_WORK_TIME * 100.0) if index < room.energy.size() else 100
		rows.append({"label": "Employee %d (%d%% energy)" % [index + 1, percent], "options": RestaurantRoom.JOB_NAMES, "selected": staff[index]})
	# WorldHire: every employee but the first (the player) can be a friend.
	var names: Array = ["A stranger"] + room.friends.map(func(friend: Dictionary) -> String: return friend["username"])
	if not room.friends.is_empty():
		for index in range(1, staff.size()):
			var friend_id := room.hired[index] if index < room.hired.size() else 0
			var hired_at := room.friends.map(func(friend: Dictionary) -> int: return int(friend["id"])).find(friend_id)
			rows.append({"label": "Employee %d is" % (index + 1), "options": names, "selected": hired_at + 1})
	var panel: ChoicePanel = room.hud.open_choices("Staff", rows)
	panel.chosen.connect(_on_staff_chosen)
	return panel


## New jobs take effect at once: the restaurant closes and reopens with the new staff.
func _on_staff_chosen(selections: Array[int]) -> void:
	var staff_count := room.staff_jobs().size()
	room.jobs = selections.slice(0, staff_count)
	if selections.size() > staff_count:
		var hired: Array[int] = [0]
		for choice in selections.slice(staff_count):
			hired.append(int(room.friends[choice - 1]["id"]) if choice > 0 and choice <= room.friends.size() else 0)
		room.hired = hired
		room._save(RestaurantRoom.HIRED_KEY, room.hired)
	room._reopen()
	room._save(RestaurantRoom.JOBS_KEY, room.jobs)
	room._save_energy()


## ponytail: a form of drop-downs with no preview, and every item is free to wear. The
## original has a dressing room that sells clothes (WorldCustomiseAvatar).
func choose_avatar() -> ChoicePanel:
	var rows: Array = []
	for group_name in RestaurantPlay.LOOK_GROUPS:
		var names: Array = RestaurantPlay.wearable(group_name).map(func(item: Dictionary) -> String: return item.get("name", ""))
		rows.append({"label": group_name, "options": names, "selected": maxi(0, names.find(room.look.get("items", {}).get(group_name)))})
	rows.append({"label": "Skin", "options": RestaurantPlay.SKIN_COLOUR_NAMES, "selected": room.look.get("skin", 0)})
	rows.append({"label": "Hair colour", "options": RestaurantPlay.HAIR_COLOUR_NAMES, "selected": room.look.get("hair", 0)})
	var panel: ChoicePanel = room.hud.open_choices("Avatar (worn by your first employee)", rows)
	panel.chosen.connect(_on_avatar_chosen)
	return panel


func _on_avatar_chosen(selections: Array[int]) -> void:
	var groups := RestaurantPlay.LOOK_GROUPS
	var items := {}
	for index in groups.size():
		var choices := RestaurantPlay.wearable(groups[index])
		if selections[index] < 0 or selections[index] >= choices.size():
			return
		items[groups[index]] = choices[selections[index]]["name"]
	room.look = ProfileRules.valid_look({"items": items, "skin": selections[groups.size()], "hair": selections[groups.size() + 1]})
	room._reopen()
	room._save(RestaurantRoom.AVATAR_KEY, room.look)


## How a recipe reads in the form: its level and what the next one takes, with what is held.
func describe_recipe(recipe: Dictionary) -> String:
	var level := int(room.known_recipes.get(int(recipe["id"]), 0))
	var parts: Array = []
	var needed := ProfileRules.ingredients_of(recipe)
	for ingredient_id: int in needed:
		var name: String = GameData.ingredient_items.get_item_by_id(ingredient_id).get("name", "?")
		parts.append("%s %d/%d" % [name, room.ingredients.get(ingredient_id, 0), needed[ingredient_id]])
	var standing := "%s (level %d)" % [RestaurantRoom.RECIPE_LEVEL_NAMES[level - 1], level] if level > 0 else "not learned"
	return "%s, %s; needs %s" % [recipe.get("name", ""), standing, ", ".join(parts)]


## WorldRecipeMenu and the ingredient market in one form: pick a recipe to learn or improve,
## or an ingredient to buy, or both.
## ponytail: drop-downs with no pictures; the original is a cookbook with a page per course.
func choose_recipe() -> ChoicePanel:
	Tips.show_once(room.hud, "TutorialRecipeMenu2")
	var recipes: Array = room.learnable_recipes()
	var market: Array = room.market_ingredients()
	var panel: ChoicePanel = room.hud.open_choices("Recipes", [
		{"label": "Learn or improve", "options": ["(nothing)"] + recipes.map(describe_recipe), "selected": 0},
		{"label": "Buy an ingredient", "options": ["(nothing)"] + market.map(func(ingredient: Dictionary) -> String:
			var coins := RestaurantRoom.ingredient_coin_price(ingredient)
			var price := "%d coins" % coins if coins > 0 else "%s cash" % ingredient.get("cash", "?")
			return "%s, %s (have %d)" % [ingredient.get("name", ""), price, room.ingredients.get(int(ingredient["id"]), 0)]),
			"selected": 0},
	])
	panel.chosen.connect(func(selections: Array[int]) -> void: _on_recipe_chosen(selections, recipes, market))
	return panel


func _on_recipe_chosen(selections: Array[int], recipes: Array, market: Array) -> void:
	if selections[0] <= 0 and selections[1] <= 0:
		return
	if not Api.is_signed_in():
		room.hud.show_message("Sign in to learn recipes and buy ingredients.")
		return
	if selections[1] > 0 and selections[1] <= market.size():
		var ingredient: Dictionary = market[selections[1] - 1]
		var for_cash := RestaurantRoom.ingredient_coin_price(ingredient) == 0
		var bought := await Api.buy_ingredient(int(ingredient["id"]), "cash" if for_cash else "coins")
		if not bought["ok"]:
			room.hud.show_message(bought["error"])
			return
		room.ingredients[int(ingredient["id"])] = int(bought["data"].get("quantity", 1))
		if for_cash:
			room.set_confirmed_cash(int(bought["data"].get("cash", 0)))
		else:
			room.set_confirmed_coins(int(bought["data"].get("coins", 0)))
	if selections[0] > 0 and selections[0] <= recipes.size():
		var recipe: Dictionary = recipes[selections[0] - 1]
		var learned := await Api.learn_recipe(int(recipe["id"]))
		if not learned["ok"]:
			room.hud.show_message(learned["error"])
			return
		room._take_kitchen(learned["data"])
		room.set_confirmed_coins(int(learned["data"].get("coins", 0)))
		if room._sync != null:
			room._sync.set_confirmed_points(int(learned["data"].get("gourmetPoints", 0)))
		room.hud.show_message("%s is now %s." % [recipe.get("name", ""), RestaurantRoom.RECIPE_LEVEL_NAMES[int(learned["data"].get("level", 1)) - 1]])


## What can be done with a plot, for the garden form: the first is always to leave it be.
static func plot_actions(plot: Dictionary) -> Array[String]:
	if plot.is_empty():
		return [RestaurantRoom.GARDEN_LEAVE, "Plant a seed (%d coins)" % RestaurantRoom.SEED_COST]
	if plot.get("ripe") == true:
		return [RestaurantRoom.GARDEN_LEAVE, "Harvest"]
	return [RestaurantRoom.GARDEN_LEAVE, "Water"]


static func describe_plot(index: int, plot: Dictionary) -> String:
	if plot.is_empty():
		return "Plot %d: empty" % (index + 1)
	var plant: String = GameData.ingredient_items.get_item_by_id(int(plot.get("ingredientId", 0))).get("name", "?")
	return "Plot %d: %s, %d of %d wet hours, soil wet for %.1f h" % [
		index + 1, plant, int(plot.get("grownSeconds", 0)) / 3600, RestaurantRoom.GROW_HOURS, float(plot.get("wetSeconds", 0)) / 3600.0]


## GardenPlot and GardenPlotActor as a form: one row per plot the level has.
## ponytail: plots are rows in a form, not beds drawn beside the restaurant, and a friend
## cannot water them yet.
func open_garden() -> void:
	if not Api.is_signed_in():
		room.hud.show_message("Sign in to garden.")
		return
	var result := await Api.fetch_garden()
	if not result["ok"]:
		room.hud.show_message(result["error"])
		return
	var garden: Dictionary = result["data"]
	if int(garden.get("plotCount", 0)) == 0:
		room.hud.show_message("Your first garden plot opens at level 7.")
		return
	choose_garden(garden)


func choose_garden(garden: Dictionary) -> ChoicePanel:
	Tips.show_once(room.hud, "TutorialGardenPlot")
	var plots := {}
	for plot: Dictionary in garden.get("plots", []):
		plots[int(plot.get("plot", -1))] = plot
	var rows: Array = []
	for index in int(garden.get("plotCount", 0)):
		rows.append({"label": describe_plot(index, plots.get(index, {})), "options": plot_actions(plots.get(index, {})), "selected": 0})
	var panel: ChoicePanel = room.hud.open_choices("Garden", rows)
	panel.chosen.connect(func(selections: Array[int]) -> void: _on_garden_chosen(selections, plots))
	return panel


func _on_garden_chosen(selections: Array[int], plots: Dictionary) -> void:
	for index in selections.size():
		if selections[index] <= 0:
			continue
		var plot: Dictionary = plots.get(index, {})
		var action := "plant" if plot.is_empty() else ("harvest" if plot.get("ripe") == true else "water")
		var result := await Api.tend_plot(action, index)
		if not result["ok"]:
			room.hud.show_message(result["error"])
			return
		if result["data"].get("coins") is float:
			room.set_confirmed_coins(int(result["data"]["coins"]))
		if action == "harvest":
			var harvested := int(result["data"].get("ingredientId", 0))
			room.ingredients[harvested] = room.ingredients.get(harvested, 0) + 1
			room.hud.show_message("You harvested %s." % GameData.ingredient_items.get_item_by_id(harvested).get("name", "?"))


static func describe_perk(perk: Dictionary) -> String:
	return "%s, %s coins: %s" % [perk.get("name", ""), perk.get("cost", "?"), perk.get("text", "")]


## The perk shop: food for one employee, and help for the whole restaurant.
func choose_food() -> ChoicePanel:
	var staff: Array = []
	for index in room.energy.size():
		staff.append("Employee %d (%d%% energy)" % [index + 1, roundi(room.energy[index] / RestaurantPlay.MAX_WORK_TIME * 100.0)])
	var foods: Array = [RestaurantRoom.NOTHING] + GameData.perk_items.get_items(RestaurantRoom.STAFF_FOOD_GROUP).map(describe_perk)
	var helps: Array = [RestaurantRoom.NOTHING] + GameData.perk_items.get_items(RestaurantRoom.RESTAURANT_PERK_GROUP).map(describe_perk)
	var panel: ChoicePanel = room.hud.open_choices("Perks", [
		{"label": "Feed", "options": staff, "selected": 0},
		{"label": "Food", "options": foods, "selected": 0},
		{"label": "For the restaurant", "options": helps, "selected": 0},
	])
	panel.chosen.connect(_on_food_chosen)
	return panel


func _on_food_chosen(selections: Array[int]) -> void:
	var foods := GameData.perk_items.get_items(RestaurantRoom.STAFF_FOOD_GROUP)
	var helps := GameData.perk_items.get_items(RestaurantRoom.RESTAURANT_PERK_GROUP)
	var food: Dictionary = foods[selections[1] - 1] if selections[1] > 0 and selections[1] <= foods.size() else {}
	var help: Dictionary = helps[selections[2] - 1] if selections[2] > 0 and selections[2] <= helps.size() else {}
	if food.is_empty() and help.is_empty():
		return
	if not Api.is_signed_in():
		room.hud.show_message("Sign in to buy perks.")
		return
	if not food.is_empty() and selections[0] >= 0 and selections[0] < room.energy.size():
		var fed := await Api.use_item(int(food["id"]))
		if not fed["ok"]:
			room.hud.show_message(fed["error"])
			return
		room.set_confirmed_coins(int(fed["data"].get("coins", 0)))
		room.give_energy(selections[0], float(food.get("workTime", 0)))
		room._save_energy()
	if not help.is_empty():
		var helped := await Api.use_item(int(help["id"]))
		if not helped["ok"]:
			room.hud.show_message(helped["error"])
			return
		room.set_confirmed_coins(int(helped["data"].get("coins", 0)))
		room._take_perks({"ok": true, "data": {"perks": helped["data"].get("perks", {})}})
		room.hud.show_message("%s is working for your restaurant." % help.get("name", ""))


## The money bags (CoinsToPfCash) turn cash into coins.
## ponytail: cash cannot be bought yet; the server answers 501 until Stripe is set up.
func choose_cash() -> ChoicePanel:
	var bags: Array = GameData.interior_items.get_items("CoinsToPfCash")
	var panel: ChoicePanel = room.hud.open_choices("Cash: %d" % int(Api.profile.get("cash", 0)), [
		{"label": "Exchange for coins", "options": [RestaurantRoom.NOTHING] + bags.map(func(bag: Dictionary) -> String:
			return "%s: %s cash for %s coins" % [bag.get("name", ""), bag.get("cash", "?"), bag.get("cost", "?")]), "selected": 0},
		{"label": "Buy cash", "options": ["Coming soon"], "selected": 0},
	])
	panel.chosen.connect(func(selections: Array[int]) -> void:
		if selections[0] <= 0 or selections[0] > bags.size():
			return
		if not Api.is_signed_in():
			room.hud.show_message("Sign in to use cash.")
			return
		var exchanged := await Api.exchange_cash(int(bags[selections[0] - 1]["id"]))
		if not exchanged["ok"]:
			room.hud.show_message(exchanged["error"])
			return
		room.set_confirmed_cash(int(exchanged["data"].get("cash", 0)))
		room.set_confirmed_coins(int(exchanged["data"].get("coins", 0))))
	return panel
