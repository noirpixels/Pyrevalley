extends CharacterBody2D

# Veyl, side-on. Movement is tuned for platforming: quick acceleration,
# coyote time and a jump buffer, a shorter hop if Jump is let go early, a
# dash (once per jump in the air), dropping through ledges with Down +
# Jump, and the Cinderwing's second jump once it's found. Fighting lives in
# veyl_combat.gd, digging in veyl_dig.gd.
# The origin is at Veyl's feet.

signal health_changed(current: float, maximum: float)
signal died
signal respawned

const VeylAnimator = preload("res://veyl_animator.gd")

const RUN_SPEED = 380.0
const GROUND_ACCEL = 3400.0
const AIR_ACCEL = 2300.0
const FRICTION = 3800.0
const JUMP_VELOCITY = 830.0
const DOUBLE_JUMP_VELOCITY = 800.0
# Letting go of Jump early keeps this much of the rise
const JUMP_CUT = 0.45
const GRAVITY = 2400.0
# Gentler gravity near the top of a held jump, for a little hang
const APEX_SPEED = 140.0
const APEX_GRAVITY = 0.6
const MAX_FALL = 1150.0
const COYOTE_TIME = 0.1
const JUMP_BUFFER = 0.12
const DASH_SPEED = 960.0
const DASH_TIME = 0.16
const DASH_COOLDOWN = 0.4
# Small ledges in dug ground are walked up rather than blocking
const STEP_HEIGHT = 16.0
const DROP_TIME = 0.25
# Holding Down this long on a ledge drops through it too
const DROP_HOLD = 0.25
const HURT_INVULN = 0.7
const PIT_DAMAGE = 15.0
# The Mosswoven charm's mending, per second
const MEND_RATE = 0.8

const LAYER_PLAYER = 4

var health: float = 100.0
var max_health: float = 100.0
var dead: bool = false
var facing: float = 1.0
var input_blocked: bool = false
# A remote player's Veyl, moved by the network (net_sync.gd)
var remote: bool = false
var peer_id: int = 1

var coyote_timer: float = 0.0
var buffer_timer: float = 0.0
var air_jumps: int = 0
var air_dash_ready: bool = true
var dash_timer: float = 0.0
var dash_cooldown: float = 0.0
var dash_dir: float = 1.0
var invuln_timer: float = 0.0
var drop_timer: float = 0.0
var down_held: float = 0.0
var knockback: Vector2 = Vector2.ZERO
var jump_held: bool = false
# A remote Veyl eases toward where its player last said it was
var net_position: Vector2
var net_on_floor: bool = true
# Ground to put Veyl back on after an ember pit
var safe_position: Vector2
var spawn_position: Vector2

var animator: VeylAnimator
var combat: Node
var digger: Node


func _ready():

	collision_layer = 0 if remote else LAYER_PLAYER
	collision_mask = 0 if remote else 1 | 2
	floor_snap_length = 10.0
	floor_max_angle = deg_to_rad(50.0)
	var shape = CapsuleShape2D.new()
	shape.radius = 16.0
	shape.height = 92.0
	var col = CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -46)
	add_child(col)

	animator = VeylAnimator.new(self)
	add_child(animator)
	if ResourceLoader.exists("res://veyl_combat.gd"):
		combat = load("res://veyl_combat.gd").new()
		add_child(combat)
	if ResourceLoader.exists("res://veyl_dig.gd"):
		digger = load("res://veyl_dig.gd").new()
		add_child(digger)
	safe_position = global_position
	spawn_position = global_position
	add_to_group("remote_players" if remote else "player")
	add_to_group("players")
	refresh_held()


# What's in Veyl's hand: the weapon, or nothing for fists
func refresh_held():

	var weapon = GameState.gear.get("weapon") if not remote else null
	if weapon:
		animator.set_held(weapon["type"], weapon["material"])
	else:
		animator.set_held("", "")


func grounded() -> bool:
	return net_on_floor if remote else is_on_floor()


# ============================================================
# NETWORK (net_sync.gd)
# ============================================================

func net_state() -> Array:

	var flags = (1 if is_on_floor() else 0) | (2 if dead else 0) | (4 if dash_timer > 0.0 else 0)
	var weapon = GameState.gear.get("weapon")
	var held = (weapon["type"] + "/" + weapon["material"]) if weapon else ""
	return [global_position, velocity, facing, flags, held]


