extends Node

# Prototype progression: inventory, quest, checkpoints and the JSON save.
# Also acts as a small event bus so world objects and UI stay decoupled.
# In a multiplayer session the world's progress (quest, boss, placed
# pickups) belongs to the host, who sends it to guests (apply_world);
# inventory, codex, Max Combo and shrines stay each player's own.

signal inventory_changed
signal quest_changed
signal notify(text)
signal boss_engaged(boss)
signal boss_disengaged
signal boss_defeated_signal
signal max_combo_changed
# Gear picked up, equipped, worn down or broken
signal gear_changed

const SAVE_PATH = "user://embervale_save.json"
# A guest's own progress in other people's worlds, kept apart from their solo save
const GUEST_SAVE_PATH = "user://embervale_guest.json"
const QUEST_GOAL = 3

# The Codex's card for the sword Veyl wakes with. Materials and all other
# gear are described in items.gd.
const ITEMS = {
	"Rustblade": {"kind": "weapon", "attack": 12, "range": 6.0, "cooldown": 0.4, "description": "A pitted old sword. It was in your hand when you woke."},
}

# Max Combo: how many hits Veyl can chain (see combo_tracker.gd). Rises by
# one for Rowan's quest and for the first defeat of each kind of creature.
const BASE_MAX_COMBO = 3
const MAX_COMBO_LIMIT = 7

# Quest states
const QUEST_NOT_STARTED = "not_started"
const QUEST_ACTIVE = "active"
const QUEST_RETURN = "return_to_rowan"
const QUEST_COMPLETE = "complete"

var loaded = false
var save_path = SAVE_PATH

const Items = preload("res://items.gd")
const GEAR_SLOTS = ["weapon", "armor", "pickaxe", "axe"]

# Stackable materials: name -> count
var inventory = {}
# Gear owned (items.gd), and what's equipped: slot -> gear id (-1 = none)
var gear = []
var equipped = {}
var next_gear_id = 1
# Name of what Veyl fights with ("Fists" with nothing equipped)
var equipped_weapon = "Rustblade"
var quest_state = QUEST_NOT_STARTED
var quest_progress = 0
var collected_pickups = []
var checkpoint_position = null
var player_position = null
var player_health = -1.0
var boss_defeated = false
var max_combo = BASE_MAX_COMBO
# Creatures whose first defeat this run already raised Max Combo
var combo_trophies = []
# True while the Ashbound is fighting (shrines won't heal)
var boss_fight = false
# The host's world objects as last saved (net_sync.gd applies them):
# dug hollows, felled trees, built stations, the blood moon's clock
var saved_objects = {}
# Which forest this is (world_gen.gd); a guest gets the host's
var world_seed = 1


# ============================================================
# LIFECYCLE
# ============================================================

# Called by anything that needs progression on scene start
func ensure_loaded():
	if loaded:
		return
	# A forest with the Ashbound beaten carries on; Play Again starts a new one
	if not load_game():
		new_game()
	loaded = true


func new_game():
	inventory = {}
	gear = []
	equipped = {}
	for slot in GEAR_SLOTS:
		equipped[slot] = -1
	next_gear_id = 1
	equip(add_gear(Items.rustblade()))
	quest_state = QUEST_NOT_STARTED
	quest_progress = 0
	collected_pickups = []
	checkpoint_position = null
	player_position = null
	player_health = -1.0
	boss_defeated = false
	max_combo = BASE_MAX_COMBO
	combo_trophies = []
	saved_objects = {}
	# Every new game is a new forest
	world_seed = randi_range(1, 999999)
	# The codex is kept across runs; load_game() fills it from the save
	loaded = true


# Which save file to use from here on (net.gd switches for guests)
func use_save(path: String):
	save_path = path
	loaded = false


# Wipes the save and starts over (Play Again / Restart)
func restart():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	new_game()
	# Keep what the codex has learned
	save_game()


# ============================================================
# INVENTORY
# ============================================================

func add_item(item_name: String, amount: int = 1):
	inventory[item_name] = inventory.get(item_name, 0) + amount
	inventory_changed.emit()


func count(item_name: String) -> int:
	return inventory.get(item_name, 0)


# cost: {item name: amount}
func can_afford(cost: Dictionary) -> bool:
	for item_name in cost:
		if count(item_name) < cost[item_name]:
			return false
	return true


func spend(cost: Dictionary):
	for item_name in cost:
		inventory[item_name] = count(item_name) - cost[item_name]
		if inventory[item_name] <= 0:
			inventory.erase(item_name)
	inventory_changed.emit()


