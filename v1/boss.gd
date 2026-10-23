extends "res://enemy.gd"

# The Ashbound. Same state machine as normal creatures, with two
# telegraphed attacks and an enraged phase below half health:
#   SLAM   - red ring on the ground, hits everything inside it
#   CHARGE - locks a direction and rushes through the player

const SLAM_RADIUS = 10.0
const CHARGE_SPEED = 24.0
const CHARGE_TIME = 0.55
const CHARGE_MIN_DIST = 14.0

var attack_kind: String = "slam"
var charge_dir: Vector3 = Vector3.ZERO
var charge_hit: bool = false
var enraged: bool = false
var engaged: bool = false
var telegraph: MeshInstance3D
var telegraph_mat: StandardMaterial3D


func _ready():

	detect_range = 26.0
	lose_range = 45.0
	leash_range = 45.0
	detect_time = 1.0
	windup_time = 0.9
	recover_time = 0.7
	attack_cooldown = 1.0
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

	if cooldown_timer > 0.0:
		return false

	if dist <= attack_reach():
		attack_kind = "slam"
		return true

	# Punish keeping distance
	if dist >= CHARGE_MIN_DIST and dist < lose_range and randf() < 0.02:
		attack_kind = "charge"
		return true

	return false


func begin_attack():

	super()
	windup_time = (0.9 if attack_kind == "slam" else 0.7) * (0.75 if enraged else 1.0)
	state_timer = windup_time
	charge_hit = false

	if attack_kind == "slam":
		telegraph_mat.albedo_color.a = 0.0
		create_tween().tween_property(telegraph_mat, "albedo_color:a", 0.45, windup_time)
	else:
		charge_dir = flat(player.global_position - global_position).normalized()


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
	else:
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
	move_speed = 1.5 + data["speed"] * 0.2
	glow_strength = 1.0
	telegraph_mat.albedo_color.a = 0.0
