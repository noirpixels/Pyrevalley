extends StaticBody2D

# A wall of flame that blocks a doorway (the arena seal). Solid while it
# burns; fades and lets Veyl through when it goes out.

var size: Vector2
var time: float = 0.0
var strength: float = 0.0


func _init(wall_size: Vector2):

	size = wall_size
	collision_layer = 1
	collision_mask = 0
	z_index = 9
	var shape = RectangleShape2D.new()
	shape.size = size
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func _ready():
	create_tween().tween_property(self, "strength", 1.0, 0.4)


func fade_out():

	collision_layer = 0
	var tween = create_tween()
	tween.tween_property(self, "strength", 0.0, 0.8)
	tween.tween_callback(queue_free)


func _process(delta):
	time += delta
	queue_redraw()


func _draw():

	var half = size / 2.0
	for i in 7:
		var x = -half.x + size.x * (i + 0.5) / 7.0
		var h = size.y * (0.75 + 0.25 * sin(time * 6.0 + i * 1.7))
		var w = size.x / 5.0
		var c = Color(1.0, 0.4 + 0.2 * sin(time * 4.0 + i), 0.08, 0.75 * strength)
		draw_colored_polygon(PackedVector2Array([Vector2(x - w, half.y), Vector2(x + w, half.y), Vector2(x + sin(time * 5.0 + i) * 8.0, half.y - h)]), c)
	draw_rect(Rect2(-half, size), Color(1.0, 0.5, 0.15, 0.12 * strength))
