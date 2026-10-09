class_name EarningsSync
extends Node
## Reports paid dishes to the server in small batches and tracks the coin total it confirms.
## The coins shown are the server's figure plus what has been earned but not yet confirmed.

signal coins_changed(coins: int)
signal progress_changed(gourmet_points: int)
## The server confirmed a new level and paid its reward.
signal leveled_up(level: int, coin_reward: int)

const FLUSH_INTERVAL := 5.0
## Only for the display while a report is on its way; the server sets the real value.
const COINS_PER_DISH := 2

var _confirmed_coins := 0
var _confirmed_points := 0
var _unsent_dishes := 0
var _sending_dishes := 0
var _since_flush := 0.0


func start() -> void:
	_confirmed_coins = int(Api.profile.get("coins", 0))
	_confirmed_points = int(Api.profile.get("gourmetPoints", 0))
	_announce()


## The shop changed the balance: take the server's new figure.
func set_confirmed_coins(coins: int) -> void:
	_confirmed_coins = coins
	_announce()


func shown_coins() -> int:
	return _confirmed_coins + (_unsent_dishes + _sending_dishes) * COINS_PER_DISH


## Each dish is one gourmet point, counted as soon as it is paid for.
func shown_points() -> int:
	return _confirmed_points + _unsent_dishes + _sending_dishes


func _announce() -> void:
	coins_changed.emit(shown_coins())
	progress_changed.emit(shown_points())


func _process(delta: float) -> void:
	_since_flush += delta
	if _since_flush >= FLUSH_INTERVAL and _unsent_dishes > 0 and _sending_dishes == 0:
		_since_flush = 0.0
		_flush()


## A customer's meal was paid for.
func add_dish() -> void:
	_unsent_dishes += 1
	_announce()


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
		_confirmed_points = int(result["data"].get("gourmetPoints", _confirmed_points))
		var reward := int(result["data"].get("levelUpReward", 0))
		if reward > 0:
			leveled_up.emit(int(result["data"].get("level", 1)), reward)
	else:
		# Not delivered: keep the dishes and try again on the next flush.
		push_warning("EarningsSync: could not report earnings (%s)" % result["error"])
		_unsent_dishes += _sending_dishes
	_sending_dishes = 0
	_announce()
