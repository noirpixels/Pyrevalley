extends Node2D

# A run of Pyrevalley: builds the seeded world (world_gen.gd, room.gd),
# spawns Veyl at the shrine vae last rested at, and keeps the camera on vem
# inside the current room. Rooms away from Veyl stop processing.

const WorldGen = preload("res://world_gen.gd")
const Room = preload("res://room.gd")
const Player = preload("res://player.gd")
const Fx = preload("res://fx.gd")

const CAMERA_FOLLOW = 7.0
const INTERACT_RANGE = 110.0
const CAMERA_LOOK_AHEAD = 70.0
# Vertical framing: Veyl sits a little below the middle of the screen
const CAMERA_LIFT = 70.0
# The arena is two screens wide: pull back and frame Veyl and the Ashbound
const ARENA_ZOOM = 0.8
const ARENA_FRAMING = 0.4

var world: Dictionary
var rooms = []
var player: Player
var camera: Camera2D
var current_room: Room
var fx: Fx
var spawner: Node
var shake_amount: float = 0.0
var interact_target: Node2D = null


func _ready():

	add_to_group("game")
	if GameState.seed_value == 0:
		GameState.new_game(randi() % 1000000 + 1)
	world = WorldGen.generate(GameState.seed_value)

	add_backdrop()
	for data in world["rooms"]:
		var room = Room.new()
		add_child(room)
		room.setup(data, GameState.seed_value)
		rooms.append(room)

	fx = Fx.new()
	add_child(fx)

	if ResourceLoader.exists("res://spawner.gd"):
		spawner = load("res://spawner.gd").new()
		add_child(spawner)
		spawner.populate(self)
		for room in rooms:
			room.terrain.ore_uncovered.connect(func(item, at): spawner.drop_item(item, room.position + at))
	replay_digs()

	player = Player.new()
	player.name = "Veyl"
	add_child(player)
	player.max_health = GameState.max_health
	player.health = GameState.health if GameState.health > 0.0 else GameState.max_health
	player.respawn_at(shrine_point())
	player.health = GameState.health if GameState.health > 0.0 else GameState.max_health
	player.died.connect(_on_player_died)
	NetSync.enter_world(self)

	RenderingServer.set_default_clear_color(Color(0.03, 0.025, 0.035))
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.global_position = camera_target(true)
	update_room(true)

	if ResourceLoader.exists("res://hud.gd"):
		add_child(load("res://hud.gd").new())
	if ResourceLoader.exists("res://ink_post.gd"):
		add_child(load("res://ink_post.gd").new())

	Sfx.play_music("forest")
	Sfx.play_ambience("forest")


# The forest behind the surface rooms, in layers that drift at different
# speeds (the main menu's art). Underground rooms cover it with rock.
func add_backdrop():

	var layers = [["sky", 0.05, 1280.0 / 960.0], ["far", 0.15, 1280.0 / 1920.0], ["mid", 0.3, 1280.0 / 1920.0], ["near", 0.5, 1280.0 / 1920.0]]
	var z = -100
	for l in layers:
		var parallax = Parallax2D.new()
		parallax.scroll_scale = Vector2(l[1], 1.0)
		parallax.repeat_size = Vector2(1280, 0)
		parallax.repeat_times = 3
		parallax.z_index = z
		z += 1
		var sprite = Sprite2D.new()
		sprite.texture = load("res://Menu/%s.png" % l[0])
		sprite.centered = false
		sprite.scale = Vector2(l[2], l[2])
		parallax.add_child(sprite)
		add_child(parallax)


# Ground dug in earlier sessions, from the save
func replay_digs():

	for room in rooms:
		var key = GameState.cell_key(room.cell)
		for d in GameState.dig_log.get(key, []):
			room.terrain.dig(Vector2(d[0], d[1]), d[2], int(d[3]), true)


func room_at(pos: Vector2) -> Room:

	for room in rooms:
		if room.contains(pos):
			return room
	return null


func room_for_cell(cell: Vector2i) -> Room:

	if not world["by_cell"].has(cell):
		return null
	return rooms[world["by_cell"][cell]]


# The terrain material under a point, or -1 for open air
func ground_material(pos: Vector2) -> int:

	var room = room_at(pos)
	if room == null:
		return -1
	var local = pos - room.position
	if not room.terrain.solid_at(local):
		return -1
	return room.terrain.material_at(local)


# Where Veyl wakes: in front of the last shrine rested at, or the first
func shrine_point() -> Vector2:

	var room = room_for_cell(GameState.shrine_cell) if GameState.shrine_cell != null else null
	if room == null:
		room = rooms[0]
	for m in room.markers:
		if m["kind"] == "S":
			return m["at"] + Vector2(70, -4)
	return room.rect.get_center()


