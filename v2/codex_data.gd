extends Node

var selected_creature = {}
var selected_entry = {}

# True while the codex is open as an in-game overlay instead of its own scene
var in_game = false

signal navigate(scene_path)


# ============================================================
# CREATURES
# ============================================================

# Single source of truth for creature stats. The codex screens and the
# game both read from here. "sprite" is the creature's art (its glow
# layer is <name>_glow.png); "size" scales its collision and weight.
const CREATURES = [
	# ---- Emberwood (prototype) ----
	{"name": "Ember Wolf", "description": "A mysterious creature said to roam the outer valleys of Embervale.", "type": "Beast", "health": 80, "attack": 18, "defense": 12, "speed": 20, "rarity": "Uncommon", "drop": "Ember Fang", "sprite": "res://Creatures/ember_wolf.png", "size": 1.0},
	{"name": "Mossling", "description": "A small bundle of living moss that wanders the Emberwood floor. Harmless, until something frightens it.", "type": "Nature", "health": 50, "attack": 10, "defense": 18, "speed": 12, "rarity": "Common", "drop": "Moss Fiber", "sprite": "res://Creatures/mossling.png", "size": 0.8},
	{"name": "Ashcrawler", "description": "A low, armoured beast with embers smouldering between its plates. It is rarely seen outside the Deep Forest.", "type": "Beast", "health": 110, "attack": 22, "defense": 8, "speed": 10, "rarity": "Rare", "drop": "Ash Core", "sprite": "res://Creatures/ashcrawler.png", "size": 1.1},
	{"name": "The Ashbound", "description": "Something vast and burning, chained to the heart of Emberwood. The creatures are not fleeing the forest. They are fleeing it.", "type": "Abomination", "health": 900, "attack": 34, "defense": 20, "speed": 14, "rarity": "Legendary", "drop": "", "sprite": "res://Creatures/ashbound.png", "size": 3.2, "boss": true},

	# ---- Rest of Embervale (codex lore, not in the prototype yet) ----
	{"name": "Ashfang", "description": "A fierce beast that hunts beneath the ancient forests of Embervale.", "type": "Beast", "health": 100, "attack": 24, "defense": 16, "speed": 18, "rarity": "Rare"},
	{"name": "Glowmoth", "description": "A strange glowing creature that appears near ancient ruins after sunset.", "type": "Insect", "health": 45, "attack": 10, "defense": 8, "speed": 28, "rarity": "Rare"},
	{"name": "Stoneback", "description": "A slow-moving guardian covered in ancient stone plates.", "type": "Guardian", "health": 150, "attack": 20, "defense": 35, "speed": 8, "rarity": "Rare"},
	{"name": "Ember Serpent", "description": "A fiery serpent that coils around the volcanic cliffs of Embervale.", "type": "Serpent", "health": 110, "attack": 30, "defense": 14, "speed": 25, "rarity": "Epic"},
	{"name": "Frostwing", "description": "A rare flying creature found near the frozen peaks beyond Embervale.", "type": "Flying", "health": 75, "attack": 22, "defense": 10, "speed": 35, "rarity": "Epic"},
	{"name": "Moonhare", "description": "A mysterious rabbit said to appear under the light of a full moon.", "type": "Beast", "health": 40, "attack": 8, "defense": 6, "speed": 40, "rarity": "Uncommon"},
	{"name": "Moss Giant", "description": "An ancient creature covered in vines, moss, and tiny flowers.", "type": "Giant", "health": 200, "attack": 28, "defense": 30, "speed": 6, "rarity": "Epic"},
	{"name": "Cinder Crow", "description": "A clever bird that nests near warm volcanic rocks.", "type": "Flying", "health": 55, "attack": 14, "defense": 7, "speed": 32, "rarity": "Uncommon"},
	{"name": "Crystal Beetle", "description": "A small creature with a glowing crystal shell.", "type": "Insect", "health": 60, "attack": 12, "defense": 26, "speed": 14, "rarity": "Uncommon"},
]


# ============================================================
# OTHER CODEX CATEGORIES
# ============================================================

# In-game weapons ("item") take their stats from GameState.ITEMS.
const WEAPONS = [
	{"name": "Rustblade", "item": true},
	{"name": "Ember Sword", "description": "A balanced blade forged from ember-forged steel. Reliable and powerful in the hands of a skilled warrior.", "rumoured": true},
]

const PLANTS = [
	{"name": "Emberwood Pine", "description": "Tall, dark pines that crowd every path in Emberwood. Their lowest branches are scorched, as if something burning once walked beneath them.", "where": "Everywhere in Emberwood"},
	{"name": "Emberbloom", "description": "Small orange flowers that open after dusk. Their petals stay warm long after they are picked.", "where": "Forest clearings", "image": "res://Textures/Grass/fgrass1.png"},
	{"name": "Glowmoss", "description": "Soft moss that glows faintly in the dark. Mosslings are made of it, or perhaps it is made of them.", "where": "The forest floor", "image": "res://Textures/Grass/m1.png"},
]

# "unlock" names a GameState condition; see CodexData.is_unlocked()
const NPCS = [
	{"name": "Veyl", "description": "Woke in the ash at the edge of Emberwood with an old sword and no memory. The embers lean toward vem whenever vae passes.", "role": "You", "image": "res://Veyl/veylclothed__F.png"},
	{"name": "Rowan", "description": "An old warden who keeps a fire burning in the middle of Emberwood. He has watched the creatures run for years, and he knows more than he says.", "role": "Forest warden", "image": "res://NPCs/rowan.png", "unlock": "met_rowan"},
]

const LOCATIONS = [
	{"name": "The Waking Glade", "description": "A patch of ash at the southern edge of the forest. Here the ash gave something back.", "region": "Emberwood"},
	{"name": "Emberwood Forest", "description": "Pines, moss and wandering creatures. Lately the creatures have stopped wandering and started running.", "region": "Emberwood"},
	{"name": "Rowan's Camp", "description": "A campfire and an ember shrine in the heart of the forest. The only place in Emberwood that feels safe.", "region": "Emberwood"},
	{"name": "The Deep Forest", "description": "Darker, quieter and older. The ash lies thicker here, and the Ashcrawlers do not like visitors.", "region": "Emberwood", "unlock": "quest_complete"},
	{"name": "Ashbound Arena", "description": "A ring of scorched earth at the far end of Emberwood. Whatever the creatures are fleeing, it waits here.", "region": "Emberwood", "unlock": "quest_complete"},
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
	selected_entry = {}
	go_to("res://codex_entry.tscn")


# Opens a codex entry from any other category. Needs "name" and
# "description"; "stats" (text) and "image" (path) are optional.
func select_entry(entry: Dictionary):
	selected_creature = {}
	selected_entry = entry
	go_to("res://codex_entry.tscn")


# In-game creatures stay hidden until Veyl has defeated one
func is_creature_known(creature: Dictionary) -> bool:
	return not creature.has("sprite") or discovered.has(creature["name"])


# Once unlocked, an entry is remembered in `discovered` (saved with the
# codex), so it stays unlocked in later runs
func is_unlocked(entry: Dictionary) -> bool:
	if discovered.has(entry["name"]):
		return true
	var unlocked = true
	match entry.get("unlock", ""):
		"met_rowan":
			unlocked = GameState.quest_accepted()
		"quest_complete":
			unlocked = GameState.quest_state == GameState.QUEST_COMPLETE or GameState.boss_defeated
	if unlocked and entry.has("unlock"):
		discovered[entry["name"]] = 1
	return unlocked


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
