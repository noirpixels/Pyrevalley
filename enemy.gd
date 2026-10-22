extends CharacterBody2D

# What every creature shares, side-on: gravity, being shoved, launched
# and dazed by Veyl's hits, a telegraphed attack (a wind-up you can read,
# then the strike), and dying into embers and loot. Each kind
# (mossling.gd, ember_wolf.gd, ashcrawler.gd, boss.gd) sets its numbers
# and fills in how it moves and attacks.
# The origin is at the creature's feet. It never leaves its room.

signal died_out(creature)

enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, HURT, DIZZY, DEAD }

const GRAVITY = 2400.0
const MAX_FALL = 1200.0
# Near the top of a launch it hangs, so the lift reads and can be followed
const LAUNCH_HANG_SPEED = 220.0
const LAUNCH_HANG_GRAVITY = 0.35
const DIZZY_DRAIN = 30.0
const DIZZY_IMMUNITY = 3.0
const HURT_TIME = 0.28
const LAYER_CREATURE = 8

var kind_name: String = "Mossling"
var max_health: float = 40.0
var health: float = 40.0
var defense: float = 2.0
var attack: float = 8.0
var speed: float = 120.0
# Heavier creatures are shoved and launched less
var weight: float = 1.0
var width: float = 50.0
var height: float = 50.0
var detect_range: float = 520.0
var windup_time: float = 0.5
var strike_time: float = 0.3
var recover_time: float = 0.6
var attack_cooldown: float = 1.0
var dizzy_threshold: float = 60.0
var dizzy_time: float = 1.8
var launchable: bool = true
var staggerable: bool = true
var sprite_path: String = "res://Creatures/mossling.png"
var sprite_scale: float = 0.7
# [item, chance] rolled on death
var drops = []

var state: State = State.IDLE
var state_timer: float = 0.0
var cooldown_timer: float = 0.0
var facing: float = -1.0
var launched: bool = false
var launch_grace: float = 0.0
var knockback: float = 0.0
var dizzy: float = 0.0
var dizzy_immunity: float = 0.0
var flash_timer: float = 0.0
var target: Node2D = null
var room: Node2D
var id: String = ""
var home: Vector2
# Players this strike has already hit, so one swing can't hit twice
var struck = []
# A guest's copy of a host creature: shown, never simulated (net_sync.gd)
var puppet: bool = false

var sprite: Sprite2D
var glow: Sprite2D
var squash: Vector2 = Vector2.ONE
var time: float = 0.0


func setup(in_room: Node2D, at: Vector2, creature_id: String):

	room = in_room
	home = at
	id = creature_id
	position = at


func _ready():

	add_to_group("creatures")
	collision_layer = LAYER_CREATURE
	collision_mask = 1 | 2
	floor_snap_length = 8.0
	health = max_health
	var shape = RectangleShape2D.new()
	shape.size = Vector2(width * 0.8, height * 0.9)
	var col = CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -height * 0.45)
	add_child(col)

	sprite = Sprite2D.new()
	sprite.texture = load(sprite_path)
	sprite.centered = false
	sprite.offset = Vector2(-sprite.texture.get_width() / 2.0, -sprite.texture.get_height())
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	add_child(sprite)
	var glow_path = sprite_path.replace(".png", "_glow.png")
	if ResourceLoader.exists(glow_path):
		glow = Sprite2D.new()
		glow.texture = load(glow_path)
		glow.centered = false
		glow.offset = sprite.offset
		var add = CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add
		sprite.add_child(glow)


func is_dead() -> bool:
	return state == State.DEAD


func is_dizzy() -> bool:
	return state == State.DIZZY


func hurt_rect() -> Rect2:
	return Rect2(global_position - Vector2(width / 2.0, height), Vector2(width, height))


# ============================================================
# EACH FRAME
# ============================================================

