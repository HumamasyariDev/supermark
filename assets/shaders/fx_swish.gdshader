// Cartoon smear arc for punches, kicks, spin kicks and the boss's paw swipes (juice fix round 1).
// Mesh: a flat annulus sector built by FxEffect ("arc" layer). UV.x runs along the sweep (0 start, 1 end),
// UV.y across it (0 inner radius, 1 outer radius).
// Timing (FxEffect): `progress` draws the head from 0 to 1 in about 3 frames, the full crescent HOLDS for 3 frames,
// then `wipe` erases it from the tail to the tip. Look: a dark ink outer edge (#3B2416), a warm cream body and a
// gold-to-pink inner gradient (Mak pink #F29AA3), plus three trailing speed lines behind the crescent, so the arc
// reads on bright grass and cobble at gameplay distance.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform vec4 inner_color : source_color = vec4(0.95, 0.6, 0.64, 1.0);
uniform vec4 ink_color : source_color = vec4(0.23, 0.14, 0.086, 1.0);
uniform float progress = 0.0;
uniform float wipe = 0.0;
uniform float tail = 0.55;
uniform float opacity = 0.95;
uniform float ink = 0.6;
uniform float streaks = 6.0;
uniform float glow = 1.15;
uniform float speed_lines = 1.0;

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float head = max(progress, 0.001);
	// 0 at the head, 1 at the start of the sweep.
	float rel = clamp((head - x) / head, 0.0, 1.0);
	float drawn = step(x, head);
	// Tail-to-tip wipe with a soft eroded front.
	float n = sm_vnoise(vec2(x * 9.0, y * 5.0));
	float wf = wipe * 1.08 - 0.04;
	float alive = smoothstep(wf, wf + 0.07, x + (n - 0.5) * 0.06);
	// Crescent: full width at the head, thinning toward the start; thins again as it is wiped.
	float thick = mix(1.0, 0.18, pow(rel, 0.8)) * (1.0 - wipe * 0.45);
	float inner = 1.0 - thick;
	float band = smoothstep(inner, inner + 0.08, y) * (1.0 - smoothstep(0.95, 1.0, y));
	// Three speed lines trailing inside the thin part of the crescent (they extend the motion read).
	float lines = 0.0;
	for (int i = 0; i < 3; i++) {
		float ly = 0.38 + float(i) * 0.17;
		float w = 0.035;
		float ln = smoothstep(w, w * 0.4, abs(y - ly));
		// Each line covers a different stretch behind the head.
		float start = 0.18 + float(i) * 0.12;
		float len = 0.55 - float(i) * 0.1;
		ln *= smoothstep(start, start + 0.05, rel) * (1.0 - smoothstep(start + len - 0.1, start + len, rel));
		lines = max(lines, ln);
	}
	lines *= speed_lines * (1.0 - band);
	// Streak texture along the sweep.
	float sn = sm_vnoise(vec2(x * 3.0 - progress * 4.0, y * streaks));
	float s = mix(0.8, 1.0, smoothstep(0.35, 0.75, sn));
	// Colour across the band: pink at the inner edge, gold, cream body, dark ink lip on the outside.
	float yb = clamp((y - inner) / max(1.0 - inner, 0.001), 0.0, 1.0);
	vec3 c = mix(mak_lin(inner_color.rgb), mak_lin(edge_color.rgb), smoothstep(0.0, 0.35, yb));
	c = mix(c, mak_lin(color.rgb), smoothstep(0.3, 0.6, yb));
	c *= glow;
	float tip = 1.0 - smoothstep(0.0, 0.1, rel);
	c = mix(c, vec3(1.0), tip * 0.5);
	float lip = smoothstep(0.8, 0.88, y);
	c = mix(c, mak_lin(ink_color.rgb), lip * ink);
	vec3 lc = mix(mak_lin(ink_color.rgb), mak_lin(color.rgb), 0.35);
	vec3 outc = mix(lc, c, band);
	float a = max(band * s, lines * 0.85) * drawn * alive * opacity;
	ALBEDO = mak_out(outc);
	ALPHA = clamp(a, 0.0, 1.0);
}
