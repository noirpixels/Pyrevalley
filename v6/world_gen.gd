extends RefCounted

# Emberwood's layout for one world seed (GameState.world_seed). Every new
# world is its own forest: each place the story needs picks one of about
# ten spots (CANDIDATES), paths wind between them, and pines, rocks,
# creatures and set dressing fill in around. The same seed always builds
# the same world, so a guest's matches the host's (net.gd sends the seed).
#
# The forest comes in two parts. The outer forest holds the Waking Glade,
# Rowan's camp, the Old Smithy, the Proving Ring and two mining sites.
# North of a wavering wall of pines lies the Deep Forest, reached through
# one ember gate: the Ashen Scar, the Broken Blades and, walled in by its
# own ring, the Ashbound Arena.
# Built once per scene by emberwood.gd (current); everything here is in
# Emberwood's local space.

# The playable area (x, z, width, length)
const BOUNDS = Rect2(-135, -185, 270, 335)
# The Deep Forest's edge: z = DEEP_BASE give or take DEEP_SWAY, wandering
# along x. It's fully dark DEEP_SPAN past the edge.
const DEEP_BASE = -30.0
const DEEP_SWAY = 14.0
const DEEP_SPAN = 70.0
# The edge as the ground shader gets it: z every DEEP_STEP from DEEP_START
const DEEP_START = -136.0
const DEEP_STEP = 4.0
const DEEP_SAMPLES = 69
const GATE_WIDTH = 20.0
const ARENA_RADIUS = 30.0
const ARENA_WALL = 34.0
const RING_RADIUS = 18.0
# Path widths: the main path from the glade to the arena, and the branches off it
const MAIN_PATH_WIDTH = 4.0
const BRANCH_PATH_WIDTH = 3.2
# Spatial hash for path distance
const PATH_CELL = 8.0
const TREE_SPACING = 8.0
const ROCKS = 60

# Where each place may go (x, z)
const CANDIDATES = {
	"glade": [Vector2(-100, 114), Vector2(-75, 104), Vector2(-50, 116), Vector2(-25, 108), Vector2(0, 118), Vector2(25, 104), Vector2(50, 116), Vector2(75, 108), Vector2(100, 114), Vector2(-5, 96)],
	"rowan": [Vector2(-80, 40), Vector2(-55, 55), Vector2(-30, 30), Vector2(-10, 60), Vector2(10, 35), Vector2(35, 55), Vector2(60, 30), Vector2(85, 50), Vector2(-100, 65), Vector2(100, 65)],
	"arena": [Vector2(-85, -130), Vector2(-58, -120), Vector2(-30, -134), Vector2(0, -126), Vector2(28, -136), Vector2(56, -122), Vector2(85, -132), Vector2(-72, -110), Vector2(45, -110), Vector2(-12, -110)],
	"ring": [Vector2(-100, 95), Vector2(-70, 40), Vector2(-40, 95), Vector2(0, 30), Vector2(40, 95), Vector2(70, 50), Vector2(100, 95), Vector2(-95, 12), Vector2(95, 15), Vector2(30, 55)],
	"quarry": [Vector2(-95, 85), Vector2(-65, 60), Vector2(-35, 30), Vector2(5, 75), Vector2(35, 40), Vector2(65, 85), Vector2(95, 50), Vector2(-85, 15), Vector2(20, 12), Vector2(80, 15)],
	"knoll": [Vector2(-105, 50), Vector2(-75, 95), Vector2(-20, 55), Vector2(10, 95), Vector2(45, 65), Vector2(75, 40), Vector2(105, 90), Vector2(-55, 15), Vector2(55, 12), Vector2(-5, 22)],
	"smithy": [Vector2(-90, 60), Vector2(-60, 35), Vector2(-30, 80), Vector2(0, 45), Vector2(30, 70), Vector2(60, 40), Vector2(90, 75), Vector2(-100, 20), Vector2(100, 25), Vector2(-45, 10)],
	"scar": [Vector2(-100, -70), Vector2(-70, -95), Vector2(-40, -65), Vector2(-10, -90), Vector2(20, -70), Vector2(50, -95), Vector2(80, -65), Vector2(105, -90), Vector2(-95, -100), Vector2(10, -60)],
	"blades": [Vector2(-110, -60), Vector2(-80, -80), Vector2(-50, -100), Vector2(-20, -70), Vector2(10, -105), Vector2(40, -75), Vector2(70, -100), Vector2(100, -70), Vector2(-60, -55), Vector2(55, -55)],
}
# Where the ember gate into the Deep Forest may stand along its edge (x)
const GATE_XS = [-100.0, -78.0, -56.0, -34.0, -12.0, 10.0, 32.0, 54.0, 76.0, 98.0]
# Room each place needs around its centre
const ROOM = {"glade": 26.0, "rowan": 20.0, "arena": 42.0, "ring": 23.0, "quarry": 20.0, "knoll": 18.0, "smithy": 11.0, "scar": 16.0, "blades": 7.0}
# Placed in this order, each keeping clear of the ones before
const PLACE_ORDER = ["glade", "rowan", "arena", "ring", "quarry", "knoll", "smithy", "scar", "blades"]
const DEEP_PLACES = ["arena", "scar", "blades"]

