extends Node3D

# Set dressing and atmosphere for Emberwood, scattered from a fixed seed so
# the forest looks the same every run. Nothing here collides or changes
# how the level plays. Lives under the Emberwood node, in its local space
# (-Z runs up the screen, from the Waking Glade at z ~ +110 to the Ashbound
# Arena at z ~ -138):
#   - ferns, glowing mushrooms, stumps and fallen logs on the forest floor
#   - bare, burnt trees through the Deep Forest and round the arena
#   - slanting shafts of low sunlight in the outer forest, ground mist deeper in
#   - the arena: chain posts staked round the Ashbound, braziers, and
#     cracks in the earth glowing with the fire under it
#   - drifting fireflies near Veyl in the outer forest, falling ash deeper in

const OCCLUDER_SHADER = preload("res://occluder.gdshader")
const EmberWall = preload("res://ember_wall.gd")
const Fx = preload("res://fx.gd")
const MiningSites = preload("res://mining_sites.gd")

const HALF_WIDTH = 40.0
const Z_START = 120.0
const DEEP_Z = -6.0
const ARENA_Z = -100.0
const ARENA_CENTRE = Vector3(0, 0, -138)
const ARENA_RADIUS = 30.0

var rng = RandomNumberGenerator.new()
# Local positions of gameplay things to keep clear of
var keep_clear: Array[Vector3] = []
var fireflies: CPUParticles3D
var ash: CPUParticles3D
var shafts: Array[MeshInstance3D] = []
var time: float = 0.0


func _ready():

	rng.seed = 4242
	collect_keep_clear()
	scatter_floor()
	scatter_dead_trees()
	add_light_shafts()
	add_mist()
	build_arena()
	build_drifters()


func collect_keep_clear():

	var level = get_parent()
	for group in ["Creatures", "Shrines", "Gates", "LoreStones", "Pickups"]:
		var node = level.get_node_or_null(group)
		if node:
			for child in node.get_children():
				if child is Node3D:
					keep_clear.append(child.position)
	var rowan = level.get_node_or_null("Rowan")
	if rowan:
		keep_clear.append(rowan.position)


func clear_of_gameplay(p: Vector3, margin: float) -> bool:

	if MiningSites.covers(p, margin):
		return false
	for k in keep_clear:
		if Vector2(p.x - k.x, p.z - k.z).length() < margin:
			return false
	return true


func random_point(z_min: float, z_max: float, edge_bias: float = 0.6) -> Vector3:

	# Pushed toward the sides so the middle of the path stays open
	var x = rng.randf_range(-1.0, 1.0)
	x = sign(x) * pow(abs(x), 1.0 - edge_bias * 0.6)
	return Vector3(x * (HALF_WIDTH - 2.0), 0, rng.randf_range(z_min, z_max))


# ============================================================
# FOREST FLOOR
# ============================================================

func scatter_floor():

	var fern = fern_mesh()
	var mushroom = mushroom_mesh()
	var stump = stump_mesh()
	var log_mesh = log_mesh()

	var ferns = []
	var shrooms = []
	var stumps = []
	var logs = []
	for i in 700:
		var p = random_point(-170.0, Z_START, 0.5)
		if abs(p.x) < 6.0 and rng.randf() < 0.8:
			continue
		if in_arena(p) or not clear_of_gameplay(p, 3.5):
			continue
		ferns.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.6)), p))
	for i in 140:
		var p = random_point(-100.0, Z_START, 0.7)
		if in_arena(p) or not clear_of_gameplay(p, 3.0):
			continue
		# Deeper in, more of them glow
		shrooms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), p))
	for i in 40:
		var p = random_point(-100.0, Z_START, 0.9)
		if not clear_of_gameplay(p, 5.0):
			continue
		stumps.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), p))
	for i in 24:
		var p = random_point(-100.0, Z_START, 1.0)
		if abs(p.x) < 12.0 or not clear_of_gameplay(p, 7.0):
			continue
		var b = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, PI / 2.0)
		logs.append(Transform3D(b.scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), p + Vector3(0, 0.55, 0)))

	add_multimesh(fern, ferns, vertex_material())
	add_multimesh(stump, stumps, vertex_material())
	add_multimesh(log_mesh, logs, vertex_material())

	# Mushroom caps glow faintly, like the Glowmoss
	var cap_mat = StandardMaterial3D.new()
	cap_mat.vertex_color_use_as_albedo = true
	cap_mat.emission_enabled = true
	cap_mat.emission = Color(0.55, 0.85, 0.7)
	cap_mat.emission_energy_multiplier = 0.9
	add_multimesh(mushroom, shrooms, cap_mat)


