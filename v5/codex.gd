extends Control

# Every tab is built from CodexData, cloning Entry1 in codex.tscn as the
# card template, so new entries only need adding in one place.

const PLACEHOLDER = preload("res://placeholdercodeximage.png")
const LOCKED_TEXT = "Not yet discovered."

@onready var category_list: VBoxContainer = $CodexScroll/CategoryList
@onready var creatures_list: VBoxContainer = $CodexScroll/CategoryList/CreaturesList
@onready var weapons_list: VBoxContainer = $CodexScroll/CategoryList/WeaponsList
@onready var template: PanelContainer = $CodexScroll/CategoryList/CreaturesList/Entry1

var lists = {}
var tab_buttons = {}


func _ready() -> void:
	# Opened from the main menu, progress may not be loaded yet
	GameState.ensure_loaded()
	template.visible = false

	lists = {
		"creatures": creatures_list,
		"weapons": weapons_list,
		"plants": add_list("PlantsList"),
		"npcs": add_list("NPCsList"),
		"locations": add_list("LocationsList"),
	}
	tab_buttons = {
		"creatures": $CategoryButtons/CreaturesButton,
		"weapons": $CategoryButtons/WeaponsButton,
		"plants": $CategoryButtons/PlantsButton,
		"npcs": $CategoryButtons/NPCsButton,
		"locations": $CategoryButtons/LocationsButton,
	}
	$CategoryButtons/PlantsButton.pressed.connect(show_tab.bind("plants"))
	$CategoryButtons/NPCsButton.pressed.connect(show_tab.bind("npcs"))
	$CategoryButtons/LocationsButton.pressed.connect(show_tab.bind("locations"))
	for button in tab_buttons.values():
		button.toggle_mode = true

	build_creatures()
	build_weapons()
	build_simple("plants", CodexData.PLANTS, "where")
	build_simple("npcs", CodexData.NPCS, "role")
	build_simple("locations", CodexData.LOCATIONS, "region")
	show_tab("creatures")


func add_list(list_name: String) -> VBoxContainer:
	var list = VBoxContainer.new()
	list.name = list_name
	list.custom_minimum_size = creatures_list.custom_minimum_size
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_list.add_child(list)
	return list


func show_tab(tab: String) -> void:
	for key in lists:
		lists[key].visible = key == tab
		tab_buttons[key].set_pressed_no_signal(key == tab)
	$CodexScroll.scroll_vertical = 0


# ============================================================
# CATEGORIES
# ============================================================

func build_creatures() -> void:
	for creature in CodexData.CREATURES:
		var known = CodexData.is_creature_known(creature)
		var image = load(creature["sprite"]) if creature.has("sprite") else PLACEHOLDER

		if not known:
			add_card("creatures", "???", LOCKED_TEXT, "Emberwood", image, Callable(), true)
			continue

		var tag = "Beyond Emberwood · rumoured"
		if creature.has("sprite"):
			tag = "Emberwood · defeated %d" % CodexData.discovered.get(creature["name"], 0)
		add_card("creatures", creature["name"], creature["description"], tag, image,
			CodexData.select.bind(creature["name"]))


func build_weapons() -> void:
	for weapon in CodexData.WEAPONS:
		var entry = {"name": weapon["name"], "image": weapon.get("image", "")}
		var tag = "Rumoured"
		if weapon.get("item", false):
			var item = GameState.ITEMS[weapon["name"]]
			entry["description"] = item["description"]
			entry["stats"] = "TYPE: Sword\nATTACK: +%d\nREACH: %.1f\nSWING: %.2fs" % [
				item["attack"], item["range"], item["cooldown"]]
			tag = "Equipped" if GameState.equipped_weapon == weapon["name"] else "Owned"
		else:
			entry["description"] = weapon["description"]
			entry["stats"] = "TYPE: Sword\nSTATUS: Rumoured"
		add_card("weapons", entry["name"], entry["description"], tag, image_for(entry),
			CodexData.select_entry.bind(entry))


# Plants, NPCs and locations: name, description, a tag field, optional image
func build_simple(tab: String, entries: Array, tag_key: String) -> void:
	for data in entries:
		var image = image_for(data)
		if not CodexData.is_unlocked(data):
			add_card(tab, "???", LOCKED_TEXT, "", image, Callable(), true)
			continue
		var entry = data.duplicate()
		entry["stats"] = tag_key.to_upper() + ": " + data[tag_key]
		add_card(tab, data["name"], data["description"], data[tag_key], image,
			CodexData.select_entry.bind(entry))


# Entries without art of their own show no picture
func image_for(entry: Dictionary) -> Texture2D:
	var path = entry.get("image", "")
	return load(path) if path != "" else null


# ============================================================
# CARDS
# ============================================================

func add_card(tab: String, title: String, description: String, tag: String,
		image: Texture2D, on_open: Callable, locked: bool = false) -> void:

	var card = template.duplicate(0)
	card.name = "Entry" + title.replace(" ", "").replace("?", "Locked")
	card.visible = true

	var picture: TextureRect = card.get_node("HBoxContainer/Image")
	picture.texture = image
	picture.visible = image != null
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if locked:
		# Silhouette only, until it's been found
		picture.modulate = Color(0, 0, 0, 0.85) if image != PLACEHOLDER else Color(0.25, 0.25, 0.25)

	card.get_node("HBoxContainer/Info/Name").text = title
	card.get_node("HBoxContainer/Info/Description").text = description

	if tag != "":
		var tag_label = Label.new()
		tag_label.text = tag
		tag_label.add_theme_font_size_override("font_size", 16)
		tag_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		card.get_node("HBoxContainer/Info").add_child(tag_label)
		card.get_node("HBoxContainer/Info").move_child(tag_label, 1)

	var button: Button = card.get_child(0)
	if on_open.is_valid():
		button.pressed.connect(on_open)
	else:
		button.disabled = true

	lists[tab].add_child(card)


func _on_back_button_pressed() -> void:
	CodexData.go_to("res://main_menu.tscn")


func _on_creatures_button_pressed() -> void:
	show_tab("creatures")


func _on_weapons_button_pressed() -> void:
	show_tab("weapons")
