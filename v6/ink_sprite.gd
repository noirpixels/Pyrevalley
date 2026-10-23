extends RefCounted

# Gives a character sprite a pale rim of light on the edges facing the low
# sun (upper left), so dark figures still read against the dark forest
# floor. The post pass (ink_post.gdshader) already inks the silhouette.
# Sprites show at about a quarter of their texture size, so the rim is a
# few texels wide to survive that. Results are cached per texture.

const RIM = Color(1.0, 0.9, 0.72)
const RIM_WIDTH = 5

static var _cache = {}


# rim: how strongly the lit edge is brightened (0..1)
static func ink(source: Texture2D, rim: float = 0.55) -> Texture2D:

	var key = "%s:%s" % [source.resource_path if source.resource_path != "" else str(source.get_instance_id()), rim]
	if _cache.has(key):
		return _cache[key]
	var img = ink_image(load_image(source), rim)
	var tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func load_image(source: Texture2D) -> Image:

	var img = source.get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func ink_image(img: Image, rim: float) -> Image:

	var w = img.get_width()
	var h = img.get_height()
	var out = img.duplicate()
	var solid = func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and img.get_pixel(x, y).a > 0.5

	for y in h:
		for x in w:
			if not solid.call(x, y):
				continue
			# How close the open air is toward the light; nearer = brighter
			for r in range(1, RIM_WIDTH + 1):
				if not solid.call(x - r, y - r) or not solid.call(x, y - r - 1):
					var c = img.get_pixel(x, y)
					var lit = c.lerp(RIM, rim * (1.0 - float(r - 1) / RIM_WIDTH))
					lit.a = c.a
					out.set_pixel(x, y, lit)
					break
	return out
