extends Control

func _ready() -> void:
	Sfx.play_music("menu")
	$Title.add_theme_font_override("font", Style.display_bold)
	$Title.add_theme_font_size_override("font_size", 84)
	# A pad starts on PLAY; pad.gd keeps focus in the menu after that
	$MenuCenter/MenuButtons/PlayButton.grab_focus.call_deferred()
	# Browsers can't run the game's networking, so the web build stays solo
	$MenuCenter/MenuButtons/MultiplayerButton.visible = not OS.has_feature("web")
	# Back from a session that ended: say why
	if Net.last_message != "":
		_on_multiplayer_button_pressed()
func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://game.tscn")
func _on_multiplayer_button_pressed() -> void:
	var lobby = preload("res://multiplayer_menu.gd").new()
	add_child(lobby)
	lobby.closed.connect($MenuCenter/MenuButtons/MultiplayerButton.grab_focus)
func _on_quit_button_pressed() -> void:
	get_tree().quit()
func _on_settings_button_pressed() -> void:
	get_tree().change_scene_to_file("res://settings.tscn") 
func _on_credits_button_pressed() -> void:
	get_tree().change_scene_to_file("res://credits.tscn")
func _on_codex_button_pressed() -> void:
	get_tree().change_scene_to_file("res://codex.tscn")
