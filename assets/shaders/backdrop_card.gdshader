// Horizon / backdrop cut-out cards (W1 pop-up card layers, 2026-10-19 render fix).
// Owner: when the camera swings past the map edge, the double-sided cards filled the view from behind with a flat
// paper-coloured wall (only Mak's x-ray silhouette showed). The cards bend around ring_center, and their triangle winding
// is mixed (triangulated polygons and paper edges), so plain back-face culling would also cut holes into the front.
// One-sided by position instead: a fragment is drawn only while the camera is on the ring's inner side of it, so from
// outside the ring the card is invisible and the sky shows through. Same look as the StandardMaterial3D it replaces
// (unshaded vertex colour, no fog, no shadows).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
// World-space centre the cards are bent around (their layers sit 76-86 m out on a circle around it).
uniform vec3 ring_center = vec3(0.0);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 outward = v_wpos.xz - ring_center.xz;
	vec2 to_cam = CAMERA_POSITION_WORLD.xz - v_wpos.xz;
	if (dot(outward, to_cam) > 0.0) {
		discard;
	}
	ALBEDO = mak_out(COLOR.rgb * mak_lin(albedo.rgb));
}
