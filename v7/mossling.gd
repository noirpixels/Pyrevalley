extends "res://enemy.gd"

# A soft, hopping knot of moss. It bounces toward Veyl in little hops,
# and when close it crouches, then pounces.

const HOP_SPEED = 520.0
const POUNCE_SPEED = 430.0
const POUNCE_JUMP = 640.0

var hop_timer: float = 0.0


func _init():

	kind_name = "Mossling"
	max_health = 34.0
	defense = 1.0
	attack = 9.0
	speed = 150.0
	weight = 0.8
	width = 56.0
	height = 50.0
	windup_time = 0.5
	strike_time = 0.55
	recover_time = 0.5
	attack_cooldown = 0.9
	dizzy_threshold = 50.0
	sprite_path = "res://Creatures/mossling.png"
	sprite_scale = 0.72
	drops = [["Moss Fiber", 0.7], ["Branch", 0.25]]


func chase_movement(dx: float) -> float:

	# Moves only while hopping
	if is_on_floor():
		hop_timer -= get_physics_process_delta_time()
		if hop_timer <= 0.0:
			hop_timer = randf_range(0.35, 0.6)
			velocity.y = -HOP_SPEED * randf_range(0.6, 0.85)
			squash = Vector2(1.2, 0.8)
		return 0.0
	return sign(dx) * speed


func wants_to_attack(dx: float, dy: float) -> bool:
	return abs(dx) < 200.0 and abs(dy) < 120.0 and is_on_floor()


func begin_strike():

	velocity.y = -POUNCE_JUMP
	squash = Vector2(0.75, 1.25)


func strike_movement(_delta: float) -> float:
	return facing * POUNCE_SPEED


func strike_rect() -> Rect2:
	return hurt_rect().grow(6.0)
