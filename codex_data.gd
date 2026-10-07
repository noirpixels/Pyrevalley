extends Node

var selected_creature = {}

# True while the codex is open as an in-game overlay instead of its own scene
var in_game = false

signal navigate(scene_path)


# ============================================================
# CREATURES
# ============================================================

# Single source of truth for creature stats. The codex screens and the
# game both read from here. color / size / shape are placeholder visuals
# until each creature gets real sprites.
const CREATURES = [
	# ---- Emberwood (prototype) ----
	{"name": "Ember Wolf", "description": "A mysterious creature said to roam the outer valleys of Embervale.", "type": "Beast", "health": 80, "attack": 18, "defense": 12, "speed": 20, "rarity": "Uncommon", "drop": "Ember Fang", "color": Color(0.9, 0.35, 0.1), "size": 1.0, "shape": "capsule"},
	{"name": "Mossling", "description": "A small bundle of living moss that wanders the Emberwood floor. Harmless, until something frightens it.", "type": "Nature", "health": 50, "attack": 10, "defense": 18, "speed": 12, "rarity": "Common", "drop": "Moss Fiber", "color": Color(0.3, 0.6, 0.3), "size": 0.8, "shape": "blob"},
	{"name": "Ashcrawler", "description": "A low, armoured beast with embers smouldering between its plates. It is rarely seen outside the Deep Forest.", "type": "Beast", "health": 110, "attack": 22, "defense": 8, "speed": 10, "rarity": "Rare", "drop": "Ash Core", "color": Color(0.22, 0.2, 0.2), "glow": Color(1.0, 0.35, 0.05), "size": 1.1, "shape": "crawler"},
	{"name": "The Ashbound", "description": "Something vast and burning, chained to the heart of Emberwood. The creatures are not fleeing the forest. They are fleeing it.", "type": "Abomination", "health": 600, "attack": 34, "defense": 20, "speed": 14, "rarity": "Legendary", "drop": "", "color": Color(0.12, 0.1, 0.1), "glow": Color(1.0, 0.3, 0.0), "size": 3.2, "shape": "capsule", "boss": true},

	# ---- Rest of Embervale (codex lore, not in the prototype yet) ----
	{"name": "Ashfang", "description": "A fierce beast that hunts beneath the ancient forests of Embervale.", "type": "Beast", "health": 100, "attack": 24, "defense": 16, "speed": 18, "rarity": "Rare"},
	{"name": "Glowmoth", "description": "A strange glowing creature that appears near ancient ruins after sunset.", "type": "Insect", "health": 45, "attack": 10, "defense": 8, "speed": 28, "rarity": "Rare"},
	{"name": "Stoneback", "description": "A slow-moving guardian covered in ancient stone plates.", "type": "Guardian", "health": 150, "attack": 20, "defense": 35, "speed": 8, "rarity": "Rare"},
	{"name": "Ember Serpent", "description": "A fiery serpent that coils around the volcanic cliffs of Embervale.", "type": "Serpent", "health": 110, "attack": 30, "defense": 14, "speed": 25, "rarity": "Epic"},
	{"name": "Frostwing", "description": "A rare flying creature found near the frozen peaks beyond Embervale.", "type": "Flying", "health": 75, "attack": 22, "defense": 10, "speed": 35, "rarity": "Epic"},
	{"name": "Moonhare", "description": "A mysterious rabbit said to appear under the light of a full moon.", "type": "Beast", "health": 40, "attack": 8, "defense": 6, "speed": 40, "rarity": "Uncommon"},
	{"name": "Moss Giant", "description": "An ancient creature covered in vines, moss, and tiny flowers.", "type": "Giant", "health": 200, "attack": 28, "defense": 30, "speed": 6, "rarity": "Epic"},
	{"name": "Cinder Crow", "description": "A clever bird that nests near warm volcanic rocks.", "type": "Flying", "health": 55, "attack": 14, "defense": 7, "speed": 32, "rarity": "Uncommon"},
]

const RARITY_COLORS = {
	"Common": Color(0.8, 0.8, 0.8),
	"Uncommon": Color(0.45, 0.9, 0.45),
	"Rare": Color(0.4, 0.65, 1.0),
	"Epic": Color(0.8, 0.45, 1.0),
	"Legendary": Color(1.0, 0.55, 0.15),
}

# name -> times defeated (saved by GameState)
var discovered = {}


func get_creature(creature_name: String) -> Dictionary:
	for creature in CREATURES:
		if creature["name"] == creature_name:
			return creature
	push_error("CodexData: unknown creature " + creature_name)
	return {}


# Opens a creature's codex entry
func select(creature_name: String):
	selected_creature = get_creature(creature_name)
	go_to("res://codex_entry.tscn")


# Codex screens call this instead of change_scene_to_file so they also
# work inside the in-game overlay.
func go_to(scene_path: String):
	if in_game:
		navigate.emit(scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)


# Returns true the first time a creature is defeated.
func record_defeat(creature_name: String) -> bool:
	var first_time = not discovered.has(creature_name)
	discovered[creature_name] = discovered.get(creature_name, 0) + 1
	return first_time


# Defense softens hits without ever fully blocking them.
func calc_damage(attack: float, defense: float) -> int:
	var raw = attack * 100.0 / (100.0 + defense * 3.0)
	return max(1, roundi(raw * randf_range(0.85, 1.15)))
