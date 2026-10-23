extends Node

# Keeps every guest's Emberwood in step with the host's (net.gd runs the
# session itself).
#   Host -> guests: creature snapshots, one-off moments (telegraphs, hits,
#     deaths), spawns, loot, and messages for everyone
#   Guest -> host: its own Veyl, hits it landed, loot it reached
# Each Veyl is run by its own player's machine, so moving, dodging and
# swinging never wait on the network; the host settles everything else.
# Positions go unreliable (a lost update is simply replaced by the next);
# anything that must happen exactly once goes reliable.
# Solo play (and before a session starts) none of this sends anything.

# Loaded when first needed rather than preloaded: these scripts use
# NetSync themselves, and an autoload can't preload its own users
const PLAYER_SCENE = "res://player.tscn"
const ITEM_PICKUP = "res://item_pickup.gd"
const EMBER_PICKUP = "res://ember_pickup.gd"
const ENEMY = "res://enemy.gd"

# Updates per second for moving things
const SEND_RATE = 30.0
# Guests only hear about creatures this close to their Veyl
const RELEVANT_RANGE = 70.0
# Sounds from fights only play this close to your own Veyl
const HEARING_RANGE = 40.0
# Positions use their own channel so they never queue behind reliable events
const STREAM = 1
# The Ember Shade (duel_bot.gd) is run by the host and shown to guests like
# another player, under this id
const BOT_ID = -1
const BOT_NAME = "Ember Shade"
# Sanity limits on what a guest may claim
const MAX_HIT = 999
const MAX_HIT_REACH = 30.0

var world: Node3D = null
# Creature spawners in a fixed order, so an index names the same one everywhere
var spawners: Array = []
# Other players' Veyls on this machine: peer id -> node
var remotes: Dictionary = {}
# Every pickup on the ground: id -> node
var pickups: Dictionary = {}
var taken: Dictionary = {}
var drop_count: int = 0
var send_timer: float = 0.0
# Host: guests whose Emberwood has loaded
var ready_peers: Array = []
# Guest: pickups already asked for (id -> msec), so standing on one asks once
var asked: Dictionary = {}


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS


func active() -> bool:
	return Net.online and world != null


func reset():

	world = null
	spawners = []
	remotes = {}
	pickups = {}
	taken = {}
	ready_peers = []
	asked = {}


# Called once Emberwood has loaded (emberwood.gd)
func enter_world(root: Node3D):

	reset()
	world = root
	spawners = get_tree().get_nodes_in_group("spawners")
	spawners.sort_custom(func(a, b): return a.spawn_id() < b.spawn_id())
	for node in get_tree().get_nodes_in_group("pickups"):
		register_pickup(node)
	# The world as it was saved: dug blocks, felled trees, built stations
	if Net.is_host():
		for key in GameState.saved_objects:
			var node = world.get_node_or_null(NodePath(key))
			if node and node.has_method("apply_snapshot"):
				node.apply_snapshot(GameState.saved_objects[key])
	if Net.online and not Net.is_host():
		client_ready.rpc_id(1)


# ============================================================
# PLAYERS
# ============================================================

func local_player() -> Node3D:
	return get_tree().get_first_node_in_group("player")


func near_me(pos: Vector3) -> bool:

	var me = local_player()
	return me == null or me.global_position.distance_to(pos) < HEARING_RANGE


# Every Veyl in the world, this machine's and everyone else's
func all_players() -> Array:
	return get_tree().get_nodes_in_group("players")


func duel_bot() -> Node3D:
	return get_tree().get_first_node_in_group("duel_bots")


func spawn_remote(id: int, pos: Vector3):

	if world == null or remotes.has(id) or id == Net.my_id():
		return
	var veyl = load(PLAYER_SCENE).instantiate()
	# Before it enters the tree, or its camera would take over the view
	veyl.find_child("MainGameCamera").current = false
	veyl.remote = true
	veyl.peer_id = id
	veyl.name = "EmberShade" if id == BOT_ID else "Peer%d" % id
	world.add_child(veyl)
	veyl.global_position = pos
	remotes[id] = veyl


