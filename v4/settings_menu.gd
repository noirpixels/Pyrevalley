extends VBoxContainer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_music_button_pressed() -> void:
	if $MusicButton.text == "ON":
		$MusicButton.text = "OFF"
	else:
		$MusicButton.text = "ON"


func _on_sound_button_pressed() -> void:
	if $SoundButton.text == "ON":
		$SoundButton.text = "OFF"
	else:
		$SoundButton.text = "ON"


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")