func in_arena(p: Vector3) -> bool:
	return Vector2(p.x - ARENA_CENTRE.x, p.z - ARENA_CENTRE.z).length() < ARENA_RADIUS


func vertex_material() -> StandardMaterial3D:

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat


func add_multimesh(mesh: Mesh, transforms: Array, mat: Material):

	if transforms.is_empty():
		return
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst = MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


# A fern: drooping fronds fanned round a centre
func fern_mesh() -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark = Color(0.05, 0.1, 0.07)
	var light = Color(0.2, 0.32, 0.18)
	var fronds = 7
	for i in fronds:
		var a = TAU * i / fronds + randf_range(-0.2, 0.2)
		var dir = Vector3(cos(a), 0, sin(a))
		var side = dir.cross(Vector3.UP) * 0.22
		var length = randf_range(1.1, 1.6)
		var mid = dir * length * 0.55 + Vector3(0, 0.75, 0)
		var tip = dir * length + Vector3(0, 0.25, 0)
		tri(st, Vector3.ZERO, mid + side, mid - side, dark, light, light)
		tri(st, mid + side, tip, mid - side, light, light.lightened(0.1), light)
	st.generate_normals()
	return st.commit()


# A cluster of three small mushrooms
func mushroom_mesh() -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem = Color(0.75, 0.72, 0.62)
	var cap = Color(0.75, 0.95, 0.85)
	for m in [[Vector3(0, 0, 0), 0.5], [Vector3(0.35, 0, 0.2), 0.35], [Vector3(-0.25, 0, 0.3), 0.28]]:
		var base: Vector3 = m[0]
		var h: float = m[1]
		var sides = 5
		for s in sides:
			var a0 = TAU * s / sides
			var a1 = TAU * (s + 1) / sides
			var r = h * 0.18
			var b0 = base + Vector3(cos(a0) * r, 0, sin(a0) * r)
			var b1 = base + Vector3(cos(a1) * r, 0, sin(a1) * r)
			tri(st, b0, b0 + Vector3(0, h, 0), b1, stem, stem, stem)
			tri(st, b1, b0 + Vector3(0, h, 0), b1 + Vector3(0, h, 0), stem, stem, stem)
			# Cap: a shallow cone
			var cr = h * 0.6
			var c0 = base + Vector3(cos(a0) * cr, h * 0.9, sin(a0) * cr)
			var c1 = base + Vector3(cos(a1) * cr, h * 0.9, sin(a1) * cr)
			tri(st, c0, base + Vector3(0, h * 1.3, 0), c1, cap, cap, cap)
	st.generate_normals()
	return st.commit()


func stump_mesh() -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark = Color(0.18, 0.12, 0.09)
	var cut = Color(0.45, 0.33, 0.22)
	var sides = 7
	for s in sides:
		var a0 = TAU * s / sides
		var a1 = TAU * (s + 1) / sides
		var r0 = 0.95
		var r1 = 0.75
		var h = randf_range(0.7, 1.1) if s == 0 else 0.9
		var b0 = Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var b1 = Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var t0 = Vector3(cos(a0) * r1, 0.9, sin(a0) * r1)
		var t1 = Vector3(cos(a1) * r1, 0.9, sin(a1) * r1)
		tri(st, b0, t0, b1, bark, bark, bark)
		tri(st, b1, t0, t1, bark, bark, bark)
		tri(st, t0, Vector3(0, 0.95, 0), t1, cut, cut, cut)
	st.generate_normals()
	return st.commit()


