extends Node

# The Ember Shade: a darker Veyl that waits in the Proving Ring and duels
# whoever walks in. It's a real Veyl (player.tscn in bot mode), so it
# swings, chains combos, lunges and dodges with exactly the player's moves;
# this script only decides what it does, a few times a second, like a
# player reacting rather than a machine reading inputs.
# Run by the host (or a solo game); guests see it like another player.

const PlayerScene = preload("res://player.tscn")

# Seconds between decisions; also how slowly it reacts
const THINK_EVERY = 0.14
# Closes to this distance before swinging (the sword reaches about 7.5)
const STRIKE_DIST = 5.0
# Backs off when closer than this, so it isn't swinging from inside you
const CROWD_DIST = 2.2
# Chance to dash aside when it sees a swing coming
const DODGE_CHANCE = 0.4
# How recent a swing it can still react to
const DODGE_WINDOW = 0.25
# Chance to hold back a beat when it could swing, leaving openings
const HESITATE_CHANCE = 0.3
# Back to full health after this long with nobody to fight
const REST_TIME = 6.0
const RESPAWN_DELAY = 3.0

var veyl: CharacterBody3D
var ring: Node3D
var think_left: float = 0.0
var idle_time: float = 0.0
var circle_side: float = 1.0
var combo_step: int = 0


func _ready():

	ring = get_parent()
	veyl = PlayerScene.instantiate()
	# Before it enters the tree, or its camera would take over the view
	veyl.find_child("MainGameCamera").current = false
	veyl.bot = true
	veyl.peer_id = NetSync.BOT_ID
	veyl.name = "EmberShade"
	veyl.position = ring.to_global(Vector3(0, 6.0, 0))
	veyl.died.connect(_on_died)
	# A sibling of the players in the scene root, not under the rotated level
	get_tree().current_scene.add_child.call_deferred(veyl)


func _physics_process(delta):

	if veyl == null or not veyl.is_inside_tree() or veyl.dead:
		return
	think_left -= delta
	if think_left > 0.0:
		return
	think_left = THINK_EVERY * randf_range(0.8, 1.2)
	think()


func think():

	var target = pick_target()
	if target == null:
		rest()
		return
	idle_time = 0.0

	var to = flat(target.global_position - veyl.global_position)
	var dist = to.length()
	var dir = to / dist if dist > 0.01 else veyl.aim_dir
	veyl.aim_dir = dir

	# See a swing coming and sometimes step out of it
	var since_swing = (Time.get_ticks_msec() - target.last_swing_msec) / 1000.0
	if since_swing < DODGE_WINDOW and dist < STRIKE_DIST + 2.5 and veyl.dash_cooldown_timer <= 0.0 and randf() < DODGE_CHANCE:
		dodge(dir)
		return

	if dist > STRIKE_DIST:
		veyl.bot_move = dir
		return

	if dist < CROWD_DIST:
		veyl.bot_move = -dir
		return

	if veyl.attack_timer <= 0.0 and randf() > HESITATE_CHANCE:
		veyl.bot_move = Vector3.ZERO
		veyl.request_attack(next_move())
		return

	# Waiting on its own swing: circle, so it isn't a standing target
	if randf() < 0.05:
		circle_side = -circle_side
	veyl.bot_move = (dir.cross(Vector3.UP) * circle_side).normalized() * 0.6


# The nearest Veyl standing inside the ring
func pick_target() -> Node3D:

	var best: Node3D = null
	var best_dist = INF
	for other in NetSync.all_players():
		# Walk-through, like players are for each other
		veyl.add_collision_exception_with(other)
		if other.dead or not ring.contains(other.global_position):
			continue
		var dist = other.global_position.distance_to(veyl.global_position)
		if dist < best_dist:
			best = other
			best_dist = dist
	return best


# Alternating cuts, finished with a slam once the chain is long enough;
# now and then it opens with a launch instead
func next_move() -> String:

	if veyl.combo.count == 0:
		combo_step = 0
		if randf() < 0.2:
			return "up"
	combo_step += 1
	if veyl.combo.count + 1 >= GameState.max_combo:
		return "down"
	return "left" if combo_step % 2 == 1 else "right"


func dodge(toward: Vector3):

	circle_side = 1.0 if randf() < 0.5 else -1.0
	var aside = (toward.cross(Vector3.UP) * circle_side - toward * 0.4).normalized()
	# try_dash goes the way it's moving
	veyl.velocity.x = aside.x * veyl.speed
	veyl.velocity.z = aside.z * veyl.speed
	veyl.bot_move = aside
	veyl.try_dash()


# Nobody to fight: drift back to the middle and recover
func rest():

	var home = ring.to_global(Vector3.ZERO)
	var to_home = flat(home - veyl.global_position)
	veyl.bot_move = to_home.normalized() * 0.5 if to_home.length() > 3.0 else Vector3.ZERO
	idle_time += THINK_EVERY
	if idle_time > REST_TIME and veyl.health < veyl.max_health:
		veyl.heal(veyl.max_health - veyl.health)


func _on_died():

	veyl.bot_move = Vector3.ZERO
	await get_tree().create_timer(RESPAWN_DELAY, false).timeout
	if is_instance_valid(veyl):
		veyl.respawn()


func _exit_tree():

	if is_instance_valid(veyl):
		veyl.queue_free()


func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
