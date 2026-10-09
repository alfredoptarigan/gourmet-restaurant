class_name EarningsSync
extends Node
## Reports paid dishes to the server in small batches and tracks the coin total it confirms.
## The coins shown are the server's figure plus what has been earned but not yet confirmed.

signal coins_changed(coins: int)

const FLUSH_INTERVAL := 5.0
## Only for the display while a report is on its way; the server sets the real value.
const COINS_PER_DISH := 2

var _confirmed_coins := 0
var _unsent_dishes := 0
var _sending_dishes := 0
var _since_flush := 0.0


func start(play: RestaurantPlay) -> void:
	_confirmed_coins = int(Api.profile.get("coins", 0))
	play.dish_paid.connect(_on_dish_paid)
	coins_changed.emit(shown_coins())


func shown_coins() -> int:
	return _confirmed_coins + (_unsent_dishes + _sending_dishes) * COINS_PER_DISH


func _process(delta: float) -> void:
	_since_flush += delta
	if _since_flush >= FLUSH_INTERVAL and _unsent_dishes > 0 and _sending_dishes == 0:
		_since_flush = 0.0
		_flush()


func _on_dish_paid() -> void:
	_unsent_dishes += 1
	coins_changed.emit(shown_coins())


## ponytail: dishes paid in the last few seconds before the game closes are not reported.
## Flush on quit (and hold the window open for it) if that ever matters.
func _flush() -> void:
	_sending_dishes = _unsent_dishes
	_unsent_dishes = 0
	var result := await Api.report_earnings(_sending_dishes)
	if result["ok"]:
		# The server pays out against elapsed time, so a report can be credited only in part.
		# The rest is real earnings that arrived too early: keep it for the next report.
		var credited := clampi(int(result["data"].get("credited", 0)), 0, _sending_dishes)
		_unsent_dishes += _sending_dishes - credited
		_confirmed_coins = int(result["data"].get("coins", _confirmed_coins))
	else:
		# Not delivered: keep the dishes and try again on the next flush.
		push_warning("EarningsSync: could not report earnings (%s)" % result["error"])
		_unsent_dishes += _sending_dishes
	_sending_dishes = 0
	coins_changed.emit(shown_coins())
