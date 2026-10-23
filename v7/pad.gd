extends Node

# Every input action, registered in code so the bindings live in one place:
# keyboard and mouse, and a gamepad alongside them.
#
#   Move          A / D (or arrows), left stick, d-pad
#   Look up/down  W / S: aims a strike up (launch) or down (slam)
#   Jump          Space, pad A
#   Dash          Shift, pad B
#   Strike        Left click or J, pad X        (with W: launch, with S: slam)
#   Heavy         Right click or K, pad Y
#   Launch / Slam Scroll up / scroll down
#   Dig           F, pad LB (toward the mouse, or where Veyl looks)
#   Interact      E, pad RB
#   Map           M or Tab, pad Back
#   Pack          I, pad d-pad up
#   Pause         Esc, pad Start

const ACTIONS = {
	"move_left": [KEY_A, KEY_LEFT, {"joy_axis": JOY_AXIS_LEFT_X, "dir": -1.0}, {"joy_button": JOY_BUTTON_DPAD_LEFT}],
	"move_right": [KEY_D, KEY_RIGHT, {"joy_axis": JOY_AXIS_LEFT_X, "dir": 1.0}, {"joy_button": JOY_BUTTON_DPAD_RIGHT}],
	"move_up": [KEY_W, KEY_UP, {"joy_axis": JOY_AXIS_LEFT_Y, "dir": -1.0}],
	"move_down": [KEY_S, KEY_DOWN, {"joy_axis": JOY_AXIS_LEFT_Y, "dir": 1.0}, {"joy_button": JOY_BUTTON_DPAD_DOWN}],
	"jump": [KEY_SPACE, {"joy_button": JOY_BUTTON_A}],
	"dash": [KEY_SHIFT, {"joy_button": JOY_BUTTON_B}],
	"strike": [KEY_J, {"mouse": MOUSE_BUTTON_LEFT}, {"joy_button": JOY_BUTTON_X}],
	"heavy": [KEY_K, {"mouse": MOUSE_BUTTON_RIGHT}, {"joy_button": JOY_BUTTON_Y}],
	"launch": [{"mouse": MOUSE_BUTTON_WHEEL_UP}],
	"slam": [{"mouse": MOUSE_BUTTON_WHEEL_DOWN}],
	"dig": [KEY_F, {"joy_button": JOY_BUTTON_LEFT_SHOULDER}],
	"interact": [KEY_E, {"joy_button": JOY_BUTTON_RIGHT_SHOULDER}],
	"map": [KEY_M, KEY_TAB, {"joy_button": JOY_BUTTON_BACK}],
	"pack": [KEY_I, {"joy_button": JOY_BUTTON_DPAD_UP}],
	"pause": [KEY_ESCAPE, {"joy_button": JOY_BUTTON_START}],
}

const DEADZONE = 0.35

# True once a gamepad has been used, until the mouse moves again: digging
# then aims with the stick instead of the cursor
var using_pad: bool = false


func _ready():

	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, DEADZONE)
		for binding in ACTIONS[action]:
			InputMap.action_add_event(action, make_event(binding))


func make_event(binding) -> InputEvent:

	if binding is int:
		var key = InputEventKey.new()
		key.physical_keycode = binding
		return key
	if binding.has("mouse"):
		var mouse = InputEventMouseButton.new()
		mouse.button_index = binding["mouse"]
		return mouse
	if binding.has("joy_axis"):
		var axis = InputEventJoypadMotion.new()
		axis.axis = binding["joy_axis"]
		axis.axis_value = binding["dir"]
		return axis
	var button = InputEventJoypadButton.new()
	button.button_index = binding["joy_button"]
	return button


func _input(event):

	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and abs(event.axis_value) > DEADZONE):
		using_pad = true
	elif event is InputEventMouseMotion and event.relative.length() > 2.0:
		using_pad = false


func rumble(weak: float, strong: float, duration: float):

	if using_pad:
		Input.start_joy_vibration(0, weak, strong, duration)
