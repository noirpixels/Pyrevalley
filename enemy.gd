extends CharacterBody3D

# A creature from CodexData, driven by the GDD state machine:
#   IDLE -> DETECTED -> CHASE -> ATTACK -> (HURT / DIZZY) -> DEAD
# Each kind fights its own way, every attack shown on the ground first
# (telegraph.gd) and landing when the warning fills:
#   Mossling    hops up and slams down where Veyl stood
#   Ember Wolf  bites up close; at range it circles, then pounces down a lane
#   Ashcrawler  bites up close; at range it spits ember bolts
# Veyl's directional hits also push, spin, launch and daze it; that runs
# on its own meters, separate from health (see IMPACT below).
# Spawned by creature_spawner.gd; call setup() before adding to the tree.
# It goes after the nearest Veyl still standing. Only the host (or a solo
# game) runs the behaviour; every sight and sound goes through fx() so
# guests see it too, and a guest's copy is a puppet that follows the
# host's snapshots (net_state / apply_net_state).

signal died(enemy)
signal health_changed(current, maximum)

enum State { IDLE, DETECTED, CHASE, ATTACK, HURT, DIZZY, DEAD }

const FloatingText = preload("res://floating_text.gd")
const SpritePose = preload("res://sprite_pose.gd")
const InkSprite = preload("res://ink_sprite.gd")
const Telegraph = preload("res://telegraph.gd")
const AshBurst = preload("res://ash_burst.gd")
const EmberBolt = preload("res://ember_bolt.gd")

const PLAYER_RADIUS = 2.5
# Dizzy meter: hits from alternating sides rattle a creature far more than
# repeated hits from one side. It drains once the hits stop.
const ALTERNATE_DIZZY = 2.5
const SAME_SIDE_DIZZY = 0.6
const SIDE_MEMORY = 1.2
const DIZZY_DRAIN_DELAY = 0.8
const DIZZY_DRAIN = 30.0
# After coming to, it can't be dazed again for this long (no stunlock)
const DIZZY_IMMUNITY = 3.0
const SPIN_DRAG = 10.0
# Below this vertical speed a launched target feels LAUNCH_HANG_GRAVITY
# of normal gravity, so it hangs at the top of the launch
const LAUNCH_HANG_SPEED = 6.0
const LAUNCH_HANG_GRAVITY = 0.4

# Same pixel density as Veyl's sprite (216 px = 8.1 units)
const SPRITE_PIXEL_SIZE = 0.0375

const KINDS = {"Mossling": "mossling", "Ember Wolf": "wolf", "Ashcrawler": "crawler"}
# Windup per move: long enough to read and dodge, short enough to threaten
const WINDUPS = {"bite": 0.45, "hop": 0.55, "pounce": 0.6, "spit": 0.6}
const HOP_VELOCITY = 10.0
const HOP_RADIUS = 3.4
const POUNCE_SPEED = 26.0
const POUNCE_TIME = 0.3
const POUNCE_MIN = 6.0
const POUNCE_MAX = 13.0
const SPIT_MIN = 7.0
const SPIT_MAX = 17.0
# Floats per creature in a network snapshot (net_state)
const NET_FIELDS = 13
# A puppet this far from where the host has it jumps there instead of gliding
const NET_SNAP_DIST = 8.0

# Behaviour tuning (boss.gd overrides some of these)
var detect_range: float = 18.0
var lose_range: float = 30.0
var leash_range: float = 40.0
var detect_time: float = 0.5
var windup_time: float = 0.45
var recover_time: float = 0.5
var attack_cooldown: float = 0.9
var hurt_time: float = 0.2
var staggerable: bool = true
var ember_drop_chance: float = 0.3
# Heals when it gives up a chase or the player respawns
var regenerates: bool = true
var dizzy_threshold: float = 100.0
var dizzy_time: float = 1.6
var launchable: bool = true

var data: Dictionary
var kind: String = ""
var spawner_id: String = ""
# The Veyl it's after (any player's)
var player: Node3D
var home: Vector3
# A guest's copy, moved by the host
var puppet: bool = false
var net_pos: Vector3
var net_vel: Vector3 = Vector3.ZERO
var net_age: float = 0.0
var has_net_state: bool = false

