extends "res://enemy.gd"

# A low, armoured crawler that keeps its distance and spits gobs of burning
# ash in an arc. Close in on it, or knock the gob aside with timing.

const EmberGlob = preload("res://ember_glob.gd")
const KEEP_AWAY = 240.0


func _init():

	kind_name = "Ashcrawler"
	max_health = 46.0
	defense = 5.0
	attack = 11.0
	speed = 90.0
	weight = 1.4
	width = 110.0
	height = 52.0
	detect_range = 700.0
	windup_time = 0.6
	strike_time = 0.15
	recover_time = 0.9
	attack_cooldown = 1.6
	dizzy_threshold = 65.0
	sprite_path = "res://Creatures/ashcrawler.png"
	sprite_scale = 0.68
	drops = [["Ash Core", 0.45], ["Flint", 0.4]]


func chase_movement(dx: float) -> float:

	# Backs off if Veyl is too close, creeps in if too far
	if abs(dx) < KEEP_AWAY:
		return -sign(dx) * speed
	if abs(dx) > KEEP_AWAY * 2.0:
		return sign(dx) * speed
	return 0.0


func wants_to_attack(dx: float, _dy: float) -> bool:
	return abs(dx) < 650.0


func begin_strike():

	if target == null:
		return
	var glob = EmberGlob.new()
	var from = global_position + Vector2(facing * width * 0.45, -height * 0.7)
	glob.launch(from, target.global_position + Vector2(0, -40), attack)
	get_parent().add_child(glob)
	NetSync.creature_fx("glob", [from, target.global_position + Vector2(0, -40)])
	Sfx.play("spit", -4.0)
	squash = Vector2(1.2, 0.8)
