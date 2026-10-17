extends Node3D

# A glob of burning ash spat by an Ashcrawler. Flies straight, burns Veyl
# on contact (a dash passes through it), and gutters out on the ground.
#   EmberBolt.spawn(parent, from, direction, damage)

const SPEED = 15.0
const LIFETIME = 1.4
const HIT_RADIUS = 1.4

var direction: Vector3 = Vector3.FORWARD
var damage: int = 10
var age: float = 0.0


static func spawn(parent: Node, from: Vector3, dir: Vector3, amount: int) -> void:

	var bolt = load("res://ember_bolt.gd").new()
	bolt.direction = Vector3(dir.x, 0, dir.z).normalized()
	bolt.damage = amount
	parent.add_child(bolt)
	bolt.global_position = from


func _ready():

	var core = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	sphere.radial_segments = 8
	sphere.rings = 4
	core.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.35)
	mat.render_priority = 5
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	var trail = CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.5
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.6
	var ramp = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.55, 0.15, 1.0))
	ramp.set_color(1, Color(0.2, 0.1, 0.1, 0.0))
	trail.color_ramp = ramp
	var quad = QuadMesh.new()
	var trail_mat = StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.render_priority = 5
	quad.material = trail_mat
	trail.mesh = quad
	add_child(trail)

	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 2.0
	light.omni_range = 5.0
	add_child(light)


func _physics_process(delta):

	age += delta
	global_position += direction * SPEED * delta

	var player = get_tree().get_first_node_in_group("player")
	if player and not player.dead:
		var offset = player.global_position - global_position
		offset.y = 0
		if offset.length() < HIT_RADIUS:
			player.take_damage(damage, global_position - direction)
			fizzle()
			return

	if age >= LIFETIME:
		fizzle()


func fizzle():

	set_physics_process(false)
	var ash = load("res://ash_burst.gd")
	ash.spawn(get_parent(), global_position, 0.25)
	queue_free()
