shader_type spatial;
render_mode cull_back, specular_disabled;

// Mining site earth (dig_site.gd). COLOR is the rock's colour (alpha: its
// veins glow, for Emberstone); CUSTOM0 the ore or grain flecked through it
// (alpha: how much); UV2.x marks topsoil and ash, whose upward faces wear the same
// painted floor as the forest round it (terrain.gdshaderinc) so the hill
// rises out of the ground without a seam. The grain is pixel-sized and
// anchored to the site, so it stays put as the earth is cut away. Like
// occluder.gdshader, earth between the camera and Veyl dithers away in a
// bubble so vae stays visible down a hole.

#include "res://terrain.gdshaderinc"

global uniform vec3 player_position;

// The site's corner in Emberwood space
uniform vec3 site_offset;
uniform float grain = 4.0;
uniform float fade_radius = 12.0;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.97;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

varying vec3 site_pos;
varying vec3 site_normal;
varying vec4 fleck;
varying float topsoil;

void vertex() {
	site_pos = VERTEX;
	site_normal = NORMAL;
	fleck = CUSTOM0;
	topsoil = UV2.x;
}

void fragment() {
	// Grain on whichever plane the face mostly lies in
	vec3 an = abs(normalize(site_normal));
	vec2 plane = an.y > max(an.x, an.z) ? site_pos.xz : (an.x > an.z ? site_pos.zy : site_pos.xy);
	vec2 cell = floor(plane * grain);
	float speck = hash(cell);
	vec3 rock = COLOR.rgb * (speck < 0.5 ? 1.0 + (speck - 0.25) * 0.24 : 1.0 - (speck - 0.5) * 0.16);
	// Ore and grain gather into clumps rather than single pixels
	float clump = hash(floor(plane * grain * 0.5) + 7.3);
	bool is_fleck = hash(cell + 3.1) < fleck.a * 0.5 || clump < fleck.a * 0.3;
	if (is_fleck) {
		rock = fleck.rgb;
	}
	// Muted, like the forest floor
	float grey = dot(rock, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(grey), rock, 0.75);
	if (topsoil > 0.5) {
		float up = smoothstep(0.55, 0.85, normalize(site_normal).y) * smoothstep(0.5, 0.9, topsoil);
		if (up > 0.0) {
			col = mix(col, ground_colour((site_pos + site_offset).xz), up);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	// Emberstone veins: bright enough to survive the ink post pass
	if (is_fleck && COLOR.a > 0.5) {
		EMISSION = fleck.rgb * 2.5;
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
