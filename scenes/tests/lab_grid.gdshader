shader_type spatial;
// MoveLab measuring material: world-space 1 m grid lines and bold 5 m lines over a soft base colour.

uniform vec4 base_color : source_color = vec4(0.55, 0.72, 0.42, 1.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_strength = 0.24;
uniform float roughness_value = 0.86;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(vec2 p, float width) {
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(1e-4));
	return 1.0 - min(min(g.x, g.y) / width, 1.0);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.y > 0.6 ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
	float g1 = grid_line(uv, 1.0) * 0.45;
	float g5 = grid_line(uv / 5.0, 1.6);
	float l = clamp(max(g1, g5) * line_strength, 0.0, 1.0);
	// Gentle large-scale tint variation so big surfaces do not read as flat grey.
	float tint = 0.04 * sin(wpos.x * 0.21) * sin(wpos.z * 0.17);
	ALBEDO = mix(base_color.rgb * (1.0 + tint), line_color.rgb, l);
	ROUGHNESS = roughness_value;
}
