extends Node3D

# Stations Veyl builds (recipes.gd BUILD): a furnace and a forge, raised in
# front of whoever built them. Walk up and interact to work at one
# (crafting_panel.gd). The builder pays first; the host places it (or turns
# it down and the builder gets the materials back), and everyone sees it
# stand. Built stations are saved with the world.
# Lives under Emberwood, in its local space.

const EmberWall = preload("res://ember_wall.gd")
const WorldGen = preload("res://world_gen.gd")
const Recipes = preload("res://recipes.gd")

const KINDS = ["Furnace", "Forge"]
# How far in front of Veyl a station goes up
const BUILD_DISTANCE = 8.0
const MAX_BUILD_REACH = 20.0
const SPACING = 7.0
const STONE = Color(0.3, 0.29, 0.3)
const IRON = Color(0.12, 0.11, 0.12)

# [kind, position]
var built: Array = []


class Station:
	extends StaticBody3D

	var kind: String

	func _init(station_kind: String):
		kind = station_kind

	func _ready():
		add_to_group("interactable")
		add_to_group("stations")
		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(4.0, 4.0, 4.0)
		shape.shape = box
		shape.position.y = 2.0
		add_child(shape)
		var label = Label3D.new()
		label.text = kind
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 36
		label.pixel_size = 0.03
		label.outline_size = 10
		label.modulate = Color(0.85, 0.78, 0.65)
		label.position.y = 7.5
		add_child(label)

	func prompt_text() -> String:
		return "[%s] Work at the %s" % [Pad.glyph("interact"), kind.to_lower()]

	func interact(_player):
		get_tree().call_group("game_ui", "open_crafting", kind)


func _ready():

	name = "Stations"
	add_to_group("net_objects")


# A spot in front of a Veyl, in Emberwood space
func spot_ahead(veyl: Node3D) -> Vector3:

	var at = get_parent().to_local(veyl.global_position + veyl.aim_dir * BUILD_DISTANCE)
	return Vector3(at.x, 0, at.z)


# Any player: pay, then ask the host to raise it
func build(kind: String, veyl: Node3D):

	var recipe = recipe_for(kind)
	if recipe.is_empty() or not Recipes.can_afford(recipe["cost"]):
		return
	Recipes.pay(recipe["cost"])
	NetSync.ask_host(self, ["build", kind, spot_ahead(veyl)])


static func recipe_for(kind: String) -> Dictionary:

	for recipe in Recipes.BUILD:
		if recipe["station"] == kind:
			return recipe
	return {}


# Where a station can't go, or ""
func problem(at: Vector3) -> String:

	var layout = WorldGen.current
	if not layout.inside(at, 6.0):
		return "Too close to the edge of the forest."
	if layout.on_site(at, 3.0):
		return "Not on the dig site."
	if layout.in_arena(at, 4.0):
		return "Not in the arena."
	for entry in built:
		if WorldGen.flat(entry[1] - at).length() < SPACING:
			return "Too close to another station."
	return ""


# args: ["build", kind, position (Emberwood space)]
func host_request(args: Array, sender: int):

	if args.size() < 3 or args[0] != "build" or not args[1] in KINDS or typeof(args[2]) != TYPE_VECTOR3:
		return
	var at: Vector3 = args[2]
	var veyl = NetSync.veyl_of(sender)
	if veyl == null or veyl.global_position.distance_to(get_parent().to_global(at)) > MAX_BUILD_REACH:
		NetSync.tell(sender, self, "refused", [args[1], "Too far away."])
		return
	var why = problem(at)
	if why != "":
		NetSync.tell(sender, self, "refused", [args[1], why])
		return
	NetSync.object_fx(self, "built", [args[1], at])


func fx_built(kind: String, at: Vector3):

	place(kind, at)
	if NetSync.near_me(get_parent().to_global(at)):
		Sfx.play("checkpoint", -4.0)


func place(kind: String, at: Vector3):

	built.append([kind, at])
	var station = Station.new(kind)
	station.position = at
	add_child(station)
	dress(station)


# The builder's materials come back
func fx_refused(kind: String, why: String):

	var recipe = recipe_for(kind)
	for item_name in recipe.get("cost", {}):
		GameState.add_item(item_name, recipe["cost"][item_name])
	GameState.notify.emit("Can't build the %s here. %s" % [kind.to_lower(), why])


func dress(station: Station):

	match station.kind:
		"Furnace":
			# A squat clay-and-stone stack with fire in its mouth
			block(station, Vector3(0, 1.8, 0), Vector3(4.0, 3.6, 4.0), STONE)
			block(station, Vector3(0, 4.3, 0), Vector3(2.6, 1.4, 2.6), STONE.darkened(0.15))
			block(station, Vector3(0, 5.6, 0), Vector3(1.2, 1.4, 1.2), STONE.darkened(0.3))
			var fire = EmberWall.new(1.8, 2.0, true)
			fire.position = Vector3(0, 0.6, 2.1)
			station.add_child(fire)
		"Forge":
			# The old anvil on a stone block, beside a small hearth
			block(station, Vector3(-0.6, 0.9, 0), Vector3(2.0, 1.8, 2.0), STONE)
			block(station, Vector3(-0.6, 2.2, 0), Vector3(2.4, 0.8, 1.0), IRON)
			block(station, Vector3(1.6, 0.6, 0), Vector3(1.6, 1.2, 2.6), STONE.darkened(0.2))
			var fire = EmberWall.new(1.2, 1.4, true)
			fire.position = Vector3(1.6, 1.2, 0)
			station.add_child(fire)


func block(parent: Node3D, at: Vector3, size: Vector3, color: Color):

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)


func net_snapshot():

	if built.is_empty():
		return null
	return built.map(func(entry): return [entry[0], entry[1].x, entry[1].z])


func apply_snapshot(data):

	if typeof(data) != TYPE_ARRAY:
		return
	for child in get_children():
		child.queue_free()
	built = []
	for entry in data:
		if entry.size() >= 3 and entry[0] in KINDS:
			place(entry[0], Vector3(entry[1], 0, entry[2]))
