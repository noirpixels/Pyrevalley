extends RefCounted

# Everything Veyl can carry: stackable materials, and gear (weapons, tools,
# armour), which are single items with their own material, quality,
# upgrade level, magic and wear. GameState holds what a player owns; this
# says what each thing is and works out a piece of gear's numbers.
#   Gear: {"id", "type", "material", "quality", "level", "magic", "durability", "name"?}

# ============================================================
# MATERIALS (stack in the inventory)
# ============================================================

const RESOURCES = {
	# Foraged, chopped and mined
	"Branch": "A dry branch off the forest floor. Good for a haft or a handle.",
	"Flint": "A grey stone that breaks to a glassy edge. Knapped, it cuts.",
	"Log": "A length of pine trunk, still sticky with sap.",
	"Stone": "Rough rock broken from the earth. Heavy, and it holds heat.",
	"Clay": "Wet, heavy clay. Fired, it holds a furnace's heat for hours.",
	"Coal": "Black seam-stone from between the limestone beds. It burns long and hot.",
	"Copper Ore": "Green-streaked malachite. Smelted, it gives soft red copper.",
	"Tin Ore": "Dark, heavy cassiterite. A little tin turns copper into bronze.",
	"Iron Ore": "Rust-red hematite. It needs a hot furnace and patience.",
	"Emberstone": "Black basalt shot through with veins that never cool. Nobody knows what keeps them burning.",
	# Made at stations
	"Charcoal": "Wood burned without air: light, black, and far hotter than a log.",
	"Bronze Ingot": "Copper and tin smelted together. Tougher than either.",
	"Iron Ingot": "A bloom of iron hammered clean of slag.",
	"Emberstone Shard": "A refined sliver of Emberstone. It burns to the touch, and so will anything it's set into.",
	"Leather": "Wolf hide scraped, cured and oiled.",
	# From creatures
	"Wolf Hide": "A rough hide, still smelling of smoke. Cure it to make leather.",
	"Ember Fang": "Still warm. Taken from an Ember Wolf.",
	"Moss Fiber": "Soft fibres that glow faintly in the dark. Twisted, they make a strong cord.",
	"Ash Core": "A dense lump of ash that hums when held.",
	# Salvaged from the ruins of the old smithy, and from broken gear
	"Rusted Anvil": "A smith's anvil, pitted with rust but still sound. Someone worked metal in Emberwood once.",
	"Old Bellows": "Cracked leather bellows on a wooden frame. Patched, they'd still blow.",
	"Old Tongs": "Long iron tongs, stiff with rust.",
	"Scrap Iron": "Broken iron: a snapped blade, bent nails, a ruined tool. It can be smelted again.",
	"Scrap Bronze": "Broken bronze. It can be smelted again.",
}

# Rough colour of each material on the ground and in the HUD
const COLORS = {
	"Branch": Color(0.55, 0.4, 0.25), "Flint": Color(0.6, 0.62, 0.65), "Log": Color(0.5, 0.33, 0.2),
	"Stone": Color(0.55, 0.53, 0.52), "Clay": Color(0.7, 0.45, 0.3), "Coal": Color(0.2, 0.2, 0.22),
	"Copper Ore": Color(0.3, 0.7, 0.5), "Tin Ore": Color(0.35, 0.33, 0.4), "Iron Ore": Color(0.65, 0.3, 0.2),
	"Emberstone": Color(1.0, 0.5, 0.15), "Charcoal": Color(0.15, 0.14, 0.15),
	"Bronze Ingot": Color(0.85, 0.6, 0.3), "Iron Ingot": Color(0.6, 0.62, 0.68),
	"Emberstone Shard": Color(1.0, 0.55, 0.2), "Leather": Color(0.55, 0.35, 0.22), "Wolf Hide": Color(0.45, 0.35, 0.3),
	"Ember Fang": Color(1.0, 0.5, 0.2), "Moss Fiber": Color(0.4, 1.0, 0.5), "Ash Core": Color(0.75, 0.3, 1.0),
	"Rusted Anvil": Color(0.5, 0.32, 0.22), "Old Bellows": Color(0.45, 0.32, 0.22), "Old Tongs": Color(0.5, 0.35, 0.25),
	"Scrap Iron": Color(0.5, 0.45, 0.42), "Scrap Bronze": Color(0.7, 0.5, 0.3),
}

