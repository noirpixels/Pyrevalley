class_name InkDraw

# Brush-and-pen drawing for things made in code (ledges, the shrine,
# pickups), so they match the inked creatures instead of looking like flat
# shapes: strokes that taper at the ends and swell along their length, and
# a soft round glow with no visible rings.

const INK = Color(0.045, 0.035, 0.05)

static var glow_texture: Texture2D


# A tapered stroke through pts. width is the widest point; seed varies the
# swell so neighbouring strokes don't match.
static func stroke(ci: CanvasItem, pts: PackedVector2Array, width: float, color: Color = INK, seed: float = 0.0):

	var n = pts.size()
	if n < 2:
		return
	var left = PackedVector2Array()
	var right = PackedVector2Array()
	for i in n:
		var t = float(i) / float(n - 1)
		var a = pts[max(i - 1, 0)]
		var b = pts[min(i + 1, n - 1)]
		var normal = (b - a).normalized().orthogonal()
		var taper = sin(t * PI) * 0.75 + 0.25
		var swell = 0.8 + 0.2 * sin(t * 5.0 + seed * 3.7)
		var half = width * 0.5 * taper * swell
		left.append(pts[i] + normal * half)
		right.append(pts[i] - normal * half)
	right.reverse()
	left.append_array(right)
	fill(ci, left, color)


# A filled shape with a soft 1 px border, since the 2D renderer used for the
# web build can't antialias polygons
static func fill(ci: CanvasItem, pts: PackedVector2Array, color: Color):

	ci.draw_colored_polygon(pts, color)
	var ring = pts.duplicate()
	ring.append(pts[0])
	ci.draw_polyline(ring, color, 1.0, true)


# A straight stroke from a to b, bowed slightly so it looks hand-drawn
static func line(ci: CanvasItem, a: Vector2, b: Vector2, width: float, color: Color = INK, seed: float = 0.0):

	var bow = (b - a).orthogonal().normalized() * (a.distance_to(b) * 0.03 * sin(seed * 12.9))
	var pts = PackedVector2Array()
	for i in 6:
		var t = i / 5.0
		pts.append(a.lerp(b, t) + bow * sin(t * PI))
	stroke(ci, pts, width, color, seed)


# The outline of a closed shape as a few overlapping strokes rather than
# one even line
static func outline(ci: CanvasItem, pts: PackedVector2Array, width: float, color: Color = INK, seed: float = 0.0):

	var n = pts.size()
	for i in n:
		var a = pts[i]
		var b = pts[(i + 1) % n]
		var over = (b - a).normalized() * width * 0.6
		line(ci, a - over, b + over, width, color, seed + i)


# A smooth radial glow, centred on at
static func glow(ci: CanvasItem, at: Vector2, radius: float, color: Color):

	if glow_texture == null:
		var g = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.35))
		var tex = GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		glow_texture = tex
	ci.draw_texture_rect(glow_texture, Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)
