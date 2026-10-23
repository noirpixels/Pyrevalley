extends Node2D

# One room of the world, built from its final rows (world_gen.gd): the
# ground (terrain.gd), drop-through ledges, ember pits, the backdrop, and
# markers for everything that lives in it, which game.gd spawns.

const Terrain = preload("res://terrain.gd")
const TILE = 40
const CELL_SIZE = Vector2(1280, 720)
# Physics layer for ledges, kept apart from the ground so Veyl can drop
# through them by ignoring just this layer for a moment
const LAYER_LEDGE = 2
const MARKERS = "bkSmwaXHNB"

var data: Dictionary
var cell: Vector2i
var rect: Rect2
var terrain: Terrain
var markers = []        # [{"kind": char, "at": Vector2 (world)}]
var underground: bool
# The hatch over a way down, in world space (empty if none)
var drop_rect: Rect2


func setup(room: Dictionary, world_seed: int):

	data = room
	cell = room["cell"]
	name = "Room%d" % room["index"]
	position = Vector2(cell) * CELL_SIZE
	var rows: Array = room["rows"]
	rect = Rect2(position, Vector2(rows[0].length(), rows.size()) * TILE)
	underground = cell.y > 0

	add_backdrop(rows)

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(rows, world_seed + room["index"] * 7919)

	add_ledges(rows)
	add_pits()
	add_door_marks(rows)

	for y in rows.size():
		for x in rows[y].length():
			var ch = rows[y][x]
			if ch in MARKERS:
				# Standing on the floor of its tile
				markers.append({"kind": ch, "at": position + Vector2(x + 0.5, y + 1) * TILE})


func contains(world_pos: Vector2) -> bool:
	return rect.has_point(world_pos)


func add_backdrop(rows: Array):

	if not underground:
		return
	var back = ColorRect.new()
	back.size = Vector2(rows[0].length(), rows.size()) * TILE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://cave_back.gdshader")
	mat.set_shader_parameter("depth", float(cell.y))
	back.material = mat
	back.z_index = -50
	add_child(back)


# Each run of = becomes one ledge you can jump up through
func add_ledges(rows: Array):

	var body = StaticBody2D.new()
	body.collision_layer = LAYER_LEDGE
	body.collision_mask = 0
	add_child(body)
	for y in rows.size():
		var x = 0
		var row: String = rows[y]
		while x < row.length():
			if row[x] != "=":
				x += 1
				continue
			var run = 0
			while x + run < row.length() and row[x + run] == "=":
				run += 1
			var shape = RectangleShape2D.new()
			shape.size = Vector2(run * TILE, 12)
			var col = CollisionShape2D.new()
			col.shape = shape
			col.one_way_collision = true
			col.position = Vector2((x + run / 2.0) * TILE, y * TILE + 6)
			body.add_child(col)
			var plank = Ledge.new()
			plank.size = Vector2(run * TILE, 14)
			plank.position = Vector2(x * TILE, y * TILE)
			add_child(plank)
			x += run


# Ways up and down glow, so they read as doorways and not just ledges
func add_door_marks(rows: Array):

	if "D" in data["doors"]:
		var mark = DoorMark.new(Rect2(14 * TILE, 16 * TILE - 70, 4 * TILE, 70), 1.0)
		add_child(mark)
		drop_rect = Rect2(position + Vector2(13.5 * TILE, 15 * TILE), Vector2(5 * TILE, TILE + 10))
	if "U" in data["doors"]:
		add_child(DoorMark.new(Rect2(12 * TILE, 0, 8 * TILE, 70), -1.0))


func add_pits():

	for t in terrain.ember_cells:
		var area = Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 4
		area.monitorable = false
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE, 16)
		var col = CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(t.x + 0.5, t.y) * TILE - Vector2(0, 4)
		area.add_child(col)
		area.body_entered.connect(_on_pit_entered)
		add_child(area)


func _on_pit_entered(body: Node):

	if body.has_method("burn_in_pit"):
		body.burn_in_pit()


