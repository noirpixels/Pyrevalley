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
	"up":     {"damage": 0.9, "arc": 110.0, "range": 1.0, "cooldown": 1.2, "push": 2.0,  "spin": 0.0,  "dizzy": 12.0, "launch": 18.0,  "side": 0,  "screen_dir": Vector2.ZERO},
	"down":   {"damage": 1.1, "arc": 120.0, "range": 1.0, "cooldown": 1.1, "push": 4.0,  "spin": 0.0,  "dizzy": 22.0, "launch": -30.0, "side": 0,  "screen_dir": Vector2.ZERO},
	"aerial": {"damage": 1.0, "arc": 140.0, "range": 1.0, "cooldown": 1.0, "push": 4.0,  "spin": 0.0,  "dizzy": 20.0, "launch": -30.0, "side": 0,  "screen_dir": Vector2.ZERO},
}

# Other weapons change some numbers of each move (anything not listed is
# the sword's) and how Veyl's arm swings it (anim, veyl_puppet.gd SWINGS):
#   spear   long, narrow thrusts; a rising sweep; a plunging slam
#   hammer  slow and heavy: wide arcs, big shoves and dizziness, a ground smash
#   fists   quick jabs that rattle more than they hurt; an uppercut; a ground pound
const MOVESETS = {
	"sword": {},
	"spear": {
		"left": {"damage": 0.85, "arc": 50.0, "cooldown": 0.8, "push": 12.0, "spin": -2.0, "dizzy": 10.0, "anim": "thrust"},
		"right": {"damage": 0.85, "arc": 50.0, "cooldown": 0.8, "push": 14.0, "spin": 2.0, "dizzy": 10.0, "anim": "thrust"},
		"up": {"arc": 90.0, "launch": 16.0},
		"down": {"damage": 1.2, "arc": 60.0, "push": 6.0},
		"aerial": {"damage": 1.3, "arc": 60.0},
	},
	"hammer": {
		"left": {"arc": 160.0, "cooldown": 1.0, "push": 18.0, "spin": -9.0, "dizzy": 32.0},
		"right": {"arc": 160.0, "cooldown": 1.0, "push": 21.0, "spin": 9.0, "dizzy": 32.0},
		"up": {"launch": 22.0, "dizzy": 26.0},
		"down": {"damage": 1.25, "arc": 360.0, "range": 0.9, "dizzy": 40.0, "push": 8.0},
		"aerial": {"damage": 1.4, "arc": 360.0, "range": 0.9},
	},
	"fists": {
		"left": {"arc": 100.0, "push": 5.0, "spin": -3.0, "dizzy": 24.0, "anim": "jab"},
		"right": {"arc": 100.0, "push": 6.0, "spin": 3.0, "dizzy": 24.0, "anim": "jab"},
		"up": {"arc": 90.0, "launch": 14.0, "dizzy": 18.0},
		"down": {"damage": 0.9, "arc": 360.0, "range": 0.8, "dizzy": 26.0},
		"aerial": {"arc": 120.0, "dizzy": 24.0},
	},
}

# Critical multiplier for an aerial hit on a launched target
const AERIAL_CRIT = 2.5


# kind is "left", "right", "up" or "down"; moveset is the weapon's
# (MOVESETS). Returns a copy of the move with its name; screen_dir ZERO =
# push straight away from Veyl
static func get_move(kind: String, airborne: bool, moveset: String = "sword") -> Dictionary:

	if airborne:
		kind = "aerial"

	var move = MOVES[kind].duplicate()
	move.merge(MOVESETS.get(moveset, {}).get(kind, {}), true)
	move["name"] = kind
	return move
