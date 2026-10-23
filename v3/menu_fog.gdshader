shader_type canvas_item;
render_mode blend_premul_alpha;

// Main menu atmosphere: drifting low mist, the sun's glow and a vignette.

uniform float fog_strength = 1.0;
uniform float vignette = 0.0;
uniform float glow = 0.0;
uniform vec2 sun = vec2(0.5, 0.6);

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * 3.0, uv.y * 7.0);
	float n = fbm(p + vec2(TIME * 0.025, 0.0)) * 0.6 + fbm(p * 1.7 + vec2(-TIME * 0.04, 3.0)) * 0.5;
	float band = smoothstep(0.55, 0.8, uv.y);
	float fog = band * smoothstep(0.35, 0.85, n) * 0.6 * fog_strength;

	float d = distance(uv * vec2(1.78, 1.0), sun * vec2(1.78, 1.0));
	vec3 mist = mix(vec3(0.45, 0.22, 0.28), vec3(1.0, 0.6, 0.35), exp(-d * 2.5));
	vec3 light = vec3(1.0, 0.55, 0.25) * exp(-d * 4.0) * (0.16 + 0.04 * sin(TIME * 1.3)) * glow;

	float vig = smoothstep(0.4, 1.0, length((uv - 0.5) * vec2(1.3, 1.1))) * vignette;
	// Premultiplied: mist and glow add light, the vignette darkens what is behind.
	COLOR = vec4(mist * fog + light, fog + vig * (1.0 - fog));
}
