// Stylized character / prop shader: soft two-tone ramp, coloured shade, rim light, glossy blob.
// Pair with outline.gdshader as next_pass for an optional ink outline.
shader_type spatial;
// RETRO_LOOK (D032, Docs/ART_V3_RETRO.md): RetroLook builds a variant of this shader with "#define RETRO_LOOK" injected
// (nearest-mipmap texels, world-space texel snapping). Without the define the shader is unchanged.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/stylized_light.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
#ifdef RETRO_LOOK
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
#else
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
#endif
uniform bool use_vertex_color = false;
// Optional tangent-space normal map (OpenGL convention), e.g. from Tripo PBR exports.
#ifdef RETRO_LOOK
uniform sampler2D normal_texture : hint_normal, filter_nearest_mipmap, repeat_enable;
#else
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
#endif
uniform bool use_normal_map = false;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
// World-space triplanar mapping for static props and blockouts (no UV stretching on big boxes).
uniform bool triplanar = false;
uniform float triplanar_scale = 0.35;
uniform vec2 uv_scale = vec2(1.0);
// Retro: triplanar blend sharpness (one projection per face reads as a classic per-face texture, no muddy cross-fades).
uniform float retro_triplanar_sharpness = 24.0;
uniform float ramp_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float ramp_softness : hint_range(0.0, 0.5) = 0.08;
uniform vec4 shadow_tint : source_color = vec4(0.58, 0.5, 0.68, 1.0);
uniform float spec_strength : hint_range(0.0, 2.0) = 0.35;
uniform float spec_size : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.45;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;
#ifdef RETRO_LOOK
// Retro matte pass (D034): ambient/sky reflection amount. RetroLook sets about 0.04 on environment materials;
// gold, brass and gameplay pieces keep the default.
uniform float retro_specular : hint_range(0.0, 1.0) = 0.5;
// Look polish 2026-10-19: optional world-space detail (value-only leaf or rock tile) multiplied over the albedo, so
// untextured foliage puffs and flat-coloured canopies break up into clumps like the textured trees. Off by default.
uniform bool use_detail = false;
uniform sampler2D detail_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
uniform float detail_scale = 0.6;
#endif
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// Hit flash, per instance: mesh_instance.set_instance_shader_parameter("flash", 1.0), then tween it back to 0.
instance uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 v_wpos;
varying vec3 v_wnorm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef RETRO_LOOK
	// Look polish: the normal matrix keeps triplanar weights right on squashed spheres (moss caps read as stripes).
	v_wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
#else
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
#endif
}

void fragment() {
	vec4 tex;
	if (triplanar) {
#ifdef RETRO_LOOK
		vec3 w = pow(abs(normalize(v_wnorm)), vec3(retro_triplanar_sharpness));
#else
		vec3 w = pow(abs(normalize(v_wnorm)), vec3(4.0));
#endif
		w /= (w.x + w.y + w.z);
		vec3 p = v_wpos * triplanar_scale;
		tex = texture(albedo_texture, p.zy * vec2(1.0, -1.0)) * w.x + texture(albedo_texture, p.xz) * w.y
			+ texture(albedo_texture, p.xy * vec2(1.0, -1.0)) * w.z;
	} else {
		tex = texture(albedo_texture, UV * uv_scale);
	}
	vec3 col = mak_lin(albedo.rgb) * mak_lin(tex.rgb);
#ifdef RETRO_LOOK
	if (use_detail) {
		// One sample from the dominant world axis (the retro triplanar is effectively one projection per face anyway);
		// the derivatives come from a continuous projection so the face seams do not drop to the smallest mip.
		vec3 an = abs(normalize(v_wnorm));
		vec3 dp = v_wpos * detail_scale;
		vec2 duv = (an.y >= an.x && an.y >= an.z) ? dp.xz : ((an.x >= an.z) ? dp.zy * vec2(1.0, -1.0) : dp.xy * vec2(1.0, -1.0));
		vec2 g = vec2(length(dFdx(dp)), length(dFdy(dp)));
		col *= mak_lin(textureGrad(detail_texture, duv, vec2(g.x, 0.0), vec2(0.0, g.y)).rgb);
	}
#endif
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	if (use_normal_map && !triplanar) {
		NORMAL_MAP = texture(normal_texture, UV * uv_scale).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	ALBEDO = mak_out(mix(col, mak_lin(flash_color.rgb), flash));
	ROUGHNESS = roughness_value;
#ifdef RETRO_LOOK
	SPECULAR = retro_specular;
#endif
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float rim = smoothstep(rim_threshold, rim_threshold + 0.25, fres);
	EMISSION = mak_out(mak_lin(rim_color.rgb) * rim * rim_strength * 0.6 + mak_lin(emission_color.rgb) * emission_energy
		+ mak_lin(flash_color.rgb) * flash * 0.8);
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		// Local lights (effect flashes, candles): plain wrapped Lambert with distance attenuation.
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION;
	} else {
		sm_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, ramp_threshold, ramp_softness,
			mak_lin(shadow_tint.rgb), spec_strength, spec_size, DIFFUSE_LIGHT, SPECULAR_LIGHT);
		// Light-facing rim: a warm edge that responds to the key light.
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
		float facing = clamp(dot(LIGHT, -VIEW) * 0.5 + 0.5, 0.0, 1.0);
		SPECULAR_LIGHT += LIGHT_COLOR / PI * smoothstep(rim_threshold, rim_threshold + 0.2, fres) * facing * rim_strength * ATTENUATION;
	}
}
