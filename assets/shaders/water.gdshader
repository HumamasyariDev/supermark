// Stylized stream / pond water: depth tint (shallow turquoise to deep blue), scrolling procedural
// normals along a flow direction, white foam where water meets geometry, painted sparkle bands,
// light refraction of the screen behind. Use on a flat plane (or a stream ribbon mesh).
shader_type spatial;
// RETRO_LOOK (D032, Docs/ART_V3_RETRO.md): RetroLook builds a variant of this shader with "#define RETRO_LOOK" injected
// (nearest-mipmap texels, world-space texel snapping). Without the define the shader is unchanged.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://assets/shaders/inc/noise.gdshaderinc"

uniform vec4 shallow_color : source_color = vec4(0.36, 0.86, 0.82, 1.0);
uniform vec4 deep_color : source_color = vec4(0.1, 0.38, 0.62, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 0.98, 1.0);
uniform float depth_distance = 2.2;
uniform float clarity = 0.55;
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed = 0.6;
uniform float ripple_scale = 1.1;
uniform float normal_strength = 0.35;
uniform float foam_distance = 0.35;
uniform float foam_noise_scale = 3.0;
uniform float refraction = 0.03;
uniform float sparkle_amount = 0.8;
// On ribbon meshes, flow follows the mesh TANGENT (world space) instead of flow_direction, so the
// current bends with the river. The ripple pattern itself stays in world XZ (no stretching).
uniform bool flow_along_uv = false;
uniform float wave_height = 0.04;
// Retro: world-space texels per metre for the ripple, foam and sparkle patterns (chunky, crisp water texels).
uniform float retro_texels_per_m = 10.0;
// Retro: the ripple pattern animates at this many frames per second (classic stepped texture animation; 0 = smooth).
uniform float retro_anim_fps = 0.0;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 v_wpos;
varying vec2 v_flow;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_flow = (MODEL_MATRIX * vec4(TANGENT, 0.0)).xz;
	float t = TIME * flow_speed;
	VERTEX.y += (sin(v_wpos.x * 1.7 + t * 2.0) + cos(v_wpos.z * 1.3 - t * 1.6)) * wave_height;
}

float height_static(vec2 p) {
	float slow = TIME * 0.05;
	float a = sm_fbm(p * ripple_scale + slow);
	float b = sm_fbm(p * ripple_scale * 1.7 + vec2(3.1, 7.7) - slow);
	return a * 0.6 + b * 0.4;
}

// Two-phase flow-map advection: stable at river bends and over long play sessions.
float height_at(vec2 p, float t, vec2 dir) {
	float k = 3.0;
	float ph0 = fract(t * 0.25);
	float ph1 = fract(ph0 + 0.5);
	float w = abs(ph0 * 2.0 - 1.0);
	float h0 = height_static(p - dir * ph0 * k);
	float h1 = height_static(p - dir * ph1 * k + vec2(0.37, 0.71));
	return mix(h0, h1, w);
}

void fragment() {
	vec2 dir = normalize(flow_direction + vec2(0.0001));
	if (flow_along_uv && length(v_flow) > 0.001) {
		dir = normalize(v_flow);
	}
	vec2 p = v_wpos.xz;
	float t = TIME * flow_speed;
	float e = 0.08;
#ifdef RETRO_LOOK
	p = (floor(p * retro_texels_per_m) + 0.5) / retro_texels_per_m;
	e = 1.0 / retro_texels_per_m;
	if (retro_anim_fps > 0.0) {
		t = floor(TIME * retro_anim_fps) / retro_anim_fps * flow_speed;
	}
#endif
	float h0 = height_at(p, t, dir);
	float hx = height_at(p + vec2(e, 0.0), t, dir);
	float hz = height_at(p + vec2(0.0, e), t, dir);
	vec3 n_tan = normalize(vec3((h0 - hx) / e * normal_strength, 1.0, (h0 - hz) / e * normal_strength));
	// Tangent-space normal for Godot: x = tangent, y = binormal, z = normal.
	NORMAL_MAP = vec3(n_tan.x, n_tan.z, n_tan.y) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Scene depth behind the water.
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world_behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	world_behind.xyz /= world_behind.w;
	float water_depth = max(-world_behind.z - (-VERTEX.z), 0.0);
	float depth_fac = clamp(water_depth / depth_distance, 0.0, 1.0);

	// Refraction, pulled back where it would sample geometry in front of the water.
	vec2 ruv = SCREEN_UV + (n_tan.xz) * refraction * depth_fac;
	float rdepth = texture(depth_tex, ruv).r;
	vec4 rb = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, rdepth, 1.0);
	rb.xyz /= rb.w;
	if (-rb.z < -VERTEX.z) {
		ruv = SCREEN_UV;
	}
	vec3 behind = textureLod(screen_tex, ruv, 1.0).rgb;

	vec3 water = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, depth_fac));
	vec3 col = mix(water, behind * shallow_color.rgb * 1.2, (1.0 - depth_fac) * clarity);

	// Foam: edge band broken by animated cells, plus streaks along the flow.
	float cells = sm_cells(p * foam_noise_scale - dir * t * 1.5);
	float edge = 1.0 - smoothstep(0.0, foam_distance, water_depth);
	float foam = step(cells, edge * 0.95 + 0.05 * sin(TIME * 3.0 + p.x * 4.0));
#ifdef RETRO_LOOK
	// Fix round 1 (critic minor): on the snapped texel grid the flow streaks and sun sparkles scattered single white
	// texels over the river that shimmered in motion. Retro water keeps only the solid edge-foam band.
	float spark = 0.0;
#else
	foam = max(foam, smoothstep(0.82, 0.9, height_at(p * 0.8, t * 1.4, dir)) * 0.7);
	// Painted sun sparkles.
	float spark = smoothstep(0.78, 0.8, h0) * sparkle_amount;
#endif
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	EMISSION = foam_color.rgb * spark * 0.4 + col * 0.06;
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.6;
	ALPHA = 1.0;
}
