shader_type spatial;
// Fix r2 (visual major, D032): the shelf book spines were flat colour boxes, the largest surface in every hub frame.
// Per-instance painted spines on the BookSpines MultiMesh: one or two gilt bands near the top and bottom, a dark
// title block on some, a worn darker top, all as hard-edged steps (crisp low-res read, no smooth gradients). The
// instance colour stays a multiply, a little darker and calmer than before. Cell choice is a hash of INSTANCE_ID.
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform float value_mul = 0.8;
uniform float sat_mul = 0.85;
uniform vec3 gilt = vec3(0.79, 0.63, 0.29);
uniform float steps_y = 48.0;

varying vec3 lp;
varying float vid;

float h1(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

void vertex() {
	lp = VERTEX;
	vid = float(INSTANCE_ID);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat_mul) * value_mul;
	// Snap the pattern coordinate to a coarse grid so edges read as texels.
	float y = floor(lp.y * steps_y) / steps_y;
	float x = floor(lp.x * 8.0) / 8.0;
	float r = h1(vid);
	float band_y = 0.29 + 0.06 * floor(r * 3.0);
	float g = step(abs(abs(y) - band_y), 0.022);
	g = max(g, step(0.45, h1(vid + 3.1)) * step(abs(abs(y) - (band_y - 0.075)), 0.011));
	float label_c = 0.06 + 0.12 * h1(vid + 7.3);
	float label = step(abs(y - label_c), 0.065) * step(abs(x), 0.32) * step(0.3, h1(vid + 5.7));
	vec3 col = c;
	col = mix(col, c * 0.42, label);
	col = mix(col, gilt * 0.9, g);
	col = mix(col, col * 0.72, step(0.44, y));
	ALBEDO = mak_out(col);
	ROUGHNESS = mix(0.88, 0.5, g);
	METALLIC = 0.0;
	SPECULAR = mix(0.15, 0.4, g);
}
