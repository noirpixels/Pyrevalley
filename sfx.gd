extends Node

# Plays sound effects and music by name from res://audio/<name>.wav.
# Every Button in the game gets the ui_click sound automatically.

const POOL_SIZE = 8

var players: Array[AudioStreamPlayer] = []
var next_player: int = 0
var music: AudioStreamPlayer
var streams = {}


func _ready():

	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in POOL_SIZE:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

	music = AudioStreamPlayer.new()
	music.volume_db = -8.0
	music.finished.connect(music.play)
	add_child(music)

	get_tree().node_added.connect(_on_node_added)


func get_stream(sound: String) -> AudioStream:

	if not streams.has(sound):
		var path = "res://audio/%s.wav" % sound
		streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return streams[sound]


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0):

	var stream = get_stream(sound)
	if stream == null:
		return

	var p = players[next_player]
	next_player = (next_player + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func play_music(track: String):

	var stream = get_stream("music_" + track)
	if stream == null or music.stream == stream:
		return
	music.stream = stream
	music.play()


func stop_music():

	music.stop()
	music.stream = null


func _on_node_added(node: Node):

	if node is BaseButton:
		node.pressed.connect(play.bind("ui_click", -6.0))
