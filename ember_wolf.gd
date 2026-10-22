extends "res://enemy.gd"

# A lean wolf with embers under its hide. It runs Veyl down, crouches with
# its eyes flaring, then lunges straight along the ground. Jump it, or dash
# through it.

const LUNGE_SPEED = 900.0
const PROWL_SPEED = 90.0


func _init():

	kind_name = "Ember Wolf"
	max_health = 58.0
	defense = 3.0
	attack = 13.0
	speed = 270.0
	weight = 1.2
	width = 110.0
	height = 84.0
	detect_range = 640.0
	windup_time = 0.45
	strike_time = 0.3
	recover_time = 0.7
	attack_cooldown = 1.0
	dizzy_threshold = 70.0
	sprite_path = "res://Creatures/ember_wolf.png"
	sprite_scale = 0.78
	drops = [["Ember Fang", 0.6]]


func idle_movement() -> float:
	return sin(time * 0.7) * PROWL_SPEED * (1.0 if abs(global_position.x - home.x) < 200.0 else -sign(global_position.x - home.x))


func chase_movement(dx: float) -> float:
	return sign(dx) * speed if abs(dx) > 160.0 else 0.0


func wants_to_attack(dx: float, dy: float) -> bool:
	return abs(dx) < 330.0 and abs(dy) < 100.0


func strike_movement(_delta: float) -> float:
	return facing * LUNGE_SPEED


func strike_rect() -> Rect2:
	return hurt_rect().grow(4.0)
