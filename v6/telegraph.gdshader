shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Ground warning for an incoming attack, inked to match the look: a hard
// outline with a hatched red fill that grows as the windup runs out, so
// the moment it's full is the moment it hits.
//   shape 0: circle (slams, eruptions, landings)
//   shape 1: lane from the attacker (UV.y 1 at the attacker, 0 at the far end)

uniform int shape = 0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// Flashes white-hot on impact
uniform float burst : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fill = vec3(0.85, 0.12, 0.05);
uniform vec3 ink = vec3(0.035, 0.028, 0.045);
uniform vec3 hot = vec3(1.0, 0.85, 0.55);

void fragment() {
	float inside;
	float border;
	float filled;
	if (shape == 0) {
		float r = length(UV - 0.5) * 2.0;
		if (r > 1.0) discard;
		border = smoothstep(0.86, 0.9, r);
		filled = step(r, progress);
		inside = 1.0;
	} else {
		float along = 1.0 - UV.y;
		float side = abs(UV.x - 0.5) * 2.0;
		border = max(smoothstep(0.8, 0.86, side), smoothstep(0.94, 0.97, along));
		filled = step(along, progress);
		inside = 1.0;
	}
	// Diagonal hatching in the fill, like a shaded panel
	vec2 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float hatch = step(0.5, fract((world.x + world.y) * 1.6));

	vec3 col = fill * mix(0.7, 1.0, hatch);
	float a = filled * mix(0.35, 0.55, hatch);
	// The outline is always there, so the danger zone reads before it fills
	col = mix(col, mix(ink, fill * 1.3, 0.35), border);
	a = max(a, border * 0.9);
	col = mix(col, hot, burst);
	a = mix(a, 0.85 * inside, burst);
	ALBEDO = col;
	ALPHA = a * alpha;
}
