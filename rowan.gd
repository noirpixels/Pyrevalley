extends Node3D

# Rowan: the prototype's quest giver, waiting by a campfire.
# Dialogue lines live here so they're easy to rewrite.

const LINES_INTRO = [
	"...You're awake. I wasn't sure you would be.",
	"The forest has become dangerous.",
	"Something is driving the creatures deeper into Emberwood.",
	"Clear the forest. Defeat three of them, then come back to me. I'll open the way north.",
]
const LINES_ACTIVE = [
	"Still %d to go. Watch for the red glow. That's when they strike.",
]
const LINES_TURN_IN = [
	"You did it. But they weren't attacking. They were running.",
	"Past the Deep Forest there's an arena of ash. Whatever waits there is what they fear.",
	"I've opened the way. And... the embers lean toward you when you pass. Strange.",
]
const LINES_AFTER = [
	"The Ashbound waits beyond the Deep Forest. Rest at the shrine first.",
]
const LINES_END = [
	"It's quiet. I haven't heard the forest this quiet in years.",
]

const BODY_TEXTURE = preload("res://NPCs/rowan.png")
const GLOW_TEXTURE = preload("res://NPCs/rowan_glow.png")
const SPRITE_PIXEL_SIZE = 0.0375
const SpritePose = preload("res://sprite_pose.gd")

var fire_light: OmniLight3D
var flames: Array[MeshInstance3D] = []
var time: float = 0.0
var body: Sprite3D
# Counts down after Veyl talks to him: a little bob of greeting
var greet_timer: float = 0.0


func _ready():

	add_to_group("interactable")
	build_body()


func build_body():

	# Painted sprite (tools/make_npc_sprites.py), same pixel density as Veyl
	body = Sprite3D.new()
	body.texture = BODY_TEXTURE
	body.pixel_size = SPRITE_PIXEL_SIZE
	body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	body.shaded = true
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

	# Eyes and lantern stay lit in the dark
	var glow = Sprite3D.new()
	glow.texture = GLOW_TEXTURE
	glow.pixel_size = SPRITE_PIXEL_SIZE
	glow.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	glow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	glow.shaded = false
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.render_priority = 1
	body.add_child(glow)
	SpritePose.pin_to_feet(body)

	var shadow_mesh = CylinderMesh.new()
	shadow_mesh.top_radius = 2.0
	shadow_mesh.bottom_radius = 2.0
	shadow_mesh.height = 0.02
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0, 0, 0, 0.35)
	var shadow = MeshInstance3D.new()
	shadow.mesh = shadow_mesh
	shadow.material_override = shadow_mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.scale = Vector3(1.0, 1.0, 0.55)
	shadow.position.y = 0.05
	add_child(shadow)

	var name_label = Label3D.new()
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.text = "Rowan"
	name_label.font_size = 40
	name_label.pixel_size = 0.025
	name_label.outline_size = 10
	name_label.modulate = Color(1.0, 0.85, 0.6)
	name_label.position.y = 10.0
	add_child(name_label)

	var collision_body = StaticBody3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = 1.3
	shape.height = 9.0
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 4.5
	collision_body.add_child(collision)
	add_child(collision_body)

	# Campfire beside Rowan: stone ring, crossed logs, two-layer flame
	var fire_pos = Vector3(-3.5, 0.0, 1.5)

	var stone_mat = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.3, 0.29, 0.31)
	for i in 8:
		var angle = TAU * i / 8.0
		var stone = MeshInstance3D.new()
		var stone_mesh = SphereMesh.new()
		stone_mesh.radius = 0.38
		stone_mesh.height = 0.5
		stone_mesh.radial_segments = 6
		stone_mesh.rings = 3
		stone.mesh = stone_mesh
		stone.material_override = stone_mat
		stone.position = fire_pos + Vector3(cos(angle) * 1.35, 0.18, sin(angle) * 1.35)
		add_child(stone)

	var log_mat = StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.25, 0.16, 0.1)
	for angle in [0.4, 1.45, 2.5]:
		var wood = MeshInstance3D.new()
		var log_mesh = CylinderMesh.new()
		log_mesh.top_radius = 0.18
		log_mesh.bottom_radius = 0.22
		log_mesh.height = 2.0
		log_mesh.radial_segments = 6
		wood.mesh = log_mesh
		wood.material_override = log_mat
		wood.position = fire_pos + Vector3(0, 0.3, 0)
		wood.rotation = Vector3(deg_to_rad(80), angle, 0)
		add_child(wood)

	flames = []
	for layer in [[Color(1.0, 0.4, 0.05), 0.85, 1.9], [Color(1.0, 0.8, 0.3), 0.45, 1.2]]:
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = layer[0]
		var flame = MeshInstance3D.new()
		var cone = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = layer[1]
		cone.height = layer[2]
		cone.radial_segments = 7
		flame.mesh = cone
		flame.material_override = mat
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.position = fire_pos + Vector3(0, 0.35 + layer[2] / 2.0, 0)
		add_child(flame)
		flames.append(flame)

	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.5, 0.15)
	fire_light.light_energy = 3.0
	fire_light.omni_range = 14.0
	fire_light.position = Vector3(-3.5, 2.5, 1.5)
	add_child(fire_light)


func _process(delta):

	time += delta
	fire_light.light_energy = 3.0 + sin(time * 11.0) * 0.3 + sin(time * 7.3) * 0.2
	for i in flames.size():
		var flicker = 1.0 + sin(time * (9.0 + i * 4.0)) * 0.08 + sin(time * 13.7 + i) * 0.05
		flames[i].scale = Vector3(1.0 / flicker, flicker, 1.0 / flicker)
		flames[i].rotation.y = time * (0.6 - i * 1.4)

	# Slow breathing and a gentle sway by the fire
	greet_timer = max(greet_timer - delta, 0.0)
	var breath = sin(time * 2.0) * 0.02
	var bob = sin((1.0 - greet_timer / 0.5) * PI) * 0.1 if greet_timer > 0.0 else 0.0
	SpritePose.apply(body, sin(time * 0.9) * 0.025, Vector2(1.0 - breath * 0.5 + bob * 0.5, 1.0 + breath - bob))


# Called by the player when pressing E nearby
func interact(_player):

	var ui = get_tree().get_first_node_in_group("game_ui")
	Sfx.play("npc")
	greet_timer = 0.5

	if GameState.boss_defeated:
		ui.show_dialogue("Rowan", LINES_END)
		return

	match GameState.quest_state:

		GameState.QUEST_NOT_STARTED:
			ui.show_dialogue("Rowan", LINES_INTRO, func():
				GameState.accept_quest()
				GameState.notify.emit("Quest started: Clear the Forest")
				GameState.save_game(_player)
			)

		GameState.QUEST_ACTIVE:
			var remaining = GameState.QUEST_GOAL - GameState.quest_progress
			ui.show_dialogue("Rowan", [LINES_ACTIVE[0] % remaining])

		GameState.QUEST_RETURN:
			ui.show_dialogue("Rowan", LINES_TURN_IN, func():
				GameState.complete_quest()
				GameState.notify.emit("Quest complete. The path to the Ashbound is open.")
				GameState.save_game(_player)
			)

		_:
			ui.show_dialogue("Rowan", LINES_AFTER)


func prompt_text() -> String:
	return "[E] Talk to Rowan"
