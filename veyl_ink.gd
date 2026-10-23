class_name VeylInk
extends RefCounted

# Veyl drawn in ink, side-on (facing right), as parts for veyl_puppet.gd's
# rig: the same pivots and posing as the cut-out art, but each part is
# brushwork rather than pixels. Coordinates are in the old 104 x 216 figure
# (feet on the bottom edge), so the rig's pivots still line up.
#
# What makes Veyl Veyl stays: the round shadow head, the ember eyes and the
# orange scarf. The head gets a pale rim on the lit side so it reads against
# dark rock, and the scarf's tail streams out behind when vae moves.

const W = 104
const H = 216
const NECK = Vector2(52, 96)
const HIP = Vector2(52, 164)
const SHOULDER = Vector2(46, 118)
const HAND = Vector2(42, 154)

const SHADOW = Color(0.1, 0.085, 0.13)
const RIM = Color(0.5, 0.47, 0.58)
const CLOTH = Color(0.22, 0.24, 0.34)
const CLOTH_LIT = Color(0.33, 0.35, 0.47)
const TROUSERS = Color(0.46, 0.39, 0.32)
const BOOT = Color(0.2, 0.14, 0.11)
const BELT = Color(0.34, 0.22, 0.13)
const EMBER = Color(1.0, 0.55, 0.15)
const EMBER_HOT = Color(1.0, 0.9, 0.6)
const SCARF = Color(0.95, 0.42, 0.1)


# Points around an ellipse, from angle a0 to a1 (radians)
static func arc(c: Vector2, r: Vector2, a0: float, a1: float, n: int) -> PackedVector2Array:

	var pts = PackedVector2Array()
	for i in n + 1:
		var a = lerp(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


# The shadow head, drawn around the neck pivot
class Head:
	extends Node2D

	var time: float = 0.0
	var blink: float = 0.0
	var next_blink: float = 2.5

	func _process(delta):
		time += delta
		next_blink -= delta
		if next_blink <= 0.0:
			blink = 0.14
			next_blink = randf_range(2.5, 5.0)
		blink = max(blink - delta, 0.0)
		queue_redraw()

	func _draw():
		var c = Vector2(4, -46)
		var r = 42.0
		# Wisps of shadow trailing off the back of the head
		for i in 3:
			var a = -2.05 - i * 0.42
			var base = c + Vector2(cos(a), sin(a)) * r * 0.8
			var out = Vector2(cos(a - 0.5), sin(a - 0.5) * 0.6).normalized()
			var reach = 30.0 - i * 5.0
			var pts = PackedVector2Array()
			for k in 8:
				var t = k / 7.0
				var sway = sin(time * 2.2 + i * 1.7 + t * 3.0) * 5.0 * t
				pts.append(base + out * reach * t + Vector2(0, t * t * 8.0 + sway))
			InkDraw.stroke(self, pts, 13.0 - i * 2.5, InkDraw.INK, i)
			InkDraw.stroke(self, pts, 8.0 - i * 1.5, SHADOW, i)
		# The pale rim on the lit side, then the head over it
		InkDraw.fill(self, VeylInk.arc(c, Vector2(r, r), 0.0, TAU, 40), RIM)
		InkDraw.fill(self, VeylInk.arc(c + Vector2(3.5, 4.0), Vector2(r - 2.0, r - 2.5), 0.0, TAU, 40), SHADOW)
		# Brush outline in two strokes, thicker on the shadow side
		InkDraw.stroke(self, VeylInk.arc(c, Vector2(r + 1.0, r + 1.0), -PI * 0.35, PI * 0.75, 24), 4.5, InkDraw.INK, 1.0)
		InkDraw.stroke(self, VeylInk.arc(c, Vector2(r + 1.0, r + 1.0), PI * 0.65, PI * 1.75, 24), 3.0, InkDraw.INK, 2.0)
		# The ember eye: a glow, an almond of fire and a hot core
		var eye = c + Vector2(22, 2)
		var open = 1.0 - sin(clamp(blink / 0.14, 0.0, 1.0) * PI) * 0.9
		InkDraw.glow(self, eye, 20.0, Color(EMBER, 0.45 + 0.1 * sin(time * 3.0)))
		var almond = PackedVector2Array()
		for k in 14:
			var a = TAU * k / 14.0
			almond.append(eye + Vector2(cos(a) * 5.5, sin(a) * 10.0 * open - 1.0))
		InkDraw.fill(self, almond, EMBER)
		if open > 0.4:
			InkDraw.fill(self, VeylInk.arc(eye + Vector2(0.5, -2.0), Vector2(2.2, 4.5 * open), 0.0, TAU, 10), EMBER_HOT)


# Tunic and belt, drawn around the hip pivot
class Torso:
	extends Node2D

	func _draw():
		var top = VeylInk.NECK - VeylInk.HIP
		var tunic = PackedVector2Array([top + Vector2(-15, 2), top + Vector2(15, 2), Vector2(19, -30), Vector2(22, -2), Vector2(4, 1), Vector2(-14, -2), Vector2(-21, -30)])
		InkDraw.fill(self, tunic, VeylInk.CLOTH)
		# Lit panel on the sun side, and a fold
		InkDraw.fill(self, PackedVector2Array([top + Vector2(-15, 2), top + Vector2(-6, 2), Vector2(-12, -30), Vector2(-15, -3), Vector2(-21, -30)]), VeylInk.CLOTH_LIT)
		InkDraw.line(self, Vector2(6, -8), Vector2(11, -2), 1.6, InkDraw.INK, 3.0)
		# Belt with a buckle
		InkDraw.fill(self, PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(21, -12), Vector2(-20, -12)]), VeylInk.BELT)
		InkDraw.fill(self, VeylInk.arc(Vector2(10, -16), Vector2(4, 4), 0.0, TAU, 10), Color(0.75, 0.6, 0.35))
		InkDraw.outline(self, tunic, 3.2, InkDraw.INK, 4.0)
		InkDraw.line(self, Vector2(-20, -20), Vector2(20, -20), 2.0, InkDraw.INK, 5.0)
		InkDraw.line(self, Vector2(-20, -12), Vector2(21, -12), 2.0, InkDraw.INK, 6.0)