func _process(delta):

	if player == null:
		return
	update_room(false)
	if NetSync.has_company() and Engine.get_process_frames() % 30 == 0:
		refresh_active_rooms()
	var zoom = ARENA_ZOOM if current_room and current_room.data["role"] == "boss" else 1.0
	camera.zoom = camera.zoom.lerp(Vector2(zoom, zoom), 1.0 - exp(-3.0 * delta))
	var target = camera_target(false)
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-CAMERA_FOLLOW * delta))
	shake_amount = move_toward(shake_amount, 0.0, delta * 2.5)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amount * 14.0
	update_interaction()


func shake(amount: float):
	shake_amount = max(shake_amount, amount)


# The nearest thing Veyl can use, shown as a prompt; E uses it
func update_interaction():

	var hud = get_tree().get_first_node_in_group("hud")
	var best: Node2D = null
	var best_d = INTERACT_RANGE
	if not player.dead and not player.input_blocked:
		for node in get_tree().get_nodes_in_group("interactable"):
			if not node.is_visible_in_tree():
				continue
			var d = node.global_position.distance_to(player.global_position + Vector2(0, -40))
			if d < best_d:
				best_d = d
				best = node
	interact_target = best
	if hud:
		hud.set_prompt(best.prompt_text() if best else "")
	if best and Input.is_action_just_pressed("interact") and not get_tree().paused:
		best.interact(player)


# Follows Veyl, held inside the current room so the next room only shows
# once vae walks through the door
func camera_target(_instant: bool) -> Vector2:

	var view = get_viewport_rect().size / camera.zoom
	var want = player.global_position + Vector2(player.facing * CAMERA_LOOK_AHEAD, -CAMERA_LIFT)
	if current_room and current_room.data["role"] == "boss":
		for c in get_tree().get_nodes_in_group("creatures"):
			if c.kind_name == "The Ashbound" and not c.is_dead():
				want.x = lerp(player.global_position.x, c.global_position.x, ARENA_FRAMING)
	var r = current_room.rect if current_room else Rect2(want - view / 2.0, view)
	var x = r.get_center().x if r.size.x <= view.x else clamp(want.x, r.position.x + view.x / 2.0, r.end.x - view.x / 2.0)
	var y = r.get_center().y if r.size.y <= view.y else clamp(want.y, r.position.y + view.y / 2.0, r.end.y - view.y / 2.0)
	return Vector2(x, y)


func update_room(instant: bool):

	var room = room_at(player.global_position + Vector2(0, -40))
	if room == null or room == current_room:
		return
	current_room = room
	for c in room.data["cells"]:
		GameState.visit(c)
	if instant and camera:
		camera.global_position = camera_target(true)
	refresh_active_rooms()
	var music = "deep" if room.underground else "forest"
	if room.data["role"] == "boss":
		music = "boss"
	Sfx.play_music(music)


# Only rooms with a player in or next to them keep running (on the host,
# guests' rooms count too, since the host runs every creature)
func refresh_active_rooms():

	var occupied = []
	for p in get_tree().get_nodes_in_group("players"):
		var r = room_at(p.global_position + Vector2(0, -40))
		if r:
			occupied.append(r)
	for r in rooms:
		var near = false
		for o in occupied:
			if r == o or r.rect.grow(10.0).intersects(o.rect):
				near = true
		r.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


# A host creature's warning or projectile, drawn on a guest's screen only
func show_creature_fx(kind: String, args: Array):

	match kind:
		"warn":
			add_child(load("res://telegraph.gd").new(args[0], args[1]))
		"wave":
			var wave = load("res://shockwave.gd").new(args[0], 0.0, args[2])
			wave.visual_only = true
			add_child(wave)
			wave.global_position = args[1]
		"glob":
			var glob = load("res://ember_glob.gd").new()
			glob.launch(args[0], args[1], 0.0)
			glob.visual_only = true
			add_child(glob)
		"erupt":
			var boss = NetSync.boss_node()
			if boss:
				boss.show_eruption(args[0])


func _on_player_died():

	await get_tree().create_timer(1.6).timeout
	# Only the host's world resets its creatures (a guest's are the host's)
	if Net.is_host() and not NetSync.has_company():
		GameState.killed = {}
		if spawner:
			spawner.respawn_creatures()
	player.respawn_at(shrine_point())


func _exit_tree():

	NetSync.leave_world()
	Engine.time_scale = 1.0
