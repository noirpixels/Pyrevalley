extends CPUParticles3D

# One-off burst of embers where Veyl's sword connects.

const LIFETIME = 0.35


static func spawn(parent: Node, pos: Vector3, dir: Vector3, color: Color, count: int = 14) -> void:

	var spark = load("res://hit_spark.gd").new()
	spark.amount = count
	spark.color = color
	parent.add_child(spark)
	spark.global_position = pos
	if dir.length() > 0.01:
		spark.direction = dir.normalized()
	spark.emitting = true


func _ready():

	one_shot = true
	explosiveness = 1.0
	lifetime = LIFETIME
	spread = 55.0
	initial_velocity_min = 10.0
	initial_velocity_max = 22.0
	gravity = Vector3(0, -40, 0)
	damping_min = 20.0
	damping_max = 30.0
	scale_amount_min = 0.25
	scale_amount_max = 0.5

	var shrink = Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	scale_amount_curve = shrink

	var quad = QuadMesh.new()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = preload("res://fx.gd").soft_dot()
	quad.material = mat
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	finished.connect(queue_free)
