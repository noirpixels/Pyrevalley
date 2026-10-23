extends Node3D

# Something on the ground to pick up. Creature drops glow and drift to you;
# mined and chopped materials lie where they fell (walk over them to take
# them) and sink away after a minute; forage lies on the forest floor.
# Drops are made in code (net_sync.gd drop); pickups placed in the level
# get a pickup_id so they stay collected after saving. With several
# players, the first to reach it gets it: the host decides, then it's
# collect()ed by the winner and vanish()es for everyone else.

const FloatingText = preload("res://floating_text.gd")

const Items = preload("res://items.gd")

const PICKUP_RANGE = 4.0
const MAGNET_RANGE = 9.0
# Mined and chopped materials lie this long, then sink into the ground
const LOOSE_LIFETIME = 60.0
const SINK_TIME = 4.0

@export var item_name: String = "Moss Fiber"
@export var amount: int = 1
@export var pickup_id: String = ""
# Set on drops so every machine can name the same one
var drop_id: String = ""
# "item": a creature's drop, a glowing gem that drifts to you;
# "loose": mined or chopped, lies where it fell until it sinks away;
# "forage": lying on the forest floor until someone takes it
var pickup_kind: String = "item"

var age: float = 0.0
var gem: MeshInstance3D
var settle_timer: float = 0.0
var floor_y: float = 0.0


func _ready():

	if pickup_id != "":
		GameState.ensure_loaded()
		if pickup_id in GameState.collected_pickups:
			queue_free()
			return

	add_to_group("pickups")
	NetSync.register_pickup(self)

	var color = Items.color(item_name)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	gem = MeshInstance3D.new()
	gem.material_override = mat
	add_child(gem)
	floor_y = global_position.y

	if pickup_kind == "item":
		var prism = PrismMesh.new()
		prism.size = Vector3(0.8, 1.0, 0.8)
		gem.mesh = prism
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
		var light = OmniLight3D.new()
		light.light_color = color
		light.light_energy = 0.8
		light.omni_range = 4.0
		light.position.y = 1.0
		add_child(light)
	else:
		# A chunk of rock or ore, a log, a stick: no glow, just the thing
		var box = BoxMesh.new()
		match item_name:
			"Log":
				box.size = Vector3(0.9, 0.9, 3.2)
			"Branch":
				box.size = Vector3(0.25, 0.25, 2.2)
			_:
				box.size = Vector3(1.0, 0.8, 1.0)
		gem.mesh = box
		gem.position.y = box.size.y / 2.0
		gem.rotation.y = randf() * TAU
		if item_name == "Emberstone":
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 2.0


func _process(delta):

	age += delta
	if pickup_kind == "item":
		gem.position.y = 1.2 + sin(age * 3.0) * 0.25
		gem.rotation.y += delta * 2.0
	else:
		settle(delta)
		if pickup_kind == "loose" and age > LOOSE_LIFETIME - SINK_TIME:
			gem.position.y -= delta * 1.5
			if age > LOOSE_LIFETIME:
				queue_free()
				return

	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.dead:
		return

	var offset = player.global_position - global_position
	offset.y = 0

	# Creature drops drift toward the player once they're close
	if pickup_kind == "item" and pickup_id == "" and offset.length() < MAGNET_RANGE:
		global_position += offset.normalized() * 10.0 * delta

	var feet = player.global_position.y - player.foot_height()
	if offset.length() < PICKUP_RANGE and abs(feet - global_position.y) < 5.0:
		NetSync.claim(self)


# Falls to whatever is below: dug out of a wall, or left hanging when the
# block under it is mined away
func settle(delta: float):

	settle_timer -= delta
	if settle_timer <= 0.0:
		settle_timer = 0.3
		var ray = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, global_position + Vector3.DOWN * 60.0)
		var hit = get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			floor_y = hit["position"].y
	global_position.y = move_toward(global_position.y, floor_y, 25.0 * delta)


func net_id() -> String:
	return pickup_id if pickup_id != "" else drop_id


func kind() -> String:
	return pickup_kind


func _exit_tree():
	NetSync.unregister_pickup(self)


# Someone else got there first
func vanish():
	queue_free()


func collect():

	GameState.add_item(item_name, amount)

	Sfx.play("pickup")
	FloatingText.spawn(
		get_parent(),
		global_position + Vector3(0, 3, 0),
		"+%d %s" % [amount, item_name],
		Items.color(item_name)
	)
	queue_free()
