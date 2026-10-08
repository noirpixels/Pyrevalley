shader_type spatial;
render_mode cull_back, specular_disabled;

// Scenery that can stand between the camera and Veyl. Uses vertex colours
// for albedo, and dithers itself away in a bubble around Veyl when it is
// in front of them, so Veyl stays visible without being drawn over everything.

global uniform vec3 player_position;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float fade_radius = 10.0;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.8;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;

	vec3 player_view = (VIEW_MATRIX * vec4(player_position, 1.0)).xyz;
	// View space looks down -Z: larger z means closer to the camera
	float in_front = smoothstep(0.5, 3.0, VERTEX.z - player_view.z);
	float bubble = 1.0 - smoothstep(fade_radius * 0.55, fade_radius, length(VERTEX.xy - player_view.xy));
	float fade = in_front * bubble * fade_amount;

	ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
	if (fade > (BAYER[cell.x + cell.y * 4] + 0.5) / 16.0) {
		discard;
	}
}
