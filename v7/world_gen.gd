extends RefCounted

# Builds a world from a seed: lays out a grid of rooms, picks a template for
# each (rooms.gd), and checks every room can actually be crossed, so each
# seed can be finished.
#
# The layout, left to right:
#   start shrine -> rooms -> GATE (a wall only the Cinderwing clears)
#   -> second shrine -> one more room -> the Ashbound's arena
# with side branches hanging off the rooms before the gate:
#   - the Cinderwing's chamber (so it's always found before the gate)
#   - a dig room full of copper, tin and flint (for the bronze pickaxe)
#   - a treasure room sealed with rock (needs the bronze pickaxe)
#   - an extra room or two to explore
# Grid y grows downward; row 0 is the forest floor, under open sky.
#
# generate(seed) -> {"rooms": [room...], "by_cell": {Vector2i: index}, "seed"}
#   room: {"index", "cell" (top-left), "cells", "template", "mirrored",
#          "doors" (String of L R U D), "role", "rows" (final tiles)}

const Rooms = preload("res://rooms.gd")

# Main path cells before the arena; the gate sits at GATE_AT
const MAIN_LENGTH = 8
const GATE_AT = 5
const MAX_DEPTH = 3
# Jump reach in tiles for the room check: a plain jump, and with the Cinderwing
const JUMP_TILES = 3
const DOUBLE_JUMP_TILES = 6
const FILLERS = ["glade", "hollow", "shaft", "ledges", "bridge"]
const DIGS = ["dig_mound", "dig_seam"]
const DIRS = {"L": Vector2i(-1, 0), "R": Vector2i(1, 0), "U": Vector2i(0, -1), "D": Vector2i(0, 1)}
const OPPOSITE = {"L": "R", "R": "L", "U": "D", "D": "U"}

static var _passable = {}


static func generate(world_seed: int) -> Dictionary:

	var rng = RandomNumberGenerator.new()
	rng.seed = world_seed
	for attempt in 200:
		var world = try_generate(rng)
		if not world.is_empty():
			world["seed"] = world_seed
			return world
	push_error("world_gen: no valid world for seed %d" % world_seed)
	return {}


static func try_generate(rng: RandomNumberGenerator) -> Dictionary:

	var plan = []          # [{"cells": [...], "role"}]
	var taken = {}         # Vector2i -> plan index
	var links = []         # [[a, b, dir from a]]

	# ---- Main path ----
	var cell = Vector2i(0, 0)
	add_room(plan, taken, [cell], "start")
	for i in range(1, MAIN_LENGTH + 1):
		var forced_right = i == GATE_AT + 1 or i == MAIN_LENGTH
		var dir = pick_step(rng, cell, taken, forced_right)
		if dir == "":
			return {}
		var next = cell + DIRS[dir]
		var role = "filler"
		var cells = [next]
		if i == GATE_AT:
			role = "gate"
		elif i == GATE_AT + 1:
			role = "shrine"
		elif i == MAIN_LENGTH:
			role = "boss"
			cells = [next, next + Vector2i(1, 0)]
			if taken.has(cells[1]):
				return {}
		add_room(plan, taken, cells, role)
		links.append([plan.size() - 2, plan.size() - 1, dir])
		cell = cells[-1]
	# One of the early rooms is always a dig room
	plan[rng.randi_range(1, GATE_AT - 1)]["role"] = "dig"

	# The gate leaves by its right-hand door, so the room before it must
	# come in from the left or above/below, never through that same door
	var gate_in = links[GATE_AT - 1][2]
	if gate_in == "L":
		return {}

	# ---- Branches off the rooms before the gate ----
	if not add_branch(rng, plan, taken, links, ["filler", "ability"], 1, GATE_AT - 1):
		return {}
	if not add_branch(rng, plan, taken, links, ["dig"], 0, GATE_AT - 1):
		return {}
	if not add_branch(rng, plan, taken, links, ["treasure"], 0, GATE_AT - 1, true):
		return {}
	if rng.randf() < 0.7:
		add_branch(rng, plan, taken, links, ["filler"], 0, GATE_AT - 1)

	# ---- Doors and templates ----
	var doors = []
	for r in plan:
		doors.append("")
	for link in links:
		doors[link[0]] += link[2]
		doors[link[1]] += OPPOSITE[link[2]]

	var rooms = []
	var by_cell = {}
	for i in plan.size():
		var room = choose_template(rng, plan[i]["role"], doors[i])
		if room.is_empty():
			return {}
		room["index"] = i
		room["cells"] = plan[i]["cells"]
		room["cell"] = plan[i]["cells"][0]
		room["role"] = plan[i]["role"]
		room["doors"] = doors[i]
		room["rows"] = finish_rows(room["rows"], doors[i], room["cell"].y == 0)
		rooms.append(room)
		for c in room["cells"]:
			by_cell[c] = i
	return {"rooms": rooms, "by_cell": by_cell}


