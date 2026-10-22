extends "res://enemy.gd"

# The Ashbound, side-on. The same wind-up and strike as any creature, with
# three attacks, each drawn on the ground before it lands:
#   SLAM      fists into the floor: shockwaves race out both ways (jump them)
#   CHARGE    head down across the arena to the wall (dash through it)
#   ERUPTION  burning columns burst up under and around Veyl (move off them)
# Below half health it roars, throws Veyl back, catches fire and fights
# faster, slamming twice. It's too heavy to launch fully: a rising cut
# heaves it partway, only between attacks, and not again for a while.
# The arena seals while it lives and Veyl is inside.

const Telegraph = preload("res://telegraph.gd")
const Shockwave = preload("res://shockwave.gd")
const EmberWall = preload("res://ember_wall.gd")

const CHARGE_SPEED = 1150.0
const ERUPTION_DELAY = 1.0
const ERUPTION_WIDTH = 90.0
const ERUPTION_HEIGHT = 340.0
const LAUNCH_SCALE = 0.6
const LAUNCH_REST = 4.0
const PHASE_SHIFT_TIME = 1.6

var attack_kind: String = "slam"
var enraged: bool = false
var queued_slam: bool = false
# This slam is the enraged follow-up, so it doesn't queue another
var followup: bool = false
var engaged: bool = false
var launch_rest: float = 0.0
var phase_shift_left: float = 0.0
var seal: Node2D
var last_kinds = []


func _init():

	kind_name = "The Ashbound"
	max_health = 620.0
	defense = 6.0
	attack = 18.0
	speed = 170.0
	weight = 3.5
	width = 190.0
	height = 270.0
	detect_range = 2600.0
	windup_time = 0.7
	recover_time = 0.9
	attack_cooldown = 0.9
	dizzy_threshold = 240.0
	dizzy_time = 1.4
	staggerable = false
	sprite_path = "res://Creatures/ashbound.png"
	sprite_scale = 0.75
	drops = []


func _physics_process(delta):

	launch_rest = max(launch_rest - delta, 0.0)
	phase_shift_left = max(phase_shift_left - delta, 0.0)
	super(delta)
	update_engagement()


# The fight starts when Veyl comes in: the door seals behind vem
func update_engagement():

	if state == State.DEAD:
		return
	var inside = false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and room.contains(p.global_position + Vector2(0, -40)):
			inside = true
	if inside and not engaged:
		engaged = true
		GameState.boss_fight = true
		seal_arena(true)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.banner("THE ASHBOUND", "It walled the Hollow off. It will not let you pass.")
			hud.show_boss(true)
			hud.set_boss_health(health, max_health)
		Sfx.play("boss_roar")
		Sfx.play_music("boss")
	elif not inside and engaged:
		engaged = false
		GameState.boss_fight = false
		seal_arena(false)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_boss(false)


func seal_arena(on: bool):

	if on and seal == null:
		seal = EmberWall.new(Vector2(80, 180))
		room.add_child(seal)
		seal.position = Vector2(40, 480 + 90)
	elif not on and seal:
		seal.fade_out()
		seal = null


func followup_cooldown() -> float:
	return 0.15 if queued_slam else attack_cooldown * (0.7 if enraged else 1.0)


func pick_target() -> Node2D:
	return super() if engaged or state == State.IDLE else null


func chase_movement(dx: float) -> float:
	return sign(dx) * speed * (1.25 if enraged else 1.0) if abs(dx) > 160.0 else 0.0


func wants_to_attack(dx: float, _dy: float) -> bool:
	return engaged and (abs(dx) < 900.0 or queued_slam)