@rpc("authority", "call_remote", "reliable")
func remote_left(id: int):

	if remotes.has(id):
		if is_instance_valid(remotes[id]):
			remotes[id].queue_free()
		remotes.erase(id)


# Host: net.gd reports a guest disconnecting
func peer_left(id: int):

	ready_peers.erase(id)
	Net.everyone(self, "remote_left", [id])


# Guest -> host: Emberwood has loaded, send me the world
@rpc("any_peer", "call_remote", "reliable")
func client_ready():

	if not (Net.is_host() and world):
		return
	var id = multiplayer.get_remote_sender_id()
	var me = local_player()
	var start = me.global_position if me else Vector3.ZERO

	var players = {Net.my_id(): start}
	for other in remotes:
		players[other] = remotes[other].global_position
	var shade = duel_bot()
	if shade:
		players[BOT_ID] = shade.global_position

	var creatures = []
	for i in spawners.size():
		var creature = spawners[i].creature
		if creature and is_instance_valid(creature) and not creature.dead_already():
			creatures.append([i, creature.max_health, creature.health, creature.global_position])

	var loot = []
	for pid in pickups:
		var node = pickups[pid]
		if node.pickup_id == "" and not taken.has(pid):
			loot.append([pid, node.kind(), node.get("item_name") if node.kind() != "ember" else "", node.global_position])

	welcome.rpc_id(id, {
		"players": players,
		"creatures": creatures,
		"loot": loot,
		"objects": object_snapshots(),
		"world": GameState.world_data(),
		"checkpoint": GameState.checkpoint_position,
	})

	for peer in ready_peers:
		remote_joined.rpc_id(peer, id, start)
	ready_peers.append(id)
	spawn_remote(id, start)
	notify_all("%s joined." % Net.name_of(id))


# Host -> new guest: everything already in the world
@rpc("authority", "call_remote", "reliable")
func welcome(data: Dictionary):

	if world == null:
		return

	for id in data["players"]:
		spawn_remote(id, data["players"][id])

	for entry in data["creatures"]:
		if entry[0] < spawners.size():
			spawners[entry[0]].spawn_puppet(entry[1], entry[2], entry[3])

	for entry in data["loot"]:
		make_pickup(entry[0], entry[1], entry[2], entry[3])

	for key in data["objects"]:
		var node = world.get_node_or_null(NodePath(key))
		if node:
			node.apply_snapshot(data["objects"][key])

	GameState.apply_world(data["world"])
	for pid in GameState.collected_pickups:
		if pickups.has(pid):
			pickups[pid].queue_free()

	# Wake beside the host, and share their shrine until you light your own
	GameState.checkpoint_position = data["checkpoint"]
	var me = local_player()
	if me:
		var host_at: Vector3 = data["players"][1]
		me.global_position = host_at + Vector3(randf_range(-3, 3), 2.0, randf_range(-3, 3))
		me.start_position = me.global_position


@rpc("authority", "call_remote", "reliable")
func remote_joined(id: int, pos: Vector3):
	spawn_remote(id, pos)


# ---- Positions, 30 times a second ----

func _physics_process(delta):

	if not active():
		return
	send_timer -= delta
	if send_timer > 0.0:
		return
	send_timer = 1.0 / SEND_RATE

	var me = local_player()
	if me:
		var state = me.net_state()
		if Net.is_host():
			for peer in ready_peers:
				player_state.rpc_id(peer, Net.my_id(), state)
		else:
			my_state.rpc_id(1, state)

	var shade = duel_bot()
	if shade and Net.is_host():
		var state = shade.net_state()
		for peer in ready_peers:
			player_state.rpc_id(peer, BOT_ID, state)

	if Net.is_host():
		send_creatures()


# Each guest only gets the creatures near their own Veyl
func send_creatures():

	for peer in ready_peers:
		var veyl = remotes.get(peer)
		if veyl == null:
			continue
		var packed = PackedFloat32Array()
		for i in spawners.size():
			var creature = spawners[i].creature
			if creature == null or not is_instance_valid(creature) or creature.dead_already():
				continue
			if creature.global_position.distance_to(veyl.global_position) > RELEVANT_RANGE:
				continue
			packed.append(i)
			packed.append_array(creature.net_state())
		if not packed.is_empty():
			creature_states.rpc_id(peer, packed)


