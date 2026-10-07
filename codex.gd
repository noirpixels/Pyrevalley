extends Control

@onready var creatures_list: VBoxContainer = $CodexScroll/CategoryList/CreaturesList


func _ready() -> void:
	add_missing_entries()


# Creatures in CodexData without a hand-made entry in codex.tscn get one
# cloned from Entry1, so new creatures only need adding in one place.
func add_missing_entries():
	var listed = []
	for entry in creatures_list.get_children():
		var label = entry.get_node_or_null("HBoxContainer/Info/Name")
		if label:
			listed.append(label.text)

	var template = creatures_list.get_node("Entry1")

	for creature in CodexData.CREATURES:
		if creature["name"] in listed:
			continue

		var entry = template.duplicate(0)
		entry.name = "Entry" + creature["name"].replace(" ", "")
		entry.get_node("HBoxContainer/Info/Name").text = creature["name"]
		entry.get_node("HBoxContainer/Info/Description").text = creature["description"]
		var button: Button = entry.get_child(0)
		button.pressed.connect(CodexData.select.bind(creature["name"]))
		creatures_list.add_child(entry)


func _on_back_button_pressed() -> void:
	CodexData.go_to("res://main_menu.tscn")
func _on_button_1_pressed() -> void:
	CodexData.select("Ember Wolf")
func _on_button_2_pressed() -> void:
	CodexData.select("Ashfang")
func _on_button_3_pressed() -> void:
	CodexData.select("Glowmoth")
func _on_button_4_pressed() -> void:
	CodexData.select("Stoneback")
func _on_button_5_pressed() -> void:
	CodexData.select("Ember Serpent")
func _on_button_6_pressed() -> void:
	CodexData.select("Frostwing")
func _on_button_7_pressed() -> void:
	CodexData.select("Moonhare")
func _on_button_8_pressed() -> void:
	CodexData.select("Moss Giant")
func _on_button_9_pressed() -> void:
	CodexData.select("Cinder Crow")
func _on_button_10_pressed() -> void:
	# Entry 10 is "Crystal Beetle" in the scene but has no stats yet,
	# so it still opens Cinder Crow like before.
	CodexData.select("Cinder Crow")


func _on_creatures_button_pressed() -> void:
	$CodexScroll/CategoryList/CreaturesList.visible = true
	$CodexScroll/CategoryList/WeaponsList.visible = false


func _on_weapons_button_pressed() -> void:
	$CodexScroll/CategoryList/CreaturesList.visible = false
	$CodexScroll/CategoryList/WeaponsList.visible = true


func _on_wb_1_pressed() -> void:
	pass # Replace with function body.
