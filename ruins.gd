extends Node3D

# What's left of the people who worked metal in Emberwood before: the Old
# Smithy, a roofless ruin west of Rowan's fire, and a heap of broken blades
# in the Deep Forest. Their salvage (an anvil, tongs, bellows, scrap) is
# what Veyl needs to build a furnace and a forge. Each piece lies there
# once per world (placed pickups, so it stays taken in the save).
# Lives under Emberwood, in its local space.

const ItemPickup = preload("res://item_pickup.gd")

const SMITHY = Vector3(-32, 0, 2)
const BLADES = Vector3(-24, 0, -84)
const STONE = Color(0.3, 0.29, 0.3)
const CHAR = Color(0.09, 0.07, 0.06)


func _ready():

	name = "Ruins"
	build_smithy()
	build_blades()


func build_smithy():

	var smithy = Node3D.new()
	smithy.position = SMITHY
	add_child(smithy)

	# Broken walls on three sides, open toward the path
	wall(smithy, Vector3(0, 0, -6), Vector3(12, 4.5, 1.2), STONE)
	wall(smithy, Vector3(-6, 0, -1), Vector3(1.2, 3.0, 9.0), STONE)
	wall(smithy, Vector3(6, 0, -3.5), Vector3(1.2, 2.0, 4.0), STONE)
	wall(smithy, Vector3(4.5, 0, 3.5), Vector3(3.0, 1.2, 1.2), STONE)
	# The old hearth, cold, and fallen roof beams
	wall(smithy, Vector3(-3.5, 0, -4), Vector3(3.5, 2.2, 3.0), STONE.darkened(0.2))
	beam(smithy, Vector3(1, 0.6, -1), Vector3(0.7, 0.7, 9.0), 0.5)
	beam(smithy, Vector3(-1.5, 0.4, 1.5), Vector3(0.6, 0.6, 7.0), -0.9)

	salvage(smithy, "Rusted Anvil", "SmithyAnvil", Vector3(0.5, 0, -2.5))
	salvage(smithy, "Old Tongs", "SmithyTongs", Vector3(-3.0, 0, -1.0))
	salvage(smithy, "Old Bellows", "SmithyBellows", Vector3(-4.2, 0, 1.5))
	salvage(smithy, "Scrap Iron", "SmithyScrap1", Vector3(3.0, 0, 1.0))
	salvage(smithy, "Scrap Iron", "SmithyScrap2", Vector3(2.0, 0, -4.5))
	title(smithy, "The Old Smithy")


func build_blades():

	var heap = Node3D.new()
	heap.position = BLADES
	add_child(heap)
	for i in 5:
		var a = i * 1.3
		beam(heap, Vector3(cos(a) * 1.5, 0.2, sin(a) * 1.5), Vector3(0.25, 0.1, 2.6), a).get_child(0).material_override.albedo_color = Color(0.4, 0.36, 0.34)
	salvage(heap, "Scrap Iron", "BladeScrap1", Vector3(1.5, 0, 0.5))
	salvage(heap, "Scrap Iron", "BladeScrap2", Vector3(-1.2, 0, -1.0))
	title(heap, "Broken Blades")


func wall(parent: Node3D, at: Vector3, size: Vector3, color: Color):

	var body = StaticBody3D.new()
	body.position = at + Vector3(0, size.y / 2.0, 0)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	parent.add_child(body)


func beam(parent: Node3D, at: Vector3, size: Vector3, turn: float) -> Node3D:

	var node = Node3D.new()
	node.position = at
	node.rotation = Vector3(0.12, turn, 0.05)
	var mesh = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = CHAR
	mesh.material_override = mat
	node.add_child(mesh)
	parent.add_child(node)
	return node


func salvage(parent: Node3D, item_name: String, id: String, at: Vector3):

	var piece = ItemPickup.new()
	piece.item_name = item_name
	piece.pickup_id = id
	piece.pickup_kind = "forage"
	piece.position = at
	parent.add_child(piece)


func title(parent: Node3D, text: String):

	var label = Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.pixel_size = 0.03
	label.outline_size = 10
	label.modulate = Color(0.85, 0.78, 0.65)
	label.position = Vector3(0, 8, 0)
	parent.add_child(label)
