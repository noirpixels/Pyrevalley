extends RefCounted

# What a swing does to rock and wood. The striking player's machine judges
# the tool against the target (and wears the tool down there); the host
# then applies the work (dig_site.gd, tree.gd host_request).
#   Pickaxe on rock: full power if its tier matches the rock's hardness;
#     one tier short is slow and wears it three times as fast; two short and
#     it glances off, wearing it badly.
#   Axe on a tree: fells it in a few strokes.
#   Anything else is the wrong tool: a blade or hammer barely marks soft
#     rock or wood and wears fast; fists dig soil by hand, shake branches
#     from trees, and hurt on stone.

const Items = preload("res://items.gd")
const Strata = preload("res://strata.gd")
const HitSpark = preload("res://hit_spark.gd")
const FloatingText = preload("res://floating_text.gd")

# How far a swing reaches a tree trunk
const TREE_REACH = 7.5
const TREE_ARC = 75.0
const DIG_REACH = 6.5
# Fists on a tree: chance a branch drops
const SHAKE_CHANCE = 0.35
const FIST_HURT = 2
# Seconds between "too hard" messages
const NAG_GAP = 2.5

static var _last_nag: int = -100000


static func strike(veyl: Node3D, move: Dictionary, aim: Vector3, gear: Dictionary) -> bool:

	var type = gear.get("type", "Fists")
	if type != "Pickaxe":
		var tree = find_tree(veyl, aim)
		if tree:
			chop(veyl, tree, type, gear)
			return true
	for site in veyl.get_tree().get_nodes_in_group("dig_sites"):
		if not site.near(veyl.global_position, DIG_REACH + 4.0):
			continue
		var hit = site.pick(veyl, move["name"], aim, DIG_REACH)
		if not hit.is_empty():
			mine(veyl, site, hit, type, gear)
			return true
	return false


static func find_tree(veyl: Node3D, aim: Vector3) -> Node3D:

	var best: Node3D = null
	var best_dist = TREE_REACH
	for tree in veyl.get_tree().get_nodes_in_group("trees"):
		if tree.felled:
			continue
		var offset = tree.global_position - veyl.global_position
		offset.y = 0
		var dist = offset.length()
		if dist > best_dist:
			continue
		if dist > 0.5 and rad_to_deg(aim.angle_to(offset.normalized())) > TREE_ARC:
			continue
		best = tree
		best_dist = dist
	return best


# hit: where the swing met the site's earth (dig_site.gd pick)
static func mine(veyl: Node3D, site: Node3D, hit: Dictionary, type: String, gear: Dictionary):

	var rock = site.material_at(hit["point"] - hit["normal"] * 0.5)
	var d = Strata.def(rock)
	if d.is_empty():
		return
	var at = site.to_global(hit["point"])
	var amount = 0.0
	var wear = 1.0
	var note = ""

	if rock == Strata.BEDROCK:
		note = "Bedrock. Nothing will break it."
		wear = 0.0
	elif type == "Pickaxe":
		var short = d["hardness"] - Items.tier(gear)
		var power = Items.tool_power(gear)
		if short <= 0:
			amount = power
		elif short == 1:
			amount = power * 0.25
			wear = 3.0
		else:
			wear = 6.0
			note = "The pick glances off. %s needs a stronger pickaxe." % d["name"]
	elif type == "Fists":
		wear = 0.0
		if d["hardness"] == 0:
			amount = 0.5
		else:
			note = "Ow. That's rock."
			veyl.take_damage(FIST_HURT, at)
	else:
		# The wrong tool for the job
		if d["hardness"] == 0:
			amount = 0.6
		elif d["hardness"] == 1:
			amount = 0.2
			wear = 4.0
		else:
			wear = 6.0
			note = "Too hard for a %s. Use a pickaxe." % type.to_lower()

	if type != "Fists" and wear > 0.0:
		GameState.wear(veyl.held_slot, wear)
	impact(veyl, at, d["base"], amount > 0.0, d["hardness"])
	nag(veyl, note)
	if amount > 0.0:
		NetSync.ask_host(site, ["dig", hit["point"], hit["normal"], hit["axis"], amount])


static func chop(veyl: Node3D, tree: Node3D, type: String, gear: Dictionary):

	var amount = 0.0
	var wear = 1.0
	var shake = false
	match type:
		"Axe":
			amount = Items.tool_power(gear)
		"Fists":
			wear = 0.0
			shake = randf() < SHAKE_CHANCE
		"Warhammer":
			amount = 0.15
			wear = 3.0
		_:
			amount = 0.3
			wear = 3.0
	if type != "Fists":
		GameState.wear(veyl.held_slot, wear)
	impact(veyl, tree.global_position + Vector3(0, 3.0, 0), Color(0.55, 0.38, 0.22), true, 0)
	if type != "Axe" and type != "Fists":
		nag(veyl, "Slow going. An axe would fell it.")
	NetSync.ask_host(tree, ["chop", amount, shake])


# Chips flying off whatever was struck, and the sound of it
static func impact(veyl: Node3D, at: Vector3, color: Color, bit: bool, hardness: int):

	var dir = (veyl.global_position - at) * Vector3(1, 0, 1) + Vector3.UP * 0.8
	HitSpark.spawn(veyl.get_parent(), at, dir, color.lightened(0.2), 12 if bit else 5)
	if hardness > 0:
		Sfx.play("hit_heavy", -6.0, randf_range(0.55, 0.75) if bit else 1.3)
	else:
		Sfx.play("enemy_land", -6.0, randf_range(1.0, 1.2))
	veyl.shake = max(veyl.shake, 0.12 if bit else 0.2)


static func nag(veyl: Node3D, text: String):

	if text == "":
		return
	var now = Time.get_ticks_msec()
	if now - _last_nag < NAG_GAP * 1000.0:
		return
	_last_nag = now
	FloatingText.spawn(veyl.get_parent(), veyl.global_position + Vector3(0, 6, 0), text, Color(0.9, 0.85, 0.75))
