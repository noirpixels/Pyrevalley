extends RefCounted

# The earth and rock a mining site (dig_site.gd) is made of: soil and rock
# in realistic layers, with ore where it really forms. Each material has
#   hardness  the pickaxe tier needed to break it well (0 = by hand)
#   hits      how much striking it takes at that tier's power (harder rock
#             gives up less to each strike)
#   drop      what breaking it leaves on the ground (chance: how often)
# base is the rock's colour; fleck the ore or grain in it, flecks how much;
# glow: Emberstone's veins burn (dig_site.gdshader).

enum {
	AIR, TOPSOIL, DIRT, CLAY, GRAVEL, TIN_GRAVEL, SANDSTONE, LIMESTONE, COAL,
	MALACHITE, GRANITE, CASSITERITE, HEMATITE, BASALT, EMBERSTONE, ASH, BEDROCK,
}

const DEFS = {
	TOPSOIL: {"name": "Topsoil", "hardness": 0, "hits": 2.0, "drop": "Flint", "chance": 0.1, "base": Color(0.32, 0.24, 0.16), "fleck": Color(0.22, 0.17, 0.12), "flecks": 0.2},
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


static func def(material: int) -> Dictionary:
	return DEFS.get(material, {})


static func breakable(material: int) -> bool:
	return material != AIR and material != BEDROCK
