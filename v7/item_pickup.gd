extends Node2D

# Something on the ground to pick up: a loose branch, a flint, ore knocked
# out of the earth, or what a creature dropped. It pops out, falls onto the
# ground, and drifts to Veyl once vae is close.

const Items = preload("res://items.gd")
const GRAVITY = 1600.0
const MAGNET_RANGE = 90.0
const COLLECT_RANGE = 34.0

var item: String
var amount: int
var velocity: Vector2 = Vector2.ZERO
# Lying where it grew (forage): doesn't fall
var resting: bool = false
# Recorded once collected, so loose forage stays gone until Veyl rests
var taken_id: String = ""
var time: float = 0.0


func _init(item_name: String, count: int):

	item = item_name
	amount = count
	z_index = 8
	time = randf() * TAU


func _physics_process(delta):

	time += delta
	var player = nearest_player()
	if player:
		var to = player.global_position + Vector2(0, -40) - global_position
		if to.length() < COLLECT_RANGE:
			collect()
			return
		if to.length() < MAGNET_RANGE:
			global_position += to.normalized() * 420.0 * delta
			queue_redraw()
			return
	if not resting:
		velocity.y += GRAVITY * delta
		var next = global_position + velocity * delta
		var game = get_tree().get_first_node_in_group("game")
		if game and (game.ground_material(next + Vector2(0, 8)) >= 0 or on_ledge(next)) and velocity.y > 0.0:
			resting = true
			velocity = Vector2.ZERO
		else:
			if game and game.ground_material(next) >= 0:
				velocity.x = -velocity.x * 0.3
				next.x = global_position.x
			global_position = next
	queue_redraw()


func on_ledge(at: Vector2) -> bool:

	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(at, at + Vector2(0, 10), 2)
	return not space.intersect_ray(query).is_empty()


func nearest_player() -> Node2D:

	var best = null
	var best_d = MAGNET_RANGE
	for p in get_tree().get_nodes_in_group("player"):
		var d = (p.global_position + Vector2(0, -40)).distance_to(global_position)
		if d < best_d and not p.dead:
			best_d = d
			best = p
	return best


func collect():

	GameState.add_item(item, amount)
	if taken_id != "":
		GameState.taken[taken_id] = true
	Sfx.play("pickup", -6.0)
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.number(global_position + Vector2(0, -20), "+%d %s" % [amount, item], Items.COLORS.get(item, Color.WHITE), 22)
	queue_free()


func _draw():

	var bob = Vector2(0, sin(time * 3.0) * 3.0) if resting else Vector2.ZERO
	var c: Color = Items.COLORS.get(item, Color(0.9, 0.8, 0.6))
	InkDraw.glow(self, bob, 26.0, Color(1.0, 0.75, 0.4, 0.18 + 0.06 * sin(time * 3.0)))
	if item == "Branch":
		InkDraw.line(self, bob + Vector2(-15, 6), bob + Vector2(15, -6), 8.0, InkDraw.INK, 1.0)
		InkDraw.line(self, bob + Vector2(-13, 5), bob + Vector2(13, -5), 4.5, c, 1.0)
		InkDraw.line(self, bob + Vector2(1, 0), bob + Vector2(8, -11), 4.0, InkDraw.INK, 2.0)
	else:
		var pts = PackedVector2Array([bob + Vector2(0, -11), bob + Vector2(10, -2), bob + Vector2(5, 10), bob + Vector2(-6, 9), bob + Vector2(-10, -3)])
		InkDraw.fill(self, pts, c)
		InkDraw.outline(self, pts, 2.6, InkDraw.INK, 3.0)
		InkDraw.line(self, bob + Vector2(-4, -5), bob + Vector2(2, -3), 2.0, Color(1, 1, 1, 0.6), 4.0)