# The equipped weapon's numbers, or Veyl's fists with none
func weapon() -> Dictionary:
	var w = equipped_gear("weapon")
	return Items.weapon_stats(w) if not w.is_empty() else Items.FISTS


# ============================================================
# GEAR
# ============================================================

func add_gear(item: Dictionary) -> int:
	item["id"] = next_gear_id
	next_gear_id += 1
	gear.append(item)
	gear_changed.emit()
	return item["id"]


func find_gear(id: int) -> Dictionary:
	for item in gear:
		if item["id"] == id:
			return item
	return {}


func equipped_gear(slot: String) -> Dictionary:
	return find_gear(equipped.get(slot, -1))


func equip(id: int):
	var item = find_gear(id)
	if item.is_empty():
		return
	equipped[Items.slot(item)] = id
	update_weapon_name()
	gear_changed.emit()


func unequip(slot: String):
	equipped[slot] = -1
	update_weapon_name()
	gear_changed.emit()


func update_weapon_name():
	var w = equipped_gear("weapon")
	equipped_weapon = Items.gear_name(w) if not w.is_empty() else "Fists"


# Use wears gear down; at nothing it breaks, leaving scrap if it was metal
func wear(slot: String, amount: float = 1.0):
	var item = equipped_gear(slot)
	if item.is_empty():
		return
	item["durability"] -= amount
	if item["durability"] > 0.0:
		gear_changed.emit()
		return
	var item_name = Items.gear_name(item)
	gear.erase(item)
	equipped[slot] = -1
	update_weapon_name()
	var scrap = Items.MATERIALS[item["material"]]["scrap"]
	if scrap != "":
		add_item(scrap)
	notify.emit("Your %s breaks!" % item_name + ("  ·  +1 %s" % scrap if scrap != "" else ""))
	Sfx.play("hit_heavy", -2.0, 0.6)
	gear_changed.emit()


# Newly made gear goes straight into an empty slot
func give_gear(item: Dictionary):
	var id = add_gear(item)
	if equipped.get(Items.slot(item), -1) == -1:
		equip(id)


# Forge work (crafting_panel.gd): mend to full, temper a level, set a magic
func repair(id: int):
	var item = find_gear(id)
	item["durability"] = Items.max_durability(item)
	gear_changed.emit()


func temper(id: int):
	var item = find_gear(id)
	var worn = item["durability"] / Items.max_durability(item)
	item["level"] = mini(item["level"] + 1, Items.MAX_LEVEL)
	item["durability"] = Items.max_durability(item) * worn
	update_weapon_name()
	gear_changed.emit()


func set_magic(id: int, magic: String):
	find_gear(id)["magic"] = magic
	update_weapon_name()
	gear_changed.emit()


# ============================================================
# QUEST: CLEAR THE FOREST
# ============================================================

# Guests ask the host, whose answer comes back through apply_world
func accept_quest():
	if not Net.is_host():
		request_quest.rpc_id(1, QUEST_ACTIVE)
		return
	if quest_state != QUEST_NOT_STARTED:
		return
	quest_state = QUEST_ACTIVE
	quest_progress = 0
	quest_changed.emit()
	push_world()


func complete_quest():
	if not Net.is_host():
		request_quest.rpc_id(1, QUEST_COMPLETE)
		return
	if quest_state != QUEST_RETURN:
		return
	quest_state = QUEST_COMPLETE
	quest_changed.emit()
	raise_max_combo("Rowan's lesson")
	push_world()


@rpc("any_peer", "call_remote", "reliable")
func request_quest(state: String):
	if not Net.is_host():
		return
	match state:
		QUEST_ACTIVE:
			accept_quest()
		QUEST_COMPLETE:
			complete_quest()


func raise_max_combo(reason: String):
	if max_combo >= MAX_COMBO_LIMIT:
		return
	max_combo += 1
	notify.emit("%s  ·  Max Combo %d" % [reason, max_combo])
	max_combo_changed.emit()


func quest_accepted() -> bool:
	return quest_state != QUEST_NOT_STARTED


# Host: a creature fell. Everyone in the session shares the credit.
func record_creature_defeat(creature_name: String):
	Net.everyone(self, "credit_defeat", [creature_name])

	if quest_state == QUEST_ACTIVE:
		quest_progress += 1
		if quest_progress >= QUEST_GOAL:
			quest_state = QUEST_RETURN
			NetSync.notify_all("The forest is clearer. Return to Rowan.")
		quest_changed.emit()
		push_world()