# Mining sites: size (x, z), depth below ground and the tallest the hill rises
const SITES = {
	"quarry": {"name": "OldQuarry", "title": "The Old Quarry", "size": Vector2(28, 24), "below": 20, "above": 9, "profile": "quarry"},
	"knoll": {"name": "GraniteKnoll", "title": "The Granite Knoll", "size": Vector2(20, 24), "below": 20, "above": 7, "profile": "knoll"},
	"scar": {"name": "AshenScar", "title": "The Ashen Scar", "size": Vector2(20, 20), "below": 24, "above": 7, "profile": "scar"},
}

# Creatures roaming each part of the forest (spawner names in game.tscn)
const OUTER_CREATURES = ["ForestMossling1", "ForestWolf1", "ForestMossling2", "ForestWolf2", "ForestMossling3"]
const DEEP_CREATURES = ["DeepWolf1", "DeepCrawler1", "DeepMossling1", "DeepCrawler2", "DeepWolf2", "DeepCrawler3", "DeepMossling2"]

static var current = null

var seed_value: int = 0
var deep_noise: FastNoiseLite
# Place name -> centre
var places: Dictionary = {}
var gate: Vector3
# Across the gate, into the Deep Forest
var gate_normal: Vector3
var has_gate: bool = false
# From the arena's centre out through its entrance
var arena_out: Vector3
var arena_entrance: Vector3
var glade_forward: Vector3
var rowan_forward: Vector3
var smithy_facing: Vector3
# Where a new Veyl wakes, and the portal into the Proving Ring
var spawn: Vector3
var ring_portal: Vector3
# Mining sites: SITES entries plus "rect" (x, z, width, length) and "seed"
var sites: Array = []
# Polylines in x/z; paths[0] is the main path
var paths: Array = []
var path_widths: Array = []
var segment_grid: Dictionary = {}
# Node path under Emberwood -> {"pos": Vector3, "yaw": float}
var markers: Dictionary = {}
# [centre, radius] kept free of trees and clutter
var clearings: Array = []
# [position, yaw, scale]
var trees: Array = []
var rocks: Array = []
# Invisible walls: [from, to]
var walls: Array = []


func build(world_seed: int):

	seed_value = world_seed
	deep_noise = FastNoiseLite.new()
	deep_noise.seed = world_seed
	deep_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	deep_noise.frequency = 0.008
	var rng = RandomNumberGenerator.new()
	rng.seed = world_seed
	place_story(rng)
	lay_paths(rng)
	place_markers(rng)
	build_walls()
	plant(rng)


# ============================================================
# QUERIES
# ============================================================

func deep_line(x: float) -> float:
	return DEEP_BASE + deep_noise.get_noise_1d(x) * DEEP_SWAY


