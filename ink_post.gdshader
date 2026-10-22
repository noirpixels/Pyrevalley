shader_type canvas_item;

// Pyrevalley's graphic-novel look over the whole 2D scene (the v6 post
// pass, without depth):
//   - a muted, cold palette in which only ember oranges keep their colour
//   - soft tonal bands, like flat washes of ink
//   - ink lines where brightness jumps (silhouettes against the backdrop)
//   - cross-hatching in the darks, paper grain and a ragged vignette
// The HUD draws on a higher layer and stays clean.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 ink = vec3(0.035, 0.028, 0.045);
uniform vec3 shadow_tint = vec3(0.62, 0.64, 0.84);
uniform vec3 light_tint = vec3(1.08, 1.02, 0.9);
uniform float world_saturation = 0.5;
uniform float ember_saturation = 1.25;
uniform float band_strength = 0.35;
uniform float edge_strength = 0.6;
uniform float hatch_strength = 0.35;
uniform float grain = 0.05;
uniform float vignette = 0.6;
uniform float intensity = 0.0;
uniform vec4 flash = vec4(1.0, 0.9, 0.7, 0.0);
// World offset of the camera, so hatching sticks to the world
uniform vec2 camera_px = vec2(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float lum_at(vec2 uv) {
	return dot(texture(screen_tex, uv).rgb, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 col = texture(screen_tex, uv).rgb;

	vec3 hsv = rgb2hsv(max(col, vec3(0.0)));
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float ember = (1.0 - smoothstep(0.08, 0.14, hsv.x)) + smoothstep(0.95, 0.99, hsv.x);
	ember *= smoothstep(0.5, 0.75, hsv.y) * smoothstep(0.5, 0.8, hsv.z);
	float sat = mix(world_saturation * (1.0 - intensity * 0.35), ember_saturation, ember);
	col = mix(vec3(lum), col, sat);

	float bands = 4.0;
	float banded = (floor(lum * bands) + smoothstep(0.35, 0.65, fract(lum * bands))) / bands;
	col *= mix(lum, banded, band_strength) / max(lum, 1e-4);
	float shade = smoothstep(0.05, 0.6, lum);
	col *= mix(shadow_tint, light_tint, shade);
	col = mix(col, col * 1.15 + vec3(0.04, 0.01, 0.0), ember);

	// Ink where brightness jumps
	float gx = lum_at(uv + vec2(px.x, 0.0)) - lum_at(uv - vec2(px.x, 0.0));
	float gy = lum_at(uv + vec2(0.0, px.y)) - lum_at(uv - vec2(0.0, px.y));
	float edge = smoothstep(0.12, 0.3, length(vec2(gx, gy)));
	col = mix(col, ink, edge * edge_strength * (1.0 - ember));

	// Hatching in the darks, pinned to the world
	vec2 world = FRAGCOORD.xy + camera_px;
	float wobble = noise(world / 40.0) * 0.35;
	float h1 = abs(fract((world.x + world.y) / 9.0 + wobble) - 0.5);
	float hatch = (1.0 - smoothstep(0.1, 0.18, h1)) * (1.0 - smoothstep(0.06, 0.2, lum));
	col = mix(col, ink, hatch * hatch_strength * (1.0 - ember));

	float g = hash(floor(FRAGCOORD.xy) + floor(TIME * 12.0));
	col *= 1.0 + (g - 0.5) * grain;

	vec2 c = uv - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float ragged = noise(uv * 9.0 + TIME * 0.05) * 0.08;
	float v = smoothstep(0.6 - intensity * 0.12, 1.1, length(c) + ragged);
	col = mix(col, ink, v * vignette);

	col = mix(col, flash.rgb, flash.a);
	COLOR = vec4(col, 1.0);
}
