extends Control

# One codex page. Creatures come from CodexData.selected_creature; every
# other category passes a ready-made entry through CodexData.selected_entry.

const PLACEHOLDER = preload("res://placeholdercodeximage.png")


func _ready() -> void:
	var picture: TextureRect = $TextureRect
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if not CodexData.selected_creature.is_empty():
		show_creature(CodexData.selected_creature, picture)
	else:
		show_entry(CodexData.selected_entry, picture)


func show_creature(data: Dictionary, picture: TextureRect) -> void:
	$EntryTitle.text = data["name"]
	$EntryDescription.text = data["description"]
	picture.texture = load(data["sprite"]) if data.has("sprite") else PLACEHOLDER

	var stats = "TYPE: " + data["type"] + "\n" \
		+ "HEALTH: " + str(data["health"]) + "\n" \
		+ "ATTACK: " + str(data["attack"]) + "\n" \
		+ "DEFENSE: " + str(data["defense"]) + "\n" \
		+ "SPEED: " + str(data["speed"]) + "\n" \
		+ "RARITY: " + data["rarity"]
	if data.has("sprite"):
		stats += "\nDEFEATED: " + str(CodexData.discovered.get(data["name"], 0))
		if data.get("drop", "") != "":
			stats += "\nDROPS: " + data["drop"]
	$EntryStats.text = stats
	$EntryStats.add_theme_color_override("font_color", CodexData.RARITY_COLORS.get(data["rarity"], Color.WHITE))


func show_entry(data: Dictionary, picture: TextureRect) -> void:
	$EntryTitle.text = data.get("name", "")
	$EntryDescription.text = data.get("description", "")
	$EntryStats.text = data.get("stats", "")
	var path = data.get("image", "")
	picture.texture = load(path) if path != "" else null


func _on_back_button_pressed() -> void:
	CodexData.go_to("res://codex.tscn")
