extends Node

# Plays sound effects and music by name from res://audio/<name>.wav
# (made by tools/make_audio.py). Music crossfades between tracks; an
# ambience bed loops underneath. Every Button in the game gets the
# ui_click sound automatically.

const POOL_SIZE = 12
const MUSIC_DB = -8.0
const AMBIENCE_DB = -16.0
const CROSSFADE = 1.2
# Silence, as far as a volume slider is concerned
const QUIET_DB = -60.0
# Per-track trims so the themes sit at a similar loudness
const TRACK_DB = {"camp": 5.0, "boss2": -1.5}

var players: Array[AudioStreamPlayer] = []
var next_player: int = 0
# Two music players, so one can fade out while the other fades in
var music: AudioStreamPlayer
var music_out: AudioStreamPlayer
var ambience: AudioStreamPlayer
var streams = {}


func _ready():

	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in POOL_SIZE:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

	music = looping_player(MUSIC_DB)
	music_out = looping_player(MUSIC_DB)
	ambience = looping_player(AMBIENCE_DB)

	get_tree().node_added.connect(_on_node_added)


func looping_player(db: float) -> AudioStreamPlayer:

	var p = AudioStreamPlayer.new()
	p.volume_db = db
	p.finished.connect(p.play)
	add_child(p)
	return p


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


# Fades to another track (or straight in, if nothing is playing)
func play_music(track: String):

	var stream = get_stream("music_" + track)
	if stream == null or music.stream == stream:
		return

	# The playing track becomes the one fading out
	var old = music
	music = music_out
	music_out = old
	var fading = music_out.playing
	var target_db = MUSIC_DB + TRACK_DB.get(track, 0.0)
	music.stream = stream
	music.volume_db = QUIET_DB if fading else target_db
	music.play()
	# Both at once: the old track fades out while the new one fades in
	var tween = create_tween().set_parallel()
	tween.tween_property(music, "volume_db", target_db, CROSSFADE).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	if fading:
		tween.tween_property(music_out, "volume_db", QUIET_DB, CROSSFADE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
		tween.chain().tween_callback(music_out.stop)


func stop_music():

	for p in [music, music_out]:
		p.stop()
		p.stream = null
		p.volume_db = MUSIC_DB


func play_ambience(bed: String):

	var stream = get_stream("ambience_" + bed)
	if stream == null or ambience.stream == stream:
		return
	ambience.stream = stream
	ambience.play()


func stop_ambience():

	ambience.stop()
	ambience.stream = null


func _on_node_added(node: Node):

	if node is BaseButton:
		node.pressed.connect(play.bind("ui_click", -6.0))
