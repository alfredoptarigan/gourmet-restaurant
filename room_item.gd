class_name RoomItem
extends RefCounted
## A piece of furniture placed in a restaurant, with the bits of state the simulation hangs
## on it. Counterpart of RoomItem.as.

var item_name: String
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

## Chair: who sits here, or is walking over to.
var occupant: Customer
## Table: the dish, or empty plate, standing on it.
var table_top_order: DishOrder
## Kitchen: a cooked dish waiting for a waiter. The stove is blocked until it is taken.
var ready_order: DishOrder


func has_type(type: String) -> bool:
	return type in types