# Embers drifting through a doorway in the floor (dir 1, drifting down)
# or the ceiling (dir -1, drifting up), with chevrons pointing the way
class DoorMark:
	extends Node2D

	var rect: Rect2
	var dir: float
	var time: float = 0.0

	func _init(area: Rect2, direction: float):
		rect = area
		dir = direction
		z_index = 2

	func _process(delta):
		time += delta
		queue_redraw()

	func _draw():
		var c = rect.get_center()
		var edge = Vector2(c.x, rect.end.y if dir > 0 else rect.position.y)
		InkDraw.glow(self, edge, rect.size.x * 0.75, Color(1.0, 0.5, 0.15, 0.22 + 0.05 * sin(time * 2.0)))
		for k in 3:
			var phase = fmod(time * 0.8 + k / 3.0, 1.0)
			var y = rect.position.y + rect.size.y * (phase if dir > 0 else 1.0 - phase)
			var a = sin(phase * PI) * 0.8
			var w = 18.0
			draw_polyline(PackedVector2Array([Vector2(c.x - w, y - 8 * dir), Vector2(c.x, y + 4 * dir), Vector2(c.x + w, y - 8 * dir)]), Color(1.0, 0.7, 0.35, a), 3.0)
		for k in 6:
			var phase = fmod(time * 0.5 + k * 0.17, 1.0)
			var x = rect.position.x + rect.size.x * fmod(k * 0.37 + 0.1, 1.0)
			var y = rect.position.y + rect.size.y * (phase if dir > 0 else 1.0 - phase)
			draw_circle(Vector2(x, y), 2.0, Color(1.0, 0.6, 0.2, sin(phase * PI)))


# A wooden ledge, inked: boards of uneven length with seams, grain and
# nails, a lit top edge, a darker underside and a soft shadow
class Ledge:
	extends Node2D

	var size: Vector2

	func _draw():
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(position)
		var wood = Color(0.4, 0.28, 0.18)
		draw_rect(Rect2(Vector2(4, size.y), Vector2(size.x - 8, 10)), Color(0, 0, 0, 0.22))

		# The plank, its top edge a little uneven
		var top = PackedVector2Array()
		var bottom = PackedVector2Array()
		var steps = int(size.x / 20.0) + 1
		for i in steps + 1:
			var x = size.x * i / steps
			top.append(Vector2(x, rng.randf_range(-1.0, 1.0)))
			bottom.append(Vector2(x, size.y + rng.randf_range(-0.8, 0.8)))
		var body = top.duplicate()
		var under = bottom.duplicate()
		under.reverse()
		body.append_array(under)
		InkDraw.fill(self, body, wood)
		var lip = top.duplicate()
		var lip_under = PackedVector2Array()
		for p in top:
			lip_under.append(p + Vector2(0, 4))
		lip_under.reverse()
		lip.append_array(lip_under)
		InkDraw.fill(self, lip, wood.lightened(0.28))

		# Boards: seams, a grain line or two and the nails
		var x = 0.0
		while x < size.x:
			var board = rng.randf_range(46.0, 84.0)
			var end = min(x + board, size.x)
			var gy = rng.randf_range(6.0, 10.0)
			InkDraw.line(self, Vector2(x + 6, gy), Vector2(x + (end - x) * rng.randf_range(0.4, 0.8), gy + rng.randf_range(-1.0, 1.0)), 1.4, Color(InkDraw.INK, 0.55), rng.randf() * 9.0)
			if end < size.x - 8:
				InkDraw.line(self, Vector2(end, 1), Vector2(end + rng.randf_range(-1.5, 1.5), size.y - 1), 2.0, InkDraw.INK, rng.randf() * 9.0)
				draw_circle(Vector2(end - 5, 7), 1.6, InkDraw.INK)
				draw_circle(Vector2(end + 5, 7), 1.6, InkDraw.INK)
			x = end

		# The plank's darker underside, seen from a little below
		draw_rect(Rect2(Vector2(0, size.y - 4), Vector2(size.x, 4)), wood.darkened(0.4))

		InkDraw.stroke(self, top, 3.2, InkDraw.INK, position.x)
		InkDraw.stroke(self, bottom, 3.6, InkDraw.INK, position.y)
		InkDraw.line(self, Vector2(0, -1), Vector2(0, size.y + 1), 3.0, InkDraw.INK, 1.0)
		InkDraw.line(self, Vector2(size.x, -1), Vector2(size.x, size.y + 1), 3.0, InkDraw.INK, 2.0)
