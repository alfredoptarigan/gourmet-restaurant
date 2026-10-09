class_name RoomSocial
extends RefCounted
## Friends in the restaurant: the friends form, mail in the letter box, and visiting a
## friend's restaurant. The server keeps the friendships (server/src/social.ts).

const LEAVE := "Leave it"
const FRIEND_ACTIONS: Array[String] = [LEAVE, "Visit", "Send a free gift", "Send an ingredient", "Send a message", "Remove"]
const REQUEST_ACTIONS: Array[String] = [LEAVE, "Accept", "Decline"]
const MAIL_ACTIONS: Array[String] = [LEAVE, "Open"]
const QUIZ_ACTIONS: Array[String] = ["Later", "Answer it"]
const RESTAURANT_SCENE := "res://restaurant_room.tscn"

var room: RestaurantRoom


func _init(restaurant_room: RestaurantRoom) -> void:
	room = restaurant_room


## The friends list from the server, keeping only well-formed entries.
static func valid_friends(saved: Variant) -> Array:
	if not saved is Array:
		return []
	return saved.filter(func(friend: Variant) -> bool:
		return friend is Dictionary and (friend.get("id") is float or friend.get("id") is int) and friend.get("username") is String)


## Opens a friend's restaurant: fetches it, then reloads the restaurant scene as a visitor.
static func visit_friend(tree: SceneTree, friend_id: int) -> String:
	var result := await Api.fetch_friend_restaurant(friend_id)
	if not result["ok"]:
		return result["error"]
	Api.visiting = result["data"]
	tree.change_scene_to_file(RESTAURANT_SCENE)
	return ""


static func describe_mail(mail: Dictionary) -> String:
	var sender: String = mail.get("from") if mail.get("from") is String else "Someone"
	match mail.get("kind"):
		"gift", "ingredient":
			var ingredient: String = GameData.ingredient_items.get_item_by_id(int(mail.get("itemId", 0))).get("name", "an ingredient")
			return "%s sent you %s" % [sender, ingredient]
	return "%s says: %s" % [sender, mail.get("text", "")]


func open_friends() -> void:
	if not Api.is_signed_in():
		room.hud.show_message("Sign in to have friends.")
		return
	var result := await Api.fetch_friends()
	if not result["ok"]:
		room.hud.show_message(result["error"])
		return
	choose_friends(result["data"])


func choose_friends(data: Dictionary) -> ChoicePanel:
	var incoming := valid_friends(data.get("incoming"))
	var friends := valid_friends(data.get("friends"))
	var rows: Array = [{"label": "Add a friend by name", "text": ""}]
	for request: Dictionary in incoming:
		rows.append({"label": "%s wants to be friends" % request["username"], "options": REQUEST_ACTIONS, "selected": 0})
	for friend: Dictionary in friends:
		rows.append({"label": "%s (level %d)" % [friend["username"], int(friend.get("level", 1))], "options": FRIEND_ACTIONS, "selected": 0})
	var panel: ChoicePanel = room.hud.open_choices("Friends", rows)
	panel.chosen.connect(func(selections: Array[int]) -> void: _on_friends_chosen(selections, panel.text_of(0), incoming, friends))
	return panel


func _on_friends_chosen(selections: Array[int], new_friend: String, incoming: Array, friends: Array) -> void:
	if not new_friend.strip_edges().is_empty():
		var asked := await Api.request_friend(new_friend.strip_edges())
		room.hud.show_message(asked["error"] if not asked["ok"] else (
			"You are now friends." if asked["data"].get("status") == "friends" else "Request sent."))
	for index in incoming.size():
		var friend_id := int(incoming[index]["id"])
		match selections[1 + index]:
			1:
				await Api.accept_friend(friend_id)
			2:
				await Api.remove_friend(friend_id)
	var visit_id := 0
	for index in friends.size():
		var friend: Dictionary = friends[index]
		var friend_id := int(friend["id"])
		match selections[1 + incoming.size() + index]:
			1:
				visit_id = friend_id
			2:
				var gift := await Api.send_mail(friend_id, "gift")
				room.hud.show_message(gift["error"] if not gift["ok"] else "Gift sent to %s." % friend["username"])
			3:
				choose_ingredient_for(friend)
			4:
				choose_message_for(friend)
			5:
				await Api.remove_friend(friend_id)
	if visit_id != 0:
		var error := await visit_friend(room.get_tree(), visit_id)
		if not error.is_empty():
			room.hud.show_message(error)


