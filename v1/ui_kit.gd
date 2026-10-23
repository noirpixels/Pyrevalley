extends RefCounted

# Shared look for the code-built UI panels.

const EMBER = Color(1.0, 0.55, 0.2)
const TEXT = Color(0.92, 0.88, 0.82)
const MUTED = Color(0.65, 0.6, 0.55)


static func label(text: String, size: int, color: Color = TEXT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.05, 0.92)
	style.border_color = Color(0.55, 0.25, 0.1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	return style


static func button(text: String, callback: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(callback)
	return b


static func centered(control: Control) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH
	return control


static func full_rect(control: Control) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control
