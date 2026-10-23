extends Control

# Minimal HUD: HP, weapon, quest, inventory/codex/pause buttons,
# boss bar, interaction prompt, notifications and the respawn fade.

signal inventory_pressed
signal codex_pressed
signal pause_pressed

const UI = preload("res://ui_kit.gd")
const InkBar = preload("res://ink_bar.gd")
const Items = preload("res://items.gd")

var player: Node3D
var health_bar: InkBar
var health_label: Label
var weapon_label: Label
var combo_label: Label
var quest_title: Label
var quest_text: Label
var buttons: HBoxContainer
var boss_box: VBoxContainer
var boss_bar: InkBar
var prompt: Label
var hint: Label
var hint_fade: Tween
var toasts: VBoxContainer
var message: Label
var fade_rect: ColorRect
# Tool bar: weapon, pickaxe, axe (keys 1-3), with wear
var tool_bar: HBoxContainer
# Multiplayer: the other players' health, and how friends can join
var party: Label
var session: Label
var party_timer: float = 0.0


func _ready():

	UI.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ---- HP + weapon (top-left) ----
	var status = VBoxContainer.new()
	status.position = Vector2(24, 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)

	health_label = UI.title("VEYL", 22, UI.TEXT)
	status.add_child(health_label)
	health_bar = InkBar.new(Vector2(300, 18), Color(0.85, 0.3, 0.08))
	status.add_child(health_bar)
	weapon_label = UI.label("", 16, UI.MUTED)
	status.add_child(weapon_label)
	combo_label = UI.title("", 28, Color(1.0, 0.8, 0.35))
	combo_label.modulate.a = 0.0
	status.add_child(combo_label)

	# ---- Quest + buttons (top-right) ----
	var right = VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -340
	right.offset_right = -24
	right.offset_top = 20
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)

	quest_title = UI.title("", 20, UI.EMBER)
	quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(quest_title)
	quest_text = UI.label("", 16)
	quest_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(quest_text)

	buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(buttons)

	party = UI.label("", 16)
	party.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	party.visible = Net.online
	right.add_child(party)
	for b in [["Inventory", "inventory", inventory_pressed], ["Codex", "codex", codex_pressed], ["Pause", "pause", pause_pressed]]:
		var button = Button.new()
		button.set_meta("label", b[0])
		button.set_meta("action", b[1])
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(b[2].emit)
		buttons.add_child(button)

	# ---- Boss bar (bottom-center, out of the boss's way) ----
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	boss_box.offset_left = -330
	boss_box.offset_right = 330
	boss_box.offset_top = -84
	boss_box.offset_bottom = -24
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	add_child(boss_box)
	var boss_name = UI.title("—   THE ASHBOUND   —", 26, UI.EMBER)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	# The notch marks where it burns brighter
	boss_bar = InkBar.new(Vector2(660, 22), Color(0.7, 0.1, 0.05), [0.5])
	boss_box.add_child(boss_bar)

	# ---- Prompt + notifications (bottom-center) ----
	toasts = VBoxContainer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toasts.offset_left = -400
	toasts.offset_right = 400
	toasts.offset_top = -190
	toasts.offset_bottom = -90
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)

	prompt = UI.label("", 22, Color(1.0, 0.9, 0.6))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.offset_left = -200
	prompt.offset_right = 200
	prompt.offset_top = 90
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)

	# ---- Tool bar (bottom-centre) ----
	tool_bar = HBoxContainer.new()
	tool_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tool_bar.offset_left = -360
	tool_bar.offset_right = 360
	tool_bar.offset_top = -78
	tool_bar.offset_bottom = -46
	tool_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tool_bar.add_theme_constant_override("separation", 28)
	tool_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tool_bar)

	# ---- Controls hint (bottom-left), fades after a while ----
	hint = UI.label("", 14, UI.MUTED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -36
	add_child(hint)
	show_controls()
	Pad.mode_changed.connect(_on_pad_mode_changed)

	# ---- Session (bottom-right) ----
	session = UI.label("", 14, UI.MUTED)
	session.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	session.offset_left = -520
	session.offset_right = -24
	session.offset_top = -150
	session.offset_bottom = -44
	session.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	session.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	session.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	session.visible = Net.online
	add_child(session)

	# ---- Respawn fade + message ----
	fade_rect = ColorRect.new()
	UI.full_rect(fade_rect)
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)

	message = UI.label("", 28, UI.EMBER)
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	message.offset_left = -400
	message.offset_right = 400
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.modulate.a = 0.0
	add_child(message)

	GameState.inventory_changed.connect(update_weapon)
	GameState.max_combo_changed.connect(update_weapon)
	GameState.quest_changed.connect(update_quest)
	GameState.notify.connect(toast)
	GameState.boss_engaged.connect(_on_boss_engaged)
	GameState.boss_disengaged.connect(func(): boss_box.visible = false)


