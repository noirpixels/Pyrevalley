extends StaticBody3D

# Wall of embers across the arena entrance that closes while the Ashbound
# is fighting. Without it the boss could be dragged to the edge of its
# leash, or out to the arena shrine, and poked or out-healed from there.
# Opens again when the fight ends: boss defeated, or Veyl dies (the boss
# resets and Veyl wakes at the shrine outside).

@export var width: float = 26.0

var collision: CollisionShape3D
var mat: StandardMaterial3D
var wall: MeshInstance3D
var light: OmniLight3D


func _ready():

	var shape = BoxShape3D.new()
	shape.size = Vector3(width, 14.0, 2.0)
	collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 7.0
	collision.disabled = true
	add_child(collision)

	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.3, 0.05, 0.0)

	wall = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(width, 10.0, 0.6)
	wall.mesh = box
	wall.material_override = mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = 5.0
	wall.visible = false
	add_child(wall)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.1)
	light.light_energy = 0.0
	light.omni_range = width * 0.6
	light.position = Vector3(0, 4.0, -2.0)
	add_child(light)

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
	wall.visible = true
	Sfx.play("gate_open")
	GameState.notify.emit("Embers seal the way behind you.")
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.5, 0.6)
	tween.parallel().tween_property(light, "light_energy", 2.0, 0.6)


func open():

	if collision.disabled:
		return

	collision.set_deferred("disabled", true)
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.8)
	tween.tween_callback(func(): wall.visible = false)
