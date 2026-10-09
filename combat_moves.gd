extends RefCounted

# Veyl's moves, one per mouse input:
#   left-click   LEFT   shove the target left on screen
#   right-click  RIGHT  shove the target right on screen (hits a little harder)
#   scroll up    UP     launches the target into the air
#   scroll down  DOWN   slams the target down; spikes launched targets
#   while airborne any attack is AERIAL: slams launched targets down for a critical hit
#
# Numbers multiply the weapon's damage, range and cooldown. push/launch are
# speeds handed to the enemy; spin and dizzy feed its impact meters, which
# are separate from its health (see enemy.gd apply_impact).

const MOVES = {
	"left":   {"damage": 1.0, "arc": 140.0, "range": 1.0, "cooldown": 1.0, "push": 10.0, "spin": -6.0, "dizzy": 18.0, "launch": 0.0,   "side": -1, "screen_dir": Vector2(-1, 0)},
	"right":  {"damage": 1.0, "arc": 140.0, "range": 1.0, "cooldown": 1.0, "push": 13.0, "spin": 6.0,  "dizzy": 18.0, "launch": 0.0,   "side": 1,  "screen_dir": Vector2(1, 0)},
	"up":     {"damage": 0.9, "arc": 110.0, "range": 1.0, "cooldown": 1.2, "push": 2.0,  "spin": 0.0,  "dizzy": 12.0, "launch": 20.0,  "side": 0,  "screen_dir": Vector2.ZERO},
	"down":   {"damage": 1.1, "arc": 120.0, "range": 1.0, "cooldown": 1.1, "push": 4.0,  "spin": 0.0,  "dizzy": 22.0, "launch": -30.0, "side": 0,  "screen_dir": Vector2.ZERO},
	"aerial": {"damage": 1.0, "arc": 140.0, "range": 1.0, "cooldown": 1.0, "push": 4.0,  "spin": 0.0,  "dizzy": 20.0, "launch": -30.0, "side": 0,  "screen_dir": Vector2.ZERO},
}

# Critical multiplier for an aerial hit on a launched target
const AERIAL_CRIT = 2.5


# kind is "left", "right", "up" or "down". Returns a copy of the move with
# its name; screen_dir ZERO = push straight away from Veyl
static func get_move(kind: String, airborne: bool) -> Dictionary:

	if airborne:
		kind = "aerial"

	var move = MOVES[kind].duplicate()
	move["name"] = kind
	return move
