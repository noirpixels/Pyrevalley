extends CharacterBody3D

# A creature from CodexData, driven by the GDD state machine:
#   IDLE -> DETECTED -> CHASE -> ATTACK -> (HURT) -> DEAD
# Spawned by creature_spawner.gd; call setup() before adding to the tree.

signal died(enemy)
signal health_changed(current, maximum)

enum State { IDLE, DETECTED, CHASE, ATTACK, HURT, DEAD }

const FloatingText = preload("res://floating_text.gd")
const ItemPickup = preload("res://item_pickup.gd")
const EmberPickup = preload("res://ember_pickup.gd")

const PLAYER_RADIUS = 2.5
# Same pixel density as Veyl's sprite (216 px = 8.1 units)
const SPRITE_PIXEL_SIZE = 0.0375

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

var data: Dictionary
var spawner_id: String = ""
var player: Node3D
var home: Vector3

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

var body_texture: Texture2D
var sprite: Sprite3D
var glow_sprite: Sprite3D
var sprite_base_y: float
var sprite_scale: Vector2 = Vector2.ONE
var glow_strength: float = 1.0
var label: Label3D
var alert_label: Label3D

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)


func setup(creature: Dictionary, id: String = ""):

	data = creature
	spawner_id = id

	max_health = creature["health"]
	health = max_health

	# Codex speed (6-40) -> world units per second
	move_speed = 1.5 + creature["speed"] * 0.2

	# Collision is a cylinder roughly the size of the sprite
	body_texture = load(creature["sprite"])
	radius = 1.4 * creature["size"]
	height = body_texture.get_height() * SPRITE_PIXEL_SIZE * 0.9


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
	sprite_base_y = -height / 2.0 + visual_height / 2.0

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


# ============================================================
# STATE MACHINE
# ============================================================

func enter_state(new_state: State):

	state = new_state
	striking = false
	alert_label.visible = new_state == State.DETECTED

	match new_state:
		State.DETECTED:
			state_timer = detect_time
		State.ATTACK:
			state_timer = windup_time
			begin_attack()
		State.HURT:
			state_timer = hurt_time


func _physics_process(delta):

	if state == State.DEAD:
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	if not is_on_floor():
		velocity.y -= gravity * delta

	state_timer -= delta
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

		State.HURT:
			if state_timer <= 0.0:
				enter_state(State.CHASE)

	velocity.x = move.x + knockback.x
	velocity.z = move.z + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 40.0 * delta)

	move_and_slide()
	update_visuals(delta)


# Wander near home; walk back and heal up after losing the player
func idle_movement(delta) -> Vector3:

	var to_home = flat(home - global_position)

	if to_home.length() <= 4.0:
		returning = false

	if to_home.length() > 4.0:
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
	return dir * move_speed


# ============================================================
# ATTACK HOOKS (overridden by boss.gd)
# ============================================================

func attack_reach() -> float:
	return radius + PLAYER_RADIUS + 1.5


func wants_to_attack(dist: float) -> bool:
	return dist <= attack_reach() and cooldown_timer <= 0.0


func begin_attack():
	face(flat(player.global_position - global_position))


func attack_movement() -> Vector3:
	return Vector3.ZERO


func perform_attack(dist: float):
	Sfx.play("enemy_attack")
	if dist <= attack_reach() + 1.0 and not player.dead:
		player.take_damage(
			CodexData.calc_damage(data["attack"], player.defense),
			global_position
		)


# ============================================================
# DAMAGE / DEATH
# ============================================================

func take_damage(amount: int, from: Vector3):

	if state == State.DEAD:
		return

	health -= amount
	flash_timer = 0.12
	health_changed.emit(max(health, 0.0), max_health)
	Sfx.play("hit")

	# Heavier creatures get pushed less
	var push = flat(global_position - from)
	if push.length() > 0.01:
		knockback = push.normalized() * 9.0 / data["size"]

	FloatingText.spawn(
		get_parent(),
		global_position + Vector3(0, height / 2.0 + 2.5, 0),
		str(amount),
		Color.WHITE
	)

	update_label()

	if health <= 0.0:
		die()
	elif staggerable or state == State.IDLE or state == State.DETECTED:
		enter_state(State.HURT)


