extends Control

# The map, drawn the way Veyl would: rooms walked through are sketched in
# pencil, and set in ink the next time vae rests at a shrine. Doorways show
# as gaps. The ember marks where Veyl is; flames mark shrines.

const CELL = Vector2(96, 54)

var ink = Color(0.12, 0.08, 0.06)
var paper = Color(0.86, 0.79, 0.66)


func _init():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw():

	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var view = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.03, 0.02, 0.03, 0.75))
	var page = Rect2(view * 0.08, view * 0.84)
	draw_rect(page, paper)
	draw_rect(page, ink, false, 4.0)
	var font = Style.display_bold
	draw_string(font, page.position + Vector2(28, 50), "THE HOLLOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
	draw_string(Style.body_font, page.position + Vector2(28, page.size.y - 24), "Pencil: walked.  Ink: set at a shrine.   World %d   ·   M to close" % GameState.seed_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)

	var here: Vector2i = game.current_room.cell if game.current_room else Vector2i.ZERO
	var player_cell = Vector2i(floor(game.player.global_position.x / 1280.0), floor((game.player.global_position.y - 40.0) / 720.0))
	var center = page.get_center() + Vector2(0, 10)

	for room in game.rooms:
		var cells: Array = room.data["cells"]
		var keys = cells.map(func(c): return GameState.cell_key(c))
		var seen = keys.any(func(k): return GameState.visited.has(k))
		if not seen:
			continue
		var inked = keys.any(func(k): return GameState.inked.has(k))
		var tl = center + (Vector2(cells[0] - player_cell)) * CELL - CELL / 2.0
		var size = Vector2(cells.size(), 1) * CELL
		var r = Rect2(tl + Vector2(6, 6), size - Vector2(12, 12))
		var col = ink if inked else Color(ink.r, ink.g, ink.b, 0.45)
		draw_rect(r, Color(0.0, 0.0, 0.0, 0.06 if inked else 0.0))
		draw_room_outline(r, room.data["doors"], col, 3.0 if inked else 1.6, not inked)
		match room.data["role"]:
			"start", "shrine":
				draw_flame(r.get_center(), col)
			"boss":
				draw_string(font, r.get_center() + Vector2(-12, 10), "✕", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.6, 0.1, 0.05))

	# Veyl
	var at = center + (game.player.global_position - Vector2(player_cell) * Vector2(1280, 720)) / Vector2(1280, 720) * CELL - CELL / 2.0
	draw_circle(at, 7.0, Color(0.95, 0.4, 0.1))
	draw_arc(at, 11.0, 0.0, TAU, 20, ink, 2.0)


# The room's outline, broken where its doors are
func draw_room_outline(r: Rect2, doors: String, col: Color, width: float, pencil: bool):

	var gap = 12.0
	var mid_y = r.position.y + r.size.y * 0.72
	var mid_x = r.get_center().x
	var segments = []
	# Top, with the U door in the middle
	if "U" in doors:
		segments.append([r.position, Vector2(mid_x - gap, r.position.y)])
		segments.append([Vector2(mid_x + gap, r.position.y), Vector2(r.end.x, r.position.y)])
	else:
		segments.append([r.position, Vector2(r.end.x, r.position.y)])
	if "D" in doors:
		segments.append([Vector2(r.position.x, r.end.y), Vector2(mid_x - gap, r.end.y)])
		segments.append([Vector2(mid_x + gap, r.end.y), r.end])
	else:
		segments.append([Vector2(r.position.x, r.end.y), r.end])
	if "L" in doors:
		segments.append([r.position, Vector2(r.position.x, mid_y - gap)])
		segments.append([Vector2(r.position.x, mid_y + gap), Vector2(r.position.x, r.end.y)])
	else:
		segments.append([r.position, Vector2(r.position.x, r.end.y)])
	if "R" in doors:
		segments.append([Vector2(r.end.x, r.position.y), Vector2(r.end.x, mid_y - gap)])
		segments.append([Vector2(r.end.x, mid_y + gap), r.end])
	else:
		segments.append([Vector2(r.end.x, r.position.y), r.end])
	for s in segments:
		if pencil:
			draw_dashed_line(s[0], s[1], col, width, 6.0)
		else:
			draw_line(s[0], s[1], col, width)


func draw_flame(at: Vector2, col: Color):

	var pts = PackedVector2Array([at + Vector2(-7, 6), at + Vector2(7, 6), at + Vector2(0, -12)])
	draw_colored_polygon(pts, Color(0.9, 0.4, 0.1))
	pts.append(pts[0])
	draw_polyline(pts, col, 1.5)
