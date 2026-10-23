extends Node

# Veyl's procedural animation: breathing, walking, jumping, dashing, sword
# swings, flinching and falling over. It only moves the sprite, never the
# body, so it can't change how the game plays. The limbs and sword are a
# cut-out puppet (veyl_puppet.gd); this script moves the sprite as a whole.

const SpritePose = preload("res://sprite_pose.gd")
const VeylPuppet = preload("res://veyl_puppet.gd")

# Radians of step cycle per metre walked (two steps per half turn)
const STEP_RATE = 1.0
# Seconds between dash afterimages
const GHOST_GAP = 0.04

var player: CharacterBody3D
var sprite: Sprite3D
var puppet: VeylPuppet
var base_scale: float
var feet: Vector3

var time: float = 0.0
var step_phase: float = 0.0
var was_on_floor: bool = true
var ghost_timer: float = 0.0
# Seconds the pose is held still: hit-stop in a multiplayer session, where
# the game can't slow down for one player (player_3d.gd hit_stop)
var hold_left: float = 0.0
var fall_side: float = 1.0

# Current pose (lift and shift are world units: up, and right on screen)
var lean: float = 0.0
var squash: Vector2 = Vector2.ONE
var lift: float = 0.0
var shift: float = 0.0

# One-shot pose (swing, flinch) that fades out over kick_time
var kick_time: float = 0.0
var kick_timer: float = 0.0
var kick_lean: float = 0.0
var kick_squash: Vector2 = Vector2.ONE
var kick_lift: float = 0.0
var kick_shift: float = 0.0


func _init(body: CharacterBody3D, body_sprite: Sprite3D):

	player = body
	sprite = body_sprite
	base_scale = sprite.scale.x
	feet = sprite.position - Vector3(0, sprite.texture.get_height() / 2.0 * sprite.pixel_size * base_scale, 0)

	# The sprite shows the puppet from here on
	puppet = VeylPuppet.new({
		"front": player.texture_front,
		"back": player.texture_back,
		"right": player.texture_right,
	})
	add_child(puppet)
	sprite.texture = puppet.texture
	SpritePose.pin_to_feet(sprite)


func _process(delta):

	if hold_left > 0.0:
		hold_left -= delta
		return

	time += delta
	ghost_timer = max(ghost_timer - delta, 0.0)

	var flat_vel = Vector3(player.velocity.x, 0, player.velocity.z)
	var speed = flat_vel.length()
	var moving_x = SpritePose.screen_x(sprite, flat_vel) / player.speed
	var on_floor = player.grounded()

	var target_lean = 0.0
	var target_squash = Vector2.ONE
	var target_lift = 0.0
	var rate = 18.0

	if player.dead:
		# Topple over
		target_lean = fall_side * 1.45
		rate = 7.0

	elif player.dash_timer > 0.0:
		target_lean = -SpritePose.screen_x(sprite, player.dash_dir) * 0.35
		target_squash = Vector2(1.15, 0.88)
		if ghost_timer <= 0.0:
			ghost_timer = GHOST_GAP
			spawn_ghost()

	elif not on_floor:
		# Stretch on the way up, ease off on the way down
		target_squash = Vector2(0.88, 1.14) if player.velocity.y > 0.0 else Vector2(0.95, 1.06)
		target_lean = -moving_x * 0.1

	elif speed > 0.5:
		# The puppet's legs do the stepping; the sprite just leans in
		step_phase += delta * speed * STEP_RATE
		target_lean = -moving_x * 0.06

	else:
		step_phase = 0.0

	puppet.animate(delta, step_phase, on_floor and speed > 0.5 and not player.dead, not on_floor, time)

	# Thump on landing
	if on_floor and not was_on_floor and not player.dead:
		squash = Vector2(1.25, 0.75)
	was_on_floor = on_floor

	var target_shift = 0.0
	if kick_timer > 0.0:
		kick_timer = max(kick_timer - delta, 0.0)
		var k = pow(kick_timer / kick_time, 2.0)
		target_lean += kick_lean * k
		target_squash *= Vector2.ONE.lerp(kick_squash, k)
		target_lift += kick_lift * k
		target_shift = kick_shift * k

	var blend = 1.0 - exp(-rate * delta)
	lean = lerp(lean, target_lean, blend)
	squash = squash.lerp(target_squash, blend)
	lift = lerp(lift, target_lift, blend)
	shift = lerp(shift, target_shift, blend)

	SpritePose.apply(sprite, lean, squash, base_scale)
	var offset_world = Vector3.UP * lift + screen_right() * shift
	sprite.position = feet + player.global_basis.inverse() * offset_world


