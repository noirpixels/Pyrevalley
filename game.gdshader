shader_type spatial;
render_mode specular_disabled;

// Emberwood forest floor.
// The six painted textures come in as a Texture2DArray (ground_textures.gd)
// in order: grass, tall grass, flower grass, dirt, rocks, mixed.
// Tiles are cross-faded so their borders and the grid never show; layers are
// picked by organic fbm patches; a worn path winds up the level; the floor darkens outside the playable strip;
// and the painted detail is turned into a bump so it catches the low sun.

uniform sampler2DArray terrain_textures : source_color, filter_linear_mipmap_anisotropic;
uniform float texture_scale = 10.0;
uniform float patch_scale = 0.05;
uniform float blend_hardness : hint_range(0.01, 0.2) = 0.05;
uniform float bump_strength = 0.6;
// Emberwood-local layout, matching emberwood.gd
uniform float mesh_offset_z = -20.0;
uniform float half_width = 40.0;
uniform float path_width = 3.5;

varying vec3 local_pos;

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

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 uv = UV * texture_scale;

	// Organic patches choose the layer (same proportions as before)
	float n = fbm(UV * patch_scale);
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

	// A worn dirt path winding up the level
	float z = local_pos.z + mesh_offset_z;
	float centre = sin(z * 0.045) * 4.0 + sin(z * 0.11 + 1.3) * 1.5;
	float width = path_width * (0.8 + 0.5 * value_noise(vec2(z * 0.08, 3.0)));
	float path = 1.0 - smoothstep(width * 0.6, width, abs(local_pos.x - centre));
	path *= 0.6 + 0.4 * value_noise(local_pos.xz * 0.6);
	col = mix(col, sample_layer(uv, 3.0) * vec3(0.95, 0.88, 0.8), clamp(path, 0.0, 1.0));

	// Large, soft colour drift so the floor never reads as one flat swatch
	float macro = fbm(local_pos.xz * 0.025 + vec2(40.0));
	col *= mix(vec3(0.78, 0.8, 0.7), vec3(1.08, 1.04, 0.95), macro);

	// Beyond the playable strip the forest floor goes dark and needle-strewn
	float edge = smoothstep(half_width - 6.0, half_width + 4.0, abs(local_pos.x));
	col = mix(col, col * vec3(0.38, 0.36, 0.32), edge);

	// Muted earth tones; the post pass keeps vivid orange for embers only
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, 0.6);

	ALBEDO = col;
	ROUGHNESS = 1.0;

	// Bump from the painted detail (screen-space derivative bump mapping)
	float h = dot(col, vec3(0.299, 0.587, 0.114)) * bump_strength;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
