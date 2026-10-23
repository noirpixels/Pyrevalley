extends Node

# Veyl as a cut-out puppet. Each facing's art is cut into head, torso, arms
# and legs, which are posed in a small 2D viewport. The CharacterSprite
# shows that viewport, so the rest of the game still sees one sprite. The
# animator says what Veyl is doing; the puppet moves the limbs and sword.

# Viewport size. Veyl's feet sit on the bottom edge, with room above and to
# the sides for the sword.
const SIZE = Vector2i(320, 288)
const InkSprite = preload("res://ink_sprite.gd")
const HeldArt = preload("res://held_art.gd")

# Cut lines per facing, in source pixels. Each arm is [rect, shoulder, hand];
# the first arm holds the sword. Parts claim pixels in this order: arms,
# head, legs, and whatever is left is the torso. rest_blade is the sword's
# screen angle at rest (degrees, 0 = right, 90 = down).
const RIGS = {
	"front": {
		"neck": 96, "hip": 172,
		"legs": [Rect2i(0, 172, 56, 44), Rect2i(56, 172, 56, 44)],
		"arms": [[Rect2i(0, 112, 30, 66), Vector2(26, 120), Vector2(16, 154)],
				[Rect2i(82, 112, 30, 66), Vector2(86, 120), Vector2(96, 154)]],
		"arms_behind": false, "fill_arms": false, "rest_blade": 125.0,
	},
	"back": {
		"neck": 96, "hip": 176,
		"legs": [Rect2i(0, 176, 56, 40), Rect2i(56, 176, 56, 40)],
		"arms": [[Rect2i(82, 112, 30, 66), Vector2(86, 120), Vector2(96, 154)],
				[Rect2i(0, 112, 30, 66), Vector2(26, 120), Vector2(16, 154)]],
		"arms_behind": true, "fill_arms": false, "rest_blade": 55.0,
	},
	# Side view faces right; one arm, and the far leg is a darkened copy
	"right": {
		"neck": 96, "hip": 164,
		"legs": [Rect2i(0, 164, 104, 52)],
		"arms": [[Rect2i(20, 124, 40, 54), Vector2(44, 120), Vector2(40, 156)]],
		"arms_behind": false, "fill_arms": true, "rest_blade": 70.0,
	},
}

# Cloth colour painted where a side-view arm used to cover the torso
const FILL = Color(0.2, 0.21, 0.29)

# Swing keyframes for a swing toward screen right; swings to the left are
# mirrored. hand is where the sword arm points from the shoulder and blade
# where the sword points, both screen angles in degrees, unwrapped so each
# swing travels the intended way (over the top, underarm, or a chop). t is
# seconds since the swing began. "smear" draws a blade trail into that key.
const SWINGS = {
	# Left / right: wind up across the body, cut over the top, follow through
	"side": [
		{"t": 0.06, "hand": 190.0, "blade": 205.0, "twist": -0.10, "body": Vector2(-3, 1)},
		{"t": 0.11, "hand": 375.0, "blade": 370.0, "twist": 0.12, "body": Vector2(6, 0), "smear": true},
		{"t": 0.21, "hand": 400.0, "blade": 410.0, "twist": 0.10, "body": Vector2(5, 1)},
		{"t": 0.36},
	],
	# Up: crouch with the blade low, rip it up through the front
	"up": [
		{"t": 0.07, "hand": 150.0, "blade": 165.0, "twist": -0.06, "body": Vector2(-2, 5)},
		{"t": 0.13, "hand": -35.0, "blade": -62.0, "twist": 0.06, "body": Vector2(3, -6), "smear": true},
		{"t": 0.24, "hand": -40.0, "blade": -68.0, "twist": 0.04, "body": Vector2(2, -4)},
		{"t": 0.40},
	],
	# Down: raise it overhead, chop it into the ground
	"down": [
		{"t": 0.08, "hand": -135.0, "blade": -150.0, "twist": -0.05, "body": Vector2(-1, -4)},
		{"t": 0.13, "hand": 60.0, "blade": 80.0, "twist": 0.10, "body": Vector2(4, 6), "smear": true},
		{"t": 0.25, "hand": 62.0, "blade": 84.0, "twist": 0.10, "body": Vector2(4, 6)},
		{"t": 0.40},
	],
	# Thrust (spears): draw back, drive the point straight out
	"thrust": [
		{"t": 0.05, "hand": 120.0, "blade": 8.0, "twist": -0.08, "body": Vector2(-4, 0)},
		{"t": 0.10, "hand": 2.0, "blade": 0.0, "twist": 0.12, "body": Vector2(8, 0), "smear": true},
		{"t": 0.20, "hand": 6.0, "blade": 2.0, "twist": 0.10, "body": Vector2(6, 0)},
		{"t": 0.32},
	],
	# Jab (fists): a short straight punch
	"jab": [
		{"t": 0.04, "hand": 110.0, "blade": 110.0, "twist": -0.06, "body": Vector2(-2, 0)},
		{"t": 0.08, "hand": 5.0, "blade": 5.0, "twist": 0.10, "body": Vector2(6, 0)},
		{"t": 0.16, "hand": 10.0, "blade": 10.0, "twist": 0.08, "body": Vector2(4, 0)},
		{"t": 0.24},
	],
	# Aerial: a bigger chop with the whole body pitching into it
	"aerial": [
		{"t": 0.09, "hand": -140.0, "blade": -170.0, "twist": -0.15, "body": Vector2(-2, -4)},
		{"t": 0.15, "hand": 75.0, "blade": 95.0, "twist": 0.30, "body": Vector2(6, 4), "smear": true},
		{"t": 0.26, "hand": 78.0, "blade": 98.0, "twist": 0.25, "body": Vector2(5, 4)},
		{"t": 0.42},
	],
}

