shader_type canvas_item;

// The far wall of an underground room: dim rock with soft strata and a
// little ember glow in the cracks, darker the deeper the room.

uniform float depth = 1.0;

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
	vec2 px = UV * vec2(1280.0, 720.0);
	float n = noise(px / 120.0) * 0.6 + noise(px / 30.0) * 0.3 + noise(px / 8.0) * 0.1;
	float strata = noise(vec2(px.x / 260.0, px.y / 26.0));
	float dark = 1.0 - clamp(depth * 0.15, 0.0, 0.45);
	vec3 col = mix(vec3(0.05, 0.045, 0.06), vec3(0.11, 0.095, 0.12), n * 0.7 + strata * 0.3) * dark;
	// Hairline cracks with a faint ember warmth
	float crack = 1.0 - smoothstep(0.0, 0.025, abs(noise(px / 70.0) - 0.5));
	col += vec3(0.25, 0.08, 0.02) * crack * 0.35;
	COLOR = vec4(col, 1.0);
}
