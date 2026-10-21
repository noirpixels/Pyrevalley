extends StaticBody3D

# A mining site: a low hill of earth and rock that Veyl digs into in smooth,
# rounded strokes, down as far as bedrock. The ground here is a grid of
# density samples H apart (positive inside the earth), drawn as one smooth
# surface (surface nets) in CHUNK-sized pieces, so a strike only redraws
# what it touched. The layers follow the site's geology (profile, strata.gd):
#   quarry  topsoil, clay and gravel (tin pebbles) over sandstone and
#           limestone beds, with a coal seam and malachite (copper)
#   knoll   topsoil over granite veined with cassiterite (tin) and hematite (iron)
#   scar    ash over basalt with hematite, and Emberstone deep down
# A strike clears a scoop as wide as the one swinging (and, swung sideways,
# about as tall), as deep as the tool and rock allow: soft earth comes away
# in deep bites, hard rock in thin scrapes, and a hole dug underfoot is
# always wide enough to drop into. The host decides every strike
# (host_request) and everyone carves the same scoop (fx_dig); what a strike
# breaks loose drops as ore and stone. A blood moon (blood_moon.gd) fills
# the hollows back in.
# Lives under MiningSites; position is the site's corner at ground level.

const Strata = preload("res://strata.gd")
const AshBurst = preload("res://ash_burst.gd")
const SHADER = preload("res://dig_site.gdshader")

# Units between density samples, and cells per mesh chunk along each axis
const H = 1.0
const CHUNK = 8
# Density is kept within this far of the surface
const LIMIT = 3.0
# Sample rows at the bottom that never break
const BEDROCK_ROWS = 2
# How far from the strike a player's Veyl may be for the host to accept it
const MAX_STRIKE_REACH = 16.0
# Most a single strike can do (iron pickaxe, masterwork)
const MAX_AMOUNT = 3.0
# Earth a strike of power 1 hollows out of a 1-hit material (cubic units);
# harder rock gives up less
const DIG_VOLUME = 140.0
# A scoop reaches this far past the swinger's body on each side, and a
# sideways one this far above and below the strike
const SCOOP_MARGIN = 1.0
# Digging straight down reaches further, so a hole dug on a slope is still
# wide enough at its uphill lip to drop into
const DOWN_MARGIN = 1.8
const SCOOP_HALF_HEIGHT = 3.6
const MIN_DEPTH = 0.35
const MAX_DEPTH = 3.2
# Floats per carve in carves: centre, depth axis, depth, width, height
const CARVE_FIELDS = 9
# Broken earth that gives up one piece of its drop (cubic units)
const YIELD_VOLUME = 40.0
# A blood moon leaves hollows open this close to a Veyl
const KEEP_RADIUS = 9.0
# The hill rises from a flat rim (units) over this share of the site's
# width: a dome gentle enough to walk up (player_3d.gd SLOPE_LIMIT)
const RIM = 1.0
const RAMP = 0.5
# The forest floor's look, shared with the grassy top (terrain.gdshaderinc)
const TERRAIN_PARAMS = [
	"terrain_textures", "texture_scale", "patch_scale", "blend_hardness", "ground_size", "mesh_offset_z",
	"path_mask", "deep_line", "deep_line_start", "deep_step", "deep_span", "deep_strength", "world_bounds",
]

var title: String = ""
# Footprint (x, z) in units, depth below ground and the tallest the hill rises
var size: Vector2 = Vector2(24, 24)
var below: int = 20
var above: int = 12
var profile: String = "quarry"
var seed_value: int = 1

# Samples along each axis; index = x + nx * (y + ny * z)
var nx: int
var ny: int
var nz: int
var density: PackedFloat32Array
var original: PackedFloat32Array
var material: PackedByteArray
# Every scoop carved so far (CARVE_FIELDS each, site space), for saves and
# late joiners
var carves: PackedFloat32Array
# Chunk -> [MeshInstance3D, CollisionShape3D]
var chunk_nodes: Dictionary = {}
var dirty: Dictionary = {}
var shader_material: ShaderMaterial
# Host: broken earth not yet given up as drops, per material
var broken: Dictionary = {}
# What the last carve broke, per material
var last_broken: Dictionary = {}

# Per material: colour, fleck colour (alpha: how much), glow, and whether
# its top wears the forest floor (topsoil, and the Scar's ash)
static var _palette: Array = []