var state: State = State.IDLE
var state_timer: float = 0.0
var cooldown_timer: float = 0.0
var striking: bool = false
# Gave up a chase and is heading home; ignores the player until it's there
var returning: bool = false

var max_health: float
var health: float
var move_speed: float
var radius: float
var height: float

var knockback: Vector3 = Vector3.ZERO
var flash_timer: float = 0.0
var wander_dir: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var facing: Vector3 = Vector3.FORWARD
var anim_time: float = 0.0

# Impact meters, separate from health
var dizzy: float = 0.0
var dizzy_drain_delay: float = 0.0
var dizzy_immunity: float = 0.0
var last_side: int = 0
var side_timer: float = 0.0
var spin_speed: float = 0.0
var spin_angle: float = 0.0
var launched: bool = false
var launch_grace: float = 0.0
var base_flip: bool = false

var body_texture: Texture2D
var sprite: Sprite3D
var glow_sprite: Sprite3D
var sprite_base_y: float
var sprite_scale: Vector2 = Vector2.ONE
var lean: float = 0.0
# Lean kicked in by a hit; fades back out
var recoil: float = 0.0
var glow_strength: float = 1.0
var label: Label3D
var alert_label: Label3D
var dizzy_label: Label3D

# The move under way, and its ground warning
var move_kind: String = "bite"
var tele: Node = null
var leap_dir: Vector3 = Vector3.ZERO
var leap_speed: float = 0.0
var leap_target: Vector3 = Vector3.ZERO
var hopping: bool = false
var hop_time: float = 0.0
var pounce_left: float = 0.0
var pounce_hit: bool = false
# Wolves circle one way or the other between pounces
var circle_side: float = 1.0

# Heavier than Earth gravity so jumps and launches don't float
var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
) * 2.5


func setup(creature: Dictionary, id: String = ""):

	data = creature
	spawner_id = id
	kind = KINDS.get(creature["name"], "")
	circle_side = 1.0 if randf() < 0.5 else -1.0
	match kind:
		"wolf":
			attack_cooldown = 1.1
			recover_time = 0.45
		"crawler":
			attack_cooldown = 1.3
			recover_time = 0.6
		"mossling":
			attack_cooldown = 1.0

	max_health = creature["health"]
	health = max_health

	# Codex speed (6-40) -> world units per second
	move_speed = 1.5 + creature["speed"] * 0.2

	# Collision is a cylinder roughly the size of the sprite
	body_texture = InkSprite.ink(load(creature["sprite"]))
	radius = 1.4 * creature["size"]
	height = body_texture.get_height() * SPRITE_PIXEL_SIZE * 0.9


# Tougher when more players are in the session
func scale_health(mult: float):

	max_health *= mult
	health = max_health


func _ready():

	add_to_group("enemies")
	home = global_position
	build_body()
	update_label()


# ============================================================
# BODY (painted sprite + unshaded glow layer)
# ============================================================

