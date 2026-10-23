shader_type canvas_item;

// Draws terrain.gd's density field: solid where it's above one half, with
// a brushed ink edge along that line. Channels: R solid, G earth, B rock,
// A ember (the rest bedrock). The texture is filtered linearly, so the
// 10 px cells blend into smooth curves.

uniform vec2 cells = vec2(128.0, 72.0);
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
	vec4 d = texture(TEXTURE, UV);
	float dens = d.r;
	float aa = max(fwidth(dens), 0.002) * 1.2;
	float solid = smoothstep(0.5 - aa, 0.5 + aa, dens);
	if (solid <= 0.001) {
		discard;
	}

	// Room pixels, for texture that stays put on the rock
	vec2 px = UV * cells * 10.0;
	float grain = noise(px / 14.0) * 0.6 + noise(px / 4.0) * 0.4;
	float strata = noise(vec2(px.x / 90.0, px.y / 11.0));

	vec3 bedrock = mix(vec3(0.13, 0.12, 0.16), vec3(0.22, 0.2, 0.25), grain);
	bedrock *= 0.85 + strata * 0.3;
	vec3 earth = mix(vec3(0.3, 0.2, 0.13), vec3(0.44, 0.3, 0.19), grain);
	earth *= 0.85 + strata * 0.25;
	vec3 rock = mix(vec3(0.4, 0.4, 0.44), vec3(0.58, 0.57, 0.6), grain);
	float pulse = 0.75 + 0.25 * sin(TIME * 2.5 + px.x * 0.03);
	vec3 ember = mix(vec3(0.9, 0.25, 0.05), vec3(1.0, 0.7, 0.25), grain) * pulse;

	float rest = clamp(1.0 - d.g - d.b - d.a, 0.0, 1.0);
	vec3 col = bedrock * rest + earth * d.g + rock * d.b + ember * d.a;

	// Deeper in, darker: the field is 1 well inside and ~0.5 at the edge
	col *= mix(1.1, 0.8, smoothstep(0.55, 1.0, dens));

	// Ink along the edge, ragged like a brush
	float band = (0.07 + noise(px / 9.0) * 0.05);
	float edge = 1.0 - smoothstep(band * 0.6, band, dens - 0.5);
	col = mix(col, ink, edge * (1.0 - d.a * 0.7));

	COLOR = vec4(col, solid);
}
