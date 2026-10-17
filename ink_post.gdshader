shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Embervale's graphic-novel look, drawn over the opaque scene by a
// full-screen quad on the camera (ink_post.gd):
//   - ink outlines wherever depth jumps (silhouettes of trees, rocks,
//     creatures, Veyl)
//   - a muted, cold palette in which only ember oranges keep their colour
//   - soft tonal bands, like flat washes of ink
//   - cross-hatching in the shadows, anchored to the world so it doesn't
//     slide over the scene as the camera moves
//   - paper grain and a ragged ink vignette
// Transparent effects (slashes, sparks, embers) draw after this and stay
// bright on top of it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 ink = vec3(0.035, 0.028, 0.045);
uniform vec3 shadow_tint = vec3(0.6, 0.62, 0.82);
uniform vec3 light_tint = vec3(1.1, 1.03, 0.9);
// How much colour survives outside the ember hues (0 = grey)
uniform float world_saturation = 0.42;
uniform float ember_saturation = 1.25;
uniform float outline_width = 1.5;
// World units of depth jump that count as an edge
uniform float outline_depth = 0.35;
uniform float outline_strength = 0.92;
uniform float hatch_spacing = 0.32;
uniform float hatch_strength = 0.55;
uniform float band_strength = 0.45;
uniform float grain = 0.05;
uniform float vignette = 0.7;
// 0..1: the boss fight and low health push the look harder
uniform float intensity = 0.0;
// Flash of the whole frame, for big hits
uniform vec4 flash = vec4(1.0, 0.9, 0.7, 0.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

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

// View-space position of the scene at a screen point
vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

float view_depth(vec2 uv, mat4 inv_proj) {
	return -view_pos(uv, inv_proj).z;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float res_scale = VIEWPORT_SIZE.y / 900.0;
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;

	// ---- Palette: cold and muted, embers keep their fire ----
	vec3 hsv = rgb2hsv(max(col, vec3(0.0)));
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// Orange/red hues (0..0.12 and the wrap near 1) that are already vivid
	float ember = (1.0 - smoothstep(0.08, 0.14, hsv.x)) + smoothstep(0.95, 0.99, hsv.x);
	// Only bright, vivid orange counts: glowing things, not dirt
	ember *= smoothstep(0.5, 0.75, hsv.y) * smoothstep(0.55, 0.85, hsv.z);
	float sat = mix(world_saturation * (1.0 - intensity * 0.35), ember_saturation, ember);
	col = mix(vec3(lum), col, sat);

	// Flat washes: pull the brightness toward a few tonal bands
	float bands = 4.0;
	float banded = (floor(lum * bands) + smoothstep(0.35, 0.65, fract(lum * bands))) / bands;
	float wash = mix(lum, banded, band_strength);
	col *= wash / max(lum, 1e-4);

	// Shadows go cold blue-violet, lights warm parchment
	float shade = smoothstep(0.05, 0.6, lum);
	col *= mix(shadow_tint, light_tint, shade);
	// Embers glow regardless
	col = mix(col, col * 1.15 + vec3(0.04, 0.01, 0.0), ember);

	// ---- Cross-hatching in the dark, pinned to the world ----
	vec3 vp = view_pos(uv, INV_PROJECTION_MATRIX);
	vec3 wp = (INV_VIEW_MATRIX * vec4(vp, 1.0)).xyz;
	// Camera-plane coordinates of the surface: stable as the camera follows Veyl
	vec2 plane = vec2(dot(wp, INV_VIEW_MATRIX[0].xyz), dot(wp, INV_VIEW_MATRIX[1].xyz));
	float wobble = noise(plane * 1.3) * 0.35;
	float h1 = abs(fract((plane.x + plane.y) / hatch_spacing + wobble) - 0.5);
	float h2 = abs(fract((plane.x - plane.y) / hatch_spacing + wobble * 0.7) - 0.5);
	float line_w = 0.1;
	float hatch1 = 1.0 - smoothstep(line_w, line_w + 0.08, h1);
	float hatch2 = 1.0 - smoothstep(line_w, line_w + 0.08, h2);
	float dark = 1.0 - smoothstep(0.08, 0.32, lum);
	float darker = 1.0 - smoothstep(0.03, 0.14, lum);
	float hatch = max(hatch1 * dark, hatch2 * darker) * hatch_strength * (1.0 - ember);
	col = mix(col, ink, hatch);

	// ---- Ink outlines where depth jumps ----
	float w = outline_width * res_scale;
	float d0 = view_depth(uv, INV_PROJECTION_MATRIX);
	float edge = 0.0;
	for (int i = 0; i < 8; i++) {
		vec2 o = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
				vec2(0.7, 0.7), vec2(-0.7, 0.7), vec2(0.7, -0.7), vec2(-0.7, -0.7))[i] * px * w;
		float d = view_depth(uv + o, INV_PROJECTION_MATRIX);
		// Both sides of a depth jump are inked, for a bold brush line
		edge = max(edge, smoothstep(outline_depth, outline_depth * 2.0, abs(d - d0)));
	}
	// Ragged, brush-like line weight
	edge *= 0.75 + 0.25 * noise(plane * 6.0);
	col = mix(col, ink, edge * outline_strength);

	// ---- Paper grain and vignette ----
	float g = hash(floor(FRAGCOORD.xy / max(res_scale, 1.0)) + floor(TIME * 12.0));
	col *= 1.0 + (g - 0.5) * grain;
	float fibre = noise(FRAGCOORD.xy / (3.0 * res_scale));
	col *= 1.0 - fibre * grain * 0.6;

	vec2 c = uv - 0.5;
	c.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float ragged = noise(uv * 9.0 + TIME * 0.05) * 0.08;
	float v = smoothstep(0.55 - intensity * 0.12, 1.05, length(c) + ragged);
	col = mix(col, ink, v * vignette);

	col = mix(col, flash.rgb, flash.a);
	ALBEDO = col;
}
