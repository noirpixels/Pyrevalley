extends Control

func _ready() -> void:
	Sfx.play_music("menu")
	$Title.add_theme_font_override("font", Style.display_bold)
	$Title.add_theme_font_size_override("font_size", 84)
	# A pad starts on PLAY; pad.gd keeps focus in the menu after that
	$MenuCenter/MenuButtons/PlayButton.grab_focus.call_deferred()
func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://game.tscn")
func _on_quit_button_pressed() -> void:
	get_tree().quit()
func _on_settings_button_pressed() -> void:
	get_tree().change_scene_to_file("res://settings.tscn") 
func _on_credits_button_pressed() -> void:
	get_tree().change_scene_to_file("res://credits.tscn")
func _on_codex_button_pressed() -> void:
	get_tree().change_scene_to_file("res://codex.tscn")
