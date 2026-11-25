// Cutaway for an occluder the gameplay camera looks through (W1 hollow log; render fix 2026-10-19).
// Owner: the old fade (alpha-hash dither at 22 %) turned the log into harsh per-pixel noise of coloured dots on top of
// the retro texels. Instead the camera-facing shell is cut away cleanly, like a storybook diorama: every triangle that
// faces the camera is discarded, the far wall and the floor stay solid (seen from inside, slightly darker), so Mak
// stands in a sliced-open log with no dither, no shimmer and no sorting. The shadow pass keeps the whole shell, so the
// log's cast shadow does not change while the cutaway is on. Same world-triplanar bark and toon light as the log.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/stylized_light.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
uniform float triplanar_scale = 0.45;
uniform vec4 inner_tint : source_color = vec4(0.8, 0.7, 0.62, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.58, 0.5, 0.68, 1.0);

varying vec3 v_wpos;
varying vec3 v_wnorm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	if (FRONT_FACING && !IN_SHADOW_PASS) {
		discard;
	}
	vec3 w = pow(abs(v_wnorm), vec3(8.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_wpos * triplanar_scale;
	vec3 t = texture(albedo_texture, p.zy * vec2(1.0, -1.0)).rgb * w.x + texture(albedo_texture, p.xz).rgb * w.y
		+ texture(albedo_texture, p.xy * vec2(1.0, -1.0)).rgb * w.z;
	ALBEDO = albedo.rgb * t * inner_tint.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION;
	} else {
		sm_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, 0.05, 0.12, shadow_tint.rgb, 0.0, 0.3,
			DIFFUSE_LIGHT, SPECULAR_LIGHT);
	}
}
