extends RefCounted

# The kinds of block a mining site (voxel_site.gd) is built from: soil and
# rock in realistic layers, with ore where it really forms. Each block has
#   hardness  the pickaxe tier needed to break it well (0 = by hand)
#   hits      how much striking it takes at that tier's power
#   drop      what breaking it leaves on the ground (chance: how often)
# Textures are pixel art drawn here into one atlas (voxel.gdshader).

const SIZE = 4.0
const TILE = 16

enum {
	AIR, TOPSOIL, DIRT, CLAY, GRAVEL, TIN_GRAVEL, SANDSTONE, LIMESTONE, COAL,
	MALACHITE, GRANITE, CASSITERITE, HEMATITE, BASALT, EMBERSTONE, ASH, BEDROCK,
}

# base: rock colour; fleck: ore or grain colour; flecks: how much of it;
# glow: Emberstone's veins burn
const DEFS = {
	TOPSOIL: {"name": "Topsoil", "hardness": 0, "hits": 2.0, "drop": "Flint", "chance": 0.1, "base": Color(0.32, 0.24, 0.16), "fleck": Color(0.22, 0.17, 0.12), "flecks": 0.2, "top": Color(0.2, 0.28, 0.16)},
	DIRT: {"name": "Dirt", "hardness": 0, "hits": 2.0, "drop": "Flint", "chance": 0.08, "base": Color(0.33, 0.24, 0.16), "fleck": Color(0.24, 0.18, 0.12), "flecks": 0.25},
	CLAY: {"name": "Clay", "hardness": 0, "hits": 3.0, "drop": "Clay", "chance": 1.0, "base": Color(0.58, 0.36, 0.24), "fleck": Color(0.66, 0.44, 0.3), "flecks": 0.15},
	GRAVEL: {"name": "Gravel", "hardness": 0, "hits": 2.0, "drop": "Flint", "chance": 0.4, "base": Color(0.45, 0.43, 0.42), "fleck": Color(0.3, 0.29, 0.29), "flecks": 0.45},
	TIN_GRAVEL: {"name": "Tin-bearing Gravel", "hardness": 0, "hits": 3.0, "drop": "Tin Ore", "chance": 1.0, "base": Color(0.45, 0.43, 0.42), "fleck": Color(0.16, 0.14, 0.18), "flecks": 0.35},
	SANDSTONE: {"name": "Sandstone", "hardness": 1, "hits": 4.0, "drop": "Stone", "chance": 1.0, "base": Color(0.66, 0.54, 0.38), "fleck": Color(0.58, 0.46, 0.32), "flecks": 0.3},
	LIMESTONE: {"name": "Limestone", "hardness": 1, "hits": 5.0, "drop": "Stone", "chance": 1.0, "base": Color(0.68, 0.66, 0.6), "fleck": Color(0.58, 0.56, 0.5), "flecks": 0.25},
	COAL: {"name": "Coal Seam", "hardness": 1, "hits": 5.0, "drop": "Coal", "chance": 1.0, "base": Color(0.36, 0.34, 0.32), "fleck": Color(0.08, 0.08, 0.09), "flecks": 0.55},
	MALACHITE: {"name": "Malachite", "hardness": 1, "hits": 6.0, "drop": "Copper Ore", "chance": 1.0, "base": Color(0.66, 0.64, 0.58), "fleck": Color(0.22, 0.62, 0.42), "flecks": 0.4},
	GRANITE: {"name": "Granite", "hardness": 2, "hits": 7.0, "drop": "Stone", "chance": 1.0, "base": Color(0.55, 0.5, 0.5), "fleck": Color(0.25, 0.23, 0.25), "flecks": 0.35},
	CASSITERITE: {"name": "Cassiterite", "hardness": 2, "hits": 8.0, "drop": "Tin Ore", "chance": 1.0, "base": Color(0.55, 0.5, 0.5), "fleck": Color(0.14, 0.12, 0.16), "flecks": 0.45},
	HEMATITE: {"name": "Hematite", "hardness": 2, "hits": 8.0, "drop": "Iron Ore", "chance": 1.0, "base": Color(0.42, 0.36, 0.36), "fleck": Color(0.6, 0.22, 0.14), "flecks": 0.45},
	BASALT: {"name": "Basalt", "hardness": 3, "hits": 9.0, "drop": "Stone", "chance": 1.0, "base": Color(0.2, 0.19, 0.21), "fleck": Color(0.13, 0.12, 0.14), "flecks": 0.3},
	EMBERSTONE: {"name": "Emberstone", "hardness": 3, "hits": 10.0, "drop": "Emberstone", "chance": 1.0, "base": Color(0.17, 0.15, 0.16), "fleck": Color(1.0, 0.45, 0.1), "flecks": 0.3, "glow": true},
	ASH: {"name": "Ash", "hardness": 0, "hits": 2.0, "drop": "", "chance": 0.0, "base": Color(0.3, 0.28, 0.28), "fleck": Color(0.4, 0.38, 0.37), "flecks": 0.3},
	BEDROCK: {"name": "Bedrock", "hardness": 99, "hits": INF, "drop": "", "chance": 0.0, "base": Color(0.1, 0.09, 0.1), "fleck": Color(0.16, 0.15, 0.16), "flecks": 0.4},
}

