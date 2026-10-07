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

var fire_light: OmniLight3D
var time: float = 0.0


func _ready():

	add_to_group("interactable")
	build_body()


func build_body():

	var cloak_mat = StandardMaterial3D.new()
	cloak_mat.albedo_color = Color(0.35, 0.18, 0.12)

	var body = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 1.2
	capsule.height = 5.5
	body.mesh = capsule
	body.material_override = cloak_mat
	body.position.y = 2.75
	add_child(body)

	var hood = MeshInstance3D.new()
	var hood_mesh = SphereMesh.new()
	hood_mesh.radius = 0.9
	hood_mesh.height = 1.8
	hood.mesh = hood_mesh
	hood.material_override = cloak_mat
	hood.position.y = 5.6
	add_child(hood)

	var name_label = Label3D.new()
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.text = "Rowan"
	name_label.font_size = 40
	name_label.pixel_size = 0.025
	name_label.outline_size = 10
	name_label.modulate = Color(1.0, 0.85, 0.6)
	name_label.position.y = 8.0
	add_child(name_label)

	var collision_body = StaticBody3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = 1.3
	shape.height = 6.0
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 3.0
	collision_body.add_child(collision)
	add_child(collision_body)

	# Campfire beside Rowan
	var fire_mat = StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.5, 0.1)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.4, 0.05)
	fire_mat.emission_energy_multiplier = 3.0

	var fire = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.8
	fire.mesh = cone
	fire.material_override = fire_mat
	fire.position = Vector3(-3.5, 0.9, 1.5)
	add_child(fire)

	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.5, 0.15)
	fire_light.light_energy = 3.0
	fire_light.omni_range = 14.0
	fire_light.position = Vector3(-3.5, 2.5, 1.5)
	add_child(fire_light)


func _process(delta):

	time += delta
	fire_light.light_energy = 3.0 + sin(time * 11.0) * 0.3 + sin(time * 7.3) * 0.2


# Called by the player when pressing E nearby
func interact(_player):

	var ui = get_tree().get_first_node_in_group("game_ui")
	Sfx.play("npc")

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