# How long the blade trail lingers (seconds)
const SMEAR_TIME = 0.07

var viewport: SubViewport
var texture: Texture2D
var rigs = {}
var rig: Dictionary
var facing: String = ""
var smear: Polygon2D
var smear_points = []

# Current swing: keyframes (already mirrored), time, and the pose it began from
var swing_keys = []
var swing_time: float = 0.0
var swing_from = {}
var swing_dir: float = 1.0


func _init(textures: Dictionary):

	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	texture = viewport.get_texture()

	var held = HeldArt.get_art("Sword", "Rusted")
	for key in textures:
		if textures[key]:
			rigs[key] = build_rig(RIGS[key], textures[key], held)
			viewport.add_child(rigs[key]["root"])

	smear = Polygon2D.new()
	smear.color = Color(1.0, 0.95, 0.85, 0.8)
	viewport.add_child(smear)

	set_facing("front")


# What's in Veyl's hand ("" for nothing: fists)
func set_held(type: String, material: String):

	var art = HeldArt.get_art(type, material) if type != "" else {}
	for key in rigs:
		var held: Sprite2D = rigs[key]["sword"]
		held.visible = not art.is_empty()
		if art.is_empty():
			continue
		held.texture = art["texture"]
		held.offset = -art["grip"]
		rigs[key]["blade_length"] = art["length"]


func set_facing(which: String):

	if which == facing or not rigs.has(which):
		return
	facing = which
	for key in rigs:
		rigs[key]["root"].visible = key == which
	rig = rigs[which]


# Start a swing. dir is +1 to swing toward screen right, -1 toward the left,
# in the puppet's own (unflipped) space.
func swing(kind: String, dir: float):

	if not SWINGS.has(kind):
		kind = "side"
	swing_from = current_pose()
	swing_dir = dir
	swing_time = 0.0
	swing_keys = []
	for key in SWINGS[kind]:
		var k = key.duplicate()
		if k.has("hand"):
			k["hand"] = mirror(deg_to_rad(k["hand"]), dir)
			k["blade"] = mirror(deg_to_rad(k["blade"]), dir)
			k["twist"] *= dir
			k["body"] = Vector2(k["body"].x * dir, k["body"].y)
		swing_keys.append(k)


func swinging() -> bool:

	return not swing_keys.is_empty()


# Poses the limbs for this frame. step is the walk cycle in radians.
func animate(delta: float, step: float, walking: bool, airborne: bool, time: float):

	var pose = rest_pose()
	var s = sin(step)

	var leg_lift = [0.0, 0.0]
	var leg_turn = 0.0
	var other_arm = 0.0

	if airborne:
		leg_lift = [5.0, 5.0]
		pose["hand"] += 0.35 * arm_side()
		other_arm = -0.35 * arm_side()
	elif walking:
		leg_lift = [max(s, 0.0) * 6.0, max(-s, 0.0) * 6.0]
		leg_turn = s * 0.35
		pose["body"].y = -abs(s) * 3.0
		pose["hand"] += s * 0.25
		other_arm = s * 0.25
	else:
		pose["body"].y = round(sin(time * 2.4) * 1.2)

	if swinging():
		swing_time += delta
		var swung = swing_pose(pose)
		swung["body"].y += pose["body"].y
		pose = swung
		other_arm = -pose["twist"] * 1.5

	apply_pose(pose, leg_lift, leg_turn, other_arm)
	update_smear(delta)


