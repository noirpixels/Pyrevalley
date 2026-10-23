extends Node2D

# A room's ground as a smooth density field rather than blocks: a grid of
# 10 px cells, each 0..1 solid, drawn by terrain.gdshader where the field
# crosses one half, so edges come out as curves. Digging lowers the field
# in a circle. Collision is rebuilt from the same field as merged
# rectangles, so what you see is what you stand on (to within a few px).
#
# Materials per cell: bedrock (never breaks), earth (any pickaxe), rock
# (bronze pickaxe), ember (the pits; hurts, never breaks). Ore sits at
# points inside earth and drops out once the ground around it is dug away.

signal ore_uncovered(item: String, at: Vector2)

const GRID = 10
const CELLS_PER_TILE = 4
const BEDROCK = 0
const EARTH = 1
const ROCK = 2
const EMBER = 3
# Tier a pickaxe needs to cut each material (0 = never)
const NEEDS = {BEDROCK: 0, EARTH: 1, ROCK: 2, EMBER: 0}
const ORE_ITEMS = {"c": "Copper Ore", "t": "Tin Ore", "f": "Flint"}
# Physics layer for the ground
const LAYER_WORLD = 1

var w: int
var h: int
var density: PackedFloat32Array
var mats_grid: PackedByteArray
var ores = []           # [{"item", "at" (local px), "cell": Vector2i}]
var image: Image
var texture: ImageTexture
var sprite: Sprite2D
var body: StaticBody2D
var ember_cells = []    # tiles that hurt, for the room to make into hazards
var ore_marks: Node2D


func build(rows: Array, noise_seed: int):

	w = rows[0].length() * CELLS_PER_TILE
	h = rows.size() * CELLS_PER_TILE
	density = PackedFloat32Array()
	density.resize(w * h)
	mats_grid = PackedByteArray()
	mats_grid.resize(w * h)

	var mats = {"#": BEDROCK, "E": EARTH, "c": EARTH, "t": EARTH, "f": EARTH, "R": ROCK, "x": EMBER}
	for ty in rows.size():
		for tx in rows[ty].length():
			var ch = rows[ty][tx]
			if not mats.has(ch):
				continue
			for cy in CELLS_PER_TILE:
				for cx in CELLS_PER_TILE:
					var i = (ty * CELLS_PER_TILE + cy) * w + tx * CELLS_PER_TILE + cx
					density[i] = 1.0
					mats_grid[i] = mats[ch]
			if ORE_ITEMS.has(ch):
				var at = Vector2(tx + 0.5, ty + 0.5) * CELLS_PER_TILE * GRID
				ores.append({"item": ORE_ITEMS[ch], "at": at})
			if ch == "x":
				ember_cells.append(Vector2i(tx, ty))

	soften(noise_seed)
	spread_materials()

	image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			image.set_pixel(x, y, cell_color(y * w + x))
	texture = ImageTexture.create_from_image(image)

	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2(GRID, GRID)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://terrain.gdshader")
	mat.set_shader_parameter("cells", Vector2(w, h))
	sprite.material = mat
	add_child(sprite)

	ore_marks = OreMarks.new()
	ore_marks.terrain = self
	add_child(ore_marks)

	body = StaticBody2D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	rebuild_collision()


# Rounds the corners and roughens the edges a little, so the cave walls
# read as rock rather than tiles. Only cells right at an edge change.
func soften(noise_seed: int):

	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.15
	var out = density.duplicate()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i = y * w + x
			var sum = 0.0
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					sum += density[i + oy * w + ox]
			var avg = sum / 9.0
			if avg > 0.0 and avg < 1.0:
				out[i] = clamp(avg + noise.get_noise_2d(x, y) * 0.22, 0.0, 1.0)
	density = out


# Open cells take the material of solid ground next to them, so the
# colours don't smear into bedrock grey at the edges of dug earth
func spread_materials():

	for pass_i in 2:
		var out = mats_grid.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var i = y * w + x
				if density[i] >= 0.5:
					continue
				for o in [-1, 1, -w, w]:
					if density[i + o] >= 0.5 and mats_grid[i + o] != BEDROCK:
						out[i] = mats_grid[i + o]
		mats_grid = out


# R: how solid; G, B, A: how much earth, rock, ember (the rest is bedrock).
# Separate channels so the linear filter blends materials cleanly.
func cell_color(i: int) -> Color:

	var m = mats_grid[i]
	return Color(density[i], 1.0 if m == EARTH else 0.0, 1.0 if m == ROCK else 0.0, 1.0 if m == EMBER else 0.0)


