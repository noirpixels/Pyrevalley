extends "res://enemy.gd"

# The Ashbound. Same state machine as normal creatures, with three
# telegraphed attacks and an enraged phase below half health:
#   SLAM     - red ring on the ground, hits everything inside it
#   CHARGE   - locks a direction and rushes through the player
#   ERUPTION - burning circles open under and around the player, then burst
# Enraged: faster windups, the slam comes twice, eruptions spread wider.
# Dashing through an attack (invulnerable) is the intended answer.
# Too heavy to launch, but alternating hits can daze it, which cancels
# whatever it was winding up.
# Every attack is drawn on the ground first (telegraph.gd) and lands when
# the warning fills. It rises with a title card the first time Veyl
# faces it, and at half health it roars, throws Veyl back and catches fire.
# With several players it fights whoever is nearest inside its arena, and
# its slam, charge and eruptions hit every Veyl they reach.

const EmberWall = preload("res://ember_wall.gd")
const InkPost = preload("res://ink_post.gd")
# Seconds it rears up, the first time it sees Veyl
const INTRO_TIME = 2.4
# The roar at half health: untouchable while it lasts
const PHASE_SHIFT_TIME = 1.6
const PHASE_SHIFT_PUSH = 28.0

const SLAM_RADIUS = 10.0
const CHARGE_SPEED = 24.0
const CHARGE_TIME = 0.55
const CHARGE_MIN_DIST = 9.0
# The fight lasts while Veyl is within this distance of the arena centre;
# the boss itself stops at leash_range and fights from there
const TERRITORY_MARGIN = 12.0
# Chases faster than its codex speed alone would make it
const CHASE_SPEED_SCALE = 1.4
const ERUPTION_RADIUS = 3.5
const ERUPTION_DELAY = 1.0

var attack_kind: String = "slam"
var charge_dir: Vector3 = Vector3.ZERO
# Veyls this charge has already hit
var charge_hits: Array = []
var enraged: bool = false
var queued_slam: bool = false
var followup: bool = false
var engaged: bool = false
var introduced: bool = false
var phase_shift_left: float = 0.0


func _ready():

	detect_range = 26.0
	lose_range = 45.0
	# Reaches every corner of the arena, so it can't be pinned at its leash
	leash_range = 60.0
	detect_time = 1.0
	windup_time = 0.6
	recover_time = 0.9
	attack_cooldown = 1.3
	staggerable = false
	ember_drop_chance = 0.0
	# Damage dealt sticks, even across Veyl's deaths
	regenerates = false
	launchable = false
	dizzy_threshold = 240.0
	dizzy_time = 1.4

	super()
	move_speed *= CHASE_SPEED_SCALE

	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.05)
	light.light_energy = 3.0
	light.omni_range = 14.0
	light.position.y = height * 0.3
	add_child(light)


# ============================================================
# ENGAGEMENT (boss health bar)
# ============================================================

func enter_state(new_state: State):

	super(new_state)

	if new_state == State.DIZZY:
		queued_slam = false

	# The first sighting: it rises and roars, and the fight is named
	if new_state == State.DETECTED and not introduced:
		introduced = true
		state_timer = INTRO_TIME
		fx("intro")

	if new_state == State.CHASE and not engaged:
		engaged = true
		fx("engage", [true])
	elif new_state == State.IDLE and engaged:
		engaged = false
		fx("engage", [false])


func fx_intro():

	fx_sound("boss_roar")
	get_tree().call_group("game_ui", "boss_intro", data["name"], "Chained heart of Emberwood")
	shake_nearby(0.5)


# Seals the arena, starts the music and shows the health bar, everywhere
func fx_engage(on: bool):

	GameState.boss_fight = on
	if on:
		GameState.boss_engaged.emit(self)
	else:
		GameState.boss_disengaged.emit()


# Shakes this player's view if their Veyl is close enough to feel it
func shake_nearby(amount: float):

	var me = NetSync.local_player()
	if me and flat(me.global_position - global_position).length() < SLAM_RADIUS * 3.0:
		me.shake = max(me.shake, amount)


# ============================================================
# TERRITORY
# ============================================================

func player_in_territory() -> bool:
	return can_hunt(player)


func can_hunt(veyl: Node3D) -> bool:
	return flat(veyl.global_position - home).length() <= leash_range + TERRITORY_MARGIN


func can_detect(dist: float) -> bool:
	return super(dist) and player_in_territory()


