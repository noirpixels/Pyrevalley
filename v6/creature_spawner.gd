extends Marker3D

# Place in the level and pick a creature from CodexData. A defeated
# creature comes back after RESPAWN_TIME, once nobody is standing close
# enough to watch it appear; the Ashbound stays down for good.
# In a multiplayer session only the host spawns real creatures; guests get
# a copy (a "puppet") that the host moves (net_sync.gd).

const Enemy = preload("res://enemy.gd")
const Boss = preload("res://boss.gd")

const RESPAWN_TIME = 90.0
# No respawn while any Veyl is this close
const RESPAWN_CLEARANCE = 30.0
# Extra creature health per extra player in the session
const HEALTH_PER_PLAYER = 0.4

@export var creature_name: String = "Mossling"

var creature: Node3D = null
var respawn_left: float = 0.0


func _ready():

	add_to_group("spawners")
	GameState.ensure_loaded()

	if Net.is_host() and not (is_boss() and GameState.boss_defeated):
		spawn()


func is_boss() -> bool:
	return CodexData.get_creature(creature_name).get("boss", false)


func make_creature() -> Node3D:

	var data = CodexData.get_creature(creature_name)
	var enemy = Boss.new() if data.get("boss", false) else Enemy.new()
	enemy.setup(data, spawn_id())
	enemy.position.y = enemy.height / 2.0 + 0.5
	enemy.died.connect(_on_creature_died)
	return enemy


func spawn():

	var enemy = make_creature()
	enemy.scale_health(1.0 + HEALTH_PER_PLAYER * (Net.player_count() - 1))
	add_child(enemy)
	creature = enemy
	NetSync.creature_spawned(self, enemy)


# Guest: the host's creature, shown here and moved by the host
func spawn_puppet(max_health: float, health: float, at: Vector3):

	if creature and is_instance_valid(creature):
		creature.queue_free()
	var enemy = make_creature()
	enemy.puppet = true
	enemy.max_health = max_health
	enemy.health = health
	add_child(enemy)
	if at != Vector3.INF:
		enemy.global_position = at
	creature = enemy


func _on_creature_died(_enemy):

	creature = null
	if not is_boss():
		respawn_left = RESPAWN_TIME


func _process(delta):

	if creature != null or respawn_left <= 0.0 or not Net.is_host():
		return
	respawn_left -= delta
	if respawn_left > 0.0:
		return
	for veyl in NetSync.all_players():
		if veyl.global_position.distance_to(global_position) < RESPAWN_CLEARANCE:
			# Try again shortly
			respawn_left = 2.0
			return
	spawn()


# Stable id from the node path
func spawn_id() -> String:
	return str(get_parent().name) + "/" + str(name)
