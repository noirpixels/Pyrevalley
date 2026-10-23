extends Control

# Minimal HUD: HP, weapon, quest, inventory/codex/pause buttons,
# boss bar, interaction prompt, notifications and the respawn fade.

signal inventory_pressed
signal codex_pressed
signal pause_pressed

const UI = preload("res://ui_kit.gd")

var player: Node3D
var health_bar: ProgressBar
var health_label: Label
var weapon_label: Label
var combo_label: Label
var quest_title: Label
var quest_text: Label
var buttons: HBoxContainer
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var prompt: Label
var hint: Label
var hint_fade: Tween
var toasts: VBoxContainer
var message: Label
var fade_rect: ColorRect


func _ready():

	UI.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ---- HP + weapon (top-left) ----
	var status = VBoxContainer.new()
	status.position = Vector2(24, 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)

	health_label = UI.label("VEYL", 20)
	status.add_child(health_label)
	health_bar = make_bar(Vector2(280, 16), Color(0.9, 0.35, 0.1))
	status.add_child(health_bar)
	weapon_label = UI.label("", 16, UI.MUTED)
	status.add_child(weapon_label)
	combo_label = UI.label("", 22, Color(1.0, 0.85, 0.3))
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

	quest_title = UI.label("", 18, UI.EMBER)
	quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(quest_title)
	quest_text = UI.label("", 16)
	quest_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(quest_text)

	buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(buttons)
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
	boss_box.offset_left = -300
	boss_box.offset_right = 300
	boss_box.offset_top = -72
	boss_box.offset_bottom = -20
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	add_child(boss_box)
	var boss_name = UI.label("THE ASHBOUND", 24, UI.EMBER)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	boss_bar = make_bar(Vector2(600, 20), Color(0.75, 0.12, 0.05))
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

	# ---- Controls hint (bottom-left), fades after a while ----
	hint = UI.label("", 14, UI.MUTED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -36
	add_child(hint)
	show_controls()
	Pad.mode_changed.connect(_on_pad_mode_changed)

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
	update_health(player.health, player.max_health)
	update_weapon()
	update_quest()


func make_bar(size: Vector2, color: Color) -> ProgressBar:

	var bar = ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.08, 0.08, 0.85)
	bar.add_theme_stylebox_override("background", bg)
	return bar


# ============================================================
# UPDATES
# ============================================================

func update_health(current: float, maximum: float):

	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "VEYL  %d / %d" % [current, maximum]


func update_weapon():

	weapon_label.text = "%s  ·  ATK %d  ·  Max Combo %d" % [GameState.equipped_weapon, player.get_attack() if player else 0, GameState.max_combo]


func update_combo(count: int, maximum: int, multiplier: float):

	if count <= 0:
		create_tween().tween_property(combo_label, "modulate:a", 0.0, 0.3)
		return

	combo_label.text = "%d / %d HITS   ×%.1f" % [count, maximum, multiplier]
	combo_label.modulate.a = 1.0
	combo_label.scale = Vector2(1.2, 1.2)
	create_tween().tween_property(combo_label, "scale", Vector2.ONE, 0.12)


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
	boss_bar.max_value = boss.max_health
	boss_bar.value = boss.health
	if not boss.health_changed.is_connected(_on_boss_health):
		boss.health_changed.connect(_on_boss_health)


func _on_boss_health(current: float, maximum: float):

	boss_bar.max_value = maximum
	boss_bar.value = current


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


func fade(alpha: float, duration: float):

	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", alpha, duration)
	await tween.finished