func _ready():

	add_to_group("dig_sites")
	add_to_group("net_objects")
	if _palette.is_empty():
		build_palette()
	shader_material = ShaderMaterial.new()
	shader_material.shader = SHADER
	copy_terrain()
	shader_material.set_shader_parameter("site_offset", get_parent().position + position)
	generate()
	original = density.duplicate()
	mark_all()
	rebuild_dirty()

	if title != "":
		var label = Label3D.new()
		label.text = title
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.03
		label.outline_size = 12
		label.modulate = Color(0.85, 0.78, 0.65)
		label.position = Vector3(size.x / 2.0, above + 8.0, size.y / 2.0)
		add_child(label)


func copy_terrain():

	var ground = get_parent().get_parent().get_node_or_null("Ground")
	if ground == null:
		return
	var ground_material = ground.mesh.material as ShaderMaterial
	for param in TERRAIN_PARAMS:
		var value = ground_material.get_shader_parameter(param)
		if value != null:
			shader_material.set_shader_parameter(param, value)


static func build_palette():

	_palette = []
	for m in Strata.BEDROCK + 1:
		var d = Strata.def(m)
		if d.is_empty():
			_palette.append([Color.BLACK, Color(0, 0, 0, 0), 0.0, 0.0])
			continue
		var fleck: Color = d["fleck"]
		fleck.a = d["flecks"]
		_palette.append([d["base"], fleck, 1.0 if d.get("glow", false) else 0.0, 1.0 if m == Strata.TOPSOIL or m == Strata.ASH else 0.0])


# ============================================================
# GEOLOGY
# ============================================================

