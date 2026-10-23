extends StaticBody3D

# A wall of embers that blocks the path until the quest allows passage.

const EmberWall = preload("res://ember_wall.gd")

@export var width: float = 20.0
# "quest_accepted" or "quest_complete"
@export var opens_when: String = "quest_accepted"
@export var sealed_text: String = "The path is sealed by embers."

var wall: EmberWall
var label: Label3D


func _ready():

	GameState.ensure_loaded()

	if is_open():
		queue_free()
		return

	var shape = BoxShape3D.new()
	shape.size = Vector3(width, 14.0, 2.0)
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 7.0
	add_child(collision)

	wall = EmberWall.new(width)
	add_child(wall)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = sealed_text
	label.font_size = 36
	label.pixel_size = 0.03
	label.outline_size = 10
	label.modulate = Color(1.0, 0.75, 0.5)
	label.position.y = 12.0
	add_child(label)

	GameState.quest_changed.connect(_on_quest_changed)


func is_open() -> bool:

	match opens_when:
		"quest_complete":
			return GameState.quest_state == GameState.QUEST_COMPLETE
		_:
			return GameState.quest_accepted()


func _on_quest_changed():

	if not is_open():
		return

	GameState.quest_changed.disconnect(_on_quest_changed)
	Sfx.play("gate_open")
	collision_layer = 0
	label.visible = false

	wall.fade_to(0.0, 1.4).tween_callback(queue_free)
