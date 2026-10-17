extends Control

# After The Ashbound falls:
#   "THE FOREST IS QUIET."  ->  "EMBERVALE / PROTOTYPE COMPLETE"

signal play_again_pressed
signal menu_pressed

const UI = preload("res://ui_kit.gd")

var bg: ColorRect
var quiet: Label
var final: VBoxContainer


func _ready():

	UI.full_rect(self)
	visible = false

	bg = ColorRect.new()
	UI.full_rect(bg)
	bg.color = Color(0, 0, 0, 0)
	add_child(bg)

	quiet = UI.title("THE FOREST IS QUIET.", 44, UI.TEXT)
	UI.centered(quiet)
	quiet.modulate.a = 0.0
	add_child(quiet)

	final = VBoxContainer.new()
	final.add_theme_constant_override("separation", 14)
	UI.centered(final)
	final.modulate.a = 0.0
	final.visible = false
	add_child(final)

	var title = UI.title("EMBERVALE", 80, UI.EMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final.add_child(title)

	var sub = UI.label("PROTOTYPE COMPLETE", 26, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final.add_child(sub)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	final.add_child(spacer)

	final.add_child(UI.button("PLAY AGAIN", play_again_pressed.emit))
	final.add_child(UI.button("RETURN TO MENU", menu_pressed.emit))


func play():

	visible = true

	var tween = create_tween()
	tween.tween_property(bg, "color:a", 1.0, 2.0)
	tween.tween_property(quiet, "modulate:a", 1.0, 1.5)
	tween.tween_interval(2.5)
	tween.tween_property(quiet, "modulate:a", 0.0, 1.2)
	tween.tween_callback(func(): final.visible = true)
	tween.tween_property(final, "modulate:a", 1.0, 1.5)
