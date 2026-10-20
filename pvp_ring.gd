extends Node3D

# The Proving Ring: a circle of ember walls off to the east of the Starting
# Area where players can fight each other. PvP only works while both
# players stand inside it (player_3d.gd resolve_swing); everywhere else in
# Emberwood, swords pass through friends. A portal by the start leads in,
# and one inside leads back. Only built in a multiplayer session.
# Lives under Emberwood, so positions are in its local space.

const EmberWall = preload("res://ember_wall.gd")

const CENTRE = Vector3(85, 0, 95)
const RADIUS = 18.0
const SEGMENTS = 12
# Portal by the Starting Area, inside the level bounds
const OUTER_PORTAL = Vector3(14, 0, 110)


class Portal:
	extends Node3D

	var label_text: String
	var prompt: String
	var destination: Callable

	func _init(text: String, prompt_line: String, to: Callable):
		label_text = text
		prompt = prompt_line
		destination = to

	func _ready():
		add_to_group("interactable")
		var fire = EmberWall.new(2.4, 3.2, true)
		add_child(fire)
		var label = Label3D.new()
		label.text = label_text
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 36
		label.pixel_size = 0.03
		label.outline_size = 10
		label.modulate = Color(1.0, 0.75, 0.5)
		label.position.y = 6.5
		add_child(label)

	func prompt_text() -> String:
		return "[%s] %s" % [Pad.glyph("interact"), prompt]

	func interact(player):
		player.global_position = destination.call()
		player.velocity = Vector3.ZERO
		Sfx.play("checkpoint", -6.0)


func _ready():

	add_to_group("pvp_ring")
	position = CENTRE

	var chord = 2.0 * RADIUS * sin(PI / SEGMENTS)
	for i in SEGMENTS:
		var angle = TAU * (i + 0.5) / SEGMENTS
		var segment = StaticBody3D.new()
		segment.position = Vector3(cos(angle), 0, sin(angle)) * RADIUS * cos(PI / SEGMENTS)
		# The wall's length runs along its local X, tangent to the circle
		segment.rotation.y = -angle + PI / 2.0
		var shape = BoxShape3D.new()
		shape.size = Vector3(chord + 0.6, 14.0, 2.0)
		var collision = CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 7.0
		segment.add_child(collision)
		segment.add_child(EmberWall.new(chord, 5.0))
		add_child(segment)

	var title = Label3D.new()
	title.text = "THE PROVING RING"
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.font_size = 56
	title.pixel_size = 0.04
	title.outline_size = 14
	title.modulate = Color(1.0, 0.7, 0.4)
	title.position = Vector3(0, 10, 0)
	add_child(title)

	var inner = Portal.new("Back to the Emberwood", "Leave the Proving Ring", outer_portal_point)
	inner.position = Vector3(0, 0, RADIUS - 5.0)
	add_child(inner)

	var outer = Portal.new("The Proving Ring\nduels between players", "Enter the Proving Ring", spawn_point)
	outer.position = OUTER_PORTAL - CENTRE
	add_child(outer)


# Is a world position inside the ring? slack widens it (the host's check
# allows for lag)
func contains(world_pos: Vector3, slack: float = 0.0) -> bool:

	var local = to_local(world_pos)
	return Vector2(local.x, local.z).length() <= RADIUS + slack


# Just inside the ring, somewhere along its south edge
func spawn_point() -> Vector3:

	var angle = PI / 2.0 + randf_range(-0.6, 0.6)
	return to_global(Vector3(cos(angle), 0, sin(angle)) * (RADIUS - 6.0) + Vector3(0, 6.0, 0))


func outer_portal_point() -> Vector3:

	return to_global(OUTER_PORTAL - CENTRE + Vector3(-4.0, 6.0, 0))
