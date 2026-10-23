extends Node2D

# Veyl's look in motion, side-on: the cut-out puppet (veyl_puppet.gd) poses
# the limbs and sword; this leans, squashes and lifts the whole figure,
# leaves afterimages on a dash, and topples it on death. It only ever moves
# the picture, never the body, so it can't change how the game plays.

const VeylPuppet = preload("res://veyl_puppet.gd")

# On-screen size of the puppet's 216 px figure
const SCALE = 0.45
const STEP_RATE = 0.022
const GHOST_GAP = 0.035

var player: CharacterBody2D
var puppet: VeylPuppet
var sprite: Sprite2D

var time: float = 0.0
var step_phase: float = 0.0
var was_on_floor: bool = true
var ghost_timer: float = 0.0
var hold_left: float = 0.0

var lean: float = 0.0
var squash: Vector2 = Vector2.ONE
var lift: float = 0.0
var kick_time: float = 0.0
var kick_timer: float = 0.0
var kick_lean: float = 0.0
var kick_squash: Vector2 = Vector2.ONE
var kick_shift: float = 0.0
var shift: float = 0.0


func _init(body: CharacterBody2D, tint: Color = Color.WHITE):

	player = body
	puppet = VeylPuppet.new({
		"front": load("res://Veyl/veylclothed__F.png"),
		"back": load("res://Veyl/veylclothed__B.png"),
		"right": load("res://Veyl/veylclothed__R.png"),
	})
	add_child(puppet)
	puppet.set_facing("right")

	sprite = Sprite2D.new()
	sprite.texture = puppet.texture
	sprite.centered = false
	sprite.offset = Vector2(-VeylPuppet.SIZE.x / 2.0, -VeylPuppet.SIZE.y)
	sprite.modulate = tint
	add_child(sprite)
	scale = Vector2(SCALE, SCALE)


func _process(delta):

	if hold_left > 0.0:
		hold_left -= delta
		return

	time += delta
	ghost_timer = max(ghost_timer - delta, 0.0)
	var on_floor = player.grounded()
	var speed = abs(player.velocity.x)
	var facing = player.facing

	var target_lean = 0.0
	var target_squash = Vector2.ONE
	var rate = 18.0

	if player.dead:
		target_lean = -facing * 1.45
		rate = 7.0
	elif player.dash_timer > 0.0:
		target_lean = facing * 0.3
		target_squash = Vector2(1.15, 0.88)
		if ghost_timer <= 0.0:
			ghost_timer = GHOST_GAP
			spawn_ghost()
	elif not on_floor:
		target_squash = Vector2(0.9, 1.12) if player.velocity.y < 0.0 else Vector2(0.96, 1.05)
		target_lean = facing * clamp(player.velocity.x / 380.0, -1.0, 1.0) * 0.08
	elif speed > 30.0:
		step_phase += delta * speed * STEP_RATE
		target_lean = facing * 0.06
	else:
		step_phase = 0.0

	puppet.animate(delta, step_phase, on_floor and speed > 30.0 and not player.dead, not on_floor, time)

	if on_floor and not was_on_floor and not player.dead:
		squash = Vector2(1.25, 0.78)
	was_on_floor = on_floor

	var target_shift = 0.0
	if kick_timer > 0.0:
		kick_timer = max(kick_timer - delta, 0.0)
		var k = pow(kick_timer / kick_time, 2.0)
		target_lean += kick_lean * k
		target_squash *= Vector2.ONE.lerp(kick_squash, k)
		target_shift = kick_shift * k

	var blend = 1.0 - exp(-rate * delta)
	lean = lerp(lean, target_lean, blend)
	squash = squash.lerp(target_squash, blend)
	shift = lerp(shift, target_shift, blend)

	sprite.flip_h = facing < 0
	rotation = lean
	scale = Vector2(SCALE * squash.x, SCALE * squash.y)
	position = Vector2(shift * facing, 0)


func hold(duration: float):
	hold_left = max(hold_left, duration)


# anim: the puppet's swing (side, up, down, aerial, thrust, jab)
func swing(anim: String):

	match anim:
		"up":
			kick(0.25, 0.0, Vector2(0.96, 1.06), 6.0)
		"down", "aerial":
			kick(0.28, 0.12, Vector2(1.06, 0.94), 6.0)
		_:
			kick(0.2, 0.1, Vector2.ONE, 10.0)
	# The puppet works unflipped, so a flipped sprite swings the other way
	puppet.swing(anim, 1.0)


func hurt():
	kick(0.25, -0.35, Vector2(0.9, 1.08), -12.0)


func set_held(type: String, material: String):
	puppet.set_held(type, material)


func kick(duration: float, k_lean: float, k_squash: Vector2, k_shift: float):

	kick_time = duration
	kick_timer = duration
	kick_lean = k_lean * player.facing
	kick_squash = k_squash
	kick_shift = k_shift
	lean += kick_lean * 0.5


func spawn_ghost():

	var ghost = Sprite2D.new()
	ghost.texture = ImageTexture.create_from_image(sprite.texture.get_image())
	ghost.centered = false
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.modulate = Color(1.0, 0.55, 0.25, 0.45)
	ghost.z_index = -1
	player.get_parent().add_child(ghost)
	ghost.global_transform = sprite.global_transform
	var tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tween.tween_callback(ghost.queue_free)
