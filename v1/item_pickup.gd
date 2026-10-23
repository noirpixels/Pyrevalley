extends Node3D

# A resource on the ground. Creature drops are created in code; pickups
# placed in the level get a pickup_id so they stay collected after saving.

const FloatingText = preload("res://floating_text.gd")

const PICKUP_RANGE = 4.0
const MAGNET_RANGE = 9.0

const ITEM_COLORS = {
	"Ember Fang": Color(1.0, 0.5, 0.2),
	"Moss Fiber": Color(0.4, 1.0, 0.5),
	"Ash Core": Color(0.75, 0.3, 1.0),
}

@export var item_name: String = "Moss Fiber"
@export var amount: int = 1
@export var pickup_id: String = ""

var age: float = 0.0
var gem: MeshInstance3D


func _ready():

	if pickup_id != "":
		GameState.ensure_loaded()
		if pickup_id in GameState.collected_pickups:
			queue_free()
			return

	var color = ITEM_COLORS.get(item_name, Color.WHITE)

	var prism = PrismMesh.new()
	prism.size = Vector3(0.8, 1.0, 0.8)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5

	gem = MeshInstance3D.new()
	gem.mesh = prism
	gem.material_override = mat
	add_child(gem)

	var light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.position.y = 1.0
	add_child(light)


func _process(delta):

	age += delta
	gem.position.y = 1.2 + sin(age * 3.0) * 0.25
	gem.rotation.y += delta * 2.0

	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.dead:
		return

	var offset = player.global_position - global_position
	offset.y = 0

	# Drops drift toward the player once they're close
	if pickup_id == "" and offset.length() < MAGNET_RANGE:
		global_position += offset.normalized() * 10.0 * delta

	if offset.length() < PICKUP_RANGE:
		collect()


func collect():

	GameState.add_item(item_name, amount)
	if pickup_id != "":
		GameState.collected_pickups.append(pickup_id)

	Sfx.play("pickup")
	FloatingText.spawn(
		get_parent(),
		global_position + Vector3(0, 3, 0),
		"+%d %s" % [amount, item_name],
		ITEM_COLORS.get(item_name, Color.WHITE)
	)
	queue_free()