func _physics_process(delta):

	if puppet:
		return
	time += delta
	state_timer -= delta
	cooldown_timer = max(cooldown_timer - delta, 0.0)
	dizzy_immunity = max(dizzy_immunity - delta, 0.0)
	launch_grace = max(launch_grace - delta, 0.0)
	flash_timer = max(flash_timer - delta, 0.0)
	dizzy = max(dizzy - DIZZY_DRAIN * delta, 0.0)

	if state == State.DEAD:
		return

	var g = GRAVITY * gravity_scale()
	if launched and abs(velocity.y) < LAUNCH_HANG_SPEED:
		g *= LAUNCH_HANG_GRAVITY
	velocity.y = min(velocity.y + g * delta, MAX_FALL)

	target = pick_target()
	var move_x = 0.0
	match state:
		State.IDLE:
			move_x = idle_movement()
			if target:
				enter_state(State.CHASE)
		State.CHASE:
			if target == null:
				enter_state(State.IDLE)
			else:
				var dx = target.global_position.x - global_position.x
				facing = sign(dx) if abs(dx) > 4.0 else facing
				move_x = chase_movement(dx)
				if cooldown_timer <= 0.0 and wants_to_attack(dx, target.global_position.y - global_position.y):
					enter_state(State.WINDUP)
		State.WINDUP:
			move_x = 0.0
			if state_timer <= 0.0:
				enter_state(State.STRIKE)
		State.STRIKE:
			move_x = strike_movement(delta)
			check_strike_hits()
			if state_timer <= 0.0:
				enter_state(State.RECOVER)
		State.RECOVER:
			if state_timer <= 0.0:
				cooldown_timer = followup_cooldown()
				enter_state(State.CHASE)
		State.HURT, State.DIZZY:
			if state_timer <= 0.0 and not launched:
				enter_state(State.CHASE)

	if state in [State.HURT, State.DIZZY] or launched:
		velocity.x = knockback
	elif state == State.STRIKE:
		velocity.x = move_x + knockback
	else:
		velocity.x = move_toward(velocity.x, move_x, speed * 8.0 * delta) + knockback
	knockback = move_toward(knockback, 0.0, 2200.0 * delta)
	move_and_slide()
	keep_in_room()

	if launched and launch_grace <= 0.0 and is_on_floor():
		launched = false
		squash = Vector2(1.3, 0.7)
		if state == State.HURT:
			state_timer = 0.2


func gravity_scale() -> float:
	return 1.0


func _process(delta):

	if state == State.DEAD:
		return
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-10.0 * delta))
	var pose = Vector2.ONE
	var tint = Color.WHITE
	match state:
		State.WINDUP:
			# Gathers itself and glows: the tell
			var k = 1.0 - clamp(state_timer / windup_time, 0.0, 1.0)
			pose = Vector2(1.0 + 0.12 * k, 1.0 - 0.15 * k)
			tint = Color(1.0, 1.0 - 0.35 * k, 1.0 - 0.6 * k)
		State.DIZZY:
			sprite.rotation = sin(time * 9.0) * 0.12
		_:
			sprite.rotation = lerp(sprite.rotation, 0.0, 0.3)
	if not is_on_floor() and not launched:
		pose *= Vector2(0.92, 1.08)
	sprite.scale = Vector2(sprite_scale * squash.x * pose.x, sprite_scale * squash.y * pose.y)
	sprite.flip_h = facing < 0.0
	if flash_timer > 0.0:
		tint = Color(3.0, 3.0, 3.0)
	sprite.modulate = tint
	if glow:
		glow.modulate.a = 0.6 + 0.4 * sin(time * 3.0) + (0.8 if state == State.WINDUP else 0.0)
	queue_redraw()


# A small health bar once hurt, and the daze stars
func _draw():

	if state == State.DEAD or health >= max_health:
		return
	var w = max(width, 50.0)
	var top = -height * 1.0 - 14.0
	draw_rect(Rect2(-w / 2.0, top, w, 6), Color(0.04, 0.03, 0.04, 0.85))
	draw_rect(Rect2(-w / 2.0, top, w * health / max_health, 6), Color(0.9, 0.35, 0.1))
	if state == State.DIZZY:
		for i in 3:
			var a = time * 4.0 + i * TAU / 3.0
			draw_circle(Vector2(cos(a) * 22.0, top - 12.0 + sin(a) * 6.0), 4.0, Color(1.0, 0.85, 0.4))


func keep_in_room():

	if room == null:
		return
	var r: Rect2 = room.rect
	var half = width / 2.0
	if global_position.x < r.position.x + half or global_position.x > r.end.x - half:
		global_position.x = clamp(global_position.x, r.position.x + half, r.end.x - half)
		knockback = 0.0
	if global_position.y > r.end.y + 200.0:
		global_position = home
		velocity = Vector2.ZERO


