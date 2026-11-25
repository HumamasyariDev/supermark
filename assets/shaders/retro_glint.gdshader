// Truffle glint pass (D034 M3, Docs/ART_V3_RETRO.md): additive, chained by RetroLook after retro_pop on truffles.
// A diagonal gold sheen band sweeps across the object every glint_period seconds, cool white twinkle cells make the
// truffle stand apart from warm worlds, and a constant gold lift keeps it warm in shade.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// OPUSLOOK: additive on the web after sRGB encoding; the colours go in as their linear (desktop) values.
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform float glint_strength : hint_range(0.0, 3.0) = 1.0;
uniform vec4 glint_color : source_color = vec4(1.0, 0.86, 0.42, 1.0);
uniform vec4 twinkle_color : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform float glint_period = 2.4;
uniform float lift : hint_range(0.0, 1.0) = 0.3;
uniform float fade_far = 80.0;

varying vec3 v_obj;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float ph = fract(TIME / glint_period);
	float band_pos = (v_obj.x + v_obj.y * 0.8) * 2.2;
	float sweep = mix(-2.2, 2.2, ph);
	float band = 1.0 - smoothstep(0.0, 0.18, abs(band_pos - sweep));
	vec3 cell = floor(v_obj * 14.0);
	float r = hash13(cell);
	float tw = step(0.93, r) * pow(max(sin(TIME * (3.0 + r * 4.0) + r * 40.0), 0.0), 12.0);
	vec3 col = mak_lin(glint_color.rgb) * band * 0.8 * glint_strength + mak_lin(twinkle_color.rgb) * tw * 1.4 * glint_strength;
	col += mak_lin(glint_color.rgb) * lift * 0.5;
	col *= 1.0 - smoothstep(fade_far * 0.7, fade_far, length(VERTEX));
	ALBEDO = col;
}
