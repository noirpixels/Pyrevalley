extends Node

# Multiplayer sessions: hosting, joining, finding games on the local
# network, and asking the router to open a port (UPnP) for online play.
# The host runs the world (net_sync.gd); everyone else joins as a guest.
# Solo play never touches this: Godot's default offline peer counts as the
# host, so every "am I the host?" check passes on its own.

signal roster_changed
# Connected and accepted by a host; the game scene loads next
signal joined
signal join_failed(reason)
signal lan_games_changed
signal port_status_changed

const PORT = 24565
const DISCOVERY_PORT = 24566
const MAX_PLAYERS = 16
# Bumped whenever guests and hosts must run the same build to play together
const PROTOCOL = 2
const ANNOUNCE_EVERY = 1.0
# A LAN game that stops announcing itself drops off the list
const LAN_TIMEOUT = 3.5
const NameFilter = preload("res://name_filter.gd")
const GAME_SCENE = "res://game.tscn"
const MENU_SCENE = "res://main_menu.tscn"

var online: bool = false
var player_name: String = "Veyl"
# peer id -> {"name": String}
var roster: Dictionary = {}
# Shown by the main menu after a session ends
var last_message: String = ""
# Shown in game after joining (the host changed this player's name)
var join_notice: String = ""
# Host: guests it removed, so their leaving reads as that
var kicked_ids: Array = []

# Announces a hosted game, or listens for them from the menu
var discovery: PacketPeerUDP = null
var announce_timer: float = 0.0
# ip -> {"name", "players", "seen"}
var lan_games: Dictionary = {}

var upnp_thread: Thread = null
var upnp: UPNP = null
var port_status: String = ""
var public_ip: String = ""


func _ready():

	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func player_count() -> int:
	return max(roster.size(), 1)


func name_of(id: int) -> String:
	if id == NetSync.BOT_ID:
		return NetSync.BOT_NAME
	if id == my_id() and not online:
		return player_name
	return roster.get(id, {}).get("name", "Veyl")


# Runs a method here and on every other machine in the session (the method
# must be an @rpc("authority") one). Solo, it just runs here.
func everyone(node: Node, method: StringName, args: Array = []):

	node.callv(method, args)
	if online and is_host():
		for peer in multiplayer.get_peers():
			node.callv("rpc_id", [peer, method] + args)


# ============================================================
# HOSTING / JOINING
# ============================================================

func host_game(requested_name: String) -> String:

	var why = NameFilter.problem(requested_name)
	if why != "":
		return why
	var peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		return "Couldn't host: port %d is already in use." % PORT
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	begin(requested_name)
	roster[1] = {"name": player_name}

	GameState.use_save(GameState.SAVE_PATH)
	start_announcing()
	open_port()
	get_tree().change_scene_to_file(GAME_SCENE)
	return ""


func join_game(address: String, requested_name: String) -> String:

	var why = NameFilter.problem(requested_name)
	if why != "":
		return why
	address = address.strip_edges()
	if address == "":
		return "Enter the host's address."
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(address, PORT) != OK:
		return "Couldn't start connecting to %s." % address
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	begin(requested_name)
	return ""


func begin(requested_name: String):

	online = true
	player_name = NameFilter.tidy(requested_name)
	roster = {}
	last_message = ""
	join_notice = ""
	kicked_ids = []
	NetSync.reset()


# Ends the session (host: for everyone) and returns to the main menu
func leave(message: String = ""):

	if not online:
		return
	online = false
	last_message = message
	stop_announcing()
	close_port()
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster = {}
	NetSync.reset()
	GameState.use_save(GameState.SAVE_PATH)
	get_tree().paused = false
	Engine.time_scale = 1.0
	Sfx.stop_music()
	Sfx.stop_ambience()
	get_tree().change_scene_to_file(MENU_SCENE)


# The menu gave up while still connecting
func cancel_join():

	if online and not is_host():
		online = false
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_connected():

	register.rpc_id(1, player_name, PROTOCOL)


func _on_connection_failed():

	online = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit("Couldn't reach that game. Check the address, and that the host's port %d is open." % PORT)


func _on_server_disconnected():

	leave("The host ended the session.")


func _on_peer_connected(_id: int):
	pass


func _on_peer_disconnected(id: int):

	if not is_host():
		return
	var who = name_of(id)
	roster.erase(id)
	sync_roster.rpc(roster)
	roster_changed.emit()
	NetSync.peer_left(id)
	if id in kicked_ids:
		kicked_ids.erase(id)
		NetSync.notify_all("%s was removed by the host." % who)
	else:
		NetSync.notify_all("%s left." % who)


# Guest -> host, first thing after connecting
@rpc("any_peer", "call_remote", "reliable")
func register(requested_name: String, protocol: int):

	if not is_host():
		return
	var id = multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		refuse.rpc_id(id, "That game is running a different version of Pyrevalley.")
		get_tree().create_timer(0.5).timeout.connect(multiplayer.multiplayer_peer.disconnect_peer.bind(id))
		return

	# Checked here as well as in the guest's menu, so a modified game
	# can't sneak a name through
	var why = NameFilter.problem(requested_name)
	var given = unique_name("Veyl" if why != "" else requested_name)
	roster[id] = {"name": given}
	sync_roster.rpc(roster)
	roster_changed.emit()
	if why != "":
		name_notice.rpc_id(id, "%s You're %s in this game." % [why.replace(" Pick another.", ""), given])
	welcome_to_session.rpc_id(id, GameState.world_seed)


