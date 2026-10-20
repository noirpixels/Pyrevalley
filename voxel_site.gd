extends StaticBody3D

# A mining site: a patch of ground built from blocks (blocks.gd) that Veyl
# digs into piece by piece, Minecraft-style, from a low hill on top down
# to bedrock. The layers follow its geology (profile):
#   quarry  topsoil, clay and gravel (tin pebbles) over sandstone and
#           limestone beds, with a coal seam and malachite (copper)
#   knoll   topsoil over granite veined with cassiterite (tin) and hematite (iron)
#   scar    ash over basalt with hematite, and Emberstone deep down
# Blocks are drawn as one mesh of their exposed faces, and each solid block
# has its own collision box. The host decides every strike (host_request);
# cracks and breaks show on every machine (fx_crack, fx_break). A blood
# moon (blood_moon.gd) grows every dug block back.
# Lives under Emberwood; position is the site's corner at ground level.

const Blocks = preload("res://blocks.gd")
const AshBurst = preload("res://ash_burst.gd")
const SHADER = preload("res://voxel.gdshader")

const S = Blocks.SIZE
# How far from a block a player's Veyl may be for the host to accept a strike
const MAX_STRIKE_REACH = 16.0
# Most a single strike can do (iron pickaxe, masterwork)
const MAX_PROGRESS = 3.0

var site_name: String = ""
var title: String = ""
var width: int = 6
var length: int = 6
# Layers below ground level, and the tallest the hill rises above it
var below: int = 5
var above: int = 3
var profile: String = "quarry"
var seed_value: int = 1

var blocks: PackedByteArray
var original: PackedByteArray
# cell -> how broken it is (0..1); the host keeps the exact progress
var damage: Dictionary = {}
var progress: Dictionary = {}
var shapes: Dictionary = {}
var box_shape: BoxShape3D
var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var dirty: bool = false

const FACES = [
	[Vector3i(1, 0, 0), [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)]],
	[Vector3i(-1, 0, 0), [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]],
	[Vector3i(0, 1, 0), [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)]],
	[Vector3i(0, -1, 0), [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]],
	[Vector3i(0, 0, 1), [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]],
	[Vector3i(0, 0, -1), [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]],
]


func _ready():

	add_to_group("voxel_sites")
	add_to_group("net_objects")
	box_shape = BoxShape3D.new()
	box_shape.size = Vector3(S, S, S)
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("atlas", Blocks.atlas())
	mesh_instance = MeshInstance3D.new()
	mesh_instance.material_override = material
	add_child(mesh_instance)
	generate()
	original = blocks.duplicate()
	rebuild_collision()
	rebuild_mesh()

	if title != "":
		var label = Label3D.new()
		label.text = title
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.03
		label.outline_size = 12
		label.modulate = Color(0.85, 0.78, 0.65)
		label.position = Vector3(width * S / 2.0, (above + 2) * S, length * S / 2.0)
		add_child(label)


# ============================================================
# GRID
# ============================================================

func layers() -> int:
	return below + above


func index(c: Vector3i) -> int:
	return c.x + width * (c.z + length * c.y)


func cell(i: int) -> Vector3i:
	return Vector3i(i % width, i / (width * length), (i / width) % length)


func inside(c: Vector3i) -> bool:
	return c.x >= 0 and c.z >= 0 and c.y >= 0 and c.x < width and c.z < length and c.y < layers()


# Outside the site, underground counts as solid (its faces are never seen)
func solid_at(c: Vector3i) -> bool:

	if not inside(c):
		return c.y < below and c.y >= 0
	return blocks[index(c)] != Blocks.AIR


func block_at(c: Vector3i) -> int:
	return blocks[index(c)] if inside(c) else Blocks.AIR


func centre_local(c: Vector3i) -> Vector3:
	return Vector3((c.x + 0.5) * S, (c.y - below + 0.5) * S, (c.z + 0.5) * S)


func centre(c: Vector3i) -> Vector3:
	return to_global(centre_local(c))


func cell_at(world_pos: Vector3) -> Vector3i:

	var p = to_local(world_pos) / S
	return Vector3i(floori(p.x), floori(p.y) + below, floori(p.z))


