extends Control

func _ready() -> void:
	pass # Replace with function body.
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
