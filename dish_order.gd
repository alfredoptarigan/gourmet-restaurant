class_name DishOrder
extends RefCounted
## One dish a customer ordered, followed from the table to the stove and back. DishOrder.as.

var recipe: Dictionary
var customer: Customer
var table: RoomItem
var kitchen: RoomItem
## True once the dish stands on the table.
var served := false
## How much of it has been eaten, from 0 to 1.
var eaten := 0.0


func _init(ordered_recipe: Dictionary, ordering_customer: Customer, at_table: RoomItem) -> void:
	recipe = ordered_recipe
	customer = ordering_customer
	table = at_table


## What the customer pays, in coins.
func cost() -> int:
	return int(recipe.get("cost", 0))