static func add_room(plan: Array, taken: Dictionary, cells: Array, role: String):

	plan.append({"cells": cells, "role": role})
	for c in cells:
		taken[c] = plan.size() - 1


# Mostly onward to the right, sometimes down into the earth or back up
static func pick_step(rng: RandomNumberGenerator, from: Vector2i, taken: Dictionary, forced_right: bool) -> String:

	var options = {"R": 5.0} if forced_right else {"R": 5.0, "D": 2.5, "U": 1.5}
	var total = 0.0
	var valid = {}
	for dir in options:
		var next = from + DIRS[dir]
		if taken.has(next) or next.y < 0 or next.y > MAX_DEPTH:
			continue
		valid[dir] = options[dir]
		total += options[dir]
	var roll = rng.randf() * total
	for dir in valid:
		roll -= valid[dir]
		if roll <= 0.0:
			return dir
	return ""


# A chain of rooms with these roles hung off one of the main path rooms
# from..to (never the gate, so its doors stay simple). sideways: the
# first room must join on its left or right (the treasure's door).
static func add_branch(rng: RandomNumberGenerator, plan: Array, taken: Dictionary, links: Array, roles: Array, from: int, to: int, sideways: bool = false) -> bool:

	var parents = range(from, to + 1)
	shuffle(rng, parents)
	for parent in parents:
		var cell: Vector2i = plan[parent]["cells"][0]
		var dirs = ["L", "R"] if sideways else ["L", "R", "U", "D"]
		shuffle(rng, dirs)
		for dir in dirs:
			var chain = [cell + DIRS[dir]]
			var ok = free_cell(taken, chain[0])
			for k in range(1, roles.size()):
				if not ok:
					break
				ok = false
				var step_dirs = ["L", "R", "D"]
				shuffle(rng, step_dirs)
				for d in step_dirs:
					var next = chain[-1] + DIRS[d]
					if free_cell(taken, next) and not next in chain:
						chain.append(next)
						ok = true
						break
			if not ok:
				continue
			var prev = parent
			for k in roles.size():
				add_room(plan, taken, [chain[k]], roles[k])
				var d = dir_between(plan[prev]["cells"], chain[k])
				links.append([prev, plan.size() - 1, d])
				prev = plan.size() - 1
			return true
	return false


static func free_cell(taken: Dictionary, c: Vector2i) -> bool:
	return not taken.has(c) and c.y >= 0 and c.y <= MAX_DEPTH


# Direction from a room (its cells) to a neighbouring cell
static func dir_between(cells: Array, to: Vector2i) -> String:

	for c in cells:
		for dir in DIRS:
			if c + DIRS[dir] == to:
				return dir
	return ""


static func shuffle(rng: RandomNumberGenerator, arr: Array):

	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


static func pool_for(role: String) -> Array:

	match role:
		"filler":
			return FILLERS
		"dig":
			return DIGS
		"start":
			return ["start"]
		"shrine":
			return ["shrine"]
		"ability":
			return ["ability"]
		"gate":
			return ["gate"]
		"treasure":
			return ["treasure"]
		"boss":
			return ["arena"]
	return FILLERS


