extends StaticBody3D

# Wall of embers across the arena entrance that closes while the Ashbound
# is fighting. Without it the boss could be dragged to the edge of its
# leash, or out to the arena shrine, and poked or out-healed from there.
# Opens again when the fight ends: boss defeated, or Veyl dies (the boss
# resets and Veyl wakes at the shrine outside).

@export var width: float = 26.0

const EmberWall = preload("res://ember_wall.gd")

var collision: CollisionShape3D
var wall: EmberWall


func _ready():

	var shape = BoxShape3D.new()
	shape.size = Vector3(width, 14.0, 2.0)
	collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 7.0
	collision.disabled = true
	add_child(collision)

	wall = EmberWall.new(width)
	wall.strength = 0.0
	add_child(wall)

	GameState.boss_engaged.connect(func(_boss): close())
	GameState.boss_disengaged.connect(open)


func close():

	if not collision.disabled:
		return

	# Never trap Veyl inside the wall: push vem into the arena first
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var local = to_local(player.global_position)
		if abs(local.z) < 4.0 and abs(local.x) < width / 2.0 + 3.0:
			player.global_position = to_global(Vector3(local.x, local.y, -4.5))

	collision.set_deferred("disabled", false)
	Sfx.play("gate_open")
	GameState.notify.emit("Embers seal the way behind you.")
	wall.fade_to(1.0, 0.6)


func open():

	if collision.disabled:
		return

	collision.set_deferred("disabled", true)
	wall.fade_to(0.0, 0.8)
