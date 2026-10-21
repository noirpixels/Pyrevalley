extends PanelContainer

# Inventory: what's equipped (weapon, armour, pickaxe, axe), the rest of
# Veyl's gear with EQUIP buttons, and materials. Gear shows its wear;
# anything at zero has already broken (GameState.wear). Crafting by hand
# and building open from here too (crafting_panel.gd, via game_ui.gd).

signal closed
signal craft_pressed(station)

const UI = preload("res://ui_kit.gd")
const Items = preload("res://items.gd")

var list: VBoxContainer
var close_button: Button


func _ready():

	add_theme_stylebox_override("panel", UI.panel_style())
	custom_minimum_size = Vector2(620, 0)
	UI.centered(self)
	visible = false

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title = UI.title("INVENTORY", 32, UI.EMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UI.button("CRAFT BY HAND", func(): craft_pressed.emit("hand")))
	row.add_child(UI.button("BUILD", func(): craft_pressed.emit("build")))
	close_button = UI.button("CLOSE", close)
	box.add_child(close_button)

	GameState.inventory_changed.connect(refresh)
	GameState.gear_changed.connect(refresh)


func open():

	refresh()
	close_button.text = "CLOSE  [%s]" % Pad.glyph("inventory")
	visible = true


func close():

	visible = false
	closed.emit()


func refresh():

	if not visible:
		return
	for child in list.get_children():
		child.queue_free()

	list.add_child(UI.label("EQUIPPED", 16, UI.MUTED))
	for slot in ["weapon", "armor", "pickaxe", "axe"]:
		var gear = GameState.equipped_gear(slot)
		if gear.is_empty():
			var empty = "Fists" if slot == "weapon" else "nothing"
			add_row("%s:  %s" % [slot.capitalize(), empty], "Fists hit softly but rattle a creature fast." if slot == "weapon" else "", "", Callable())
		else:
			add_row("%s:  %s" % [slot.capitalize(), Items.gear_name(gear)], Items.describe(gear), "TAKE OFF", GameState.unequip.bind(slot))

	var spare = GameState.gear.filter(func(g): return not g["id"] in GameState.equipped.values())
	if not spare.is_empty():
		list.add_child(UI.label("GEAR", 16, UI.MUTED))
		for gear in spare:
			add_row(Items.gear_name(gear), Items.describe(gear), "EQUIP", GameState.equip.bind(gear["id"]))

	list.add_child(UI.label("MATERIALS", 16, UI.MUTED))
	var any = false
	for item_name in Items.RESOURCES:
		if GameState.count(item_name) > 0:
			add_row("%s  ×%d" % [item_name, GameState.count(item_name)], Items.RESOURCES[item_name], "", Callable())
			any = true
	if not any:
		list.add_child(UI.label("Nothing yet. Forage the forest floor, mine, chop, and see what creatures leave behind.", 16, UI.MUTED))


func add_row(title: String, description: String, action: String, callback: Callable):

	var row = HBoxContainer.new()
	var text = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UI.label(title, 19))
	if description != "":
		var desc = UI.label(description, 15, UI.MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(440, 0)
		text.add_child(desc)
	row.add_child(text)
	if action != "":
		var button = UI.button(action, callback)
		button.custom_minimum_size = Vector2(120, 38)
		button.add_theme_font_size_override("font_size", 16)
		row.add_child(button)
	list.add_child(row)
