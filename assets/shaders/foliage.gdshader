// Foliage: grass blades, leaf cards and flowers. Wind sway grows with height (or vertex colour alpha),
// with a travelling gust wave in world space. Two-sided, optional alpha scissor, soft translucent light.
// Works on MultiMesh instances (MODEL_MATRIX includes the instance transform).
shader_type spatial;
// RETRO_LOOK (D032, Docs/ART_V3_RETRO.md): RetroLook builds a variant of this shader with "#define RETRO_LOOK" injected
// (nearest-mipmap texels, world-space texel snapping). Without the define the shader is unchanged.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.22, 0.45, 0.16, 1.0);
uniform vec4 tip_color : source_color = vec4(0.62, 0.82, 0.3, 1.0);
#ifdef RETRO_LOOK
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, hint_default_white;
#else
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
#endif
uniform bool use_texture_alpha = false;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.4;
// Multiply by vertex colour RGB (flowers carry their petal colour in vertex colours).
uniform bool use_vertex_color = false;
// Height over which sway reaches full strength (metres, local space). With use_color_weight,
// vertex colour alpha (0 root, 1 tip) is used instead and the root-to-tip gradient is skipped.
uniform float sway_height = 0.6;
uniform bool use_color_weight = false;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.3);
uniform float wind_strength = 0.18;
uniform float wind_speed = 1.4;
uniform float gust_scale = 0.08;
uniform float flutter = 0.03;
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.5, 0.58, 1.0);
uniform float translucency = 0.35;
// Something that pushes the grass aside: world position xyz + radius w (set per frame by a script; optional).
uniform vec4 pusher = vec4(0.0, -1000.0, 0.0, 0.8);
uniform float colour_variation = 0.18;
uniform bool gradient_by_height = true;
// Retro: number of flat colour bands in the root-to-tip gradient (0 keeps the smooth gradient).
uniform float retro_gradient_steps = 4.0;

varying float v_weight;
varying vec3 v_origin;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = use_color_weight ? COLOR.a : clamp(VERTEX.y / max(sway_height, 0.001), 0.0, 1.0);
	v_weight = w;
	w = w * w;
	vec3 dir = normalize(wind_direction + vec3(0.0001));
	float t = TIME * wind_speed;
	float gust = sm_vnoise(origin.xz * gust_scale - dir.xz * t * 0.6);
	gust = smoothstep(0.25, 0.9, gust);
	float sway = sin(t * 2.1 + dot(origin.xz, vec2(0.7, 0.3)) * 1.3) * 0.35 + 0.35 + gust * 1.2;
	vec3 offset_w = dir * sway * wind_strength * w;
	offset_w += vec3(sin(t * 7.0 + wpos.x * 5.0), 0.0, cos(t * 6.3 + wpos.z * 5.0)) * flutter * w;
	vec3 to = wpos - pusher.xyz;
	float d = length(to.xz);
	float push = (1.0 - smoothstep(pusher.w * 0.3, pusher.w, d)) * w;
	vec2 pd = normalize(to.xz + vec2(0.001));
	offset_w += vec3(pd.x, -0.4, pd.y) * push * 0.35;
	mat4 inv = inverse(MODEL_MATRIX);
	VERTEX += (inv * vec4(offset_w, 0.0)).xyz;
	v_origin = origin;
	// Upward-biased normals make tufts shade like a soft volume instead of flat cards.
	NORMAL = normalize(mix(NORMAL, normalize((inv * vec4(0.0, 1.0, 0.0, 0.0)).xyz), 0.6));
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	float h = clamp(sqrt(max(v_weight, 0.0)), 0.0, 1.0);
#ifdef RETRO_LOOK
	if (retro_gradient_steps > 0.5) {
		h = floor(h * retro_gradient_steps + 0.5) / retro_gradient_steps;
	}
#endif
	vec3 col = gradient_by_height ? mix(mak_lin(base_color.rgb), mak_lin(tip_color.rgb), h) : mak_lin(base_color.rgb);
	float var = sm_vnoise(v_origin.xz * 0.15) - 0.5;
	col *= 1.0 + var * colour_variation;
	col.r *= 1.0 + var * colour_variation * 0.8;
	col *= mak_lin(tex.rgb);
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	ALBEDO = mak_out(col);
	ROUGHNESS = 0.9;
#ifdef RETRO_LOOK
	ROUGHNESS = 1.0;
	SPECULAR = 0.04;
#endif
	if (use_texture_alpha) {
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
	BACKLIGHT = col * translucency;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		// Local lights (effect flashes, candles): plain wrapped Lambert with distance attenuation.
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION;
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lit = smoothstep(-0.3, 0.6, ndl) * smoothstep(0.05, 0.6, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(mak_lin(shadow_tint.rgb), vec3(1.0), lit);
	}
}
