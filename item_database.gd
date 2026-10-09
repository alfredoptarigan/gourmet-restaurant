class_name ItemDatabase
extends RefCounted
## Lookups over a JSON file written by tools/extract_data.py. Port of ItemDatabase.as.
## Groups are {"name", "items": [...]}; item numbers are strings, as in the original client.

var groups: Array = []


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
	return database


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


func get_item(item_name: String) -> Dictionary:
	for group: Dictionary in groups:
		for item: Dictionary in group["items"]:
			if item.get("name") == item_name:
				return item
	push_warning("ItemDatabase: item %s not found" % item_name)
	return {}
