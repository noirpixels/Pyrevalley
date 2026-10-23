extends Control

# Animated Emberwood backdrop for the main menu: painted layers (see
# tools/make_menu_background.py) that parallax with the mouse, drifting fog,
# a pulsing sun glow and embers rising from the forest floor.

const LAYERS = [
	# texture, parallax strength in pixels
	[preload("res://Menu/sky.png"), 8.0],
	[preload("res://Menu/far.png"), 16.0],
	[preload("res://Menu/mid.png"), 28.0],
	[preload("res://Menu/near.png"), 48.0],
]
const MARGIN = 60.0  # layers overhang the screen so parallax never shows an edge
const FOG_SHADER = preload("res://menu_fog.gdshader")

var _layers: Array[TextureRect] = []
var _strengths: Array[float] = []
var _look := Vector2.ZERO
var _time := 0.0
var _embers: CPUParticles2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in LAYERS.size():
		var rect = TextureRect.new()
		rect.texture = LAYERS[i][0]
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_layers.append(rect)
		_strengths.append(LAYERS[i][1])
		if i == 2:
			# Mist settles between the mid trees and the foreground.
			add_child(_overlay(0.9, 0.0, 1.0))
	_embers = _make_embers()
	add_child(_embers)
	# Low mist in front, then the vignette that frames the menu.
	add_child(_overlay(0.3, 0.75, 0.0))
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_time += delta
	var target = Vector2.ZERO
	if size.x > 0 and size.y > 0:
		target = (get_local_mouse_position() / size - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	_look = _look.lerp(target, 1.0 - exp(-delta * 3.0))
	var drift = Vector2(sin(_time * 0.21), sin(_time * 0.17) * 0.5) * 0.08
	for i in _layers.size():
		_layers[i].position = Vector2(-MARGIN, -MARGIN) - (_look + drift) * _strengths[i] * 2.0


func _layout() -> void:
	for rect in _layers:
		rect.size = size + Vector2(MARGIN, MARGIN) * 2.0
	if _embers:
		_embers.position = Vector2(size.x * 0.5, size.y + 10.0)
		_embers.emission_rect_extents = Vector2(size.x * 0.55, 10.0)


func _overlay(fog: float, vignette: float, glow: float) -> ColorRect:
	var rect = ColorRect.new()
	var mat = ShaderMaterial.new()
	mat.shader = FOG_SHADER
	mat.set_shader_parameter("fog_strength", fog)
	mat.set_shader_parameter("vignette", vignette)
	mat.set_shader_parameter("glow", glow)
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


func _make_embers() -> CPUParticles2D:
	var dot = GradientTexture2D.new()
	dot.width = 16
	dot.height = 16
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.gradient = Gradient.new()
	dot.gradient.set_color(0, Color(1, 1, 1, 1))
	dot.gradient.set_color(1, Color(1, 1, 1, 0))

	var fade = Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 0.85, 0.5, 0.0),
		Color(1.0, 0.7, 0.3, 1.0),
		Color(1.0, 0.4, 0.15, 0.8),
		Color(0.8, 0.2, 0.1, 0.0),
	])

	var p = CPUParticles2D.new()
	p.texture = dot
	p.amount = 80
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -12)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 70.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.tangential_accel_min = -15.0
	p.tangential_accel_max = 15.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.75
	p.color_ramp = fade
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p
