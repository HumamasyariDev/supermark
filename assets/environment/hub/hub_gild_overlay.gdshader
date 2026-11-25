shader_type spatial;
// Hub-side gilding overlay for collectibles (r1 visual round 2): an additive warm-gold fresnel rim, a faint
// overall gold lift and an occasional travelling glint, so acorns read gold (#FFC93C) on the walnut floor.
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;
// OPUSLOOK: the web adds this pass after sRGB encoding, so the gold goes in as its linear value (as on the desktop); added
// unconverted, its blue channel was six times too strong and turned the acorns pale peach.
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 gold : source_color = vec4(1.0, 0.79, 0.24, 1.0);
uniform float lift = 0.14;
uniform float rim_strength = 0.85;
uniform float rim_power = 2.2;
uniform float glint_strength = 1.4;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power) * rim_strength;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = fract(TIME * 0.35 + dot(wp, vec3(0.13, 0.07, 0.11)));
	// Fix r1b: the old band test was true on ~90 % of the surface, so a glint turned whole acorns white for a
	// quarter of every cycle (the "ghost" white acorns in the A_v5 capture). Now a thin travelling stripe.
	float s = abs(fract(wp.y * 2.0 - phase * 3.0) - 0.5);
	float band = 1.0 - smoothstep(0.0, 0.07, s);
	float glint = band * step(0.72, phase) * glint_strength;
	ALBEDO = mak_lin(gold.rgb) * (lift + rim) + vec3(1.0, 0.96, 0.85) * glint * 0.5;
}
