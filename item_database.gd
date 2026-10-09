class_name ItemDatabase
extends RefCounted
## Lookups over a JSON file written by tools/extract_data.py. Port of ItemDatabase.as.
## Groups are {"name", "items": [...]}; item numbers are strings, as in the original client.

var groups: Array = []

## Item id -> {"item", "group"}, built once on load.
var _by_id: Dictionary = {}


static func load_from(path: String) -> ItemDatabase:
	var database := ItemDatabase.new()
	if not FileAccess.file_exists(path):
		push_error("ItemDatabase: %s is missing. Run: python3 tools/extract_data.py" % path)
		return database
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array:
		push_error("ItemDatabase: %s is not a JSON array of groups" % path)
		return database
	database.groups = parsed
	for group: Dictionary in database.groups:
		for item: Dictionary in group["items"]:
			if item.has("id"):
				database._by_id[int(item["id"])] = {"item": item, "group": group}
	return database


## ItemDatabase.getItemFromId. Empty if there is no such item.
func get_item_by_id(item_id: int) -> Dictionary:
	return _by_id.get(item_id, {}).get("item", {})


func get_group_name_by_id(item_id: int) -> String:
	return _by_id.get(item_id, {}).get("group", {}).get("name", "")


## The type flags of an item: its own plus its group's, as RoomItem's constructor merges them.
func get_types_by_id(item_id: int) -> Array:
	var entry: Dictionary = _by_id.get(item_id, {})
	return entry.get("group", {}).get("types", []) + entry.get("item", {}).get("types", [])


func get_group(group_name: String) -> Dictionary:
	for group: Dictionary in groups:
		if group["name"] == group_name:
			return group
	return {}


func get_items(group_name: String) -> Array:
	return get_group(group_name).get("items", [])


func get_item_from_group(item_name: String, group_name: String) -> Dictionary:
	for item: Dictionary in get_items(group_name):
		if item.get("name") == item_name:
			return item
	push_warning("ItemDatabase: item %s not found in group %s" % [item_name, group_name])
	return {}


## The type flags of an item: its own plus its group's, as RoomItem's constructor merges them.
func get_item_types(item_name: String) -> Array:
	for group: Dictionary in groups:
		for item: Dictionary in group["items"]:
			if item.get("name") == item_name:
				return group.get("types", []) + item.get("types", [])
	return []


func get_item(item_name: String) -> Dictionary:
	for group: Dictionary in groups:
		for item: Dictionary in group["items"]:
			if item.get("name") == item_name:
				return item
	push_warning("ItemDatabase: item %s not found" % item_name)
	return {}
