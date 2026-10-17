extends PanelContainer

# Simple list inventory: equipped weapon and resource quantities.

signal closed

const UI = preload("res://ui_kit.gd")

var list: VBoxContainer
var close_button: Button


func _ready():

	add_theme_stylebox_override("panel", UI.panel_style())
	custom_minimum_size = Vector2(520, 0)
	UI.centered(self)
	visible = false

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title = UI.label("INVENTORY", 30, UI.EMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	box.add_child(list)

	close_button = UI.button("CLOSE", close)
	box.add_child(close_button)

	GameState.inventory_changed.connect(refresh)


func open():

	refresh()
	close_button.text = "CLOSE  [%s]" % Pad.glyph("inventory")
	visible = true


func close():

	visible = false
	closed.emit()


func refresh():

	for child in list.get_children():
		child.queue_free()

	list.add_child(UI.label("WEAPON", 16, UI.MUTED))
	var weapon = GameState.weapon()
	add_row(GameState.equipped_weapon + "  (equipped)", "ATK +%d · %s" % [weapon["attack"], weapon["description"]])

	list.add_child(UI.label("RESOURCES", 16, UI.MUTED))
	var any = false
	for item_name in GameState.ITEMS:
		var item = GameState.ITEMS[item_name]
		if item["kind"] == "resource" and GameState.inventory.get(item_name, 0) > 0:
			add_row("%s  ×%d" % [item_name, GameState.inventory[item_name]], item["description"])
			any = true

	if not any:
		list.add_child(UI.label("Nothing yet. Defeated creatures leave things behind.", 16, UI.MUTED))


func add_row(title: String, description: String):

	var row = VBoxContainer.new()
	row.add_child(UI.label(title, 20))
	var desc = UI.label(description, 15, UI.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(460, 0)
	row.add_child(desc)
	list.add_child(row)
