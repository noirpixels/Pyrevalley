extends PanelContainer

# Making things (recipes.gd). Opens by hand or to build from the inventory,
# and at a furnace or forge by working at one (stations.gd). Each recipe
# shows what it takes against what Veyl carries.
# At the forge, new gear is struck into shape: a glow slides along the
# iron and each of STRIKES blows lands best in the heat. How well they land
# sets the quality (items.gd QUALITIES). The forge also mends, tempers and
# sets rare materials into gear Veyl already owns.

signal closed

const UI = preload("res://ui_kit.gd")
const Items = preload("res://items.gd")
const Recipes = preload("res://recipes.gd")

const TITLES = {"hand": "CRAFT BY HAND", "build": "BUILD", "Furnace": "FURNACE", "Forge": "FORGE"}
const STRIKES = 3
# How close to the heat a blow must land: perfect, then good (share of the bar)
const PERFECT = 0.05
const GOOD = 0.13
const HEAT_WIDTH = 0.1
const GLOW_SPEED = 1.1
# Each blow comes faster
const SPEED_UP = 1.25

var station: String = "hand"
var title: Label
var list: VBoxContainer
var close_button: Button

# Forging
var forging: VBoxContainer
var bar: ColorRect
var heat: ColorRect
var glow: ColorRect
var forge_note: Label
var strike_button: Button
var recipe_forging: Dictionary = {}
var glow_at: float = 0.0
var glow_dir: float = 1.0
var heat_at: float = 0.5
var speed: float = GLOW_SPEED
var blows: int = 0
var score: int = 0