func rest_pose() -> Dictionary:

	return {
		"hand": PI / 2.0,
		"blade": deg_to_rad(rig["rest_blade"]),
		"twist": 0.0,
		"body": Vector2.ZERO,
		"smear": false,
	}


func current_pose() -> Dictionary:

	var arm: Node2D = rig["arms"][0]
	return {
		"hand": arm.rotation + PI / 2.0,
		"blade": rig["sword"].global_rotation - PI / 2.0,
		"twist": rig["body"].rotation,
		"body": rig["body"].position - rig["body_rest"],
		"smear": false,
	}


# Where the swing is now. The first leg starts from wherever the arm was and
# the last eases back to rest; both take the short way round. The legs in
# between keep their unwrapped angles so the arc goes the intended way.
func swing_pose(rest: Dictionary) -> Dictionary:

	var t0 = 0.0
	var from = swing_from
	for i in swing_keys.size():
		var key = swing_keys[i]
		var to = key if key.has("hand") else rest
		if swing_time < key["t"]:
			var u = (swing_time - t0) / (key["t"] - t0)
			var short = i == 0 or not key.has("hand")
			if key.get("smear", false):
				u = 1.0 - pow(1.0 - u, 3.0)
			else:
				u = smoothstep(0.0, 1.0, u)
			return blend(from, to, u, short, key.get("smear", false))
		t0 = key["t"]
		from = to
	swing_keys = []
	return rest


func blend(a: Dictionary, b: Dictionary, u: float, short: bool, smearing: bool) -> Dictionary:

	var hand_b = b["hand"]
	var blade_b = b["blade"]
	if short:
		hand_b = a["hand"] + angle_difference(a["hand"], b["hand"])
		blade_b = a["blade"] + angle_difference(a["blade"], b["blade"])
	return {
		"hand": lerp(a["hand"], hand_b, u),
		"blade": lerp(a["blade"], blade_b, u),
		"twist": lerp(a["twist"], b["twist"], u),
		"body": a["body"].lerp(b["body"], u),
		"smear": smearing,
	}


func apply_pose(pose: Dictionary, leg_lift: Array, leg_turn: float, other_arm: float):

	var body: Node2D = rig["body"]
	body.position = rig["body_rest"] + pose["body"]
	body.rotation = pose["twist"]
	rig["head"].rotation = -pose["twist"] * 0.4

	var arms = rig["arms"]
	arms[0].rotation = pose["hand"] - PI / 2.0
	# The sword's own turn is whatever's left after the arm's
	rig["sword"].rotation = pose["blade"] + PI / 2.0 - arms[0].rotation - body.rotation
	if arms.size() > 1:
		arms[1].rotation = other_arm

	var legs = rig["legs"]
	if legs.size() == 2 and not rig["side"]:
		for i in 2:
			legs[i].position = rig["leg_rest"][i] - Vector2(0, leg_lift[i])
	else:
		# Side view: the legs scissor around the hip
		legs[0].rotation = -leg_turn
		legs[1].rotation = leg_turn
		legs[0].position = rig["leg_rest"][0] - Vector2(0, leg_lift[0] * 0.5)
		legs[1].position = rig["leg_rest"][1] - Vector2(0, leg_lift[1] * 0.5)

	smear.set_meta("active", pose["smear"])


# Blade trail: the last few blade positions joined into a sheet
func update_smear(delta: float):

	for p in smear_points:
		p["age"] += delta
	smear_points = smear_points.filter(func(p): return p["age"] < SMEAR_TIME)

	if smear.get_meta("active", false):
		var xf: Transform2D = rig["sword"].get_global_transform()
		smear_points.append({"tip": xf * Vector2(0, -rig["blade_length"]), "base": xf * Vector2(0, -12), "age": 0.0})

	if smear_points.size() < 2:
		smear.polygon = PackedVector2Array()
		return
	var poly = PackedVector2Array()
	for p in smear_points:
		poly.append(p["tip"])
	for i in range(smear_points.size() - 1, -1, -1):
		poly.append(smear_points[i]["base"])
	smear.polygon = poly


# Which way the sword arm reaches outward on screen
func arm_side() -> float:

	return -1.0 if rig["rest_blade"] > 90.0 else 1.0


