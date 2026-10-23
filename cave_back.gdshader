shader_type canvas_item;

// The far wall of an underground room, as an ink wash: a warm, uneven
// ground tone that's lightest in the middle of the room, two layers of
// distant rock pillars in darker washes, each with a faint broken pen
// edge, and a few drips. Darker the deeper the room.

uniform float depth = 1.0;
uniform vec3 ink = vec3(0.045, 0.035, 0.05);

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

// Rock pillars: columns that come and go along x, narrowing as they rise
float pillars(vec2 px, float scale, float seed) {
	float n = noise(vec2(px.x / scale + seed, seed * 3.0)) * 0.7 + noise(vec2(px.x / (scale * 0.3) + seed, px.y / 400.0)) * 0.3;
	float height = 1.0 - px.y / 720.0;
	float v = n - height * 0.25 + 0.12;
	float fw = max(fwidth(v), 1e-4);
	return smoothstep(0.54 - fw, 0.54 + fw, v);
}

void fragment() {
	vec2 px = UV * vec2(1280.0, 720.0);
	float dark = 1.0 - clamp(depth * 0.1, 0.0, 0.35);

	// The ground tone: lit from the middle of the room, soft blotches of wash
	float wash = noise(px / 160.0) * 0.6 + noise(px / 55.0) * 0.4;
	float centre = 1.0 - smoothstep(0.15, 0.75, length((UV - vec2(0.5, 0.55)) * vec2(1.0, 1.3)));
	vec3 col = mix(vec3(0.17, 0.14, 0.15), vec3(0.34, 0.27, 0.24), centre * 0.7 + wash * 0.3);

	// Two layers of distant pillars, the nearer one darker
	float far = pillars(px, 260.0, 1.7);
	float near = pillars(px + vec2(400.0, 0.0), 180.0, 5.3);
	col = mix(col, col * 0.72, far);
	col = mix(col, col * 0.6, near);

	// Faint, broken pen edges on the pillars
	float edge_far = abs(dFdx(far)) + abs(dFdy(far));
	float edge_near = abs(dFdx(near)) + abs(dFdy(near));
	float broken = smoothstep(0.4, 0.6, noise(px / 30.0));
	col = mix(col, ink, clamp(edge_far * 0.6 + edge_near, 0.0, 1.0) * mix(0.35, 0.85, broken));

	// Drips down the wall
	float drip_x = abs(fract(px.x / 37.0 + noise(vec2(px.x / 37.0, 0.0))) - 0.5);
	float drip = (1.0 - smoothstep(0.0, 0.03, drip_x)) * smoothstep(0.55, 0.8, noise(vec2(px.x / 37.0, px.y / 120.0)));
	col = mix(col, ink, drip * 0.25);

	COLOR = vec4(col * dark, 1.0);
}
