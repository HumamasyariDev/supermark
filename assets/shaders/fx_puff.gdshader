// Cartoon toon puff for dust, smoke balls and cloud pops: a lumpy, two-tone shaded ball with a thin
// darker rim that erodes into holes as the particle alpha falls (instead of fading to mush).
// Billboard particle (uses INSTANCE_CUSTOM.x as the spin angle). Colour = particle colour (sRGB authored).
// Juice fix round 1: warm (not lavender) shade, a near-camera fade so a puff between the camera and Mak never
// fills the frame, and a soft depth fade (0.3 m) so puffs hug and melt into the ground instead of cutting it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 shade_color : source_color = vec4(0.9, 0.82, 0.74, 1.0);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_depth = 0.3;
uniform vec2 near_fade = vec2(0.6, 2.2);
uniform float edge_noise = 0.3;
uniform float rim_dark = 0.82;
uniform float highlight = 0.05;
uniform float max_alpha = 0.9;
// 0 = classic fade, 1 = full noise erosion as alpha falls.
uniform float erosion = 1.0;

varying float v_seed;
varying float v_angle;

void vertex() {
	v_seed = float(INSTANCE_ID) * 0.6180339 + INSTANCE_CUSTOM.x * 0.1;
	float a = INSTANCE_CUSTOM.x;
	v_angle = a;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	VERTEX.xy = rot * VERTEX.xy;
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 sp = p + vec2(fract(v_seed * 7.13), fract(v_seed * 3.71)) * 9.0;
	float n = sm_fbm(sp * 1.6);
	// Lumpy cloud silhouette (three soft lobes from the noise), not a sphere.
	float r = length(p) + (n - 0.5) * edge_noise * 2.0 + 0.08 * sin(atan(p.y, p.x) * 3.0 + v_seed * 6.0);
	float body = 1.0 - smoothstep(0.8, 0.86, r);
	// Light comes from the screen's upper left, unrotated by the sprite spin so shading stays consistent.
	vec2 q = mat2(vec2(cos(-v_angle), -sin(-v_angle)), vec2(sin(-v_angle), cos(-v_angle))) * p;
	float rr = clamp(length(q) / 0.86, 0.0, 1.0);
	vec3 nrm = normalize(vec3(q.x, -q.y, sqrt(max(1.0 - rr * rr, 0.0)) + 0.15));
	float ndl = dot(nrm, normalize(vec3(-0.45, 0.7, 0.55)));
	float lit = smoothstep(0.0, 0.3, ndl + (n - 0.5) * 0.4);
	vec3 pc = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	vec3 c = mix(pc * mak_lin(shade_color.rgb), pc, lit);
	c += vec3(highlight) * smoothstep(0.55, 0.8, ndl);
	float rim = smoothstep(0.7, 0.8, r) * body;
	c *= mix(1.0, rim_dark, rim);
	// Erosion: holes open from the noise as alpha falls.
	// Erosion eats from the rim inward (dust thinning out) more than it punches holes in the middle.
	float e = sm_fbm(sp * 2.7 + 13.0) * 0.55 + (1.0 - clamp(r, 0.0, 1.0)) * 0.45 + 0.04;
	float thr = (1.0 - COLOR.a) * 1.05 - 0.05;
	float keep = mix(COLOR.a, smoothstep(thr, thr + 0.06, e), erosion);
	ALBEDO = mak_out(c);
	float a = body * keep * mix(1.0, COLOR.a, 1.0 - erosion) * max_alpha;
	// Near-camera fade.
	a *= smoothstep(near_fade.x, near_fade.y, -VERTEX.z);
	// Soft depth fade against the scene.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = up.z / up.w;
	a *= clamp((VERTEX.z - scene_z) / soft_depth, 0.0, 1.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