static func choose_template(rng: RandomNumberGenerator, role: String, doors: String) -> Dictionary:

	var options = []
	for name in pool_for(role):
		for mirrored in [false, true]:
			if mirrored and role == "boss":
				continue
			var supported = Rooms.doors_of(name, mirrored)
			var fits = true
			for d in doors:
				if not d in supported:
					fits = false
			if fits:
				options.append([name, mirrored])
	shuffle(rng, options)
	for option in options:
		var rows = Rooms.rows_of(option[0], option[1])
		# Same template, doors and role always give the same answer
		var key = "%s/%s/%s/%s" % [option[0], option[1], doors, role]
		if not _passable.has(key):
			_passable[key] = room_passable(rows, doors, role)
		if _passable[key]:
			return {"template": option[0], "mirrored": option[1], "rows": rows}
	return {}


# Walls up the doors this room doesn't use. Forest-floor rooms lose their
# ceiling to open sky.
static func finish_rows(rows: Array, doors: String, surface: bool) -> Array:

	var out = []
	for row in rows:
		out.append(row)
	var last = out[0].length() - 1
	if not "L" in doors:
		for y in range(12, 16):
			out[y] = set_char(out[y], 0, "#")
	if not "R" in doors:
		for y in range(12, 16):
			out[y] = set_char(out[y], last, "#")
	if not "U" in doors:
		for x in range(12, 20):
			out[0] = set_char(out[0], x, "#")
	if not "D" in doors:
		for x in range(14, 18):
			out[16] = set_char(out[16], x, "#")
			out[17] = set_char(out[17], x, "#")
	if surface:
		for y in 2:
			var row = ""
			for x in out[y].length():
				var edge = x == 0 or x == last
				row += out[y][x] if edge or out[y][x] != "#" else "."
			out[y] = row
	return out


static func set_char(s: String, i: int, c: String) -> String:
	return s.substr(0, i) + c + s.substr(i + 1)


# ============================================================
# CAN THE ROOM BE CROSSED?
# ============================================================

static func is_solid(c: String) -> bool:
	return c in "#ERctfx"


static func room_passable(rows: Array, doors: String, role: String) -> bool:

	var sealed = finish_rows(rows, doors, false)
	match role:
		"treasure":
			# Past the rock (as if broken), the Ember Heart can be reached
			var open_rows = []
			for row in sealed:
				open_rows.append(row.replace("R", "."))
			return reaches(open_rows, door_entry(open_rows, doors[0]), find_char(open_rows, "H"), JUMP_TILES)
		"gate":
			# Left to right needs the Cinderwing, and plainly can't be done
			var in_l = door_entry(sealed, "L")
			var out_r = door_exit(sealed, "R")
			if reaches(sealed, in_l, out_r, JUMP_TILES):
				return false
			return all_doors_connected(sealed, doors, DOUBLE_JUMP_TILES)
		"ability":
			if not reaches(sealed, door_entry(sealed, doors[0]), find_char(sealed, "X"), JUMP_TILES):
				return false
	return all_doors_connected(sealed, doors, JUMP_TILES)


static func all_doors_connected(rows: Array, doors: String, jump: int) -> bool:

	for a in doors:
		for b in doors:
			if a != b and not reaches(rows, door_entry(rows, a), door_exit(rows, b), jump):
				return false
	return true


static func find_char(rows: Array, c: String) -> Array:

	for y in rows.size():
		var x = rows[y].find(c)
		if x >= 0:
			return [Vector2i(x, y)]
	return []


# Where Veyl stands on coming in through a door
static func door_entry(rows: Array, door: String) -> Array:

	var last = rows[0].length() - 1
	match door:
		"L":
			return [Vector2i(0, 15)]
		"R":
			return [Vector2i(last, 15)]
		"D":
			return [Vector2i(15, 15)]
		"U":
			# Dropped in from above: falls down the doorway to the first footing
			for y in range(0, rows.size()):
				if can_stand(rows, 15, y):
					return [Vector2i(15, y)]
	return []


