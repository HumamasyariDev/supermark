// Shared body of the W3 liquid shaders (w3_liquid / w3_liquid_curtain).
#include "res://assets/shaders/inc/noise.gdshaderinc"

uniform vec4 dark_color : source_color = vec4(0.29, 0.13, 0.06, 1.0);
uniform vec4 mid_color : source_color = vec4(0.48, 0.25, 0.12, 1.0);
uniform vec4 cream_color : source_color = vec4(0.88, 0.70, 0.52, 1.0);
uniform vec4 pop_color : source_color = vec4(1.0, 0.54, 0.24, 1.0);   // hazard #FF8A3D
uniform float pop_amount = 1.0;
uniform vec2 flow = vec2(1.0, 0.15);
uniform float flow_speed = 0.35;
uniform float swirl_scale = 0.32;
uniform float curtain_speed = 1.6;
uniform float alpha_mul = 1.0;
uniform float gloss = 0.9;
uniform float self_glow = 0.18;

varying vec3 v_wpos;
varying vec4 v_col;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
	#ifndef CURTAIN
	{
		VERTEX.y += (sm_vnoise(v_wpos.xz * 0.35 + TIME * 0.25) - 0.5) * 0.06;
	}
#endif
}

void fragment() {
#ifdef CURTAIN
	vec2 p = vec2(UV.x * 6.0, UV.y * 3.0 - TIME * curtain_speed);
#else
	vec2 p = v_wpos.xz * swirl_scale - normalize(flow) * TIME * flow_speed * 0.5;
#endif
	vec2 warp = vec2(sm_fbm_rot(p + vec2(TIME * 0.05, 0.0), 3), sm_fbm_rot(p * 1.3 + 5.2, 3));
	float m = sm_fbm_rot((p + warp * 1.3) * 1.2, 4);
	float bands = smoothstep(0.62, 0.95, sin(m * 15.0) * 0.5 + 0.5);
	vec3 col = mix(dark_color.rgb, mid_color.rgb, smoothstep(0.3, 0.7, m));
	col = mix(col, mix(mid_color.rgb, cream_color.rgb, 0.45), bands * 0.45);
	float e = 0.05;
	float hx = sm_fbm_rot((p + vec2(e, 0.0) + warp * 1.3) * 1.2, 4);
	float hz = sm_fbm_rot((p + vec2(0.0, e) + warp * 1.3) * 1.2, 4);
	vec3 nn = normalize(vec3((m - hx) * 3.0, 1.0, (m - hz) * 3.0));
	NORMAL_MAP = vec3(nn.x, nn.z, nn.y) * 0.5 + 0.5;
	// Shore foam (creamy rim).
	float foam = smoothstep(0.35, 0.8, v_col.r + (sm_vnoise(v_wpos.xz * 1.8 + TIME * 0.3) - 0.5) * 0.35);
	col = mix(col, cream_color.rgb, foam * 0.85);
	// Bubbles that rise, grow and pop with an orange flash (hazard read).
	vec2 bp = v_wpos.xz * 0.7;
#ifdef CURTAIN
	bp = p * 1.5;
#endif
	vec2 cell = floor(bp);
	float rnd = sm_hash21(cell);
	float life = fract(TIME * 0.45 + rnd * 7.0);
	vec2 c = cell + 0.5 + (vec2(sm_hash21(cell + 3.1), sm_hash21(cell + 8.7)) - 0.5) * 0.5;
	float r = length(bp - c);
	float active = step(rnd, 0.35);
	float rad = 0.07 + life * 0.22;
	float bubble = (1.0 - smoothstep(rad - 0.03, rad, r)) * active * smoothstep(0.0, 0.2, life) * (1.0 - smoothstep(0.82, 0.9, life));
	float ring = (1.0 - smoothstep(0.0, 0.035, abs(r - rad))) * active * (1.0 - smoothstep(0.85, 0.95, life));
	float pop = (1.0 - smoothstep(0.0, 0.05, abs(r - (0.25 + (life - 0.88) * 3.0)))) * active * step(0.88, life);
	col = mix(col, mix(col, cream_color.rgb, 0.35), bubble);
	col = mix(col, pop_color.rgb, (ring * 0.55 + pop) * pop_amount);
	ALBEDO = col;
	ROUGHNESS = 0.22;
	EMISSION = col * self_glow + pop_color.rgb * (ring * 0.6 + pop * 2.0) * pop_amount;
#ifdef CURTAIN
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	ALPHA = clamp(edge * alpha_mul, 0.0, 1.0);
#endif
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.2, 0.6, ndl) * smoothstep(0.05, 0.6, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(vec3(0.72, 0.52, 0.5), vec3(1.0), lit);
	vec3 h = normalize(LIGHT + VIEW);
	float s = pow(max(dot(NORMAL, h), 0.0), 70.0);
	s = smoothstep(0.25, 0.6, s) * gloss;
	SPECULAR_LIGHT += LIGHT_COLOR / PI * vec3(1.0, 0.93, 0.85) * s * ATTENUATION;
}
