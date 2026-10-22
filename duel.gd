extends Node3D

# Local Duel: two players on one keyboard fight in the Proving Ring, best
# Built entirely here (duel.tscn is just this script):
# the ring, the inked look, two Veyls on their halves of the keyboard
# (pad.gd DUEL_ACTIONS), a camera that keeps both in view, and the HUD.
#   Player 1: WASD move, X / C strike, Q launch, E slam, G jump, Left Shift dodge
#   Player 2: arrows move, / and Right Shift strike, , launch, . slam, L jump, ; dodge
# Esc pauses. Tab swaps between the angled view and a side-on test view
# (fighters locked to one plane, Up jumps).

const PlayerScene = preload("res://player.tscn")
const PvpRing = preload("res://pvp_ring.gd")
const InkPost = preload("res://ink_post.gd")
const InkBar = preload("res://ink_bar.gd")
const UI = preload("res://ui_kit.gd")

const ROUNDS_TO_WIN = 5
const START_GAP = 9.0
# Orthographic view height: tight when they're close, wider as they part
const VIEW_MIN = 30.0
const VIEW_MAX = 64.0
const CAMERA_PITCH = -35.0
const CAMERA_YAW = 45.0
# Side-on: looking along -Z, tipped down enough that the floor fills the
# frame behind the fighters instead of an empty sky
const SIDE_PITCH = -14.0
const KEYS = [
	"WASD move  ·  X / C strike  ·  Q launch  ·  E slam  ·  G jump  ·  L-Shift dodge",
	"Arrows move  ·  / and R-Shift strike  ·  , launch  ·  . slam  ·  L jump  ·  ; dodge",
]

var fighters: Array = []
var wins = [0, 0]
var round_number = 0
var round_live = false
var camera: Camera3D
var side_on = true
var ring: Node3D
var view_hint: Label

var bars: Array = []
var pips: Array = []
var banner: Label
var sub_banner: Label
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_title: Label


func _ready():

	build_world()
	build_fighters()
	build_hud()
	Sfx.play_music("boss")
	start_round()


# ============================================================
# WORLD
# ============================================================

func build_world():

	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.44, 0.62)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.35
	env.glow_enabled = true
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.13, 0.1, 0.14)
	env.fog_density = 0.0025
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 8, 0)
	sun.light_color = Color(1, 0.8, 0.6)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	# The forest floor, the same painted ground as Emberwood
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(160, 160)
	var ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://game.gdshader")
	ground_mat.set_shader_parameter("mesh_offset_z", 0.0)
	ground_mat.set_shader_parameter("ground_size", plane.size)
	plane.material = ground_mat
	ground.mesh = plane
	ground.set_script(load("res://ground_textures.gd"))
	var layers: Array[Texture2D] = []
	for name in ["grass1", "tgrass1", "fgrass1", "dp1", "r1", "m1"]:
		layers.append(load("res://Textures/Grass/%s.png" % name))
	ground.terrain_layers = layers
	add_child(ground)

	var floor_body = StaticBody3D.new()
	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(160, 2, 160)
	floor_shape.shape = box
	floor_shape.position.y = -1.0
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	ring = PvpRing.new()
	ring.arena_only = true
	add_child(ring)

	add_child(InkPost.new())

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW_MIN
	camera.far = 400.0
	camera.rotation_degrees = Vector3(CAMERA_PITCH, CAMERA_YAW, 0)
	add_child(camera)
	camera.make_current()


func build_fighters():

	for i in 2:
		var veyl = PlayerScene.instantiate()
		veyl.input_prefix = "p%d" % (i + 1)
		veyl.name = "Player%d" % (i + 1)
		veyl.find_child("MainGameCamera").current = false
		# Player 2 is the darker Veyl
		if i == 1:
			veyl.base_tint = veyl.SHADE_TINT
		add_child(veyl)
		var label = Label3D.new()
		label.text = "P%d" % (i + 1)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 48
		label.pixel_size = 0.005
		label.outline_size = 12
		label.modulate = UI.EMBER if i == 0 else UI.TEXT
		label.position.y = 1.55
		veyl.add_child(label)
		veyl.died.connect(_on_fighter_died.bind(i))
		veyl.health_changed.connect(_on_health_changed.bind(i))
		fighters.append(veyl)
	fighters[0].opponent = fighters[1]
	fighters[1].opponent = fighters[0]
	set_view(side_on)


func set_view(side: bool):

	side_on = side
	camera.rotation_degrees = Vector3(SIDE_PITCH, 0, 0) if side else Vector3(CAMERA_PITCH, CAMERA_YAW, 0)
	for veyl in fighters:
		veyl.plane_lock = side
		# Moves and facing are screen-relative, so they follow the camera
		veyl.iso_yaw_degrees = 0.0 if side else CAMERA_YAW
		if side:
			veyl.global_position.z = 0.0
	# The near half of the ring wall would stand between the camera and
	# the fight; it still blocks, it just isn't drawn
	for segment in ring.get_children():
		if segment is StaticBody3D:
			for child in segment.get_children():
				if child is Node3D:
					child.visible = not (side and segment.position.z > 1.0)
		elif segment is Label3D:
			# The ring's title would sit right behind the fighters
			segment.visible = not side
	if view_hint:
		view_hint.text = "TAB  ·  %s" % ("SIDE-ON  (Up jumps)" if side else "ANGLED")