func setup(target: Node3D):

	player = target
	player.health_changed.connect(update_health)
	player.interact_target_changed.connect(_on_interact_target_changed)
	player.combo_changed.connect(update_combo)
	player.held_changed.connect(update_tool_bar)
	player.held_changed.connect(update_weapon)
	GameState.gear_changed.connect(update_tool_bar)
	update_tool_bar()
	update_health(player.health, player.max_health)
	update_weapon()
	update_quest()


# ============================================================
# UPDATES
# ============================================================

func update_health(current: float, maximum: float):

	health_bar.set_values(current, maximum)
	health_label.text = "VEYL  %d / %d" % [current, maximum]


func update_weapon():

	weapon_label.text = "%s  ·  ATK %d  ·  Max Combo %d" % [GameState.equipped_weapon, player.get_attack() if player else 0, GameState.max_combo]


func update_tool_bar():

	if player == null:
		return
	for child in tool_bar.get_children():
		child.queue_free()
	for i in player.HELD_SLOTS.size():
		var slot = player.HELD_SLOTS[i]
		var gear = GameState.equipped_gear(slot)
		var text = "%d  " % (i + 1)
		if gear.is_empty():
			text += "Fists" if slot == "weapon" else "no %s" % slot
		else:
			text += "%s  %d%%" % [Items.gear_name(gear), ceil(100.0 * gear["durability"] / Items.max_durability(gear))]
		var held = slot == player.held_slot
		tool_bar.add_child(UI.label(text, 17, UI.EMBER if held else UI.MUTED))