# Anywhere Veyl can stand and leave by a door
static func door_exit(rows: Array, door: String) -> Array:

	var last = rows[0].length() - 1
	match door:
		"L":
			return [Vector2i(0, 15)]
		"R":
			return [Vector2i(last, 15)]
		"D":
			return [Vector2i(15, 15), Vector2i(14, 15), Vector2i(16, 15), Vector2i(17, 15)]
		"U":
			# A plain jump from the ledge right under the doorway clears it
			var out = []
			for x in range(14, 18):
				out.append(Vector2i(x, 0))
			return out
	return []


static func tile(rows: Array, x: int, y: int) -> String:

	if y < 0:
		return "."
	if x < 0 or y >= rows.size() or x >= rows[0].length():
		return "#"
	return rows[y][x]


static func is_open(rows: Array, x: int, y: int) -> bool:
	return not is_solid(tile(rows, x, y))


# Veyl is three tiles tall and stands on rock, earth or a ledge
static func can_stand(rows: Array, x: int, y: int) -> bool:

	if not (is_open(rows, x, y) and is_open(rows, x, y - 1) and is_open(rows, x, y - 2)):
		return false
	var below = tile(rows, x, y + 1)
	return (is_solid(below) and below != "x") or below == "="


static func reaches(rows: Array, from: Array, targets: Array, jump: int) -> bool:

	if from.is_empty() or targets.is_empty():
		return false
	var goal = {}
	for t in targets:
		goal[t] = true
	var seen = {}
	var queue = []
	for f in from:
		if can_stand(rows, f.x, f.y):
			seen[f] = true
			queue.append(f)
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if goal.has(at):
			return true
		for next in moves(rows, at, jump):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return false


# Every footing reachable in one hop: a jump up to `jump` tiles and across
# a few, or a fall (wider the further it drops), with the arc kept clear;
# and dropping through a ledge
static func moves(rows: Array, at: Vector2i, jump: int) -> Array:

	var out = []
	var w = rows[0].length()
	for x in range(max(at.x - 7, 0), min(at.x + 8, w)):
		for y in range(max(at.y - jump, 0), min(at.y + 12, rows.size())):
			if Vector2i(x, y) == at or not can_stand(rows, x, y):
				continue
			var dx = abs(x - at.x)
			var drop = y - at.y
			var reach = 4 if drop <= 0 else 4 + drop / 2
			if jump > JUMP_TILES:
				reach += 2
			if dx > reach:
				continue
			if arc_clear(rows, at, Vector2i(x, y)):
				out.append(Vector2i(x, y))
	# Down + Jump through a ledge
	if tile(rows, at.x, at.y + 1) == "=":
		for y in range(at.y + 2, rows.size()):
			if can_stand(rows, at.x, y):
				out.append(Vector2i(at.x, y))
				break
			if not is_open(rows, at.x, y):
				break
	return out


# The hop's path: up the start column to the peak, across, and down the
# far column, with room for Veyl's height all the way (ledges don't block
# rising, and Veyl lands on them)
static func arc_clear(rows: Array, a: Vector2i, b: Vector2i) -> bool:

	# A jump up peaks at the footing it lands on; a jump across a gap a
	# tile above; a step or a fall just goes over the edge
	var peak = a.y
	if b.y < a.y:
		peak = b.y
	elif b.y == a.y and abs(b.x - a.x) > 1:
		peak = a.y - 1
	for y in range(peak, a.y + 1):
		if not body_clear(rows, a.x, y):
			return false
	var step = 1 if b.x > a.x else -1
	var x = a.x
	while x != b.x:
		x += step
		if not body_clear(rows, x, peak):
			return false
	for y in range(peak, b.y + 1):
		if not body_clear(rows, b.x, y):
			return false
	return true


static func body_clear(rows: Array, x: int, feet: int) -> bool:

	for k in 3:
		if not is_open(rows, x, feet - k):
			return false
	return true