## A trade: one of the player's own ingredients goes to the friend.
func choose_ingredient_for(friend: Dictionary) -> ChoicePanel:
	var held: Array = room.ingredients.keys().filter(func(ingredient_id: int) -> bool: return room.ingredients[ingredient_id] > 0)
	var names: Array = held.map(func(ingredient_id: int) -> String:
		return "%s (have %d)" % [GameData.ingredient_items.get_item_by_id(ingredient_id).get("name", "?"), room.ingredients[ingredient_id]])
	var panel: ChoicePanel = room.hud.open_choices("Send %s an ingredient" % friend["username"], [{"label": "Ingredient", "options": names, "selected": 0}])
	panel.chosen.connect(func(selections: Array[int]) -> void:
		if selections[0] < 0 or selections[0] >= held.size():
			return
		var sent := await Api.send_mail(int(friend["id"]), "ingredient", held[selections[0]])
		if sent["ok"]:
			room.ingredients[held[selections[0]]] -= 1
		room.hud.show_message(sent["error"] if not sent["ok"] else "Sent to %s." % friend["username"]))
	return panel


func choose_message_for(friend: Dictionary) -> ChoicePanel:
	var panel: ChoicePanel = room.hud.open_choices("Write to %s" % friend["username"], [{"label": "Message", "text": ""}])
	panel.chosen.connect(func(_selections: Array[int]) -> void:
		var text := panel.text_of(0).strip_edges()
		if text.is_empty():
			return
		var sent := await Api.send_mail(int(friend["id"]), "message", 0, text)
		room.hud.show_message(sent["error"] if not sent["ok"] else "Message sent."))
	return panel


## The letter box: mail from friends, and the daily quiz if it is still to be answered.
func open_mailbox() -> void:
	if not Api.is_signed_in():
		room.hud.show_message("Sign in to get mail.")
		return
	var mail := await Api.fetch_mail()
	var quiz := await Api.fetch_quiz()
	var letters: Array = mail["data"].get("mail", []) if mail["ok"] else []
	var open_quiz: Dictionary = quiz["data"] if quiz["ok"] and quiz["data"].get("answered") != true else {}
	if letters.is_empty() and open_quiz.is_empty():
		room.hud.show_message("No new mail. A new quiz comes tomorrow.")
		return
	choose_mail(letters, open_quiz)


func choose_mail(letters: Array, quiz: Dictionary) -> ChoicePanel:
	Tips.show_once(room.hud, "TutorialMailClient")
	var rows: Array = []
	for letter: Dictionary in letters:
		rows.append({"label": describe_mail(letter), "options": MAIL_ACTIONS, "selected": 1})
	if not quiz.is_empty():
		rows.append({"label": "Today's quiz", "options": QUIZ_ACTIONS, "selected": 1})
	var panel: ChoicePanel = room.hud.open_choices("Mail", rows)
	panel.chosen.connect(func(selections: Array[int]) -> void: _on_mail_chosen(selections, letters, quiz))
	return panel


func _on_mail_chosen(selections: Array[int], letters: Array, quiz: Dictionary) -> void:
	for index in letters.size():
		if selections[index] != 1:
			continue
		var opened := await Api.open_mail(int(letters[index]["id"]))
		if opened["ok"] and opened["data"].get("itemId") is float and opened["data"].get("kind") != "message":
			var ingredient_id := int(opened["data"]["itemId"])
			room.ingredients[ingredient_id] = room.ingredients.get(ingredient_id, 0) + 1
	if not quiz.is_empty() and selections[letters.size()] == 1:
		room.forms.ask_quiz(quiz)


## A friend's garden while visiting: their plots can be watered for a coin each.
func choose_friend_garden(host: Dictionary) -> ChoicePanel:
	var plots: Array = host.get("plots", [])
	var rows: Array = []
	for plot: Dictionary in plots:
		rows.append({"label": RoomForms.describe_plot(int(plot.get("plot", 0)), plot), "options": [LEAVE, "Water"], "selected": 1})
	if rows.is_empty():
		room.hud.show_message("Nothing grows in %s's garden." % host.get("username", "this"))
		return null
	var panel: ChoicePanel = room.hud.open_choices("%s's garden" % host.get("username", ""), rows)
	panel.chosen.connect(func(selections: Array[int]) -> void:
		for index in plots.size():
			if selections[index] == 1:
				var watered := await Api.water_friend(int(host["id"]), int(plots[index].get("plot", 0)))
				room.hud.show_message(watered["error"] if not watered["ok"] else "Watered. You earned a coin."))
	return panel