@rpc("any_peer", "call_remote", "unreliable_ordered", STREAM)
func my_state(state: PackedFloat32Array):

	if not Net.is_host():
		return
	var id = multiplayer.get_remote_sender_id()
	if remotes.has(id):
		remotes[id].apply_net_state(state)
	for peer in ready_peers:
		if peer != id:
			player_state.rpc_id(peer, id, state)


@rpc("authority", "call_remote", "unreliable_ordered", STREAM)
func player_state(id: int, state: PackedFloat32Array):

	if remotes.has(id):
		remotes[id].apply_net_state(state)


@rpc("authority", "call_remote", "unreliable_ordered", STREAM)
func creature_states(packed: PackedFloat32Array):

	if world == null:
		return
	var size = 1 + load(ENEMY).NET_FIELDS
	var at = 0
	while at + size <= packed.size():
		var i = int(packed[at])
		if i < spawners.size():
			var creature = spawners[i].creature
			if creature and is_instance_valid(creature):
				creature.apply_net_state(packed, at + 1)
		at += size


# ---- One-off moments on a Veyl (swings, flinches, falling, waking) ----

# id: whose Veyl it is (this player's, or the host's Ember Shade)
func share_player_fx(fx: String, args: Array, id: int):

	if not active():
		return
	if Net.is_host():
		for peer in ready_peers:
			remote_player_fx.rpc_id(peer, id, fx, args)
	else:
		relay_player_fx.rpc_id(1, fx, args)


@rpc("any_peer", "call_remote", "reliable")
func relay_player_fx(fx: String, args: Array):

	if not Net.is_host():
		return
	var id = multiplayer.get_remote_sender_id()
	remote_player_fx(id, fx, args)
	for peer in ready_peers:
		if peer != id:
			remote_player_fx.rpc_id(peer, id, fx, args)


@rpc("authority", "call_remote", "reliable")
func remote_player_fx(id: int, fx: String, args: Array):

	var veyl = remotes.get(id)
	if veyl and is_instance_valid(veyl) and veyl.has_method("fx_" + fx):
		veyl.callv("fx_" + fx, args)


# ---- Damage to a Veyl: always applied by its own player's machine, so a
# dodge that looked clean on their screen stays clean ----

# Host: a creature (or a duel) hit someone's Veyl
func hurt_player(id: int, amount: int, from: Vector3, push: Vector3 = Vector3.ZERO, attacker: int = 0):

	if id == Net.my_id():
		var me = local_player()
		if me:
			me.take_hit(amount, from, push, attacker)
	elif id == BOT_ID:
		var shade = duel_bot()
		if shade:
			shade.take_hit(amount, from, push, attacker)
	else:
		hurt_me.rpc_id(id, amount, from, push, attacker)


@rpc("authority", "call_remote", "reliable")
func hurt_me(amount: int, from: Vector3, push: Vector3, attacker: int):

	var me = local_player()
	if me:
		me.take_hit(amount, from, push, attacker)


# A duel hit landed on this machine (attacker: this player, or the host's
# Ember Shade); the host passes it on
func pvp_hit(target: int, amount: int, from: Vector3, push: Vector3, attacker: int):

	if Net.is_host():
		hurt_player(target, amount, from, push, attacker)
	else:
		request_pvp_hit.rpc_id(1, target, amount, from, push)


@rpc("any_peer", "call_remote", "reliable")
func request_pvp_hit(target: int, amount: int, from: Vector3, push: Vector3):

	if not Net.is_host():
		return
	var id = multiplayer.get_remote_sender_id()
	var ring = get_tree().get_first_node_in_group("pvp_ring")
	var attacker = remotes.get(id)
	var victim = local_player() if target == Net.my_id() else (duel_bot() if target == BOT_ID else remotes.get(target))
	if ring == null or attacker == null or victim == null:
		return
	# Both have to be in the ring on the host's copy too (with some slack)
	if not (ring.contains(attacker.global_position, 4.0) and ring.contains(victim.global_position, 4.0)):
		return
	hurt_player(target, clampi(amount, 0, MAX_HIT), from, push.limit_length(40.0), id)