func build_body():

	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height

	var collision = CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	var visual_height = body_texture.get_height() * SPRITE_PIXEL_SIZE
	var visual_width = body_texture.get_width() * SPRITE_PIXEL_SIZE

	# Soft blob shadow grounds the billboard
	var shadow_mesh = CylinderMesh.new()
	shadow_mesh.top_radius = visual_width * 0.38
	shadow_mesh.bottom_radius = visual_width * 0.38
	shadow_mesh.height = 0.02
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0, 0, 0, 0.35)
	var shadow = MeshInstance3D.new()
	shadow.mesh = shadow_mesh
	shadow.material_override = shadow_mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.scale = Vector3(1.0, 1.0, 0.55)
	shadow.position.y = -height / 2.0 + 0.05
	add_child(shadow)

	# Feet sit on the bottom of the collision cylinder
	sprite_base_y = -height / 2.0

	sprite = Sprite3D.new()
	sprite.texture = body_texture
	sprite.pixel_size = SPRITE_PIXEL_SIZE
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position.y = sprite_base_y
	add_child(sprite)

	# Eyes, embers and cracks: unshaded so they glow in the dark forest
	var glow_path = data["sprite"].replace(".png", "_glow.png")
	if ResourceLoader.exists(glow_path):
		glow_sprite = Sprite3D.new()
		glow_sprite.texture = load(glow_path)
		glow_sprite.pixel_size = SPRITE_PIXEL_SIZE
		glow_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		glow_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		glow_sprite.shaded = false
		glow_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow_sprite.render_priority = 1
		sprite.add_child(glow_sprite)

	SpritePose.pin_to_feet(sprite)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.025
	label.outline_size = 12
	label.modulate = CodexData.RARITY_COLORS.get(data["rarity"], Color.WHITE)
	label.position.y = -height / 2.0 + visual_height + 1.0
	label.visible = false
	add_child(label)

	alert_label = Label3D.new()
	alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert_label.no_depth_test = true
	alert_label.text = "!"
	alert_label.font_size = 96
	alert_label.pixel_size = 0.03
	alert_label.outline_size = 16
	alert_label.modulate = Color(1.0, 0.8, 0.2)
	alert_label.position.y = -height / 2.0 + visual_height + 3.0
	alert_label.visible = false
	add_child(alert_label)

	dizzy_label = Label3D.new()
	dizzy_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dizzy_label.no_depth_test = true
	dizzy_label.text = "~ dizzy ~"
	dizzy_label.font_size = 48
	dizzy_label.pixel_size = 0.03
	dizzy_label.outline_size = 12
	dizzy_label.modulate = Color(1.0, 0.95, 0.4)
	dizzy_label.position.y = alert_label.position.y
	dizzy_label.visible = false
	add_child(dizzy_label)


# ============================================================
# STATE MACHINE
# ============================================================

func enter_state(new_state: State):

	state = new_state
	striking = false
	if new_state != State.ATTACK:
		hopping = false
		pounce_left = 0.0
		clear_tele(true)
	alert_label.visible = new_state == State.DETECTED
	dizzy_label.visible = new_state == State.DIZZY

	match new_state:
		State.DETECTED:
			state_timer = detect_time
		State.ATTACK:
			state_timer = windup_time
			begin_attack()
		State.HURT:
			state_timer = hurt_time
		State.DIZZY:
			state_timer = dizzy_time


func _physics_process(delta):

	if state == State.DEAD:
		return

	if puppet:
		puppet_process(delta)
		return

	pick_target()
	if player == null:
		return

	if not is_on_floor():
		var g = gravity
		# Launched targets hang near the top so the launch reads as a lift
		if launched and abs(velocity.y) < LAUNCH_HANG_SPEED:
			g *= LAUNCH_HANG_GRAVITY
		velocity.y -= g * delta

	state_timer -= delta
	update_impact(delta)
	cooldown_timer = max(cooldown_timer - delta, 0.0)
	flash_timer = max(flash_timer - delta, 0.0)

	var to_player = flat(player.global_position - global_position)
	var dist = to_player.length()
	var move = Vector3.ZERO

	match state:

		State.IDLE:
			if can_detect(dist):
				enter_state(State.DETECTED)
			else:
				move = idle_movement(delta)

		State.DETECTED:
			face(to_player)
			if state_timer <= 0.0:
				enter_state(State.CHASE)

		State.CHASE:
			if should_give_up(dist):
				returning = not player.dead
				enter_state(State.IDLE)
			elif wants_to_attack(dist):
				enter_state(State.ATTACK)
			elif dist > attack_reach() * 0.8:
				move = chase_movement(to_player / dist)
				face(to_player)

		State.ATTACK:
			# Windup (telegraph) -> strike -> recover
			if not striking and state_timer <= 0.0:
				striking = true
				state_timer = recover_time
				perform_attack(dist)
			elif striking and state_timer <= 0.0:
				cooldown_timer = attack_cooldown
				enter_state(State.CHASE)
			move = attack_movement()

		# Launched creatures can't act until they land
		State.HURT:
			if state_timer <= 0.0 and not launched:
				enter_state(State.CHASE)

		State.DIZZY:
			if state_timer <= 0.0 and not launched:
				enter_state(State.CHASE)

	if hopping:
		hop_time += delta
		if hop_time > 0.15 and is_on_floor():
			land_hop()

	velocity.x = move.x + knockback.x
	velocity.z = move.z + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 40.0 * delta)

	move_and_slide()
	update_visuals(delta)


