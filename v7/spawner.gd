extends Node

# Fills the rooms from their markers (room.gd): creatures, loose branches
# and flint, shrines, the Cinderwing, Ember Hearts, Rowan and the Ashbound.
# Creatures killed stay dead until Veyl rests or dies; loose branches and
# flint grow back on resting; relics, once taken, are gone for good.

const Mossling = preload("res://mossling.gd")
const EmberWolf = preload("res://ember_wolf.gd")
const Ashcrawler = preload("res://ashcrawler.gd")
const ItemPickup = preload("res://item_pickup.gd")
const Shrine = preload("res://shrine.gd")
const Relic = preload("res://relic.gd")
const Rowan = preload("res://rowan.gd")

const CREATURES = {"m": Mossling, "w": EmberWolf, "a": Ashcrawler}
const FORAGE = {"b": "Branch", "k": "Flint"}

var game: Node
var creatures = []
var forage = []    # [{"id", "item", "at", "room", "node"}]


func _ready():
	add_to_group("spawner")


func populate(in_game: Node):

	game = in_game
	for room in game.rooms:
		var i = 0
		for m in room.markers:
			i += 1
			var id = "%d_%d" % [room.data["index"], i]
			var kind: String = m["kind"]
			if CREATURES.has(kind):
				var c = CREATURES[kind].new()
				c.setup(room, m["at"], "c" + id)
				c.puppet = not Net.is_host()
				room.add_child(c)
				c.global_position = m["at"]
				creatures.append(c)
				if GameState.killed.has(c.id):
					c.die_quietly()
			elif FORAGE.has(kind):
				forage.append({"id": "forage:" + id, "item": FORAGE[kind], "at": m["at"] + Vector2(0, -14), "room": room, "node": null})
			elif kind == "S":
				var shrine = Shrine.new()
				shrine.cell = room.cell
				room.add_child(shrine)
				shrine.global_position = m["at"]
			elif kind == "X" or kind == "H":
				var relic_id = ("relic:cinderwing" if kind == "X" else "relic:heart" + id)
				if not GameState.taken.has(relic_id):
					var relic = Relic.new("cinderwing" if kind == "X" else "heart", relic_id)
					room.add_child(relic)
					relic.global_position = m["at"] + Vector2(0, -50)
			elif kind == "N":
				var rowan = Rowan.new()
				room.add_child(rowan)
				rowan.global_position = m["at"]
			elif kind == "B":
				if not GameState.boss_defeated and ResourceLoader.exists("res://boss.gd"):
					var boss = load("res://boss.gd").new()
					boss.setup(room, m["at"], "boss")
					boss.puppet = not Net.is_host()
					room.add_child(boss)
					boss.global_position = m["at"]
	regrow_forage()


# After resting or dying: every creature back where it began
func respawn_creatures():

	for c in creatures:
		if is_instance_valid(c) and c.is_dead():
			c.revive()


func regrow_forage():

	for f in forage:
		if GameState.taken.has(f["id"]) or is_instance_valid(f["node"]):
			continue
		var pickup = ItemPickup.new(f["item"], 1)
		pickup.taken_id = f["id"]
		pickup.resting = true
		f["room"].add_child(pickup)
		pickup.global_position = f["at"]
		f["node"] = pickup


func drop_item(item: String, at: Vector2, amount: int = 1):

	var pickup = ItemPickup.new(item, amount)
	pickup.velocity = Vector2(randf_range(-160.0, 160.0), randf_range(-520.0, -320.0))
	game.add_child(pickup)
	pickup.global_position = at
