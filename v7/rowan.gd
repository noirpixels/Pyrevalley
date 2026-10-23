extends Node2D

# Rowan, who has lived at the edge of the Hollow longer than he'll say.
# He points Veyl the right way: the Cinderwing, the bronze, the Ashbound.

var time: float = 0.0
var sprite: Sprite2D


func _ready():

	add_to_group("interactable")
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture = load("res://NPCs/rowan.png")
	sprite.centered = false
	sprite.offset = Vector2(-sprite.texture.get_width() / 2.0, -sprite.texture.get_height())
	sprite.scale = Vector2(0.46, 0.46)
	add_child(sprite)
	z_index = -1


func prompt_text() -> String:
	return "Talk to Rowan"


func lines() -> Array:

	if GameState.boss_defeated:
		return ["The ash is settling. I can hear the forest again.", "Go on, Veyl. The Hollow's yours to wander now."]
	if GameState.has_ability("cinderwing"):
		return ["That feather... the Cinderwing took you, then. Good.",
			"The wall past the deep rooms won't stop you now. The Ashbound waits beyond it.",
			"Rest at the shrine past the wall before you face it."]
	return ["Another one woken by the embers. Rowan. I keep this shrine.",
		"The Ashbound walled the Hollow off. There's a stone too high to climb, deeper in.",
		"Somewhere below there's a feather of flame, the Cinderwing. It lifts those it chooses.",
		"And if you find copper and tin in the earth, the shrine's flame will make bronze of it. Bronze breaks rock."]


func interact(_player: Node):

	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.dialogue("Rowan", lines())


func _process(delta):

	time += delta
	sprite.scale.y = 0.46 * (1.0 + sin(time * 2.0) * 0.012)