func generate():

	nx = int(size.x / H) + 1
	nz = int(size.y / H) + 1
	ny = int((below + above) / H) + 1
	density = PackedFloat32Array()
	density.resize(nx * ny * nz)
	material = PackedByteArray()
	material.resize(nx * ny * nz)
	var hill = FastNoiseLite.new()
	hill.seed = seed_value
	hill.frequency = 0.055
	var ore = FastNoiseLite.new()
	ore.seed = seed_value + 7
	ore.frequency = 0.0875
	var ore2 = FastNoiseLite.new()
	ore2.seed = seed_value + 13
	ore2.frequency = 0.1

	for z in nz:
		for x in nx:
			# Flat at the rim, so it meets the forest floor; highest in the middle
			var rim = mini(mini(x, z), mini(nx - 1 - x, nz - 1 - z)) * H
			var t = clampf((rim - RIM) / (minf(size.x, size.y) * RAMP), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var height = (hill.get_noise_2d(x * H, z * H) * 0.25 + 0.75) * above * t
			for y in ny:
				var wy = y * H - below
				var i = x + nx * (y + ny * z)
				if y < BEDROCK_ROWS:
					density[i] = LIMIT
					material[i] = Strata.BEDROCK
					continue
				density[i] = clampf(height - wy, -LIMIT, LIMIT)
				var depth = height - wy
				var n = ore.get_noise_3d(x * H, wy, z * H) if depth > 4.0 else 0.0
				var n2 = ore2.get_noise_3d(x * H, wy, z * H) if depth > 4.0 else 0.0
				material[i] = layer(depth, wy + below, n, n2)


# depth: units under the surface; height: units above the site's floor;
# n, n2: ore noise
func layer(depth: float, height: float, n: float, n2: float) -> int:

	# Rock beds four units thick, counted up from the floor
	var bed = int(height / 4.0)
	match profile:
		"knoll":
			if depth < 2.0:
				return Strata.TOPSOIL
			if depth < 5.0:
				return Strata.GRAVEL if n > 0.0 else Strata.DIRT
			if n > 0.38:
				return Strata.CASSITERITE
			if n2 > 0.4:
				return Strata.HEMATITE
			return Strata.GRANITE
		"scar":
			if depth < 2.0:
				return Strata.ASH
			if depth < 5.0:
				return Strata.GRAVEL
			if bed <= 2 and n2 > 0.3:
				return Strata.EMBERSTONE
			if n > 0.36:
				return Strata.HEMATITE
			return Strata.BASALT
		_:
			if depth < 2.0:
				return Strata.TOPSOIL
			if depth < 5.0:
				return Strata.CLAY if n > 0.1 else Strata.DIRT
			if depth < 8.0:
				return Strata.TIN_GRAVEL if n2 > 0.3 else Strata.GRAVEL
			if bed == 2 and n > -0.35:
				return Strata.COAL
			if bed % 2 == 1:
				return Strata.MALACHITE if n2 > 0.32 else Strata.LIMESTONE
			return Strata.SANDSTONE


func sample_index(x: int, y: int, z: int) -> int:
	return x + nx * (y + ny * z)


# The material at a point in site space: the most solid sample around it
func material_at(p: Vector3) -> int:

	var base = Vector3i(floori(p.x / H), floori((p.y + below) / H), floori(p.z / H))
	var best = Strata.AIR
	var best_d = -INF
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var c = base + Vector3i(dx, dy, dz)
				if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= nx or c.y >= ny or c.z >= nz:
					continue
				var i = sample_index(c.x, c.y, c.z)
				if density[i] > best_d:
					best_d = density[i]
					best = material[i]
	return best if best_d > -1.0 else Strata.AIR


# Rough reach test, before casting for the surface
func near(world_pos: Vector3, margin: float) -> bool:

	var p = to_local(world_pos)
	return p.x > -margin and p.z > -margin and p.x < size.x + margin and p.z < size.y + margin


# ============================================================
# CARVING
# ============================================================

# Hollow out a scoop (site space): an ellipsoid depth deep along axis (out
# of the earth, toward the swinger), width across and height up. Returns
# the earth it broke, per material.
func carve(centre: Vector3, axis: Vector3, depth: float, width: float, height: float) -> Dictionary:

	var removed = {}
	var n = axis.normalized()
	var side: Vector3
	var up: Vector3
	if absf(n.y) > 0.7:
		# Straight down or up: round across
		side = Vector3.RIGHT
		height = width
	else:
		side = n.cross(Vector3.UP).normalized()
	up = side.cross(n).normalized()
	side = n.cross(up).normalized()
	var reach = maxf(depth, maxf(width, height))
	var unit = minf(depth, minf(width, height))
	var lo = Vector3i(maxi(floori((centre.x - reach) / H), 1), maxi(floori((centre.y + below - reach) / H), BEDROCK_ROWS), maxi(floori((centre.z - reach) / H), 1))
	var hi = Vector3i(mini(ceili((centre.x + reach) / H), nx - 2), mini(ceili((centre.y + below + reach) / H), ny - 1), mini(ceili((centre.z + reach) / H), nz - 2))
	if lo.x > hi.x or lo.y > hi.y or lo.z > hi.z:
		return removed
	var cell_volume = H * H * H
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var offset = Vector3(x * H, y * H - below, z * H) - centre
				var e = Vector3(offset.dot(n) / depth, offset.dot(side) / width, offset.dot(up) / height).length()
				var v = (e - 1.0) * unit
				var i = sample_index(x, y, z)
				var old = density[i]
				if v >= old:
					continue
				if old > 0.0 and v <= 0.0:
					removed[material[i]] = removed.get(material[i], 0.0) + cell_volume
				density[i] = maxf(v, -LIMIT)
	# A sample shapes the cells either side of it
	for cz in range(maxi(lo.z - 1, 0) / CHUNK, mini(hi.z, nz - 2) / CHUNK + 1):
		for cy in range(maxi(lo.y - 1, 0) / CHUNK, mini(hi.y, ny - 2) / CHUNK + 1):
			for cx in range(maxi(lo.x - 1, 0) / CHUNK, mini(hi.x, nx - 2) / CHUNK + 1):
				dirty[Vector3i(cx, cy, cz)] = true
	return removed


func carve_entry(list: PackedFloat32Array, k: int) -> Dictionary:
	return carve(Vector3(list[k], list[k + 1], list[k + 2]), Vector3(list[k + 3], list[k + 4], list[k + 5]), list[k + 6], list[k + 7], list[k + 8])


# Back to the untouched hill, then the given hollows
func restore(list: PackedFloat32Array):

	density = original.duplicate()
	carves = PackedFloat32Array()
	for k in range(0, list.size() - CARVE_FIELDS + 1, CARVE_FIELDS):
		carve_entry(list, k)
		carves.append_array(list.slice(k, k + CARVE_FIELDS))
	mark_all()


func mark_all():

	for cz in ceili((nz - 1) / float(CHUNK)):
		for cy in ceili((ny - 1) / float(CHUNK)):
			for cx in ceili((nx - 1) / float(CHUNK)):
				dirty[Vector3i(cx, cy, cz)] = true


# ============================================================
# MESH AND COLLISION (surface nets)
# ============================================================

func _process(_delta):

	if not dirty.is_empty():
		rebuild_dirty()


func rebuild_dirty():

	for c in dirty:
		build_chunk(c)
	dirty = {}


# One vertex in every cell the surface passes through, at the average of
# where it crosses the cell's edges; one quad across every sample edge
# where the earth begins
func build_chunk(c: Vector3i):

	var x0 = c.x * CHUNK
	var y0 = c.y * CHUNK
	var z0 = c.z * CHUNK
	var x1 = mini(x0 + CHUNK, nx - 1)
	var y1 = mini(y0 + CHUNK, ny - 1)
	var z1 = mini(z0 + CHUNK, nz - 1)
	# Quads along this chunk's low edges need the cells just below it
	var bx = maxi(x0 - 1, 0)
	var by = maxi(y0 - 1, 0)
	var bz = maxi(z0 - 1, 0)
	var w = x1 - bx
	var hgt = y1 - by
	var vid = PackedInt32Array()
	vid.resize(w * hgt * (z1 - bz))
	vid.fill(-1)
	var sy = nx
	var sz = nx * ny
	var verts = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var custom = PackedFloat32Array()
	var uv2 = PackedVector2Array()
	var offsets = [0, 1, sy, sy + 1, sz, sz + 1, sz + sy, sz + sy + 1]

	for z in range(bz, z1):
		for y in range(by, y1):
			for x in range(bx, x1):
				var i = x + nx * (y + ny * z)
				var d0 = density[i]
				var d1 = density[i + 1]
				var d2 = density[i + sy]
				var d3 = density[i + sy + 1]
				var d4 = density[i + sz]
				var d5 = density[i + sz + 1]
				var d6 = density[i + sz + sy]
				var d7 = density[i + sz + sy + 1]
				var s0 = d0 > 0.0
				if s0 == (d1 > 0.0) and s0 == (d2 > 0.0) and s0 == (d3 > 0.0) and s0 == (d4 > 0.0) and s0 == (d5 > 0.0) and s0 == (d6 > 0.0) and s0 == (d7 > 0.0):
					continue
				var sum = Vector3.ZERO
				var n = 0
				# Edges along x
				if (d0 > 0.0) != (d1 > 0.0):
					sum += Vector3(d0 / (d0 - d1), 0, 0)
					n += 1
				if (d2 > 0.0) != (d3 > 0.0):
					sum += Vector3(d2 / (d2 - d3), 1, 0)
					n += 1
				if (d4 > 0.0) != (d5 > 0.0):
					sum += Vector3(d4 / (d4 - d5), 0, 1)
					n += 1
				if (d6 > 0.0) != (d7 > 0.0):
					sum += Vector3(d6 / (d6 - d7), 1, 1)
					n += 1
				# Along y
				if (d0 > 0.0) != (d2 > 0.0):
					sum += Vector3(0, d0 / (d0 - d2), 0)
					n += 1
				if (d1 > 0.0) != (d3 > 0.0):
					sum += Vector3(1, d1 / (d1 - d3), 0)
					n += 1
				if (d4 > 0.0) != (d6 > 0.0):
					sum += Vector3(0, d4 / (d4 - d6), 1)
					n += 1
				if (d5 > 0.0) != (d7 > 0.0):
					sum += Vector3(1, d5 / (d5 - d7), 1)
					n += 1
				# Along z
				if (d0 > 0.0) != (d4 > 0.0):
					sum += Vector3(0, 0, d0 / (d0 - d4))
					n += 1
				if (d1 > 0.0) != (d5 > 0.0):
					sum += Vector3(1, 0, d1 / (d1 - d5))
					n += 1
				if (d2 > 0.0) != (d6 > 0.0):
					sum += Vector3(0, 1, d2 / (d2 - d6))
					n += 1
				if (d3 > 0.0) != (d7 > 0.0):
					sum += Vector3(1, 1, d3 / (d3 - d7))
					n += 1
				var gradient = Vector3((d1 + d3 + d5 + d7) - (d0 + d2 + d4 + d6), (d2 + d3 + d6 + d7) - (d0 + d1 + d4 + d5), (d4 + d5 + d6 + d7) - (d0 + d1 + d2 + d3))
				# The earth showing here: the solid corner nearest the surface
				var ds = [d0, d1, d2, d3, d4, d5, d6, d7]
				var nearest = LIMIT + 1.0
				var m = 0
				for k in 8:
					if ds[k] > 0.0 and ds[k] < nearest:
						nearest = ds[k]
						m = material[i + offsets[k]]
				var look: Array = _palette[m]
				vid[(x - bx) + w * ((y - by) + hgt * (z - bz))] = verts.size()
				verts.append((Vector3(x, y, z) + sum / n) * H - Vector3(0, below, 0))
				normals.append(-gradient.normalized() if gradient.length_squared() > 0.0001 else Vector3.UP)
				var base: Color = look[0]
				colors.append(Color(base.r, base.g, base.b, look[2]))
				var fleck: Color = look[1]
				custom.append_array([fleck.r, fleck.g, fleck.b, fleck.a])
				uv2.append(Vector2(look[3], 0.0))

	var indices = PackedInt32Array()
	for z in range(z0, z1):
		for y in range(y0, y1):
			for x in range(x0, x1):
				var i = x + nx * (y + ny * z)
				var solid = density[i] > 0.0
				var lx = x - bx
				var ly = y - by
				var lz = z - bz
				# Across the edge to x+1: the four cells round it, in order
				# about +x; solid below means the surface faces +x
				if y > 0 and z > 0 and (density[i + 1] > 0.0) != solid:
					quad(indices, vid, lx + w * ((ly - 1) + hgt * (lz - 1)), lx + w * (ly + hgt * (lz - 1)), lx + w * (ly + hgt * lz), lx + w * ((ly - 1) + hgt * lz), solid)
				if x > 0 and z > 0 and (density[i + sy] > 0.0) != solid:
					quad(indices, vid, (lx - 1) + w * (ly + hgt * (lz - 1)), lx + w * (ly + hgt * (lz - 1)), lx + w * (ly + hgt * lz), (lx - 1) + w * (ly + hgt * lz), not solid)
				if x > 0 and y > 0 and (density[i + sz] > 0.0) != solid:
					quad(indices, vid, (lx - 1) + w * ((ly - 1) + hgt * lz), lx + w * ((ly - 1) + hgt * lz), lx + w * (ly + hgt * lz), (lx - 1) + w * (ly + hgt * lz), solid)

	commit_chunk(c, verts, normals, colors, custom, uv2, indices)


func quad(indices: PackedInt32Array, vid: PackedInt32Array, a: int, b: int, c: int, d: int, flip: bool):

	var va = vid[a]
	var vb = vid[b]
	var vc = vid[c]
	var vd = vid[d]
	if va < 0 or vb < 0 or vc < 0 or vd < 0:
		return
	# Godot draws clockwise faces as the front
	if flip:
		indices.append_array([va, vc, vb, va, vd, vc])
	else:
		indices.append_array([va, vb, vc, va, vc, vd])


func commit_chunk(c: Vector3i, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, custom: PackedFloat32Array, uv2: PackedVector2Array, indices: PackedInt32Array):

	var nodes = chunk_nodes.get(c)
	if indices.is_empty():
		if nodes:
			nodes[0].mesh = null
			nodes[1].disabled = true
		return
	if nodes == null:
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.material_override = shader_material
		add_child(mesh_instance)
		var shape = CollisionShape3D.new()
		add_child(shape)
		nodes = [mesh_instance, shape]
		chunk_nodes[c] = nodes

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	nodes[0].mesh = mesh

	var faces = PackedVector3Array()
	faces.resize(indices.size())
	for k in indices.size():
		faces[k] = verts[indices[k]]
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	nodes[1].shape = shape
	nodes[1].disabled = false


# ============================================================
# TARGETING (harvest.gd)
# ============================================================

# Where a swing meets this site's earth: kind "down" digs under Veyl's feet,
# "up" overhead, anything else straight ahead (then low, then high, then
# the ground in front, so a few swings clear a notch to walk into).
# Returns {"point", "normal", "axis"} in site space (axis: the way the
# scoop faces, back toward Veyl), or {} for a miss.
func pick(veyl: Node3D, kind: String, aim: Vector3, reach: float) -> Dictionary:

	var space = get_world_3d().direct_space_state
	var centre = veyl.global_position
	var feet = centre - Vector3(0, veyl.foot_height(), 0)
	var rays = []
	var axis = -Vector3(aim.x, 0, aim.z).normalized()
	match kind:
		"down":
			rays = [[centre, feet + Vector3.DOWN * 10.0], [centre, feet + aim * 1.5 + Vector3.DOWN * 10.0]]
			axis = Vector3.UP
		"up":
			rays = [[centre, centre + aim * 3.0 + Vector3.UP * 7.0], [centre, centre + aim * reach + Vector3.UP * 4.0]]
			axis = Vector3.DOWN
		_:
			rays = [
				[centre, centre + aim * (reach + 2.0)],
				[feet + Vector3.UP * 1.5, feet + Vector3.UP * 1.5 + aim * (reach + 1.0)],
				[centre + Vector3.UP * 3.5, centre + Vector3.UP * 3.5 + aim * (reach + 1.0)],
				[centre, feet + aim * reach * 0.7 + Vector3.DOWN * 1.5],
			]
	for ray in rays:
		var query = PhysicsRayQueryParameters3D.create(ray[0], ray[1])
		query.exclude = [veyl.get_rid()]
		var hit = space.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] == self:
			var to_site = global_basis.inverse()
			return {"point": to_local(hit["position"]), "normal": (to_site * hit["normal"]).normalized(), "axis": (to_site * axis).normalized()}
	return {}


