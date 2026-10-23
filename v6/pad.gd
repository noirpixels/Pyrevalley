extends Node

# Controller support. Sets up the input actions (keyboard and gamepad),
# tracks whether a pad is in use and what kind, so prompts can name the
# right buttons, gives menus focus so a pad can drive them, presses BACK
# on B, and rumbles.
#
# Pad buttons below are named by position, the way Godot reports them:
# JOY_BUTTON_A is the bottom face button on every pad, which Nintendo
# labels B. Nintendo pads also get Nintendo's menu buttons: A (right)
# confirms and B (bottom) backs out.
#
#   Left stick  move            ZL / ZR  strike left / right
#   Right stick aim             X (top)  launch      Y (left)  slam
#   B (bottom)  jump            A (right) interact   R  dodge
#   +  pause    -  inventory    L  codex             D-pad up/down  zoom
#   D-pad left/right  switch between weapon, pickaxe and axe (keys 1 2 3)

signal mode_changed

# Each entry is a key, a pad button {"button"}, or a stick/trigger {"axis", "dir"}
const ACTIONS = {
	"move_left": [KEY_A, KEY_LEFT, {"axis": JOY_AXIS_LEFT_X, "dir": -1.0}],
	"move_right": [KEY_D, KEY_RIGHT, {"axis": JOY_AXIS_LEFT_X, "dir": 1.0}],
	"move_up": [KEY_W, KEY_UP, {"axis": JOY_AXIS_LEFT_Y, "dir": -1.0}],
	"move_down": [KEY_S, KEY_DOWN, {"axis": JOY_AXIS_LEFT_Y, "dir": 1.0}],
	"aim_left": [{"axis": JOY_AXIS_RIGHT_X, "dir": -1.0}],
	"aim_right": [{"axis": JOY_AXIS_RIGHT_X, "dir": 1.0}],
	"aim_up": [{"axis": JOY_AXIS_RIGHT_Y, "dir": -1.0}],
	"aim_down": [{"axis": JOY_AXIS_RIGHT_Y, "dir": 1.0}],
	"jump": [KEY_SPACE, {"button": JOY_BUTTON_A}],
	"dash": [KEY_SHIFT, {"button": JOY_BUTTON_RIGHT_SHOULDER}],
	"interact": [KEY_E, {"button": JOY_BUTTON_B}],
	"strike_left": [{"axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1.0}],
	"strike_right": [{"axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1.0}],
	"launch": [{"button": JOY_BUTTON_Y}],
	"slam": [{"button": JOY_BUTTON_X}],
	"pause": [KEY_ESCAPE, {"button": JOY_BUTTON_START}],
	"inventory": [KEY_I, {"button": JOY_BUTTON_BACK}],
	"codex": [KEY_C, {"button": JOY_BUTTON_LEFT_SHOULDER}],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD, {"button": JOY_BUTTON_DPAD_UP}],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT, {"button": JOY_BUTTON_DPAD_DOWN}],
	# Tool bar: weapon, pickaxe, axe
	"tool_1": [KEY_1],
	"tool_2": [KEY_2],
	"tool_3": [KEY_3],
	"tool_prev": [{"button": JOY_BUTTON_DPAD_LEFT}],
	"tool_next": [{"button": JOY_BUTTON_DPAD_RIGHT}],
}

# Local Duel (duel.gd): two players on one keyboard, combat keys only.
# {"key", "location"} tells left and right Shift apart.
const DUEL_ACTIONS = {
	"p1_move_left": [KEY_A], "p1_move_right": [KEY_D], "p1_move_up": [KEY_W], "p1_move_down": [KEY_S],
	"p1_strike_left": [KEY_X], "p1_strike_right": [KEY_C], "p1_launch": [KEY_Q], "p1_slam": [KEY_E],
	"p1_jump": [KEY_G], "p1_dash": [{"key": KEY_SHIFT, "location": KEY_LOCATION_LEFT}],
	"p2_move_left": [KEY_LEFT], "p2_move_right": [KEY_RIGHT], "p2_move_up": [KEY_UP], "p2_move_down": [KEY_DOWN],
	"p2_strike_left": [KEY_SLASH], "p2_strike_right": [{"key": KEY_SHIFT, "location": KEY_LOCATION_RIGHT}],
	"p2_launch": [KEY_COMMA], "p2_slam": [KEY_PERIOD], "p2_jump": [KEY_L], "p2_dash": [KEY_SEMICOLON],
}

# Stick tilt needed before it counts; triggers need a firmer pull
const STICK_DEADZONE = 0.25
const TRIGGER_DEADZONE = 0.5

# What each pad calls its buttons
const GLYPHS = {
	"nintendo": {
		JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
		JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R",
		JOY_BUTTON_START: "+", JOY_BUTTON_BACK: "-",
		"lt": "ZL", "rt": "ZR",
	},
	"xbox": {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View",
		"lt": "LT", "rt": "RT",
	},
	"playstation": {
		JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
		JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Create",
		"lt": "L2", "rt": "R2",
	},
}

var using_pad: bool = false
var layout: String = "xbox"
var device: int = 0

var focus_check: float = 0.0


func _ready():

	process_mode = Node.PROCESS_MODE_ALWAYS

	for action in ACTIONS:
		var deadzone = TRIGGER_DEADZONE if action.begins_with("strike") else STICK_DEADZONE
		if not InputMap.has_action(action):
			InputMap.add_action(action, deadzone)
		for entry in ACTIONS[action]:
			InputMap.action_add_event(action, make_event(entry))
	for action in DUEL_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for entry in DUEL_ACTIONS[action]:
			InputMap.action_add_event(action, make_event(entry))

	# Menu navigation on the D-pad and left stick
	for dir in [["ui_left", JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0],
			["ui_up", JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0]]:
		InputMap.action_add_event(dir[0], make_event({"button": dir[1]}))
		InputMap.action_add_event(dir[0], make_event({"axis": dir[2], "dir": dir[3]}))
	set_menu_buttons()

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads = Input.get_connected_joypads()
	if not pads.is_empty():
		set_layout(pads[0])


func make_event(entry) -> InputEvent:

	if entry is int:
		var key = InputEventKey.new()
		key.keycode = entry
		return key
	if entry.has("key"):
		# Godot only tells left from right on the physical key
		var sided = InputEventKey.new()
		sided.physical_keycode = entry["key"]
		sided.location = entry["location"]
		return sided
	if entry.has("button"):
		var button = InputEventJoypadButton.new()
		button.button_index = entry["button"]
		return button
	var motion = InputEventJoypadMotion.new()
	motion.axis = entry["axis"]
	motion.axis_value = entry["dir"]
	return motion


func pad_events(action: String) -> Array:

	return InputMap.action_get_events(action).filter(func(e): return e is InputEventJoypadButton)


# ============================================================
# WHICH INPUT IS IN USE
# ============================================================

func _input(event):

	var pad_now = using_pad
	if event is InputEventJoypadButton and event.pressed:
		pad_now = true
	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
		pad_now = true
	elif event is InputEventKey and event.pressed:
		pad_now = false
	elif event is InputEventMouseButton and event.pressed:
		pad_now = false
	elif event is InputEventMouseMotion and event.relative.length() > 4.0:
		pad_now = false
	elif event is InputEventPanGesture:
		pad_now = false

	if pad_now and (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device != device:
		set_layout(event.device)

	if pad_now != using_pad:
		using_pad = pad_now
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if using_pad else Input.MOUSE_MODE_VISIBLE
		if not using_pad:
			# Don't leave a pad-focused button highlighted under the mouse
			var focused = get_viewport().gui_get_focus_owner()
			if focused:
				focused.release_focus()
		mode_changed.emit()


func set_layout(pad: int):

	device = pad
	var joy_name = Input.get_joy_name(pad).to_lower()
	var before = layout
	layout = "xbox"
	for word in ["nintendo", "switch", "joy-con", "pro controller"]:
		if word in joy_name:
			layout = "nintendo"
	for word in ["playstation", "dualsense", "dualshock", "ps4", "ps5", "sony"]:
		if word in joy_name:
			layout = "playstation"

	set_menu_buttons()
	if layout != before:
		mode_changed.emit()


# Confirm is the bottom button and back the right one, except on Nintendo
# pads: A (right) confirms and B (bottom) backs out
func set_menu_buttons():

	for action in ["ui_accept", "ui_cancel"]:
		for e in pad_events(action):
			InputMap.action_erase_event(action, e)
	var swap = layout == "nintendo"
	InputMap.action_add_event("ui_accept", make_event({"button": JOY_BUTTON_B if swap else JOY_BUTTON_A}))
	InputMap.action_add_event("ui_cancel", make_event({"button": JOY_BUTTON_A if swap else JOY_BUTTON_B}))


func _on_joy_connection_changed(pad: int, connected: bool):

	if connected:
		set_layout(pad)
	elif pad == device and using_pad:
		using_pad = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mode_changed.emit()


# ============================================================
# BUTTON NAMES
# ============================================================

# What to press for an action, named for the controller in use
func glyph(action: String) -> String:

	for e in InputMap.action_get_events(action):
		if using_pad and e is InputEventJoypadButton:
			return button_name(e.button_index)
		if using_pad and e is InputEventJoypadMotion:
			match e.axis:
				JOY_AXIS_TRIGGER_LEFT:
					return GLYPHS[layout]["lt"]
				JOY_AXIS_TRIGGER_RIGHT:
					return GLYPHS[layout]["rt"]
				JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
					return "Left stick"
				_:
					return "Right stick"
		if not using_pad and e is InputEventKey:
			return OS.get_keycode_string(e.keycode)
	return "?"


func button_name(button: int) -> String:

	match button:
		JOY_BUTTON_DPAD_UP:
			return "D-pad Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-pad Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-pad Right"
	return GLYPHS[layout].get(button, "?")


# The one-line controls reminder for the HUD
func controls_hint() -> String:

	if not using_pad:
		return "WASD move · Mouse aim · Left/right click strike · Scroll up launch · Scroll down slam · Space jump · Shift dodge · E interact · -/= zoom"
	return "%s move · %s aim · %s/%s strike · %s launch · %s slam · %s jump · %s dodge · %s interact · D-pad zoom · %s pause" % [
		glyph("move_left"), glyph("aim_left"), glyph("strike_left"), glyph("strike_right"),
		glyph("launch"), glyph("slam"), glyph("jump"), glyph("dash"), glyph("interact"), glyph("pause"),
	]


# ============================================================
# MENUS
# ============================================================

# A pad can't click, so give a menu focus when one is showing and nothing
# has it. Only while paused, a menu is open, or outside the game, so a HUD
# button never eats a gameplay press.
func _process(delta):

	focus_check -= delta
	if not using_pad or focus_check > 0.0:
		return
	focus_check = 0.15
	if get_viewport().gui_get_focus_owner():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not get_tree().paused and player and not player.input_blocked:
		return
	var button = first_button(get_tree().root)
	if button:
		button.grab_focus()


func first_button(node: Node) -> Button:

	if node is CanvasItem and not node.visible:
		return null
	if node is Button and node.focus_mode != Control.FOCUS_NONE and not node.disabled and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found = first_button(child)
		if found:
			return found
	return null


# B on a screen with a BACK button presses it (the codex, settings, credits)
func _unhandled_input(event):

	if not (event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")):
		return
	var back = find_back(get_tree().root)
	if back:
		get_viewport().set_input_as_handled()
		back.pressed.emit()


func find_back(node: Node) -> Button:

	if node is CanvasItem and not node.visible:
		return null
	if node is Button and node.name == "BackButton" and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found = find_back(child)
		if found:
			return found
	return null


# ============================================================
# RUMBLE
# ============================================================

func rumble(weak: float, strong: float, duration: float):

	if using_pad:
		Input.start_joy_vibration(device, weak, strong, duration)