# The nearest Veyl still standing; with everyone down, the nearest at all,
# so the chase ends. An attack already under way keeps its target.
func pick_target():

	if state == State.ATTACK and player and is_instance_valid(player):
		return
	player = nearest_player(true)
	if player == null:
		player = nearest_player(false)


func nearest_player(must_hunt: bool) -> Node3D:

	var best: Node3D = null
	var best_dist = INF
	for veyl in NetSync.all_players():
		if must_hunt and (veyl.dead or not can_hunt(veyl)):
			continue
		var dist = flat(veyl.global_position - global_position).length()
		if dist < best_dist:
			best = veyl
			best_dist = dist
	return best


# boss.gd only hunts inside its arena
func can_hunt(_veyl: Node3D) -> bool:
	return true


# Every Veyl within reach of a point (area attacks hit all of them)
func players_within(point: Vector3, reach: float) -> Array:

	var hit = []
	for veyl in NetSync.all_players():
		if not veyl.dead and flat(veyl.global_position - point).length() <= reach:
			hit.append(veyl)
	return hit


# Wander near home; walk back and heal up after losing the player
func idle_movement(delta) -> Vector3:

	var to_home = flat(home - global_position)

	if to_home.length() <= 4.0:
		returning = false

	if to_home.length() > 4.0:
		if regenerates:
			health = min(health + max_health * 0.25 * delta, max_health)
			update_label()
		face(to_home)
		return to_home.normalized() * move_speed

	wander_timer -= delta
	if wander_timer <= 0.0:
		wander_timer = randf_range(1.5, 3.5)
		var angle = randf() * TAU
		wander_dir = Vector3(cos(angle), 0, sin(angle)) if randf() < 0.5 else Vector3.ZERO

	if wander_dir != Vector3.ZERO:
		face(wander_dir)
	return wander_dir * move_speed * 0.35


# ============================================================
# CHASE HOOKS (overridden by boss.gd)
# ============================================================

# Not while walking home after giving up: otherwise standing just past the
# leash makes it flip between IDLE and DETECTED forever, never attacking
func can_detect(dist: float) -> bool:
	return not player.dead and not returning and dist < detect_range


func should_give_up(dist: float) -> bool:
	return player.dead or dist > lose_range or flat(global_position - home).length() > leash_range


func chase_movement(dir: Vector3) -> Vector3:

	# Between pounces a wolf circles at a distance instead of walking in
	if kind == "wolf" and cooldown_timer > 0.0:
		var dist = flat(player.global_position - global_position).length()
		var around = dir.cross(Vector3.UP) * circle_side
		var keep = -dir if dist < POUNCE_MIN else (dir if dist > POUNCE_MAX - 2.0 else Vector3.ZERO)
		return (around + keep * 0.8).normalized() * move_speed * 0.8

	return dir * move_speed


# ============================================================
# ATTACK HOOKS (overridden by boss.gd)
# ============================================================

func attack_reach() -> float:
	return radius + PLAYER_RADIUS + 1.5


func wants_to_attack(dist: float) -> bool:

	if cooldown_timer > 0.0:
		return false
	move_kind = "bite"
	match kind:
		"mossling":
			if dist <= attack_reach() + 4.0:
				move_kind = "hop"
				return true
		"wolf":
			if dist >= POUNCE_MIN and dist <= POUNCE_MAX:
				move_kind = "pounce"
				return true
		"crawler":
			if dist >= SPIT_MIN and dist <= SPIT_MAX:
				move_kind = "spit"
				return true
	return dist <= attack_reach()