# How far a Veyl's body reaches out from vair centre
static func body_radius(veyl: Node3D) -> float:

	var shape = veyl.get_node_or_null("CollisionShape3D")
	if shape and shape.shape is CylinderShape3D:
		return shape.shape.radius * veyl.scale.x
	return 2.5


# ============================================================
# STRIKES (host decides; everyone sees)
# ============================================================

# args: ["dig", point, surface normal, scoop axis (all site space), strike power]
func host_request(args: Array, sender: int):

	if args.size() < 5 or args[0] != "dig" or typeof(args[1]) != TYPE_VECTOR3 or typeof(args[2]) != TYPE_VECTOR3 or typeof(args[3]) != TYPE_VECTOR3:
		return
	var point: Vector3 = args[1]
	var normal: Vector3 = args[2].normalized()
	var axis: Vector3 = args[3]
	var amount = clampf(float(args[4]), 0.0, MAX_AMOUNT)
	if amount <= 0.0 or axis.length_squared() < 0.01:
		return
	axis = axis.normalized()
	var veyl = NetSync.veyl_of(sender)
	if veyl == null or veyl.global_position.distance_to(to_global(point)) > MAX_STRIKE_REACH:
		return
	var m = material_at(point - normal * 0.5 * H)
	if not Strata.breakable(m):
		return
	# As wide as the swinger; as deep as the work done allows
	var vertical = absf(axis.y) > 0.7
	var width = body_radius(veyl) + (DOWN_MARGIN if vertical else SCOOP_MARGIN)
	var height = width if vertical else SCOOP_HALF_HEIGHT
	var volume = DIG_VOLUME * amount / Strata.def(m)["hits"]
	var depth = clampf(3.0 * volume / (4.0 * PI * width * height), MIN_DEPTH, MAX_DEPTH)
	NetSync.object_fx(self, "dig", [point - axis * depth * 0.25, axis, depth, width, height])
	for mat in last_broken:
		broken[mat] = broken.get(mat, 0.0) + last_broken[mat]
		var d = Strata.def(mat)
		while broken[mat] >= YIELD_VOLUME:
			broken[mat] -= YIELD_VOLUME
			if d.get("drop", "") != "" and randf() < d["chance"]:
				NetSync.drop("loose", d["drop"], to_global(point + normal * 1.5))


