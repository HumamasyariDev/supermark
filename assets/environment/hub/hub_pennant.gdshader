shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/inc/web_color.gdshaderinc"
// Bunting flags (r1 visual round 2): UV.y = 0 on the string, 1 at the flag tip. The tip flutters; the string holds.
uniform float sway = 0.07;
uniform float speed = 1.6;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = UV.y * UV.y;
	float ph = wp.x * 0.7 + wp.z * 0.5;
	VERTEX += NORMAL * sin(TIME * speed + ph) * sway * k * 3.0;
	VERTEX.y += sin(TIME * speed * 0.7 + ph * 1.3) * sway * 0.4 * k;
}

void fragment() {
	ALBEDO = mak_out(COLOR.rgb);
	ROUGHNESS = 0.85;
	BACKLIGHT = COLOR.rgb * 0.35;
}
