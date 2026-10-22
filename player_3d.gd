extends CharacterBody3D

# Veyl. In a multiplayer session every player has one: theirs is run here
# (group "player", camera, input) and everyone else's is a remote copy
# that follows the state their machine sends (net_sync.gd). Damage to a
# Veyl is always applied by its own player's machine.
# A bot Veyl (duel_bot.gd, the Ember Shade) runs this same code on the
# host, with duel_bot.gd steering it instead of the keyboard.

signal health_changed(current, maximum)
signal died
signal respawned
signal interact_target_changed(target)
signal combo_changed(count, maximum, multiplier)
# The tool bar slot in hand changed, or what's in it did
signal held_changed

const SlashEffect = preload("res://slash_effect.gd")
const FloatingText = preload("res://floating_text.gd")
const CombatMoves = preload("res://combat_moves.gd")
const ComboTracker = preload("res://combo_tracker.gd")
const VeylAnimator = preload("res://veyl_animator.gd")
const HitSpark = preload("res://hit_spark.gd")
const SpritePose = preload("res://sprite_pose.gd")
const InkPost = preload("res://ink_post.gd")
const Items = preload("res://items.gd")
const Harvest = preload("res://harvest.gd")

# An attack released this close to the end of the cooldown waits for it;
# one released earlier is a fumble and breaks the combo
const ATTACK_BUFFER = 0.15
# Pause after a combo reaches Max Combo before the next chain can start
const COMBO_END_LAG = 0.45
# Quiet time that ends a scroll gesture
const SCROLL_GAP = 0.25
# Trackpad pan distance that counts as a scroll attack
const PAN_THRESHOLD = 1.0
# macOS natural scrolling reverses the wheel and pan direction Godot reports,
# so flip it back to match the way the fingers or wheel actually move
var scroll_flip: bool = OS.get_name() == "macOS"
# Game speed during hit-stop, the brief freeze when a hit lands
const HIT_STOP_SCALE = 0.05
# Seconds from the button press to the blade connecting, matching the
# strike frame of each swing in veyl_puppet.gd
const IMPACT_DELAY = {"left": 0.07, "right": 0.07, "up": 0.09, "down": 0.11, "aerial": 0.12}
# A grounded swing steps Veyl forward into it, unless a target is already close
const LUNGE_SPEED = 13.0
const LUNGE_TIME = 0.08
const LUNGE_SKIP_DIST = 3.5
# Swing sound pitch per move: slams lower, launches higher
const SWING_PITCH = {"left": 1.0, "right": 1.05, "up": 1.2, "down": 0.8, "aerial": 0.75}
# Height (world units) where Veyl's shadow is at its smallest and faintest
const SHADOW_FADE_HEIGHT = 6.0
# How quickly WASD can bend Veyl's path in mid-air; on the ground it's instant
const AIR_STEER = 5.0
# Extra damage on a dizzy target
const DIZZY_BONUS = 1.25
# Pad buttons for each move (mouse attacks are handled as events below)
const PAD_MOVES = {"left": "strike_left", "right": "strike_right", "up": "launch", "down": "slam"}
# Right stick tilt that takes over aiming
const AIM_STICK_DEADZONE = 0.3
# With a pad, an attack turns toward an enemy this far off the aim (degrees)
const AIM_ASSIST_DEGREES = 70.0
# Tool bar slots, in order (keys 1-3, d-pad left/right)
const HELD_SLOTS = ["weapon", "pickaxe", "axe"]
# Swinging a pickaxe or axe: reach and pace
const TOOL_SWING = {"range": 7.0, "cooldown": 0.55, "moves": "sword", "attack": 0.0, "magic": ""}
# Mosswoven gear mends this much health per second
const MEND_RATE = 0.6
# Ashweight hits shove and daze this much harder
const ASHWEIGHT = 1.4
# Emberbrand sets creatures burning for this long
const BURN_TIME = 3.0
# Hops up a bank of a dug hole too steep to walk (taller than a jump)
const CLIMB_SPEED = 15.5
# Steepest ground Veyl walks up (the mining sites' hills stay under it),
# and how far vae sticks to the ground walking down a slope
const SLOPE_LIMIT = 52.0
const FLOOR_SNAP = 2.0
# Duels in the Proving Ring hit softer than Veyl's sword hits creatures
const PVP_DAMAGE = 0.5
# Share of a move's launch a Veyl takes from another Veyl
const PVP_LAUNCH = 0.8
# A remote Veyl this far from where its player has it jumps there
const NET_SNAP_DIST = 10.0
# The Ember Shade is drawn darker than a player's Veyl
const SHADE_TINT = Color(0.5, 0.42, 0.45)

@export_group("2.5D Character Textures")
@export var texture_front: Texture2D
@export var texture_back: Texture2D
@export var texture_right: Texture2D

@export_group("Movement")
@export var speed: float = 8.0
@export var jump_velocity: float = 9.0

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

var combo = ComboTracker.new()
var buffered_move: Dictionary = {}
# One scroll gesture is one attack: the wheel (and a trackpad's momentum)
# sends a burst of events, so later ones are ignored until it goes quiet
var scroll_locked: bool = false
var scroll_quiet: float = 0.0
var pan_amount: float = 0.0
# Physics frame Veyl last ran on, to spot the first frame after a pause
var last_physics_frame: int = 0
# Swings waiting for the blade to connect: {"move", "aim", "time"}
var pending_swings: Array = []
var lunge_timer: float = 0.0
var lunge_dir: Vector3 = Vector3.ZERO
var hit_stop_scale: float = 1.0