func die():

	state = State.DEAD
	remove_from_group("enemies")
	alert_label.visible = false
	label.visible = false
	set_collision_layer(0)
	set_collision_mask(0)
	Sfx.play("enemy_death")

	GameState.record_creature_defeat(spawner_id, data["name"])
	drop_loot()
	died.emit(self)

	# Collapse into ash
	var tween = create_tween().set_parallel()
	tween.tween_property(sprite, "scale", Vector3(1.3, 0.1, 1.0), 0.4)
	tween.tween_property(sprite, "position:y", -height / 2.0, 0.4)
	tween.tween_property(sprite, "modulate", Color(0.1, 0.1, 0.1, 0.0), 0.4)
	if glow_sprite:
		tween.tween_property(glow_sprite, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)


func drop_loot():

	var world = get_parent()
	var ground = Vector3(global_position.x, 0, global_position.z)

	if data.get("drop", "") != "":
		var item = ItemPickup.new()
		item.item_name = data["drop"]
		world.add_child(item)
		item.global_position = ground + Vector3(1.0, 0, 0)

	if randf() < ember_drop_chance:
		var ember = EmberPickup.new()
		ember.player = player
		world.add_child(ember)
		ember.global_position = ground + Vector3(-1.0, 0, 0)


# Called when the player respawns: survivors forget the fight
func reset():

	if state == State.DEAD:
		return

	health = max_health
	global_position = home
	returning = false
	velocity = Vector3.ZERO
	knockback = Vector3.ZERO
	enter_state(State.IDLE)
	health_changed.emit(health, max_health)
	update_label()


# ============================================================
# VISUALS
# ============================================================

func face(direction: Vector3):

	if direction.length() > 0.01:
		facing = direction.normalized()


func update_visuals(delta):

	anim_time += delta

	# Art faces right; flip when heading left on screen
	if player and abs(facing.x) + abs(facing.z) > 0.01:
		var on_screen = player.iso_basis().inverse() * facing
		if abs(on_screen.x) > 0.15:
			sprite.flip_h = on_screen.x < 0
			if glow_sprite:
				glow_sprite.flip_h = sprite.flip_h

	var winding_up = state == State.ATTACK and not striking
	var moving = Vector2(velocity.x, velocity.z).length() > 0.5
	var target = Vector2.ONE
	var lift = 0.0

	if winding_up:
		# Crouch and swell before striking
		var t = clamp(1.0 - state_timer / windup_time, 0.0, 1.0)
		target = Vector2(1.0 + 0.12 * t, 1.0 - 0.1 * t)
	elif state == State.ATTACK and striking:
		target = Vector2(0.92, 1.1)
	elif moving:
		# Hop along with a little squash on landing
		var step = abs(sin(anim_time * (6.0 + move_speed)))
		lift = step * height * 0.06
		target = Vector2(1.0 + 0.04 * (1.0 - step), 1.0 - 0.04 * (1.0 - step))
	else:
		# Breathing
		var b = sin(anim_time * 2.5) * 0.025
		target = Vector2(1.0 - b * 0.5, 1.0 + b)

	sprite_scale = sprite_scale.lerp(target, 14.0 * delta)
	sprite.scale = Vector3(sprite_scale.x, sprite_scale.y, 1.0)
	sprite.position.y = sprite_base_y + lift - (1.0 - sprite_scale.y) * height * 0.5

	if flash_timer > 0.0:
		sprite.modulate = Color(2.5, 2.5, 2.5)
	elif winding_up:
		# Glow red while winding up so the player can dodge
		var t = clamp(1.0 - state_timer / windup_time, 0.0, 1.0)
		sprite.modulate = Color.WHITE.lerp(Color(1.8, 0.35, 0.3), t)
	else:
		sprite.modulate = Color.WHITE

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
