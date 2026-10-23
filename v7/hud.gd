extends CanvasLayer

# Everything drawn over the game: Veyl's health, what vae carries in hand,
# the combo count, notices, the prompt for whatever's in reach, banners for
# big moments, the boss's health, and Rowan's dialogue. Opens the pack
# (crafting_panel.gd), the map (map_overlay.gd) and the pause menu.

const InkBar = preload("res://ink_bar.gd")
const UI = preload("res://ui_kit.gd")
const Items = preload("res://items.gd")

var health_bar: InkBar
var gear_label: Label
var objective: Label
var combo_label: Label
var notice: Label
var prompt: Label
var banner_title: Label
var banner_sub: Label
var boss_box: VBoxContainer
var boss_bar: InkBar
var dialogue_panel: PanelContainer
var dialogue_name: Label
var dialogue_text: Label
var dialogue_lines = []
var crafting: Control
var map_view: Control
var pause: Control
var notice_tween: Tween
var banner_tween: Tween


func _ready():

	add_to_group("hud")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root = UI.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top = VBoxContainer.new()
	top.position = Vector2(24, 18)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.add_child(UI.title("VEYL", 22, UI.EMBER))
	health_bar = InkBar.new(Vector2(300, 16), Color(0.85, 0.3, 0.08))
	health_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(health_bar)
	gear_label = UI.label("", 16, UI.MUTED)
	top.add_child(gear_label)
	objective = UI.label("", 17, Color(1.0, 0.82, 0.6))
	top.add_child(objective)
	combo_label = UI.title("", 26, Color(1.0, 0.8, 0.35))
	top.add_child(combo_label)

	var keys = UI.label("A/D move · Space jump · Shift dash · Click strike · Right-click heavy · W/S + strike launch/slam · F dig · E use · I pack · M map", 14, UI.MUTED)
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 24
	keys.offset_top = -30
	root.add_child(keys)

	notice = UI.label("", 22, UI.TEXT)
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notice.offset_left = -500
	notice.offset_right = 500
	notice.offset_top = 22
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notice)

	prompt = UI.label("", 20, Color(1.0, 0.85, 0.6))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = -120
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt)

	banner_title = UI.title("", 64, UI.EMBER)
	UI.centered(banner_title)
	banner_title.offset_top = -140
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner_title)
	banner_sub = UI.label("", 24, UI.TEXT)
	UI.centered(banner_sub)
	banner_sub.offset_top = -60
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner_sub)

	boss_box = VBoxContainer.new()
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	boss_box.offset_left = -360
	boss_box.offset_right = 360
	boss_box.offset_top = -86
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	var boss_name = UI.title("THE ASHBOUND", 24, UI.EMBER)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	boss_bar = InkBar.new(Vector2(720, 18), Color(0.75, 0.12, 0.05), [0.5])
	boss_box.add_child(boss_bar)
	root.add_child(boss_box)

	build_dialogue(root)

	GameState.notify.connect(show_notice)
	GameState.inventory_changed.connect(refresh_gear)
	GameState.abilities_changed.connect(refresh_gear)
	refresh_gear()

	var game = get_tree().get_first_node_in_group("game")
	if game and game.player:
		game.player.health_changed.connect(health_bar.set_values)
		health_bar.set_values(game.player.health, game.player.max_health)

	for script in ["crafting_panel", "map_overlay", "pause_menu"]:
		if ResourceLoader.exists("res://%s.gd" % script):
			var panel = load("res://%s.gd" % script).new()
			panel.visible = false
			root.add_child(panel)
			match script:
				"crafting_panel":
					crafting = panel
				"map_overlay":
					map_view = panel
				"pause_menu":
					pause = panel


func build_dialogue(root: Control):

	dialogue_panel = PanelContainer.new()
	dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.offset_left = -440
	dialogue_panel.offset_right = 440
	dialogue_panel.offset_top = -210
	dialogue_panel.offset_bottom = -50
	dialogue_panel.visible = false
	var box = VBoxContainer.new()
	dialogue_panel.add_child(box)
	dialogue_name = UI.title("", 24, UI.EMBER)
	box.add_child(dialogue_name)
	dialogue_text = UI.label("", 21, UI.TEXT)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.custom_minimum_size = Vector2(820, 70)
	box.add_child(dialogue_text)
	var hint = UI.label("E / Space to continue", 14, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)
	root.add_child(dialogue_panel)