# Another player's Veyl, shown here
var remote: bool = false
var peer_id: int = 1
# Run by duel_bot.gd: walks where bot_move points
var bot: bool = false
var bot_move: Vector3 = Vector3.ZERO
var base_tint: Color = Color.WHITE
# When this Veyl last swung (the bot reads it to dodge)
var last_swing_msec: int = -100000
# Local Duel (duel.gd): read this player's half of the keyboard ("p1" or
# "p2", pad.gd DUEL_ACTIONS), always face the opponent, and hit them
# directly. The duel's own camera shows both.
var input_prefix: String = ""
# Side-on duel view (duel.gd): Veyl stays on the z = 0 plane, Up also
# jumps, swings stand upright and reach counts height
var plane_lock: bool = false
var opponent: Node3D = null
# Which tool bar slot is in hand (HELD_SLOTS)
var held_slot: String = "weapon"
# What's in hand, as items.gd held_code (shown on other players' screens)
var held_code: int = -1
var base_defense: float
# A menu or dialogue is open (multiplayer keeps running underneath)
var input_blocked: bool = false
var net_pos: Vector3
var net_vel: Vector3 = Vector3.ZERO
var net_age: float = 0.0
var remote_on_floor: bool = true
# Who last hit this Veyl in the Proving Ring
var last_attacker: int = 0
var died_in_ring: bool = false

@onready var sprite: Sprite3D = find_child("CharacterSprite")
@onready var camera_boom: Node3D = find_child("CameraBoom")
@onready var spring_arm: SpringArm3D = find_child("SpringArm3D")
@onready var main_cam: Camera3D = find_child("MainGameCamera")
var animator: VeylAnimator
# Camera shake strength (world units), decays every frame
var shake: float = 0.0
var hit_stop_left: float = 0.0
# Ground shadow; it stays on the floor while Veyl is in the air
var blob: MeshInstance3D
var blob_mat: StandardMaterial3D
var blob_base_scale: Vector3

# Heavier than Earth gravity so jumps and launches don't float
var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
) * 2.5


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

	# A bot isn't a player: creatures ignore it, and other Veyls see it the
	# way they see each other ("remote_players")
	if bot:
		add_to_group("duel_bots")
		add_to_group("remote_players")
	elif input_prefix != "":
		add_to_group("duelists")
	elif peer_id == NetSync.BOT_ID:
		add_to_group("remote_players")
	else:
		add_to_group("players")
		add_to_group("remote_players" if remote else "player")
	start_position = global_position
	health = max_health
	base_defense = defense
	floor_max_angle = deg_to_rad(SLOPE_LIMIT)
	floor_snap_length = FLOOR_SNAP
	floor_constant_speed = true
	if peer_id == NetSync.BOT_ID:
		base_tint = SHADE_TINT

	if not remote and not bot and input_prefix == "":
		# Restore progress from the save (position, HP)
		GameState.ensure_loaded()

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
		sprite.modulate = base_tint

		animator = VeylAnimator.new(self, sprite)
		add_child(animator)

	# Don't let the spring arm collide with Veyl, or with trees: pulling the
	# camera in just clips the canopies between it and the player
	if spring_arm:
		spring_arm.add_excluded_object(get_rid())
		spring_arm.collision_mask = 0

	if remote or bot:
		# Walk-through, so players never shove each other around (a bot
		# still walks into the ring's walls)
		collision_layer = 0
		if remote:
			collision_mask = 0
		net_pos = global_position
		if main_cam:
			main_cam.current = false
		add_name_label()
		return

	if input_prefix != "":
		if main_cam:
			main_cam.current = false
		return

	apply_camera_preset(zoom_state, true)

	GameState.gear_changed.connect(refresh_gear)
	refresh_gear()

	GameState.boss_engaged.connect(_on_boss_engaged)
	GameState.boss_disengaged.connect(_on_boss_disengaged)


# ============================================================
# INPUT
# ============================================================

# Unhandled so clicks on HUD buttons don't also swing the sword
func _unhandled_input(event):

	if dead or remote or bot or input_blocked or input_prefix != "":
		return

	# --------------------------------------------------------
	# MOUSE ATTACKS
	# --------------------------------------------------------

	if event is InputEventMouseButton and event.pressed:

		match event.button_index:
			MOUSE_BUTTON_LEFT:
				request_attack("left")
			MOUSE_BUTTON_RIGHT:
				request_attack("right")
			MOUSE_BUTTON_WHEEL_UP:
				scroll_attack("down" if scroll_flip else "up")
			MOUSE_BUTTON_WHEEL_DOWN:
				scroll_attack("up" if scroll_flip else "down")

	# Trackpads send a two-finger scroll as a pan gesture instead
	elif event is InputEventPanGesture:

		scroll_quiet = 0.0
		if not scroll_locked:
			pan_amount += event.delta.y
			if abs(pan_amount) >= PAN_THRESHOLD:
				var pan_up = (pan_amount > 0.0) if scroll_flip else (pan_amount < 0.0)
				scroll_attack("up" if pan_up else "down")



