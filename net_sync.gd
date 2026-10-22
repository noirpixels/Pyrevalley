extends Node

# Keeps co-op worlds in step. Everyone builds the same rooms from the
# host's seed; then:
#   - each player moves their own Veyl and sends where it is; the others
#     show it as a remote Veyl (player.gd, remote)
#   - the host runs every creature and the Ashbound, and sends their state;
#     guests show copies that don't think for themselves (enemy.gd, puppet)
#   - a guest's hit on a creature goes to the host to be applied
#   - a creature hurting someone is sent to that player's machine
#   - digging is sent to everyone, so the ground stays the same
#   - attacks' warnings and projectiles are shown on guests' screens too,
#     drawn only (the host's copy is the one that hurts)
# Alone, all of this falls through to applying things directly.

const Player = preload("res://player.gd")
const PLAYER_SEND_GAP = 0.05
const CREATURE_SEND_GAP = 0.066

var game: Node = null
var remotes = {}        # peer id -> remote Veyl
var send_timer: float = 0.0
var creature_timer: float = 0.0


func _ready():
	Net.peer_left.connect(_on_peer_left)


func has_company() -> bool:
	return Net.online() and multiplayer.get_peers().size() > 0


# ============================================================
# ENTERING THE WORLD
# ============================================================

func enter_world(in_game: Node):

	game = in_game
	remotes = {}
	if Net.online():
		arrived.rpc()


func leave_world():
	game = null
	remotes = {}


@rpc("any_peer", "reliable")
func arrived():

	var id = multiplayer.get_remote_sender_id()
	add_remote(id)
	present.rpc_id(id)


@rpc("any_peer", "reliable")
func present():
	add_remote(multiplayer.get_remote_sender_id())


func add_remote(id: int):

	if game == null or remotes.has(id) or id == Net.my_id():
		return
	var veyl = Player.new()
	veyl.remote = true
	veyl.peer_id = id
	veyl.name = "Veyl%d" % id
	game.add_child(veyl)
	veyl.global_position = game.player.global_position
	remotes[id] = veyl
	veyl.add_name_label(Net.name_of(id))


func _on_peer_left(id: int):

	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)


# ============================================================
# EACH TICK: OUR VEYL OUT, THE HOST'S CREATURES OUT
# ============================================================

func _physics_process(delta):

	if game == null or not Net.online() or game.player == null:
		return
	send_timer -= delta
	if send_timer <= 0.0:
		send_timer = PLAYER_SEND_GAP
		player_state.rpc(game.player.net_state())
	if multiplayer.is_server() and has_company():
		creature_timer -= delta
		if creature_timer <= 0.0:
			creature_timer = CREATURE_SEND_GAP
			send_creatures()


@rpc("any_peer", "unreliable_ordered")
func player_state(state: Array):

	var id = multiplayer.get_remote_sender_id()
	if remotes.has(id):
		remotes[id].apply_net_state(state)


func send_creatures():

	var data = []
	var creatures = game.spawner.creatures if game.spawner else []
	for i in creatures.size():
		var c = creatures[i]
		if not is_instance_valid(c) or not c.room.can_process():
			continue
		data.append([i, c.global_position, c.velocity.x, c.facing, c.state, c.health, c.launched, c.is_dead()])
	creature_states.rpc(data)


@rpc("authority", "unreliable_ordered")
func creature_states(data: Array):

	if game == null or game.spawner == null:
		return
	var creatures = game.spawner.creatures
	for row in data:
		var i: int = row[0]
		if i >= creatures.size():
			continue
		var c = creatures[i]
		if row[7]:
			continue
		if c.is_dead():
			c.revive()
		c.puppet_to(row[1], row[2], row[3], row[4], row[5], row[6])


# ============================================================
# HITS AND HURTS
# ============================================================

func hit_creature(creature: Node, amount: float, from: Vector2, push: Vector2, dizzy: float, launch: float):

	if Net.is_host():
		creature.receive_hit(amount, from, push, dizzy, launch)
		return
	var i = game.spawner.creatures.find(creature) if game and game.spawner else -1
	if creature.id == "boss":
		i = -2
	request_hit.rpc_id(1, i, amount, from, push, dizzy, launch)
	# Show the hit right away; the host's numbers follow
	creature.flash_timer = 0.08


@rpc("any_peer", "reliable")
func request_hit(i: int, amount: float, from: Vector2, push: Vector2, dizzy: float, launch: float):

	if not multiplayer.is_server() or game == null:
		return
	var c = boss_node() if i == -2 else (game.spawner.creatures[i] if i >= 0 and i < game.spawner.creatures.size() else null)
	if c and not c.is_dead():
		c.receive_hit(min(amount, 200.0), from, push.limit_length(1200.0), min(dizzy, 80.0), clamp(launch, -1300.0, 1300.0))


func boss_node() -> Node:

	for c in get_tree().get_nodes_in_group("creatures"):
		if c.id == "boss":
			return c
	return null


# Creature deaths are announced so every machine shows the burst and drops
# its own player's loot
func creature_died(creature: Node):

	if not (Net.online() and multiplayer.is_server() and has_company()) or game == null:
		return
	var i = -2 if creature.id == "boss" else game.spawner.creatures.find(creature)
	died.rpc(i)


@rpc("authority", "reliable")
func died(i: int):

	var c = boss_node() if i == -2 else (game.spawner.creatures[i] if game and i >= 0 and i < game.spawner.creatures.size() else null)
	if c and not c.is_dead():
		c.die()


func hurt_player(player: Node, amount: float, from: Vector2):

	if player.remote:
		if multiplayer.is_server():
			hurt_me.rpc_id(player.peer_id, amount, from)
		return
	player.take_damage(amount, from)


@rpc("authority", "reliable")
func hurt_me(amount: float, from: Vector2):

	if game and game.player:
		game.player.take_damage(amount, from)


# ============================================================
# DIGGING, SWINGS AND ATTACK EFFECTS
# ============================================================

func share_dig(room_index: int, at: Vector2, radius: float, tier: int):

	if Net.online():
		remote_dig.rpc(room_index, at, radius, tier)


@rpc("any_peer", "reliable")
func remote_dig(room_index: int, at: Vector2, radius: float, tier: int):

	if game == null or room_index < 0 or room_index >= game.rooms.size():
		return
	var room = game.rooms[room_index]
	if room.terrain.dig(at, clamp(radius, 0.0, 60.0), clampi(tier, 0, 2)) > 0:
		GameState.log_dig(room.cell, at, radius, tier)


func share_player_fx(kind: String, args: Array):

	if Net.online():
		player_fx.rpc(kind, args)


@rpc("any_peer", "unreliable_ordered")
func player_fx(kind: String, args: Array):

	var id = multiplayer.get_remote_sender_id()
	if remotes.has(id):
		remotes[id].remote_fx(kind, args)


# The host shows guests a creature's warning or projectile, drawn only
func creature_fx(kind: String, args: Array):

	if Net.online() and multiplayer.is_server() and has_company():
		remote_creature_fx.rpc(kind, args)


@rpc("authority", "reliable")
func remote_creature_fx(kind: String, args: Array):

	if game:
		game.show_creature_fx(kind, args)
