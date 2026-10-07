extends Node3D

# Ember shrine: a safe location. Walking up to it restores HP, saves the
# game, and makes it the respawn point.

const ACTIVATE_RANGE = 7.0

var player_near: bool = false
var flame_mat: StandardMaterial3D
var light: OmniLight3D


func _ready():

	var stone_mat = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.25, 0.24, 0.26)

	var pillar = MeshInstance3D.new()
	var pillar_mesh = CylinderMesh.new()
	pillar_mesh.top_radius = 0.9
	pillar_mesh.bottom_radius = 1.3
	pillar_mesh.height = 3.0
	pillar.mesh = pillar_mesh
	pillar.material_override = stone_mat
	pillar.position.y = 1.5
	add_child(pillar)

	flame_mat = StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.45, 0.1)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.4, 0.05)
	flame_mat.emission_energy_multiplier = 0.3

	var flame = MeshInstance3D.new()
	var flame_mesh = SphereMesh.new()
	flame_mesh.radius = 0.6
	flame_mesh.height = 1.4
	flame.mesh = flame_mesh
	flame.material_override = flame_mat
	flame.position.y = 3.7
	add_child(flame)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 0.6
	light.omni_range = 10.0
	light.position.y = 4.0
	add_child(light)

	# Already the active shrine in a loaded save
	GameState.ensure_loaded()
	if GameState.checkpoint_position != null and GameState.checkpoint_position.distance_to(respawn_point()) < 1.0:
		set_lit(true)


func _process(_delta):

	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.dead:
		return

	var offset = player.global_position - global_position
	offset.y = 0
	var near = offset.length() < ACTIVATE_RANGE

	if near and not player_near:
		activate(player)

	player_near = near


func activate(player):

	var first_time = GameState.checkpoint_position == null or GameState.checkpoint_position.distance_to(respawn_point()) > 1.0

	GameState.checkpoint_position = respawn_point()
	if player.health < player.max_health:
		player.heal(player.max_health - player.health)
	GameState.save_game(player)
	set_lit(true)

	if first_time:
		Sfx.play("checkpoint")
		GameState.notify.emit("Ember shrine kindled. You will awaken here.")


func set_lit(lit: bool):

	flame_mat.emission_energy_multiplier = 3.0 if lit else 0.3
	light.light_energy = 2.5 if lit else 0.6


# Slightly in front of the shrine, high enough to drop onto the ground
func respawn_point() -> Vector3:
	return global_position + global_basis.z * 4.0 + Vector3(0, 6.0, 0)
