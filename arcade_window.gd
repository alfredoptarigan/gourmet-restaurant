class_name ArcadeWindow
extends PanelContainer
## The screen of an arcade machine: one of its games at twice the size, the best score, and
## a Quit button. Port of ArcadeGame.as.

## A game ended with a new best score.
signal new_best(game_name: String, score: int)

const GAMES := {"Snake": preload("res://arcade_snake.gd"), "Cave": preload("res://arcade_cave.gd")}
const ZOOM := 2.0

var game_name := ""
var game: Control
var best := 0

var _score_label := Label.new()


## `game_to_play` is a machine's arcadeGame: "Snake" or "Cave".
func setup(game_to_play: String, best_score: int) -> void:
	game_name = game_to_play
	best = best_score
	var column := VBoxContainer.new()
	add_child(column)
	var holder := Control.new()
	holder.custom_minimum_size = ArcadeSnake.SCREEN_SIZE * ZOOM
	column.add_child(holder)
	game = GAMES[game_name].new()
	game.scale = Vector2(ZOOM, ZOOM)
	holder.add_child(game)
	game.game_over.connect(_on_game_over)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_score_label)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(queue_free)
	bar.add_child(quit)
	_show_best()
	game.call_deferred("grab_focus")


func _on_game_over(score: int) -> void:
	if score > best:
		best = score
		_show_best()
		new_best.emit(game_name, score)


func _show_best() -> void:
	_score_label.text = "%s - best score %d. Arrow keys or space to play." % [game_name, best]
