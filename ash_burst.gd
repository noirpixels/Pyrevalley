extends Node3D

# A creature crumbling to ash: dark flakes blown outward and up, a puff of
# smoke, and embers that keep rising after the rest has settled.
#   AshBurst.spawn(parent, position, size)

static func spawn(parent: Node, pos: Vector3, size: float = 1.0) -> void:

	var burst = load("res://ash_burst.gd").new()
	burst.size = size
	parent.add_child(burst)
	burst.global_position = pos


var size: float = 1.0


func _ready():

	# Ash flakes
	add_child(emitter(int(40 * size), 1.2, Color(0.1, 0.08, 0.09), Color(0.25, 0.22, 0.22, 0.0),
			Vector3(0, 1, 0), 70.0, 6.0 * size, 14.0 * size, Vector3(0, -6, 0), 0.25 * size, 0.6 * size))
	# Smoke puff
	add_child(emitter(int(10 * size), 0.9, Color(0.18, 0.16, 0.18, 0.7), Color(0.18, 0.16, 0.18, 0.0),
			Vector3(0, 1, 0), 60.0, 2.0 * size, 5.0 * size, Vector3(0, 1.5, 0), 1.0 * size, 2.2 * size))
	# Rising embers
	add_child(emitter(int(24 * size), 1.8, Color(1.0, 0.8, 0.4), Color(1.0, 0.25, 0.05, 0.0),
			Vector3(0, 1, 0), 40.0, 3.0 * size, 9.0 * size, Vector3(0, 3, 0), 0.12 * size, 0.28 * size))
	get_tree().create_timer(2.2).timeout.connect(queue_free)


func emitter(count: int, life: float, start: Color, end: Color, dir: Vector3, spread_deg: float,
		v_min: float, v_max: float, grav: Vector3, s_min: float, s_max: float) -> CPUParticles3D:

	var p = CPUParticles3D.new()
	p.amount = max(count, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.8 * size
	p.direction = dir
	p.spread = spread_deg
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = grav
	p.damping_min = 4.0
	p.damping_max = 8.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = s_min
	p.scale_amount_max = s_max
	var ramp = Gradient.new()
	ramp.set_color(0, start)
	ramp.set_color(1, end)
	p.color_ramp = ramp

	var quad = QuadMesh.new()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.render_priority = 5
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p
