extends Node2D

# A warning drawn before an attack lands: a glowing area that fills up as
# the moment approaches, then flashes and goes. Rect in local space.

var rect: Rect2
var duration: float
var time: float = 0.0
var color = Color(1.0, 0.25, 0.08)


func _init(area: Rect2, seconds: float):

	rect = area
	duration = seconds
	z_index = 3


func _process(delta):

	time += delta
	if time > duration + 0.15:
		queue_free()
		return
	queue_redraw()


func _draw():

	var t = clamp(time / duration, 0.0, 1.0)
	var c = color
	c.a = 0.18 + 0.12 * sin(time * 20.0)
	draw_rect(rect, c)
	# The fill rises from the floor as the strike comes
	var fill = Rect2(rect.position.x, rect.end.y - rect.size.y * t, rect.size.x, rect.size.y * t)
	var f = color
	f.a = 0.35
	draw_rect(fill, f)
	var edge = color.lightened(0.3)
	edge.a = 0.9 if time < duration else 1.0 - (time - duration) / 0.15
	draw_rect(rect, edge, false, 3.0)
