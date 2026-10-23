extends Node3D

# The look of a wall of embers (gate.gd, arena_seal.gd): a flame curtain
# (ember_wall.gdshader), rising sparks and a light.
# set_strength(0..1) raises or dies it down; 0 hides it.
# A campfire is the same thing, small, with its two curtains crossed.

const SHADER = preload("res://ember_wall.gdshader")

var width: float = 20.0
var height: float = 9.0
var campfire: bool = false
var strength: float = 1.0
var mat: ShaderMaterial
var sparks: CPUParticles3D
var light: OmniLight3D


func _init(wall_width: float, wall_height: float = 9.0, is_campfire: bool = false):

	width = wall_width
	height = wall_height
	campfire = is_campfire


func _ready():

	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("columns", max(width / 2.6, 1.6))
	# After the ink post pass, so the fire stays bright
	mat.render_priority = 10

	# Two curtains so it has body from the isometric angle; crossed for a campfire
	for i in 2:
		var curtain = MeshInstance3D.new()
		var quad = QuadMesh.new()
		quad.size = Vector2(width, height)
		curtain.mesh = quad
		curtain.material_override = mat
		curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		curtain.position = Vector3(0, height / 2.0, 0.0 if campfire else [-0.4, 0.4][i])
		if campfire:
			curtain.rotation.y = i * PI / 2.0
		add_child(curtain)

	sparks = CPUParticles3D.new()
	sparks.amount = max(int(width * 2.5), 8)
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(width / 2.0, 0.3, 0.6)
	sparks.direction = Vector3.UP
	sparks.spread = 20.0
	sparks.gravity = Vector3(0, 2.0, 0)
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.2
	var ramp = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	ramp.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	sparks.color_ramp = ramp
	var quad = QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var spark_mat = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.render_priority = 10
	spark_mat.albedo_texture = preload("res://fx.gd").soft_dot()
	quad.material = spark_mat
	sparks.mesh = quad
	add_child(sparks)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.12)
	light.omni_range = width * 0.6
	light.position = Vector3(0, 3.0, 2.0)
	add_child(light)

	set_strength(strength)


func set_strength(value: float):

	strength = value
	visible = value > 0.001
	if mat == null:
		return
	mat.set_shader_parameter("strength", value)
	sparks.emitting = value > 0.3
	light.light_energy = 2.5 * value


# Tween helper: raise or lower the wall over time
func fade_to(value: float, duration: float) -> Tween:

	var tween = create_tween()
	tween.tween_method(set_strength, strength, value, duration)
	return tween