# Sets the windup and puts the warning on the ground
func begin_attack():

	var to_player = flat(player.global_position - global_position)
	face(to_player)
	if kind == "":
		return

	windup_time = WINDUPS[move_kind]
	state_timer = windup_time
	var dir = to_player.normalized() if to_player.length() > 0.01 else facing
	var ground = global_position - Vector3(0, height / 2.0, 0)
	clear_tele(true)
	fx("sound", ["enemy_windup", -10.0, randf_range(0.9, 1.15)])

	match move_kind:
		"bite":
			fx("lane", [ground, dir, attack_reach() + 1.0, radius * 1.8, windup_time])
		"hop":
			# Locks on where Veyl is now: keep moving and it misses
			leap_target = flat(player.global_position) + Vector3(0, ground.y, 0)
			fx("circle", [leap_target, HOP_RADIUS, windup_time])
		"pounce":
			leap_dir = dir
			fx("lane", [ground, dir, POUNCE_SPEED * POUNCE_TIME + radius, radius * 1.6, windup_time])
		"spit":
			leap_dir = dir
			fx("lane", [ground, dir, to_player.length() + 2.0, 1.2, windup_time])


func attack_movement() -> Vector3:

	if not striking:
		return Vector3.ZERO
	if hopping:
		return leap_dir * leap_speed
	if pounce_left > 0.0:
		pounce_left -= get_physics_process_delta_time()
		face(leap_dir)
		var dist = flat(player.global_position - global_position).length()
		if not pounce_hit and dist < radius + PLAYER_RADIUS and not player.dead:
			pounce_hit = true
			player.take_damage(CodexData.calc_damage(data["attack"] * 1.2, player.defense), global_position)
		return leap_dir * POUNCE_SPEED
	return Vector3.ZERO


func perform_attack(dist: float):

	match move_kind:
		"hop":
			fx("sound", ["enemy_attack", 0.0, 1.2])
			var to_target = flat(leap_target - global_position)
			var air_time = 2.0 * HOP_VELOCITY / gravity
			leap_dir = to_target.normalized() if to_target.length() > 0.01 else Vector3.ZERO
			leap_speed = min(to_target.length() / air_time, move_speed * 4.0)
			velocity.y = HOP_VELOCITY
			hopping = true
			hop_time = 0.0
			state_timer = air_time + recover_time
		"pounce":
			fx("sound", ["enemy_attack", 0.0, 0.85])
			pounce_left = POUNCE_TIME
			pounce_hit = false
			state_timer = POUNCE_TIME + recover_time
			clear_tele(false)
		"spit":
			fx("sound", ["spit"])
			var mouth = global_position + facing * radius + Vector3(0, height * 0.1, 0)
			fx("bolt", [mouth, leap_dir, CodexData.calc_damage(data["attack"] * 0.8, player.defense)])
			clear_tele(false)
		_:
			fx("sound", ["enemy_attack"])
			clear_tele(false)
			if dist <= attack_reach() + 1.0 and not player.dead:
				player.take_damage(
					CodexData.calc_damage(data["attack"], player.defense),
					global_position
				)


# The hop comes down: anything under it is hit
func land_hop():

	hopping = false
	clear_tele(false)
	fx("land")
	for veyl in players_within(global_position, HOP_RADIUS + 1.0):
		veyl.take_damage(CodexData.calc_damage(data["attack"] * 1.1, veyl.defense), global_position)


# cancelled: the attack never happened (fade); otherwise it just landed (flash)
func clear_tele(cancelled: bool):

	if tele and is_instance_valid(tele):
		fx("clear_tele", [cancelled])
	tele = null


# ============================================================
# DAMAGE / DEATH
# ============================================================

func take_damage(amount: int, from: Vector3):

	if state == State.DEAD:
		return

	health -= amount
	health_changed.emit(max(health, 0.0), max_health)

	# Heavier creatures get pushed less
	var push = flat(global_position - from)
	if push.length() > 0.01:
		knockback = push.normalized() * 9.0 / data["size"]

	fx("hurt", [amount, from])

	if health <= 0.0:
		die()
	elif state == State.DIZZY or launched:
		pass
	elif staggerable or state == State.IDLE or state == State.DETECTED:
		enter_state(State.HURT)


# A Veyl's blade connected (net_sync.gd sends guests' hits here)
func receive_hit(amount: int, from: Vector3, push: Vector3, spin: float, dizzy_gain: float, launch: float, side: int):

	take_damage(amount, from)
	apply_impact(push, spin, dizzy_gain, launch, side)


func dead_already() -> bool:
	return state == State.DEAD


# ============================================================
# IMPACT (push, spin, dizziness, launch; never touches health)
# ============================================================

