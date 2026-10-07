extends Node3D

# A carved stone whose inscription appears when the player is near.
# Hints at the larger mystery without explaining it.

const READ_RANGE = 10.0

@export_multiline var text: String = ""

var label: Label3D


func _ready():

	var stone = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(1.6, 3.0, 0.6)
	stone.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.34)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.5, 1.0)
	mat.emission_energy_multiplier = 0.15
	stone.material_override = mat
	stone.position.y = 1.5
	add_child(stone)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.text = text
	label.font_size = 34
	label.pixel_size = 0.03
	label.outline_size = 10
	label.width = 700
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.7, 0.8, 1.0, 0.0)
	label.outline_modulate = Color(0, 0, 0, 0)
	label.position.y = 6.0
	add_child(label)


func _process(delta):

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var offset = player.global_position - global_position
	offset.y = 0
	var target = 1.0 if offset.length() < READ_RANGE else 0.0
	label.modulate.a = move_toward(label.modulate.a, target, delta * 2.0)
	label.outline_modulate.a = label.modulate.a
