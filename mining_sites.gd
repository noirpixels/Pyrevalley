extends Node3D

# Places Emberwood's mining sites (dig_site.gd) where this world put them
# (world_gen.gd) and makes room for them: a hole in the painted ground and
# its collision where each site's own earth takes over. Lives under
# Emberwood, in its local space.
#   The Old Quarry     outer forest: soft sedimentary rock, clay, coal,
#                      copper and tin pebbles
#   The Granite Knoll  outer forest: hard granite with tin and iron
#   The Ashen Scar     Deep Forest: basalt with iron and Emberstone

const DigSite = preload("res://dig_site.gd")
const WorldGen = preload("res://world_gen.gd")

# The ground's collision in Emberwood space: the whole ground plane
const GROUND = Rect2(-150, -210, 300, 380)
# The ground stops this far inside each site's edge, where the site's own
# surface (one sample cell in from its rim) begins
const INSET = DigSite.H / 2.0


# Is an Emberwood-space point on (or within margin of) a mining site?
static func covers(local: Vector3, margin: float = 0.0) -> bool:
	return WorldGen.current != null and WorldGen.current.on_site(local, margin)


func _ready():

	name = "MiningSites"
	var level = get_parent()
	cut_ground(level)
	for def in WorldGen.current.sites:
		var site = DigSite.new()
		site.name = def["name"]
		site.title = def["title"]
		var r: Rect2 = def["rect"]
		site.size = r.size
		site.below = def["below"]
		site.above = def["above"]
		site.profile = def["profile"]
		site.seed_value = def["seed"]
		site.position = Vector3(r.position.x, 0, r.position.y)
		add_child(site)


func holes() -> Array:
	return WorldGen.current.sites.map(func(def): return def["rect"].grow(-INSET))


# The painted ground skips each site (game.gdshader holes), and its
# collision is rebuilt as boxes around them
func cut_ground(level: Node):

	var ground = level.get_node_or_null("Ground")
	if ground == null:
		return
	var shader_holes = []
	for r in holes():
		shader_holes.append(Vector4(r.position.x, r.position.y - ground.position.z, r.end.x, r.end.y - ground.position.z))
	var mat = ground.mesh.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("holes", shader_holes)
		mat.set_shader_parameter("hole_count", shader_holes.size())

	var csg = ground.get_node_or_null("GroundCollision")
	if csg:
		csg.use_collision = false

	# Split the ground into a grid at every hole edge; keep the cells that
	# aren't a hole, merged into runs along x
	var xs = [GROUND.position.x, GROUND.end.x]
	var zs = [GROUND.position.y, GROUND.end.y]
	for r in holes():
		xs.append_array([r.position.x, r.end.x])
		zs.append_array([r.position.y, r.end.y])
	xs.sort()
	zs.sort()
	var cut = holes()
	var body = StaticBody3D.new()
	body.name = "GroundCollision"
	level.add_child.call_deferred(body)
	for j in zs.size() - 1:
		var run_start = -1
		for i in xs.size():
			var solid = false
			if i < xs.size() - 1 and xs[i + 1] > xs[i] and zs[j + 1] > zs[j]:
				var mid = Vector2((xs[i] + xs[i + 1]) / 2.0, (zs[j] + zs[j + 1]) / 2.0)
				solid = not cut.any(func(r): return r.has_point(mid))
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
