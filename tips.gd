class_name Tips
extends RefCounted
## The original's tutorial hints, each shown once, in the words of lang_en.bin. Which tips
## a player has seen is kept with the profile (offline, for the session only).
##
## ponytail: hints, not the original's scripted walkthrough, which led new players through
## hiring a Facebook friend step by step.

const TIPS_KEY := "tips"
const LANGUAGE_PATH := "res://data/lang_en.json"
## The parts of a tip that only fit the original (its ten-second quiz clock).
const DROPPED_SENTENCES: Array[String] = ["Be quick though - you only have 10 seconds to answer! Ready?"]

static var _texts: Dictionary = {}
static var _seen_offline: Dictionary = {}
## The tip on screen, and the ones waiting for it to close: [parent, id] each.
static var _open: AcceptDialog
static var _waiting: Array = []


## A text of lang_en.bin as plain text: no FONT tags, real line breaks.
static func text(id: String) -> String:
	if _texts.is_empty() and FileAccess.file_exists(LANGUAGE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANGUAGE_PATH))
		if parsed is Array and not parsed.is_empty() and parsed[0] is Dictionary and parsed[0].get("texts") is Dictionary:
			_texts = parsed[0]["texts"]
	var raw: String = _texts.get(id, "")
	var tags := RegEx.create_from_string("</?FONT[^>]*>")
	var plain := tags.sub(raw, "", true).replace("\\n", "\n")
	for sentence in DROPPED_SENTENCES:
		plain = plain.replace(sentence, "")
	return plain.strip_edges()


static func has_seen(id: String) -> bool:
	if Api.is_signed_in():
		var seen: Variant = Api.profile.get("data", {}).get(TIPS_KEY)
		return seen is Array and id in seen
	return _seen_offline.has(id)


## Shows the tip in a small window over `parent` the first time; null if it was seen before,
## has no text, or must wait for the tip already on screen (it shows when that one closes).
static func show_once(parent: Node, id: String) -> AcceptDialog:
	if has_seen(id) or text(id).is_empty():
		return null
	if is_instance_valid(_open):
		if not _waiting.any(func(entry: Array) -> bool: return entry[1] == id):
			_waiting.append([parent, id])
		return null
	_mark_seen(id)
	var dialog := AcceptDialog.new()
	dialog.title = "Tip"
	dialog.dialog_text = text(id)
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(360, 0)
	dialog.confirmed.connect(_close.bind(dialog))
	dialog.canceled.connect(_close.bind(dialog))
	parent.add_child(dialog)
	dialog.popup_centered()
	_open = dialog
	return dialog


static func _close(dialog: AcceptDialog) -> void:
	# Hidden first: a window only goes at the end of the frame, and until then the next tip
	# could not take the screen.
	dialog.hide()
	dialog.queue_free()
	_open = null
	while not _waiting.is_empty():
		var entry: Array = _waiting.pop_front()
		if is_instance_valid(entry[0]) and show_once(entry[0], entry[1]) != null:
			return


## Marked at once, so a tip asked for again before the save comes back is not shown twice.
static func _mark_seen(id: String) -> void:
	if not Api.is_signed_in():
		_seen_offline[id] = true
		return
	var data: Dictionary = Api.profile.get("data", {})
	var seen: Variant = data.get(TIPS_KEY)
	var updated: Array = seen.duplicate() if seen is Array else []
	updated.append(id)
	data[TIPS_KEY] = updated
	Api.profile["data"] = data
	Api.save_data(TIPS_KEY, updated)