# Rough reach test, before looking for a block
func near(world_pos: Vector3, margin: float) -> bool:

	var p = to_local(world_pos)
	return p.x > -margin and p.z > -margin and p.x < width * S + margin and p.z < length * S + margin


# ============================================================
# GEOLOGY
# ============================================================

func generate():

	blocks = PackedByteArray()
	blocks.resize(width * length * layers())
	var hill = FastNoiseLite.new()
	hill.seed = seed_value
	hill.frequency = 0.22
	var ore = FastNoiseLite.new()
	ore.seed = seed_value + 7
	ore.frequency = 0.35
	var ore2 = FastNoiseLite.new()
	ore2.seed = seed_value + 13
	ore2.frequency = 0.4

	for z in length:
		for x in width:
			# Highest in the middle, falling away to ground level at the rim
			var rim = min(min(x, z), min(width - 1 - x, length - 1 - z))
			var rise = (hill.get_noise_2d(x, z) * 0.5 + 0.6) * above * clamp(rim / 2.0, 0.0, 1.0)
			var surface = below + clampi(roundi(rise), 0, above)
			for y in layers():
				var b = Blocks.AIR
				if y == 0:
					b = Blocks.BEDROCK
				elif y < surface:
					b = layer(x, y, z, surface - 1 - y, ore.get_noise_3d(x, y, z), ore2.get_noise_3d(x, y, z))
				blocks[index(Vector3i(x, y, z))] = b


# depth: blocks under the surface (0 = the top one); n, n2: ore noise
func layer(_x: int, y: int, _z: int, depth: int, n: float, n2: float) -> int:

	match profile:
		"knoll":
			if depth == 0:
				return Blocks.TOPSOIL
			if depth == 1:
				return Blocks.GRAVEL if n > 0.0 else Blocks.DIRT
			if n > 0.38:
				return Blocks.CASSITERITE
			if n2 > 0.4:
				return Blocks.HEMATITE
			return Blocks.GRANITE
		"scar":
			if depth == 0:
				return Blocks.ASH
			if depth == 1:
				return Blocks.GRAVEL
			if y <= 2 and n2 > 0.3:
				return Blocks.EMBERSTONE
			if n > 0.36:
				return Blocks.HEMATITE
			return Blocks.BASALT
		_:
			# Sedimentary beds, layered by height rather than by depth
			if depth == 0:
				return Blocks.TOPSOIL
			if depth == 1:
				return Blocks.CLAY if n > 0.1 else Blocks.DIRT
			if depth == 2:
				return Blocks.TIN_GRAVEL if n2 > 0.3 else Blocks.GRAVEL
			if y == 2 and n > -0.35:
				return Blocks.COAL
			if y % 2 == 1:
				return Blocks.MALACHITE if n2 > 0.32 else Blocks.LIMESTONE
			return Blocks.SANDSTONE


# ============================================================
# MESH AND COLLISION
# ============================================================

func rebuild_mesh():

	dirty = false
	var verts = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	var indices = PackedInt32Array()
	var tile_w = 1.0 / Blocks.COLUMNS

	for i in blocks.size():
		var b = blocks[i]
		if b == Blocks.AIR:
			continue
		var c = cell(i)
		var base = Vector3(c.x, c.y - below, c.z) * S
		var tint = Color(1, 1, 1, 1.0 - damage.get(i, 0.0))
		for face in FACES:
			if solid_at(c + face[0]):
				continue
			var t = Blocks.tile(b, face[0] == Vector3i(0, 1, 0))
			var u0 = t * tile_w
			var start = verts.size()
			var corners: Array = face[1]
			for k in 4:
				verts.append(base + corners[k] * S)
				normals.append(Vector3(face[0]))
				colors.append(tint)
			uvs.append(Vector2(u0, 1))
			uvs.append(Vector2(u0 + tile_w, 1))
			uvs.append(Vector2(u0 + tile_w, 0))
			uvs.append(Vector2(u0, 0))
			indices.append_array([start, start + 2, start + 1, start, start + 3, start + 2])

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh


func rebuild_collision():

	for i in shapes:
		shapes[i].queue_free()
	shapes = {}
	for i in blocks.size():
		if blocks[i] != Blocks.AIR:
			add_shape(i)


