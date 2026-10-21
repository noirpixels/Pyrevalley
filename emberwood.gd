extends Node3D

# Emberwood level root. Children are laid out in this node's local space:
# local -Z runs "up" the isometric screen, from the Waking Glade in the south
# to the Ashbound Arena in the north. Where everything stands comes from
# this world's seed (world_gen.gd): the story's nodes in game.tscn are moved
# into place and the forest is planted before any of them is ready.
# Handles the level bounds, atmosphere and music.

const InkPost = preload("res://ink_post.gd")
const WorldDressing = preload("res://world_dressing.gd")
const PvpRing = preload("res://pvp_ring.gd")
const MiningSites = preload("res://mining_sites.gd")
const Forage = preload("res://forage.gd")
const Ruins = preload("res://ruins.gd")
const BloodMoon = preload("res://blood_moon.gd")
const Stations = preload("res://stations.gd")
const WorldGen = preload("res://world_gen.gd")
const TREE_SCENE = preload("res://tree.tscn")
const ROCK_SCENE = preload("res://rock.tscn")
# How close to Rowan's fire his theme takes over
const CAMP_RADIUS = 26.0

@export var light_path: NodePath = ^"../DirectionalLight3D"
@export var environment_path: NodePath = ^"../WorldEnvironment"

# Where a new Veyl stands above the ground
const SPAWN_HEIGHT = 5.9
# The ground plane's painted paths: pixels per unit
const MASK_SCALE = 1.0

var layout
var light: DirectionalLight3D
var environment: Environment
var embers: CPUParticles3D
var base_light_energy: float
var base_ambient_energy: float


# Before anything in the level is ready: lay out this world
func _enter_tree():

	if layout:
		return
	GameState.ensure_loaded()
	layout = WorldGen.new()
	layout.build(GameState.world_seed)
	WorldGen.current = layout
	place_markers()
	plant_forest()
	place_player()
	paint_ground()


func _ready():

	light = get_node_or_null(light_path)
	var world_env = get_node_or_null(environment_path)
	if world_env:
		environment = world_env.environment
		base_ambient_energy = environment.ambient_light_energy
	if light:
		base_light_energy = light.light_energy

	build_bounds()
	build_walls()
	build_embers()
	add_child(InkPost.new())
	# Mining sites first: they clear trees and rocks out of their way
	add_child(MiningSites.new())
	add_child(WorldDressing.new())
	add_child(Forage.new())
	add_child(Ruins.new())
	add_child(BloodMoon.new())
	add_child(Stations.new())
	add_child(PvpRing.new())
	# Spawners and placed pickups are ready now; start (or join) the session
	NetSync.enter_world.call_deferred(get_parent())
	update_signs()
	Pad.mode_changed.connect(update_signs)
	Sfx.play_ambience("forest")
	GameState.boss_engaged.connect(func(_boss): Sfx.play_music("boss"))
	# Deferred: when the boss dies it disengages just before it counts as defeated
	GameState.boss_disengaged.connect(_on_boss_disengaged, CONNECT_DEFERRED)


# The tutorial signs name the keys or pad buttons in use
func update_signs():

	var move_sign = get_node_or_null("Signs/MoveSign")
	var fight_sign = get_node_or_null("Signs/FightSign")
	if move_sign == null or fight_sign == null:
		return
	if Pad.using_pad:
		move_sign.text = "%s to move  ·  %s to aim" % [Pad.glyph("move_left"), Pad.glyph("aim_left")]
		fight_sign.text = "%s / %s to strike  ·  %s to launch\n%s to slam  ·  %s to dodge" % [
			Pad.glyph("strike_left"), Pad.glyph("strike_right"), Pad.glyph("launch"), Pad.glyph("slam"), Pad.glyph("dash")]
	else:
		move_sign.text = "WASD to move  ·  Mouse to aim"
		fight_sign.text = "Left/right click to strike  ·  Scroll up to launch\nScroll down to slam  ·  Shift to dodge"


# Outside the boss fight (which picks its own music) and the ending, the
# place sets the theme: Rowan's fire, the outer forest, or the Deep Forest
func update_music(local: Vector3):

	var ui = get_tree().get_first_node_in_group("game_ui")
	if GameState.boss_fight or (GameState.boss_defeated and ui and not ui.exploring):
		return
	var rowan = get_node_or_null("Rowan")
	if rowan and Vector2(local.x - rowan.position.x, local.z - rowan.position.z).length() < CAMP_RADIUS:
		Sfx.play_music("camp")
	elif layout.is_deep(local):
		Sfx.play_music("deep")
	else:
		Sfx.play_music("forest")


func _on_boss_disengaged():

	if GameState.boss_defeated:
		Sfx.stop_music()


