extends StaticBody3D

# Low-poly pine built from code: a tapered trunk under drooping, star-edged
# branch tiers, flat-shaded with vertex colours so every facet catches the
# light differently. The canopy starts above Veyl's head so vae can walk
# up to the trunk; trees between Veyl and the camera dither out
# (occluder.gdshader).
# An axe fells it (harvest.gd): it topples away from whoever cut it,
# leaving logs and a stump, and grows back after REGROW_TIME. The host
# keeps count of the cuts (host_request); everyone sees it fall (fx_fell).

const VARIANTS = 4
const OCCLUDER_SHADER = preload("res://occluder.gdshader")
const CONTACT_SHADER = preload("res://contact_shadow.gdshader")

const BARK = Color(0.24, 0.16, 0.11)
const BARK_DARK = Color(0.11, 0.07, 0.05)
const NEEDLE_DARK = Color(0.05, 0.11, 0.08)
const NEEDLE = Color(0.13, 0.26, 0.17)
const NEEDLE_TIP = Color(0.27, 0.40, 0.22)

# Axe power it takes to fell (a stone axe hits for 1)
const CHOP_HP = 8.0
const REGROW_TIME = 300.0
# Won't grow back on top of a Veyl
const REGROW_CLEARANCE = 8.0
const LOGS = 3

var felled: bool = false
var chop_left: float = CHOP_HP
var rest_basis: Basis
var stump: MeshInstance3D = null
var visuals: Array = []

static var _meshes: Array[ArrayMesh] = []
static var _material: ShaderMaterial
static var _shadow_material: StandardMaterial3D
static var _contact_mesh: QuadMesh
static var _contact_material: ShaderMaterial


func _ready() -> void:
	if _meshes.is_empty():
		_build_shared()
	add_to_group("trees")
	add_to_group("net_objects")
	rest_basis = basis

	# Same tree every run: the variant comes from where it stands
	var p = global_position
	var variant = absi(int(p.x * 7.0) * 31 + int(p.z * 13.0)) % VARIANTS

	var visual = MeshInstance3D.new()
	visual.mesh = _meshes[variant]
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

	# Shadows come from a plain copy, so fading the tree never fades its shadow
	var caster = MeshInstance3D.new()
	caster.mesh = _meshes[variant]
	caster.material_override = _shadow_material
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(caster)

	var contact = MeshInstance3D.new()
	contact.mesh = _contact_mesh
	contact.material_override = _contact_material
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact.position.y = 0.06
	add_child(contact)
	visuals = [visual, caster, contact]


# ============================================================
# FELLING (host decides; everyone sees)
# ============================================================

# args: ["chop", axe power, fists shook it]
func host_request(args: Array, sender: int):

	if felled or args.size() < 3 or args[0] != "chop":
		return
	var veyl = NetSync.veyl_of(sender)
	if veyl == null or veyl.global_position.distance_to(global_position) > 16.0:
		return
	if args[2] and randf() < 0.5:
		drop("Branch", global_position + random_ring(2.5))
	var amount = clampf(args[1], 0.0, 3.0)
	if amount <= 0.0:
		NetSync.object_fx(self, "shake")
		return
	chop_left -= amount
	if chop_left > 0.0:
		NetSync.object_fx(self, "shake")
		return
	# Topples away from whoever cut it
	var away = (global_position - veyl.global_position) * Vector3(1, 0, 1)
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	NetSync.object_fx(self, "fell", [away])
	for i in LOGS:
		drop("Log", global_position + away * (3.0 + i * 3.0) + random_ring(1.0))
	drop("Branch", global_position + away * 6.0 + random_ring(2.0))
	schedule_regrow(REGROW_TIME)


func drop(item_name: String, at: Vector3):
	NetSync.drop("loose", item_name, Vector3(at.x, 0, at.z))


func random_ring(r: float) -> Vector3:
	var a = randf() * TAU
	return Vector3(cos(a), 0, sin(a)) * r


func schedule_regrow(after: float):
	get_tree().create_timer(after, false).timeout.connect(try_regrow)


func try_regrow():

	if not felled:
		return
	for veyl in NetSync.all_players():
		if veyl.global_position.distance_to(global_position) < REGROW_CLEARANCE:
			schedule_regrow(10.0)
			return
	NetSync.object_fx(self, "regrow")


func fx_shake():

	var tween = create_tween()
	var lean = rest_basis.rotated(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(), 0.04)
	tween.tween_property(self, "basis", lean, 0.06)
	tween.tween_property(self, "basis", rest_basis, 0.18)


