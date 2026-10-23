extends TileMapLayer

const MAP_WIDTH = 20
const MAP_HEIGHT = 20

var rng = RandomNumberGenerator.new()


func _ready():
	rng.seed = 12345
	generate_map()


func generate_map():
	clear()

	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var tile = choose_tile()
			set_cell(Vector2i(x, y), 0, tile)


func choose_tile() -> Vector2i:
	var roll = rng.randi_range(1, 100)

	var row: int

	if roll <= 40:
		row = 2
	elif roll <= 50:
		row = 5
	elif roll <= 58:
		row = 1
	elif roll <= 68:
		row = 0
	elif roll <= 75:
		row = 4
	else:
		row = 3

	var column = rng.randi_range(0, 5)

	return Vector2i(column, row)