func refresh_gear():

	var weapon = Items.gear_name(GameState.gear.get("weapon"))
	var pick = GameState.gear.get("pickaxe")
	var line = weapon + "  ·  " + (Items.gear_name(pick) if pick else "no pickaxe")
	if GameState.gear.get("charm"):
		line += "  ·  " + Items.gear_name(GameState.gear["charm"])
	if GameState.has_ability("cinderwing"):
		line += "  ·  Cinderwing"
	gear_label.text = line
	objective.text = "◆ " + objective_text()


# What to do next, so the way on is never a guess
func objective_text() -> String:

	if GameState.boss_defeated:
		return "The Hollow is yours to wander."
	if not GameState.has_ability("cinderwing"):
		return "Find the Cinderwing, the feather of flame (M: map; arrows mark ways not yet taken)"
	return "Leap the high wall with the Cinderwing, then face the Ashbound (marked on your map)"


func show_combo(count: int, maximum: int):

	if count <= 1:
		combo_label.text = ""
		return
	combo_label.text = "%d HIT%s" % [count, "  MAX" if count >= maximum else ""]


func show_notice(text: String):

	notice.text = text
	notice.modulate.a = 1.0
	if notice_tween:
		notice_tween.kill()
	notice_tween = create_tween()
	notice_tween.tween_interval(3.0)
	notice_tween.tween_property(notice, "modulate:a", 0.0, 0.8)


func set_prompt(text: String, use_key: bool = true):
	prompt.text = ("[E]  " + text if use_key else text) if text != "" else ""


func banner(title: String, sub: String, hold: float = 3.5):

	banner_title.text = title
	banner_sub.text = sub
	banner_title.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	if banner_tween:
		banner_tween.kill()
	banner_tween = create_tween().set_parallel()
	banner_tween.tween_property(banner_title, "modulate:a", 1.0, 0.4)
	banner_tween.tween_property(banner_sub, "modulate:a", 1.0, 0.4)
	banner_tween.chain().tween_interval(hold)
	banner_tween.chain().tween_property(banner_title, "modulate:a", 0.0, 0.8)
	banner_tween.parallel().tween_property(banner_sub, "modulate:a", 0.0, 0.8)


func show_boss(on: bool):
	boss_box.visible = on


func set_boss_health(current: float, maximum: float):
	boss_bar.set_values(current, maximum)


# ============================================================
# DIALOGUE
# ============================================================

func dialogue(speaker: String, lines: Array):

	dialogue_lines = lines.duplicate()
	dialogue_name.text = speaker
	dialogue_panel.visible = true
	set_blocked(true)
	next_line()


func next_line():

	if dialogue_lines.is_empty():
		dialogue_panel.visible = false
		set_blocked(false)
		return
	dialogue_text.text = dialogue_lines.pop_front()
	Sfx.play("npc", -8.0, randf_range(0.95, 1.1))


func talking() -> bool:
	return dialogue_panel.visible


func set_blocked(on: bool):

	var game = get_tree().get_first_node_in_group("game")
	if game and game.player:
		game.player.input_blocked = on


# A panel that pauses the world (pack, map, pause menu)
func panel_open() -> bool:

	for p in [crafting, map_view, pause]:
		if p and p.visible:
			return true
	return false


func open_crafting(at_shrine: bool):

	if crafting == null:
		return
	crafting.open(at_shrine)
	pause_world(true)


func close_panels():

	for p in [crafting, map_view, pause]:
		if p:
			p.visible = false
	pause_world(false)


# Alone, panels stop the world; with others playing it carries on, and
# only Veyl stands still
func pause_world(on: bool):

	if Net.online():
		set_blocked(on)
	else:
		get_tree().paused = on


func _unhandled_input(event):

	if talking():
		if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("strike"):
			get_viewport().set_input_as_handled()
			next_line()
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if panel_open():
			close_panels()
		elif pause:
			pause.visible = true
			pause_world(true)
	elif event.is_action_pressed("pack") and crafting:
		get_viewport().set_input_as_handled()
		if crafting.visible:
			close_panels()
		elif not panel_open():
			open_crafting(false)
	elif event.is_action_pressed("map") and map_view:
		get_viewport().set_input_as_handled()
		if map_view.visible:
			close_panels()
		elif not panel_open():
			map_view.visible = true
			map_view.queue_redraw()
			pause_world(true)
