// W2 walkable cloud decks (fix round 1, W2 lighting.value_pass): a copy of the shared cloud.gdshader whose albedo
// follows the world normal: warm light deck tops, lavender sides, deeper lavender undersides, so walkable decks
// separate from the white background clouds and the cream hero reads on them. Owned by the W2 builder.
// Original header: Puffy cloud surface for cloud platforms and 3D sky clouds. Apply to sphere clusters or a blobby mesh.
// The surface breathes (noise displacement along normals), shades with a soft white to lavender ramp,
// glows at the rim and softly fades into the ground where it touches geometry (optional).
shader_type spatial;
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
uniform vec4 top_albedo : source_color = vec4(0.96, 0.91, 0.93, 1.0);
uniform vec4 side_albedo : source_color = vec4(0.79, 0.71, 0.9, 1.0);
uniform vec4 under_albedo : source_color = vec4(0.63, 0.56, 0.84, 1.0);

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
	float n = sm_fbm(v_wpos.xz * 1.2 + v_wpos.y * 0.7);
	if (dissolve > 0.0 && n < dissolve * 1.05) {
		discard;
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 alb = mix(mak_lin(side_albedo.rgb), mak_lin(top_albedo.rgb), smoothstep(0.35, 0.85, wn.y));
	alb = mix(alb, mak_lin(under_albedo.rgb), smoothstep(-0.15, -0.65, wn.y));
	ALBEDO = mak_out(alb);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = mak_out(mak_lin(rim_color.rgb) * fres * rim_strength * 0.5 + mak_lin(light_color.rgb) * glow);
	ROUGHNESS = 1.0;
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