# ============================================================
# CREATURES
# ============================================================

func creature_at(i: int) -> Node3D:

	if i < 0 or i >= spawners.size():
		return null
	var creature = spawners[i].creature
	return creature if creature and is_instance_valid(creature) else null


# Host: show a creature's moment on every guest too
func creature_fx(creature: Node3D, fx: String, args: Array):

	if not active() or not Net.is_host():
		return
	var i = spawners.find(creature.get_parent())
	if i < 0:
		return
	for peer in ready_peers:
		play_creature_fx.rpc_id(peer, i, fx, args)


@rpc("authority", "call_remote", "reliable")
func play_creature_fx(i: int, fx: String, args: Array):

	var creature = creature_at(i)
	if creature and creature.has_method("fx_" + fx):
		creature.callv("fx_" + fx, args)


# Host: a spawner made a creature
func creature_spawned(spawner: Node, creature: Node3D):

	if not active():
		return
	var i = spawners.find(spawner)
	for peer in ready_peers:
		spawn_creature.rpc_id(peer, i, creature.max_health)


@rpc("authority", "call_remote", "reliable")
func spawn_creature(i: int, max_health: float):

	if world and i >= 0 and i < spawners.size():
		spawners[i].spawn_puppet(max_health, max_health, Vector3.INF)


# This player's swing connected with a creature. The host applies it
# straight away; a guest's hit goes to the host, which trusts what the
# guest saw (within limits), so hits land the way they looked.
func hit_creature(creature: Node3D, amount: int, from: Vector3, push: Vector3, spin: float, dizzy: float, launch: float, side: int, burn: float):

	if Net.is_host():
		creature.receive_hit(amount, from, push, spin, dizzy, launch, side, burn)
	else:
		request_hit.rpc_id(1, spawners.find(creature.get_parent()), amount, from, push, spin, dizzy, launch, side, burn)


@rpc("any_peer", "call_remote", "reliable")
func request_hit(i: int, amount: int, from: Vector3, push: Vector3, spin: float, dizzy: float, launch: float, side: int, burn: float):

	if not Net.is_host():
		return
	var creature = creature_at(i)
	if creature == null or creature.dead_already():
		return
	if from.distance_to(creature.global_position) > MAX_HIT_REACH:
		return
	creature.receive_hit(clampi(amount, 0, MAX_HIT), from, push.limit_length(60.0), spin, dizzy, launch, side, clampf(burn, 0.0, 5.0))


# ============================================================
# LOOT (first to reach it gets it)
# ============================================================

func register_pickup(node: Node3D):

	var id = node.net_id()
	if id != "":
		pickups[id] = node


func unregister_pickup(node: Node3D):

	var id = node.net_id()
	if pickups.get(id) == node:
		pickups.erase(id)


# Host (or solo): a creature dropped something
func drop(kind: String, item_name: String, pos: Vector3) -> Node3D:

	drop_count += 1
	var id = "drop%d" % drop_count
	var node = make_pickup(id, kind, item_name, pos)
	if active():
		for peer in ready_peers:
			loot_dropped.rpc_id(peer, id, kind, item_name, pos)
	return node


@rpc("authority", "call_remote", "reliable")
func loot_dropped(id: String, kind: String, item_name: String, pos: Vector3):
	make_pickup(id, kind, item_name, pos)


func make_pickup(id: String, kind: String, item_name: String, pos: Vector3) -> Node3D:

	if world == null:
		return null
	var node
	if kind == "ember":
		node = load(EMBER_PICKUP).new()
	else:
		# "item": creature drops; "loose": mined or chopped, sinks away in
		# time; "forage": lying on the forest floor
		node = load(ITEM_PICKUP).new()
		node.item_name = item_name
		node.pickup_kind = kind
	node.drop_id = id
	world.add_child(node)
	node.global_position = pos
	return node


