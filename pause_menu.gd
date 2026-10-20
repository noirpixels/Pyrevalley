extends PanelContainer

signal resume_pressed
signal inventory_pressed
signal codex_pressed
signal save_pressed
signal restart_pressed
signal quit_pressed

const UI = preload("res://ui_kit.gd")

# Set by game_ui.gd: no restarting someone else's world, and quitting
# leaves (or, for the host, ends) the session
var multiplayer_session: bool = false
var players: VBoxContainer = null


func _ready():

	add_theme_stylebox_override("panel", UI.panel_style())
	UI.centered(self)
	visible = false

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title = UI.title("PAUSED", 38, UI.EMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(UI.button("RESUME", resume_pressed.emit))
	box.add_child(UI.button("INVENTORY", _on_inventory))
	box.add_child(UI.button("CODEX", _on_codex))
	box.add_child(UI.button("SAVE GAME", save_pressed.emit))
	if multiplayer_session:
		if Net.is_host():
			box.add_child(UI.button("PLAYERS", _on_players))
			players = VBoxContainer.new()
			players.visible = false
			box.add_child(players)
			Net.roster_changed.connect(refresh_players)
		var leave = "SAVE & END SESSION" if Net.is_host() else "SAVE & LEAVE SESSION"
		box.add_child(UI.button(leave, quit_pressed.emit))
	else:
		box.add_child(UI.button("RESTART PROTOTYPE", restart_pressed.emit))
		box.add_child(UI.button("SAVE & QUIT TO MENU", quit_pressed.emit))


# Host only: everyone in the session, each with a KICK button
func _on_players():
	players.visible = not players.visible
	refresh_players()


func refresh_players():

	if players == null or not players.visible:
		return
	for child in players.get_children():
		child.queue_free()
	var guests = Net.roster.keys().filter(func(id): return id != Net.my_id())
	if guests.is_empty():
		players.add_child(UI.label("Nobody else is here yet.", 16, UI.MUTED))
		return
	for id in guests:
		var row = HBoxContainer.new()
		var who = UI.label(Net.name_of(id), 18)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		var kick = UI.button("KICK", Net.kick.bind(id))
		kick.custom_minimum_size = Vector2(90, 36)
		row.add_child(kick)
		players.add_child(row)


# Swap the pause menu for the chosen screen
func _on_inventory():
	visible = false
	inventory_pressed.emit()


func _on_codex():
	visible = false
	codex_pressed.emit()
