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
