extends Marker3D

# Place in the level and pick a creature from CodexData. It spawns once;
# creatures defeated in a saved game stay defeated.

const Enemy = preload("res://enemy.gd")
const Boss = preload("res://boss.gd")

@export var creature_name: String = "Mossling"


func _ready():

	GameState.ensure_loaded()

	var id = spawn_id()
	if id in GameState.defeated_spawners:
		return

	var creature = CodexData.get_creature(creature_name)
	var enemy = Boss.new() if creature.get("boss", false) else Enemy.new()
	enemy.setup(creature, id)
	enemy.position.y = enemy.height / 2.0 + 0.5
	add_child(enemy)


# Stable id from the node path, used by the save file
func spawn_id() -> String:
	return str(get_parent().name) + "/" + str(name)