func _ready():

	add_theme_stylebox_override("panel", UI.panel_style())
	custom_minimum_size = Vector2(660, 0)
	UI.centered(self)
	visible = false

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	title = UI.title("CRAFT", 32, UI.EMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	build_forging(box)

	close_button = UI.button("CLOSE", close)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(close_button)

	GameState.inventory_changed.connect(refresh)
	GameState.gear_changed.connect(refresh)


func build_forging(box: VBoxContainer):

	forging = VBoxContainer.new()
	forging.add_theme_constant_override("separation", 10)
	forging.visible = false
	box.add_child(forging)

	forge_note = UI.label("", 18)
	forge_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forging.add_child(forge_note)

	bar = ColorRect.new()
	bar.color = Color(0.12, 0.1, 0.1)
	bar.custom_minimum_size = Vector2(560, 30)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	forging.add_child(bar)
	heat = ColorRect.new()
	heat.color = Color(0.85, 0.35, 0.08, 0.8)
	bar.add_child(heat)
	glow = ColorRect.new()
	glow.color = Color(1.0, 0.85, 0.5)
	bar.add_child(glow)

	strike_button = UI.button("STRIKE", strike)
	strike_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	forging.add_child(strike_button)


func open(at: String):

	station = at
	title.text = TITLES.get(station, "CRAFT")
	close_button.text = "CLOSE  [%s]" % Pad.glyph("pause")
	stop_forging()
	visible = true
	refresh()


func close():

	# Walking away mid-forge still gives the piece, as struck so far
	if forging.visible:
		finish_forging()
	visible = false
	closed.emit()


# ============================================================
# RECIPES
# ============================================================

func refresh():

	if not visible:
		return
	for child in list.get_children():
		child.queue_free()

	if station == "build":
		list.add_child(note("Stations go up in front of you. Work at one to use it."))
	for recipe in Recipes.list(station):
		var detail = Recipes.describe_cost(recipe["cost"])
		if recipe.has("gear"):
			detail = Items.describe(Items.make(recipe["gear"][0], recipe["gear"][1])) + "\n" + detail
		elif recipe.has("item"):
			detail = Items.RESOURCES.get(recipe["item"][0], "") + "\n" + detail
		var verb = "BUILD" if recipe.has("station") else ("FORGE" if station == "Forge" else "MAKE")
		add_row(recipe["title"], detail, verb, make.bind(recipe), Recipes.can_afford(recipe["cost"]))

	if station == "Forge":
		forge_work()


func forge_work():

	if GameState.gear.is_empty():
		return
	list.add_child(UI.label("YOUR GEAR", 16, UI.MUTED))
	for gear in GameState.gear:
		var max_wear = Items.max_durability(gear)
		var name_line = "%s   (wear %d / %d)" % [Items.gear_name(gear), ceil(gear["durability"]), max_wear]
		if gear["durability"] < max_wear:
			var cost = Recipes.repair_cost(gear)
			add_row(name_line, "Mend to full  ·  " + Recipes.describe_cost(cost), "REPAIR", work.bind("repair", gear["id"], cost, ""), Recipes.can_afford(cost))
			name_line = ""
		if Recipes.can_temper(gear):
			var cost = Recipes.temper_cost(gear)
			add_row(name_line, "Temper to +%d (stronger, longer-lasting)  ·  %s" % [gear["level"] + 1, Recipes.describe_cost(cost)], "TEMPER", work.bind("temper", gear["id"], cost, ""), Recipes.can_afford(cost))
			name_line = ""
		var kind = "armor" if Items.slot(gear) == "armor" else "weapon"
		for magic in Recipes.magics_for(gear):
			var cost = Recipes.magic_cost(magic)
			# Only offered once Veyl has found the material
			if GameState.count(cost.keys()[0]) == 0:
				continue
			add_row(name_line, "%s: %s  ·  %s" % [magic, Items.MAGIC[magic][kind], Recipes.describe_cost(cost)], "SET", work.bind("magic", gear["id"], cost, magic), Recipes.can_afford(cost))
			name_line = ""


func make(recipe: Dictionary):

	if not Recipes.can_afford(recipe["cost"]):
		return
	if recipe.has("station"):
		var player = get_tree().get_first_node_in_group("player")
		var stations = get_tree().current_scene.get_node_or_null("Emberwood/Stations")
		if player and stations:
			stations.build(recipe["station"], player)
		close()
		return
	Recipes.pay(recipe["cost"])
	if recipe.has("gear") and station == "Forge":
		start_forging(recipe)
		return
	if recipe.has("gear"):
		var gear = Items.make(recipe["gear"][0], recipe["gear"][1])
		GameState.give_gear(gear)
		GameState.notify.emit("Made a %s." % Items.gear_name(gear))
	else:
		GameState.add_item(recipe["item"][0], recipe["item"][1])
		GameState.notify.emit("+%d %s" % [recipe["item"][1], recipe["item"][0]])
	Sfx.play("pickup")


func work(kind: String, id: int, cost: Dictionary, magic: String):

	if not Recipes.can_afford(cost) or GameState.find_gear(id).is_empty():
		return
	Recipes.pay(cost)
	match kind:
		"repair":
			GameState.repair(id)
		"temper":
			GameState.temper(id)
		"magic":
			GameState.set_magic(id, magic)
	Sfx.play("hit_heavy", -4.0, 1.2)
	GameState.notify.emit(Items.gear_name(GameState.find_gear(id)))


func note(text: String) -> Label:

	var l = UI.label(text, 15, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	return l


func add_row(title_text: String, description: String, action: String, callback: Callable, enabled: bool):

	var row = HBoxContainer.new()
	var text = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if title_text != "":
		text.add_child(UI.label(title_text, 19))
	var desc = UI.label(description, 15, UI.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(470, 0)
	text.add_child(desc)
	row.add_child(text)
	var button = UI.button(action, callback)
	button.custom_minimum_size = Vector2(120, 38)
	button.add_theme_font_size_override("font_size", 16)
	button.disabled = not enabled
	row.add_child(button)
	list.add_child(row)


# ============================================================
# FORGING
# ============================================================

func start_forging(recipe: Dictionary):

	recipe_forging = recipe
	blows = 0
	score = 0
	speed = GLOW_SPEED
	glow_at = 0.0
	glow_dir = 1.0
	place_heat()
	list.get_parent().visible = false
	forging.visible = true
	update_note()
	strike_button.grab_focus.call_deferred()


func stop_forging():

	recipe_forging = {}
	forging.visible = false
	list.get_parent().visible = true


func place_heat():
	heat_at = randf_range(0.2, 0.8)


func update_note():
	forge_note.text = "Forging the %s.  Strike when the glow is in the heat.  Blow %d of %d  [%s]" % [recipe_forging["title"], blows + 1, STRIKES, Pad.glyph("interact")]


func _process(delta):

	if not forging.visible:
		return
	glow_at += glow_dir * speed * delta
	if glow_at > 1.0 or glow_at < 0.0:
		glow_dir = -glow_dir
		glow_at = clampf(glow_at, 0.0, 1.0)
	var w = bar.size.x
	heat.position = Vector2((heat_at - HEAT_WIDTH / 2.0) * w, 0)
	heat.size = Vector2(HEAT_WIDTH * w, bar.size.y)
	glow.position = Vector2(glow_at * w - 3.0, -4.0)
	glow.size = Vector2(6.0, bar.size.y + 8.0)


func _unhandled_input(event):

	if forging.visible and event.is_action_pressed("interact"):
		strike()
		get_viewport().set_input_as_handled()


func strike():

	if not forging.visible:
		return
	var off = absf(glow_at - heat_at)
	if off < PERFECT:
		score += 2
		Sfx.play("hit_heavy", -2.0, 1.3)
	elif off < GOOD:
		score += 1
		Sfx.play("hit_heavy", -4.0, 1.0)
	else:
		Sfx.play("hit_heavy", -6.0, 0.6)
	blows += 1
	if blows >= STRIKES:
		finish_forging()
		return
	speed *= SPEED_UP
	place_heat()
	update_note()


# 0-1 Crude, 2-3 Standard, 4-5 Fine, all perfect Masterwork
func finish_forging():

	var quality = clampi(score / 2, 0, Items.QUALITIES.size() - 1)
	var gear = Items.make(recipe_forging["gear"][0], recipe_forging["gear"][1], quality)
	GameState.give_gear(gear)
	GameState.notify.emit("Forged a %s." % Items.gear_name(gear))
	stop_forging()
	refresh()
