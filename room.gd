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


# A wooden ledge: a plank with an ink edge and a couple of brackets
class Ledge:
	extends Node2D

	var size: Vector2

	func _draw():
		var ink = Color(0.035, 0.028, 0.045)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.25, 0.16))
		draw_rect(Rect2(Vector2(0, 0), Vector2(size.x, 4)), Color(0.5, 0.36, 0.22))
		draw_rect(Rect2(Vector2.ZERO, size), ink, false, 2.0)
		var step = 40.0
		var x = step * 0.5
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x - 6, size.y + 12), ink, 3.0)
			x += step
