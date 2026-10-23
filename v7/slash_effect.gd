extends Node2D

# The glowing arc of a swing: a crescent that sweeps through the move's
# angle with a bright leading edge, then fades. Drawn on Veyl, so it moves
# with vem.

const SWEEP_TIME = 0.09
const FADE_TIME = 0.14
const SEGMENTS = 18
# Start and end angles per move, degrees, 0 = straight ahead, negative up
const ARCS = {
	"strike": [-70.0, 35.0],
	"heavy": [-95.0, 45.0],
	"launch": [55.0, -110.0],
	"slam": [-100.0, 55.0],
	"aerial": [-120.0, 100.0],
}

var kind: String
var radius: float
var facing: float
var time: float = 0.0
var color = Color(1.0, 0.62, 0.25)


func _init(move_name: String, reach: float, face: float):

	kind = move_name
	radius = reach * 0.95
	facing = face
	position = Vector2(0, -52)
	z_index = 5
	if move_name in ["slam", "aerial"]:
		color = Color(1.0, 0.82, 0.35)


func _process(delta):

	time += delta
	if time > SWEEP_TIME + FADE_TIME:
		queue_free()
		return
	queue_redraw()


func _draw():

	var arc: Array = ARCS.get(kind, ARCS["strike"])
	var sweep = clamp(time / SWEEP_TIME, 0.0, 1.0)
	var fade = 1.0 - clamp((time - SWEEP_TIME) / FADE_TIME, 0.0, 1.0)
	var a0 = deg_to_rad(arc[0])
	var a1 = lerp(a0, deg_to_rad(arc[1]), sweep)
	if abs(a1 - a0) < 0.08:
		return
	var outer = []
	var inner = []
	var colors = []
	for i in SEGMENTS + 1:
		var t = float(i) / SEGMENTS
		var a = lerp(a0, a1, t)
		var dir = Vector2(cos(a) * facing, sin(a))
		# The crescent thickens toward the leading edge
		var thick = lerp(0.12, 0.42, t)
		outer.append(dir * radius)
		inner.append(dir * radius * (1.0 - thick))
		var c = color
		c.a = t * 0.85 * fade
		colors.append(c)
	var points = PackedVector2Array()
	var cols = PackedColorArray()
	for i in outer.size():
		points.append(outer[i])
		cols.append(colors[i])
	for i in range(inner.size() - 1, -1, -1):
		points.append(inner[i])
		var c = colors[i]
		c.a *= 0.3
		cols.append(c)
	if points.size() >= 3:
		draw_polygon(points, cols)
	# A bright line along the blade's edge
	if sweep < 1.0 or fade > 0.5:
		var tip = Vector2(cos(a1) * facing, sin(a1))
		draw_line(tip * radius * 0.55, tip * radius * 1.02, Color(1.0, 0.95, 0.85, fade), 4.0)
