extends RefCounted

# Pixel art for what Veyl holds: swords, spears, warhammers, pickaxes and
# axes in each material, drawn in code like the Rustblade (veyl_puppet.gd)
# so they need no imported files. Each points up from where the hand grips.
#   HeldArt.get_art(type, material) -> {"texture", "grip", "length"}
# Fists hold nothing.

const OUTLINE = Color(0.08, 0.06, 0.07)
const WOOD = Color(0.42, 0.28, 0.17)
const WOOD_DARK = Color(0.27, 0.17, 0.11)
const WRAP = Color(0.25, 0.17, 0.14)

# light, mid, dark, accent per material
const PALETTES = {
	"Stone": [Color(0.74, 0.74, 0.76), Color(0.52, 0.52, 0.55), Color(0.34, 0.34, 0.37), Color(0.4, 0.95, 0.5)],
	"Rusted": [Color(0.88, 0.86, 0.82), Color(0.64, 0.62, 0.6), Color(0.4, 0.38, 0.4), Color(0.55, 0.3, 0.18)],
	"Bronze": [Color(0.98, 0.78, 0.45), Color(0.8, 0.55, 0.28), Color(0.52, 0.33, 0.16), Color(0.95, 0.7, 0.35)],
	"Iron": [Color(0.86, 0.88, 0.92), Color(0.6, 0.63, 0.68), Color(0.36, 0.38, 0.43), Color(0.75, 0.78, 0.82)],
}

static var _cache = {}


static func get_art(type: String, material: String) -> Dictionary:

	var key = type + "/" + material
	if not _cache.has(key):
		var pal = PALETTES.get(material, PALETTES["Iron"])
		match type:
			"Spear":
				_cache[key] = spear(pal)
			"Warhammer":
				_cache[key] = hammer(pal)
			"Pickaxe":
				_cache[key] = pickaxe(pal)
			"Axe":
				_cache[key] = axe(pal)
			_:
				_cache[key] = sword(pal, material == "Rusted")
	return _cache[key]


# Same shape as the Rustblade; only the old one is pitted with rust
static func sword(pal: Array, rusty: bool) -> Dictionary:

	var img = blank(25, 98)
	for y in range(1, 78):
		var half = min(5, 1 + y / 4)
		for x in range(12 - half, 13 + half):
			var c = pal[1]
			if x <= 13 - half:
				c = pal[0]
			elif x >= 11 + half:
				c = pal[2]
			elif x == 12 and y > 18 and y < 72:
				c = pal[2].lerp(pal[1], 0.5)
			img.set_pixel(x, y, c)
	if rusty:
		for p in [Vector2i(14, 24), Vector2i(10, 38), Vector2i(15, 39), Vector2i(14, 40), Vector2i(10, 57), Vector2i(15, 66), Vector2i(9, 68)]:
			img.set_pixel(p.x, p.y, pal[3])
	var guard = Color(0.78, 0.46, 0.2) if rusty else pal[2]
	img.fill_rect(Rect2i(1, 77, 23, 5), guard)
	img.fill_rect(Rect2i(1, 81, 23, 1), guard.darkened(0.35))
	img.fill_rect(Rect2i(10, 82, 5, 10), WRAP)
	img.fill_rect(Rect2i(9, 92, 7, 4), guard)
	return finish(img, Vector2(12, 87))


static func spear(pal: Array) -> Dictionary:

	var img = blank(17, 150)
	# Ash-wood shaft
	img.fill_rect(Rect2i(7, 28, 3, 120), WOOD)
	img.fill_rect(Rect2i(9, 28, 1, 120), WOOD_DARK)
	# Leaf-shaped head and its socket
	for y in range(1, 28):
		var half = int(round(sin(clamp(y / 27.0, 0.0, 1.0) * PI * 0.85) * 5.0))
		for x in range(8 - half, 9 + half):
			img.set_pixel(x, y, pal[0] if x < 8 else (pal[2] if x > 9 else pal[1]))
	img.fill_rect(Rect2i(6, 26, 5, 5), pal[2])
	img.fill_rect(Rect2i(6, 100, 5, 8), WRAP)
	return finish(img, Vector2(8, 104))


static func hammer(pal: Array) -> Dictionary:

	var img = blank(39, 104)
	img.fill_rect(Rect2i(17, 18, 5, 84), WOOD)
	img.fill_rect(Rect2i(20, 18, 2, 84), WOOD_DARK)
	# A heavy squared head, darker on its striking faces
	img.fill_rect(Rect2i(2, 2, 35, 20), pal[1])
	img.fill_rect(Rect2i(2, 2, 35, 3), pal[0])
	img.fill_rect(Rect2i(2, 18, 35, 4), pal[2])
	img.fill_rect(Rect2i(2, 2, 3, 20), pal[2])
	img.fill_rect(Rect2i(34, 2, 3, 20), pal[2])
	img.fill_rect(Rect2i(16, 86, 7, 12), WRAP)
	return finish(img, Vector2(19, 92))


static func pickaxe(pal: Array) -> Dictionary:

	var img = blank(57, 92)
	img.fill_rect(Rect2i(26, 6, 5, 84), WOOD)
	img.fill_rect(Rect2i(29, 6, 2, 84), WOOD_DARK)
	# Curved head, a point at each end
	for x in range(2, 55):
		var t = (x - 28.5) / 26.5
		var y = int(round(4 + t * t * 9.0))
		var thick = int(round(lerp(5.0, 2.0, abs(t))))
		for dy in thick:
			img.set_pixel(x, y + dy, pal[0] if dy == 0 else (pal[2] if dy == thick - 1 else pal[1]))
	img.fill_rect(Rect2i(25, 3, 7, 9), pal[2])
	img.fill_rect(Rect2i(25, 78, 7, 10), WRAP)
	return finish(img, Vector2(28, 83))


static func axe(pal: Array) -> Dictionary:

	var img = blank(37, 92)
	img.fill_rect(Rect2i(8, 4, 5, 86), WOOD)
	img.fill_rect(Rect2i(11, 4, 2, 86), WOOD_DARK)
	# Bearded blade on one side, flaring to the edge
	for y in range(4, 34):
		var reach = int(round(lerp(6.0, 22.0, sin((y - 4) / 30.0 * PI))))
		for x in range(13, 13 + reach):
			var edge = x >= 13 + reach - 2
			img.set_pixel(x, y, pal[0] if edge else (pal[2] if y > 28 else pal[1]))
	img.fill_rect(Rect2i(6, 6, 9, 14), pal[2])
	img.fill_rect(Rect2i(7, 76, 7, 12), WRAP)
	return finish(img, Vector2(10, 82))


static func blank(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


# One-pixel dark outline round everything, like the rest of Veyl
static func finish(img: Image, grip: Vector2) -> Dictionary:

	var out = img.duplicate()
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and img.get_pixel(q.x, q.y).a > 0.0:
					out.set_pixel(x, y, OUTLINE)
					break
	return {"texture": ImageTexture.create_from_image(out), "grip": grip, "length": grip.y}
