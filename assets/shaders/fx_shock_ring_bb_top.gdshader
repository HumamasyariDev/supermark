// On-top copy (juice fix r1): contact rings that must read through the target body.
// Billboarded variant (camera-facing ring burst for hits, pickups and portals) of the stylised shockwave ring (Ham Slam, boss stomps, gummy slams, bounce pads, landings).
// A quad (ground-aligned or billboarded) whose fragment draws an expanding annulus with a cream body,
// a warm inner glow, an ink-dark outer lip and noisy breakup, plus a gentle screen-space refraction
// of what is behind it. FxEffect animates `progress` 0..1; size comes from the node scale.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, blend_mix;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.4, 1.0);
uniform vec4 ink_color : source_color = vec4(0.231, 0.141, 0.086, 1.0);
uniform float progress = 0.0;
uniform float thickness = 0.22;
uniform float opacity = 0.95;
uniform float ink = 0.55;
uniform float breakup = 0.45;
uniform float refraction = 0.0; // unused since juice fix r2
uniform float seed = 0.0;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float k = clamp(progress, 0.0, 1.0);
	float e = 1.0 - pow(1.0 - k, 3.0);
	float radius = mix(0.12, 0.92, e);
	float th = thickness * mix(1.0, 0.25, k);
	// Signed distance from the ring centre line, 0 at the outer lip side.
	float d = (r - (radius - th)) / max(th, 0.0001);
	float body = smoothstep(0.0, 0.25, d) * (1.0 - smoothstep(0.85, 1.0, d));
	float lip = smoothstep(0.62, 0.8, d) * (1.0 - smoothstep(0.92, 1.0, d));
	float inner_glow = smoothstep(-0.5, 0.2, d) * (1.0 - smoothstep(0.2, 0.6, d));  // r2: narrow (was a filled bubble)
	float n = sm_fbm_rot(vec2(ang * 3.0 + seed * 7.0, r * 4.0 - k * 3.0), 3);
	float cut = smoothstep(breakup * k, breakup * k + 0.18, n);
	float fade = 1.0 - k * k;
	vec3 c = mix(mak_lin(color.rgb), mak_lin(glow_color.rgb) * 1.4, inner_glow * (1.0 - body) + 0.25 * (1.0 - d));
	c = mix(c, mak_lin(ink_color.rgb), lip * ink);
	float a = max(body, inner_glow * 0.12) * cut * fade * opacity;
	// Juice fix r2: no screen-texture refraction (it greyed every band and cost a screen copy per frame). The ring is a
	// warm cream band with an ink outer lip; `refraction` stays as an unused uniform for older presets.
	ALBEDO = mak_out(c);
	ALPHA = clamp(a, 0.0, 1.0);
}
