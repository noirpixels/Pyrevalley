extends CanvasLayer

# Draws ink_post.gdshader over the scene (under the HUD), and pushes the
# look harder in the boss fight and when Veyl is badly hurt. flash()
# whites out the frame for a moment on big hits.

var rect: ColorRect
var mat: ShaderMaterial
var intensity: float = 0.0
var flash_color: Color = Color(1, 1, 1, 0)


func _ready():

	add_to_group("ink_post")
	layer = 5
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = preload("res://ink_post.gdshader")
	rect.material = mat
	add_child(rect)


func _process(delta):

	var target = 0.6 if GameState.boss_fight else 0.0
	var player = get_tree().get_first_node_in_group("player")
	if player and player.health < player.max_health * 0.3:
		target = max(target, 0.8)
	intensity = move_toward(intensity, target, delta * 0.8)
	mat.set_shader_parameter("intensity", intensity)
	flash_color.a = move_toward(flash_color.a, 0.0, delta * 4.0)
	mat.set_shader_parameter("flash", flash_color)
	var cam = get_viewport().get_camera_2d()
	if cam:
		mat.set_shader_parameter("camera_px", cam.get_screen_center_position() * Vector2(1, -1))


static func flash(tree: SceneTree, color: Color, strength: float):

	var post = tree.get_first_node_in_group("ink_post")
	if post:
		post.flash_color = Color(color.r, color.g, color.b, max(post.flash_color.a, strength))
