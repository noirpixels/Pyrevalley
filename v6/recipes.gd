extends RefCounted

# What Veyl can make, and where (crafting_panel.gd):
#   hand     anywhere: stone tools from branches and flint, leather
#   build    stations raised in front of Veyl (stations.gd): a furnace
#            from the Old Smithy's bellows, a forge from its anvil and tongs
#   Furnace  charcoal from logs, ingots from ore or scrap, Emberstone shards
#   Forge    bronze and iron gear (struck for quality), and work on gear
#            already owned: repair, temper, and setting a rare material in
# A recipe: {"title", "cost": {item: count}, and one of
#   "item": [name, count]   a material
#   "gear": [type, material]  a piece of gear (items.gd)
#   "station": kind         a station to build}
# "Fuel" in a cost is paid in Coal, then Charcoal.

const Items = preload("res://items.gd")

const FUELS = ["Coal", "Charcoal"]

const HAND = [
	{"title": "Stone Pickaxe", "gear": ["Pickaxe", "Stone"], "cost": {"Branch": 2, "Flint": 3}},
	{"title": "Stone Axe", "gear": ["Axe", "Stone"], "cost": {"Branch": 2, "Flint": 3}},
	{"title": "Stone Spear", "gear": ["Spear", "Stone"], "cost": {"Branch": 3, "Flint": 2}},
	{"title": "Leather", "item": ["Leather", 1], "cost": {"Wolf Hide": 1, "Flint": 1}},
	{"title": "Leather Jerkin", "gear": ["Armor", "Leather"], "cost": {"Leather": 4, "Moss Fiber": 1}},
]

const BUILD = [
	{"title": "Furnace", "station": "Furnace", "cost": {"Stone": 8, "Clay": 4, "Old Bellows": 1}},
	{"title": "Forge", "station": "Forge", "cost": {"Stone": 6, "Rusted Anvil": 1, "Old Tongs": 1}},
]

const FURNACE = [
	{"title": "Charcoal ×2", "item": ["Charcoal", 2], "cost": {"Log": 2}},
	{"title": "Bronze Ingot", "item": ["Bronze Ingot", 1], "cost": {"Copper Ore": 2, "Tin Ore": 1, "Fuel": 1}},
	{"title": "Iron Ingot", "item": ["Iron Ingot", 1], "cost": {"Iron Ore": 2, "Fuel": 2}},
	{"title": "Iron Ingot (from scrap)", "item": ["Iron Ingot", 1], "cost": {"Scrap Iron": 2, "Fuel": 1}},
	{"title": "Bronze Ingot (from scrap)", "item": ["Bronze Ingot", 1], "cost": {"Scrap Bronze": 2, "Fuel": 1}},
	{"title": "Emberstone Shard", "item": ["Emberstone Shard", 1], "cost": {"Emberstone": 1, "Fuel": 1}},
]

# Forge: each type in bronze and iron. Ingots of the metal, plus these.
const FORGED = {
	"Pickaxe": {"ingots": 2, "Log": 1},
	"Axe": {"ingots": 2, "Log": 1},
	"Sword": {"ingots": 3, "Log": 1},
	"Spear": {"ingots": 2, "Log": 2},
	"Warhammer": {"ingots": 4, "Log": 1},
	"Armor": {"ingots": 5, "Leather": 2},
}
const METALS = ["Bronze", "Iron"]

# Forge work on owned gear: what mends each material, and what a
# tempering (one level, up to Items.MAX_LEVEL) costs
const REPAIR_WITH = {"Stone": "Flint", "Rusted": "Scrap Iron", "Leather": "Leather", "Bronze": "Bronze Ingot", "Iron": "Iron Ingot"}
const TEMPER_INGOTS = 2
# Rare material count to set a magic into gear (items.gd MAGIC)
const MAGIC_COST = {"Emberbrand": 1, "Ashweight": 1, "Fangswift": 1, "Mosswoven": 2}


static func list(station: String) -> Array:

	match station:
		"hand":
			return HAND
		"build":
			return BUILD
		"Furnace":
			return FURNACE
		"Forge":
			var out = []
			for metal in METALS:
				for type in FORGED:
					var cost = {}
					for key in FORGED[type]:
						if key == "ingots":
							cost[metal + " Ingot"] = FORGED[type][key]
						else:
							cost[key] = FORGED[type][key]
					var title = Items.gear_name(Items.make(type, metal))
					out.append({"title": title, "gear": [type, metal], "cost": cost})
			return out
	return []


static func fuel() -> int:

	var total = 0
	for f in FUELS:
		total += GameState.count(f)
	return total


static func can_afford(cost: Dictionary) -> bool:

	for item_name in cost:
		var have = fuel() if item_name == "Fuel" else GameState.count(item_name)
		if have < cost[item_name]:
			return false
	return true


static func pay(cost: Dictionary):

	var plain = {}
	for item_name in cost:
		if item_name != "Fuel":
			plain[item_name] = cost[item_name]
	var owed = cost.get("Fuel", 0)
	for f in FUELS:
		var take = mini(owed, GameState.count(f))
		if take > 0:
			plain[f] = plain.get(f, 0) + take
			owed -= take
	GameState.spend(plain)


# "Branch 1/2 · Flint 3/3"
static func describe_cost(cost: Dictionary) -> String:

	var parts = []
	for item_name in cost:
		var have = fuel() if item_name == "Fuel" else GameState.count(item_name)
		var label = "Fuel (coal or charcoal)" if item_name == "Fuel" else item_name
		parts.append("%s %d/%d" % [label, have, cost[item_name]])
	return "  ·  ".join(parts)


static func repair_cost(gear: Dictionary) -> Dictionary:
	return {REPAIR_WITH.get(gear["material"], "Flint"): 1}


static func can_temper(gear: Dictionary) -> bool:
	return gear["material"] in METALS and gear["level"] < Items.MAX_LEVEL


static func temper_cost(gear: Dictionary) -> Dictionary:
	return {gear["material"] + " Ingot": TEMPER_INGOTS}


# Magics that can go into this gear (weapons and armour only)
static func magics_for(gear: Dictionary) -> Array:

	var kind = Items.slot(gear)
	if kind != "weapon" and kind != "armor":
		return []
	var out = []
	for magic in Items.MAGIC:
		if Items.MAGIC[magic][kind] != "" and gear["magic"] != magic:
			out.append(magic)
	return out


static func magic_cost(magic: String) -> Dictionary:
	return {Items.MAGIC[magic]["material"]: MAGIC_COST[magic]}
