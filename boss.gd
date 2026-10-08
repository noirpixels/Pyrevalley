extends "res://enemy.gd"

# The Ashbound. Same state machine as normal creatures, with three
# telegraphed attacks and an enraged phase below half health:
#   SLAM     - red ring on the ground, hits everything inside it
#   CHARGE   - locks a direction and rushes through the player
#   ERUPTION - burning circles open under and around the player, then burst
# Enraged: faster windups, the slam comes twice, eruptions spread wider.
# Dashing through an attack (invulnerable) is the intended answer.

const SLAM_RADIUS = 10.0
const CHARGE_SPEED = 24.0
const CHARGE_TIME = 0.55
const CHARGE_MIN_DIST = 11.0
const ERUPTION_RADIUS = 3.5
const ERUPTION_DELAY = 1.0

var attack_kind: String = "slam"
var charge_dir: Vector3 = Vector3.ZERO
var charge_hit: bool = false
var enraged: bool = false
var queued_slam: bool = false
var followup: bool = false
var engaged: bool = false
var telegraph: MeshInstance3D
var telegraph_mat: StandardMaterial3D


func _ready():

	detect_range = 26.0
	lose_range = 45.0
	leash_range = 45.0
	detect_time = 1.0
	windup_time = 0.75
	recover_time = 0.5
	attack_cooldown = 0.7
	staggerable = false
	ember_drop_chance = 0.0

	super()
	build_telegraph()

	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.05)
	light.light_energy = 3.0
	light.omni_range = 14.0
	light.position.y = height * 0.3
	add_child(light)


func build_telegraph():

	var disc = CylinderMesh.new()
	disc.top_radius = SLAM_RADIUS
	disc.bottom_radius = SLAM_RADIUS
	disc.height = 0.05

	telegraph_mat = StandardMaterial3D.new()
	telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	telegraph_mat.albedo_color = Color(1.0, 0.15, 0.05, 0.0)

	telegraph = MeshInstance3D.new()
	telegraph.mesh = disc
	telegraph.material_override = telegraph_mat
	telegraph.position.y = -height / 2.0 + 0.1
	add_child(telegraph)


# ============================================================
# ENGAGEMENT (boss health bar)
# ============================================================

func enter_state(new_state: State):

	super(new_state)

	if new_state == State.CHASE and not engaged:
		engaged = true
		GameState.boss_engaged.emit(self)
	elif new_state == State.IDLE and engaged:
		engaged = false
		GameState.boss_disengaged.emit()


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

	# Punish keeping distance
	if dist >= CHARGE_MIN_DIST and dist < lose_range:
		attack_kind = "charge" if randf() < 0.5 else "eruption"
		return true

	if randf() < 0.01:
		attack_kind = "eruption"
		return true

	return false


func begin_attack():

	super()
	var windup = {"slam": 0.75, "charge": 0.6, "eruption": 0.5}[attack_kind]
	followup = queued_slam
	queued_slam = false
	if followup:
		windup = 0.35
	windup_time = windup * (0.75 if enraged else 1.0)
	state_timer = windup_time
	charge_hit = false

	match attack_kind:
		"slam":
			telegraph_mat.albedo_color.a = 0.0
			create_tween().tween_property(telegraph_mat, "albedo_color:a", 0.45, windup_time)
		"charge":
			charge_dir = flat(player.global_position - global_position).normalized()
		"eruption":
			start_eruption()


func perform_attack(dist: float):

	Sfx.play("boss_attack")

	if attack_kind == "slam":
		telegraph_mat.albedo_color.a = 0.8
		create_tween().tween_property(telegraph_mat, "albedo_color:a", 0.0, 0.3)
		if dist <= SLAM_RADIUS + PLAYER_RADIUS and not player.dead:
			player.take_damage(
				CodexData.calc_damage(data["attack"], player.defense),
				global_position
			)
		if enraged and not followup:
			queued_slam = true
			state_timer = 0.2
	elif attack_kind == "charge":
		state_timer = CHARGE_TIME + recover_time


func attack_movement() -> Vector3:

	if attack_kind != "charge" or not striking:
		return Vector3.ZERO

	# Only the first part of the strike phase is the rush itself
	if state_timer < recover_time:
		return Vector3.ZERO

	face(charge_dir)

	var dist = flat(player.global_position - global_position).length()
	if not charge_hit and dist < radius + PLAYER_RADIUS + 1.0 and not player.dead:
		charge_hit = true
		player.take_damage(
			CodexData.calc_damage(data["attack"] * 1.2, player.defense),
			global_position
		)

	return charge_dir * CHARGE_SPEED * (1.2 if enraged else 1.0)


# Circles under the player, around them, and where they're heading
func start_eruption():

	var count = 5 if enraged else 3
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

	var disc = CylinderMesh.new()
	disc.top_radius = ERUPTION_RADIUS
	disc.bottom_radius = ERUPTION_RADIUS
	disc.height = 0.05
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.35, 0.05, 0.0)
	var circle = MeshInstance3D.new()
	circle.mesh = disc
	circle.material_override = mat
	circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(circle)
	circle.global_position = where

	var delay = ERUPTION_DELAY * (0.8 if enraged else 1.0)
	var tween = circle.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.5, delay)
	tween.tween_callback(erupt.bind(where, mat))
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(circle.queue_free)


func erupt(where: Vector3, mat: StandardMaterial3D):

	if state == State.DEAD:
		return

	mat.albedo_color = Color(1.0, 0.75, 0.3, 0.9)
	Sfx.play("boss_attack")
	if player and not player.dead and flat(player.global_position - where).length() <= ERUPTION_RADIUS + 1.0:
		player.take_damage(
			CodexData.calc_damage(data["attack"] * 0.8, player.defense),
			where
		)


func take_damage(amount: int, from: Vector3):

	super(amount, from)

	# Too heavy to be knocked around
	knockback = Vector3.ZERO

	if not enraged and health > 0.0 and health < max_health * 0.5:
		enraged = true
		move_speed *= 1.35
		GameState.notify.emit("The Ashbound burns brighter!")
		glow_strength = 1.8


func die():

	telegraph.visible = false
	GameState.boss_disengaged.emit()
	super()
	Sfx.play("boss_death")
	GameState.defeat_boss()


func reset():

	super()
	enraged = false
	queued_slam = false
	followup = false
	move_speed = 1.5 + data["speed"] * 0.2
	glow_strength = 1.0
	telegraph_mat.albedo_color.a = 0.0