func update_combo(count: int, maximum: int, multiplier: float):

	if count <= 0:
		create_tween().tween_property(combo_label, "modulate:a", 0.0, 0.3)
		return

	combo_label.text = "%d HIT%s   ×%.1f" % [count, "S" if count > 1 else "", multiplier]
	combo_label.modulate.a = 1.0
	combo_label.pivot_offset = Vector2(0, 18)
	combo_label.scale = Vector2(1.35, 1.35)
	create_tween().tween_property(combo_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func update_quest():

	var progress = "Defeat creatures  %d / %d" % [GameState.quest_progress, GameState.QUEST_GOAL]

	if GameState.boss_defeated:
		quest_title.text = ""
		quest_text.text = "The forest is quiet."
		return

	match GameState.quest_state:
		GameState.QUEST_NOT_STARTED:
			quest_title.text = "EMBERWOOD"
			quest_text.text = "Find someone who knows these woods."
		GameState.QUEST_ACTIVE:
			quest_title.text = "CLEAR THE FOREST"
			quest_text.text = progress
		GameState.QUEST_RETURN:
			quest_title.text = "CLEAR THE FOREST"
			quest_text.text = progress + "\nReturn to Rowan"
		_:
			quest_title.text = "THE ASHBOUND"
			quest_text.text = "Face what waits beyond the Deep Forest."


# Names the keys or pad buttons in use, and shows the hint again for a while
func show_controls():

	hint.text = Pad.controls_hint()
	hint.modulate.a = 1.0
	if hint_fade:
		hint_fade.kill()
	hint_fade = create_tween()
	hint_fade.tween_property(hint, "modulate:a", 0.0, 2.0).set_delay(30.0)
	for button in buttons.get_children():
		button.text = "%s [%s]" % [button.get_meta("label"), Pad.glyph(button.get_meta("action"))]


func _on_pad_mode_changed():

	show_controls()
	_on_interact_target_changed(player.interact_target if player else null)


func set_buttons_visible(show: bool):

	buttons.visible = show


func _on_interact_target_changed(target):

	prompt.text = target.prompt_text() if target else ""


func _on_boss_engaged(boss):

	boss_box.visible = true
	boss_bar.set_values(boss.health, boss.max_health)
	# The boss bar takes the bottom of the screen; the controls reminder goes
	if hint_fade:
		hint_fade.kill()
	create_tween().tween_property(hint, "modulate:a", 0.0, 0.4)
	if not boss.health_changed.is_connected(_on_boss_health):
		boss.health_changed.connect(_on_boss_health)


func _on_boss_health(current: float, maximum: float):

	boss_bar.set_values(current, maximum)


func toast(text: String):

	var l = UI.label(text, 20, Color(1.0, 0.8, 0.5))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toasts.add_child(l)
	var tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(l, "modulate:a", 0.0, 0.6)
	tween.tween_callback(l.queue_free)


func show_message(text: String):

	message.text = text
	var tween = create_tween()
	tween.tween_property(message, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.0)
	tween.tween_property(message, "modulate:a", 0.0, 0.6)


# A boss's name across the screen, like a chapter heading in a comic:
# black ink bands slide in top and bottom, the name stamps down
func title_card(title: String, subtitle: String):

	var card = Control.new()
	UI.full_rect(card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)

	var bands = []
	for top in [true, false]:
		var band = ColorRect.new()
		band.color = Color(0.02, 0.015, 0.025, 0.92)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		band.custom_minimum_size = Vector2(0, 110)
		band.offset_bottom = 110 if top else 0
		band.offset_top = 0 if top else -110
		band.position.y += -110 if top else 110
		card.add_child(band)
		bands.append([band, band.position.y, band.position.y + (110 if top else -110)])

	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.full_rect(box)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var name_label = UI.title(title.to_upper(), 84, UI.EMBER)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.pivot_offset = Vector2(400, 50)
	box.add_child(name_label)
	var sub_label = UI.label(subtitle, 24, UI.TEXT)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub_label)
	name_label.modulate.a = 0.0
	sub_label.modulate.a = 0.0

	var tween = create_tween().set_parallel()
	for b in bands:
		tween.tween_property(b[0], "position:y", b[2], 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	name_label.scale = Vector2(1.6, 1.6)
	tween.tween_property(name_label, "modulate:a", 1.0, 0.15).set_delay(0.3)
	tween.tween_property(name_label, "scale", Vector2.ONE, 0.25).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sub_label, "modulate:a", 1.0, 0.4).set_delay(0.7)
	tween.chain().tween_interval(1.6)
	tween.chain().tween_property(card, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(card.queue_free)


func fade(alpha: float, duration: float):

	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", alpha, duration)
	await tween.finished


# ============================================================
# MULTIPLAYER
# ============================================================

func _process(delta):

	if not Net.online:
		return
	party_timer -= delta
	if party_timer > 0.0:
		return
	party_timer = 0.25

	var lines = []
	for veyl in get_tree().get_nodes_in_group("remote_players"):
		if veyl.peer_id == NetSync.BOT_ID:
			continue
		var bars = 8
		var filled = int(ceil(clamp(veyl.health / veyl.max_health, 0.0, 1.0) * bars))
		var bar = "fallen" if veyl.dead else "■".repeat(filled) + "□".repeat(bars - filled)
		lines.append("%s  %s" % [Net.name_of(veyl.peer_id), bar])
	party.text = "\n".join(lines)

	var count = "%d / %d players" % [Net.roster.size(), Net.MAX_PLAYERS]
	if Net.is_host():
		var text = "Hosting  ·  %s" % count
		var lan = Net.lan_addresses()
		if not lan.is_empty():
			text += "\nSame Wi-Fi: join %s" % ", ".join(lan)
		if Net.port_status != "":
			text += "\n" + Net.port_status
		session.text = text
	else:
		session.text = "In %s's world  ·  %s" % [Net.name_of(1), count]

