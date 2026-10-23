extends MeshInstance3D

# Feeds the terrain textures into game.gdshader's Texture2DArray uniform.
# Layer order matches the shader: grass, tall grass, flower grass, dirt,
# rocks, mixed.

@export var terrain_layers: Array[Texture2D] = []
@export var texture_scale: float = 50.0
@export var patch_scale: float = 12.0


func _ready():

	if terrain_layers.is_empty():
		return

	# Layers must match exactly; import settings can pad or compress some
	var size = terrain_layers[0].get_size()
	var images: Array[Image] = []
	for tex in terrain_layers:
		var img = tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(int(size.x), int(size.y))
		img.generate_mipmaps()
		images.append(img)

	var array = Texture2DArray.new()
	array.create_from_images(images)

	var mat = get_active_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("terrain_textures", array)
		mat.set_shader_parameter("texture_scale", texture_scale)
		mat.set_shader_parameter("patch_scale", patch_scale)