func _process(delta):

	if fighters.is_empty():
		return
	var a = fighters[0].global_position
	var b = fighters[1].global_position
	var focus = (a + b) / 2.0 + Vector3(0, 3.0, 0)
	var gap = Vector2(a.x - b.x, a.z - b.z).length()
	var view = clamp(gap * 1.25 + 16.0, VIEW_MIN, VIEW_MAX)
	if side_on:
		# Height matters side-on: frame both fighters top to bottom too
		view = clamp(max(view, abs(a.y - b.y) * 1.3 + 16.0), VIEW_MIN, VIEW_MAX)
	camera.size = lerp(camera.size, view, 1.0 - exp(-4.0 * delta))
	if side_on:
		# Ease after launches rather than jerking up with them
		var low = min(a.y, b.y)
		focus.y = low + camera.size * 0.12
		var target = focus + camera.global_basis.z * 120.0
		camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-6.0 * delta))
	else:
		camera.global_position = focus + camera.global_basis.z * 120.0


# ============================================================
# ROUNDS
# ============================================================

func start_round():

	round_number += 1
	round_live = false
	for i in 2:
		var veyl = fighters[i]
		veyl.global_position = Vector3(START_GAP * (-1 if i == 0 else 1), 6.0, 0)
		veyl.velocity = Vector3.ZERO
		veyl.health = veyl.max_health
		veyl.dead = false
		veyl.invuln_timer = 0.0
		veyl.combo.drop()
		veyl.input_blocked = true
		if veyl.sprite:
			veyl.sprite.modulate = veyl.base_tint
		veyl.health_changed.emit(veyl.health, veyl.max_health)
	show_banner("ROUND %d" % round_number, "")
	await get_tree().create_timer(1.2).timeout
	show_banner("FIGHT!", "")
	Sfx.play("boss_roar", -8.0, 1.4)
	for veyl in fighters:
		veyl.input_blocked = false
	round_live = true
	await get_tree().create_timer(0.8).timeout
	if round_live:
		show_banner("", "")


func _on_fighter_died(loser: int):

	if not round_live:
		return
	round_live = false
	var winner = 1 - loser
	wins[winner] += 1
	update_pips()
	for veyl in fighters:
		veyl.input_blocked = true
	Sfx.play("kill", -2.0)

	# The knockout lands in slow motion
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.9, true, false, true).timeout
	Engine.time_scale = 1.0

	if wins[winner] >= ROUNDS_TO_WIN:
		show_banner("", "")
		end_title.text = "PLAYER %d WINS" % (winner + 1)
		end_panel.visible = true
		Sfx.play_music("ending")
		return
	show_banner("PLAYER %d TAKES THE ROUND" % (winner + 1), "%d  —  %d" % [wins[0], wins[1]])
	await get_tree().create_timer(2.0).timeout
	start_round()


func rematch():

	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func quit_to_menu():

	get_tree().paused = false
	Engine.time_scale = 1.0
	Sfx.stop_music()
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _unhandled_input(event):

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		set_view(not side_on)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not end_panel.visible:
		pause_panel.visible = not pause_panel.visible
		get_tree().paused = pause_panel.visible
		get_viewport().set_input_as_handled()


# ============================================================
# HUD
# ============================================================

func build_hud():

	var layer = CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root = UI.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	for i in 2:
		var box = VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0:
			box.position = Vector2(24, 20)
		else:
			box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			box.offset_left = -344
			box.offset_right = -24
			box.offset_top = 20
		root.add_child(box)
		var name_label = UI.title("PLAYER %d" % (i + 1), 22, UI.EMBER if i == 0 else UI.TEXT)
		if i == 1:
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(name_label)
		var bar = InkBar.new(Vector2(320, 18), Color(0.85, 0.3, 0.08))
		box.add_child(bar)
		bars.append(bar)
		var pip = UI.label("", 20, UI.EMBER)
		if i == 1:
			pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(pip)
		pips.append(pip)

		var keys = UI.label(KEYS[i], 14, UI.MUTED)
		keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT if i == 0 else Control.PRESET_BOTTOM_RIGHT)
		if i == 0:
			keys.offset_left = 24
			keys.offset_top = -36
		else:
			keys.offset_left = -640
			keys.offset_right = -24
			keys.offset_top = -36
			keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		root.add_child(keys)
	update_pips()

	view_hint = UI.label("", 16, UI.MUTED)
	view_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	view_hint.offset_left = -200
	view_hint.offset_right = 200
	view_hint.offset_top = 24
	view_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(view_hint)
	set_view(side_on)

	banner = UI.title("", 64, UI.EMBER)
	UI.centered(banner)
	banner.offset_top = -120
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner)
	sub_banner = UI.title("", 32, UI.TEXT)
	UI.centered(sub_banner)
	sub_banner.offset_top = -40
	sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub_banner)

	pause_panel = menu_panel("PAUSED", [["RESUME", func():
		pause_panel.visible = false
		get_tree().paused = false], ["REMATCH", rematch], ["QUIT TO MENU", quit_to_menu]])
	root.add_child(pause_panel)

	end_panel = menu_panel("", [["REMATCH", rematch], ["QUIT TO MENU", quit_to_menu]])
	end_title = end_panel.get_child(0).get_child(0)
	root.add_child(end_panel)


func menu_panel(title: String, buttons: Array) -> PanelContainer:

	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_style())
	UI.centered(panel)
	panel.visible = false
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var heading = UI.title(title, 38, UI.EMBER)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	for b in buttons:
		box.add_child(UI.button(b[0], b[1]))
	return panel


func show_banner(text: String, sub: String):

	banner.text = text
	sub_banner.text = sub


func update_pips():

	for i in 2:
		pips[i].text = "◆ ".repeat(wins[i]) + "◇ ".repeat(ROUNDS_TO_WIN - wins[i])


func _on_health_changed(current: float, maximum: float, i: int):

	bars[i].set_values(current, maximum)


func _exit_tree():

	Engine.time_scale = 1.0
