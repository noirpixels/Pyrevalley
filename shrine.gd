extends Node2D

# An ember shrine: a stone basin with a flame that never goes out. Resting
# here heals Veyl, sets where vae wakes after dying, inks the map, brings
# the creatures back and saves. The flame is also a forge (crafting).

var cell: Vector2i
var time: float = 0.0


func _ready():
	add_to_group("interactable")
	z_index = -2


func prompt_text() -> String:
	return "Rest at the shrine"


func interact(player: Node):

	var first = GameState.shrine_cell != cell
	GameState.shrine_cell = cell
	player.heal(player.max_health)
	GameState.ink_map()
	for key in GameState.taken.keys():
		if key.begins_with("forage:"):
			GameState.taken.erase(key)
	var spawner = get_tree().get_first_node_in_group("spawner")
	if spawner:
		spawner.regrow_forage()
		# Creatures come back only in the host's world, and only when the
		# host rests alone (not mid-fight for a friend)
		if Net.is_host() and not NetSync.has_company():
			GameState.killed = {}
			spawner.respawn_creatures()
	GameState.save_game(player)
	Sfx.play("checkpoint")
	var fx = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.burst(global_position + Vector2(0, -60), Color(1.0, 0.6, 0.25), 30, 300.0, 0.9)
	GameState.notify.emit("Ember shrine kindled. You will wake here." if first else "You rest. The map sets in ink.")
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.open_crafting(true)


func _process(delta):
	time += delta
	queue_redraw()


func _draw():

	# Warm light on the ground and the air around the flame
	InkDraw.glow(self, Vector2(0, -60), 190.0, Color(1.0, 0.45, 0.12, 0.3 + 0.04 * sin(time * 3.0)))
	var stone = Color(0.34, 0.31, 0.32)
	var dark = stone.darkened(0.35)

	# A broad foot stone, a pillar of two blocks and a carved bowl
	var foot = PackedVector2Array([Vector2(-34, 0), Vector2(34, 0), Vector2(29, -10), Vector2(-29, -10)])
	var lower = PackedVector2Array([Vector2(-20, -10), Vector2(20, -10), Vector2(17, -30), Vector2(-17, -30)])
	var upper = PackedVector2Array([Vector2(-16, -30), Vector2(16, -30), Vector2(14, -46), Vector2(-14, -46)])
	var bowl = PackedVector2Array([Vector2(-38, -58), Vector2(38, -58), Vector2(32, -50), Vector2(18, -45), Vector2(-18, -45), Vector2(-32, -50)])
	for part in [foot, lower, upper, bowl]:
		InkDraw.fill(self, part, stone)
	# Shade on the side away from the flame's lean, and a lit rim on the bowl
	InkDraw.fill(self, PackedVector2Array([Vector2(8, -10), Vector2(20, -10), Vector2(17, -30), Vector2(6, -30)]), dark)
	InkDraw.fill(self, PackedVector2Array([Vector2(6, -30), Vector2(16, -30), Vector2(14, -46), Vector2(5, -46)]), dark)
	InkDraw.line(self, Vector2(-36, -57), Vector2(36, -57), 3.0, Color(1.0, 0.6, 0.25, 0.8), 4.0)
	# Carved rings and a couple of cracks
	InkDraw.line(self, Vector2(-12, -38), Vector2(12, -38), 1.6, InkDraw.INK, 5.0)
	InkDraw.line(self, Vector2(-9, -20), Vector2(-3, -14), 1.4, InkDraw.INK, 6.0)
	InkDraw.line(self, Vector2(22, -5), Vector2(27, -2), 1.4, InkDraw.INK, 7.0)
	for part in [foot, lower, upper, bowl]:
		InkDraw.outline(self, part, 3.0, InkDraw.INK, part[0].y)

	# The flame: three tongues that lick and sway, outer one inked
	for i in 3:
		var sway = sin(time * (4.0 + i * 1.3) + i * 2.0) * (6.0 - i * 1.5)
		var hgt = 58.0 - i * 15.0 + sin(time * 6.5 + i) * 7.0
		var wdt = 22.0 - i * 6.0
		var col = [Color(0.95, 0.32, 0.06), Color(1.0, 0.62, 0.18), Color(1.0, 0.93, 0.65)][i]
		var pts = PackedVector2Array()
		for k in 13:
			var t = k / 12.0
			var y = -58.0 - hgt * t
			var w = wdt * pow(1.0 - t, 0.42) * (0.8 + 0.3 * sin(t * PI)) + sin(t * 9.0 + time * 8.0 + i) * 2.5 * t * (1.0 - t)
			pts.append(Vector2(-w + sway * t * t, y))
		for k in range(11, -1, -1):
			var t = k / 12.0
			var y = -58.0 - hgt * t
			var w = wdt * pow(1.0 - t, 0.42) * (0.8 + 0.3 * sin(t * PI)) + sin(t * 9.0 + time * 8.0 + i) * 2.5 * t * (1.0 - t)
			pts.append(Vector2(w + sway * t * t, y))
		InkDraw.fill(self, pts, col)
		if i == 0:
			# Each side of the outer tongue as its own stroke up to the tip
			InkDraw.stroke(self, pts.slice(0, 13), 2.4, InkDraw.INK, time)
			var right = pts.slice(13)
			right.reverse()
			right.append(pts[12])
			InkDraw.stroke(self, right, 2.4, InkDraw.INK, time + 1.0)
