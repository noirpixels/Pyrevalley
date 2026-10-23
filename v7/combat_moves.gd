extends RefCounted

# Veyl's moves, side-on. The juggle game from v6, turned on its side:
#   STRIKE  (left click / J)          a quick cut that shoves the target away
#   HEAVY   (right click / K)         slower, harder, a big shove and daze
#   LAUNCH  (scroll up, or Up+strike) an upward cut that throws it into the air
#   SLAM    (scroll down, or Down+strike) a downward chop
#   AERIAL  (slam in the air)         chops down: spikes a launched target
#                                     for a critical hit
# Alternating strike and heavy rattles a target, filling its daze meter
# faster. Any hit landed in the air gives back Veyl's jump and dash.
#
# Numbers multiply the weapon's damage, reach and cooldown. push and launch
# are speeds (px/s) handed to the target. box: the hit area in front of
# Veyl as [x from, x to, y from, y to], in reach units (x) and px (y, up is
# negative), mirrored when Veyl faces left.

const MOVES = {
	"strike": {"damage": 1.0, "cooldown": 1.0, "push": 380.0, "launch": 0.0, "dizzy": 18.0, "anim": "side",
		"box": [-0.1, 1.0, -105.0, -10.0], "impact": 0.06},
	"heavy": {"damage": 1.4, "cooldown": 1.55, "push": 680.0, "launch": 0.0, "dizzy": 30.0, "anim": "side",
		"box": [-0.15, 1.15, -115.0, -5.0], "impact": 0.11},
	"launch": {"damage": 0.9, "cooldown": 1.2, "push": 120.0, "launch": 980.0, "dizzy": 12.0, "anim": "up",
		"box": [-0.1, 0.9, -160.0, -10.0], "impact": 0.08},
	"slam": {"damage": 1.1, "cooldown": 1.1, "push": 200.0, "launch": 0.0, "dizzy": 22.0, "anim": "down",
		"box": [0.0, 1.0, -70.0, 15.0], "impact": 0.1},
	"aerial": {"damage": 1.0, "cooldown": 0.9, "push": 160.0, "launch": -1150.0, "dizzy": 20.0, "anim": "aerial",
		"box": [-0.45, 0.85, -70.0, 70.0], "impact": 0.09},
}

# Per weapon, the numbers that differ from the sword's
const MOVESETS = {
	"sword": {},
	"spear": {
		"strike": {"damage": 0.85, "box": [0.0, 1.0, -80.0, -30.0], "anim": "thrust"},
		"heavy": {"damage": 1.2, "box": [0.0, 1.1, -85.0, -25.0], "anim": "thrust"},
		"launch": {"launch": 900.0},
		"aerial": {"damage": 1.25},
	},
	"hammer": {
		"strike": {"push": 560.0, "dizzy": 30.0},
		"heavy": {"push": 900.0, "dizzy": 48.0, "box": [-0.3, 1.2, -120.0, 0.0]},
		"launch": {"launch": 1100.0, "dizzy": 26.0},
		"slam": {"damage": 1.3, "dizzy": 40.0, "box": [-0.8, 1.1, -70.0, 15.0]},
		"aerial": {"damage": 1.4, "box": [-0.8, 0.9, -70.0, 80.0]},
	},
	"fists": {
		"strike": {"push": 180.0, "dizzy": 24.0, "anim": "jab"},
		"heavy": {"push": 300.0, "dizzy": 36.0, "anim": "jab"},
		"launch": {"launch": 820.0, "dizzy": 18.0},
		"aerial": {"dizzy": 24.0},
	},
}

const AERIAL_CRIT = 2.5
const DIZZY_BONUS = 1.25


static func get_move(kind: String, airborne: bool, moveset: String) -> Dictionary:

	if airborne and kind == "slam":
		kind = "aerial"
	var move = MOVES[kind].duplicate()
	move.merge(MOVESETS.get(moveset, {}).get(kind, {}), true)
	move["name"] = kind
	return move


# The move's hit area in world space
static func hit_rect(move: Dictionary, origin: Vector2, facing: float, reach: float) -> Rect2:

	var b: Array = move["box"]
	var x0 = b[0] * reach
	var x1 = b[1] * reach
	if facing < 0.0:
		var t = x0
		x0 = -x1
		x1 = -t
	return Rect2(origin + Vector2(x0, b[2]), Vector2(x1 - x0, b[3] - b[2]))
