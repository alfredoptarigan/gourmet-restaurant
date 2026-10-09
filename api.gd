extends Node
## Talks to the Gourmet Street server (server/). Every call returns
## {"ok": bool, "status": int, "data": Dictionary, "error": String}; status 0 means the
## server could not be reached at all.
##
## ponytail: the session token is kept in plain text in user://session.cfg, like a browser
## cookie on disk. Move it to the OS keychain if accounts ever guard something valuable.

const SESSION_PATH := "user://session.cfg"
const SESSION_SECTION := "session"
const TOKEN_KEY := "token"
const DEFAULT_BASE_URL := "http://localhost:3000"
## Set this environment variable to point the game at another server.
const BASE_URL_VARIABLE := "GOURMET_SERVER_URL"
const REQUEST_TIMEOUT := 10.0
const UNAUTHORIZED := 401
const LAYOUT_KEY := "layout"

var base_url := DEFAULT_BASE_URL
var token := ""
## The profile as last fetched: username, coins, cash, version, data.
var profile: Dictionary = {}


func _ready() -> void:
	var override := OS.get_environment(BASE_URL_VARIABLE)
	if not override.is_empty():
		base_url = override.trim_suffix("/")
	var config := ConfigFile.new()
	if config.load(SESSION_PATH) == OK:
		var saved: Variant = config.get_value(SESSION_SECTION, TOKEN_KEY, "")
		token = saved if saved is String else ""


func is_signed_in() -> bool:
	return not token.is_empty()


func register(username: String, password: String) -> Dictionary:
	return await _sign_in("/auth/register", username, password)


func login(username: String, password: String) -> Dictionary:
	return await _sign_in("/auth/login", username, password)


func logout() -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, "/auth/logout")
	_set_token("")
	profile = {}
	return result


func fetch_profile() -> Dictionary:
	var result := await _request(HTTPClient.METHOD_GET, "/profile")
	if result["ok"]:
		profile = result["data"]
	return result


## Tells the server how many dishes and extras (arcade plays) were paid for. It answers with
## how many it credited and the new coin total; the server alone decides what each is worth.
func report_earnings(dishes: int, extras: int = 0) -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, "/profile/earnings", {"dishes": dishes, "extras": extras})
	if result["ok"] and result["data"].get("coins") is float:
		profile["coins"] = result["data"]["coins"]
	return result


## What the player owns: item id -> quantity.
func fetch_inventory() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/shop/inventory")


func buy(item_id: int) -> Dictionary:
	return await _trade("/shop/buy", item_id)


func sell(item_id: int) -> Dictionary:
	return await _trade("/shop/sell", item_id)


## Stores the restaurant's layout. The server refuses furniture the player does not own.
func save_layout(layout: Dictionary) -> Dictionary:
	return await save_data(LAYOUT_KEY, layout)


## Stores one entry of the profile's free-form data and keeps the others.
func save_data(key: String, value: Variant) -> Dictionary:
	var data: Dictionary = profile.get("data", {}).duplicate()
	data[key] = value
	# The server keeps the stored layout when a save leaves it out, and checks it against
	# what the player owns when it is there: only send it when it is what changed.
	var sent := data.duplicate()
	if key != LAYOUT_KEY:
		sent.erase(LAYOUT_KEY)
	var result := await _request(HTTPClient.METHOD_PUT, "/profile", {"version": int(profile.get("version", 0)), "data": sent})
	if result["ok"]:
		profile["version"] = result["data"].get("version", profile.get("version", 0))
		profile["data"] = data
	return result


func _trade(path: String, item_id: int) -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, path, {"itemId": item_id})
	if result["ok"] and result["data"].get("coins") is float:
		profile["coins"] = result["data"]["coins"]
	return result


func _sign_in(path: String, username: String, password: String) -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, path, {"username": username, "password": password})
	if not result["ok"]:
		return result
	var new_token: Variant = result["data"].get("token")
	if not new_token is String or new_token.is_empty():
		return _failure(result["status"], "The server did not return a session")
	_set_token(new_token)
	return await fetch_profile()


func _set_token(value: String) -> void:
	token = value
	var config := ConfigFile.new()
	config.set_value(SESSION_SECTION, TOKEN_KEY, token)
	var error := config.save(SESSION_PATH)
	if error != OK:
		push_error("Api: cannot save %s (%s); you will have to sign in again next time" % [SESSION_PATH, error_string(error)])


func _failure(status: int, message: String) -> Dictionary:
	return {"ok": false, "status": status, "data": {}, "error": message}


func _request(method: HTTPClient.Method, path: String, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if is_signed_in():
		headers.append("Authorization: Bearer " + token)
	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var error := http.request(base_url + path, headers, method, payload)
	if error != OK:
		http.queue_free()
		return _failure(0, "Could not send the request (%s)" % error_string(error))
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return _failure(0, "Cannot reach the server at %s" % base_url)
	var status: int = response[1]
	# Never trust the reply's shape: it must be the server's { success, data, error } envelope.
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("success") is bool:
		return _failure(status, "The server sent a reply the game does not understand")
	if status == UNAUTHORIZED and is_signed_in():
		# The session ended on the server; stop presenting a token that no longer works.
		_set_token("")
	var data: Variant = parsed.get("data")
	var message: Variant = parsed.get("error")
	return {
		"ok": parsed["success"],
		"status": status,
		"data": data if data is Dictionary else {},
		"error": message if message is String else "",
	}
