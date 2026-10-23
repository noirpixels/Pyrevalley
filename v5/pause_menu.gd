extends PanelContainer

signal resume_pressed
signal inventory_pressed
signal codex_pressed
signal save_pressed
signal restart_pressed
signal quit_pressed

const UI = preload("res://ui_kit.gd")


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
	box.add_child(UI.button("RESTART PROTOTYPE", restart_pressed.emit))
	box.add_child(UI.button("SAVE & QUIT TO MENU", quit_pressed.emit))


# Swap the pause menu for the chosen screen
func _on_inventory():
	visible = false
	inventory_pressed.emit()


func _on_codex():
	visible = false
	codex_pressed.emit()