func hold(duration: float):
	hold_left = max(hold_left, duration)


# Called by the player as each move swings. The puppet swings the sword;
# the sprite only lunges a little toward the cut.
# anim: the arm's swing when the move set has its own (thrust, jab)
func swing(kind: String, aim: Vector3, anim: String = ""):

	var aim_x = SpritePose.screen_x(sprite, aim)
	var toward = sign_or_one(aim_x)

	match kind:
		"left":
			toward = -1.0
			kick(0.2, 0.06, Vector2.ONE, 0.0, -0.2)
		"right":
			toward = 1.0
			kick(0.2, -0.06, Vector2.ONE, 0.0, 0.2)
		"up":
			kick(0.25, 0.0, Vector2(0.96, 1.05), 0.25, toward * 0.15)
		"down":
			kick(0.25, 0.0, Vector2(1.06, 0.94), 0.0, toward * 0.15)
		"aerial":
			kick(0.3, 0.0, Vector2(1.06, 0.94), 0.0, toward * 0.15)

	# The puppet works unflipped, so a flipped sprite swings the other way
	var dir = -toward if sprite.flip_h else toward
	if anim == "":
		anim = "side" if kind == "left" or kind == "right" else kind
	puppet.swing(anim, dir)


# Which art Veyl shows ("front", "back" or "right"); flip mirrors it to face left
func face(which: String, flip: bool):

	puppet.set_facing(which)
	sprite.flip_h = flip


# Snap away from whatever hit Veyl
func hurt(from: Vector3):

	var away = Vector3(player.global_position.x - from.x, 0, player.global_position.z - from.z)
	var away_x = SpritePose.screen_x(sprite, away.normalized())
	fall_side = -sign_or_one(away_x)
	kick(0.25, -away_x * 0.35, Vector2(0.9, 1.08), 0.0, away_x * 0.3)


func kick(duration: float, k_lean: float, k_squash: Vector2, k_lift: float, k_shift: float):

	kick_time = duration
	kick_timer = duration
	kick_lean = k_lean
	kick_squash = k_squash
	kick_lift = k_lift
	kick_shift = k_shift
	# Jump straight into the pose instead of easing toward it
	lean += k_lean * 0.5


# Fading copy left behind while dashing
func spawn_ghost():

	var ghost = Sprite3D.new()
	# A still copy; the puppet's own texture keeps moving
	ghost.texture = ImageTexture.create_from_image(sprite.texture.get_image())
	ghost.flip_h = sprite.flip_h
	ghost.pixel_size = sprite.pixel_size
	ghost.offset = sprite.offset
	ghost.texture_filter = sprite.texture_filter
	ghost.shaded = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.modulate = Color(1.0, 0.55, 0.25, 0.45)
	player.get_parent().add_child(ghost)
	ghost.global_transform = sprite.global_transform

	var tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tween.tween_callback(ghost.queue_free)


func screen_right() -> Vector3:

	var cam = sprite.get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.RIGHT
	var right = cam.global_basis.x
	right.y = 0.0
	return right.normalized()


func sign_or_one(x: float) -> float:
	return -1.0 if x < 0.0 else 1.0
