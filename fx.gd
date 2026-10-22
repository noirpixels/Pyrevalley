extends Node2D

# Cheap one-off effects drawn in one place: ember bursts and sparks (little
# glowing streaks with gravity), and floating numbers. Anything can reach
# it through the "fx" group.

const FONT_SIZE = 30

var particles = []   # {"pos", "vel", "life", "max", "color", "size"}


func _ready():

	add_to_group("fx")
	z_index = 40


# count embers flung out from at, up to speed px/s
func burst(at: Vector2, color: Color, count: int, speed: float, up_bias: float = 0.4):

	for i in count:
		var angle = randf() * TAU
		var dir = Vector2(cos(angle), sin(angle) - up_bias).normalized()
		var life = randf_range(0.3, 0.7)
		particles.append({"pos": at, "vel": dir * randf_range(speed * 0.3, speed), "life": life, "max": life, "color": color, "size": randf_range(2.0, 5.0)})


# Sparks thrown mostly along dir, for hits
func sparks(at: Vector2, dir: Vector2, color: Color, count: int):

	for i in count:
		var spread = dir.normalized().rotated(randf_range(-0.9, 0.9))
		var life = randf_range(0.15, 0.4)
		particles.append({"pos": at, "vel": spread * randf_range(200.0, 700.0), "life": life, "max": life, "color": color, "size": randf_range(2.0, 4.0)})


# Clods of dirt or chips of rock from a pickaxe strike
func debris(at: Vector2, color: Color, count: int):

	for i in count:
		var vel = Vector2(randf_range(-220.0, 220.0), randf_range(-420.0, -120.0))
		var life = randf_range(0.4, 0.8)
		particles.append({"pos": at, "vel": vel, "life": life, "max": life, "color": color, "size": randf_range(3.0, 6.0), "heavy": true})


func number(at: Vector2, text: String, color: Color, size: int = FONT_SIZE):

	var label = Label.new()
	label.text = text
	label.add_theme_font_override("font", Style.display_bold)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.position = at - Vector2(40, 20)
	label.size = Vector2(80, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 50
	add_child(label)
	var tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 60.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


func _process(delta):

	for p in particles:
		p["life"] -= delta
		p["vel"].y += (1400.0 if p.get("heavy") else 500.0) * delta
		p["vel"] *= 0.98
		p["pos"] += p["vel"] * delta
	particles = particles.filter(func(p): return p["life"] > 0.0)
	queue_redraw()


func _draw():

	for p in particles:
		var t = p["life"] / p["max"]
		var c: Color = p["color"]
		c.a = t
		if p.get("heavy"):
			draw_rect(Rect2(p["pos"] - Vector2.ONE * p["size"] / 2.0, Vector2.ONE * p["size"]), c)
		else:
			var tail = p["pos"] - p["vel"] * 0.02
			draw_line(tail, p["pos"], c, p["size"] * t + 1.0)
