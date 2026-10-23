extends PanelContainer

# Esc: carry on, or leave for the title (the run saves at shrines).

const UI = preload("res://ui_kit.gd")


func _init():

	process_mode = Node.PROCESS_MODE_ALWAYS
	UI.centered(self)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var heading = UI.title("PAUSED", 38, UI.EMBER)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	box.add_child(UI.button("RESUME", resume))
	box.add_child(UI.button("QUIT TO TITLE", quit_to_title))
	var note = UI.label("Your journey is saved each time you rest.", 15, UI.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)


func resume():

	visible = false
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.pause_world(false)
	else:
		get_tree().paused = false


func quit_to_title():

	get_tree().paused = false
	Engine.time_scale = 1.0
	if Net.has_method("leave"):
		Net.leave()
	get_tree().change_scene_to_file("res://main_menu.tscn")
