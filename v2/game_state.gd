extends Node

# Prototype progression: inventory, quest, checkpoints and the JSON save.
# Also acts as a small event bus so world objects and UI stay decoupled.

signal inventory_changed
signal quest_changed
signal notify(text)
signal boss_engaged(boss)
signal boss_disengaged
signal boss_defeated_signal

const SAVE_PATH = "user://embervale_save.json"
const QUEST_GOAL = 3

const ITEMS = {
	"Rustblade": {"kind": "weapon", "attack": 12, "range": 6.0, "cooldown": 0.4, "description": "A pitted old sword. It was in your hand when you woke."},
	"Ember Fang": {"kind": "resource", "description": "Still warm. Taken from an Ember Wolf."},
	"Moss Fiber": {"kind": "resource", "description": "Soft fibres that glow faintly in the dark."},
	"Ash Core": {"kind": "resource", "description": "A dense lump of ash that hums when held."},
}

# Quest states
const QUEST_NOT_STARTED = "not_started"
const QUEST_ACTIVE = "active"
const QUEST_RETURN = "return_to_rowan"
const QUEST_COMPLETE = "complete"

var loaded = false

var inventory = {}
var equipped_weapon = "Rustblade"
var quest_state = QUEST_NOT_STARTED
var quest_progress = 0
var defeated_spawners = []
var collected_pickups = []
var checkpoint_position = null
var player_position = null
var player_health = -1.0
var boss_defeated = false
# True while the Ashbound is fighting (shrines won't heal)
var boss_fight = false


# ============================================================
# LIFECYCLE
# ============================================================

# Called by anything that needs progression on scene start
func ensure_loaded():
	if loaded:
		return
	# A finished prototype starts fresh from the menu
	if not load_game() or boss_defeated:
		new_game()
	loaded = true


func new_game():
	inventory = {"Rustblade": 1}
	equipped_weapon = "Rustblade"
	quest_state = QUEST_NOT_STARTED
	quest_progress = 0
	defeated_spawners = []
	collected_pickups = []
	checkpoint_position = null
	player_position = null
	player_health = -1.0
	boss_defeated = false
	# The codex is kept across runs; load_game() fills it from the save
	loaded = true


# Wipes the save and starts over (Play Again / Restart)
func restart():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()
	# Keep what the codex has learned
	save_game()


# ============================================================
# INVENTORY
# ============================================================

func add_item(item_name: String, amount: int = 1):
	inventory[item_name] = inventory.get(item_name, 0) + amount
	inventory_changed.emit()


func weapon() -> Dictionary:
	return ITEMS[equipped_weapon]


# ============================================================
# QUEST: CLEAR THE FOREST
# ============================================================

func accept_quest():
	quest_state = QUEST_ACTIVE
	quest_progress = 0
	quest_changed.emit()


func complete_quest():
	quest_state = QUEST_COMPLETE
	quest_changed.emit()


func quest_accepted() -> bool:
	return quest_state != QUEST_NOT_STARTED


func record_creature_defeat(spawner_id: String, creature_name: String):
	if spawner_id != "":
		defeated_spawners.append(spawner_id)

	if CodexData.record_defeat(creature_name):
		notify.emit("Codex discovered: " + creature_name)

	if quest_state == QUEST_ACTIVE:
		quest_progress += 1
		if quest_progress >= QUEST_GOAL:
			quest_state = QUEST_RETURN
			notify.emit("The forest is clearer. Return to Rowan.")
		quest_changed.emit()


func defeat_boss():
	boss_defeated = true
	boss_defeated_signal.emit()


# ============================================================
# SAVE / LOAD (JSON)
# ============================================================

func save_game(player: Node3D = null):
	if player:
		player_position = player.global_position
		player_health = player.health

	var data = {
		"player_position": vec_to_array(player_position),
		"player_health": player_health,
		"checkpoint_position": vec_to_array(checkpoint_position),
		"inventory": inventory,
		"equipped_weapon": equipped_weapon,
		"quest_state": quest_state,
		"quest_progress": quest_progress,
		"defeated_spawners": defeated_spawners,
		"collected_pickups": collected_pickups,
		"codex_discovered": CodexData.discovered,
		"boss_defeated": boss_defeated,
	}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("GameState: save file unreadable, starting fresh")
		return false

	new_game()
	player_position = array_to_vec(data.get("player_position"))
	player_health = data.get("player_health", -1.0)
	checkpoint_position = array_to_vec(data.get("checkpoint_position"))
	equipped_weapon = data.get("equipped_weapon", "Rustblade")
	quest_state = data.get("quest_state", QUEST_NOT_STARTED)
	quest_progress = int(data.get("quest_progress", 0))
	defeated_spawners = data.get("defeated_spawners", [])
	collected_pickups = data.get("collected_pickups", [])
	boss_defeated = data.get("boss_defeated", false)

	# JSON numbers come back as floats
	inventory = {}
	for key in data.get("inventory", {}):
		inventory[key] = int(data["inventory"][key])
	CodexData.discovered = {}
	for key in data.get("codex_discovered", {}):
		CodexData.discovered[key] = int(data["codex_discovered"][key])

	return true


func vec_to_array(v):
	return null if v == null else [v.x, v.y, v.z]


func array_to_vec(a):
	return null if a == null else Vector3(a[0], a[1], a[2])