func fx_dig(centre: Vector3, axis: Vector3, depth: float, width: float, height: float):

	last_broken = carve(centre, axis, depth, width, height)
	carves.append_array([centre.x, centre.y, centre.z, axis.x, axis.y, axis.z, depth, width, height])
	var at = to_global(centre)
	AshBurst.spawn(get_parent(), at, 0.35 + depth * 0.15)
	if NetSync.near_me(at):
		var hard = last_broken.keys().any(func(m): return Strata.def(m).get("hardness", 0) > 0)
		Sfx.play("enemy_land", -4.0, randf_range(0.7, 0.9) if hard else 1.1)


# Blood moon: the earth closes up again, except round each Veyl (so nobody
# is buried)
func host_regrow():

	var keep = PackedFloat32Array()
	for k in range(0, carves.size() - CARVE_FIELDS + 1, CARVE_FIELDS):
		var at = to_global(Vector3(carves[k], carves[k + 1], carves[k + 2]))
		for veyl in NetSync.all_players():
			if veyl.global_position.distance_to(at) < KEEP_RADIUS:
				keep.append_array(carves.slice(k, k + CARVE_FIELDS))
				break
	broken = {}
	NetSync.object_fx(self, "regrow", [keep])


func fx_regrow(keep: PackedFloat32Array):
	restore(keep)


func net_snapshot():

	if carves.is_empty():
		return null
	return Marshalls.raw_to_base64(carves.to_byte_array())


func apply_snapshot(data):

	if typeof(data) != TYPE_STRING:
		return
	restore(Marshalls.base64_to_raw(data).to_float32_array())
