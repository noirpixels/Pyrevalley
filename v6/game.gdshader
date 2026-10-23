shader_type spatial;
render_mode specular_disabled;

// Emberwood forest floor, painted by terrain.gdshaderinc. Mining sites
// (mining_sites.gd) cut holes in it where their own ground takes over, and
// the painted detail is turned into a bump so it catches the low sun.

#include "res://terrain.gdshaderinc"

uniform float bump_strength = 0.6;
// x0, z0, x1, z1 in this mesh's space
uniform vec4 holes[4];
uniform int hole_count = 0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	for (int i = 0; i < hole_count; i++) {
		vec4 h = holes[i];
		if (local_pos.x > h.x && local_pos.x < h.z && local_pos.z > h.y && local_pos.z < h.w) {
			discard;
		}
	}

	vec3 col = ground_colour(vec2(local_pos.x, local_pos.z + mesh_offset_z));
	ALBEDO = col;
	ROUGHNESS = 1.0;

	// Bump from the painted detail (screen-space derivative bump mapping)
	float h = dot(col, vec3(0.299, 0.587, 0.114)) * bump_strength;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
