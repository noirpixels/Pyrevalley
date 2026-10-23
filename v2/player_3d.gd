extends CharacterBody3D

signal health_changed(current, maximum)
signal died
signal respawned
signal interact_target_changed(target)

const SlashEffect = preload("res://slash_effect.gd")
const FloatingText = preload("res://floating_text.gd")

@export_group("2.5D Character Textures")
@export var texture_front: Texture2D
@export var texture_back: Texture2D
@export var texture_right: Texture2D

@export_group("Movement")
@export var speed: float = 8.0
@export var jump_velocity: float = 4.5

@export_group("Isometric Camera")
@export var follow_smoothness: float = 10.0
# World yaw of the camera. 45 = classic isometric diagonal.
@export var iso_yaw_degrees: float = 45.0
# Orthographic view height per zoom step
@export var ortho_zoom_scale: float = 5.6
# Orthographic cameras sit far back so tall trees never cross the near plane
@export var ortho_distance: float = 16.0

# Camera starting position
# 0 = Far Top-Down
# 1 = Medium Isometric
# 2 = Close Isometric
var zoom_state: int = 1

# Continuous zoom
@export var min_zoom: float = 2.0
@export var max_zoom: float = 12.0
@export var zoom_speed: float = 1.0

var current_zoom: float = 5.0

# Pull the camera back during the boss fight so The Ashbound fits on screen
@export var boss_fight_zoom: float = 7.5
var zoom_before_boss: float = -1.0

@export_group("Combat")
@export var max_health: float = 100.0
# Total ATK = base_attack + equipped weapon's attack (see GameState.ITEMS)
@export var base_attack: float = 13.0
@export var defense: float = 15.0
@export var attack_arc_degrees: float = 120.0
@export var interact_range: float = 7.0
@export var dash_speed: float = 18.0
@export var dash_time: float = 0.18
@export var dash_cooldown: float = 0.8

var health: float
var dead: bool = false
var aim_dir: Vector3 = Vector3.FORWARD
var attack_timer: float = 0.0
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_dir: Vector3 = Vector3.ZERO
var invuln_timer: float = 0.0
var start_position: Vector3
var interact_target: Node3D = null

@onready var sprite: Sprite3D = find_child("CharacterSprite")
@onready var camera_boom: Node3D = find_child("CameraBoom")
@onready var spring_arm: SpringArm3D = find_child("SpringArm3D")
@onready var main_cam: Camera3D = find_child("MainGameCamera")

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)


# ============================================================
# ISOMETRIC CAMERA PRESETS
# ============================================================

# x = boom height, y = zoom, z = boom pitch (degrees)
var presets = {
	0: Vector3(3.0, 7.5, -65.0),   # Far Top-Down
	1: Vector3(1.0, 5.0, -35.0),    # Medium Isometric
	2: Vector3(0.5, 3.0, -30.0)     # Close Isometric
}


func _ready():

	add_to_group("player")
	start_position = global_position

	# Restore progress from the save (position, HP)
	GameState.ensure_loaded()
	health = max_health

	if GameState.player_position != null:
		global_position = GameState.player_position
	if GameState.player_health > 0.0:
		health = min(GameState.player_health, max_health)

	# Isometric: free cursor for aiming
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Character sprite always faces the camera
	if sprite:

		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.shaded = true

		# Depth-tested so scenery can stand in front of Veyl; trees fade
		# around the sprite instead (occluder.gdshader)
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_blob_shadow()

		if texture_front:
			sprite.texture = texture_front

	# Don't let the spring arm collide with Veyl, or with trees: pulling the
	# camera in just clips the canopies between it and the player
	if spring_arm:
		spring_arm.add_excluded_object(get_rid())
		spring_arm.collision_mask = 0

	apply_camera_preset(zoom_state, true)

	GameState.boss_engaged.connect(_on_boss_engaged)
	GameState.boss_disengaged.connect(_on_boss_disengaged)


# ============================================================
# INPUT
# ============================================================

# Unhandled so clicks on HUD buttons don't also swing the sword
func _unhandled_input(event):

	if dead:
		return

	# --------------------------------------------------------
	# MOUSE WHEEL ZOOM / ATTACK
	# --------------------------------------------------------

	if event is InputEventMouseButton:

		if event.pressed:

			# Scroll UP = zoom IN
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:

				current_zoom = clamp(
					current_zoom - zoom_speed,
					min_zoom,
					max_zoom
				)

			# Scroll DOWN = zoom OUT
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:

				current_zoom = clamp(
					current_zoom + zoom_speed,
					min_zoom,
					max_zoom
				)

			# Left click swings toward the cursor
			elif event.button_index == MOUSE_BUTTON_LEFT:

				try_attack()


	# --------------------------------------------------------
	# DASH
	# --------------------------------------------------------

	if event is InputEventKey:

		if event.is_pressed() and not event.is_echo():

			if event.keycode == KEY_SHIFT:

				try_dash()

			elif event.keycode == KEY_E and interact_target:

				interact_target.interact(self)


