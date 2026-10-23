extends Node

# One run of Pyrevalley: the world seed and everything this player has
# found, learned and changed in it, saved as JSON. The world itself is
# rebuilt from the seed (world_gen.gd); only changes are stored, such as
# ground dug away (dig_log) or a treasure taken (taken).

signal notify(text: String)
signal inventory_changed
signal abilities_changed
signal map_changed

const SAVE_PATH = "user://pyrevalley_v7_save.json"
# A guest in someone else's world keeps its own file, so joining a friend
# never overwrites your own run
const GUEST_SAVE_PATH = "user://pyrevalley_v7_guest.json"

const ITEM_NAMES = {
	"Branch": "A dry branch. Good for a haft or a handle.",
	"Flint": "A grey stone that breaks to a glassy edge.",
	"Copper Ore": "Green-streaked malachite. Smelted, it gives soft red copper.",
	"Tin Ore": "Dark, heavy cassiterite. A little tin turns copper into bronze.",
	"Bronze Ingot": "Copper and tin smelted together. Tougher than either.",
	"Moss Fiber": "Soft fibres that glow faintly in the dark.",
	"Ember Fang": "Still warm. Taken from an Ember Wolf.",
	"Ash Core": "A dense lump of ash that hums when held.",
}

var seed_value: int = 0
var abilities = {}
var inventory = {}
# Equipped gear by slot: {"type", "material"}; no weapon means fists
var gear = {"weapon": {"type": "Sword", "material": "Rusted"}, "pickaxe": null, "charm": null}
# Every piece of gear Veyl has (crafting_panel.gd picks what's in hand)
var owned = []
var max_health: float = 100.0
var health: float = -1.0
# The shrine Veyl last rested at (grid cell), where vae wakes after dying
var shrine_cell = null
# Grid cells walked into, and the ones inked onto the map by resting at a
# shrine since (map_overlay.gd draws the rest in pencil)
var visited = {}
var inked = {}
# Per room cell: ground dug away, as [x, y, radius, tier] in room pixels
var dig_log = {}
# One-time things picked up or opened, by id
var taken = {}
var boss_defeated: bool = false
# Creatures stay dead until Veyl rests or dies (killed = ids)
var killed = {}
var boss_fight: bool = false
var save_path = SAVE_PATH


func new_game(world_seed: int):

	seed_value = world_seed
	abilities = {}
	inventory = {}
	owned = [{"type": "Sword", "material": "Rusted"}]
	gear = {"weapon": owned[0], "pickaxe": null, "charm": null}
	max_health = 100.0
	health = -1.0
	shrine_cell = null
	visited = {}
	inked = {}
	dig_log = {}
	taken = {}
	killed = {}
	boss_defeated = false
	boss_fight = false


# ============================================================
# INVENTORY
# ============================================================

func count(item: String) -> int:
	return inventory.get(item, 0)


func add_item(item: String, amount: int = 1):

	inventory[item] = count(item) + amount
	inventory_changed.emit()


func can_afford(cost: Dictionary) -> bool:

	for item in cost:
		if count(item) < cost[item]:
			return false
	return true


func spend(cost: Dictionary):

	for item in cost:
		inventory[item] = count(item) - cost[item]
		if inventory[item] <= 0:
			inventory.erase(item)
	inventory_changed.emit()


func has_ability(ability: String) -> bool:
	return abilities.get(ability, false)


func learn(ability: String):

	abilities[ability] = true
	abilities_changed.emit()


func pickaxe_tier() -> int:

	var pick = gear.get("pickaxe")
	if pick == null:
		return 0
	return {"Stone": 1, "Bronze": 2}.get(pick["material"], 1)


# ============================================================
# MAP
# ============================================================

static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func visit(cell: Vector2i):

	var key = cell_key(cell)
	if visited.has(key):
		return
	visited[key] = true
	map_changed.emit()


# Resting at a shrine sets everything walked so far in ink
func ink_map():

	for key in visited:
		inked[key] = true
	map_changed.emit()


func log_dig(cell: Vector2i, at: Vector2, radius: float, tier: int):

	var key = cell_key(cell)
	if not dig_log.has(key):
		dig_log[key] = []
	dig_log[key].append([roundi(at.x), roundi(at.y), radius, tier])


# ============================================================
# SAVE / LOAD
# ============================================================

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(player: Node = null):

	if player:
		health = player.health
	var data = {
		"seed": seed_value,
		"abilities": abilities,
		"inventory": inventory,
		"gear": gear,
		"owned": owned,
		"max_health": max_health,
		"health": health,
		"shrine_cell": [shrine_cell.x, shrine_cell.y] if shrine_cell != null else null,
		"visited": visited,
		"inked": inked,
		"dig_log": dig_log,
		"taken": taken,
		"boss_defeated": boss_defeated,
	}
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func load_game() -> bool:

	if not FileAccess.file_exists(save_path):
		return false
	var file = FileAccess.open(save_path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text()) if file else null
	if not data is Dictionary:
		return false
	new_game(int(data.get("seed", 0)))
	abilities = data.get("abilities", {})
	inventory = {}
	for item in data.get("inventory", {}):
		inventory[item] = int(data["inventory"][item])
	owned = data.get("owned", owned)
	# Equipped gear points at the owned pieces, so the pack can tell them apart
	var saved_gear = data.get("gear", {})
	for slot in gear:
		gear[slot] = null
		var g = saved_gear.get(slot)
		for o in owned:
			if g is Dictionary and o["type"] == g["type"] and o["material"] == g["material"]:
				gear[slot] = o
	max_health = data.get("max_health", 100.0)
	health = data.get("health", -1.0)
	var shrine = data.get("shrine_cell")
	shrine_cell = Vector2i(int(shrine[0]), int(shrine[1])) if shrine is Array else null
	visited = data.get("visited", {})
	inked = data.get("inked", {})
	dig_log = data.get("dig_log", {})
	taken = data.get("taken", {})
	boss_defeated = data.get("boss_defeated", false)
	return true