func pick_target() -> Node2D:

	var best: Node2D = null
	var best_d = detect_range
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or (room and not room.contains(p.global_position + Vector2(0, -40))):
			continue
		var d = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func enter_state(new_state: State):

	state = new_state
	match new_state:
		State.WINDUP:
			state_timer = windup_time
			Sfx.play("enemy_windup", -8.0)
			begin_windup()
		State.STRIKE:
			state_timer = strike_time
			struck = []
			Sfx.play("enemy_attack", -6.0)
			begin_strike()
		State.RECOVER:
			state_timer = recover_time
		State.HURT:
			state_timer = HURT_TIME
		State.DIZZY:
			state_timer = dizzy_time


# ---- What each kind fills in ----

func followup_cooldown() -> float:
	return attack_cooldown


func idle_movement() -> float:
	return 0.0


func chase_movement(dx: float) -> float:
	return sign(dx) * speed if abs(dx) > width else 0.0


func wants_to_attack(dx: float, _dy: float) -> bool:
	return abs(dx) < width + 60.0


func begin_windup():
	pass


func begin_strike():
	pass


func strike_movement(_delta: float) -> float:
	return 0.0


# The area this strike hurts this frame (world space); empty for none
func strike_rect() -> Rect2:
	return Rect2()


func check_strike_hits():

	var r = strike_rect()
	if r.size == Vector2.ZERO:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p in struck or p.dead:
			continue
		var body = Rect2(p.global_position - Vector2(16, 92), Vector2(32, 92))
		if r.intersects(body):
			struck.append(p)
			NetSync.hurt_player(p, attack, global_position)


# ============================================================
# BEING HIT
# ============================================================

func receive_hit(amount: float, from: Vector2, push: Vector2, dizzy_gain: float, launch: float):

	if state == State.DEAD:
		return
	health -= amount
	flash_timer = 0.08
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.number(global_position + Vector2(0, -height - 20), str(roundi(amount)), Color(1.0, 0.85, 0.6))
	if health <= 0.0:
		die()
		return

	knockback = push.x / weight
	facing = sign(from.x - global_position.x) if from.x != global_position.x else facing
	if launch > 0.0 and launchable and not launched:
		velocity.y = -launch / sqrt(weight)
		launched = true
		launch_grace = 0.1
		enter_state(State.HURT)
	elif launch < 0.0 and launched:
		velocity.y = -launch
	elif staggerable and state != State.DIZZY:
		# A hit interrupts anything but a strike already swinging
		if state != State.STRIKE:
			enter_state(State.HURT)

	if state != State.DIZZY and dizzy_immunity <= 0.0:
		dizzy += dizzy_gain
		if dizzy >= dizzy_threshold:
			dizzy = 0.0
			dizzy_immunity = dizzy_time + DIZZY_IMMUNITY
			enter_state(State.DIZZY)
			Sfx.play("enemy_land", -4.0, 1.3)
	squash = Vector2(0.8, 1.2)


func die():

	state = State.DEAD
	collision_layer = 0
	velocity = Vector2.ZERO
	GameState.killed[id] = true
	Sfx.play("enemy_death", -4.0)
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.burst(global_position + Vector2(0, -height / 2.0), Color(1.0, 0.5, 0.15), 26, 420.0)
	drop_loot()
	died_out.emit(self)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.4, 0.1, 0.0), 0.45)
	tween.tween_callback(hide)


func drop_loot():

	var spawner = get_tree().get_first_node_in_group("spawner")
	if spawner == null:
		return
	for d in drops:
		if randf() < d[1]:
			spawner.drop_item(d[0], global_position + Vector2(0, -height / 2.0))


# Already dead when the world was built (killed before a reload)
func die_quietly():

	state = State.DEAD
	collision_layer = 0
	hide()


# Back to life where it started, after Veyl rests or dies
func revive():

	state = State.IDLE
	health = max_health
	global_position = home
	velocity = Vector2.ZERO
	knockback = 0.0
	launched = false
	dizzy = 0.0
	collision_layer = LAYER_CREATURE
	sprite.modulate = Color.WHITE
	show()