func log_mesh() -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark = Color(0.16, 0.11, 0.08)
	var moss = Color(0.16, 0.26, 0.14)
	var sides = 7
	var half = 3.0
	for s in sides:
		var a0 = TAU * s / sides
		var a1 = TAU * (s + 1) / sides
		var r = 0.55
		var p0 = Vector3(cos(a0) * r, -half, sin(a0) * r)
		var p1 = Vector3(cos(a1) * r, -half, sin(a1) * r)
		# The side facing up after the log is laid down gets moss
		var c = moss if cos((a0 + a1) / 2.0) > 0.3 else bark
		tri(st, p0, p0 + Vector3(0, half * 2.0, 0), p1, c, c, c)
		tri(st, p1, p0 + Vector3(0, half * 2.0, 0), p1 + Vector3(0, half * 2.0, 0), c, c, c)
	st.generate_normals()
	return st.commit()


func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color):

	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


# ============================================================
# DEAD TREES
# ============================================================

func scatter_dead_trees():

	var meshes = []
	for i in 4:
		meshes.append(dead_tree_mesh())
	var mat = ShaderMaterial.new()
	mat.shader = OCCLUDER_SHADER
	var placed = 0
	for i in 160:
		if placed >= 45:
			break
		var p = random_point(-172.0, DEEP_Z + 10.0, 1.2)
		if abs(p.x) < 9.0 or not clear_of_gameplay(p, 6.0):
			continue
		if in_arena(p) and Vector2(p.x, p.z - ARENA_CENTRE.z).length() < ARENA_RADIUS - 4.0:
			continue
		var tree = MeshInstance3D.new()
		tree.mesh = meshes[placed % meshes.size()]
		tree.material_override = mat
		tree.position = p
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
		add_child(tree)
		placed += 1


# A bare, burnt trunk with a few crooked limbs
func dead_tree_mesh() -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var char_col = Color(0.07, 0.05, 0.05)
	var ember = Color(0.35, 0.1, 0.04)
	limb(st, Vector3.ZERO, Vector3(randf_range(-0.6, 0.6), 13.0, randf_range(-0.6, 0.6)), 0.9, 0.2, char_col, ember)
	for i in randi_range(3, 5):
		var y = randf_range(5.0, 11.0)
		var a = randf() * TAU
		var out = Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 4.5)
		var start = Vector3(0, y, 0)
		limb(st, start, start + out + Vector3(0, randf_range(1.5, 3.5), 0), 0.3, 0.05, char_col, char_col)
	st.generate_normals()
	return st.commit()


