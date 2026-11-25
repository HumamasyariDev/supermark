// Inverted-hull ink outline. Use as next_pass on a toon material. Width is roughly constant in screen space.
// Optional (RetroLook gameplay pop, D034): exact_px uses the real projection and viewport height instead of the 1080p
// approximation; fade_px > 0 thins the outline on objects whose projected radius (object_radius) is under about
// 2 x fade_px pixels (no dark rings around far acorns); fade_far > 0 drops it beyond that distance.
// LOOK finish (D037): the hull is always offset in view space, so the width is in true world units at any mesh scale;
// thin_radius > 0 caps it for thin parts.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.22, 0.13, 0.12, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 2.0;
uniform float max_world_width = 0.03;
uniform bool exact_px = false;
uniform float viewport_height = 1080.0;
uniform float object_radius = 0.0;
uniform float fade_px = 0.0;
uniform float fade_far = 0.0;
// > 0: radius (m) of the thinnest dimension of the mesh this pass sits on (set by RetroLook for thin parts).
uniform float thin_radius = 0.0;

void vertex() {
	// LOOK finish pass: the hull is pushed out in view space, so the width is in true world units whatever the mesh's
	// own scale (imported characters with a 10x node or bone scale grew 25 px halos that covered the whole model).
	vec3 vpos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vn = normalize(mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * NORMAL));
	float dist = max(-vpos.z, 0.1);
	float px_world = dist * 0.0012;
	if (exact_px) {
		// abs(): the Vulkan projection carries a flipped Y (negative [1][1]); without it every "exact" outline hit its world cap.
		px_world = dist * 2.0 / max(abs(PROJECTION_MATRIX[1][1]) * viewport_height, 1.0);
	}
	float w = min(outline_width * px_world, max_world_width);
	if (fade_px > 0.0 && object_radius > 0.0) {
		float radius_px = object_radius / max(px_world, 1e-5);
		w *= smoothstep(fade_px * 0.5, fade_px * 1.5, radius_px);
	}
	if (fade_far > 0.0) {
		w *= 1.0 - smoothstep(fade_far * 0.8, fade_far, dist);
	}
	// Thin parts (lances, stalks): never wider than a third of the part's own radius (no black poles).
	if (thin_radius > 0.0) {
		w = min(w, thin_radius * 0.35);
	}
	POSITION = PROJECTION_MATRIX * vec4(vpos + vn * w, 1.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
