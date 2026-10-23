extends PanelContainer

# The pack: what Veyl carries, the gear vae owns (pick what's in hand), and
# what vae can make: tools from branches and flint anywhere, and bronze at
# an ember shrine's flame.

const Items = preload("res://items.gd")
const UI = preload("res://ui_kit.gd")

var at_shrine: bool = false
var title: Label
var items_box: VBoxContainer
var gear_box: VBoxContainer
var recipe_box: VBoxContainer


func _init():

	process_mode = Node.PROCESS_MODE_ALWAYS
	UI.centered(self)
	custom_minimum_size = Vector2(980, 520)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	add_child(outer)
	title = UI.title("PACK", 34, UI.EMBER)
	outer.add_child(title)
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	outer.add_child(cols)
	items_box = column(cols, "CARRIED", 240)
	gear_box = column(cols, "GEAR", 260)
	recipe_box = column(cols, "MAKE", 400)
	var hint = UI.label("I or Esc to close", 14, UI.MUTED)
	outer.add_child(hint)


func column(parent: Control, heading: String, width: float) -> VBoxContainer:

	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 6)
	box.add_child(UI.title(heading, 20, UI.MUTED))
	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	box.add_child(inner)
	parent.add_child(box)
	return inner


func open(shrine: bool):

	at_shrine = shrine
	title.text = "SHRINE FORGE" if shrine else "PACK"
	visible = true
	refresh()


func refresh():

	for box in [items_box, gear_box, recipe_box]:
		for child in box.get_children():
			child.queue_free()

	if GameState.inventory.is_empty():
		items_box.add_child(UI.label("Nothing yet.", 18, UI.MUTED))
	for item in GameState.inventory:
		var l = UI.label("%s  ×%d" % [item, GameState.inventory[item]], 18, Items.COLORS.get(item, UI.TEXT))
		l.tooltip_text = GameState.ITEM_NAMES.get(item, "")
		items_box.add_child(l)

	for gear in GameState.owned:
		var slot = Items.slot_of(gear["type"])
		var equipped = GameState.gear.get(slot) == gear
		var b = UI.button(("◆ " if equipped else "") + Items.gear_name(gear), equip.bind(gear))
		b.custom_minimum_size = Vector2(250, 36)
		b.disabled = equipped
		gear_box.add_child(b)

	var recipes = Items.HAND.duplicate()
	if at_shrine:
		recipes.append_array(Items.SHRINE)
	for r in recipes:
		var row = VBoxContainer.new()
		var cost = []
		for item in r["cost"]:
			cost.append("%d %s" % [r["cost"][item], item])
		var b = UI.button("%s  —  %s" % [r["title"], ", ".join(cost)], make.bind(r))
		b.custom_minimum_size = Vector2(400, 36)
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = not GameState.can_afford(r["cost"]) or owns(r)
		row.add_child(b)
		row.add_child(UI.label(r["text"], 14, UI.MUTED))
		recipe_box.add_child(row)
	if not at_shrine:
		recipe_box.add_child(UI.label("Bronze is made at an ember shrine.", 15, UI.MUTED))


func owns(recipe: Dictionary) -> bool:

	if not recipe.has("gear"):
		return false
	for g in GameState.owned:
		if g["type"] == recipe["gear"][0] and g["material"] == recipe["gear"][1]:
			return true
	return false


func make(recipe: Dictionary):

	if not GameState.can_afford(recipe["cost"]):
		return
	GameState.spend(recipe["cost"])
	if recipe.has("item"):
		GameState.add_item(recipe["item"][0], recipe["item"][1])
	else:
		var gear = {"type": recipe["gear"][0], "material": recipe["gear"][1]}
		GameState.owned.append(gear)
		equip(gear)
	Sfx.play("checkpoint", -6.0, 1.3)
	GameState.notify.emit("Made: %s" % recipe["title"])
	refresh()


func equip(gear: Dictionary):

	GameState.gear[Items.slot_of(gear["type"])] = gear
	GameState.inventory_changed.emit()
	var game = get_tree().get_first_node_in_group("game")
	if game and game.player:
		game.player.refresh_held()
	refresh()