# Local Duel: this player's half of the keyboard
func update_duel_actions():

	if input_blocked:
		return
	if Input.is_action_just_pressed(input_prefix + "_dash"):
		try_dash()
	for kind in PAD_MOVES:
		if Input.is_action_just_pressed(input_prefix + "_" + PAD_MOVES[kind]):
			request_attack(kind)


# Dash, interact, zoom and pad attacks are actions (pad.gd), polled so a
# trigger pull counts once rather than on every bit of travel
func update_actions():

	# Skipping the frame count here makes the first free frame count as
	# "just unpaused" too
	if input_blocked:
		return

	# The press that closed a menu shouldn't also act in the game
	var frame = Engine.get_physics_frames()
	var just_unpaused = frame - last_physics_frame > 1
	last_physics_frame = frame
	if just_unpaused:
		return

	if Input.is_action_just_pressed("dash"):
		try_dash()

	if Input.is_action_just_pressed("interact") and interact_target:
		interact_target.interact(self)

	# Zoom moved off the wheel, which now attacks
	if Input.is_action_just_pressed("zoom_in"):
		current_zoom = clamp(current_zoom - zoom_speed, min_zoom, max_zoom)
	elif Input.is_action_just_pressed("zoom_out"):
		current_zoom = clamp(current_zoom + zoom_speed, min_zoom, max_zoom)

	for kind in PAD_MOVES:
		if Input.is_action_just_pressed(PAD_MOVES[kind]):
			request_attack(kind)

	for i in HELD_SLOTS.size():
		if Input.is_action_just_pressed("tool_%d" % (i + 1)):
			hold(HELD_SLOTS[i])
	var step = int(Input.is_action_just_pressed("tool_next")) - int(Input.is_action_just_pressed("tool_prev"))
	if step != 0:
		hold(HELD_SLOTS[posmod(HELD_SLOTS.find(held_slot) + step, HELD_SLOTS.size())])


# ============================================================
# PHYSICS / MOVEMENT
# ============================================================

func _physics_process(delta):

	if remote:
		remote_process(delta)
		return

	attack_timer = max(attack_timer - delta, 0.0)
	lunge_timer = max(lunge_timer - delta, 0.0)
	if uses_gear():
		mend(delta)
	update_combat(delta)
	update_pending_swings(delta)
	dash_timer = max(dash_timer - delta, 0.0)
	dash_cooldown_timer = max(dash_cooldown_timer - delta, 0.0)
	invuln_timer = max(invuln_timer - delta, 0.0)

	# --------------------------------------------------------
	# GRAVITY
	# --------------------------------------------------------

	if not is_on_floor():

		velocity.y -= gravity * delta


	if not bot and input_prefix == "":
		update_camera(delta)
		RenderingServer.global_shader_parameter_set("player_position", global_position)

	if dead:

		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		update_blob_shadow()
		return


	# --------------------------------------------------------
	# JUMP
	# --------------------------------------------------------

	if input_prefix != "":
		update_duel_actions()
	elif not bot:
		update_actions()

	var jump_held = Input.is_action_pressed(input_prefix + "_jump" if input_prefix != "" else "jump")
	if plane_lock:
		jump_held = jump_held or Input.is_action_pressed(input_prefix + "_move_up" if input_prefix != "" else "move_up")
	if jump_held and not input_blocked and not bot:

		if is_on_floor():

			velocity.y = jump_velocity


	# --------------------------------------------------------
	# WASD / LEFT STICK MOVEMENT (screen-relative)
	# --------------------------------------------------------

	# A stick gives partial tilt for a slower walk; keys are always full
	var p = input_prefix + "_" if input_prefix != "" else ""
	var direction_2d = Vector2.ZERO if input_blocked else Input.get_vector(p + "move_left", p + "move_right", p + "move_up", p + "move_down")

	# Rotate input by the camera yaw so W is always "up" on screen
	var direction = iso_basis() * Vector3(
		direction_2d.x,
		0,
		direction_2d.y
	)
	if bot:
		direction = bot_move
	if plane_lock:
		direction.z = 0.0


	if dash_timer > 0.0:

		velocity.x = dash_dir.x * dash_speed
		velocity.z = dash_dir.z * dash_speed

	elif not is_on_floor():

		# Keep the jump's momentum; input only nudges it, and letting go
		# doesn't stop Veyl dead in the air
		if direction != Vector3.ZERO:
			var steer = 1.0 - exp(-AIR_STEER * delta)
			velocity.x = lerp(velocity.x, direction.x * speed, steer)
			velocity.z = lerp(velocity.z, direction.z * speed, steer)

	elif lunge_timer > 0.0:

		velocity.x = lunge_dir.x * LUNGE_SPEED
		velocity.z = lunge_dir.z * LUNGE_SPEED

	elif direction != Vector3.ZERO:

		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

	else:

		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)


	if bot:

		# duel_bot.gd aims
		pass

	elif input_prefix != "":

		# Fighting-game style: always square up to the opponent
		var to_foe = (opponent.global_position - global_position) if opponent else Vector3.ZERO
		to_foe.y = 0
		if to_foe.length() > 0.1:
			aim_dir = to_foe.normalized()
		elif direction != Vector3.ZERO:
			aim_dir = Vector3(direction.x, 0, direction.z).normalized()

	elif Pad.using_pad:

		# Right stick aims; without it Veyl faces where vae walks
		var stick = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if stick.length() > AIM_STICK_DEADZONE:
			aim_dir = (iso_basis() * Vector3(stick.x, 0, stick.y)).normalized()
		elif direction != Vector3.ZERO:
			aim_dir = Vector3(direction.x, 0, direction.z).normalized()

	else:

		# Aim at the mouse cursor
		var target = mouse_ground_point()
		var to_target = target - global_position
		to_target.y = 0

		if to_target.length() > 0.1:
			aim_dir = to_target.normalized()

	update_sprite_facing()
	if not bot and input_prefix == "":
		update_interact_target()

	move_and_slide()
	if plane_lock:
		global_position.z = 0.0
		velocity.z = 0.0
	if is_on_floor() and direction != Vector3.ZERO:
		climb(direction)
	update_blob_shadow()


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

	shake = move_toward(shake, 0.0, shake * 10.0 * delta + 0.2 * delta)
	main_cam.h_offset = randf_range(-shake, shake)
	main_cam.v_offset = randf_range(-shake, shake)

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
	blob_mat = StandardMaterial3D.new()
	blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_mat.albedo_color = Color(0, 0, 0, 0.4)
	blob = MeshInstance3D.new()
	blob.mesh = mesh
	blob.material_override = blob_mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.scale = Vector3(1.0, 1.0, 0.6)
	var shape = $CollisionShape3D.shape as CylinderShape3D
	blob.position.y = -shape.height / 2.0 + 0.01
	add_child(blob)
	blob_base_scale = blob.scale


