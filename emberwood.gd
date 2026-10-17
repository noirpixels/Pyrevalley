extends Node3D

# Emberwood level root. Children are laid out in this node's local space:
# local -Z runs "up" the isometric screen, from the Starting Area (z ~ +105)
# to the Ashbound Arena (z ~ -135).
# Handles the level bounds, atmosphere and music.

const InkPost = preload("res://ink_post.gd")
const WorldDressing = preload("res://world_dressing.gd")

@export var light_path: NodePath = ^"../DirectionalLight3D"
@export var environment_path: NodePath = ^"../WorldEnvironment"

# Playable bounds in local space
@export var half_width: float = 40.0
@export var z_min: float = -168.0
@export var z_max: float = 125.0

# Where the forest starts getting darker / is fully dark (local z)
@export var dark_start_z: float = -10.0
@export var dark_full_z: float = -100.0

var light: DirectionalLight3D
var environment: Environment
var embers: CPUParticles3D
var base_light_energy: float
var base_ambient_energy: float


func _ready():

	light = get_node_or_null(light_path)
	var world_env = get_node_or_null(environment_path)
	if world_env:
		environment = world_env.environment
		base_ambient_energy = environment.ambient_light_energy
	if light:
		base_light_energy = light.light_energy

	build_bounds()
	build_embers()
	add_child(InkPost.new())
	add_child(WorldDressing.new())
	Sfx.play_music("forest")
	Sfx.play_ambience("forest")
	GameState.boss_engaged.connect(func(_boss): Sfx.play_music("boss"))
	# Deferred: when the boss dies it disengages just before it counts as defeated
	GameState.boss_disengaged.connect(_on_boss_disengaged, CONNECT_DEFERRED)


func _on_boss_disengaged():

	if GameState.boss_defeated:
		Sfx.stop_music()
	else:
		Sfx.play_music("forest")


func build_bounds():

	var length = z_max - z_min
	var center_z = (z_max + z_min) / 2.0
	var walls = [
		[Vector3(half_width, 0, center_z), Vector3(1, 40, length)],
		[Vector3(-half_width, 0, center_z), Vector3(1, 40, length)],
		[Vector3(0, 0, z_max), Vector3(half_width * 2, 40, 1)],
		[Vector3(0, 0, z_min), Vector3(half_width * 2, 40, 1)],
	]

	for wall in walls:
		var body = StaticBody3D.new()
		var shape = BoxShape3D.new()
		shape.size = wall[1]
		var collision = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		body.position = wall[0]
		add_child(body)


# Drifting embers around the player
func build_embers():

	embers = CPUParticles3D.new()
	embers.amount = 60
	embers.lifetime = 5.0
	embers.local_coords = false
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(25, 1, 25)
	embers.direction = Vector3(0, 1, 0)
	embers.spread = 30.0
	embers.gravity = Vector3(0.3, 0.6, 0)
	embers.initial_velocity_min = 0.3
	embers.initial_velocity_max = 1.2
	embers.scale_amount_min = 0.6
	embers.scale_amount_max = 1.4

	var ramp = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.55, 0.15, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.5, 0.1, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.3, 0.05, 0.0))
	embers.color_ramp = ramp

	var quad = QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = preload("res://fx.gd").soft_dot()
	quad.material = mat
	embers.mesh = quad

	add_child(embers)


func _process(_delta):

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	embers.global_position = Vector3(player.global_position.x, 0.5, player.global_position.z)

	# Deeper into the forest = darker
	var local_z = to_local(player.global_position).z
	var t = clamp(inverse_lerp(dark_start_z, dark_full_z, local_z), 0.0, 1.0)

	if light:
		light.light_energy = lerp(base_light_energy, base_light_energy * 0.35, t)
	if environment:
		environment.ambient_light_energy = lerp(base_ambient_energy, base_ambient_energy * 0.6, t)
