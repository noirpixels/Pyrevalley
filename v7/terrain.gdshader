shader_type canvas_item;

// Draws terrain.gd's density field: solid where it's above one half. The
// look is a pen-and-wash drawing rather than a texture:
//   - a brushed ink outline that swells and thins along its length
//   - flat washes, lit at the lip of the ground and darker deeper in
//   - broken pen lines for strata, a few pebbles, hatching only deep inside
//   - grass tufts in ink along the tops of the ground
// Channels: R solid, G earth, B rock, A ember (the rest bedrock). The
// texture is filtered linearly, so the 10 px cells blend into smooth curves.

uniform vec2 cells = vec2(128.0, 72.0);
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

void fragment() {
	vec4 d = texture(TEXTURE, UV);
	float dens = d.r;
	vec2 cell_uv = 1.0 / cells;
	// Room pixels, so every mark stays put on the ground
	vec2 px = UV * cells * 10.0;
	float aa = max(fwidth(dens), 0.002) * 1.2;
	float solid = smoothstep(0.5 - aa, 0.5 + aa, dens);

	// Up is open air here: the top of the ground
	float above = texture(TEXTURE, UV - vec2(0.0, 1.5 * cell_uv.y)).r;
	float top = 1.0 - smoothstep(0.35, 0.6, above);

	if (solid <= 0.001) {
		// Grass tufts: ink blades standing just above a top edge
		float below = texture(TEXTURE, UV + vec2(0.0, 1.2 * cell_uv.y)).r;
		float on_top = smoothstep(0.5, 0.7, below) * top * (1.0 - d.a);
		float clump = smoothstep(0.3, 0.6, noise(vec2(px.x / 40.0, 3.1)));
		float blade = pow(abs(sin(px.x * 0.55 + noise(vec2(px.x / 5.0, 0.0)) * 2.0)), 3.0);
		float reach = 0.5 - (0.04 + blade * 0.11) * clump;
		float tuft = smoothstep(reach - aa, reach + aa, dens) * on_top;
		if (tuft <= 0.01) {
			discard;
		}
		COLOR = vec4(ink, tuft);
	} else {
		float rest = clamp(1.0 - d.g - d.b - d.a, 0.0, 1.0);
		vec3 bedrock = vec3(0.15, 0.125, 0.13);
		vec3 earth = vec3(0.36, 0.25, 0.16);
		vec3 rock = vec3(0.42, 0.4, 0.4);
		float pulse = 0.8 + 0.2 * sin(TIME * 2.5 + px.x * 0.03);
		vec3 ember = mix(vec3(0.9, 0.28, 0.06), vec3(1.0, 0.72, 0.3), noise(px / 12.0)) * pulse;
		vec3 col = bedrock * rest + earth * d.g + rock * d.b + ember * d.a;
		float not_ember = 1.0 - d.a;

		// A soft wash: uneven, like watercolour drying, never noisy
		col *= 0.92 + noise(px / 60.0) * 0.16;
		// Lit lip just inside the edge, strongest on top surfaces
		float inner = smoothstep(0.5, 0.62, dens) * (1.0 - smoothstep(0.62, 0.8, dens));
		col = mix(col, col * 1.35 + vec3(0.03, 0.02, 0.0), inner * (0.12 + top * 0.88) * not_ember);
		// Deeper in, darker
		float deep = smoothstep(0.75, 1.0, dens);
		col *= mix(1.0, 0.62, deep * not_ember);

		// Strata as broken pen lines, gently wavy and mostly level
		float sv = fract(px.y / 34.0 + noise(px / vec2(140.0, 60.0)) * 1.4);
		float strata = (1.0 - smoothstep(0.0, 0.045, abs(sv - 0.5))) * smoothstep(0.4, 0.6, noise(px / vec2(70.0, 30.0)));
		col = mix(col, ink, strata * 0.55 * smoothstep(0.58, 0.7, dens) * not_ember);

		// A few pebbles: small inked rings
		vec2 pc = floor(px / 46.0);
		vec2 pf = px - (pc + vec2(hash(pc), hash(pc + 7.0)) * 0.6 + 0.2) * 46.0;
		float pr = 3.0 + hash(pc + 3.0) * 4.0;
		float pebble = (1.0 - smoothstep(0.8, 1.6, abs(length(pf * vec2(1.0, 1.4)) - pr))) * step(0.72, hash(pc + 11.0));
		col = mix(col, ink, pebble * 0.7 * smoothstep(0.6, 0.72, dens) * not_ember);

		// Hatching, only deep in the ground, as broken diagonal pen strokes
		float hv = abs(fract((px.x - px.y) / 7.0 + noise(px / 50.0) * 0.6) - 0.5);
		float hatch = (1.0 - smoothstep(0.08, 0.16, hv)) * smoothstep(0.3, 0.6, noise(px / vec2(18.0, 9.0)));
		col = mix(col, ink, hatch * 0.32 * smoothstep(0.9, 1.0, dens) * smoothstep(0.45, 0.7, noise(px / 120.0)) * not_ember);

		// The outline: a brush stroke that swells and thins along the edge
		float swell = noise(px / 70.0);
		float band = 0.035 + swell * 0.06 + top * 0.015;
		float edge = 1.0 - smoothstep(band * 0.7, band, dens - 0.5);
		col = mix(col, ink, edge * (1.0 - d.a * 0.7));

		COLOR = vec4(col, solid);
	}
}
