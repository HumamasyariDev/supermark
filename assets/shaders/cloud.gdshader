// Puffy cloud surface for cloud platforms and 3D sky clouds. Apply to sphere clusters or a blobby mesh.
// The surface breathes (noise displacement along normals), shades with a soft white to lavender ramp,
// glows at the rim and softly fades into the ground where it touches geometry (optional).
shader_type spatial;
// RETRO_LOOK (D032, Docs/ART_V3_RETRO.md): RetroLook builds a variant of this shader with "#define RETRO_LOOK" injected
// (nearest-mipmap texels, world-space texel snapping). Without the define the shader is unchanged.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 light_color : source_color = vec4(1.0, 0.99, 0.96, 1.0);
uniform vec4 shade_color : source_color = vec4(0.62, 0.66, 0.9, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float rim_strength = 0.45;
uniform float puff_amount = 0.08;
uniform float puff_scale = 1.6;
uniform float puff_speed = 0.35;
uniform float ramp_softness = 0.18;
// 0..1 fade used by vanishing clouds (dissolves with a noisy edge).
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float glow = 0.04;
// Retro: world-space texels per metre for the dissolve edge (crisp stepped edge instead of noisy fuzz).
uniform float retro_texels_per_m = 8.0;

varying vec3 v_wpos;
varying vec3 v_lpos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = sm_vnoise(wp.xz * puff_scale + vec2(TIME * puff_speed, wp.y * puff_scale)) ;
	n += sm_vnoise(wp.xy * puff_scale * 2.1 - TIME * puff_speed * 0.7) * 0.5;
	VERTEX += NORMAL * (n - 0.6) * puff_amount;
	v_wpos = wp;
	v_lpos = VERTEX;
}

void fragment() {
	vec3 wp = v_wpos;
#ifdef RETRO_LOOK
	wp = (floor(wp * retro_texels_per_m) + 0.5) / retro_texels_per_m;
#endif
	float n = sm_fbm(wp.xz * 1.2 + wp.y * 0.7);
	if (dissolve > 0.0 && n < dissolve * 1.05) {
		discard;
	}
	ALBEDO = vec3(1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = mak_out(mak_lin(rim_color.rgb) * fres * rim_strength * 0.5 + mak_lin(light_color.rgb) * glow);
	ROUGHNESS = 1.0;
#ifdef RETRO_LOOK
	SPECULAR = 0.05;
#endif
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		// Local lights (effect flashes, candles): plain wrapped Lambert with distance attenuation.
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION;
	} else {
		float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
		float lit = smoothstep(0.5 - ramp_softness, 0.5 + ramp_softness, ndl) * mix(0.55, 1.0, ATTENUATION);
		vec3 c = mix(mak_lin(shade_color.rgb), mak_lin(light_color.rgb), lit);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * c;
		// Silver lining toward the light.
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * fres * back * rim_strength;
	}
}
