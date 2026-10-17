shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A curtain of fire drawn like a comic panel: flat, hard-edged tongues in
// three bands (deep red, ember orange, white-hot core) licking upward,
// with an ink line round each tongue. UV.y runs 0 at the top to 1 at the base.

uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float speed = 1.4;
uniform float columns = 7.0;
uniform vec3 deep = vec3(0.42, 0.05, 0.03);
uniform vec3 mid = vec3(1.0, 0.42, 0.06);
uniform vec3 core = vec3(1.0, 0.9, 0.6);
uniform vec3 ink = vec3(0.035, 0.028, 0.045);

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

void fragment() {
	float h = 1.0 - UV.y;
	vec2 p = vec2(UV.x * columns, h * 2.2 - TIME * speed);
	float n = noise(p) * 0.6 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3) * 0.1;
	// Tongues: tall in some columns, short in others, always flickering
	float tongue = n + 0.55 * noise(vec2(UV.x * columns * 0.5, TIME * 0.6)) - h * 1.25;
	tongue -= (1.0 - strength) * 1.2;
	// Lower toward the ends so the wall doesn't stop in a hard edge
	float across = abs(UV.x * 2.0 - 1.0);
	tongue -= smoothstep(0.6, 1.0, across + noise(vec2(h * 3.0, TIME)) * 0.1) * 1.3;
	// Ragged base, sunk into the coals
	if (h < 0.04 + 0.05 * noise(vec2(UV.x * columns * 3.0, 1.0))) {
		tongue = min(tongue, 0.3);
	}

	float t_outer = 0.0;
	float t_mid = 0.22;
	float t_core = 0.45;
	float edge = 0.04;
	if (tongue < t_outer - edge) {
		discard;
	}
	vec3 col = ink;
	if (tongue > t_outer) col = deep;
	if (tongue > t_mid) col = mid;
	if (tongue > t_core) col = core;
	ALBEDO = col;
	ALPHA = 1.0;
}
