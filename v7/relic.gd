extends Node2D

# Something left for Veyl to find, floating where it was hidden:
#   cinderwing  a feather of living flame; grants a second jump in the air
#   heart       an Ember Heart; raises Veyl's health for good

var kind: String
var taken_id: String
var time: float = 0.0


func _init(relic_kind: String, id: String):

	kind = relic_kind
	taken_id = id
	z_index = 6


func _ready():
	add_to_group("interactable")


func prompt_text() -> String:
	return "Take the feather of flame" if kind == "cinderwing" else "Take the Ember Heart"


func interact(player: Node):

	GameState.taken[taken_id] = true
	var hud = get_tree().get_first_node_in_group("hud")
	if kind == "cinderwing":
		GameState.learn("cinderwing")
		if hud:
			hud.banner("CINDERWING", "Press Jump again in the air to leap from the embers.")
	else:
		GameState.max_health += 25.0
		player.max_health = GameState.max_health
		player.heal(player.max_health)
		if hud:
			hud.banner("EMBER HEART", "It beats in your chest. You can take more before you fall.")
	Sfx.play("boss_death", -8.0, 1.5)
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.burst(global_position, Color(1.0, 0.7, 0.3), 50, 520.0, 0.2)
	GameState.save_game(player)
	queue_free()


func _process(delta):
	time += delta
	queue_redraw()


func _draw():

	var bob = Vector2(0, sin(time * 2.0) * 8.0)
	for i in 5:
		draw_circle(bob, 60.0 - i * 10.0, Color(1.0, 0.5, 0.15, 0.05 + i * 0.03))
	var ink = Color(0.035, 0.028, 0.045)
	if kind == "cinderwing":
		# A feather: a curved vane of flame
		var pts = PackedVector2Array()
		for i in 9:
			var t = i / 8.0
			pts.append(bob + Vector2(-6 + sin(t * PI) * 14.0, 26 - t * 52))
		for i in range(7, 0, -1):
			var t = i / 8.0
			pts.append(bob + Vector2(-6 - sin(t * PI) * 4.0 + t * 6.0, 26 - t * 52))
		draw_colored_polygon(pts, Color(1.0, 0.55, 0.15))
		pts.append(pts[0])
		draw_polyline(pts, ink, 2.5)
		draw_line(bob + Vector2(-6, 30), bob + Vector2(0, -26), Color(1.0, 0.9, 0.6), 2.0)
	else:
		# A heart: two lobes and a point, beating
		var s = 1.0 + 0.08 * max(sin(time * 6.0), 0.0)
		var red = Color(0.95, 0.3, 0.1)
		for side in [-1.0, 1.0]:
			draw_circle(bob + Vector2(side * 10.0, -6.0) * s, 13.0 * s, ink)
		draw_colored_polygon(PackedVector2Array([bob + Vector2(-24, -2) * s, bob + Vector2(24, -2) * s, bob + Vector2(0, 26) * s]), ink)
		for side in [-1.0, 1.0]:
			draw_circle(bob + Vector2(side * 10.0, -6.0) * s, 10.5 * s, red)
		draw_colored_polygon(PackedVector2Array([bob + Vector2(-20.5, -2) * s, bob + Vector2(20.5, -2) * s, bob + Vector2(0, 22) * s]), red)
		draw_circle(bob + Vector2(-12, -10) * s, 3.0 * s, Color(1.0, 0.8, 0.6))
