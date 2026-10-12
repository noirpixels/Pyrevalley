extends MeshInstance3D

# Glowing arc drawn on the ground for Veyl's sword swing. Swings sweep
# across the arc with a bright leading edge and a fading trail; slams burst
# out as a ring.

const SEGMENTS = 24
# Seconds for the blade to cross the arc, then for the trail to fade
const SWEEP_TIME = 0.1
const FADE_TIME = 0.16
const RING_TIME = 0.22

var radius: float = 6.0
var arc_degrees: float = 120.0
var color: Color = Color(1.0, 0.55, 0.15, 0.6)
# "sweep" (1 runs -X to +X locally, -1 the other way), "fan" (opens from the
# middle out to both sides) or "ring"
var style: String = "sweep"
var sweep_dir: float = 1.0

var time: float = 0.0
var immediate: ImmediateMesh
var verts: Array = []


func _ready():

	immediate = ImmediateMesh.new()
	mesh = immediate

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	draw()


func _process(delta):

	time += delta
	var life = RING_TIME if style == "ring" else SWEEP_TIME + FADE_TIME
	if time >= life:
		queue_free()
		return
	draw()


func draw():

	verts.clear()
	if style == "ring":
		draw_ring()
	else:
		draw_arc()

	immediate.clear_surfaces()
	# The sweep has nothing to show on its very first frame
	if verts.is_empty():
		return
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		immediate.surface_set_color(v[1])
		immediate.surface_add_vertex(v[0])
	immediate.surface_end()


func draw_arc():

	var half = deg_to_rad(arc_degrees) / 2.0
	# 0..1 position of the blade across the arc
	var lead = ease(clamp(time / SWEEP_TIME, 0.0, 1.0), 0.4)
	var fade = 1.0 - clamp((time - SWEEP_TIME) / FADE_TIME, 0.0, 1.0)

	for i in SEGMENTS:
		var u0 = float(i) / SEGMENTS
		var u1 = float(i + 1) / SEGMENTS
		# How far behind the blade this slice is, measured from where the swing starts
		var along = u0
		if style == "fan":
			along = abs(u0 + u1 - 1.0)
		elif sweep_dir < 0.0:
			along = 1.0 - u1
		if along > lead:
			continue

		# Brightest at the blade, dimmer along the trail
		var heat = 1.0 - clamp((lead - along) / 0.7, 0.0, 1.0)
		var a = color.a * fade * (0.25 + 0.75 * heat)
		var a0 = -half + 2.0 * half * u0
		var a1 = -half + 2.0 * half * u1

		# Faint fill toward Veyl, bright rim at the sword's reach
		var inner = 0.35
		var c_in = Color(color.r, color.g, color.b, a * 0.25)
		var c_out = Color(color.r, color.g, color.b, a)
		var c_rim = Color(1.0, 0.95, 0.8, a)
		quad(a0, a1, inner, 0.85, c_in, c_out)
		quad(a0, a1, 0.85, 1.0, c_rim, c_out)


func draw_ring():

	var t = clamp(time / RING_TIME, 0.0, 1.0)
	var outer = lerp(0.3, 1.1, ease(t, 0.3))
	var width = 0.25 * (1.0 - t) + 0.05
	var a = color.a * (1.0 - t)
	var c_edge = Color(1.0, 0.95, 0.8, a)
	var c_soft = Color(color.r, color.g, color.b, 0.0)

	for i in SEGMENTS:
		var a0 = TAU * i / SEGMENTS
		var a1 = TAU * (i + 1) / SEGMENTS
		quad(a0, a1, max(outer - width, 0.0), outer, c_soft, c_edge)
		quad(a0, a1, outer, outer + width * 0.4, c_edge, c_soft)


# One slice of an annulus between two angles and two radii (0..1 of radius)
func quad(a0: float, a1: float, r_in: float, r_out: float, c_in: Color, c_out: Color):

	var p0 = point(a0, r_in)
	var p1 = point(a1, r_in)
	var p2 = point(a1, r_out)
	var p3 = point(a0, r_out)
	verts.append_array([[p0, c_in], [p2, c_out], [p1, c_in], [p0, c_in], [p3, c_out], [p2, c_out]])


# Angle 0 is forward (-Z), positive angles toward +X
func point(angle: float, r: float) -> Vector3:
	return Vector3(sin(angle), 0, -cos(angle)) * radius * r
