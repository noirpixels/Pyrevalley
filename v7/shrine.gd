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

	var ink = Color(0.035, 0.028, 0.045)
	# Warm light on the ground around it
	for i in 6:
		var r = 150.0 - i * 22.0
		draw_circle(Vector2(0, -40), r, Color(1.0, 0.45, 0.12, 0.035 + i * 0.012))
	# Plinth and basin
	var stone = Color(0.3, 0.28, 0.32)
	var plinth = PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(18, -46), Vector2(-18, -46)])
	draw_colored_polygon(plinth, stone)
	var basin = PackedVector2Array([Vector2(-40, -46), Vector2(40, -46), Vector2(30, -66), Vector2(-30, -66)])
	draw_colored_polygon(basin, stone.lightened(0.15))
	plinth.append(plinth[0])
	basin.append(basin[0])
	draw_polyline(plinth, ink, 3.0)
	draw_polyline(basin, ink, 3.0)
	# Flame: a few flickering tongues
	for i in 3:
		var sway = sin(time * (5.0 + i) + i * 2.0) * 5.0
		var hgt = 46.0 + sin(time * 7.0 + i) * 8.0 - i * 10.0
		var wdt = 18.0 - i * 4.0
		var col = [Color(0.95, 0.3, 0.05), Color(1.0, 0.6, 0.15), Color(1.0, 0.92, 0.6)][i]
		var flame = PackedVector2Array([Vector2(-wdt, -66), Vector2(wdt, -66), Vector2(sway, -66 - hgt)])
		draw_colored_polygon(flame, col)
