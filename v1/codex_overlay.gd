extends Control

# Shows the existing codex.tscn / codex_entry.tscn on top of the game.
# Their navigation goes through CodexData.go_to(), which we intercept here.

signal closed

const UI = preload("res://ui_kit.gd")

var content: Node = null


func _ready():

	UI.full_rect(self)
	visible = false

	var bg = ColorRect.new()
	UI.full_rect(bg)
	bg.color = Color(0.04, 0.03, 0.03, 0.96)
	add_child(bg)


func open():

	CodexData.in_game = true
	if not CodexData.navigate.is_connected(_on_navigate):
		CodexData.navigate.connect(_on_navigate)
	show_scene("res://codex.tscn")
	visible = true


func close():

	if content:
		content.queue_free()
		content = null
	CodexData.in_game = false
	visible = false
	closed.emit()


func _on_navigate(scene_path: String):

	# The codex's BACK button heads for the main menu: close instead
	if scene_path == "res://main_menu.tscn":
		close()
	else:
		show_scene(scene_path)


func show_scene(scene_path: String):

	if content:
		content.queue_free()
	content = load(scene_path).instantiate()
	add_child(content)