# Drops the shadow to the floor below Veyl, shrinking and fading it with
# height so a jump reads as going up rather than moving north
func update_blob_shadow():

	if blob == null:
		return

	var shape = $CollisionShape3D.shape as CylinderShape3D
	var feet = global_position + global_basis.y * (-shape.height / 2.0)
	var ray = PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.1, feet + Vector3.DOWN * 100.0)
	ray.exclude = [get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		blob.visible = false
		return

	blob.visible = true
	var height = max(feet.y - hit["position"].y - 0.1, 0.0)
	var t = clamp(height / SHADOW_FADE_HEIGHT, 0.0, 1.0)
	blob.global_position = Vector3(feet.x, hit["position"].y + 0.05, feet.z)
	blob.scale = blob_base_scale * lerp(1.0, 0.45, t)
	blob_mat.albedo_color.a = lerp(0.4, 0.12, t)


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


# Front / back / side art based on aim relative to the camera
func update_sprite_facing():

	if not animator:
		return

	var local = iso_basis().inverse() * aim_dir

	if abs(local.x) > abs(local.z):

		animator.face("right", local.x < 0)

	elif local.z > 0:

		animator.face("front", false)

	else:

		animator.face("back", false)


# ============================================================
# COMBAT
# ============================================================

func request_attack(kind: String):

	var move = CombatMoves.get_move(kind, not is_on_floor(), held_stats()["moves"])

	if attack_timer <= 0.0:
		perform_move(move)
	elif attack_timer <= ATTACK_BUFFER:
		buffered_move = move
	elif combo.count > 0:
		# Mashing breaks the rhythm
		combo.drop()
		emit_combo()


func scroll_attack(kind: String):

	scroll_quiet = 0.0
	if scroll_locked:
		return
	scroll_locked = true
	pan_amount = 0.0
	request_attack(kind)


func update_combat(delta):

	scroll_quiet += delta
	if scroll_quiet >= SCROLL_GAP:
		scroll_locked = false
		pan_amount = 0.0

	if not buffered_move.is_empty() and attack_timer <= 0.0 and not dead:
		perform_move(buffered_move)
		buffered_move = {}

	if combo.tick(delta):
		emit_combo()


func perform_move(move: Dictionary):

	var weapon = held_stats()
	var attack_range: float = weapon["range"] * move["range"]
	var arc: float = move["arc"]
	if Pad.using_pad and not bot and not holding_tool():
		aim_assist(attack_range)
	attack_timer = weapon["cooldown"] * move["cooldown"]
	last_swing_msec = Time.get_ticks_msec()
	Sfx.play("attack", 0.0, SWING_PITCH.get(move["name"], 1.0))

	# The blade connects a moment later, on the swing's strike frame
	pending_swings.append({"move": move, "aim": aim_dir, "time": IMPACT_DELAY.get(move["name"], 0.07)})

	# A pick or axe works where Veyl stands, so a hole dug underfoot stays underfoot
	if is_on_floor() and nearest_enemy_distance() > LUNGE_SKIP_DIST and not holding_tool():
		lunge_timer = LUNGE_TIME
		lunge_dir = aim_dir

	if animator:
		animator.swing(move["name"], aim_dir, move.get("anim", ""))
	NetSync.share_player_fx("swing", [move["name"], aim_dir, weapon["moves"], weapon["range"]], net_id())


func update_pending_swings(delta: float):

	for swing in pending_swings.duplicate():
		swing["time"] -= delta
		if swing["time"] <= 0.0:
			pending_swings.erase(swing)
			if not dead:
				resolve_swing(swing["move"], swing["aim"])


func nearest_enemy_distance() -> float:

	var best = INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset = enemy.global_position - global_position
		offset.y = 0
		best = min(best, offset.length() - enemy.radius)
	return best


# The blade connects: find what's in the arc and hit it. A pickaxe or axe
# only works rock and wood (harvest.gd); a blade or fist that meets no
# creature strikes whatever block or tree is in front instead.
func resolve_swing(move: Dictionary, aim: Vector3):

	if holding_tool():
		Harvest.strike(self, move, aim, equipped(held_slot))
		return

	var weapon = held_stats()
	var attack_range: float = weapon["range"] * move["range"]
	var arc: float = move["arc"]
	var half_arc = deg_to_rad(arc) / 2.0
	var hits = []

	# The Ember Shade only duels
	for enemy in [] if bot else get_tree().get_nodes_in_group("enemies"):

		var offset = enemy.global_position - global_position
		offset.y = 0

		if offset.length() > attack_range + enemy.radius:
			continue

		if offset.length() > 0.01 and aim.angle_to(offset.normalized()) > half_arc:
			continue

		hits.append(enemy)

	# Other players (and the Ember Shade), only while both are inside the
	# Proving Ring. The Shade goes after the real players. In a Local Duel
	# the opponent is the only target.
	var duels = []
	if opponent and not opponent.dead:
		var offset = opponent.global_position - global_position
		# Side-on, a launched opponent is out of reach of a ground swing
		var reach = offset.length() if plane_lock else Vector2(offset.x, offset.z).length()
		offset.y = 0
		if reach <= attack_range + 1.5 and (offset.length() <= 0.01 or aim.angle_to(offset.normalized()) <= half_arc):
			duels.append(opponent)
	var ring = get_tree().get_first_node_in_group("pvp_ring")
	if ring and ring.contains(global_position) and opponent == null:
		for other in get_tree().get_nodes_in_group("players" if bot else "remote_players"):
			var offset = other.global_position - global_position
			offset.y = 0
			if other.dead or not ring.contains(other.global_position):
				continue
			if offset.length() > attack_range + 1.5:
				continue
			if offset.length() > 0.01 and aim.angle_to(offset.normalized()) > half_arc:
				continue
			duels.append(other)

	if hits.is_empty() and duels.is_empty() and uses_gear():
		Harvest.strike(self, move, aim, equipped("weapon"))

	if not hits.is_empty() or not duels.is_empty():
		if uses_gear():
			GameState.wear("weapon")
		var combo_mult = combo.add_hit(GameState.max_combo)
		for enemy in hits:
			strike(enemy, move, combo_mult)
		for other in duels:
			duel_strike(other, move, combo_mult)

		# The hit that reaches Max Combo (or an aerial finisher) ends the chain
		if combo.finished(GameState.max_combo) or move["name"] == "aerial":
			if combo.count > 1:
				FloatingText.spawn(get_parent(), global_position + Vector3(0, 6, 0), "%d HIT!" % combo.count, Color(1.0, 0.85, 0.3))
			combo.drop()
			attack_timer += COMBO_END_LAG
		emit_combo()

	show_slash(move, aim, weapon["range"])


# Swing visual (spawned in world space, not under the scaled player)
func show_slash(move: Dictionary, aim: Vector3, reach: float):

	var attack_range: float = reach * move["range"]
	var arc: float = move["arc"]
	var slash = SlashEffect.new()
	slash.radius = attack_range
	slash.arc_degrees = arc
	if move["name"] == "down" or move["name"] == "aerial":
		slash.color = Color(1.0, 0.8, 0.3, 0.75)
	get_parent().add_child(slash)
	slash.global_position = Vector3(global_position.x, 0.1, global_position.z)
	slash.global_basis = Basis.looking_at(aim)
	match move["name"]:
		"down", "aerial":
			slash.style = "ring"
		"up":
			slash.style = "fan"
		_:
			# Run the sweep toward the side of the screen the move swings to
			var local_right = SpritePose.screen_x(self, slash.global_basis.x)
			slash.sweep_dir = 1.0 if local_right * move["side"] >= 0.0 else -1.0
	if plane_lock:
		# Side-on the ground is edge-on, so the swing stands up at chest
		# height, its arc in the plane the camera faces
		slash.global_position = global_position + Vector3(0, 4.5, 0)
		slash.global_basis = Basis.looking_at(aim) * Basis(Vector3.BACK, PI / 2.0)


# Health damage first, then the separate push / spin / dizzy / launch
func strike(enemy: Node3D, move: Dictionary, combo_mult: float):

	var mult = move["damage"] * combo_mult
	var crit = move["name"] == "aerial" and enemy.launched
	if crit:
		mult *= CombatMoves.AERIAL_CRIT
	if enemy.is_dizzy():
		mult *= DIZZY_BONUS

	var amount = CodexData.calc_damage(get_attack() * mult, enemy.data["defense"])
	# Judged here, so a guest's killing blow lands with no wait for the host
	var killing = enemy.health - amount <= 0.0

	var away = enemy.global_position - global_position
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else aim_dir

	var push_dir = away
	var screen_dir: Vector2 = move["screen_dir"]
	if screen_dir != Vector2.ZERO:
		# Screen direction of the attack, a little away from Veyl so the
		# target isn't shoved back into the swing
		var world = iso_basis() * Vector3(screen_dir.x, 0, screen_dir.y)
		push_dir = (world + away * 0.25).normalized()

	# Aerial hits only spike targets that are already in the air
	var launch: float = move["launch"]
	if move["name"] == "aerial" and not enemy.launched:
		launch = 0.0

	var magic = held_stats()["magic"]
	var heavy_mult = ASHWEIGHT if magic == "Ashweight" else 1.0
	var burn = BURN_TIME if magic == "Emberbrand" else 0.0
	NetSync.hit_creature(enemy, amount, global_position, push_dir * move["push"] * heavy_mult, move["spin"], move["dizzy"] * heavy_mult, launch, move["side"], burn)

	if crit:
		FloatingText.spawn(get_parent(), enemy.global_position + Vector3(0, enemy.height / 2.0 + 5.0, 0), "CRITICAL!", Color(1.0, 0.75, 0.2))

	# A killing blow: the world slows, the page flashes
	if killing:
		var boss = enemy.data.get("boss", false)
		hit_stop(1.1 if boss else 0.3, 0.2)
		shake = max(shake, 0.8 if boss else 0.45)
		InkPost.flash(get_tree(), Color(1.0, 0.94, 0.82), 0.6 if boss else 0.3)
		Sfx.play("kill", -3.0 if boss else -6.0)
		Pad.rumble(0.7, 0.9, 0.3)

	# Heavier moves land harder: longer freeze, more shake, more sparks
	var heavy = crit or move["launch"] != 0.0 or combo.finished(GameState.max_combo)
	var spark_at = enemy.global_position + Vector3(0, enemy.height * 0.2, 0)
	var spark_dir = (enemy.global_position - global_position) * Vector3(1, 0, 1) + Vector3.UP * 0.6
	if crit:
		HitSpark.spawn(get_parent(), spark_at, spark_dir, Color(1.0, 0.85, 0.4), 28)
		hit_stop(0.12)
		shake = max(shake, 0.6)
		Pad.rumble(0.6, 0.8, 0.18)
	elif heavy:
		Sfx.play("hit_heavy", -2.0)
		HitSpark.spawn(get_parent(), spark_at, spark_dir, Color(1.0, 0.6, 0.2), 20)
		hit_stop(0.08)
		shake = max(shake, 0.35)
		Pad.rumble(0.5, 0.4, 0.12)
	else:
		HitSpark.spawn(get_parent(), spark_at, spark_dir, Color(1.0, 0.5, 0.15), 12)
		hit_stop(0.045)
		shake = max(shake, 0.15)
		Pad.rumble(0.35, 0.0, 0.07)


# A duel hit in the Proving Ring: the other player's machine applies it
func duel_strike(other: Node3D, move: Dictionary, combo_mult: float):

	var amount = CodexData.calc_damage(get_attack() * move["damage"] * combo_mult * PVP_DAMAGE, other.defense)
	var away = other.global_position - global_position
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else aim_dir
	# Launches ride in the push's height (take_hit); aerial hits only
	# spike a Veyl who is already in the air
	var launch: float = move["launch"] * PVP_LAUNCH
	if launch < 0.0 and other.grounded():
		launch = 0.0
	var push = away * move["push"] * 0.6 + Vector3.UP * launch
	if other == opponent:
		other.take_hit(amount, global_position, push, 0)
	else:
		NetSync.pvp_hit(other.peer_id, amount, global_position, push, net_id())

	var spark_at = other.global_position + Vector3(0, 3.0, 0)
	HitSpark.spawn(get_parent(), spark_at, away + Vector3.UP * 0.6, Color(1.0, 0.5, 0.15), 14)
	Sfx.play("hit_heavy", -4.0)
	hit_stop(0.06)
	shake = max(shake, 0.2)
	if not bot:
		Pad.rumble(0.4, 0.2, 0.08)


# A stick can't point as precisely as a mouse, so swing at the closest
# enemy roughly where Veyl is aiming
func aim_assist(attack_range: float):

	var best: Node3D = null
	var best_dist = attack_range + 2.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset = enemy.global_position - global_position
		offset.y = 0
		var dist = offset.length() - enemy.radius
		if dist > best_dist or offset.length() < 0.01:
			continue
		if rad_to_deg(aim_dir.angle_to(offset.normalized())) > AIM_ASSIST_DEGREES:
			continue
		best = enemy
		best_dist = dist

	if best:
		var offset = best.global_position - global_position
		aim_dir = Vector3(offset.x, 0, offset.z).normalized()
		update_sprite_facing()


# Freeze the game for a moment so the hit has weight. Overlapping hits
# extend the freeze rather than stacking; the slowest requested speed wins.
# A kill uses a longer, gentler slow-motion (scale ~0.25).
func hit_stop(duration: float, scale: float = HIT_STOP_SCALE):

	if bot:
		return

	# A shared world can't slow down for one player, so in a session only
	# this Veyl's pose holds for the moment instead
	if Net.online:
		if animator:
			animator.hold(min(duration, 0.15))
		return

	var already_stopped = hit_stop_left > 0.0
	hit_stop_left = max(hit_stop_left, duration)
	hit_stop_scale = min(hit_stop_scale, scale) if already_stopped else scale
	Engine.time_scale = hit_stop_scale
	if already_stopped:
		return

	while hit_stop_left > 0.0:
		var before = Time.get_ticks_usec()
		await get_tree().process_frame
		hit_stop_left -= (Time.get_ticks_usec() - before) / 1000000.0
		Engine.time_scale = hit_stop_scale
	hit_stop_left = 0.0
	hit_stop_scale = 1.0
	Engine.time_scale = 1.0


# Never leave the game frozen if Veyl is removed mid hit-stop
func _exit_tree():

	Engine.time_scale = 1.0


func emit_combo():

	combo_changed.emit(combo.count, GameState.max_combo, 1.0 + ComboTracker.STEP_BONUS * max(combo.count - 1, 0))


func get_attack() -> float:

	return base_attack + held_stats()["attack"]


# ============================================================
# GEAR (tool bar, wear, armour, magic)
# ============================================================

# The Ember Shade and Local Duel fighters don't carry the player's gear
func uses_gear() -> bool:
	return not bot and input_prefix == ""


func equipped(slot: String) -> Dictionary:
	return GameState.equipped_gear(slot) if uses_gear() else {}


func holding_tool() -> bool:
	return held_slot != "weapon"


# Reach, pace and move set of what's in hand. The Ember Shade and Local
# Duel fighters always have a Rustblade of their own.
func held_stats() -> Dictionary:

	if not uses_gear():
		return Items.weapon_stats(Items.rustblade())
	if holding_tool():
		return TOOL_SWING
	return GameState.weapon()


# Switch the tool bar slot (an empty pickaxe or axe slot can't be held)
func hold(slot: String):

	if slot != "weapon" and equipped(slot).is_empty():
		GameState.notify.emit("No %s. Craft one first." % slot)
		return
	held_slot = slot
	refresh_gear()


# Gear changed: what's in hand, armour, and the HUD
func refresh_gear():

	if holding_tool() and equipped(held_slot).is_empty():
		held_slot = "weapon"
	var gear = equipped(held_slot)
	held_code = Items.held_code(gear["type"], gear["material"]) if not gear.is_empty() else 0
	show_held(held_code)
	var armor = equipped("armor")
	defense = base_defense + (Items.armor_defense(armor) if not armor.is_empty() else 0.0)
	held_changed.emit()


func show_held(code: int):

	if animator == null:
		return
	var held = Items.held_from_code(code)
	animator.puppet.set_held(held[0], held[1])


func has_magic(magic: String) -> bool:

	for slot in ["weapon", "armor"]:
		if equipped(slot).get("magic", "") == magic:
			return true
	return false


# Mosswoven gear slowly closes wounds
func mend(delta: float):

	if dead or health >= max_health or not has_magic("Mosswoven"):
		return
	health = min(health + MEND_RATE * delta, max_health)
	health_changed.emit(health, max_health)


func try_dash():

	if dash_cooldown_timer > 0.0:
		return

	var horizontal = Vector3(velocity.x, 0, velocity.z)
	dash_dir = horizontal.normalized() if horizontal.length() > 0.1 else aim_dir

	dash_timer = dash_time
	dash_cooldown_timer = dash_cooldown * (0.7 if equipped("armor").get("magic", "") == "Fangswift" else 1.0)
	Sfx.play("dash", -4.0)
	invuln_timer = dash_time + 0.05
	NetSync.share_player_fx("dash", [], net_id())


func take_damage(amount: int, from: Vector3):

	# Someone else's Veyl: their machine decides (a dodge there still counts)
	if remote:
		NetSync.hurt_player(peer_id, amount, from)
		return

	if dead or invuln_timer > 0.0:
		return

	health = max(health - amount, 0.0)
	invuln_timer = 0.3
	if not bot:
		Pad.rumble(0.4, 0.7, 0.2)
	if uses_gear():
		GameState.wear("armor")
	if combo.count > 0:
		combo.drop()
		emit_combo()
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

	if animator:
		animator.hurt(from)

	flinch()
	NetSync.share_player_fx("hurt", [amount, from], net_id())

	if health <= 0.0:
		die()


func flinch():

	if sprite:
		sprite.modulate = Color(1.0, 0.3, 0.3)
		create_tween().tween_property(sprite, "modulate", base_tint, 0.25)


# A hit sent over the network (net_sync.gd): a creature on the host's
# machine, or another player in the Proving Ring
func take_hit(amount: int, from: Vector3, push: Vector3, attacker: int):

	var before = health
	if attacker != 0:
		last_attacker = attacker
	take_damage(amount, from)
	if health < before:
		velocity.x += push.x
		velocity.z += push.z
		# Height is a launch (up) or a spike (down), not added to a jump
		if push.y > 0.0:
			velocity.y = max(velocity.y, push.y)
		elif push.y < 0.0:
			velocity.y = min(velocity.y, push.y)


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
	fade_out()
	NetSync.share_player_fx("die", [], net_id())

	var ring = get_tree().get_first_node_in_group("pvp_ring")
	died_in_ring = ring != null and ring.contains(global_position)
	if died_in_ring and last_attacker != 0:
		NetSync.announce("%s bested %s in the Proving Ring." % [Net.name_of(last_attacker), Net.name_of(net_id())])
	last_attacker = 0

	died.emit()


func fade_out():

	if sprite:
		create_tween().tween_property(sprite, "modulate", Color(0.3, 0.3, 0.3, 0.6), 0.6)


# Back to the last ember shrine (or the edge of the Proving Ring after a
# duel). Quest, inventory and kills are kept, and the creatures carry on
# where they were: they lose interest and wander home on their own.
func respawn():

	var ring = get_tree().get_first_node_in_group("pvp_ring")
	if died_in_ring and ring:
		global_position = ring.spawn_point()
	else:
		global_position = GameState.checkpoint_position if GameState.checkpoint_position != null else start_position
	died_in_ring = false
	velocity = Vector3.ZERO
	health = max_health
	dead = false
	invuln_timer = 1.0

	if sprite:
		sprite.modulate = base_tint

	health_changed.emit(health, max_health)
	respawned.emit()
	NetSync.share_player_fx("respawn", [], net_id())


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


# ============================================================
# NETWORK (this machine's Veyl -> everyone else's copy of it)
# ============================================================

# How far Veyl's feet are below vair centre
func foot_height() -> float:
	return ($CollisionShape3D.shape as CylinderShape3D).height / 2.0 * scale.y


# Walking into a bank of a mining site too steep to walk up, with room
# above it: hop up onto it, the way Terraria steps you up a ledge
func climb(direction: Vector3):

	for k in get_slide_collision_count():
		var hit = get_slide_collision(k)
		var collider = hit.get_collider()
		var normal = hit.get_normal()
		# Walkable ground or an overhang: nothing to climb
		if collider == null or not collider.is_in_group("dig_sites") or normal.y > cos(deg_to_rad(SLOPE_LIMIT)) or normal.y < -0.3:
			continue
		if Vector3(normal.x, 0, normal.z).normalized().dot(direction.normalized()) > -0.3:
			continue
		var up = Vector3.UP * 4.4
		if not test_move(global_transform, up) and not test_move(global_transform.translated(up), direction.normalized() * 1.2):
			velocity.y = CLIMB_SPEED
		return


# Who this Veyl is in the session
func net_id() -> int:
	return NetSync.BOT_ID if bot else Net.my_id()


func grounded() -> bool:
	return remote_on_floor if remote else is_on_floor()


func net_state() -> PackedFloat32Array:

	var flags = (1 if dead else 0) | (2 if is_on_floor() else 0) | (4 if dash_timer > 0.0 else 0)
	return PackedFloat32Array([
		global_position.x, global_position.y, global_position.z,
		velocity.x, velocity.y, velocity.z,
		aim_dir.x, aim_dir.z, flags, health,
		dash_dir.x, dash_dir.z, held_code, defense,
	])


func apply_net_state(s: PackedFloat32Array):

	if s.size() < 14:
		return
	net_pos = Vector3(s[0], s[1], s[2])
	net_vel = Vector3(s[3], s[4], s[5])
	net_age = 0.0
	var aim = Vector3(s[6], 0, s[7])
	if aim.length() > 0.1:
		aim_dir = aim.normalized()
	var flags = int(s[8])
	dead = flags & 1 != 0
	remote_on_floor = flags & 2 != 0
	dash_timer = 0.1 if flags & 4 != 0 else 0.0
	health = s[9]
	dash_dir = Vector3(s[10], 0, s[11])
	defense = s[13]
	if int(s[12]) != held_code:
		held_code = int(s[12])
		show_held(held_code)


# Glide toward where its player has it, a little ahead along its velocity
func remote_process(delta):

	net_age += delta
	var target = net_pos + net_vel * min(net_age, 0.12)
	if global_position.distance_to(target) > NET_SNAP_DIST:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-18.0 * delta))
	velocity = net_vel
	update_sprite_facing()
	update_blob_shadow()


