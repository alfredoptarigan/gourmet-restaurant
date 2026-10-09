class_name ChoicePanel
extends PanelContainer
## A small form over the restaurant: one drop-down per row and a Done button.

## One selected option index per row, in row order; -1 for a row that had no options.
signal chosen(selections: Array[int])

var _pickers: Array[OptionButton] = []


## Each row is {"label": String, "options": Array of String, "selected": int}.
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


func finish() -> void:
	var selections: Array[int] = []
	for picker in _pickers:
		selections.append(picker.selected)
	chosen.emit(selections)
	queue_free()