# Atlas columns: one per block kind (index = block id), plus the grassy
# top of topsoil in the last column
const COLUMNS = 18
const GRASS_TOP = 17

static var _atlas: ImageTexture = null


static func def(block: int) -> Dictionary:
	return DEFS.get(block, {})


static func breakable(block: int) -> bool:
	return block != AIR and block != BEDROCK


# Which atlas tile a face shows
static func tile(block: int, face_up: bool) -> int:
	return GRASS_TOP if block == TOPSOIL and face_up else block


# Pixel-art tiles: speckled rock with darker edges; ore as clustered
# flecks; Emberstone's veins marked in alpha so the shader can make them
# glow. Seeded, so every run draws the same.
static func atlas() -> ImageTexture:

	if _atlas:
		return _atlas
	var img = Image.create(TILE * COLUMNS, TILE, false, Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new()
	rng.seed = 1337
	for block in DEFS:
		draw_tile(img, block, DEFS[block], rng)
	var grass = DEFS[TOPSOIL].duplicate()
	grass["base"] = DEFS[TOPSOIL]["top"]
	grass["fleck"] = Color(0.28, 0.38, 0.2)
	draw_tile(img, GRASS_TOP, grass, rng)
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


static func draw_tile(img: Image, column: int, d: Dictionary, rng: RandomNumberGenerator):

	var ox = column * TILE
	var glow = d.get("glow", false)
	for y in TILE:
		for x in TILE:
			var c: Color = d["base"]
			c = c.lightened(rng.randf_range(-0.06, 0.06)) if rng.randf() < 0.5 else c.darkened(rng.randf_range(0.0, 0.08))
			var alpha = 1.0
			if rng.randf() < d["flecks"] * 0.5:
				c = d["fleck"]
				if glow:
					alpha = 0.0
			# Edges a touch darker so blocks read as blocks
			if x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1:
				c = c.darkened(0.25)
			img.set_pixel(ox + x, y, Color(c.r, c.g, c.b, alpha))
	# Ore and grain gather into clumps rather than single pixels
	var clumps = int(d["flecks"] * 6.0)
	for i in clumps:
		var cx = rng.randi_range(2, TILE - 4)
		var cy = rng.randi_range(2, TILE - 4)
		for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			if rng.randf() < 0.8:
				img.set_pixel(ox + cx + p.x, cy + p.y, Color(d["fleck"].r, d["fleck"].g, d["fleck"].b, 0.0 if glow else 1.0))