# ============================================================
# GEAR
# ============================================================

# slot: where it's equipped. Weapons: attack, range and cooldown are the
# base numbers before material and quality; moves picks the move set
# (combat_moves.gd). Tools: power scales how much rock or wood one strike
# breaks. Armour: defense is added to Veyl's own.
const TYPES = {
	"Sword": {"slot": "weapon", "attack": 12.0, "range": 6.0, "cooldown": 0.4, "moves": "sword", "wear": 1.0},
	"Spear": {"slot": "weapon", "attack": 10.0, "range": 8.5, "cooldown": 0.45, "moves": "spear", "wear": 0.9},
	"Warhammer": {"slot": "weapon", "attack": 19.0, "range": 5.5, "cooldown": 0.62, "moves": "hammer", "wear": 1.25},
	"Pickaxe": {"slot": "pickaxe", "wear": 1.0},
	"Axe": {"slot": "axe", "wear": 1.0},
	"Armor": {"slot": "armor", "wear": 1.0},
}

# Nothing in hand: Veyl fights with vair fists
const FISTS = {"attack": 6.0, "range": 4.5, "cooldown": 0.3, "moves": "fists", "type": "Fists", "magic": "", "tier": 0}

# tier: how hard a rock it can break (blocks.gd hardness); attack and
# defense multiply the type's numbers; durability is strikes or hits
const MATERIALS = {
	"Stone": {"tier": 1, "attack": 0.8, "defense": 0.0, "durability": 60, "scrap": ""},
	"Rusted": {"tier": 1, "attack": 1.0, "defense": 0.0, "durability": 150, "scrap": "Scrap Iron"},
	"Leather": {"tier": 1, "attack": 0.0, "defense": 6.0, "durability": 120, "scrap": ""},
	"Bronze": {"tier": 2, "attack": 1.3, "defense": 12.0, "durability": 220, "scrap": "Scrap Bronze"},
	"Iron": {"tier": 3, "attack": 1.6, "defense": 18.0, "durability": 340, "scrap": "Scrap Iron"},
}

# Forging quality (forge_panel.gd): stats and wear both scale with it
const QUALITIES = ["Crude", "Standard", "Fine", "Masterwork"]
const QUALITY_MULT = [0.85, 1.0, 1.12, 1.25]
const MAX_LEVEL = 3
const LEVEL_BONUS = 0.1

# Rare materials set into gear at the forge. Weapons and armour take them;
# tools don't.
const MAGIC = {
	"Emberbrand": {"material": "Emberstone Shard", "weapon": "Hits set creatures burning.", "armor": ""},
	"Ashweight": {"material": "Ash Core", "weapon": "Hits shove and daze much harder.", "armor": "Turns aside far more of every blow."},
	"Fangswift": {"material": "Ember Fang", "weapon": "Swings come quicker.", "armor": "Dodges recover sooner."},
	"Mosswoven": {"material": "Moss Fiber", "weapon": "Slowly mends your wounds.", "armor": "Slowly mends your wounds."},
}

# What's in hand, as one number for the network: type index * 10 + material
const HELD_TYPES = ["", "Sword", "Spear", "Warhammer", "Pickaxe", "Axe"]
const HELD_MATERIALS = ["Stone", "Rusted", "Leather", "Bronze", "Iron"]

# Tool power by tier, before quality
const TOOL_POWER = {1: 1.0, 2: 1.6, 3: 2.3}