static func mirror(angle: float, dir: float) -> float:

	return angle if dir > 0.0 else PI - angle


# ============================================================
# BUILDING
# ============================================================

func build_rig(def: Dictionary, source: Texture2D, held: Dictionary) -> Dictionary:

	# Lit on the sun side before cutting, so cut lines don't get a rim
	var img = InkSprite.ink_image(InkSprite.load_image(source), 0.45)
	var w = img.get_width()
	var h = img.get_height()

	# Sort every pixel into a part
	var arm_imgs = []
	for a in def["arms"]:
		arm_imgs.append(blank(w, h))
	var head_img = blank(w, h)
	var torso_img = blank(w, h)
	var leg_imgs = []
	for l in def["legs"]:
		leg_imgs.append(blank(w, h))

	for y in h:
		for x in w:
			var c = img.get_pixel(x, y)
			# Compression leaves soft edges; keep the pixel art crisp
			if c.a < 0.5:
				continue
			c.a = 1.0
			var p = Vector2i(x, y)
			var claimed = false
			for i in def["arms"].size():
				if def["arms"][i][0].has_point(p):
					arm_imgs[i].set_pixel(x, y, c)
					if def["fill_arms"] and y > def["neck"]:
						torso_img.set_pixel(x, y, FILL)
					claimed = true
					break
			if claimed:
				continue
			if y < def["neck"]:
				head_img.set_pixel(x, y, c)
				continue
			for i in def["legs"].size():
				if def["legs"][i].has_point(p):
					leg_imgs[i].set_pixel(x, y, c)
					claimed = true
					break
			if not claimed:
				torso_img.set_pixel(x, y, c)

	# Top-left of the source image inside the viewport, feet on the bottom edge
	var origin = Vector2((SIZE.x - w) / 2, SIZE.y - h)
	var hip = Vector2(w / 2.0, def["hip"])
	var neck = Vector2(w / 2.0, def["neck"])

	var root = Node2D.new()
	root.position = origin

	var side = def["legs"].size() == 1
	var legs = []
	var leg_rest = []
	var leg_defs = def["legs"]
	if side:
		# Far leg: a darker copy behind the near one
		leg_imgs = [leg_imgs[0], leg_imgs[0]]
		leg_defs = [def["legs"][0], def["legs"][0]]
	for i in leg_imgs.size():
		var r: Rect2i = leg_defs[i]
		var pivot = Vector2(r.position.x + r.size.x / 2.0, r.position.y)
		var leg = part(leg_imgs[i], pivot)
		if side and i == 1:
			leg.modulate = Color(0.6, 0.6, 0.7)
		legs.append(leg)
		leg_rest.append(pivot)
	if side:
		# Draw the far leg first
		root.add_child(legs[1])
		root.add_child(legs[0])
	else:
		for leg in legs:
			root.add_child(leg)

	var body = Node2D.new()
	body.position = hip
	root.add_child(body)

	var torso = part(torso_img, hip)
	torso.position = Vector2.ZERO

	var head = part(head_img, neck)
	head.position = neck - hip

	var arms = []
	for i in def["arms"].size():
		var shoulder: Vector2 = def["arms"][i][1]
		var arm = part(arm_imgs[i], shoulder)
		arm.position = shoulder - hip
		arms.append(arm)

	if def["arms_behind"]:
		for arm in arms:
			body.add_child(arm)
	body.add_child(torso)
	body.add_child(head)
	if not def["arms_behind"]:
		for arm in arms:
			body.add_child(arm)

	# The held item goes in the first arm's fist, drawn under the mitten
	var sword = Sprite2D.new()
	sword.texture = held["texture"]
	sword.centered = false
	sword.offset = -held["grip"]
	sword.position = def["arms"][0][2] - def["arms"][0][1]
	sword.show_behind_parent = true
	arms[0].add_child(sword)

	return {
		"root": root, "body": body, "body_rest": hip, "head": head, "torso": torso,
		"arms": arms, "legs": legs, "leg_rest": leg_rest, "sword": sword,
		"side": side, "rest_blade": def["rest_blade"], "blade_length": held["length"],
	}


# A Node2D that turns around pivot (source pixels), holding the part's image
func part(img: Image, pivot: Vector2) -> Node2D:

	var node = Node2D.new()
	node.position = pivot
	var spr = Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	spr.centered = false
	spr.offset = -pivot
	node.add_child(spr)
	return node


static func blank(w: int, h: int) -> Image:

	return Image.create(w, h, false, Image.FORMAT_RGBA8)