func add_name_label():

	var label = Label3D.new()
	label.text = Net.name_of(peer_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	# Veyl is scaled up 5x, so the label is drawn 5x smaller to match
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = Color(1.0, 0.8, 0.55)
	label.position.y = 1.55
	add_child(label)


# ---- Moments another player's Veyl shows here ----

func fx_swing(kind: String, aim: Vector3, moveset: String, reach: float):

	if NetSync.near_me(global_position):
		Sfx.play("attack", -4.0, SWING_PITCH.get(kind, 1.0))
	last_swing_msec = Time.get_ticks_msec()
	var move = CombatMoves.get_move(kind, kind == "aerial", moveset)
	if animator:
		animator.swing(kind, aim, move.get("anim", ""))
	get_tree().create_timer(IMPACT_DELAY.get(kind, 0.07)).timeout.connect(show_slash.bind(move, aim, reach))


func fx_dash():

	if NetSync.near_me(global_position):
		Sfx.play("dash", -8.0)


func fx_hurt(amount: int, from: Vector3):

	FloatingText.spawn(get_parent(), global_position + Vector3(0, 5, 0), str(amount), Color(1.0, 0.3, 0.3))
	if animator:
		animator.hurt(from)
	flinch()


func fx_die():
	fade_out()


func fx_respawn():

	if sprite:
		sprite.modulate = base_tint