func add_shape(i: int):

	var shape = CollisionShape3D.new()
	shape.shape = box_shape
	shape.position = centre_local(cell(i))
	add_child(shape)
	shapes[i] = shape


func remove_shape(i: int):

	if shapes.has(i):
		shapes[i].queue_free()
		shapes.erase(i)


func _process(_delta):

	if dirty:
		rebuild_mesh()


# ============================================================
# TARGETING (harvest.gd)
# ============================================================

# Which block a swing reaches: kind "down" digs under Veyl's feet, "up"
# the block above head height, anything else the first solid block ahead
# at waist level, then head level, then the ground in front. -1 for none.
func pick(veyl: Node3D, kind: String, aim: Vector3, reach: float) -> int:

	var feet = veyl.global_position - Vector3(0, veyl.foot_height(), 0)
	var candidates = []
	match kind:
		"down":
			candidates = [feet + Vector3.DOWN * 1.0, feet + aim * 1.5 + Vector3.DOWN * 1.0, feet + aim * 3.0 + Vector3.DOWN * 1.0]
		"up":
			for d in [2.5, 4.5, 6.0]:
				candidates.append(feet + Vector3.UP * (S * 2.4) + aim * d)
		_:
			# Waist height, then head height, then the ground just ahead
			# (so a swing can cut a trench forward)
			for row in [0.5, 1.5, -0.5]:
				for d in [2.8, 4.0, 5.2, reach]:
					candidates.append(feet + Vector3.UP * (S * row) + aim * d)
	for p in candidates:
		var c = cell_at(p)
		if inside(c) and blocks[index(c)] != Blocks.AIR:
			return index(c)
	return -1


# ============================================================
# STRIKES (host decides; everyone sees)
# ============================================================

func host_request(args: Array, sender: int):

	if args.size() < 3 or args[0] != "strike":
		return
	var i: int = args[1]
	var amount: float = clampf(args[2], 0.0, MAX_PROGRESS)
	if i < 0 or i >= blocks.size() or not Blocks.breakable(blocks[i]):
		return
	var veyl = NetSync.veyl_of(sender)
	if veyl == null or veyl.global_position.distance_to(centre(cell(i))) > MAX_STRIKE_REACH:
		return
	var hits: float = Blocks.def(blocks[i])["hits"]
	progress[i] = progress.get(i, 0.0) + amount
	if progress[i] >= hits:
		progress.erase(i)
		var d = Blocks.def(blocks[i])
		NetSync.object_fx(self, "break", [i])
		if d["drop"] != "" and randf() < d["chance"]:
			NetSync.drop("loose", d["drop"], centre(cell(i)))
	else:
		NetSync.object_fx(self, "crack", [i, progress[i] / hits])


func fx_crack(i: int, amount: float):

	damage[i] = amount
	dirty = true


func fx_break(i: int):

	var b = blocks[i]
	blocks[i] = Blocks.AIR
	damage.erase(i)
	remove_shape(i)
	dirty = true
	var at = centre(cell(i))
	AshBurst.spawn(get_parent(), at - Vector3(0, S * 0.3, 0), 0.5)
	if NetSync.near_me(at):
		Sfx.play("enemy_land", -4.0, randf_range(0.7, 0.9) if Blocks.def(b)["hardness"] > 0 else 1.1)


# Blood moon: the earth closes up again, except where a Veyl stands (keep:
# cells left open)
func host_regrow():

	var keep = []
	for i in blocks.size():
		if blocks[i] == original[i]:
			continue
		for veyl in NetSync.all_players():
			if veyl.global_position.distance_to(centre(cell(i))) < S * 1.6:
				keep.append(i)
				break
	progress = {}
	NetSync.object_fx(self, "regrow", [keep])


func fx_regrow(keep: Array):

	blocks = original.duplicate()
	for i in keep:
		blocks[i] = Blocks.AIR
	damage = {}
	rebuild_collision()
	dirty = true


func net_snapshot():

	if blocks == original:
		return null
	return Marshalls.raw_to_base64(blocks)


func apply_snapshot(data):

	var saved = Marshalls.base64_to_raw(data)
	if saved.size() != blocks.size():
		return
	blocks = saved
	damage = {}
	rebuild_collision()
	dirty = true