func limb(st: SurfaceTool, from: Vector3, to: Vector3, r0: float, r1: float, c0: Color, c1: Color):

	var axis = (to - from).normalized()
	var side = axis.cross(Vector3.UP if abs(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up = axis.cross(side)
	var sides = 5
	for s in sides:
		var a0 = TAU * s / sides
		var a1 = TAU * (s + 1) / sides
		var d0 = side * cos(a0) + up * sin(a0)
		var d1 = side * cos(a1) + up * sin(a1)
		tri(st, from + d0 * r0, to + d0 * r1, from + d1 * r0, c1, c0, c1)
		tri(st, from + d1 * r0, to + d0 * r1, to + d1 * r1, c1, c0, c0)


# ============================================================
# LIGHT AND MIST
# ============================================================

# Slanting shafts of low sun in the clearings of the outer forest
func add_light_shafts():

	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float strength = 0.16;
uniform float phase = 0.0;
void fragment() {
	// Bright at the top, gone by the ground, soft at the sides
	float across = 1.0 - pow(abs(UV.x * 2.0 - 1.0), 2.0);
	float down = smoothstep(1.0, 0.25, UV.y) * smoothstep(0.0, 0.15, UV.y);
	float sway = 0.75 + 0.25 * sin(TIME * 0.5 + phase + UV.x * 3.0);
	ALBEDO = vec3(1.0, 0.86, 0.62) * across * down * strength * sway;
}
"""
	for i in 16:
		var p = random_point(DEEP_Z + 4.0, Z_START, 0.0)
		if not clear_of_gameplay(p, 2.0):
			continue
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("phase", rng.randf() * TAU)
		mat.render_priority = 4
		var shaft = MeshInstance3D.new()
		var quad = QuadMesh.new()
		quad.size = Vector2(rng.randf_range(2.5, 5.0), 26.0)
		shaft.mesh = quad
		shaft.material_override = mat
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft.position = p + Vector3(0, 10.0, 0)
		# Leaning with the low sun, turned to face the isometric camera
		shaft.rotation = Vector3(0, deg_to_rad(-45.0) + rng.randf_range(-0.3, 0.3), deg_to_rad(28.0))
		add_child(shaft)
		shafts.append(shaft)


# Low drifting mist, thicker and colder the deeper the forest gets
func add_mist():

	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 tint = vec3(0.6, 0.62, 0.72);
uniform float density = 0.35;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float n = noise(w * 0.08 + vec2(TIME * 0.05, TIME * 0.02)) * 0.65 + noise(w * 0.21 - vec2(TIME * 0.04, 0.0)) * 0.35;
	float edge = 1.0 - smoothstep(0.3, 0.5, length(UV - 0.5));
	// Banded like an ink wash rather than soft fog
	float a = smoothstep(0.45, 0.62, n) * 0.6 + smoothstep(0.62, 0.7, n) * 0.4;
	ALBEDO = tint;
	ALPHA = a * edge * density;
}
"""
	for i in 22:
		var z = lerp(DEEP_Z + 10.0, -165.0, float(i) / 21.0) + rng.randf_range(-6, 6)
		var deep = clamp(inverse_lerp(DEEP_Z, -120.0, z), 0.0, 1.0)
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("density", lerp(0.22, 0.42, deep))
		mat.set_shader_parameter("tint", Color(0.62, 0.62, 0.7).lerp(Color(0.5, 0.42, 0.45), deep))
		mat.render_priority = 3
		var mist = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(rng.randf_range(26, 40), rng.randf_range(18, 26))
		mist.mesh = plane
		mist.material_override = mat
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mist.position = Vector3(rng.randf_range(-24, 24), 0.6 + rng.randf() * 0.6, z)
		add_child(mist)


# ============================================================
# THE ARENA
# ============================================================

func build_arena():

	# The earth round the Ashbound has split, and the cracks glow
	var crack_shader = Shader.new()
	crack_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float boss_fight = 0.0;
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
void fragment() {
	vec2 p = (UV - 0.5) * 13.0;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	float crack = 1.0 - smoothstep(0.0, 0.05 + 0.04 * hash2(i).x, d2 - d1);
	// Not every seam has split open
	vec2 q = UV * 5.0;
	vec2 qi = floor(q); vec2 qf = fract(q); qf = qf * qf * (3.0 - 2.0 * qf);
	float n = mix(mix(hash2(qi).x, hash2(qi + vec2(1.0, 0.0)).x, qf.x), mix(hash2(qi + vec2(0.0, 1.0)).x, hash2(qi + vec2(1.0, 1.0)).x, qf.x), qf.y);
	crack *= smoothstep(0.3, 0.55, n);
	float r = length(UV - 0.5) * 2.0;
	float fade = 1.0 - smoothstep(0.55, 1.0, r);
	float pulse = 0.75 + 0.25 * sin(TIME * (1.5 + boss_fight * 2.5) - r * 6.0);
	vec3 hot = mix(vec3(0.9, 0.25, 0.04), vec3(1.0, 0.7, 0.3), crack * pulse);
	ALBEDO = hot * (1.0 + boss_fight * 0.5);
	ALPHA = crack * fade * pulse * (0.75 + boss_fight * 0.25);
}
"""
	var crack_mat = ShaderMaterial.new()
	crack_mat.shader = crack_shader
	crack_mat.render_priority = 4
	var cracks = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(ARENA_RADIUS * 2.0, ARENA_RADIUS * 2.0)
	cracks.mesh = plane
	cracks.material_override = crack_mat
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cracks.position = ARENA_CENTRE + Vector3(0, 0.07, 0)
	cracks.set_meta("mat", crack_mat)
	add_child(cracks)
	GameState.boss_engaged.connect(func(_b): create_tween().tween_method(func(v): crack_mat.set_shader_parameter("boss_fight", v), 0.0, 1.0, 1.5))
	GameState.boss_disengaged.connect(func(): crack_mat.set_shader_parameter("boss_fight", 0.0))

	var stone = StandardMaterial3D.new()
	stone.albedo_color = Color(0.2, 0.19, 0.21)
	stone.roughness = 1.0
	var iron = StandardMaterial3D.new()
	iron.albedo_color = Color(0.1, 0.09, 0.1)
	iron.metallic = 0.6
	iron.roughness = 0.6

	# Chain posts staked round it, chains running in toward the centre
	for i in 6:
		var a = TAU * i / 6.0 + 0.3
		var at = ARENA_CENTRE + Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 6.0)
		var post = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1.4, 5.0, 1.4)
		post.mesh = box
		post.material_override = stone
		post.position = at + Vector3(0, 2.5, 0)
		post.rotation = Vector3(rng.randf_range(-0.08, 0.08), a, rng.randf_range(-0.08, 0.08))
		add_child(post)
		var inward = (ARENA_CENTRE - at).normalized()
		for link in 9:
			var ring = MeshInstance3D.new()
			var torus = TorusMesh.new()
			torus.inner_radius = 0.22
			torus.outer_radius = 0.42
			torus.rings = 8
			torus.ring_segments = 5
			ring.mesh = torus
			ring.material_override = iron
			var t = float(link) / 8.0
			# Sagging from the top of the post down to the ground
			ring.position = at + inward * (0.8 + link * 0.75) + Vector3(0, lerp(4.2, 0.25, sqrt(t)), 0)
			ring.rotation = Vector3(PI / 2.0 if link % 2 == 0 else 0.0, a, 0)
			add_child(ring)

	# Braziers ringing the arena, so the fight is lit by fire
	for i in 8:
		var a = TAU * i / 8.0
		var at = ARENA_CENTRE + Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS + 1.0)
		if at.z > ARENA_Z - 6.0:
			continue
		var bowl = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 1.1
		cyl.bottom_radius = 0.5
		cyl.height = 2.6
		cyl.radial_segments = 6
		bowl.mesh = cyl
		bowl.material_override = stone
		bowl.position = at + Vector3(0, 1.3, 0)
		add_child(bowl)
		var fire = EmberWall.new(1.8, 2.6, true)
		fire.position = at + Vector3(0, 2.5, 0)
		add_child(fire)
		fire.light.omni_range = 16.0


# ============================================================
# DRIFTERS (around Veyl)
# ============================================================

func build_drifters():

	fireflies = drifter(40, Color(0.85, 1.0, 0.55), Vector3(0, 0.15, 0), 0.6, 0.35)
	fireflies.emission_box_extents = Vector3(22, 3, 22)
	ash = drifter(90, Color(0.75, 0.72, 0.72, 0.8), Vector3(0.4, -1.2, 0.2), 0.3, 0.3)
	ash.emission_box_extents = Vector3(26, 1, 26)


func drifter(count: int, color: Color, grav: Vector3, vel: float, size: float) -> CPUParticles3D:

	var p = CPUParticles3D.new()
	p.amount = count
	p.lifetime = 6.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.gravity = grav
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var ramp = Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 0.0))
	ramp.add_point(0.2, color)
	ramp.add_point(0.8, color)
	ramp.set_color(ramp.get_point_count() - 1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var quad = QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_dot()
	mat.render_priority = 5
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _process(_delta):

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var local = to_local(player.global_position)
	var at = player.global_position
	fireflies.global_position = Vector3(at.x, 1.5, at.z)
	ash.global_position = Vector3(at.x, 12.0, at.z)
	# Fireflies in the outer forest, falling ash deeper in
	var deep = clamp(inverse_lerp(DEEP_Z + 10.0, ARENA_Z, local.z), 0.0, 1.0)
	fireflies.emitting = deep < 0.5
	ash.emitting = deep > 0.15
