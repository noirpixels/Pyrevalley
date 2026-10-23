extends Control

# A health bar in the inked style: a pale "damage trail" lingers behind
# the fill after a hit and then drains down to it, so big hits read.
# Optional notches mark thresholds (the boss's half-health phase).


var front: ProgressBar
var trail: ProgressBar
var trail_tween: Tween
var notches: Array = []


func _init(size: Vector2, fill: Color, notch_at: Array = []):

	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	notches = notch_at

	trail = ProgressBar.new()
	trail.show_percentage = false
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var trail_fill = StyleBoxFlat.new()
	trail_fill.bg_color = Color(1.0, 0.92, 0.75)
	trail.add_theme_stylebox_override("fill", trail_fill)
	trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(trail)

	front = ProgressBar.new()
	front.show_percentage = false
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var front_fill = StyleBoxFlat.new()
	front_fill.bg_color = fill
	front_fill.border_color = fill.lightened(0.35)
	front_fill.border_width_top = 2
	front.add_theme_stylebox_override("fill", front_fill)
	front.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(front)

	# Notches go on a layer of their own, above the fill
	if not notches.is_empty():
		var layer = Control.new()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.draw.connect(draw_notches.bind(layer))
		add_child(layer)


func set_values(current: float, maximum: float):

	var dropped = current < front.value
	front.max_value = maximum
	trail.max_value = maximum
	front.value = current
	if not dropped:
		trail.value = current
		return
	if trail_tween:
		trail_tween.kill()
	trail_tween = create_tween()
	trail_tween.tween_interval(0.35)
	trail_tween.tween_property(trail, "value", current, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# A jolt so a hit is felt in the HUD too
	var start = position
	var jolt = create_tween()
	jolt.tween_property(self, "position", start + Vector2(randf_range(-4, 4), 3), 0.04)
	jolt.tween_property(self, "position", start, 0.08)


# Ink notches at thresholds
func draw_notches(layer: Control):

	for at in notches:
		var x = layer.size.x * at
		layer.draw_line(Vector2(x, -4), Vector2(x, layer.size.y + 4), Color(0.035, 0.028, 0.045), 4.0)
		layer.draw_line(Vector2(x, -4), Vector2(x, layer.size.y + 4), Color(1.0, 0.85, 0.6, 0.8), 1.5)