# push: velocity to shove it by; spin: rad/s; side: -1 left, 1 right, 0 none
func apply_impact(push: Vector3, spin: float, dizzy_gain: float, launch: float, side: int):

	if state == State.DEAD:
		return

	var weight = max(data["size"], 0.6)
	knockback = push / weight
	spin_speed += spin / weight

	# Switching sides reverses its momentum and rattles it
	if side != 0 and side_timer > 0.0:
		if side == -last_side:
			dizzy_gain *= ALTERNATE_DIZZY
			knockback *= 1.25
		else:
			dizzy_gain *= SAME_SIDE_DIZZY
	if side != 0:
		last_side = side
		side_timer = SIDE_MEMORY

	if launchable and launch > 0.0 and not launched:
		velocity.y = launch
		launched = true
		launch_grace = 0.1
		enter_state(State.HURT)
	elif launch < 0.0 and launched:
		# Spiked back down
		velocity.y = launch

	if state != State.DIZZY and dizzy_immunity <= 0.0:
		dizzy += dizzy_gain
		dizzy_drain_delay = DIZZY_DRAIN_DELAY
		if dizzy >= dizzy_threshold:
			become_dizzy()


func become_dizzy():

	dizzy = 0.0
	dizzy_immunity = dizzy_time + DIZZY_IMMUNITY
	enter_state(State.DIZZY)
	fx("dizzy")


func is_dizzy() -> bool:
	return state == State.DIZZY


func update_impact(delta):

	side_timer = max(side_timer - delta, 0.0)
	dizzy_immunity = max(dizzy_immunity - delta, 0.0)
	launch_grace = max(launch_grace - delta, 0.0)

	if dizzy_drain_delay > 0.0:
		dizzy_drain_delay -= delta
	else:
		dizzy = max(dizzy - DIZZY_DRAIN * delta, 0.0)

	spin_speed = move_toward(spin_speed, 0.0, SPIN_DRAG * delta)
	spin_angle += spin_speed * delta
	if abs(spin_speed) < 1.0:
		# Settle facing the way it was
		spin_angle = lerp(spin_angle, round(spin_angle / TAU) * TAU, 8.0 * delta)

	if launched and launch_grace <= 0.0 and is_on_floor() and velocity.y <= 0.0:
		launched = false
		sprite_scale = Vector2(1.25, 0.7)
		if state == State.HURT:
			state_timer = 0.25


func die():

	clear_tele(true)
	GameState.record_creature_defeat(data["name"])
	drop_loot()
	fx("die")
	died.emit(self)


func drop_loot():

	var ground = Vector3(global_position.x, 0, global_position.z)

	if data.get("drop", "") != "":
		NetSync.drop("item", data["drop"], ground + Vector3(1.0, 0, 0))

	if randf() < ember_drop_chance:
		NetSync.drop("ember", "", ground + Vector3(-1.0, 0, 0))


# ============================================================
# MOMENTS (seen and heard on every machine in a session)
# ============================================================

# Plays a sight or sound here and, when hosting, on every guest's copy
func fx(moment: String, args: Array = []):

	callv("fx_" + moment, args)
	NetSync.creature_fx(self, moment, args)


# Only fights near your own Veyl are heard
func fx_sound(sound: String, volume_db: float = 0.0, pitch: float = 1.0):

	if NetSync.near_me(global_position):
		Sfx.play(sound, volume_db, pitch)


func fx_lane(from: Vector3, dir: Vector3, length: float, width: float, windup: float):

	fx_clear_tele(true)
	tele = Telegraph.lane(get_parent(), from, dir, length, width, windup)


func fx_circle(centre: Vector3, reach: float, windup: float):

	fx_clear_tele(true)
	tele = Telegraph.circle(get_parent(), centre, reach, windup)


func fx_clear_tele(cancelled: bool):

	if tele and is_instance_valid(tele):
		if cancelled:
			tele.cancel()
		else:
			tele.burst()
	tele = null


# A guest's bolt is only for show; the host's one does the burning
func fx_bolt(from: Vector3, dir: Vector3, amount: int):

	EmberBolt.spawn(get_parent(), from, dir, 0 if puppet else amount)


