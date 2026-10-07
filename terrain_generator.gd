extends Node3D

const MAP_WIDTH = 20
const MAP_HEIGHT = 20

const CHUNK_SIZE = 17.5

var rng = RandomNumberGenerator.new()


func _ready():
	rng.seed = 12345
	generate_terrain()


func generate_terrain():

	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):

			create_chunk(x, y)


func create_chunk(x: int, y: int):

	var chunk = CSGBox3D.new() 
	

	var plane = PlaneMesh.new()
	plane.size = Vector2(
		CHUNK_SIZE,
		CHUNK_SIZE
	)

	chunk.mesh = plane

	chunk.position = Vector3(
		x * CHUNK_SIZE,
		0,
		y * CHUNK_SIZE
	)

	add_child(chunk)
