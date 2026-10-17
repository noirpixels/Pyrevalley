extends PanelContainer

# Bottom-of-screen dialogue with a typewriter effect.
# E / Space / Enter / click: finish the line, then advance.

signal closed

const UI = preload("res://ui_kit.gd")
const CHARS_PER_SECOND = 45.0

var speaker_label: Label
var hint: Label
var text_label: Label
var lines: Array = []
var index: int = 0
var on_done: Callable
var typing: Tween


func _ready():

	add_theme_stylebox_override("panel", UI.panel_style())

	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -420
	offset_right = 420
	offset_top = -200
	offset_bottom = -40
	visible = false

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	speaker_label = UI.title("", 24, UI.EMBER)
	box.add_child(speaker_label)

	text_label = UI.label("", 22)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(780, 60)
	box.add_child(text_label)

	hint = UI.label("", 14, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)


func start(speaker: String, new_lines: Array, done: Callable = Callable()):

	speaker_label.text = speaker
	hint.text = "[%s] continue" % Pad.glyph("interact")
	lines = new_lines
	index = 0
	on_done = done
	visible = true
	show_line()


func show_line():

	text_label.text = lines[index]
	text_label.visible_ratio = 0.0
	typing = create_tween()
	typing.tween_property(text_label, "visible_ratio", 1.0, lines[index].length() / CHARS_PER_SECOND)


func _input(event):

	if not visible:
		return

	var advance = false
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		advance = true
	elif event is InputEventMouseButton and event.pressed:
		advance = event.button_index == MOUSE_BUTTON_LEFT

	if not advance:
		return

	get_viewport().set_input_as_handled()

	if typing and typing.is_running():
		typing.kill()
		text_label.visible_ratio = 1.0
		return

	index += 1
	if index < lines.size():
		Sfx.play("npc", -4.0)
		show_line()
	else:
		visible = false
		closed.emit()
		if on_done.is_valid():
			on_done.call()