func solid_at(local: Vector2) -> bool:

	var x = int(local.x / GRID)
	var y = int(local.y / GRID)
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return density[y * w + x] >= 0.5


func material_at(local: Vector2) -> int:

	var x = clampi(int(local.x / GRID), 0, w - 1)
	var y = clampi(int(local.y / GRID), 0, h - 1)
	return mats_grid[y * w + x]


# Cuts a circle out of the ground with a pickaxe of this tier. Returns how
# many cells gave way, and -1 if the strike hit something too hard.
func dig(center: Vector2, radius: float, tier: int, quiet: bool = false) -> int:

	var x0 = maxi(int((center.x - radius) / GRID), 0)
	var x1 = mini(int((center.x + radius) / GRID) + 1, w - 1)
	var y0 = maxi(int((center.y - radius) / GRID), 0)
	var y1 = mini(int((center.y + radius) / GRID) + 1, h - 1)
	var cut = 0
	var blocked = false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i = y * w + x
			if density[i] <= 0.0:
				continue
			var d = Vector2(x + 0.5, y + 0.5).distance_to(center / GRID) * GRID
			if d > radius:
				continue
			var need = NEEDS[mats_grid[i]]
			if need == 0 or tier < need:
				if density[i] >= 0.5:
					blocked = true
				continue
			# Soft falloff at the rim keeps the hole's edge smooth
			var take = clamp((radius - d) / (GRID * 1.5), 0.0, 1.0)
			var before = density[i]
			density[i] = max(before - take, 0.0)
			if before >= 0.5 and density[i] < 0.5:
				cut += 1
			image.set_pixel(x, y, cell_color(i))
	if cut > 0:
		texture.update(image)
		rebuild_collision()
		release_ores(quiet)
	return -1 if cut == 0 and blocked else cut


# Ore drops once most of the ground around it is gone
func release_ores(quiet: bool):

	for ore in ores.duplicate():
		var open = 0
		var total = 0
		for oy in range(-2, 2):
			for ox in range(-2, 2):
				total += 1
				if not solid_at(ore["at"] + Vector2(ox + 0.5, oy + 0.5) * GRID):
					open += 1
		if open * 2 >= total:
			ores.erase(ore)
			ore_marks.queue_redraw()
			if not quiet:
				ore_uncovered.emit(ore["item"], ore["at"])


# Greedy rectangles over the solid cells: grow each run right, then down
# while the whole run stays solid
func rebuild_collision():

	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var used = PackedByteArray()
	used.resize(w * h)
	for y in h:
		var x = 0
		while x < w:
			var i = y * w + x
			if used[i] or density[i] < 0.5:
				x += 1
				continue
			var run = 1
			while x + run < w and not used[i + run] and density[i + run] >= 0.5:
				run += 1
			var depth = 1
			while y + depth < h and row_free(x, y + depth, run, used):
				depth += 1
			for yy in range(y, y + depth):
				for xx in range(x, x + run):
					used[yy * w + xx] = 1
			var shape = RectangleShape2D.new()
			shape.size = Vector2(run, depth) * GRID
			var col = CollisionShape2D.new()
			col.shape = shape
			col.position = Vector2(x + run / 2.0, y + depth / 2.0) * GRID
			body.add_child(col)
			x += run


func row_free(x: int, y: int, run: int, used: PackedByteArray) -> bool:

	for xx in range(x, x + run):
		var i = y * w + xx
		if used[i] or density[i] < 0.5:
			return false
	return true


# Glints of ore showing through the earth, so you know where to dig
class OreMarks:
	extends Node2D

	const COLORS = {"Copper Ore": Color(0.35, 0.9, 0.6), "Tin Ore": Color(0.7, 0.68, 0.85), "Flint": Color(0.85, 0.87, 0.9)}

	var terrain: Node2D

	func _draw():
		for ore in terrain.ores:
			var c: Color = COLORS.get(ore["item"], Color.WHITE)
			var at: Vector2 = ore["at"]
			for k in 3:
				var o = Vector2(sin(at.x * 0.37 + k * 2.1), cos(at.y * 0.29 + k * 1.7)) * 9.0
				var pts = PackedVector2Array([at + o + Vector2(0, -6), at + o + Vector2(5, 0), at + o + Vector2(0, 6), at + o + Vector2(-5, 0)])
				draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.85))
