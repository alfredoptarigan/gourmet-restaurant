class_name ChoicePanel
extends PanelContainer
## A small form over the restaurant: one drop-down or text field per row and a Done button.

## One selected option index per row, in row order; -1 for a text row or a row with no
## options. Read a text row with text_of() while handling this signal.
signal chosen(selections: Array[int])

var _pickers: Array[OptionButton] = []
## Row -> the text field of a text row.
var _texts: Dictionary = {}


## Each row is {"label": String, "options": Array of String, "selected": int}, or
## {"label": String, "text": String} for a text field.
func setup(title: String, rows: Array) -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for row: Dictionary in rows:
		var label := Label.new()
		label.text = row["label"]
		grid.add_child(label)
		if row.has("text"):
			var field := LineEdit.new()
			field.text = row["text"]
			field.custom_minimum_size = Vector2(200, 0)
			grid.add_child(field)
			_texts[_pickers.size()] = field
			_pickers.append(null)
			continue
		var picker := OptionButton.new()
		for option: String in row["options"]:
			picker.add_item(option)
		if picker.item_count > 0:
			picker.select(clampi(int(row["selected"]), 0, picker.item_count - 1))
		grid.add_child(picker)
		_pickers.append(picker)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(finish)
	box.add_child(done)


func select(row: int, option: int) -> void:
	_pickers[row].select(option)


func text_of(row: int) -> String:
	return _texts[row].text if _texts.has(row) else ""


func set_text(row: int, text: String) -> void:
	_texts[row].text = text


func finish() -> void:
	var selections: Array[int] = []
	for picker in _pickers:
		selections.append(picker.selected if picker != null else -1)
	chosen.emit(selections)
	queue_free()
