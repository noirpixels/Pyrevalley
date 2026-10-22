extends Node2D

# A wave of burning ash racing along the floor from the Ashbound's slam.
# Low enough to jump; it dies at the arena wall.

const SPEED = 720.0
const HEIGHT = 70.0
const LENGTH = 70.0

var dir: float
var damage: float
var bounds: Rect2
var hit = []
var time: float = 0.0


func _init(direction: float, dmg: float, arena: Rect2):

	dir = direction
	damage = dmg
	bounds = arena
	z_index = 11


func _physics_process(delta):

	time += delta
	position.x += dir * SPEED * delta
	if global_position.x < bounds.position.x + 40.0 or global_position.x > bounds.end.x - 40.0:
		queue_free()
		return
	var r = Rect2(global_position + Vector2(-LENGTH / 2.0, -HEIGHT), Vector2(LENGTH, HEIGHT))
	for p in get_tree().get_nodes_in_group("players"):
		if p in hit or p.dead:
			continue
		var body = Rect2(p.global_position - Vector2(16, 92), Vector2(32, 92))
		if r.intersects(body):
			hit.append(p)
			NetSync.hurt_player(p, damage, global_position - Vector2(dir * 40.0, 0))
	queue_redraw()


func _draw():

	var flick = sin(time * 30.0) * 6.0
	var pts = PackedVector2Array([
		Vector2(-LENGTH / 2.0 * dir, 0), Vector2(LENGTH / 2.0 * dir, 0),
		Vector2(LENGTH * 0.2 * dir, -HEIGHT + flick), Vector2(-LENGTH * 0.1 * dir, -HEIGHT * 0.6)])
	draw_colored_polygon(pts, Color(1.0, 0.45, 0.1, 0.85))
	var inner = PackedVector2Array([
		Vector2(-LENGTH * 0.2 * dir, 0), Vector2(LENGTH * 0.4 * dir, 0), Vector2(LENGTH * 0.15 * dir, -HEIGHT * 0.6 + flick)])
	draw_colored_polygon(inner, Color(1.0, 0.85, 0.5, 0.9))
