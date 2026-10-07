extends Control
var creature_name = ""
var creature_description = ""
var creature_type = ""
var creature_health = 0
var creature_attack = 0
var creature_defense = 0
var creature_speed = 0
var creature_rarity = ""

func _ready() -> void:
	var data = CodexData.selected_creature

	$EntryTitle.text = data["name"]
	$EntryDescription.text = data["description"]

	$EntryStats.text = "TYPE: " + data["type"] + "\n" \
		+ "HEALTH: " + str(data["health"]) + "\n" \
		+ "ATTACK: " + str(data["attack"]) + "\n" \
		+ "DEFENSE: " + str(data["defense"]) + "\n" \
		+ "SPEED: " + str(data["speed"]) + "\n" \
		+ "RARITY: " + data["rarity"]
func _on_back_button_pressed() -> void:
	CodexData.go_to("res://codex.tscn")
