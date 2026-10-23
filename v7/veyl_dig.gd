extends Node

# Digging: F swings the pickaxe toward the mouse (or the stick, or where
# Veyl is looking with W/S), cutting a round bite out of the ground. A
# stone pickaxe cuts earth; bronze cuts rock too. Ore in the earth drops
# out once it's dug around. Held F keeps swinging.

const DIG_REACH = 72.0
const DIG_RADIUS = {1: 34.0, 2: 42.0}
const DIG_COOLDOWN = 0.3
const CHEST = Vector2(0, -52)

var player: CharacterBody2D
var cooldown: float = 0.0
var warned_hard: bool = false


func _ready():
	player = get_parent()


func _physics_process(delta):

	cooldown = max(cooldown - delta, 0.0)
	if player.remote or player.dead or player.input_blocked:
		return
	if Input.is_action_pressed("dig") and cooldown <= 0.0:
		swing()


func aim() -> Vector2:

	if not Pad.using_pad:
		var to = player.get_global_mouse_position() - (player.global_position + CHEST)
		if to.length() > 8.0:
			return to.normalized()
	var stick = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if stick.length() > 0.3:
		return stick.normalized()
	return Vector2(player.facing, 0)


func swing():

	cooldown = DIG_COOLDOWN
	var tier = GameState.pickaxe_tier()
	if tier == 0:
		if Input.is_action_just_pressed("dig"):
			GameState.notify.emit("You need a pickaxe: 2 Branch and 3 Flint. Open your pack with I.")
		return
	var dir = aim()
	if abs(dir.x) > 0.2:
		player.facing = sign(dir.x)
	var pick = GameState.gear["pickaxe"]
	player.animator.set_held("Pickaxe", pick["material"])
	player.animator.swing("down" if dir.y > 0.5 else ("up" if dir.y < -0.5 else "side"))
	get_tree().create_timer(0.3).timeout.connect(player.refresh_held)

	var at = player.global_position + CHEST + dir * DIG_REACH
	dig_at(at, DIG_RADIUS.get(tier, 34.0), tier, true)


func dig_at(at: Vector2, radius: float, tier: int, local_player: bool):

	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var room = game.room_at(at)
	if room == null:
		return
	var local = at - room.position
	var mat = room.terrain.material_at(local)
	var result = room.terrain.dig(local, radius, tier)
	var fx = get_tree().get_first_node_in_group("fx")
	if result > 0:
		GameState.log_dig(room.cell, local, radius, tier)
		if NetSync.has_method("share_dig"):
			NetSync.share_dig(room.data["index"], local, radius, tier)
		Sfx.play("hit", -6.0, 0.7)
		if fx:
			fx.debris(at, Color(0.45, 0.3, 0.18) if mat == 1 else Color(0.55, 0.55, 0.6), 10)
		game.shake(0.08)
	elif result < 0:
		Sfx.play("hit_heavy", -8.0, 1.6)
		if fx:
			fx.sparks(at, -aim(), Color(1.0, 0.9, 0.6), 8)
		if local_player and not warned_hard:
			warned_hard = true
			var why = "Bedrock. Nothing breaks it." if mat == 0 else "Too hard. A bronze pickaxe would break this rock."
			GameState.notify.emit(why)