func fx_fell(away: Vector3):

	felled = true
	$CollisionShape3D.set_deferred("disabled", true)
	if NetSync.near_me(global_position):
		Sfx.play("hit_heavy", -2.0, 0.45)
	# Tip over around the base, then sink away and leave the stump
	var axis = Vector3.UP.cross(away).normalized()
	var local_axis = (get_parent().global_basis.inverse() * axis).normalized()
	var down = rest_basis.rotated(local_axis, PI / 2.0 * 0.95)
	var tween = create_tween()
	tween.tween_property(self, "basis", down, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(1.5)
	tween.tween_callback(func():
		for v in visuals:
			v.visible = false
		basis = rest_basis)
	show_stump()


func fx_regrow():

	felled = false
	chop_left = CHOP_HP
	if stump:
		stump.queue_free()
		stump = null
	basis = rest_basis.scaled(Vector3(0.15, 0.15, 0.15))
	for v in visuals:
		v.visible = true
	$CollisionShape3D.set_deferred("disabled", false)
	create_tween().tween_property(self, "basis", rest_basis, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func show_stump():

	if stump:
		return
	stump = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.8
	mesh.bottom_radius = 1.0
	mesh.height = 1.2
	var mat = StandardMaterial3D.new()
	mat.albedo_color = BARK
	mesh.material = mat
	stump.mesh = mesh
	stump.position = position + Vector3(0, 0.6, 0)
	get_parent().add_child(stump)


func net_snapshot():
	return {"felled": true} if felled else null


func apply_snapshot(_data):

	felled = true
	$CollisionShape3D.set_deferred("disabled", true)
	for v in visuals:
		v.visible = false
	show_stump()
	if Net.is_host():
		schedule_regrow(REGROW_TIME)


func _exit_tree():

	if stump:
		stump.queue_free()


static func _build_shared() -> void:
	_material = ShaderMaterial.new()
	_material.shader = OCCLUDER_SHADER

	_shadow_material = StandardMaterial3D.new()

	for i in VARIANTS:
		var rng = RandomNumberGenerator.new()
		rng.seed = 9001 + i * 97
		_meshes.append(_build_pine(rng))

	# Darkened ground around the roots, standing in for ambient occlusion
	_contact_mesh = QuadMesh.new()
	_contact_mesh.size = Vector2(11, 11)
	_contact_mesh.orientation = PlaneMesh.FACE_Y
	_contact_material = ShaderMaterial.new()
	_contact_material.shader = CONTACT_SHADER


static func _build_pine(rng: RandomNumberGenerator) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Trunk with a little root flare
	var sides = 7
	var trunk = [[0.0, 1.05], [0.9, 0.72], [7.0, 0.55], [14.0, 0.3]]
	for r in trunk.size() - 1:
		var y0 = trunk[r][0]
		var y1 = trunk[r + 1][0]
		for s in sides:
			var a0 = TAU * s / sides
			var a1 = TAU * (s + 1) / sides
			var b0 = Vector3(cos(a0) * trunk[r][1], y0, sin(a0) * trunk[r][1])
			var b1 = Vector3(cos(a1) * trunk[r][1], y0, sin(a1) * trunk[r][1])
			var t0 = Vector3(cos(a0) * trunk[r + 1][1], y1, sin(a0) * trunk[r + 1][1])
			var t1 = Vector3(cos(a1) * trunk[r + 1][1], y1, sin(a1) * trunk[r + 1][1])
			var mid = Vector3(0, (y0 + y1) / 2.0, 0)
			var c0 = BARK_DARK.lerp(BARK, y0 / 7.0)
			var c1 = BARK_DARK.lerp(BARK, y1 / 7.0)
			_tri(st, b0, t0, b1, c0, c1, c0, mid)
			_tri(st, b1, t0, t1, c0, c1, c1, mid)

	# Branch tiers, widest at the bottom; the lowest tips clear Veyl's head
	var tiers = rng.randi_range(4, 6)
	var lowest = 10.5
	var tip = rng.randf_range(19.5, 22.0)
	for i in tiers:
		var t = float(i) / (tiers - 1)
		var base_y = lerp(lowest, tip - 5.0, t)
		var top_y = base_y + 5.0 if i < tiers - 1 else tip
		var radius = lerp(5.2, 2.2, t) * rng.randf_range(0.9, 1.1)
		var shade = lerp(0.0, 0.35, t)  # higher tiers sit in more light
		_tier(st, rng, base_y, top_y, radius, shade)

	st.index()
	return st.commit()


static func _tier(st: SurfaceTool, rng: RandomNumberGenerator, base_y: float, top_y: float, radius: float, shade: float) -> void:
	var points = 9
	var twist = rng.randf() * TAU
	var apex = Vector3(rng.randf_range(-0.2, 0.2), top_y, rng.randf_range(-0.2, 0.2))
	var under = Vector3(0, base_y + 1.6, 0)

	# Star-shaped rim: drooping branch tips with notches between them
	var rim: Array[Vector3] = []
	for k in points * 2:
		var a = twist + TAU * k / (points * 2)
		var is_tip = k % 2 == 0
		var r = radius * (rng.randf_range(0.95, 1.12) if is_tip else rng.randf_range(0.62, 0.72))
		var y = base_y - (rng.randf_range(0.4, 0.9) if is_tip else -0.7)
		rim.append(Vector3(cos(a) * r, y, sin(a) * r))

	var inner = NEEDLE_DARK.lerp(NEEDLE, 0.35 + shade)
	var outer = NEEDLE.lerp(NEEDLE_TIP, 0.25 + shade)
	var below = NEEDLE_DARK.darkened(0.3)
	var axis_low = Vector3(0, base_y - 4.0, 0)
	var axis_high = Vector3(0, top_y + 4.0, 0)
	for k in rim.size():
		var a = rim[k]
		var b = rim[(k + 1) % rim.size()]
		var ca = outer if k % 2 == 0 else outer.darkened(0.25)
		var cb = outer if (k + 1) % 2 == 0 else outer.darkened(0.25)
		_tri(st, apex, a, b, inner, ca, cb, axis_low)
		_tri(st, under, b, a, below, below, below, axis_high)


# Adds a flat-shaded triangle facing away from `inside`
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, inside: Vector3) -> void:
	var centroid = (a + b + c) / 3.0
	var outward = centroid - inside
	var normal = (b - a).cross(c - a).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	else:
		# Godot's front faces wind clockwise as seen from outside
		var swap = b
		b = c
		c = swap
		var swap_c = cb
		cb = cc
		cc = swap_c
	st.set_normal(normal)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
