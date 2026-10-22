extends Node

# Pyrevalley's look for every UI screen, applied to the root window so the
# code-built panels and the scene-built menus (main menu, codex, settings,
# credits) all share it: inked dark panels with an ember edge, carved
# Cinzel capitals for names and titles, Alegreya for reading.
# Fonts are under the SIL Open Font License (Fonts/OFL-*.txt).

const INK = Color(0.035, 0.028, 0.045)
const PAPER = Color(0.06, 0.045, 0.05, 0.95)
const EMBER = Color(1.0, 0.55, 0.2)
const EMBER_DEEP = Color(0.55, 0.2, 0.08)
const TEXT = Color(0.93, 0.88, 0.8)
const MUTED = Color(0.65, 0.6, 0.55)

var body_font: Font
var display_font: Font
var display_bold: Font


func _ready():

	var ts = TextServerManager.get_primary_interface()
	var alegreya = load("res://Fonts/Alegreya.ttf")
	var cinzel = load("res://Fonts/Cinzel.ttf")

	body_font = variation(alegreya, ts.name_to_tag("wght"), 500)
	display_font = variation(cinzel, ts.name_to_tag("wght"), 600)
	display_bold = variation(cinzel, ts.name_to_tag("wght"), 800)

	# In-world text (Label3D) and anything without a theme
	ThemeDB.fallback_font = body_font
	get_tree().root.theme = build_theme()


func variation(base: Font, tag: int, weight: int) -> FontVariation:

	var v = FontVariation.new()
	v.base_font = base
	v.variation_opentype = {tag: weight}
	return v


func box(bg: Color, border: Color, width: int = 2, margin: float = 10.0) -> StyleBoxFlat:

	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(margin)
	s.anti_aliasing = false
	return s


func panel() -> StyleBoxFlat:

	var s = box(PAPER, EMBER_DEEP, 3, 26.0)
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 10
	s.shadow_offset = Vector2(4, 6)
	return s


func build_theme() -> Theme:

	var t = Theme.new()
	t.default_font = body_font
	t.default_font_size = 19

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color.BLACK)
	t.set_constant("outline_size", "Label", 6)

	# Buttons: ink plates; hover warms them; focus (a pad or keyboard) gets
	# a bright ember frame so it's obvious which one A / Enter will press
	var normal = box(Color(0.08, 0.06, 0.06, 0.92), Color(0.3, 0.14, 0.08), 2)
	normal.border_width_bottom = 4
	var hover = box(Color(0.16, 0.08, 0.05, 0.95), EMBER_DEEP.lightened(0.2), 2)
	hover.border_width_bottom = 4
	var pressed = box(Color(0.3, 0.12, 0.05, 0.95), EMBER, 2)
	pressed.border_width_top = 4
	pressed.border_width_bottom = 2
	var focus = box(Color(0, 0, 0, 0), EMBER, 3)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	var disabled = box(Color(0.05, 0.04, 0.04, 0.7), Color(0.15, 0.1, 0.08), 2)
	for type in ["Button", "MenuButton", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, disabled)
		t.set_font("font", type, display_font)
		t.set_font_size("font_size", type, 18)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1.0, 0.85, 0.6))
		t.set_color("font_focus_color", type, Color(1.0, 0.85, 0.6))
		t.set_color("font_pressed_color", type, EMBER)
		t.set_color("font_disabled_color", type, Color(0.4, 0.36, 0.33))
		t.set_color("font_outline_color", type, Color.BLACK)
		t.set_constant("outline_size", type, 4)

	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())

	var bar_bg = box(Color(0.04, 0.03, 0.035, 0.9), INK, 2, 0.0)
	var bar_fill = box(Color(0.85, 0.3, 0.08), Color(1.0, 0.65, 0.35), 0, 0.0)
	bar_fill.border_width_top = 2
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)

	var grabber = box(EMBER_DEEP, EMBER_DEEP, 0, 0.0)
	var scroll_bg = box(Color(0.05, 0.04, 0.04, 0.6), Color(0, 0, 0, 0), 0, 0.0)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, scroll_bg)
		t.set_stylebox("grabber", type, grabber)
		t.set_stylebox("grabber_highlight", type, box(EMBER, EMBER, 0, 0.0))
		t.set_stylebox("grabber_pressed", type, box(EMBER, EMBER, 0, 0.0))

	return t
