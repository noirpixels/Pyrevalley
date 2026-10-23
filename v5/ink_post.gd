extends MeshInstance3D

# Draws ink_post.gdshader as a full-screen quad (the vertex shader puts it
# over the whole view wherever the node sits), and
# pushes the look harder during the boss fight and when Veyl is hurt.
# InkPost.flash() whites out the frame for a moment on big hits.

const SHADER = preload("res://ink_post.gdshader")

var mat: ShaderMaterial
var intensity: float = 0.0
var flash_color: Color = Color(1, 1, 1, 0)


func _ready():

	add_to_group("ink_post")
	var quad = QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	# First in the transparent pass, so effects drawn after it stay bright
	mat.render_priority = -100
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader puts it over the whole screen; never cull it
	extra_cull_margin = 16384.0


func _process(delta):

	var target = 0.0
	if GameState.boss_fight:
		target = 0.6
	var player = get_tree().get_first_node_in_group("player")
	if player and player.health < player.max_health * 0.3:
		target = max(target, 0.8)
	intensity = move_toward(intensity, target, delta * 0.8)
	mat.set_shader_parameter("intensity", intensity)

	flash_color.a = move_toward(flash_color.a, 0.0, delta * 4.0)
	mat.set_shader_parameter("flash", flash_color)


static func flash(tree: SceneTree, color: Color, strength: float):

	var post = tree.get_first_node_in_group("ink_post")
	if post:
		post.flash_color = Color(color.r, color.g, color.b, max(post.flash_color.a, strength))