func apply_net_state(state: Array):

	net_position = state[0]
	velocity = state[1]
	facing = state[2]
	var flags: int = state[3]
	net_on_floor = flags & 1 != 0
	var was_dead = dead
	dead = flags & 2 != 0
	dash_timer = 0.1 if flags & 4 else 0.0
	if was_dead and not dead:
		global_position = net_position
	var held: String = state[4]
	if held != get_meta("held", "-"):
		set_meta("held", held)
		var parts = held.split("/")
		animator.set_held(parts[0] if held != "" else "", parts[1] if parts.size() > 1 else "")


func remote_fx(kind: String, args: Array):

	match kind:
		"swing":
			animator.swing(args[0])
			add_child(load("res://slash_effect.gd").new(args[1], args[2], facing))
		"hurt":
			animator.hurt()
			flash(Color(1.0, 0.35, 0.3))


func add_name_label(text: String):

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.position = Vector2(-60, -140)
	label.size = Vector2(120, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	animator.sprite.modulate = Color(0.75, 0.82, 1.0)


func _process(delta):

	if remote:
		if global_position.distance_to(net_position) > 300.0:
			global_position = net_position
		global_position = global_position.lerp(net_position, 1.0 - exp(-14.0 * delta))


func _physics_process(delta):

	if remote:
		return

	coyote_timer = max(coyote_timer - delta, 0.0)
	buffer_timer = max(buffer_timer - delta, 0.0)
	dash_timer = max(dash_timer - delta, 0.0)
	dash_cooldown = max(dash_cooldown - delta, 0.0)
	invuln_timer = max(invuln_timer - delta, 0.0)
	if drop_timer > 0.0:
		drop_timer -= delta
		if drop_timer <= 0.0:
			set_collision_mask_value(2, true)

	if dead:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL)
		move_and_slide()
		return

	var dir = 0.0 if input_blocked else Input.get_axis("move_left", "move_right")
	var on_floor = is_on_floor()
	var charm = GameState.gear.get("charm")
	if charm and charm["material"] == "Mosswoven" and health < max_health:
		heal(MEND_RATE * delta)

	if on_floor:
		coyote_timer = COYOTE_TIME
		air_jumps = 1 if GameState.has_ability("cinderwing") else 0
		air_dash_ready = true
		if on_safe_ground():
			safe_position = global_position

	if not input_blocked:
		if Input.is_action_just_pressed("jump"):
			buffer_timer = JUMP_BUFFER
		if Input.is_action_just_pressed("dash"):
			try_dash(dir)

	# Down + Jump (or just holding Down) on a ledge drops through it
	down_held = down_held + delta if on_floor and not input_blocked and Input.is_action_pressed("move_down") and dir == 0.0 else 0.0
	if on_floor and on_ledge() and ((buffer_timer > 0.0 and Input.is_action_pressed("move_down")) or down_held > DROP_HOLD):
		down_held = 0.0
		buffer_timer = 0.0
		drop_timer = DROP_TIME
		set_collision_mask_value(2, false)
		position.y += 2.0
	elif buffer_timer > 0.0 and (on_floor or coyote_timer > 0.0):
		jump(JUMP_VELOCITY)
	elif buffer_timer > 0.0 and air_jumps > 0 and dash_timer <= 0.0:
		air_jumps -= 1
		jump(DOUBLE_JUMP_VELOCITY)
		cinder_burst()

	# Let go early for a short hop
	if jump_held and not Input.is_action_pressed("jump"):
		jump_held = false
		if velocity.y < 0.0:
			velocity.y *= JUMP_CUT

	if dash_timer > 0.0:
		velocity.x = dash_dir * DASH_SPEED
		velocity.y = 0.0
	else:
		var accel = GROUND_ACCEL if on_floor else AIR_ACCEL
		if dir != 0.0:
			velocity.x = move_toward(velocity.x, dir * RUN_SPEED, accel * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, (FRICTION if on_floor else AIR_ACCEL * 0.5) * delta)
		var g = GRAVITY
		if jump_held and abs(velocity.y) < APEX_SPEED:
			g *= APEX_GRAVITY
		velocity.y = min(velocity.y + g * delta, MAX_FALL)

	var attacking = combat != null and combat.busy()
	if dir != 0.0 and dash_timer <= 0.0 and not attacking:
		facing = sign(dir)

	velocity += knockback
	var before = global_position
	move_and_slide()
	velocity -= knockback
	knockback = knockback.move_toward(Vector2.ZERO, 2600.0 * delta)

	if dir != 0.0 and is_on_floor() and is_on_wall():
		step_up(dir, before)