func build_bounds():

	var r: Rect2 = WorldGen.BOUNDS
	var c = r.get_center()
	var walls = [
		[Vector3(r.end.x, 0, c.y), Vector3(1, 40, r.size.y)],
		[Vector3(r.position.x, 0, c.y), Vector3(1, 40, r.size.y)],
		[Vector3(c.x, 0, r.end.y), Vector3(r.size.x, 40, 1)],
		[Vector3(c.x, 0, r.position.y), Vector3(r.size.x, 40, 1)],
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


# The Deep Forest's edge and the arena's ring: unseen walls behind the
# pines, open only where the gates stand
func build_walls():

	var body = StaticBody3D.new()
	body.name = "ForestWalls"
	for wall in layout.walls:
		var a: Vector3 = wall[0]
		var b: Vector3 = wall[1]
		var shape = BoxShape3D.new()
		shape.size = Vector3(a.distance_to(b) + 1.0, 40.0, 2.0)
		var collision = CollisionShape3D.new()
		collision.shape = shape
		collision.position = (a + b) / 2.0
		collision.rotation.y = -atan2(b.z - a.z, b.x - a.x)
		body.add_child(collision)
	add_child(body)


# ============================================================
# LAYOUT (world_gen.gd)
# ============================================================

# The story's nodes (shrines, gates, Rowan, creature spawners...) go where
# this world put them
func place_markers():

	for node_path in layout.markers:
		var node = get_node_or_null(node_path)
		if node == null:
			continue
		var m = layout.markers[node_path]
		node.position = Vector3(m["pos"].x, node.position.y, m["pos"].z)
		node.rotation.y = m["yaw"]


func plant_forest():

	var trees = get_node("Trees")
	for i in layout.trees.size():
		var t = layout.trees[i]
		var tree = TREE_SCENE.instantiate()
		tree.name = "Tree%d" % i
		tree.position = t[0]
		tree.rotation.y = t[1]
		tree.scale = Vector3.ONE * t[2]
		trees.add_child(tree)
	var rocks = get_node("Rocks")
	for i in layout.rocks.size():
		var r = layout.rocks[i]
		var rock = ROCK_SCENE.instantiate()
		rock.name = "Rock%d" % i
		rock.position = r[0]
		rock.rotation.y = r[1]
		# Squashed in the mesh only: physics wants the body scaled evenly
		rock.scale = Vector3.ONE * r[2]
		rock.get_node("Mesh").scale = Vector3(1.0, 0.8, 1.0)
		rocks.add_child(rock)


# A new Veyl wakes in the glade (a saved one goes back where it was, in
# player_3d.gd)
func place_player():

	var player = get_parent().get_node_or_null("Player3D")
	if player:
		player.position = transform * layout.spawn + Vector3(0, SPAWN_HEIGHT, 0)


# The paths painted into a mask for game.gdshader, and the Deep Forest's
# edge and the world's bounds for it to darken past
func paint_ground():

	var ground = get_node_or_null("Ground")
	if ground == null:
		return
	var mat = ground.mesh.material as ShaderMaterial
	var size: Vector2 = ground.mesh.size
	var offset_z: float = ground.position.z
	var w = int(size.x * MASK_SCALE)
	var h = int(size.y * MASK_SCALE)
	var data = PackedByteArray()
	data.resize(w * h)
	for k in layout.paths.size():
		var points: PackedVector2Array = layout.paths[k]
		var width: float = layout.path_widths[k]
		for i in points.size() - 1:
			# Into mask pixels: x from the plane's left edge, z from its top
			var a = (points[i] + Vector2(size.x / 2.0, size.y / 2.0 - offset_z)) * MASK_SCALE
			var b = (points[i + 1] + Vector2(size.x / 2.0, size.y / 2.0 - offset_z)) * MASK_SCALE
			var reach = width * MASK_SCALE + 1.0
			for py in range(maxi(floori(minf(a.y, b.y) - reach), 0), mini(ceili(maxf(a.y, b.y) + reach), h - 1) + 1):
				for px in range(maxi(floori(minf(a.x, b.x) - reach), 0), mini(ceili(maxf(a.x, b.x) + reach), w - 1) + 1):
					var at = Vector2(px + 0.5, py + 0.5)
					var d = Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) / MASK_SCALE
					var v = int(255.0 * (1.0 - smoothstep(width * 0.6, width, d)))
					var idx = py * w + px
					if v > data[idx]:
						data[idx] = v
	var mask = Image.create_from_data(w, h, false, Image.FORMAT_L8, data)
	mat.set_shader_parameter("path_mask", ImageTexture.create_from_image(mask))
	mat.set_shader_parameter("deep_line", layout.deep_line_samples())
	mat.set_shader_parameter("deep_line_start", WorldGen.DEEP_START)
	mat.set_shader_parameter("deep_step", WorldGen.DEEP_STEP)
	mat.set_shader_parameter("deep_span", WorldGen.DEEP_SPAN)
	mat.set_shader_parameter("deep_strength", 1.0)
	var r: Rect2 = WorldGen.BOUNDS
	mat.set_shader_parameter("world_bounds", Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	mat.set_shader_parameter("ground_size", size)


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

	update_music(to_local(player.global_position))

	# Deeper into the forest = darker
	var t = layout.deepness(to_local(player.global_position))

	if light:
		light.light_energy = lerp(base_light_energy, base_light_energy * 0.35, t)
	if environment:
		environment.ambient_light_energy = lerp(base_ambient_energy, base_ambient_energy * 0.6, t)