# This player reached a pickup
func claim(node: Node3D):

	var id = node.net_id()
	if Net.is_host():
		grant(id, Net.my_id())
		return
	var now = Time.get_ticks_msec()
	if now - asked.get(id, -10000) < 1000:
		return
	asked[id] = now
	request_pickup.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup(id: String):

	if Net.is_host():
		grant(id, multiplayer.get_remote_sender_id())


func grant(id: String, who: int):

	if not pickups.has(id) or taken.has(id):
		return
	taken[id] = true
	Net.everyone(self, "pickup_taken", [id, who])


@rpc("authority", "call_remote", "reliable")
func pickup_taken(id: String, who: int):

	taken.erase(id)
	asked.erase(id)
	var node = pickups.get(id)
	pickups.erase(id)
	if node == null or not is_instance_valid(node):
		return
	if node.pickup_id != "" and not node.pickup_id in GameState.collected_pickups:
		GameState.collected_pickups.append(node.pickup_id)
	if who == Net.my_id():
		node.collect()
	else:
		node.vanish()


# ============================================================
# WORLD OBJECTS (mining sites, trees, stations, the blood moon)
# ============================================================
# A world object is in group "net_objects" and has:
#   host_request(args, sender)  the host acts on a player's strike, chop or build
#   fx_<name>(...)              what everyone sees happen (object_fx)
#   net_snapshot() / apply_snapshot(data)  its state, for late joiners and
#                                the host's save (null when untouched)

func object_key(node: Node) -> String:
	return str(world.get_path_to(node)) if world else ""


# Any player: ask the host to act (the host just does it)
func ask_host(node: Node, args: Array):

	if Net.is_host():
		node.host_request(args, Net.my_id())
	elif active():
		request_object.rpc_id(1, object_key(node), args)


@rpc("any_peer", "call_remote", "reliable")
func request_object(key: String, args: Array):

	if not (Net.is_host() and world):
		return
	var node = world.get_node_or_null(NodePath(key))
	if node and node.is_in_group("net_objects"):
		node.host_request(args, multiplayer.get_remote_sender_id())


# Host: a world object changed; show it here and on every guest
func object_fx(node: Node, fx: String, args: Array = []):

	node.callv("fx_" + fx, args)
	if active() and Net.is_host():
		var key = object_key(node)
		for peer in ready_peers:
			play_object_fx.rpc_id(peer, key, fx, args)


# Host: tell just one player (a refused build, say)
func tell(peer: int, node: Node, fx: String, args: Array = []):

	if peer == Net.my_id():
		node.callv("fx_" + fx, args)
	elif active():
		play_object_fx.rpc_id(peer, object_key(node), fx, args)


@rpc("authority", "call_remote", "reliable")
func play_object_fx(key: String, fx: String, args: Array):

	if world == null:
		return
	var node = world.get_node_or_null(NodePath(key))
	if node and node.has_method("fx_" + fx):
		node.callv("fx_" + fx, args)


func object_snapshots() -> Dictionary:

	var snaps = {}
	if world == null:
		return snaps
	for node in get_tree().get_nodes_in_group("net_objects"):
		var snap = node.net_snapshot()
		if snap != null:
			snaps[object_key(node)] = snap
	return snaps


# Where a player's Veyl is, as the host sees it (to check their reach)
func veyl_of(peer: int) -> Node3D:
	return local_player() if peer == Net.my_id() else remotes.get(peer)


# ============================================================
# MESSAGES
# ============================================================

func notify_all(text: String):
	Net.everyone(self, "notify", [text])


# Any player: a message for the whole session (the host sends it out)
func announce(text: String):

	if not Net.online:
		GameState.notify.emit(text)
		return
	if Net.is_host():
		notify_all(text)
	else:
		request_announce.rpc_id(1, text.left(120))


@rpc("any_peer", "call_remote", "reliable")
func request_announce(text: String):

	if Net.is_host():
		notify_all(text)


@rpc("authority", "call_remote", "reliable")
func notify(text: String):
	GameState.notify.emit(text)
