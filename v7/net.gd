extends Node

# Co-op connection (desktop only: browsers can't open the sockets ENet
# needs). One player hosts their world; others join it by address or from
# the list of games found on the local network. On joining, the host sends
# its world seed and the ground dug so far, and the guest's game is built
# from that. Each player keeps their own progress (a separate guest save).
# What happens in the world is kept in step by net_sync.gd.

signal hosts_changed
signal joined_world
signal connection_failed(reason: String)
signal peer_left(id: int)

const PORT = 24600
const DISCOVERY_PORT = 24601
const GAME_ID = "pyrevalley7"
const MAX_PLAYERS = 4
const BEACON_GAP = 1.0
const HOST_TIMEOUT = 3.5

var player_name: String = "Veyl"
var names = {}          # peer id -> name
var hosts = {}          # address -> {"name", "seed", "seen"}
var last_message: String = ""
var discovery: PacketPeerUDP
var beacon_timer: float = 0.0
var listening: bool = false


func _ready():

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func online() -> bool:

	var peer = multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return not online() or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if online() else 1


func name_of(id: int) -> String:
	return names.get(id, "Veyl")


func available() -> bool:
	return not OS.has_feature("web")


# ============================================================
# HOSTING AND JOINING
# ============================================================

func host(with_name: String) -> String:

	leave()
	player_name = with_name
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return "Couldn't open port %d (is another game hosting?)" % PORT
	multiplayer.multiplayer_peer = peer
	names = {1: player_name}
	start_beacon()
	return ""


func join(address: String, with_name: String):

	leave()
	player_name = with_name
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address.strip_edges(), PORT)
	if err != OK:
		connection_failed.emit("Couldn't reach %s" % address)
		return
	multiplayer.multiplayer_peer = peer


func leave():

	stop_discovery()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	names = {}
	GameState.save_path = GameState.SAVE_PATH


func _on_connected():
	hello.rpc_id(1, player_name)


func _on_connection_failed():

	leave()
	connection_failed.emit("Couldn't connect.")


func _on_server_disconnected():

	last_message = "The host left. Your progress was saved at your last rest."
	leave()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _on_peer_connected(_id: int):
	pass


func _on_peer_disconnected(id: int):

	var who = name_of(id)
	names.erase(id)
	peer_left.emit(id)
	GameState.notify.emit("%s left." % who)


@rpc("any_peer", "reliable")
func hello(guest_name: String):

	if not multiplayer.is_server():
		return
	var id = multiplayer.get_remote_sender_id()
	names[id] = guest_name.substr(0, 16)
	welcome.rpc_id(id, GameState.seed_value, GameState.dig_log, GameState.boss_defeated, names)
	GameState.notify.emit("%s joined." % names[id])
	update_names.rpc(names)


@rpc("authority", "reliable")
func welcome(world_seed: int, dig_log: Dictionary, boss_defeated: bool, all_names: Dictionary):

	names = all_names
	# A guest's own progress lives in its own file, kept per world
	GameState.save_path = GameState.GUEST_SAVE_PATH
	if not GameState.load_game() or GameState.seed_value != world_seed:
		GameState.new_game(world_seed)
	GameState.dig_log = dig_log
	GameState.boss_defeated = boss_defeated
	joined_world.emit()


@rpc("authority", "reliable")
func update_names(all_names: Dictionary):
	names = all_names


# ============================================================
# FINDING GAMES ON THE LOCAL NETWORK
# ============================================================

func start_beacon():

	discovery = PacketPeerUDP.new()
	discovery.set_broadcast_enabled(true)
	discovery.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	listening = false


func listen_for_hosts():

	stop_discovery()
	hosts = {}
	discovery = PacketPeerUDP.new()
	if discovery.bind(DISCOVERY_PORT) != OK:
		discovery = null
		return
	listening = true


func stop_discovery():

	if discovery:
		discovery.close()
	discovery = null
	listening = false


func _process(delta):

	if discovery == null:
		return
	if listening:
		while discovery.get_available_packet_count() > 0:
			var packet = discovery.get_packet().get_string_from_utf8()
			var address = discovery.get_packet_ip()
			var data = JSON.parse_string(packet)
			if data is Dictionary and data.get("game") == GAME_ID:
				hosts[address] = {"name": data.get("name", "?"), "seed": data.get("seed", 0), "seen": Time.get_ticks_msec()}
				hosts_changed.emit()
		for address in hosts.keys():
			if Time.get_ticks_msec() - hosts[address]["seen"] > HOST_TIMEOUT * 1000.0:
				hosts.erase(address)
				hosts_changed.emit()
	elif online() and multiplayer.is_server():
		beacon_timer -= delta
		if beacon_timer <= 0.0:
			beacon_timer = BEACON_GAP
			var msg = JSON.stringify({"game": GAME_ID, "name": player_name, "seed": GameState.seed_value, "players": names.size()})
			discovery.put_packet(msg.to_utf8_buffer())