static func make(type: String, material: String, quality: int = 1, magic: String = "") -> Dictionary:

	var gear = {"id": 0, "type": type, "material": material, "quality": quality, "level": 0, "magic": magic}
	gear["durability"] = max_durability(gear)
	return gear


# The sword Veyl wakes with
static func rustblade() -> Dictionary:

	var gear = make("Sword", "Rusted")
	gear["name"] = "Rustblade"
	return gear


static func slot(gear: Dictionary) -> String:
	return TYPES[gear["type"]]["slot"]


static func gear_name(gear: Dictionary) -> String:

	if gear.has("name"):
		return gear["name"]
	var base = "%s %s" % [gear["material"], gear["type"]]
	if gear["type"] == "Armor":
		base = {"Leather": "Leather Jerkin", "Bronze": "Bronze Scale Armour", "Iron": "Iron Mail"}.get(gear["material"], base)
	if gear["magic"] != "":
		base = "%s %s" % [gear["magic"], base]
	var q = QUALITIES[gear["quality"]]
	if q != "Standard":
		base = "%s %s" % [q, base]
	if gear["level"] > 0:
		base += " +%d" % gear["level"]
	return base


static func quality_mult(gear: Dictionary) -> float:
	return QUALITY_MULT[gear["quality"]] * (1.0 + LEVEL_BONUS * gear["level"])


static func max_durability(gear: Dictionary) -> float:
	return MATERIALS[gear["material"]]["durability"] * QUALITY_MULT[gear["quality"]] * (1.0 + 0.15 * gear["level"]) * TYPES[gear["type"]]["wear"]


static func tier(gear: Dictionary) -> int:
	return MATERIALS[gear["material"]]["tier"]


# A weapon's working numbers, in the shape GameState.weapon() returns
static func weapon_stats(gear: Dictionary) -> Dictionary:

	var t = TYPES[gear["type"]]
	var cooldown = t["cooldown"] * (0.85 if gear["magic"] == "Fangswift" else 1.0)
	return {
		"attack": t["attack"] * MATERIALS[gear["material"]]["attack"] * quality_mult(gear),
		"range": t["range"],
		"cooldown": cooldown,
		"moves": t["moves"],
		"type": gear["type"],
		"magic": gear["magic"],
		"tier": tier(gear),
	}


static func tool_power(gear: Dictionary) -> float:
	return TOOL_POWER[tier(gear)] * quality_mult(gear)


static func armor_defense(gear: Dictionary) -> float:
	return MATERIALS[gear["material"]]["defense"] * quality_mult(gear) * (1.3 if gear["magic"] == "Ashweight" else 1.0)


static func describe(gear: Dictionary) -> String:

	var lines = []
	match slot(gear):
		"weapon":
			var s = weapon_stats(gear)
			lines.append("ATK %d  ·  reach %.1f" % [s["attack"], s["range"]])
		"armor":
			lines.append("DEF +%d" % armor_defense(gear))
		_:
			lines.append("Breaks rock of hardness %d  ·  power %.1f" % [tier(gear), tool_power(gear)])
	if gear["magic"] != "":
		var kind = "armor" if slot(gear) == "armor" else "weapon"
		lines.append("%s: %s" % [gear["magic"], MAGIC[gear["magic"]][kind]])
	lines.append("Wear %d / %d" % [ceil(gear["durability"]), max_durability(gear)])
	return "  ·  ".join(lines)


static func held_code(type: String, material: String) -> int:
	return max(HELD_TYPES.find(type), 0) * 10 + max(HELD_MATERIALS.find(material), 0)


static func held_from_code(code: int) -> Array:
	return [HELD_TYPES[clampi(code / 10, 0, HELD_TYPES.size() - 1)], HELD_MATERIALS[clampi(code % 10, 0, HELD_MATERIALS.size() - 1)]]


static func color(item_name: String) -> Color:
	return COLORS.get(item_name, Color.WHITE)
