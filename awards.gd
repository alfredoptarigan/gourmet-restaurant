class_name Awards
extends RefCounted
## GameAwards: what each award counts and the bronze, silver, and gold trophy it earns. The
## server keeps the same table (server/src/awards.ts) and hands the trophies out.

enum Award {
	VISIT = 0, REMOVE_TRASH = 1, GIFT = 2, TRADE = 3, SPEND_COIN = 4, BUY_INDOOR_ITEM = 5,
	BUY_OUTDOOR_ITEM = 6, BUY_AVATAR_ITEM = 7, RECIPE_LEVEL_10 = 8, RATE_COUNT = 11, HARVEST = 12,
	TASK_CLEAR_PLATE = 13, TASK_FIX_TOILET = 14, TASK_REPAIR_ITEM = 15, TASK_HELP_FRIEND = 16,
}

## Award -> [what it counts, [bronze, silver, gold targets]], in the order shown.
const TABLE := {
	Award.VISIT: ["Visit friends", [100, 1000, 10000]],
	Award.REMOVE_TRASH: ["Pick up trash", [100, 1000, 10000]],
	Award.GIFT: ["Send gifts", [50, 500, 5000]],
	Award.TRADE: ["Trade ingredients", [50, 100, 5000]],
	Award.SPEND_COIN: ["Spend coins", [2000, 20000, 200000]],
	Award.BUY_INDOOR_ITEM: ["Buy furniture", [10, 500, 2000]],
	Award.BUY_OUTDOOR_ITEM: ["Buy outdoor items", [10, 200, 500]],
	Award.BUY_AVATAR_ITEM: ["Buy clothes", [10, 100, 500]],
	Award.RECIPE_LEVEL_10: ["Royal recipes", [1, 5, 20]],
	Award.RATE_COUNT: ["Rate restaurants", [100, 1000, 10000]],
	Award.HARVEST: ["Harvest plants", [10, 50, 200]],
	Award.TASK_CLEAR_PLATE: ["Clear plates", [50, 500, 2000]],
	Award.TASK_FIX_TOILET: ["Fix toilets", [20, 200, 1000]],
	Award.TASK_REPAIR_ITEM: ["Repair machines", [20, 200, 1000]],
	Award.TASK_HELP_FRIEND: ["Help friends", [50, 250, 1000]],
}
const TIER_NAMES: Array[String] = ["bronze", "silver", "gold"]


## How an award reads with `value` counted: the trophies earned and the next target.
static func describe(award: int, value: int) -> String:
	var targets: Array = TABLE[award][1]
	var earned := targets.filter(func(target: int) -> bool: return value >= target).size()
	if earned == targets.size():
		return "%d, all trophies won" % value
	var won := "" if earned == 0 else ", %s won" % TIER_NAMES[earned - 1]
	return "%d of %d for %s%s" % [value, targets[earned], TIER_NAMES[earned], won]
