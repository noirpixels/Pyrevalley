extends CanvasLayer

# Owns every in-game screen and decides when the game is paused.
# Actions (pad.gd): pause (Esc / +) pause or close, inventory (I / -),
# codex (C / L), and a pad's back button closes the open screen.
# In a multiplayer session nothing pauses: screens open over the running
# game and only stop your own Veyl from moving.

const Hud = preload("res://hud.gd")
const DialogueBox = preload("res://dialogue_box.gd")
const InventoryPanel = preload("res://inventory_panel.gd")
const PauseMenu = preload("res://pause_menu.gd")
const CodexOverlay = preload("res://codex_overlay.gd")
const EndingScreen = preload("res://ending_screen.gd")

@export var player_path: NodePath = ^"../Player3D"

var player: Node3D
var hud
var dialogue
var inventory
var pause_menu
var codex
var ending


func _ready():

	add_to_group("game_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node(player_path)

	hud = Hud.new()
	add_child(hud)
	hud.setup(player)
	hud.inventory_pressed.connect(toggle_inventory)
	hud.codex_pressed.connect(toggle_codex)
	hud.pause_pressed.connect(toggle_pause)

	dialogue = DialogueBox.new()
	add_child(dialogue)
	dialogue.closed.connect(update_paused)

	inventory = InventoryPanel.new()
	add_child(inventory)
	inventory.closed.connect(update_paused)

	pause_menu = PauseMenu.new()
	pause_menu.multiplayer_session = Net.online
	add_child(pause_menu)
	pause_menu.resume_pressed.connect(toggle_pause)
	pause_menu.inventory_pressed.connect(toggle_inventory)
	pause_menu.codex_pressed.connect(toggle_codex)
	pause_menu.save_pressed.connect(save)
	pause_menu.restart_pressed.connect(restart)
	pause_menu.quit_pressed.connect(quit_to_menu)

	codex = CodexOverlay.new()
	add_child(codex)
	codex.closed.connect(update_paused)

	ending = EndingScreen.new()
	ending.multiplayer_session = Net.online
	add_child(ending)
	ending.play_again_pressed.connect(restart)
	ending.menu_pressed.connect(quit_to_menu)

	player.died.connect(_on_player_died)
	GameState.boss_defeated_signal.connect(_on_boss_defeated)


func _input(event):

	if ending.visible or dialogue.visible:
		return

	if event.is_action_pressed("pause"):
		if codex.visible:
			codex.close()
		elif inventory.visible:
			inventory.close()
		else:
			toggle_pause()
	elif event.is_action_pressed("inventory"):
		toggle_inventory()
	elif event.is_action_pressed("codex"):
		toggle_codex()
	elif event is InputEventJoypadButton and event.is_action_pressed("ui_cancel") and (inventory.visible or pause_menu.visible):
		# The codex has its own BACK button, which pad.gd presses
		if inventory.visible:
			inventory.close()
		else:
			toggle_pause()
	else:
		return

	get_viewport().set_input_as_handled()


# ============================================================
# SCREENS
# ============================================================

func update_paused():

	var paused = dialogue.visible or inventory.visible or pause_menu.visible or codex.visible or ending.visible
	get_tree().paused = paused and not Net.online
	player.input_blocked = paused
	# Let pad.gd hand focus to whichever screen is now on top
	get_viewport().gui_release_focus()
	hud.set_buttons_visible(not paused)


func boss_intro(title: String, subtitle: String):

	hud.title_card(title, subtitle)


func show_dialogue(speaker: String, lines: Array, on_done: Callable = Callable()):

	dialogue.start(speaker, lines, on_done)
	update_paused()


func toggle_pause():

	pause_menu.visible = not pause_menu.visible
	update_paused()


func toggle_inventory():

	if inventory.visible:
		inventory.close()
	else:
		pause_menu.visible = false
		inventory.open()
	update_paused()


func toggle_codex():

	if codex.visible:
		codex.close()
	else:
		pause_menu.visible = false
		codex.open()
	update_paused()


# ============================================================
# GAME FLOW
# ============================================================

func save():

	GameState.save_game(player)
	hud.toast("Game saved.")


func restart():

	GameState.restart()
	get_tree().paused = false
	get_tree().reload_current_scene()


func quit_to_menu():

	if not GameState.boss_defeated:
		GameState.save_game(player)
	GameState.loaded = false
	if Net.online:
		Net.leave()
		return
	get_tree().paused = false
	Sfx.stop_music()
	Sfx.stop_ambience()
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _on_player_died():

	await get_tree().create_timer(1.0).timeout
	await hud.fade(1.0, 0.6)
	player.respawn()
	hud.show_message("You awaken at the ember shrine.")
	await hud.fade(0.0, 0.8)


func _on_boss_defeated():

	GameState.save_game(player)
	await get_tree().create_timer(2.5).timeout
	Sfx.stop_ambience()
	Sfx.play_music("ending")
	ending.play()
	update_paused()