func is_deep(p: Vector3) -> bool:
	return p.z < deep_line(p.x)


# 0 in the outer forest, rising to 1 DEEP_SPAN past the Deep Forest's edge
func deepness(p: Vector3) -> float:
	return clampf((deep_line(p.x) - p.z) / DEEP_SPAN, 0.0, 1.0)


# The edge, sampled the way the ground shader reads it
func deep_line_samples() -> PackedFloat32Array:

	var out = PackedFloat32Array()
	for i in DEEP_SAMPLES:
		out.append(deep_line(DEEP_START + i * DEEP_STEP))
	return out


func arena() -> Vector3:
	return places["arena"]


func in_arena(p: Vector3, margin: float = 0.0) -> bool:
	return flat(p - arena()).length() < ARENA_RADIUS + margin


func on_site(p: Vector3, margin: float = 0.0) -> bool:

	for site in sites:
		if site["rect"].grow(margin).has_point(Vector2(p.x, p.z)):
			return true
	return false


# Somewhere a gameplay place already stands: a site, a clearing, the
# arena or the ring
func blocked(p: Vector3, margin: float) -> bool:

	if on_site(p, margin) or flat(p - arena()).length() < ARENA_WALL + margin:
		return true
	for c in clearings:
		if flat(p - c[0]).length() < c[1] + margin:
			return true
	return false


func inside(p: Vector3, margin: float = 0.0) -> bool:
	return BOUNDS.grow(-margin).has_point(Vector2(p.x, p.z))


# Distance to the nearest path (anything past PATH_CELL counts as far)
func path_distance(p: Vector3) -> float:

	var at = Vector2(p.x, p.z)
	var cell = Vector2i(floori(at.x / PATH_CELL), floori(at.y / PATH_CELL))
	var best = INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for seg in segment_grid.get(cell + Vector2i(dx, dz), []):
				best = minf(best, Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1]).distance_to(at))
	return best


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# Right of a facing, on the ground
static func right_of(forward: Vector3) -> Vector3:
	return Vector3(-forward.z, 0, forward.x)