func fx_land():

	sprite_scale = Vector2(1.35, 0.65)
	fx_sound("enemy_land", -2.0)
	AshBurst.spawn(get_parent(), global_position - Vector3(0, height / 2.0, 0), 0.4)


func fx_hurt(amount: int, from: Vector3):

	flash_timer = 0.12
	fx_sound("hit")

	# The top snaps the way it's pushed
	var push = flat(global_position - from)
	if push.length() > 0.01:
		recoil = -SpritePose.screen_x(sprite, push.normalized()) * 0.3

	FloatingText.spawn(
		get_parent(),
		global_position + Vector3(0, height / 2.0 + 2.5, 0),
		str(amount),
		Color.WHITE
	)

	# Don't wait for the next snapshot to drop the bar
	if puppet:
		health = max(health - amount, 0.0)
		health_changed.emit(health, max_health)
	update_label()


func fx_dizzy():

	FloatingText.spawn(
		get_parent(),
		global_position + Vector3(0, height / 2.0 + 4.0, 0),
		"DIZZY",
		Color(1.0, 0.95, 0.4)
	)


# Crumble into ash
func fx_die():

	state = State.DEAD
	dizzy_label.visible = false
	remove_from_group("enemies")
	alert_label.visible = false
	label.visible = false
	set_collision_layer(0)
	set_collision_mask(0)
	fx_sound("enemy_death")
	fx_clear_tele(true)

	AshBurst.spawn(get_parent(), global_position, clamp(data["size"], 0.6, 3.0))
	var tween = create_tween().set_parallel()
	tween.tween_property(sprite, "scale", Vector3(1.3, 0.1, 1.0), 0.4)
	tween.tween_property(sprite, "position:y", -height / 2.0, 0.4)
	tween.tween_property(sprite, "modulate", Color(0.1, 0.1, 0.1, 0.0), 0.4)
	if glow_sprite:
		tween.tween_property(glow_sprite, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)

	if puppet:
		died.emit(self)


# ============================================================
# NETWORK (host snapshots -> guest puppets)
# ============================================================

func net_state() -> PackedFloat32Array:

	var flags = (1 if striking else 0) | (2 if launched else 0)
	return PackedFloat32Array([
		global_position.x, global_position.y, global_position.z,
		velocity.x, velocity.y, velocity.z,
		atan2(facing.x, facing.z), state, health, flags,
		state_timer, windup_time, spin_angle,
	])


func apply_net_state(s: PackedFloat32Array, at: int):

	if state == State.DEAD:
		return

	net_pos = Vector3(s[at], s[at + 1], s[at + 2])
	net_vel = Vector3(s[at + 3], s[at + 4], s[at + 5])
	net_age = 0.0
	if not has_net_state:
		has_net_state = true
		global_position = net_pos
	facing = Vector3(sin(s[at + 6]), 0, cos(s[at + 6]))

	var new_state = int(s[at + 7]) as State
	if new_state != state:
		state = new_state
		alert_label.visible = state == State.DETECTED
		dizzy_label.visible = state == State.DIZZY

	if not is_equal_approx(s[at + 8], health):
		health = s[at + 8]
		health_changed.emit(max(health, 0.0), max_health)
		update_label()

	var flags = int(s[at + 9])
	striking = flags & 1 != 0
	launched = flags & 2 != 0
	state_timer = s[at + 10]
	windup_time = max(s[at + 11], 0.01)
	spin_angle = s[at + 12]


# Glide toward where the host has it, a little ahead along its velocity,
# so it moves smoothly between snapshots instead of stepping
func puppet_process(delta):

	net_age += delta
	state_timer -= delta
	flash_timer = max(flash_timer - delta, 0.0)
	if has_net_state:
		var target = net_pos + net_vel * min(net_age, 0.15)
		if global_position.distance_to(target) > NET_SNAP_DIST:
			global_position = target
		else:
			global_position = global_position.lerp(target, 1.0 - exp(-15.0 * delta))
	velocity = net_vel
	update_visuals(delta)


# ============================================================
# VISUALS
# ============================================================

func face(direction: Vector3):

	if direction.length() > 0.01:
		facing = direction.normalized()


