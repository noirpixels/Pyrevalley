extends RefCounted

# Veyl's moves, picked by how the left mouse button is used:
#   click            JAB      light hit that sets the target spinning
#   drag left/right  LEFT / RIGHT  shove the target that way (right hits harder)
#   drag up          UP       launches the target into the air
#   drag down        SLASH    drives the target straight back
#   drag diagonally  DIAGONAL shove along the drag, lifting it a little if upward
#   long drag        any of the above, wide and powerful
#   hold, release    CHARGED  heavy hit
#   while airborne   AERIAL   slams launched targets down for a critical hit
#
# Numbers multiply the weapon's damage, range and cooldown. push/launch are
# speeds handed to the enemy; spin and dizzy feed its impact meters, which
# are separate from its health (see enemy.gd apply_impact).

const TAP_FRACTION = 0.025   # of viewport height: shorter drags are clicks
const LONG_FRACTION = 0.2    # of viewport height: longer drags are powerful
const CHARGE_TIME = 0.55
# How close to horizontal/vertical a drag must be to count as straight
const STRAIGHT = 0.9

const MOVES = {
	"jab":      {"damage": 0.7, "arc": 70.0,  "range": 0.9,  "cooldown": 0.7, "push": 3.0,  "spin": 16.0, "dizzy": 10.0, "launch": 0.0, "side": 0},
	"left":     {"damage": 1.0, "arc": 140.0, "range": 1.0,  "cooldown": 1.0, "push": 10.0, "spin": -6.0, "dizzy": 18.0, "launch": 0.0, "side": -1},
	"right":    {"damage": 1.0, "arc": 140.0, "range": 1.0,  "cooldown": 1.0, "push": 13.0, "spin": 6.0,  "dizzy": 18.0, "launch": 0.0, "side": 1},
	"up":       {"damage": 0.9, "arc": 110.0, "range": 1.0,  "cooldown": 1.2, "push": 2.0,  "spin": 0.0,  "dizzy": 12.0, "launch": 9.0, "side": 0},
	"slash":    {"damage": 1.0, "arc": 120.0, "range": 1.0,  "cooldown": 1.0, "push": 9.0,  "spin": 0.0,  "dizzy": 12.0, "launch": 0.0, "side": 0},
	"diagonal": {"damage": 1.1, "arc": 90.0,  "range": 1.15, "cooldown": 1.0, "push": 8.0,  "spin": 3.0,  "dizzy": 15.0, "launch": 0.0, "side": 0},
	"charged":  {"damage": 2.2, "arc": 160.0, "range": 1.25, "cooldown": 1.6, "push": 16.0, "spin": 8.0,  "dizzy": 35.0, "launch": 0.0, "side": 0},
	"aerial":   {"damage": 1.0, "arc": 140.0, "range": 1.0,  "cooldown": 1.0, "push": 4.0,  "spin": 0.0,  "dizzy": 20.0, "launch": -20.0, "side": 0},
}

# Critical multiplier for an aerial hit on a launched target
const AERIAL_CRIT = 2.5


# drag is in screen pixels (y down). Returns a copy of the move with:
#   name, power (long drag), screen_dir (Vector2, ZERO = push straight away)
static func classify(drag: Vector2, held: float, view_height: float, airborne: bool) -> Dictionary:

	var length = drag.length()
	var dir = drag / length if length > 0.0 else Vector2.ZERO
	var kind: String

	if airborne:
		kind = "aerial"
	elif length < view_height * TAP_FRACTION:
		kind = "charged" if held >= CHARGE_TIME else "jab"
	elif abs(dir.x) >= STRAIGHT:
		kind = "left" if dir.x < 0.0 else "right"
	elif dir.y <= -STRAIGHT:
		kind = "up"
	elif dir.y >= STRAIGHT:
		kind = "slash"
	else:
		kind = "diagonal"

	var move = MOVES[kind].duplicate()
	move["name"] = kind
	move["screen_dir"] = Vector2.ZERO
	move["power"] = false

	match kind:
		"left", "right":
			move["screen_dir"] = Vector2(sign(dir.x), 0.0)
		"diagonal":
			move["screen_dir"] = dir
			move["side"] = -1 if dir.x < 0.0 else 1
			# Upward diagonals lift a little
			if dir.y < 0.0:
				move["launch"] = 5.0

	# A long, sweeping drag: wider and heavier, but slower to recover
	if kind != "aerial" and kind != "jab" and kind != "charged" and length >= view_height * LONG_FRACTION:
		move["power"] = true
		move["damage"] *= 1.4
		move["push"] *= 1.4
		move["dizzy"] *= 1.3
		move["arc"] = min(move["arc"] + 70.0, 220.0)
		move["cooldown"] *= 1.5

	return move