# Each player's own codex entry and Max Combo trophy
@rpc("authority", "call_remote", "reliable")
func credit_defeat(creature_name: String):
	if CodexData.record_defeat(creature_name):
		notify.emit("Codex discovered: " + creature_name)

	if not creature_name in combo_trophies:
		combo_trophies.append(creature_name)
		raise_max_combo("First " + creature_name + " felled")


func defeat_boss():
	boss_defeated = true
	boss_defeated_signal.emit()
	push_world()


# ============================================================
# SHARED WORLD (multiplayer)
# ============================================================

func world_data() -> Dictionary:
	return {
		"quest_state": quest_state,
		"quest_progress": quest_progress,
		"boss_defeated": boss_defeated,
		"collected_pickups": collected_pickups,
	}


# Host: send the world's progress to every guest
func push_world():
	if Net.online and Net.is_host():
		apply_world.rpc(world_data())


@rpc("authority", "call_remote", "reliable")
func apply_world(data: Dictionary):
	var was_complete = quest_state == QUEST_COMPLETE
	quest_state = data["quest_state"]
	quest_progress = data["quest_progress"]
	collected_pickups = data["collected_pickups"]
	quest_changed.emit()
	# Rowan's lesson reaches everyone in the party
	if quest_state == QUEST_COMPLETE and not was_complete:
		raise_max_combo("Rowan's lesson")
	if data["boss_defeated"] and not boss_defeated:
		boss_defeated = true
		boss_defeated_signal.emit()


# A guest arrives in someone else's world: the gates start closed and the
# host's progress (apply_world) opens what it should
func reset_world():
	quest_state = QUEST_NOT_STARTED
	quest_progress = 0
	collected_pickups = []
	boss_defeated = false
	boss_fight = false
	checkpoint_position = null
	player_position = null
	saved_objects = {}


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
		"gear": gear,
		"equipped": equipped,
		"next_gear_id": next_gear_id,
		"quest_state": quest_state,
		"quest_progress": quest_progress,
		"collected_pickups": collected_pickups,
		"codex_discovered": CodexData.discovered,
		"boss_defeated": boss_defeated,
		"max_combo": max_combo,
		"combo_trophies": combo_trophies,
		"world_seed": world_seed,
	}
	# Only the world's owner saves it
	if Net.is_host() and NetSync.world:
		data["world_objects"] = NetSync.object_snapshots()

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false

	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("GameState: save file unreadable, starting fresh")
		return false

	new_game()
	player_position = array_to_vec(data.get("player_position"))
	player_health = data.get("player_health", -1.0)
	checkpoint_position = array_to_vec(data.get("checkpoint_position"))
	quest_state = data.get("quest_state", QUEST_NOT_STARTED)
	quest_progress = int(data.get("quest_progress", 0))
	collected_pickups = data.get("collected_pickups", [])
	boss_defeated = data.get("boss_defeated", false)
	max_combo = clampi(int(data.get("max_combo", BASE_MAX_COMBO)), BASE_MAX_COMBO, MAX_COMBO_LIMIT)
	combo_trophies = data.get("combo_trophies", [])
	saved_objects = data.get("world_objects", {})
	if data.has("world_seed"):
		world_seed = int(data["world_seed"])
	else:
		# Saved before the forest was generated: keep what Veyl carries and
		# knows, but wake vem in a new forest (new_game picked its seed)
		player_position = null
		checkpoint_position = null
		saved_objects = {}

	# JSON numbers come back as floats
	inventory = {}
	for key in data.get("inventory", {}):
		# Older saves kept the Rustblade here; it's gear now
		if key != "Rustblade":
			inventory[key] = int(data["inventory"][key])
	# Saves from before gear start with just the Rustblade (new_game above)
	if data.has("gear"):
		gear = []
		for item in data["gear"]:
			item["id"] = int(item["id"])
			item["quality"] = int(item["quality"])
			item["level"] = int(item["level"])
			gear.append(item)
		next_gear_id = int(data.get("next_gear_id", gear.size() + 1))
		for slot in GEAR_SLOTS:
			equipped[slot] = int(data.get("equipped", {}).get(slot, -1))
		update_weapon_name()
	CodexData.discovered = {}
	for key in data.get("codex_discovered", {}):
		CodexData.discovered[key] = int(data["codex_discovered"][key])

	return true


func vec_to_array(v):
	return null if v == null else [v.x, v.y, v.z]


func array_to_vec(a):
	return null if a == null else Vector3(a[0], a[1], a[2])