# The sword arm, hanging down from the shoulder pivot at rest
class Arm:
	extends Node2D

	func _draw():
		var hand = VeylInk.HAND - VeylInk.SHOULDER
		InkDraw.line(self, Vector2(0, -3), hand * 0.85, 17.0, InkDraw.INK, 1.0)
		InkDraw.line(self, Vector2(0, -2), hand * 0.82, 12.0, VeylInk.CLOTH_LIT, 1.0)
		InkDraw.fill(self, VeylInk.arc(hand, Vector2(8.5, 8.5), 0.0, TAU, 14), InkDraw.INK)
		InkDraw.fill(self, VeylInk.arc(hand + Vector2(-0.5, -0.5), Vector2(6.0, 6.0), 0.0, TAU, 14), VeylInk.BOOT)


# A leg from the hip pivot, foot forward (to the right)
class Leg:
	extends Node2D

	func _draw():
		var foot = Vector2(0, 216 - VeylInk.HIP.y)
		InkDraw.line(self, Vector2(0, -4), foot + Vector2(0, -10), 17.0, InkDraw.INK, 2.0)
		InkDraw.line(self, Vector2(0, -3), foot + Vector2(0, -11), 12.0, VeylInk.TROUSERS, 2.0)
		var boot = PackedVector2Array([foot + Vector2(-8, -16), foot + Vector2(6, -16), foot + Vector2(15, -6), foot + Vector2(16, 0), foot + Vector2(-9, 0)])
		InkDraw.fill(self, boot, VeylInk.BOOT)
		InkDraw.outline(self, boot, 2.8, InkDraw.INK, 3.0)


# The scarf: a wrap at the neck and a tail that trails out behind. It sits
# on the body, and is told how Veyl is moving (in the puppet's own space,
# where Veyl always faces right).
class Scarf:
	extends Node2D

	const SEGMENTS = 9
	const LENGTH = 8.0

	var motion: Vector2 = Vector2.ZERO
	var points = []
	var time: float = 0.0

	func _ready():
		for i in SEGMENTS:
			points.append(Vector2(-4 - i * LENGTH * 0.4, 4 + i * LENGTH * 0.9))

	func _process(delta):
		time += delta
		# Still air: the tail hangs down behind. Moving: it streams out away
		# from the way Veyl is going, rising when vae falls
		var speed = clamp(motion.length() / 300.0, 0.0, 1.0)
		var away = Vector2(-1.0, 0.0) if motion.length() < 1.0 else -motion.normalized()
		var hang = Vector2(-0.35, 1.0).normalized()
		var dir = hang.lerp(away, speed).normalized()
		var anchor = Vector2(-8, 2)
		var prev = anchor
		for i in SEGMENTS:
			var t = float(i + 1) / SEGMENTS
			var flutter = dir.orthogonal() * sin(time * (6.0 + speed * 8.0) - i * 0.9) * (1.0 + speed * 3.0) * t
			var want = prev + (dir * LENGTH + flutter)
			points[i] = points[i].lerp(want, 1.0 - exp(-delta * (14.0 - i * 0.8)))
			points[i] = prev + (points[i] - prev).limit_length(LENGTH * 1.1)
			prev = points[i]
		queue_redraw()

	func _draw():
		var tail = PackedVector2Array([Vector2(-6, 2)])
		tail.append_array(PackedVector2Array(points))
		InkDraw.stroke(self, tail, 15.0, InkDraw.INK, 7.0)
		InkDraw.stroke(self, tail, 10.0, VeylInk.SCARF, 7.0)
		# The wrap, over the tail's root
		var wrap = PackedVector2Array([Vector2(-17, -6), Vector2(16, -7), Vector2(18, 3), Vector2(4, 8), Vector2(-16, 5)])
		InkDraw.fill(self, wrap, VeylInk.SCARF)
		InkDraw.line(self, Vector2(-14, 0), Vector2(14, -2), 1.8, Color(0.6, 0.2, 0.05), 8.0)
		InkDraw.outline(self, wrap, 3.0, InkDraw.INK, 9.0)
