shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Soft darkening on the ground where a tree meets it.

uniform float strength = 0.45;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.15, 1.0, d));
}
