class_name RoomItem
extends RefCounted
## A piece of furniture placed in a restaurant, with the bits of state the simulation hangs
## on it. Counterpart of RoomItem.as.

var item_id: int
var item_name: String
## How many quarter turns the layout asks for (see `rotation` for what is shown).
var turns: int
var config: Dictionary
## Type flags from the item and its group, e.g. "chairItem", "tableItem", "kitchen".
var types: Array
var tile: Vector2i
## The timeline frame shown. It wraps at the art's frame count, so it can be lower than the
## number of turns the layout asked for (RoomItem.getRotationCount).
var rotation: int
var footprint: Vector2i
var sprite: Sprite2D
## How far above the floor the item's top is: where a dish on a table sits.
var top_height := 0.0

## Chair, toilet, sink, or arcade machine: who uses it, or is walking over to.
var occupant: Customer
## Table: the dish, or empty plate, standing on it.
var table_top_order: DishOrder
## Kitchen: a cooked dish waiting for a waiter. The stove is blocked until it is taken.
var ready_order: DishOrder
## Toilet or arcade machine: uses since it was last cleaned or repaired.
var usage_count := 0
## Broken item: the cleaner on the way to repair it.
var cleaner: Cleaner
## Drink dispenser: the waiter making a drink at it, or walking over to.
var waiter: Waiter


func has_type(type: String) -> bool:
	return type in types


## RoomItem.isBroken: a toilet or arcade machine stops working after `breakCount` uses.
func is_broken() -> bool:
	var break_count := int(config.get("breakCount", 0))
	return break_count > 0 and usage_count >= break_count


## WorldRestaurantPlay.getModifiedOperateTime: better items are quicker to use.
func operate_time(seconds: float) -> float:
	return seconds * float(config.get("operateTimePercentage", 100)) / 100.0
