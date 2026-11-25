// W1 Huff & Puff Hollow terrain. Based on res://assets/shaders/terrain.gdshader (vfx workstream),
// extended for W1: vertex colour R = lane (dirt), G = cobble lane, B = wet stream bank, A = rock hint.
// Grass on flat ground with a sunny top lift, rock on steep skirts, painterly noise-broken edges.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D dirt_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D cobble_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 grass_tint_high : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(1.0);
uniform vec4 cobble_tint : source_color = vec4(1.0);
uniform vec4 rock_tint : source_color = vec4(1.0);
uniform vec4 wet_tint : source_color = vec4(0.55, 0.5, 0.38, 1.0);
uniform float grass_scale = 0.16;
uniform float dirt_scale = 0.2;
uniform float cobble_scale = 0.35;
uniform float rock_scale = 0.07;
uniform float slope_start : hint_range(0.0, 1.0) = 0.8;
uniform float slope_end : hint_range(0.0, 1.0) = 0.62;
uniform float blend_noise = 0.14;
uniform float triplanar_sharpness = 4.0;
uniform float macro_variation = 0.12;
uniform vec4 shadow_tint : source_color = vec4(0.5, 0.52, 0.68, 1.0);
uniform float grass_brightness = 1.08;
uniform float high_start = 3.0;
uniform float high_end = 11.0;
uniform float texture_strength = 0.75;
// Steep banks stay grassy (a deeper, mossier green); bare rock only shows on the steepest faces, in big patches.
uniform vec4 steep_tint : source_color = vec4(0.78, 0.86, 0.66, 1.0);
uniform float rock_up_start = 0.56;
uniform float rock_up_end = 0.4;
uniform float rock_patch_scale = 0.09;

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying vec4 v_color;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR;
}

vec3 tri(sampler2D tex, vec3 p, vec3 w, float s) {
	vec3 x = texture(tex, p.zy * s).rgb;
	vec3 y = texture(tex, p.xz * s).rgb;
	vec3 z = texture(tex, p.xy * s).rgb;
	return x * w.x + y * w.y + z * w.z;
}

// Soften a texture toward its own mean so it reads as painted colour blocks, not a photo.
vec3 soften(vec3 c, vec3 mean_col) {
	return mix(mean_col, c, texture_strength);
}

void fragment() {
	vec3 n = normalize(v_wnorm);
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	w /= (w.x + w.y + w.z);
	float nz = sm_fbm(v_wpos.xz * 0.35) - 0.5;
	vec2 g = v_wpos.xz * grass_scale;
	vec3 grass_a = mak_lin(texture(grass_texture, g).rgb);
	vec3 grass_b = mak_lin(texture(grass_texture, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * g * 0.61 + 0.37).rgb);
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.35, 0.65, sm_fbm(v_wpos.xz * 0.05)));
	grass = soften(grass, vec3(0.45, 0.62, 0.3));
	float hi = smoothstep(high_start, high_end, v_wpos.y + nz * 1.5);
	grass *= mix(mak_lin(grass_tint.rgb), mak_lin(grass_tint_high.rgb), hi) * grass_brightness;
	vec3 dirt = soften(mak_lin(texture(dirt_texture, v_wpos.xz * dirt_scale).rgb), vec3(0.7, 0.55, 0.38)) * mak_lin(dirt_tint.rgb);
	vec3 cob = soften(mak_lin(texture(cobble_texture, v_wpos.xz * cobble_scale).rgb), vec3(0.62, 0.6, 0.56)) * mak_lin(cobble_tint.rgb);
	vec3 rock = mak_lin(tri(rock_texture, v_wpos, w, rock_scale)) * mak_lin(rock_tint.rgb);
	float up = n.y + nz * blend_noise;
	float flat_w = smoothstep(slope_end, slope_start, up);
	// OPUSLOOK: a narrower lane edge. The 0.38-0.62 cross-fade mixed grass and dirt into a 15-20 px lime band along
	// every path at the gameplay camera; the noise term keeps the edge organic.
	float path = smoothstep(0.46, 0.54, v_color.r + nz * 0.45);
	float cobble = smoothstep(0.4, 0.6, v_color.g + nz * 0.3);
	vec3 lane = mix(dirt, cob, cobble);
	vec3 top = mix(grass, lane, path);
	// Wet, darker earth along the stream banks (below the grass line).
	float wet = smoothstep(0.35, 0.85, v_color.b + nz * 0.3) * smoothstep(0.4, -0.5, v_wpos.y);
	top = mix(top, top * mak_lin(wet_tint.rgb) * 1.4, wet);
	float patchn = sm_fbm(v_wpos.xz * rock_patch_scale + vec2(v_wpos.y * 0.05)) - 0.5;
	float rock_w = smoothstep(rock_up_start, rock_up_end, n.y + patchn * 0.35);
	vec3 bank = grass * mak_lin(steep_tint.rgb);
	vec3 steep_col = mix(bank, rock, rock_w);
	vec3 col = mix(steep_col, top, flat_w);
	float macro = sm_fbm(v_wpos.xz * 0.03) - 0.5;
	col *= 1.0 + macro * macro_variation * 2.0;
	col = mix(col, col * vec3(1.1, 1.05, 0.82), clamp(macro + 0.5, 0.0, 1.0) * macro_variation);
	ALBEDO = mak_out(col);
	ROUGHNESS = 0.95;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.1, 0.5, ndl) * smoothstep(0.05, 0.7, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(mak_lin(shadow_tint.rgb), vec3(1.0), lit) * 1.05;
}
