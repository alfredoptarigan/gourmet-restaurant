class_name Levels
extends RefCounted
## GameWorld.LEVEL_THRESHOLDS from the original client: what each level starts at and unlocks.
## Level 1 is the first row. The server keeps its own copy (server/src/levels.ts) and decides
## rewards; this one is for display and for sizing the restaurant.

const TABLE: Array[Dictionary] = [
	{"points": 0, "room_size": Vector2i(8, 8), "employees": 2, "coin_reward": 0},
	{"points": 50, "room_size": Vector2i(8, 8), "employees": 2, "coin_reward": 3500},
	{"points": 70, "room_size": Vector2i(8, 8), "employees": 3, "coin_reward": 2500},
	{"points": 100, "room_size": Vector2i(9, 8), "employees": 3, "coin_reward": 1000},
	{"points": 200, "room_size": Vector2i(9, 9), "employees": 3, "coin_reward": 1000},
	{"points": 500, "room_size": Vector2i(9, 9), "employees": 4, "coin_reward": 1000},
	{"points": 1000, "room_size": Vector2i(10, 9), "employees": 4, "coin_reward": 1000},
	{"points": 2000, "room_size": Vector2i(10, 10), "employees": 4, "coin_reward": 1000},
	{"points": 4000, "room_size": Vector2i(10, 10), "employees": 5, "coin_reward": 1000},
	{"points": 6000, "room_size": Vector2i(11, 10), "employees": 5, "coin_reward": 1000},
	{"points": 8000, "room_size": Vector2i(11, 11), "employees": 5, "coin_reward": 1000},
	{"points": 10000, "room_size": Vector2i(11, 11), "employees": 6, "coin_reward": 1000},
	{"points": 14000, "room_size": Vector2i(12, 11), "employees": 6, "coin_reward": 1000},
	{"points": 18000, "room_size": Vector2i(12, 12), "employees": 6, "coin_reward": 1000},
	{"points": 22000, "room_size": Vector2i(12, 12), "employees": 7, "coin_reward": 1000},
	{"points": 30000, "room_size": Vector2i(13, 12), "employees": 7, "coin_reward": 1000},
	{"points": 38000, "room_size": Vector2i(13, 13), "employees": 7, "coin_reward": 1000},
	{"points": 46000, "room_size": Vector2i(13, 13), "employees": 8, "coin_reward": 1000},
	{"points": 58000, "room_size": Vector2i(14, 13), "employees": 8, "coin_reward": 1000},
	{"points": 70000, "room_size": Vector2i(14, 14), "employees": 8, "coin_reward": 1000},
	{"points": 86000, "room_size": Vector2i(15, 14), "employees": 8, "coin_reward": 1000},
	{"points": 102000, "room_size": Vector2i(15, 15), "employees": 9, "coin_reward": 1000},
	{"points": 122000, "room_size": Vector2i(16, 15), "employees": 9, "coin_reward": 1000},
	{"points": 142000, "room_size": Vector2i(16, 16), "employees": 9, "coin_reward": 1000},
	{"points": 166000, "room_size": Vector2i(17, 16), "employees": 9, "coin_reward": 1000},
	{"points": 190000, "room_size": Vector2i(17, 17), "employees": 9, "coin_reward": 1000},
	{"points": 218000, "room_size": Vector2i(18, 17), "employees": 9, "coin_reward": 1000},
	{"points": 246000, "room_size": Vector2i(18, 18), "employees": 9, "coin_reward": 1000},
	{"points": 280000, "room_size": Vector2i(18, 18), "employees": 9, "coin_reward": 1000},
	{"points": 320000, "room_size": Vector2i(19, 18), "employees": 9, "coin_reward": 1000},
	{"points": 370000, "room_size": Vector2i(19, 18), "employees": 9, "coin_reward": 1000},
	{"points": 430000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 500000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 580000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 661000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 743000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 826000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 910000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 995000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1081000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1168000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1256000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1345000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1435000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1526000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1618000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1711000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1805000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1900000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 1996000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2093000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2191000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2290000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2390000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2491000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2593000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2696000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2800000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 2905000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 3011000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 3118000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 3226000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 3335000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 3445000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 3556000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
	{"points": 3668000, "room_size": Vector2i(19, 19), "employees": 9, "coin_reward": 1000},
]


static func count() -> int:
	return TABLE.size()


static func level_for(gourmet_points: int) -> int:
	var level := 1
	while level < TABLE.size() and gourmet_points >= TABLE[level]["points"]:
		level += 1
	return level


static func row(level: int) -> Dictionary:
	return TABLE[clampi(level, 1, TABLE.size()) - 1]


static func room_size(level: int) -> Vector2i:
	return row(level)["room_size"]


## How far through the current level the points are, from 0 to 1. The last level is always full.
static func progress(gourmet_points: int) -> float:
	var level := level_for(gourmet_points)
	if level >= TABLE.size():
		return 1.0
	var start: int = TABLE[level - 1]["points"]
	var end: int = TABLE[level]["points"]
	return clampf(float(gourmet_points - start) / float(end - start), 0.0, 1.0)