func unique_name(wanted: String) -> String:

	wanted = NameFilter.tidy(wanted)
	if wanted == "":
		wanted = "Veyl"
	var taken = roster.values().map(func(p): return p["name"])
	var candidate = wanted
	var n = 2
	while candidate in taken:
		# Room for the number within the length limit
		candidate = "%s %d" % [wanted.left(NameFilter.MAX_LENGTH - 3), n]
		n += 1
	return candidate


@rpc("authority", "call_remote", "reliable")
func name_notice(text: String):
	join_notice = text


# Host: remove a guest from the session
func kick(id: int):

	if not (is_host() and roster.has(id)) or id == my_id():
		return
	kicked_ids.append(id)
	kicked.rpc_id(id)
	# A moment for the message to arrive before the line drops
	get_tree().create_timer(0.3).timeout.connect(func():
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.disconnect_peer(id))


@rpc("authority", "call_remote", "reliable")
func kicked():
	leave("The host removed you from the session.")


@rpc("authority", "call_remote", "reliable")
func refuse(reason: String):

	online = false
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func sync_roster(data: Dictionary):

	roster = data
	if roster.has(my_id()):
		player_name = roster[my_id()]["name"]
	roster_changed.emit()


# Host -> new guest: accepted, load Emberwood. The host's seed builds the
# same forest here (world_gen.gd), and world progress comes from the host;
# the guest keeps its own inventory, codex and Max Combo in a separate save
# so their solo world is never touched.
@rpc("authority", "call_remote", "reliable")
func welcome_to_session(world_seed: int):

	GameState.use_save(GameState.GUEST_SAVE_PATH)
	GameState.ensure_loaded()
	GameState.reset_world()
	GameState.world_seed = world_seed
	joined.emit()
	get_tree().change_scene_to_file(GAME_SCENE)


# ============================================================
# LAN DISCOVERY
# ============================================================

func start_announcing():

	stop_announcing()
	discovery = PacketPeerUDP.new()
	discovery.set_broadcast_enabled(true)
	discovery.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	announce_timer = 0.0


func stop_announcing():

	if discovery:
		discovery.close()
	discovery = null


# The multiplayer menu listens while it's open
func listen_lan(listen: bool):

	stop_announcing()
	lan_games = {}
	if listen:
		discovery = PacketPeerUDP.new()
		if discovery.bind(DISCOVERY_PORT) != OK:
			discovery = null
	lan_games_changed.emit()


func _process(delta):

	if discovery == null:
		return

	if online and is_host():
		announce_timer -= delta
		if announce_timer <= 0.0:
			announce_timer = ANNOUNCE_EVERY
			var info = {"game": "Pyrevalley", "protocol": PROTOCOL, "name": player_name, "players": roster.size(), "max": MAX_PLAYERS}
			discovery.put_packet(JSON.stringify(info).to_utf8_buffer())
		return

	var changed = false
	while discovery.get_available_packet_count() > 0:
		var packet = discovery.get_packet().get_string_from_utf8()
		var ip = discovery.get_packet_ip()
		var info = JSON.parse_string(packet)
		if typeof(info) != TYPE_DICTIONARY or info.get("game") != "Pyrevalley":
			continue
		if int(info.get("protocol", 0)) != PROTOCOL:
			continue
		changed = changed or not lan_games.has(ip)
		lan_games[ip] = {"name": str(info.get("name", "?")), "players": int(info.get("players", 1)), "max": int(info.get("max", MAX_PLAYERS)), "seen": Time.get_ticks_msec()}

	var now = Time.get_ticks_msec()
	for ip in lan_games.keys():
		if now - lan_games[ip]["seen"] > LAN_TIMEOUT * 1000.0:
			lan_games.erase(ip)
			changed = true
	if changed:
		lan_games_changed.emit()


# Addresses friends on the same Wi-Fi can type in
func lan_addresses() -> Array:

	var found = []
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			found.append(address)
	return found


# ============================================================
# ONLINE (UPnP port forwarding)
# ============================================================

# Router discovery blocks for a couple of seconds, so it runs on a thread
func open_port():

	port_status = "Opening port %d on your router..." % PORT
	public_ip = ""
	port_status_changed.emit()
	upnp_thread = Thread.new()
	upnp_thread.start(_upnp_open)


func _upnp_open():

	var u = UPNP.new()
	var status = ""
	var address = ""
	if u.discover(2000, 2) != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		status = "Your router didn't answer (UPnP). Online friends need port %d (UDP) forwarded to this computer." % PORT
	elif u.add_port_mapping(PORT, PORT, "Pyrevalley", "UDP") != UPNP.UPNP_RESULT_SUCCESS:
		status = "Your router refused to open port %d. Forward it (UDP) by hand for online play." % PORT
	else:
		address = u.query_external_address()
		status = "Online friends can join at %s" % address
	_upnp_done.call_deferred(u if address != "" else null, status, address)


func _upnp_done(u: UPNP, status: String, address: String):

	if upnp_thread:
		upnp_thread.wait_to_finish()
		upnp_thread = null
	if not online:
		# The session ended while the router was answering
		if u:
			u.delete_port_mapping(PORT, "UDP")
		return
	upnp = u
	port_status = status
	public_ip = address
	port_status_changed.emit()


func close_port():

	if upnp_thread:
		upnp_thread.wait_to_finish()
		upnp_thread = null
	if upnp:
		upnp.delete_port_mapping(PORT, "UDP")
	upnp = null
	port_status = ""
	public_ip = ""


func _exit_tree():

	if online:
		close_port()
		multiplayer.multiplayer_peer.close()