func begin_windup():

	followup = queued_slam
	if queued_slam:
		attack_kind = "slam"
		queued_slam = false
		state_timer = 0.45
	else:
		attack_kind = choose_attack()
		state_timer = {"slam": 0.75, "charge": 0.65, "eruption": 0.6}[attack_kind] * (0.85 if enraged else 1.0)
	var floor_y = room.rect.position.y + 640.0
	match attack_kind:
		"slam":
			add_warning(Rect2(global_position.x - 260, floor_y - 40, 520, 40), state_timer)
			strike_time = 0.35
		"charge":
			var to_x = room.rect.position.x + 80.0 if facing < 0.0 else room.rect.end.x - 80.0
			add_warning(Rect2(min(global_position.x, to_x), floor_y - height, abs(to_x - global_position.x), height), state_timer)
			strike_time = 1.6
		"eruption":
			strike_time = ERUPTION_DELAY + 0.3
			start_eruptions(floor_y)


# Never the same attack three times running
func choose_attack() -> String:

	var options = ["slam", "charge", "eruption"]
	if last_kinds.size() >= 2 and last_kinds[-1] == last_kinds[-2]:
		options.erase(last_kinds[-1])
	var dx = abs(target.global_position.x - global_position.x) if target else 0.0
	var kind = options[randi() % options.size()]
	if dx < 300.0 and "slam" in options and randf() < 0.5:
		kind = "slam"
	last_kinds.append(kind)
	if last_kinds.size() > 3:
		last_kinds.pop_front()
	return kind


func add_warning(r: Rect2, seconds: float):

	var t = Telegraph.new(r, seconds)
	get_parent().add_child(t)


func begin_strike():

	Sfx.play("boss_attack")
	match attack_kind:
		"slam":
			squash = Vector2(1.25, 0.75)
			var floor_y = room.rect.position.y + 640.0
			for dir in [-1.0, 1.0]:
				var wave = Shockwave.new(dir, attack * 0.9, room.rect)
				get_parent().add_child(wave)
				wave.global_position = Vector2(global_position.x + dir * width * 0.4, floor_y)
			var game = get_tree().get_first_node_in_group("game")
			if game:
				game.shake(0.5)
			var fx = get_tree().get_first_node_in_group("fx")
			if fx:
				fx.debris(global_position + Vector2(0, -10), Color(0.3, 0.27, 0.3), 18)
			if enraged and not followup:
				queued_slam = true
		"charge":
			squash = Vector2(1.15, 0.9)


func strike_movement(_delta: float) -> float:

	if attack_kind != "charge":
		return 0.0
	# Stops dead at the wall, shaking the arena
	var limit = room.rect.position.x + width * 0.6 if facing < 0.0 else room.rect.end.x - width * 0.6
	if (facing < 0.0 and global_position.x <= limit + 4.0) or (facing > 0.0 and global_position.x >= limit - 4.0):
		if state_timer > 0.7:
			state_timer = 0.7
			var game = get_tree().get_first_node_in_group("game")
			if game:
				game.shake(0.6)
			Sfx.play("enemy_land", 0.0, 0.6)
		return 0.0
	return facing * CHARGE_SPEED * (1.15 if enraged else 1.0)


func strike_rect() -> Rect2:

	if attack_kind == "charge" and state_timer > 0.7:
		return hurt_rect()
	return Rect2()


# Columns under Veyl, ahead of vem, and behind
func start_eruptions(floor_y: float):

	if target == null:
		return
	var count = 4 if enraged else 3
	var xs = [target.global_position.x]
	var lead = sign(target.velocity.x) if abs(target.velocity.x) > 50.0 else (1.0 if randf() < 0.5 else -1.0)
	for i in range(1, count):
		xs.append(target.global_position.x + lead * i * 170.0 * (1 if i % 2 == 1 else -1))
	for x in xs:
		x = clamp(x, room.rect.position.x + 80.0, room.rect.end.x - 80.0)
		var r = Rect2(x - ERUPTION_WIDTH / 2.0, floor_y - ERUPTION_HEIGHT, ERUPTION_WIDTH, ERUPTION_HEIGHT)
		add_warning(Rect2(r.position.x, floor_y - 24, r.size.x, 24), ERUPTION_DELAY)
		erupt_later(r)


