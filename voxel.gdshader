shader_type spatial;
render_mode cull_back, specular_disabled;

// Mining site blocks (voxel_site.gd). Pixel-art tiles from one atlas
// (blocks.gd); alpha in the atlas marks Emberstone veins, which glow.
// COLOR.a is how damaged a block is: cracks spread across it as it takes
// hits. Like occluder.gdshader, blocks between the camera and Veyl dither
// away in a bubble so vae stays visible down a tunnel.

global uniform vec3 player_position;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float fade_radius = 12.0;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.97;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	// Emberstone veins: bright enough to survive the ink post pass
	EMISSION = tex.rgb * (1.0 - tex.a) * 2.5;

	// Cracks: pixel cells along jagged lines go dark as damage rises
	float damage = 1.0 - COLOR.a;
	if (damage > 0.01) {
		vec2 cell = floor(fract(UV * vec2(18.0, 1.0)) * 16.0);
		float line = abs(fract(cell.x * 0.37 + cell.y * 0.21 + hash(floor(UV * vec2(18.0, 1.0))) * 3.0) - 0.5);
		if (line < damage * 0.22 && hash(cell + 3.1) < 0.85) {
			ALBEDO *= 0.25;
		}
	}

	vec3 player_view = (VIEW_MATRIX * vec4(player_position, 1.0)).xyz;
	float in_front = smoothstep(0.5, 3.0, VERTEX.z - player_view.z);
	float bubble = 1.0 - smoothstep(fade_radius * 0.55, fade_radius, length(VERTEX.xy - player_view.xy));
	float fade = in_front * bubble * fade_amount;
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	if (fade > 0.0 && fade * 16.0 > BAYER[p.y * 4 + p.x] + 0.5) {
		discard;
	}
}
