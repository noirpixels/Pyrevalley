extends RefCounted

# Gear and what it's made from, and every recipe (crafting_panel.gd).
#   Gear: {"type", "material"}; weapons go in the weapon slot, pickaxes in
#   the pickaxe slot. No weapon means Veyl fights with vair fists.

# Base numbers before material. range: px in front of Veyl a strike reaches
const WEAPONS = {
	"Sword": {"attack": 12.0, "range": 100.0, "cooldown": 0.34, "moves": "sword"},
	"Spear": {"attack": 10.0, "range": 140.0, "cooldown": 0.4, "moves": "spear"},
	"Warhammer": {"attack": 19.0, "range": 92.0, "cooldown": 0.58, "moves": "hammer"},
}
const FISTS = {"type": "Fists", "material": "", "attack": 6.0, "range": 62.0, "cooldown": 0.24, "moves": "fists"}

const MATERIAL_ATTACK = {"Rusted": 1.0, "Stone": 0.85, "Bronze": 1.35}

# Rough colour of each material on the ground and in the pack
const COLORS = {
	"Branch": Color(0.55, 0.4, 0.25), "Flint": Color(0.62, 0.64, 0.68),
	"Copper Ore": Color(0.3, 0.75, 0.55), "Tin Ore": Color(0.45, 0.42, 0.55),
	"Bronze Ingot": Color(0.9, 0.62, 0.3), "Moss Fiber": Color(0.45, 1.0, 0.5),
	"Ember Fang": Color(1.0, 0.5, 0.2), "Ash Core": Color(0.75, 0.35, 1.0),
}

# Anywhere: tools and a spear from what lies around
const HAND = [
	{"title": "Stone Pickaxe", "gear": ["Pickaxe", "Stone"], "cost": {"Branch": 2, "Flint": 3},
		"text": "Breaks earth. Dig toward the mouse with F."},
	{"title": "Stone Spear", "gear": ["Spear", "Stone"], "cost": {"Branch": 3, "Flint": 2},
		"text": "Reaches further, in narrow thrusts."},
]

# At an ember shrine, which is also a forge
const SHRINE = [
	{"title": "Bronze Ingot", "item": ["Bronze Ingot", 1], "cost": {"Copper Ore": 2, "Tin Ore": 1},
		"text": "Copper and tin, smelted in the shrine's flame."},
	{"title": "Bronze Pickaxe", "gear": ["Pickaxe", "Bronze"], "cost": {"Bronze Ingot": 2, "Branch": 1},
		"text": "Hard enough to break rock."},
	{"title": "Bronze Sword", "gear": ["Sword", "Bronze"], "cost": {"Bronze Ingot": 3, "Branch": 1},
		"text": "A true blade. Hits a third harder than the Rustblade."},
	{"title": "Bronze Warhammer", "gear": ["Warhammer", "Bronze"], "cost": {"Bronze Ingot": 4, "Ash Core": 1},
		"text": "Slow and crushing: big shoves, quick to daze."},
	{"title": "Mosswoven Charm", "gear": ["Charm", "Mosswoven"], "cost": {"Moss Fiber": 4, "Ember Fang": 1},
		"text": "Slowly closes wounds."},
]


static func slot_of(type: String) -> String:

	match type:
		"Pickaxe":
			return "pickaxe"
		"Charm":
			return "charm"
	return "weapon"


static func gear_name(gear) -> String:

	if gear == null:
		return "nothing"
	if gear["type"] == "Sword" and gear["material"] == "Rusted":
		return "Rustblade"
	if gear["type"] == "Charm":
		return "%s Charm" % gear["material"]
	return "%s %s" % [gear["material"], gear["type"]]


# The weapon in hand as working numbers (fists if none)
static func weapon_stats(gear) -> Dictionary:

	if gear == null or not WEAPONS.has(gear["type"]):
		return FISTS.duplicate()
	var stats = WEAPONS[gear["type"]].duplicate()
	stats["attack"] *= MATERIAL_ATTACK.get(gear["material"], 1.0)
	stats["type"] = gear["type"]
	stats["material"] = gear["material"]
	return stats