func erupt_later(r: Rect2):

	await get_tree().create_timer(ERUPTION_DELAY).timeout
	if state == State.DEAD or not is_inside_tree():
		return
	Sfx.play("eruption", -4.0)
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		for k in 3:
			fx.burst(Vector2(r.get_center().x, r.end.y - k * 100.0), Color(1.0, 0.45, 0.1), 16, 520.0, 1.2)
	var col = EruptionColumn.new(r)
	get_parent().add_child(col)
	for p in get_tree().get_nodes_in_group("players"):
		var body = Rect2(p.global_position - Vector2(16, 92), Vector2(32, 92))
		if not p.dead and r.intersects(body):
			NetSync.hurt_player(p, attack, Vector2(r.get_center().x, r.end.y))


# ============================================================
# HITS, PHASES AND DEATH
# ============================================================

func receive_hit(amount: float, from: Vector2, push: Vector2, dizzy_gain: float, launch: float):

	if phase_shift_left > 0.0 or not engaged:
		return
	# Partway up, only between attacks, and not again for a while
	if launch > 0.0:
		if state in [State.WINDUP, State.STRIKE] or launch_rest > 0.0:
			launch = 0.0
		else:
			launch *= LAUNCH_SCALE
			launch_rest = LAUNCH_REST
	super(amount, from, push * 0.15, dizzy_gain, launch)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_boss_health(max(health, 0.0), max_health)
	if not enraged and health > 0.0 and health < max_health * 0.5:
		phase_shift()


func phase_shift():

	enraged = true
	phase_shift_left = PHASE_SHIFT_TIME
	enter_state(State.HURT)
	state_timer = PHASE_SHIFT_TIME
	speed *= 1.2
	Sfx.play("boss_roar", 2.0, 0.85)
	Sfx.play_music("boss2")
	GameState.notify.emit("The Ashbound burns brighter!")
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game.shake(0.9)
	for p in get_tree().get_nodes_in_group("player"):
		var away = sign(p.global_position.x - global_position.x)
		if abs(p.global_position.x - global_position.x) < 500.0:
			p.knockback = Vector2(away * 900.0, 0)
			p.velocity.y = -500.0
	if glow:
		glow.self_modulate = Color(1.6, 1.2, 1.0)


func die():

	super()
	GameState.boss_defeated = true
	GameState.boss_fight = false
	seal_arena(false)
	Engine.time_scale = 0.3
	get_tree().create_timer(1.0, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	Sfx.play("boss_death")
	Sfx.play_music("ending")
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		for k in 4:
			fx.burst(global_position + Vector2(randf_range(-60, 60), -height * randf()), Color(1.0, 0.55, 0.2), 30, 600.0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_boss(false)
		hud.banner("THE ASHBOUND FALLS", "The Hollow breathes again. The way is open; wander as you like.", 6.0)
	var game = get_tree().get_first_node_in_group("game")
	if game and game.player:
		GameState.save_game(game.player)


# A column of fire that bursts up and dies away
class EruptionColumn:
	extends Node2D

	var rect: Rect2
	var time: float = 0.0

	func _init(r: Rect2):
		rect = r
		z_index = 12

	func _process(delta):
		time += delta
		if time > 0.5:
			queue_free()
		queue_redraw()

	func _draw():
		var t = time / 0.5
		var rise = min(t * 4.0, 1.0)
		var r = Rect2(rect.position.x, rect.end.y - rect.size.y * rise, rect.size.x, rect.size.y * rise)
		draw_rect(r, Color(1.0, 0.45, 0.1, 0.8 * (1.0 - t)))
		draw_rect(r.grow_individual(-rect.size.x * 0.3, 0, -rect.size.x * 0.3, 0), Color(1.0, 0.9, 0.6, 0.9 * (1.0 - t)))
