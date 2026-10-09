extends Node
## The game's static data. Names follow GameWorld.as (front_bin holds buildings,
## restaurant_bin holds interior items).

var building_items := ItemDatabase.load_from("res://data/front.json")
var avatar_items := ItemDatabase.load_from("res://data/avatar.json")
var interior_items := ItemDatabase.load_from("res://data/restaurant.json")
var perk_items := ItemDatabase.load_from("res://data/perk.json")
var ingredient_items := ItemDatabase.load_from("res://data/ingredient.json")
var recipe_items := ItemDatabase.load_from("res://data/recipe.json")
var quiz_items := ItemDatabase.load_from("res://data/quiz.json")
var appointment_items := ItemDatabase.load_from("res://data/appointment.json")