# ============================================================
# PHYSICS / MOVEMENT
# ============================================================

func _physics_process(delta):

	attack_timer = max(attack_timer - delta, 0.0)
	dash_timer = max(dash_timer - delta, 0.0)
	dash_cooldown_timer = max(dash_cooldown_timer - delta, 0.0)
	invuln_timer = max(invuln_timer - delta, 0.0)

	# --------------------------------------------------------
	# GRAVITY
	# --------------------------------------------------------

	if not is_on_floor():

		velocity.y -= gravity * delta


	update_camera(delta)
	RenderingServer.global_shader_parameter_set("player_position", global_position)

	if dead:

		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return


	# --------------------------------------------------------
	# JUMP
	# --------------------------------------------------------

	if Input.is_key_pressed(KEY_SPACE):

		if is_on_floor():

			velocity.y = jump_velocity


	# --------------------------------------------------------
	# WASD MOVEMENT (screen-relative)
	# --------------------------------------------------------

	var input_dir = Vector2.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1

	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1

	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1


	var direction_2d = input_dir.normalized()

	# Rotate input by the camera yaw so W is always "up" on screen
	var direction = iso_basis() * Vector3(
		direction_2d.x,
		0,
		direction_2d.y
	)


	if dash_timer > 0.0:

		velocity.x = dash_dir.x * dash_speed
		velocity.z = dash_dir.z * dash_speed

	elif direction != Vector3.ZERO:

		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

	else:

		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)


	# Aim at the mouse cursor
	var target = mouse_ground_point()
	var to_target = target - global_position
	to_target.y = 0

	if to_target.length() > 0.1:
		aim_dir = to_target.normalized()

	update_sprite_facing()
	update_interact_target()

	move_and_slide()


# ============================================================
# CAMERA
# ============================================================

func iso_basis() -> Basis:

	return Basis(Vector3.UP, deg_to_rad(iso_yaw_degrees))


func update_camera(delta):

	if not (camera_boom and spring_arm and main_cam):
		return

	# Keep boom centered on the player
	camera_boom.position.x = 0
	camera_boom.position.z = 0

	# Fixed world yaw, regardless of the player's own rotation
	camera_boom.rotation.y = deg_to_rad(iso_yaw_degrees) - rotation.y
	camera_boom.rotation.z = 0

	spring_arm.spring_length = lerp(
		spring_arm.spring_length,
		camera_distance(),
		follow_smoothness * delta
	)

	# Orthographic cameras zoom by view size, not distance
	if main_cam.projection == Camera3D.PROJECTION_ORTHOGONAL:

		main_cam.size = lerp(
			main_cam.size,
			current_zoom * ortho_zoom_scale,
			follow_smoothness * delta
		)

	# Skip until the spring arm has moved the camera off the player
	var focus = global_position + Vector3(0, 1.0, 0)

	var offset = main_cam.global_position - focus

	if Vector2(offset.x, offset.z).length() > 0.1:

		main_cam.look_at(focus)


func apply_camera_preset(
	preset_idx: int,
	instant: bool
):

	var preset = presets[preset_idx]

	if camera_boom:

		camera_boom.position.y = preset.x
		camera_boom.rotation_degrees.x = preset.z
		camera_boom.rotation.y = deg_to_rad(iso_yaw_degrees) - rotation.y

	if spring_arm:

		current_zoom = preset.y

		if instant:

			spring_arm.spring_length = camera_distance()

	if main_cam and instant:

		main_cam.size = current_zoom * ortho_zoom_scale


# Soft shadow under vair feet, like the creatures have
func add_blob_shadow():

	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.32
	mesh.bottom_radius = 0.32
	mesh.height = 0.004
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.4)
	var blob = MeshInstance3D.new()
	blob.mesh = mesh
	blob.material_override = mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.scale = Vector3(1.0, 1.0, 0.6)
	var shape = $CollisionShape3D.shape as CylinderShape3D
	blob.position.y = -shape.height / 2.0 + 0.01
	add_child(blob)


# Orthographic zoom comes from the view size, so distance only needs to clear the scenery
func camera_distance() -> float:

	if main_cam and main_cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return ortho_distance

	return current_zoom


# Where the cursor points on the ground plane Veyl stands on
func mouse_ground_point() -> Vector3:

	if not main_cam:
		return global_position + aim_dir

	var mouse = get_viewport().get_mouse_position()
	var origin = main_cam.project_ray_origin(mouse)
	var normal = main_cam.project_ray_normal(mouse)
	var hit = Plane(Vector3.UP, global_position.y).intersects_ray(origin, normal)

	if hit == null:
		return global_position + aim_dir

	return hit