# Only leaving the arena area ends the fight, not luring it to the edge
func should_give_up(_dist: float) -> bool:
	return player.dead or not player_in_territory()


# Holds the edge of its arena instead of being pulled out of it; from
# there it still charges and erupts
func chase_movement(dir: Vector3) -> Vector3:
	var from_home = flat(global_position - home)
	if from_home.length() >= leash_range and dir.dot(from_home) > 0.0:
		return Vector3.ZERO
	return super(dir)


# ============================================================
# ATTACKS
# ============================================================

func attack_reach() -> float:
	return SLAM_RADIUS * 0.7


func wants_to_attack(dist: float) -> bool:

	# Enraged slams come in pairs, the second with almost no warning
	if queued_slam:
		attack_kind = "slam"
		return true

	if cooldown_timer > 0.0:
		return false

	if dist <= attack_reach():
		attack_kind = "slam" if randf() < 0.65 else "eruption"
		return true

	# Out of slam range is never safe: Veyl's sword outreaches the slam
	# trigger, so poking from just outside it gets answered straight away
	if dist >= CHARGE_MIN_DIST:
		attack_kind = "charge" if randf() < 0.5 else "eruption"
	else:
		attack_kind = "eruption"
	return true


func begin_attack():

	super()
	# Too short to walk out of the slam ring (~0.55s at full speed plus
	# reaction time), long enough to time a dash; the long recovery after
	# each attack is the opening to hit back
	var windup = {"slam": 0.7, "charge": 0.6, "eruption": 0.6}[attack_kind]
	followup = queued_slam
	queued_slam = false
	if followup:
		windup = 0.55
	windup_time = windup * (0.85 if enraged else 1.0)
	state_timer = windup_time
	charge_hits = []

	clear_tele(true)
	match attack_kind:
		"slam":
			fx("circle", [ground_point(global_position), SLAM_RADIUS, windup_time])
		"charge":
			charge_dir = flat(player.global_position - global_position).normalized()
			var length = CHARGE_SPEED * (1.2 if enraged else 1.0) * CHARGE_TIME + radius
			fx("lane", [ground_point(global_position), charge_dir, length, radius * 2.0, windup_time])
		"eruption":
			start_eruption()


func perform_attack(_dist: float):

	fx("sound", ["boss_attack"])

	if attack_kind == "slam":
		clear_tele(false)
		fx("slam")
		for veyl in players_within(global_position, SLAM_RADIUS + PLAYER_RADIUS):
			veyl.take_damage(
				CodexData.calc_damage(data["attack"], veyl.defense),
				global_position
			)
		if enraged and not followup:
			queued_slam = true
			state_timer = 0.2
	elif attack_kind == "charge":
		clear_tele(false)
		state_timer = CHARGE_TIME + recover_time


func ground_point(at: Vector3) -> Vector3:
	return Vector3(at.x, global_position.y - height / 2.0, at.z)


# Ash thrown up all round the ring, and the page shakes
func fx_slam():

	sprite_scale = Vector2(1.25, 0.75)
	for i in 10:
		var angle = TAU * i / 10.0
		var at = ground_point(global_position) + Vector3(cos(angle), 0, sin(angle)) * SLAM_RADIUS * 0.85
		AshBurst.spawn(get_parent(), at, 0.6)
	if NetSync.near_me(global_position):
		shake_nearby(0.55)
		InkPost.flash(get_tree(), Color(1.0, 0.6, 0.3), 0.18)
		Pad.rumble(0.5, 0.8, 0.25)


func attack_movement() -> Vector3:

	if attack_kind != "charge" or not striking:
		return Vector3.ZERO

	# Only the first part of the strike phase is the rush itself
	if state_timer < recover_time:
		return Vector3.ZERO

	face(charge_dir)

	for veyl in players_within(global_position, radius + PLAYER_RADIUS + 1.0):
		if not veyl in charge_hits:
			charge_hits.append(veyl)
			veyl.take_damage(
				CodexData.calc_damage(data["attack"] * 1.2, veyl.defense),
				global_position
			)

	return charge_dir * CHARGE_SPEED * (1.2 if enraged else 1.0)


