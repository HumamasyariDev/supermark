shader_type spatial;
// W1 fix round 1 (visual critic r1: the horizon was ~60 identical smooth green ellipsoids): patchwork fields for the
// backdrop hills, in object space so each scaled hill gets fields of a few metres: four field tints in rotated strips,
// dark hedgerow seams and a sunlit crest.
render_mode cull_back;

uniform vec4 c1 : source_color = vec4(0.55, 0.78, 0.35, 1.0);
uniform vec4 c2 : source_color = vec4(0.72, 0.82, 0.38, 1.0);
uniform vec4 c3 : source_color = vec4(0.47, 0.70, 0.33, 1.0);
uniform vec4 c4 : source_color = vec4(0.83, 0.80, 0.48, 1.0);
uniform vec4 seam : source_color = vec4(0.24, 0.42, 0.20, 1.0);
uniform float cell = 0.22;
uniform float seed = 0.0;
uniform float angle = 0.6;

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

void fragment() {
	vec2 p = opos.xz / cell + vec2(opos.y * 0.7, 0.0);
	float ca = cos(angle);
	float sa = sin(angle);
	p = vec2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
	vec2 q = vec2(p.x, p.y * 0.55);
	vec2 id = floor(q);
	vec2 f = fract(q);
	float r = h(id);
	vec3 col = r < 0.3 ? c1.rgb : (r < 0.55 ? c2.rgb : (r < 0.8 ? c3.rgb : c4.rgb));
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y) * 1.8);
	float s = 1.0 - smoothstep(0.025, 0.07, edge);
	col = mix(col, seam.rgb, s * 0.8);
	float top = clamp(opos.y, 0.0, 1.0);
	col *= 0.86 + 0.24 * top;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
