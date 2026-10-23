extends MeshInstance3D

# A ground warning (telegraph.gdshader): a circle or a lane that fills
# over the windup, bursts when the attack lands, then fades.
#   var t = Telegraph.circle(parent, centre, radius, windup)
#   var t = Telegraph.lane(parent, from, direction, length, width, windup)
# Call burst() when the attack lands (or cancel() if it's interrupted).
# Positions are world space; it sits just above the ground.

const SHADER = preload("res://telegraph.gdshader")

var mat: ShaderMaterial
var tween: Tween


static func circle(parent: Node, centre: Vector3, radius: float, windup: float) -> Node:

	var t = new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	t.mesh = plane
	parent.add_child(t)
	t.global_position = Vector3(centre.x, centre.y + 0.08, centre.z)
	t.start(0, windup)
	return t


static func lane(parent: Node, from: Vector3, direction: Vector3, length: float, width: float, windup: float) -> Node:

	var t = new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(width, length)
	# Shift so the near end sits at the origin
	plane.center_offset = Vector3(0, 0, -length / 2.0)
	t.mesh = plane
	parent.add_child(t)
	t.global_position = Vector3(from.x, from.y + 0.08, from.z)
	var flat = Vector3(direction.x, 0, direction.z)
	if flat.length() > 0.01:
		t.global_basis = Basis.looking_at(flat.normalized())
	t.start(1, windup)
	return t


func _init():

	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 5
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func start(shape: int, windup: float):

	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("progress", 0.0)
	tween = create_tween()
	tween.tween_method(func(v): mat.set_shader_parameter("progress", v), 0.0, 1.0, max(windup, 0.01))


# The attack lands: flash and fade
func burst():

	if tween:
		tween.kill()
	mat.set_shader_parameter("progress", 1.0)
	tween = create_tween()
	tween.tween_method(func(v): mat.set_shader_parameter("burst", v), 1.0, 0.0, 0.25)
	tween.parallel().tween_method(func(v): mat.set_shader_parameter("alpha", v), 1.0, 0.0, 0.3)
	tween.tween_callback(queue_free)


func cancel():

	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_method(func(v): mat.set_shader_parameter("alpha", v), 1.0, 0.0, 0.15)
	tween.tween_callback(queue_free)
