// Hot-chocolate river / pool: thick glossy liquid with a slow marbled swirl, creamy edge foam,
// a lazy bulging surface and bubble rings that rise and pop. Opaque (cheap, no depth reads).
// edge_mode: 0 = no edge foam, 1 = river ribbon (foam where UV.y nears 0 or 1),
//            2 = round pool (foam where the UV distance from the centre nears 0.5).
shader_type spatial;
// RETRO_LOOK (D032, Docs/ART_V3_RETRO.md): RetroLook builds a variant of this shader with "#define RETRO_LOOK" injected
// (nearest-mipmap texels, world-space texel snapping). Without the define the shader is unchanged.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/noise.gdshaderinc"

uniform vec4 dark_color : source_color = vec4(0.24, 0.1, 0.04, 1.0);
uniform vec4 mid_color : source_color = vec4(0.46, 0.22, 0.09, 1.0);
uniform vec4 cream_color : source_color = vec4(0.96, 0.84, 0.68, 1.0);
uniform vec2 flow_direction = vec2(1.0, 0.2);
uniform float flow_speed = 0.12;
uniform float swirl_scale = 0.55;
uniform float swirl_strength = 1.4;
uniform int edge_mode = 2;
uniform float edge_width = 0.08;
uniform float bubble_density = 0.5;
uniform float wave_height = 0.05;
uniform float gloss = 0.9;
// Discard outside the inscribed circle of the UV square (round pools on a plane mesh).
uniform bool round_clip = false;
uniform vec4 highlight_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
// Retro: world-space texels per metre for the marble, bubbles and foam (crisp cocoa texels).
uniform float retro_texels_per_m = 8.0;
// Retro: number of flat colour bands in the marble (limited palette).
uniform float retro_bands = 5.0;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.6;
	VERTEX.y += (sm_vnoise(v_wpos.xz * 0.4 + t * 0.3) - 0.5) * wave_height * 2.0;
}

float marble(vec2 p, float t) {
	vec2 warp = vec2(sm_fbm_rot(p + vec2(t * 0.3, -t * 0.2), 3), sm_fbm_rot(p * 1.3 + vec2(-t * 0.25, t * 0.15) + 5.2, 3));
	return sm_fbm_rot((p + warp * swirl_strength) * 1.4, 4);
}

void fragment() {
	if (round_clip && length(UV - 0.5) > 0.5) {
		discard;
	}
	float t = TIME * flow_speed;
	vec2 dir = normalize(flow_direction + vec2(0.0001));
	vec3 wq = v_wpos;
#ifdef RETRO_LOOK
	wq.xz = (floor(wq.xz * retro_texels_per_m) + 0.5) / retro_texels_per_m;
#endif
	vec2 p = wq.xz * swirl_scale - dir * t * 2.0;
	float st = TIME * 0.08;
	float m = marble(p, st);
#ifdef RETRO_LOOK
	m = floor(m * retro_bands + 0.5) / retro_bands;
#endif
	float bands = sin(m * 16.0) * 0.5 + 0.5;
	bands = smoothstep(0.6, 0.95, bands);
	vec3 col = mix(dark_color.rgb, mid_color.rgb, smoothstep(0.3, 0.7, m));
	col = mix(col, mix(mid_color.rgb, cream_color.rgb, 0.4), bands * 0.5);

	float e = 0.06;
	float hx = marble(p + vec2(e, 0.0), st);
	float hz = marble(p + vec2(0.0, e), st);
	vec3 n = normalize(vec3((m - hx) * 2.5, 1.0, (m - hz) * 2.5));
	NORMAL_MAP = vec3(n.x, n.z, n.y) * 0.5 + 0.5;

	float edge = 0.0;
	if (edge_mode == 1) {
		edge = min(UV.y, 1.0 - UV.y);
	} else if (edge_mode == 2) {
		edge = 0.5 - length(UV - 0.5);
	}
	float foam = 0.0;
	if (edge_mode > 0) {
		float wob = (sm_vnoise(wq.xz * 2.5 + TIME * 0.4) - 0.5) * edge_width * 0.8;
		foam = 1.0 - smoothstep(edge_width * 0.6, edge_width, edge + wob);
	}

	// Bubble rings that appear, grow and pop.
	vec2 bp = wq.xz * 1.1;
	vec2 cell = floor(bp);
	float rnd = sm_hash21(cell);
	float life = fract(TIME * 0.3 + rnd * 7.0);
	vec2 c = cell + 0.5 + (vec2(sm_hash21(cell + 3.1), sm_hash21(cell + 8.7)) - 0.5) * 0.5;
	float r = length(bp - c);
	float ring = (1.0 - smoothstep(0.0, 0.04, abs(r - life * 0.32))) * step(rnd, bubble_density) * (1.0 - life);
	col = mix(col, cream_color.rgb * 0.85, ring * 0.7);
	col = mix(col, cream_color.rgb, foam);

	ALBEDO = col;
	// Keep sky reflections tiny (they turned the cocoa lavender); the glossy look comes from light().
	ROUGHNESS = 0.45;
	SPECULAR = 0.08;
	// Self-warmth keeps the cocoa rich under cool sky ambient.
	EMISSION = col * 0.22;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		// Local lights (effect flashes, candles): plain wrapped Lambert with distance attenuation.
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION;
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lit = smoothstep(-0.2, 0.6, ndl) * smoothstep(0.05, 0.6, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(vec3(0.7, 0.5, 0.4), vec3(1.0), lit);
		// Long glossy painted highlight.
		vec3 h = normalize(LIGHT + VIEW + vec3(0.0, 1e-4, 0.0));
		float s = pow(max(dot(NORMAL, h), 0.0), 60.0);
		s = smoothstep(0.25, 0.6, s) * gloss;
		SPECULAR_LIGHT += LIGHT_COLOR / PI * highlight_color.rgb * s * ATTENUATION;
	}
}
