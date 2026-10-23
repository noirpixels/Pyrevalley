extends Label3D

# Damage numbers / pickup text that rise and fade out.

static func spawn(parent: Node, pos: Vector3, msg: String, color: Color) -> void:
	var label = load("res://floating_text.gd").new()
	label.text = msg
	label.modulate = color
	parent.add_child(label)
	label.global_position = pos


func _ready():
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	font_size = 64
	pixel_size = 0.03
	outline_size = 16
	outline_modulate = Color(0, 0, 0, 0.8)

	var tween = create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y + 3.0, 0.7)
	tween.tween_property(self, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.tween_property(self, "outline_modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(queue_free)