func jump(speed: float):

	velocity.y = -speed
	buffer_timer = 0.0
	coyote_timer = 0.0
	jump_held = true
	Sfx.play("dash", -12.0, 1.4)


func try_dash(dir: float):

	if dash_cooldown > 0.0 or (not is_on_floor() and not air_dash_ready):
		return
	dash_dir = dir if dir != 0.0 else facing
	facing = dash_dir
	dash_timer = DASH_TIME
	dash_cooldown = DASH_COOLDOWN
	invuln_timer = max(invuln_timer, DASH_TIME)
	if not is_on_floor():
		air_dash_ready = false
	Sfx.play("dash", -6.0)


# Aerial hits give the jump and dash back (veyl_combat.gd)
func refresh_air():

	air_dash_ready = true
	if GameState.has_ability("cinderwing"):
		air_jumps = 1


# Solid footing that isn't an ember pit, a little in from any edge
func on_safe_ground() -> bool:

	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return true
	for dx in [-20.0, 0.0, 20.0]:
		var m = game.ground_material(global_position + Vector2(dx, 6))
		if m == 3 or (m == -1 and not on_ledge()):
			return false
	return true


func on_ledge() -> bool:

	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -4), global_position + Vector2(0, 8), 2)
	return not space.intersect_ray(query).is_empty()


# Walk up small steps in dug ground instead of stopping against them
func step_up(dir: float, before: Vector2):

	var up = Transform2D(0.0, global_position + Vector2(0, -STEP_HEIGHT))
	if not test_move(up, Vector2(dir * 6.0, 0)) and not test_move(global_transform, Vector2(0, -STEP_HEIGHT)):
		global_position += Vector2(dir * 4.0, -STEP_HEIGHT)
		velocity.x = dir * RUN_SPEED * 0.8


# A burst of embers under Veyl's feet for the Cinderwing's second jump
func cinder_burst():

	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.burst(global_position, Color(1.0, 0.55, 0.2), 16, 260.0)
	Sfx.play("checkpoint", -10.0, 1.6)


# ============================================================
# HEALTH
# ============================================================

func take_damage(amount: float, from: Vector2, push: float = 420.0) -> bool:

	if dead or invuln_timer > 0.0:
		return false
	health = max(health - amount, 0.0)
	invuln_timer = HURT_INVULN
	var away = sign(global_position.x - from.x)
	if away == 0.0:
		away = -facing
	knockback = Vector2(away * push, 0)
	velocity.y = min(velocity.y, -260.0)
	health_changed.emit(health, max_health)
	animator.hurt()
	flash(Color(1.0, 0.35, 0.3))
	NetSync.share_player_fx("hurt", [])
	Sfx.play("player_hurt")
	Pad.rumble(0.4, 0.7, 0.2)
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.number(global_position + Vector2(0, -110), str(roundi(amount)), Color(1.0, 0.35, 0.3))
	if combat:
		combat.drop_combo()
	if health <= 0.0:
		die()
	return true


func heal(amount: float):

	if dead:
		return
	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)


func burn_in_pit():

	if dead:
		return
	invuln_timer = 0.0
	take_damage(PIT_DAMAGE, global_position + Vector2(0, 10), 0.0)
	if not dead:
		global_position = safe_position
		velocity = Vector2.ZERO
		knockback = Vector2.ZERO


func flash(color: Color):

	animator.modulate = color
	create_tween().tween_property(animator, "modulate", Color.WHITE, 0.3)


func die():

	dead = true
	velocity.x = 0.0
	died.emit()


func respawn_at(at: Vector2):

	global_position = at
	velocity = Vector2.ZERO
	knockback = Vector2.ZERO
	health = max_health
	dead = false
	invuln_timer = 1.0
	animator.lean = 0.0
	health_changed.emit(health, max_health)
	respawned.emit()
