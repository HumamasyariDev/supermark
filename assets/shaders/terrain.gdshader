// Stylized triplanar terrain. Grass on flat ground, rock on slopes, dirt paths from vertex colour red
// and/or a world-space mask texture. Noise-broken blends keep the edges painterly.
shader_type spatial;
// RETRO_LOOK (D032, Docs/ART_V3_RETRO.md): RetroLook builds a variant of this shader with "#define RETRO_LOOK" injected
// (nearest-mipmap texels, world-space texel snapping). Without the define the shader is unchanged.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

#ifdef RETRO_LOOK
uniform sampler2D grass_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
#else
uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
#endif
#ifdef RETRO_LOOK
uniform sampler2D dirt_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
#else
uniform sampler2D dirt_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
#endif
#ifdef RETRO_LOOK
uniform sampler2D rock_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
#else
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
#endif
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(1.0);
uniform vec4 rock_tint : source_color = vec4(1.0);
uniform float grass_scale = 0.16;
uniform float dirt_scale = 0.2;
uniform float rock_scale = 0.12;
// Surface normal Y above slope_start is fully "flat" (grass/dirt); below slope_end it is rock.
uniform float slope_start : hint_range(0.0, 1.0) = 0.78;
uniform float slope_end : hint_range(0.0, 1.0) = 0.62;
uniform float blend_noise = 0.14;
uniform float triplanar_sharpness = 4.0;
uniform bool use_vertex_color_mask = true;
#ifdef RETRO_LOOK
uniform sampler2D path_mask : hint_default_black, filter_nearest;
#else
uniform sampler2D path_mask : hint_default_black, filter_linear;
#endif
uniform bool use_path_mask = false;
uniform vec4 path_mask_rect = vec4(-60.0, -60.0, 120.0, 120.0); // x, z, width, depth (world)
uniform float macro_variation = 0.14;
uniform vec4 shadow_tint : source_color = vec4(0.5, 0.52, 0.68, 1.0);
// Brightness lift on the grass so meadows read sunny rather than muddy.
uniform float grass_brightness = 1.08;
// Retro: texels per tile of the (downscaled) textures; the layer blends snap to this world-space texel grid.
uniform float retro_texels = 64.0;
// Retro: 0 = pixel-stepped blends at 50 %, 1 = 4x4 ordered-dither blends between grass, dirt and rock.
uniform float retro_dither = 1.0;

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying vec4 v_color;

#ifdef RETRO_LOOK
// 4x4 ordered-dither threshold for an integer cell (classic stippled blends between texture layers).
float retro_bayer4(vec2 cell) {
	ivec2 c = ivec2(mod(cell, 4.0));
	int i = c.x + c.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}
#endif

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

void fragment() {
	vec3 n = normalize(v_wnorm);
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	w /= (w.x + w.y + w.z);
	// World position used by the layer blends. Retro: snapped to the grass texel grid so every blend edge is a crisp texel step.
	vec3 bp = v_wpos;
#ifdef RETRO_LOOK
	float grid = max(grass_scale * retro_texels, 0.001);
	vec2 cell = floor(v_wpos.xz * grid);
	bp.xz = (cell + 0.5) / grid;
	float dth = mix(0.5, retro_bayer4(cell), retro_dither);
	// Fix round 1 (critic minor): no stipple right at the player's feet; within about 6 m the blends are clean texel steps.
	dth = mix(dth, 0.5, 1.0 - smoothstep(4.0, 8.0, length(VERTEX)));
#endif
	float nz = sm_fbm(bp.xz * 0.35) - 0.5;
	// Two rotated grass samples hide repetition.
	vec2 g = v_wpos.xz * grass_scale;
	vec3 grass_a = mak_lin(texture(grass_texture, g).rgb);
	vec3 grass_b = mak_lin(texture(grass_texture, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * g * 0.61 + 0.37).rgb);
#ifdef RETRO_LOOK
	vec3 grass = (step(dth, smoothstep(0.35, 0.65, sm_fbm(bp.xz * 0.05))) > 0.5 ? grass_b : grass_a) * mak_lin(grass_tint.rgb) * grass_brightness;
#else
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.35, 0.65, sm_fbm(v_wpos.xz * 0.05))) * mak_lin(grass_tint.rgb) * grass_brightness;
#endif
	vec3 dirt = mak_lin(texture(dirt_texture, v_wpos.xz * dirt_scale).rgb) * mak_lin(dirt_tint.rgb);
	vec3 rock = mak_lin(tri(rock_texture, v_wpos, w, rock_scale)) * mak_lin(rock_tint.rgb);
	float up = n.y + nz * blend_noise;
	float flat_w = smoothstep(slope_end, slope_start, up);
	float path = use_vertex_color_mask ? v_color.r : 0.0;
	if (use_path_mask) {
		vec2 muv = (bp.xz - path_mask_rect.xy) / path_mask_rect.zw;
		path = max(path, texture(path_mask, muv).r);
	}
	path = smoothstep(0.38, 0.62, path + nz * 0.45);
#ifdef RETRO_LOOK
	// Dithered, texel-sized steps instead of soft cross-fades (no smeared half-grass, half-dirt texels).
	path = step(dth, path);
	flat_w = step(dth, flat_w);
#endif
	vec3 top = mix(grass, dirt, path);
	vec3 col = mix(rock, top, flat_w);
	float macro = sm_fbm(bp.xz * 0.03) - 0.5;
#ifdef RETRO_LOOK
	// Macro tint in a few flat bands (limited palette) instead of a continuous gradient.
	macro = (floor((macro + 0.5) * 4.0 + dth) / 4.0) - 0.5;
#endif
	col *= 1.0 + macro * macro_variation * 2.0;
	col = mix(col, col * vec3(1.1, 1.05, 0.82), clamp(macro + 0.5, 0.0, 1.0) * macro_variation);
	ALBEDO = mak_out(col);
	ROUGHNESS = 0.95;
#ifdef RETRO_LOOK
	// Matte pass (D034): no sky sheen on the ground.
	ROUGHNESS = 1.0;
	SPECULAR = 0.04;
#endif
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		// Local lights (effect flashes, candles): plain wrapped Lambert with distance attenuation.
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION;
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lit = smoothstep(-0.1, 0.5, ndl) * smoothstep(0.05, 0.7, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(mak_lin(shadow_tint.rgb), vec3(1.0), lit) * 1.05;
	}
}
