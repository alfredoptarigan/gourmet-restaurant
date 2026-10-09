class_name DishOrder
extends RefCounted
## One dish a customer ordered, followed from the table to the stove and back. DishOrder.as.

var recipe: Dictionary
var customer: Customer
var table: RoomItem
var kitchen: RoomItem


func _init(ordered_recipe: Dictionary, ordering_customer: Customer, at_table: RoomItem) -> void:
	recipe = ordered_recipe
	customer = ordering_customer
	table = at_table


## What the customer pays, in coins.
func cost() -> int:
	return int(recipe.get("cost", 0))
