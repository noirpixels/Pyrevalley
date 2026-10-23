extends Node3D

# Glowing ember dropped by defeated creatures. Walk over it to heal.

const PICKUP_RANGE = 4.0
const LIFETIME = 15.0

var heal_amount: float = 12.0
var player: Node3D
var age: float = 0.0

@onready var orb: MeshInstance3D = MeshInstance3D.new()


func _ready():
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	orb.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 3.0
	orb.material_override = mat
	add_child(orb)

	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.1)
	light.omni_range = 5.0
	add_child(light)


func _process(delta):
	age += delta
	orb.position.y = 1.0 + sin(age * 4.0) * 0.3

	# Blink before disappearing
	if age > LIFETIME - 3.0:
		visible = fmod(age, 0.25) < 0.15
	if age > LIFETIME:
		queue_free()
		return

	if player and not player.dead:
		var offset = player.global_position - global_position
		offset.y = 0
		if offset.length() < PICKUP_RANGE:
			player.heal(heal_amount)
			Sfx.play("pickup")
			queue_free()