# Circles under the player, around them, and where they're heading
func start_eruption():

	var count = 4 if enraged else 3
	var ground_y = global_position.y - height / 2.0 + 0.12
	var target = flat(player.global_position)
	var spots = [target, target + flat(player.velocity) * ERUPTION_DELAY * 0.8]
	while spots.size() < count:
		var angle = randf() * TAU
		var dist = randf_range(ERUPTION_RADIUS * 1.6, ERUPTION_RADIUS * 3.2)
		spots.append(target + Vector3(cos(angle), 0, sin(angle)) * dist)

	for spot in spots:
		spawn_eruption(Vector3(spot.x, ground_y, spot.z))


func spawn_eruption(where: Vector3):

	var delay = ERUPTION_DELAY * (0.9 if enraged else 1.0)
	fx("eruption", [where, delay])
	get_tree().create_timer(delay, false).timeout.connect(erupt.bind(where))


# The warning circle, then a pillar of fire that burns out
func fx_eruption(where: Vector3, delay: float):

	var circle = Telegraph.circle(get_parent(), where, ERUPTION_RADIUS, delay)
	get_tree().create_timer(delay, false).timeout.connect(fx_erupt.bind(where, circle))


func fx_erupt(where: Vector3, circle: Node):

	if is_instance_valid(circle):
		circle.burst()
	if state == State.DEAD or not is_inside_tree():
		return

	var pillar = EmberWall.new(ERUPTION_RADIUS * 1.4, 7.0, true)
	get_parent().add_child(pillar)
	pillar.global_position = where
	pillar.fade_to(0.0, 0.7).tween_callback(pillar.queue_free)
	AshBurst.spawn(get_parent(), where, 0.5)
	fx_sound("eruption", -2.0, randf_range(0.9, 1.1))


func erupt(where: Vector3):

	if state == State.DEAD or not is_inside_tree():
		return
	for veyl in players_within(where, ERUPTION_RADIUS + 1.0):
		veyl.take_damage(
			CodexData.calc_damage(data["attack"] * 0.8, veyl.defense),
			where
		)


func take_damage(amount: int, from: Vector3):

	# Untouchable while it roars into its second phase
	if phase_shift_left > 0.0:
		return

	super(amount, from)

	# Too heavy to be knocked around
	knockback = Vector3.ZERO

	if not enraged and health > 0.0 and health < max_health * 0.5:
		phase_shift()


# Half health: it roars, throws Veyl back, the ground erupts all round it,
# and it fights faster and harder from here on
func phase_shift():

	enraged = true
	move_speed *= 1.2
	phase_shift_left = PHASE_SHIFT_TIME
	clear_tele(true)
	queued_slam = false
	enter_state(State.HURT)
	state_timer = PHASE_SHIFT_TIME
	fx("phase_shift")

	for i in 8:
		var angle = TAU * i / 8.0
		spawn_eruption(ground_point(global_position) + Vector3(cos(angle), 0, sin(angle)) * SLAM_RADIUS * 1.25)


# Each player's own Veyl is thrown back on their own machine
func fx_phase_shift():

	enraged = true
	glow_strength = 1.8
	sprite_scale = Vector2(0.85, 1.25)

	fx_sound("boss_roar", 2.0, 0.85)
	Sfx.play_music("boss2")
	GameState.notify.emit("The Ashbound burns brighter!")
	if not NetSync.near_me(global_position):
		return
	InkPost.flash(get_tree(), Color(1.0, 0.5, 0.2), 0.55)
	Pad.rumble(0.8, 1.0, 0.6)
	shake_nearby(0.9)
	var me = NetSync.local_player()
	var away = flat(me.global_position - global_position) if me else Vector3.ZERO
	if me and not me.dead and away.length() < SLAM_RADIUS * 1.5:
		me.velocity += away.normalized() * PHASE_SHIFT_PUSH + Vector3.UP * 8.0


func _physics_process(delta):

	phase_shift_left = max(phase_shift_left - delta, 0.0)
	super(delta)


func die():

	fx("engage", [false])
	super()
	GameState.defeat_boss()


func fx_die():

	super()
	fx_sound("boss_death")
	# It comes apart in waves
	for i in 5:
		var at = global_position + Vector3(randf_range(-3, 3), randf_range(-2, 4), randf_range(-3, 3))
		get_tree().create_timer(0.15 * i).timeout.connect(AshBurst.spawn.bind(get_parent(), at, 1.6))


# Leaving the level mid-fight (quit to menu) must not leave shrines cold
func _exit_tree():
	if GameState.boss_fight:
		GameState.boss_fight = false