func update_visuals(delta):

	anim_time += delta

	# Art faces right; flip when heading left on this player's screen
	var viewer = NetSync.local_player()
	if viewer and abs(facing.x) + abs(facing.z) > 0.01:
		var on_screen = viewer.iso_basis().inverse() * facing
		if abs(on_screen.x) > 0.15:
			base_flip = on_screen.x < 0

	var winding_up = state == State.ATTACK and not striking
	var moving = Vector2(velocity.x, velocity.z).length() > 0.5
	# Leaning by +toward_x tips the top away from where it faces
	var toward_x = SpritePose.screen_x(sprite, facing)
	var target = Vector2.ONE
	var target_lean = 0.0
	var lift = 0.0

	if launched:
		# Knocked onto its back in the air
		target = Vector2(0.9, 1.1)
		target_lean = toward_x * 0.5
	elif winding_up:
		# Crouch, swell and rear back before striking
		var t = clamp(1.0 - state_timer / windup_time, 0.0, 1.0)
		target = Vector2(1.0 + 0.12 * t, 1.0 - 0.1 * t)
		target_lean = toward_x * 0.18 * t
	elif state == State.ATTACK and striking:
		# Lunge into the strike
		target = Vector2(0.92, 1.1)
		target_lean = -toward_x * 0.25
	elif state == State.DIZZY:
		# Reeling
		var w = sin(anim_time * 9.0) * 0.08
		target = Vector2(1.0 + w, 1.0 - w)
		target_lean = sin(anim_time * 4.5) * 0.2
	elif state == State.DETECTED:
		# Startled hop
		var t = clamp(1.0 - state_timer / detect_time, 0.0, 1.0)
		lift = sin(t * PI) * height * 0.2
		target = Vector2(0.9, 1.12)
	elif moving:
		# Hop along with a little squash on landing, waddling side to side
		var stride = anim_time * (6.0 + move_speed)
		var step = abs(sin(stride))
		lift = step * height * 0.06
		target = Vector2(1.0 + 0.04 * (1.0 - step), 1.0 - 0.04 * (1.0 - step))
		var heading_x = SpritePose.screen_x(sprite, flat(velocity)) / max(move_speed, 1.0)
		target_lean = clamp(-heading_x * 0.12, -0.3, 0.3) + sin(stride) * 0.05
	else:
		# Breathing
		var b = sin(anim_time * 2.5) * 0.025
		target = Vector2(1.0 - b * 0.5, 1.0 + b)

	sprite_scale = sprite_scale.lerp(target, 14.0 * delta)
	lean = lerp(lean, target_lean, 12.0 * delta)
	recoil = lerp(recoil, 0.0, 10.0 * delta)
	# Spinning: the sprite turns edge-on and flips as it goes round
	var turn = cos(spin_angle)
	SpritePose.apply(sprite, lean + recoil, Vector2(sprite_scale.x * max(abs(turn), 0.12), sprite_scale.y))
	sprite.flip_h = base_flip != (turn < 0.0)
	if glow_sprite:
		glow_sprite.flip_h = sprite.flip_h
	sprite.position.y = sprite_base_y + lift

	if flash_timer > 0.0:
		sprite.modulate = Color(2.5, 2.5, 2.5)
	elif winding_up:
		# Glow red while winding up so the player can dodge
		var t = clamp(1.0 - state_timer / windup_time, 0.0, 1.0)
		sprite.modulate = Color.WHITE.lerp(Color(1.8, 0.35, 0.3), t)
	elif state == State.DIZZY:
		sprite.modulate = Color(1.25, 1.2, 0.8)
	else:
		sprite.modulate = Color.WHITE

	if state == State.DIZZY:
		dizzy_label.position.y = alert_label.position.y + sin(anim_time * 6.0) * 0.3

	if glow_sprite:
		var pulse = glow_strength * (1.0 + sin(anim_time * 3.0) * 0.12)
		glow_sprite.modulate = Color(pulse, pulse, pulse, 1.0)

	# Name + health only show once the creature is engaged or hurt
	label.visible = state != State.IDLE or health < max_health


func update_label():

	var bars = 10
	var filled = int(ceil(clamp(health / max_health, 0.0, 1.0) * bars))
	label.text = data["name"] + "\n" + "■".repeat(filled) + "□".repeat(bars - filled)


func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
