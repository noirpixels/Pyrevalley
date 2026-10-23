extends Node2D

# A gob of burning ash, lobbed in an arc. It bursts on the ground, on a
# wall, or on Veyl. A swing can knock it out of the air.

const GRAVITY = 1400.0
const FLIGHT_TIME = 0.75
const RADIUS = 12.0

var velocity: Vector2
var damage: float
var life: float = 3.0
# A guest's copy of the host's gob: drawn, never hurts
var visual_only: bool = false


func launch(from: Vector2, to: Vector2, dmg: float):

	position = from
	damage = dmg
	# Arc that arrives in about FLIGHT_TIME
	var t = FLIGHT_TIME
	velocity = Vector2((to.x - from.x) / t, (to.y - from.y - 0.5 * GRAVITY * t * t) / t)
	z_index = 10
	add_to_group("projectiles")


func _physics_process(delta):

	life -= delta
	velocity.y += GRAVITY * delta
	position += velocity * delta
	var game = get_tree().get_first_node_in_group("game")
	if life <= 0.0 or (game and game.ground_material(global_position) >= 0):
		burst()
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or visual_only:
			continue
		var body = Rect2(p.global_position - Vector2(16, 92), Vector2(32, 92))
		if body.grow(RADIUS).has_point(global_position):
			NetSync.hurt_player(p, damage, global_position)
			burst()
			return
	queue_redraw()


# Veyl's swing batted it away
func deflect():
	burst()


func burst():

	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.burst(global_position, Color(1.0, 0.45, 0.1), 14, 260.0)
	queue_free()


func _draw():

	draw_circle(Vector2.ZERO, RADIUS + 5.0, Color(1.0, 0.35, 0.05, 0.35))
	draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.55, 0.15))
	draw_circle(Vector2(-3, -3), RADIUS * 0.45, Color(1.0, 0.9, 0.6))