# Front / back / side texture based on aim relative to the camera
func update_sprite_facing():

	if not sprite:
		return

	var local = iso_basis().inverse() * aim_dir

	if abs(local.x) > abs(local.z) and texture_right:

		sprite.texture = texture_right
		sprite.flip_h = local.x < 0

	elif local.z > 0 and texture_front:

		sprite.texture = texture_front
		sprite.flip_h = false

	elif texture_back:

		sprite.texture = texture_back
		sprite.flip_h = false


# ============================================================
# COMBAT
# ============================================================

func try_attack():

	if attack_timer > 0.0:
		return

	var weapon = GameState.weapon()
	var attack_range: float = weapon["range"]
	attack_timer = weapon["cooldown"]
	Sfx.play("attack")

	var half_arc = deg_to_rad(attack_arc_degrees) / 2.0

	for enemy in get_tree().get_nodes_in_group("enemies"):

		var offset = enemy.global_position - global_position
		offset.y = 0

		if offset.length() > attack_range + enemy.radius:
			continue

		if offset.length() > 0.01 and aim_dir.angle_to(offset.normalized()) > half_arc:
			continue

		enemy.take_damage(
			CodexData.calc_damage(get_attack(), enemy.data["defense"]),
			global_position
		)

	# Swing visual (spawned in world space, not under the scaled player)
	var slash = SlashEffect.new()
	slash.radius = attack_range
	slash.arc_degrees = attack_arc_degrees
	get_parent().add_child(slash)
	slash.global_position = Vector3(global_position.x, 0.1, global_position.z)
	slash.global_basis = Basis.looking_at(aim_dir)

	# Quick squash on the sprite as the swing animation
	if sprite:
		var base_scale = Vector3.ONE * 0.75
		sprite.scale = base_scale * Vector3(1.15, 0.9, 1.0)
		create_tween().tween_property(sprite, "scale", base_scale, 0.15)


func get_attack() -> float:

	return base_attack + GameState.weapon()["attack"]


func try_dash():

	if dash_cooldown_timer > 0.0:
		return

	var horizontal = Vector3(velocity.x, 0, velocity.z)
	dash_dir = horizontal.normalized() if horizontal.length() > 0.1 else aim_dir

	dash_timer = dash_time
	dash_cooldown_timer = dash_cooldown
	invuln_timer = dash_time + 0.05


func take_damage(amount: int, from: Vector3):

	if dead or invuln_timer > 0.0:
		return

	health = max(health - amount, 0.0)
	invuln_timer = 0.3
	health_changed.emit(health, max_health)
	Sfx.play("player_hurt")

	FloatingText.spawn(
		get_parent(),
		global_position + Vector3(0, 5, 0),
		str(amount),
		Color(1.0, 0.3, 0.3)
	)

	# Small knockback away from the attacker
	var push = global_position - from
	push.y = 0
	if push.length() > 0.01:
		velocity += push.normalized() * 8.0

	if sprite:
		sprite.modulate = Color(1.0, 0.3, 0.3)
		create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.25)

	if health <= 0.0:
		die()


func heal(amount: float):

	if dead:
		return

	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)

	FloatingText.spawn(
		get_parent(),
		global_position + Vector3(0, 5, 0),
		"+" + str(int(amount)),
		Color(1.0, 0.7, 0.2)
	)


func die():

	dead = true

	if sprite:
		create_tween().tween_property(sprite, "modulate", Color(0.3, 0.3, 0.3, 0.6), 0.6)

	died.emit()


# Back to the last ember shrine. Quest, inventory and kills are kept.
func respawn():

	global_position = GameState.checkpoint_position if GameState.checkpoint_position != null else start_position
	velocity = Vector3.ZERO
	health = max_health
	dead = false
	invuln_timer = 1.0

	if sprite:
		sprite.modulate = Color.WHITE

	get_tree().call_group("enemies", "reset")
	health_changed.emit(health, max_health)
	respawned.emit()


# ============================================================
# INTERACTION (NPCs etc.)
# ============================================================

func update_interact_target():

	var best: Node3D = null
	var best_dist = interact_range

	for node in get_tree().get_nodes_in_group("interactable"):

		var offset = node.global_position - global_position
		offset.y = 0

		if offset.length() < best_dist:
			best = node
			best_dist = offset.length()

	if best != interact_target:
		interact_target = best
		interact_target_changed.emit(best)


func _on_boss_engaged(_boss):

	if zoom_before_boss < 0.0:
		zoom_before_boss = current_zoom
	current_zoom = max(current_zoom, boss_fight_zoom)


func _on_boss_disengaged():

	if zoom_before_boss >= 0.0:
		current_zoom = zoom_before_boss
		zoom_before_boss = -1.0