# Turn that points a node's -Z along dir
static func yaw_toward(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


# ============================================================
# STORY PLACES
# ============================================================

func place_story(rng: RandomNumberGenerator):

	for place in PLACE_ORDER:
		places[place] = choose(place, rng)
		# The gate goes in once both sides of it are known
		if place == "rowan":
			place_gate(rng)

	glade_forward = flat(places["rowan"] - places["glade"]).normalized()
	rowan_forward = flat(gate - places["rowan"]).normalized()
	arena_out = flat(gate - arena()).normalized()
	arena_entrance = arena() + arena_out * ARENA_WALL
	spawn = places["glade"]

	var site_seed = 11
	for key in ["quarry", "knoll", "scar"]:
		var def: Dictionary = SITES[key].duplicate()
		var size: Vector2 = def["size"]
		var c: Vector3 = places[key]
		def["rect"] = Rect2(roundf(c.x - size.x / 2.0), roundf(c.z - size.y / 2.0), size.x, size.y)
		def["seed"] = seed_value + site_seed
		site_seed += 12
		sites.append(def)


# The first of the place's spots (in a seeded shuffle) with room, or the
# roomiest if none has
func choose(place: String, rng: RandomNumberGenerator) -> Vector3:

	var best = Vector3.ZERO
	var best_room = -INF
	for c in shuffled(CANDIDATES[place], rng):
		var p = Vector3(c.x, 0, c.y)
		var room = room_at(place, p)
		if room >= 0.0:
			return p
		if room > best_room:
			best_room = room
			best = p
	return best


# How much space is left over around p (negative: it doesn't fit)
func room_at(place: String, p: Vector3) -> float:

	var r: float = ROOM[place]
	var room = INF
	for other in places:
		room = minf(room, flat(p - places[other]).length() - r - ROOM[other] - 6.0)
	var past_edge = deep_line(p.x) - p.z
	if place in DEEP_PLACES:
		room = minf(room, past_edge - r - 12.0)
	else:
		room = minf(room, -past_edge - r - 12.0)
	if has_gate:
		room = minf(room, flat(p - gate).length() - r - 24.0)
	room = minf(room, minf(p.x - BOUNDS.position.x, BOUNDS.end.x - p.x) - r - 4.0)
	room = minf(room, minf(p.z - BOUNDS.position.y, BOUNDS.end.y - p.z) - r - 4.0)
	return room


func place_gate(rng: RandomNumberGenerator):

	var best_room = -INF
	for x in shuffled(GATE_XS, rng):
		var p = Vector3(x, 0, deep_line(x))
		var room = minf(flat(p - places["glade"]).length() - 70.0, flat(p - places["rowan"]).length() - 30.0)
		if room > best_room:
			best_room = room
			gate = p
		if room >= 0.0:
			break
	var slope = (deep_line(gate.x + 1.0) - deep_line(gate.x - 1.0)) / 2.0
	gate_normal = Vector3(slope, 0, -1).normalized()
	has_gate = true


func shuffled(items: Array, rng: RandomNumberGenerator) -> Array:

	var out = items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


# ============================================================
# PATHS
# ============================================================

func lay_paths(rng: RandomNumberGenerator):

	# Glade, past Rowan's fire, through the gate, on to the arena
	var camp = places["rowan"] + right_of(rowan_forward) * 8.0
	var before_gate = gate - gate_normal * 12.0
	var after_gate = gate + gate_normal * 12.0
	var before_arena = arena_entrance + arena_out * 12.0
	var main = PackedVector2Array()
	main.append_array(wiggle(v2(places["glade"]), v2(camp), rng, false))
	main.append_array(wiggle(v2(camp), v2(before_gate), rng, false))
	main.append(v2(gate))
	main.append_array(wiggle(v2(after_gate), v2(before_arena), rng, true))
	main.append(v2(arena_entrance))
	main = smooth(main)
	add_path(main, MAIN_PATH_WIDTH)

	# The smithy opens toward the path
	var smithy = places["smithy"]
	var near = nearest_on(main, v2(smithy), false)
	smithy_facing = flat(Vector3(near.x, 0, near.y) - smithy).normalized()
	branch(main, smithy + smithy_facing * 8.0, false, rng)
	for site in sites:
		var deep = site["profile"] == "scar"
		var r: Rect2 = site["rect"]
		var from = nearest_on(main, r.get_center(), deep)
		# To the side of the site facing the path
		var door = Vector2(clampf(from.x, r.position.x, r.end.x), clampf(from.y, r.position.y, r.end.y))
		var out = (from - r.get_center()).normalized()
		branch(main, Vector3(door.x + out.x * 2.0, 0, door.y + out.y * 2.0), deep, rng)
	branch(main, places["blades"], true, rng)


func branch(main: PackedVector2Array, to: Vector3, deep: bool, rng: RandomNumberGenerator):

	var from = nearest_on(main, v2(to), deep)
	add_path(smooth(wiggle(from, v2(to), rng, deep)), BRANCH_PATH_WIDTH)


func add_path(points: PackedVector2Array, width: float):

	paths.append(points)
	path_widths.append(width)
	for i in points.size() - 1:
		var a = points[i]
		var b = points[i + 1]
		var lo = Vector2i(floori(minf(a.x, b.x) / PATH_CELL), floori(minf(a.y, b.y) / PATH_CELL))
		var hi = Vector2i(floori(maxf(a.x, b.x) / PATH_CELL), floori(maxf(a.y, b.y) / PATH_CELL))
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var key = Vector2i(cx, cz)
				if not segment_grid.has(key):
					segment_grid[key] = []
				segment_grid[key].append([a, b])


# A winding line from a to b (midpoint displacement), kept on its own side
# of the Deep Forest's edge and inside the bounds
func wiggle(a: Vector2, b: Vector2, rng: RandomNumberGenerator, deep: bool) -> PackedVector2Array:

	var pts = [a, b]
	var amp = a.distance_to(b) * 0.16
	for level in 4:
		var out = [pts[0]]
		for i in pts.size() - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var mid = (p0 + p1) / 2.0 + (p1 - p0).orthogonal().normalized() * rng.randf_range(-amp, amp)
			out.append(keep_side(mid, deep))
			out.append(p1)
		pts = out
		amp *= 0.5
	return PackedVector2Array(pts)


func keep_side(p: Vector2, deep: bool) -> Vector2:

	var edge = deep_line(p.x)
	if deep and p.y > edge - 8.0:
		p.y = edge - 8.0
	elif not deep and p.y < edge + 8.0:
		p.y = edge + 8.0
	p.x = clampf(p.x, BOUNDS.position.x + 10.0, BOUNDS.end.x - 10.0)
	p.y = clampf(p.y, BOUNDS.position.y + 10.0, BOUNDS.end.y - 10.0)
	return p


# Chaikin corner cutting, keeping the ends
func smooth(points: PackedVector2Array) -> PackedVector2Array:

	for pass_number in 2:
		var out = PackedVector2Array([points[0]])
		for i in points.size() - 1:
			out.append(points[i].lerp(points[i + 1], 0.25))
			out.append(points[i].lerp(points[i + 1], 0.75))
		out.append(points[points.size() - 1])
		points = out
	return points


# The point on a path nearest to p, from its outer or deep stretch
func nearest_on(path: PackedVector2Array, p: Vector2, deep: bool) -> Vector2:

	var best = path[0]
	var best_d = INF
	for i in path.size() - 1:
		var q = Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
		if (q.y < deep_line(q.x)) != deep:
			continue
		var d = q.distance_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


static func v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


# ============================================================
# MARKERS (the story's nodes in game.tscn)
# ============================================================

func place_markers(rng: RandomNumberGenerator):

	var glade = places["glade"]
	var rowan = places["rowan"]
	var gf = glade_forward
	var rf = rowan_forward
	var side = right_of(arena_out)

	clearings = [
		[glade, 22.0], [rowan, 16.0], [places["smithy"], 11.0], [places["ring"], RING_RADIUS + 5.0],
		[places["blades"], 7.0], [gate, 14.0], [arena_entrance + arena_out * 10.0, 12.0],
	]

	mark("Shrines/StartShrine", beside(glade, gf, -8, -3))
	mark("Signs/MoveSign", beside(glade, gf, -12, 9) + Vector3(0, 3, 0))
	mark("Signs/FightSign", beside(glade, gf, 12, 17) + Vector3(0, 3, 0))
	mark("Signs/ShrineSign", beside(glade, gf, -8, -13) + Vector3(0, 3, 0))
	mark("LoreStones/WakingStone", beside(glade, gf, 24, -7))
	mark("Creatures/StartMossling", beside(glade, gf, 6, 15))
	ring_portal = beside(glade, gf, 14, -5)

	mark("Rowan", rowan)
	mark("Shrines/RowanShrine", beside(rowan, rf, -14, -2))
	mark("LoreStones/FleeingStone", beside(rowan, rf, -16, -16))

	mark("Gates/DeepForestGate", gate, yaw_toward(gate_normal))
	mark("Gates/ArenaGate", arena_entrance, yaw_toward(-arena_out))
	mark("Gates/ArenaSeal", arena_entrance, yaw_toward(-arena_out))
	mark("Shrines/ArenaShrine", arena_entrance + arena_out * 10.0 - side * 10.0)
	mark("LoreStones/AshboundStone", arena_entrance + arena_out * 6.0 + side * 16.0)
	mark("Creatures/Ashbound", arena())

	# Creatures roam their own part of the forest, apart from each other
	var taken: Array = [markers["Creatures/StartMossling"]["pos"]]
	for spawner in OUTER_CREATURES:
		var far = 55.0 if "Wolf" in spawner else 40.0
		var p = find_spot(rng, false, taken, 18.0, func(q): return flat(q - glade).length() > far and flat(q - rowan).length() > 26.0)
		mark("Creatures/" + spawner, p)
		taken.append(p)
	for spawner in DEEP_CREATURES:
		var p = find_spot(rng, true, taken, 18.0, func(q): return flat(q - gate).length() > 22.0)
		mark("Creatures/" + spawner, p)
		taken.append(p)

	# Rare materials, tucked away off the paths
	var off_path = func(q): return path_distance(q) > 9.0
	for pickup in [["MossFiberHidden", false], ["MossFiberClearing", false], ["EmberFangRoots", true], ["AshCoreHollow", true]]:
		var p = find_spot(rng, pickup[1], taken, 12.0, off_path)
		mark("Pickups/" + pickup[0], p)
		taken.append(p)


func mark(node_path: String, p: Vector3, yaw: float = 0.0):

	# Keep it inside the forest whatever way the place faces
	p.x = clampf(p.x, BOUNDS.position.x + 6.0, BOUNDS.end.x - 6.0)
	p.z = clampf(p.z, BOUNDS.position.y + 6.0, BOUNDS.end.y - 6.0)
	markers[node_path] = {"pos": p, "yaw": yaw}


# A point to the right (r) and ahead (a) of an origin facing forward
func beside(origin: Vector3, forward: Vector3, r: float, a: float) -> Vector3:
	return origin + right_of(forward) * r + forward * a


# A random open spot in the outer or deep forest, gap from everything in
# apart, that also passes extra
func find_spot(rng: RandomNumberGenerator, deep: bool, apart: Array, gap: float, extra: Callable) -> Vector3:

	var p = Vector3.ZERO
	for attempt in 400:
		p = Vector3(rng.randf_range(BOUNDS.position.x + 14.0, BOUNDS.end.x - 14.0), 0, rng.randf_range(BOUNDS.position.y + 14.0, BOUNDS.end.y - 14.0))
		if is_deep(p) != deep or absf(deep_line(p.x) - p.z) < 12.0:
			continue
		if blocked(p, 6.0):
			continue
		if apart.any(func(q): return flat(p - q).length() < gap):
			continue
		if extra.call(p):
			return p
	return p


# ============================================================
# WALLS AND FOREST
# ============================================================

# The Deep Forest's edge, open only at the gate, and the arena's ring,
# open only at its entrance
func build_walls():

	var tangent = Vector3(-gate_normal.z, 0, gate_normal.x)
	if tangent.x < 0.0:
		tangent = -tangent
	var gap_left = gate - tangent * (GATE_WIDTH / 2.0)
	var gap_right = gate + tangent * (GATE_WIDTH / 2.0)
	var edge = []
	var x = BOUNDS.position.x
	while x < gap_left.x:
		edge.append(Vector3(x, 0, deep_line(x)))
		x += 6.0
	edge.append(gap_left)
	for i in edge.size() - 1:
		walls.append([edge[i], edge[i + 1]])
	edge = [gap_right]
	x = ceilf(gap_right.x / 6.0) * 6.0
	while x <= BOUNDS.end.x:
		edge.append(Vector3(x, 0, deep_line(x)))
		x += 6.0
	for i in edge.size() - 1:
		walls.append([edge[i], edge[i + 1]])

	var open_half = asin((GATE_WIDTH / 2.0) / ARENA_WALL)
	var start = atan2(arena_out.z, arena_out.x) + open_half
	var sweep = TAU - open_half * 2.0
	var steps = 28
	for i in steps:
		var a0 = start + sweep * i / steps
		var a1 = start + sweep * (i + 1) / steps
		walls.append([arena() + Vector3(cos(a0), 0, sin(a0)) * ARENA_WALL, arena() + Vector3(cos(a1), 0, sin(a1)) * ARENA_WALL])


func plant(rng: RandomNumberGenerator):

	var keep = []
	for key in markers:
		keep.append(markers[key]["pos"])
	keep.append(ring_portal)
	# Mining sites stand in a clearing, so their hills aren't lost under the pines
	var fits = func(p: Vector3, margin: float) -> bool:
		if not inside(p, 3.0) or blocked(p, margin) or on_site(p, 8.0) or path_distance(p) < 6.0:
			return false
		return not keep.any(func(k): return flat(p - k).length() < 5.0)

	# A dark band of pines round the edge of the world
	var edge_step = 6.0
	var perimeter = []
	var r = BOUNDS.grow(-3.0)
	var x = r.position.x
	while x <= r.end.x:
		perimeter.append(Vector3(x, 0, r.position.y))
		perimeter.append(Vector3(x, 0, r.end.y))
		x += edge_step
	var z = r.position.y + edge_step
	while z < r.end.y:
		perimeter.append(Vector3(r.position.x, 0, z))
		perimeter.append(Vector3(r.end.x, 0, z))
		z += edge_step
	for p in perimeter:
		add_tree(rng, p + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)))

	# Two ragged rows along the Deep Forest's edge, broken at the gate
	x = BOUNDS.position.x + 6.0
	while x < BOUNDS.end.x - 6.0:
		if absf(x - gate.x) > GATE_WIDTH / 2.0 + 4.0:
			var e = deep_line(x)
			add_tree(rng, Vector3(x + rng.randf_range(-1.0, 1.0), 0, e + rng.randf_range(1.0, 3.5)))
			if rng.randf() < 0.75:
				add_tree(rng, Vector3(x + 2.2 + rng.randf_range(-1.0, 1.0), 0, e - rng.randf_range(1.5, 4.0)))
		x += 4.5

	# Round the arena, outside its wall, but not across the entrance
	var open_half = asin((GATE_WIDTH / 2.0 + 4.0) / ARENA_WALL)
	var out_angle = atan2(arena_out.z, arena_out.x)
	for ring_r in [ARENA_WALL + 3.0, ARENA_WALL + 8.0]:
		var count = int(TAU * ring_r / 5.5)
		for i in count:
			var a = TAU * i / count + rng.randf_range(-0.04, 0.04)
			if absf(angle_difference(a, out_angle)) < open_half:
				continue
			add_tree(rng, arena() + Vector3(cos(a), 0, sin(a)) * (ring_r + rng.randf_range(-1.0, 1.0)))

	# The forest itself: patchy where the noise says, thinner in the Deep Forest
	var density = FastNoiseLite.new()
	density.seed = seed_value + 5
	density.frequency = 0.025
	z = BOUNDS.position.y + 10.0
	while z < BOUNDS.end.y - 8.0:
		x = BOUNDS.position.x + 10.0
		while x < BOUNDS.end.x - 8.0:
			var p = Vector3(x + rng.randf_range(-3.0, 3.0), 0, z + rng.randf_range(-3.0, 3.0))
			var deep = is_deep(p)
			var threshold = 0.15 if deep else -0.2
			if density.get_noise_2d(p.x, p.z) > threshold and absf(deep_line(p.x) - p.z) > 6.0 and fits.call(p, 3.0):
				add_tree(rng, p)
			x += TREE_SPACING
		z += TREE_SPACING

	# Boulders among the trees
	var placed = 0
	for attempt in ROCKS * 6:
		if placed >= ROCKS:
			break
		var p = Vector3(rng.randf_range(BOUNDS.position.x + 8.0, BOUNDS.end.x - 8.0), 0, rng.randf_range(BOUNDS.position.y + 8.0, BOUNDS.end.y - 8.0))
		if not fits.call(p, 4.0) or absf(deep_line(p.x) - p.z) < 5.0:
			continue
		if trees.any(func(t): return flat(p - t[0]).length() < 4.0):
			continue
		rocks.append([p, rng.randf() * TAU, rng.randf_range(0.7, 1.4)])
		placed += 1


func add_tree(rng: RandomNumberGenerator, p: Vector3):
	trees.append([p, rng.randf() * TAU, rng.randf_range(0.85, 1.25)])
