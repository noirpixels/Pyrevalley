extends PanelContainer

# The main menu's multiplayer screen: pick a name, host a game, join one
# by address, or pick a game announced on the same Wi-Fi (net.gd).
# Remembers the name and last address in user://multiplayer.cfg.

signal closed

const UI = preload("res://ui_kit.gd")
const PREFS = "user://multiplayer.cfg"

var name_field: LineEdit
var address_field: LineEdit
var lan_list: VBoxContainer
var status: Label
var host_button: Button
var join_button: Button


func _ready():

	add_theme_stylebox_override("panel", UI.panel_style())
	UI.centered(self)
	custom_minimum_size = Vector2(520, 0)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title = UI.title("MULTIPLAYER", 38, UI.EMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var prefs = ConfigFile.new()
	prefs.load(PREFS)

	box.add_child(UI.label("Your name", 18, UI.MUTED))
	name_field = field(prefs.get_value("player", "name", "Veyl"), "Veyl")
	name_field.max_length = 16
	box.add_child(name_field)

	host_button = UI.button("HOST A GAME", _on_host)
	box.add_child(host_button)
	var host_note = UI.label("Up to %d players. Friends on your Wi-Fi find it below; online friends join with your address." % Net.MAX_PLAYERS, 15, UI.MUTED)
	host_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(host_note)

	box.add_child(HSeparator.new())

	box.add_child(UI.label("Join by address", 18, UI.MUTED))
	var row = HBoxContainer.new()
	box.add_child(row)
	address_field = field(prefs.get_value("player", "address", ""), "192.168.1.20")
	address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_field.text_submitted.connect(func(_text): _on_join())
	row.add_child(address_field)
	join_button = UI.button("JOIN", _on_join)
	join_button.custom_minimum_size = Vector2(120, 44)
	row.add_child(join_button)

	box.add_child(UI.label("Games on your Wi-Fi", 18, UI.MUTED))
	lan_list = VBoxContainer.new()
	box.add_child(lan_list)

	status = UI.label(Net.last_message, 17, UI.EMBER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	Net.last_message = ""

	box.add_child(UI.button("BACK", close))

	Net.lan_games_changed.connect(refresh_lan)
	Net.join_failed.connect(_on_join_failed)
	Net.listen_lan(true)
	refresh_lan()
	host_button.grab_focus.call_deferred()


func field(text: String, placeholder: String) -> LineEdit:

	var edit = LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 40)
	edit.add_theme_font_size_override("font_size", 20)
	return edit


func refresh_lan():

	for child in lan_list.get_children():
		child.queue_free()
	if Net.lan_games.is_empty():
		lan_list.add_child(UI.label("Looking...", 16, UI.MUTED))
		return
	for ip in Net.lan_games:
		var game = Net.lan_games[ip]
		var text = "%s's game  ·  %d/%d" % [game["name"], game["players"], game["max"]]
		lan_list.add_child(UI.button(text, _join.bind(ip)))


func remember():

	var prefs = ConfigFile.new()
	prefs.set_value("player", "name", name_field.text.strip_edges())
	prefs.set_value("player", "address", address_field.text.strip_edges())
	prefs.save(PREFS)


func _on_host():

	remember()
	var error = Net.host_game(name_field.text)
	if error != "":
		status.text = error


func _on_join():
	_join(address_field.text)


func _join(address: String):

	remember()
	var error = Net.join_game(address, name_field.text)
	if error != "":
		status.text = error
		return
	status.text = "Joining %s..." % address.strip_edges()
	host_button.disabled = true
	join_button.disabled = true


func _on_join_failed(reason: String):

	status.text = reason
	host_button.disabled = false
	join_button.disabled = false


func _unhandled_input(event):

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close():

	Net.cancel_join()
	closed.emit()
	queue_free()


func _exit_tree():

	if not Net.online:
		Net.listen_lan(false)
