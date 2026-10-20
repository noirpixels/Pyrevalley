extends Node3D

# Places Emberwood's mining sites (voxel_site.gd) and makes room for them:
# a hole in the painted ground and its collision where each site's blocks
# take over, and no trees, scenery rocks or set dressing inside. Lives
# under Emberwood, in its local space (Starting Area at z ~ +105).
#   The Old Quarry   east of the Starting Area: soft sedimentary rock,
#                    clay, coal, copper and tin pebbles
#   The Granite Knoll  west of the start: hard granite with tin and iron
#   The Ashen Scar   in the Deep Forest: basalt with iron and Emberstone

const VoxelSite = preload("res://voxel_site.gd")
const Blocks = preload("res://blocks.gd")

# rect: the site's footprint in Emberwood space (x, z, width, length), in
# whole blocks (4 units)
const SITES = [
	{"name": "OldQuarry", "title": "The Old Quarry", "rect": Rect2(10, 64, 28, 24), "below": 5, "above": 3, "profile": "quarry", "seed": 11},
	{"name": "GraniteKnoll", "title": "The Granite Knoll", "rect": Rect2(-38, 72, 20, 24), "below": 5, "above": 4, "profile": "knoll", "seed": 23},
	{"name": "AshenScar", "title": "The Ashen Scar", "rect": Rect2(18, -64, 20, 20), "below": 6, "above": 3, "profile": "scar", "seed": 37},
]

# The ground's collision in Emberwood space (game.tscn GroundCollision)
const GROUND = Rect2(-150, -170, 300, 300)
# The ground mesh sits this far along z from Emberwood's origin
const GROUND_MESH_Z = -20.0


# Is an Emberwood-space point on (or within margin of) a mining site?
static func covers(local: Vector3, margin: float = 0.0) -> bool:

	for site in SITES:
		if site["rect"].grow(margin).has_point(Vector2(local.x, local.z)):
			return true
	return false


func _ready():

	name = "MiningSites"
	var level = get_parent()
	clear_footprints(level)
	cut_ground(level)
	for def in SITES:
		var site = VoxelSite.new()
		site.name = def["name"]
		site.title = def["title"]
		var r: Rect2 = def["rect"]
		site.width = int(r.size.x / Blocks.SIZE)
		site.length = int(r.size.y / Blocks.SIZE)
		site.below = def["below"]
		site.above = def["above"]
		site.profile = def["profile"]
		site.seed_value = def["seed"]
		site.position = Vector3(r.position.x, 0, r.position.y)
		add_child(site)


# Trees and scenery rocks that would stand in a site
func clear_footprints(level: Node):

	for group in ["Trees", "Rocks"]:
		var node = level.get_node_or_null(group)
		if node == null:
			continue
		for child in node.get_children():
			if child is Node3D and covers(child.position, 3.0):
				child.free()


# The painted ground skips each site (game.gdshader holes), and its
# collision is rebuilt as boxes around them
func cut_ground(level: Node):

	var ground = level.get_node_or_null("Ground")
	if ground == null:
		return
	var holes = []
	for def in SITES:
		var r: Rect2 = def["rect"]
		holes.append(Vector4(r.position.x, r.position.y - GROUND_MESH_Z, r.end.x, r.end.y - GROUND_MESH_Z))
	var mat = ground.mesh.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("holes", holes)
		mat.set_shader_parameter("hole_count", holes.size())

	var csg = ground.get_node_or_null("GroundCollision")
	if csg:
		csg.use_collision = false

	# Split the ground into a grid at every hole edge; keep the cells that
	# aren't a hole, merged into runs along x
	var xs = [GROUND.position.x, GROUND.end.x]
	var zs = [GROUND.position.y, GROUND.end.y]
	for def in SITES:
		var r: Rect2 = def["rect"]
		xs.append_array([r.position.x, r.end.x])
		zs.append_array([r.position.y, r.end.y])
	xs.sort()
	zs.sort()
	var body = StaticBody3D.new()
	body.name = "GroundCollision"
	level.add_child.call_deferred(body)
	for j in zs.size() - 1:
		var run_start = -1
		for i in xs.size():
			var solid = i < xs.size() - 1 and xs[i + 1] > xs[i] and zs[j + 1] > zs[j] and not covers(Vector3((xs[i] + xs[i + 1]) / 2.0, 0, (zs[j] + zs[j + 1]) / 2.0))
			if solid and run_start < 0:
				run_start = i
			elif not solid and run_start >= 0:
				add_ground_box(body, xs[run_start], xs[i], zs[j], zs[j + 1])
				run_start = -1


func add_ground_box(body: StaticBody3D, x0: float, x1: float, z0: float, z1: float):

	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(x1 - x0, 2.0, z1 - z0)
	shape.shape = box
	shape.position = Vector3((x0 + x1) / 2.0, -1.0, (z0 + z1) / 2.0)
	body.add_child(shape)
