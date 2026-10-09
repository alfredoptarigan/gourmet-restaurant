extends Node
## Run: tests/check_online.sh
## Drives the real Api autoload against a real server: register, earn, sign out.

const ALLOWANCE_WAIT_SECONDS := 4.0

var failures: Array[String] = []


func _ready() -> void:
	var saved_token := Api.token
	await _check()
	# Leave the developer's own saved session as it was.
	Api._set_token(saved_token)
	for failure in failures:
		printerr("FAIL: " + failure)
	print("check_online: %s" % ("OK" if failures.is_empty() else "%d failed" % failures.size()))
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _check() -> void:
	var username := "check_%d" % (Time.get_ticks_usec() % 100000000)
	var password := "check online pw"

	var short := await Api.register(username, "short")
	_expect(not short["ok"] and short["status"] == 400 and short["error"].begins_with("password:"),
			"a short password should be rejected with the server's reason, got %s" % short)

	var registered := await Api.register(username, password)
	_expect(registered["ok"], "registering should succeed, got %s" % registered)
	_expect(Api.is_signed_in(), "registering should sign the player in")
	_expect(Api.profile.get("username") == username and Api.profile.get("coins") == 0.0,
			"a new profile should have the username and no coins, got %s" % Api.profile)

	var taken := await Api.register(username, password)
	_expect(taken["status"] == 409, "a taken username should be refused, got %s" % taken)

	var early := await Api.report_earnings(1)
	_expect(early["ok"] and early["data"].get("credited") == 0.0, "a report with no time passed should credit nothing, got %s" % early)

	await get_tree().create_timer(ALLOWANCE_WAIT_SECONDS).timeout
	var earned := await Api.report_earnings(1)
	_expect(earned["ok"] and earned["data"].get("credited") == 1.0 and earned["data"].get("coins") == 2.0,
			"one dish after a wait should credit 2 coins, got %s" % earned)

	var inventory := await Api.fetch_inventory()
	_expect(inventory["ok"] and inventory["data"].get("items", {}).get("3040001") == 3.0, "a new player should own three chairs, got %s" % inventory)
	var starting: Variant = Api.profile.get("data", {}).get("layout")
	_expect(starting is Dictionary and starting.get("items") is Array and starting["items"].size() == 16, "a new profile should carry the starting layout")

	var too_dear := await Api.buy(3040001)
	_expect(too_dear["status"] == 409 and too_dear["error"] == "Not enough coins", "a 200 coin chair cannot be bought with 2 coins, got %s" % too_dear)

	if starting is Dictionary:
		var moved: Dictionary = starting.duplicate(true)
		moved["items"][4]["x"] = 4
		moved["items"][4]["y"] = 4
		var saved := await Api.save_layout(moved)
		_expect(saved["ok"] and Api.profile.get("version") == 1.0, "moving a chair should save, got %s" % saved)
		var greedy: Dictionary = moved.duplicate(true)
		greedy["items"].append({"id": 3040001, "x": 5, "y": 2, "rotation": 0})
		var refused := await Api.save_layout(greedy)
		_expect(refused["status"] == 409, "a layout with a chair that is not owned should be refused, got %s" % refused)
		var again := await Api.fetch_profile()
		_expect(again["ok"] and Api.profile["data"]["layout"]["items"][4]["x"] == 4.0, "the saved layout should come back on the next fetch")

	var menu_saved := await Api.save_data("menu", {"Starter": 5000008})
	var layout_saved := await Api.save_layout(Api.profile["data"]["layout"])
	var reloaded := await Api.fetch_profile()
	_expect(menu_saved["ok"] and layout_saved["ok"] and reloaded["ok"], "saving the menu and then the layout should both succeed, got %s and %s" % [menu_saved, layout_saved])
	_expect(Api.profile["data"].get("menu") == {"Starter": 5000008.0} and Api.profile["data"].get("layout") is Dictionary,
			"each save should keep what the other stored, got keys %s" % [Api.profile["data"].keys()])

	Api._set_token("")
	var signed_in := await Api.login(username, password)
	_expect(signed_in["ok"] and Api.profile.get("coins") == 2.0, "signing in again should show the saved coins, got %s" % Api.profile)

	var wrong := await Api.login(username, "the wrong password")
	_expect(wrong["status"] == 401, "a wrong password should be refused, got %s" % wrong)

	await Api.login(username, password)
	await Api.logout()
	_expect(not Api.is_signed_in(), "signing out should clear the session")

	Api.base_url = "http://127.0.0.1:9"
	var unreachable := await Api.fetch_profile()
	_expect(not unreachable["ok"] and unreachable["status"] == 0, "an unreachable server should fail cleanly, got %s" % unreachable)
