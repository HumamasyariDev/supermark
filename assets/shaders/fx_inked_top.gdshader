// On-top copy (no depth test) of fx_inked.gdshader, for impact stars that must read through Mak (wall kick).
// Inked sprite particles with erosion instead of a fade (juice fix round 2).
// Billboard particle (INSTANCE_CUSTOM.x = spin angle). Texture colour x particle colour (sRGB authored).
// mode 0 (impact_star): the particle alpha opens a hole from the centre outward, so a hit star pops, then goes hollow
//                       and breaks up at the spikes (never a flat disc that sits over the target).
// mode 1 (dust_crescent, cocoa drops): noise erosion that eats from the edge inward as the particle alpha falls.
// Near-camera fade and a soft depth fade keep ground dust from cutting the ground or filling the frame.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, blend_mix;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform sampler2D sprite : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform int mode = 0;
uniform float soft_depth = 0.05;
uniform vec2 near_fade = vec2(0.5, 1.6);
uniform bool use_depth = true;

varying float v_seed;

void vertex() {
	v_seed = float(INSTANCE_ID) * 0.6180339 + INSTANCE_CUSTOM.x * 0.1;
	float a = INSTANCE_CUSTOM.x;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	VERTEX.xy = rot * VERTEX.xy;
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
}

void fragment() {
	vec4 t = texture(sprite, UV);
	vec3 pc = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float life_a = clamp(COLOR.a, 0.0, 1.0);
	float keep;
	if (mode == 0) {
		// Hollow from the centre: radius grows as alpha falls; a little noise so the inner edge is ragged.
		float n = sm_fbm(p * 3.0 + v_seed * 5.0);
		float hole = (1.0 - life_a) * 1.15 + (n - 0.5) * 0.18;
		keep = smoothstep(hole - 0.02, hole + 0.04, r);
	} else {
		float n = sm_fbm(p * 2.4 + vec2(v_seed * 7.1, v_seed * 3.3));
		float e = n * 0.6 + (1.0 - clamp(r, 0.0, 1.0)) * 0.4;
		float thr = (1.0 - life_a) * 1.05 - 0.04;
		keep = smoothstep(thr, thr + 0.07, e);
		// Mottled translucency so dust reads as dust, not a flat paper cut-out.
		keep *= mix(0.6, 1.0, smoothstep(0.3, 0.7, sm_fbm(p * 5.0 + v_seed * 11.0)));
	}
	ALBEDO = mak_out(mak_lin(t.rgb) * pc);
	float alpha = t.a * keep * step(0.01, life_a);
	alpha *= smoothstep(near_fade.x, near_fade.y, -VERTEX.z);
	if (use_depth) {
		float depth = texture(depth_tex, SCREEN_UV).r;
		vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene_z = up.z / up.w;
		alpha *= clamp((VERTEX.z - scene_z) / soft_depth, 0.0, 1.0);
	}
	ALPHA = clamp(alpha, 0.0, 1.0);
}
