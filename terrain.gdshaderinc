// Emberwood's painted forest floor, shared by the ground (game.gdshader)
// and the grassy tops of the mining sites (dig_site.gdshader) so the two
// meet without a seam. ground_colour() takes an Emberwood-local x/z.
// The six painted textures come in as a Texture2DArray (ground_textures.gd)
// in order: grass, tall grass, flower grass, dirt, rocks, mixed.
// Tiles are cross-faded so their borders and the grid never show; layers are
// picked by organic fbm patches; worn paths (painted by emberwood.gd from
// world_gen.gd) wind between the story's places; the floor greys toward ash
// in the Deep Forest and goes dark outside the playable area.

uniform sampler2DArray terrain_textures : source_color, filter_linear_mipmap_anisotropic;
uniform float texture_scale = 10.0;
uniform float patch_scale = 0.05;
uniform float blend_hardness : hint_range(0.01, 0.2) = 0.05;
// The ground plane's size, and how far it sits along z from Emberwood's origin
uniform vec2 ground_size = vec2(300.0, 380.0);
uniform float mesh_offset_z = -20.0;
// Path strength over the ground plane
uniform sampler2D path_mask : hint_default_black, filter_linear, repeat_disable;
// The Deep Forest's edge: its z every deep_step along x from deep_line_start
// (world_gen.gd), and how far past it the floor is fully ashen
uniform float deep_line[69];
uniform float deep_line_start = -136.0;
uniform float deep_step = 4.0;
uniform float deep_span = 70.0;
uniform float deep_strength = 0.0;
// The playable area: x0, z0, x1, z1 (Emberwood space)
uniform vec4 world_bounds = vec4(-10000.0, -10000.0, 10000.0, 10000.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

// The painted textures are tiles with ragged transparent borders, so they
// can't simply repeat. Each grid cell gets a randomly shifted, mirrored window
// of the tile's solid interior spread over the 2x2 cells around it; the four
// nearest copies are cross-faded to nothing before their borders.
vec3 sample_layer(vec2 uv, float layer) {
	vec2 p = uv * 2.2;
	vec2 base = floor(p - 0.5);
	vec2 grad_x = dFdx(p) * 0.36;
	vec2 grad_y = dFdy(p) * 0.36;
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec2 centre = base + vec2(float(i), float(j)) + 0.5;
			vec2 d = p - centre;
			float w = (1.0 - abs(d.x)) * (1.0 - abs(d.y));
			w = w * w * w;
			float flip = hash(centre + layer * 13.0) < 0.5 ? -1.0 : 1.0;
			// A different window into the tile for every copy breaks the lattice
			vec2 shift = (vec2(hash(centre * 1.7), hash(centre * 2.3 + 5.0)) - 0.5) * 0.12;
			vec2 local = vec2(d.x * flip, d.y) * 0.36 + 0.5 + shift;
			vec4 tex = textureGrad(terrain_textures, vec3(local, layer), grad_x, grad_y);
			w *= tex.a;
			sum += tex.rgb * w;
			total += w;
		}
	}
	return sum / max(total, 1e-4);
}

// 0 in the outer forest, 1 deep past the Deep Forest's edge
float deepness(vec2 l) {
	float f = clamp((l.x - deep_line_start) / deep_step, 0.0, 67.999);
	int i = int(f);
	float edge = mix(deep_line[i], deep_line[i + 1], fract(f));
	return clamp((edge - l.y) / deep_span, 0.0, 1.0) * deep_strength;
}

vec3 ground_colour(vec2 l) {
	// The ground plane's own space, and its 0..1 coordinates
	vec2 m = vec2(l.x, l.y - mesh_offset_z);
	vec2 plane_uv = m / ground_size + 0.5;
	vec2 uv = plane_uv * texture_scale;

	// Organic patches choose the layer
	float n = fbm(plane_uv * patch_scale);
	n = clamp((n - 0.5) * 2.0 + 0.5, 0.0, 1.0);
	float thresholds[5] = float[](0.40, 0.50, 0.58, 0.68, 0.75);
	float layer = 5.0;
	float next_layer = 5.0;
	float weight = 0.0;
	for (int i = 0; i < 5; i++) {
		if (n < thresholds[i]) {
			layer = float(i);
			next_layer = float(i + 1);
			weight = smoothstep(thresholds[i] - blend_hardness, thresholds[i], n);
			break;
		}
	}
	vec3 col = sample_layer(uv, layer);
	if (weight > 0.0) {
		col = mix(col, sample_layer(uv, next_layer), weight);
	}

	// Worn dirt paths, ragged at the edges
	float path = texture(path_mask, plane_uv).r;
	path *= 0.6 + 0.4 * value_noise(m * 0.6);
	col = mix(col, sample_layer(uv, 3.0) * vec3(0.95, 0.88, 0.8), clamp(path, 0.0, 1.0));

	// Large, soft colour drift so the floor never reads as one flat swatch
	float macro = fbm(m * 0.025 + vec2(40.0));
	col *= mix(vec3(0.78, 0.8, 0.7), vec3(1.08, 1.04, 0.95), macro);

	// Ash settles over the Deep Forest's floor
	float deep = deepness(l);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * vec3(0.66, 0.62, 0.62), deep * 0.55);
	col *= 1.0 - deep * 0.15;

	// Beyond the playable area the forest floor goes dark and needle-strewn
	float outside = max(max(world_bounds.x - l.x, l.x - world_bounds.z), max(world_bounds.y - l.y, l.y - world_bounds.w));
	col = mix(col, col * vec3(0.38, 0.36, 0.32), smoothstep(-6.0, 4.0, outside));

	// Muted earth tones; the post pass keeps vivid orange for embers only
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	return mix(vec3(grey), col, 0.6);
}
