extends Node3D

# Things lying on the forest floor for anyone to pick up: dry branches
# under the pines and flint along the paths. They're how a new Veyl gets
# started (a stone pickaxe and axe need both). Scattered from a fixed seed
# so they're in the same places every run; the host puts each back
# REGROW_TIME after it's taken. Lives under Emberwood, in its local space.

const MiningSites = preload("res://mining_sites.gd")

const SPOTS = 44
const REGROW_TIME = 150.0
const CHECK_EVERY = 3.0
const HALF_WIDTH = 36.0

# Emberwood-space spots, and what each grows
var spots: Array = []
# Host: the pickup lying at each spot (null while it's regrowing)
var lying: Array = []
var regrow_left: Array = []
var check_timer: float = 1.5


func _ready():

	name = "Forage"
	var rng = RandomNumberGenerator.new()
	rng.seed = 777
	var level = get_parent()
	var avoid = []
	for group in ["Creatures", "Shrines", "Gates", "LoreStones", "Pickups"]:
		var node = level.get_node_or_null(group)
		if node:
			for child in node.get_children():
				avoid.append(child.position)
	while spots.size() < SPOTS:
		var p = Vector3(rng.randf_range(-HALF_WIDTH, HALF_WIDTH), 0, rng.randf_range(-95.0, 118.0))
		if MiningSites.covers(p, 4.0) or avoid.any(func(a): return Vector2(p.x - a.x, p.z - a.z).length() < 6.0):
			continue
		spots.append({"pos": p, "item": "Flint" if rng.randf() < 0.35 else "Branch"})
	for i in SPOTS:
		lying.append(null)
		regrow_left.append(0.0)


func _process(delta):

	if not Net.is_host() or NetSync.world == null:
		return
	check_timer -= delta
	if check_timer > 0.0:
		return
	check_timer = CHECK_EVERY
	for i in spots.size():
		if lying[i] != null and is_instance_valid(lying[i]):
			continue
		if lying[i] != null:
			# Just taken
			lying[i] = null
			regrow_left[i] = REGROW_TIME
		regrow_left[i] -= CHECK_EVERY
		if regrow_left[i] <= 0.0:
			lying[i] = NetSync.drop("forage", spots[i]["item"], to_global(spots[i]["pos"]))
