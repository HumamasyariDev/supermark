shader_type spatial;
// W3 frosting slide (R1 visual major: the slide was untextured pale cyan with flat banding, val_std 0.054).
// R2.9 colours: bed #8FD0F5, walls #5BB0E6 (darker and more saturated than the bed), a bright rounded lip,
// rainbow sprinkles about every 2 m and a scrolling sheen that reads as speed. World-space, so no UVs are needed.

#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 bed_color : source_color = vec4(0.561, 0.816, 0.961, 1.0);
uniform vec4 wall_color : source_color = vec4(0.357, 0.69, 0.902, 1.0);
uniform vec4 lip_color : source_color = vec4(0.93, 0.97, 1.0, 1.0);
uniform float sprinkle_density = 0.11;
uniform float sheen_speed = 2.2;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float up = clamp(wnrm.y, 0.0, 1.0);
	float wall = 1.0 - smoothstep(0.55, 0.85, up);
	vec3 col = mix(mak_lin(bed_color.rgb), mak_lin(wall_color.rgb), wall);
	// Lip: the baked vertex colour marks the rim (lighter than the bed); keep it as a bright rounded edge.
	float lum = dot(COLOR.rgb, vec3(0.333));
	col = mix(col, mak_lin(lip_color.rgb), smoothstep(0.88, 0.97, lum) * 0.8);
	// Low-frequency swirl so the bed is not one flat value.
	float sw = sin(wpos.x * 0.45 + sin(wpos.z * 0.33) * 1.7) * 0.5 + 0.5;
	col *= mix(0.92, 1.06, sw);
	// Sprinkles (only on the bed).
	vec2 cell = floor(wpos.xz * 2.2);
	vec2 f = fract(wpos.xz * 2.2) - 0.5;
	float h = hash(cell);
	if (h < sprinkle_density && up > 0.8) {
		float ang = hash(cell + 7.0) * 6.2832;
		vec2 d = vec2(cos(ang), sin(ang));
		float along = dot(f, d);
		float across = dot(f, vec2(-d.y, d.x));
		float m = step(abs(along), 0.24) * step(abs(across), 0.07);
		float k = hash(cell + 3.0);
		vec3 sc = k < 0.2 ? vec3(1.0, 0.37, 0.64) : k < 0.4 ? vec3(1.0, 0.88, 0.29) : k < 0.6 ? vec3(0.37, 0.88, 0.78) : k < 0.8 ? vec3(1.0, 0.54, 0.24) : vec3(1.0);
		col = mix(col, sc, m);
	}
	// Scrolling sheen band.
	float sheen = pow(max(0.0, sin(dot(wpos.xz, vec2(0.35, 0.55)) * 0.9 - TIME * sheen_speed)), 12.0);
	ALBEDO = mak_out(col);
	ROUGHNESS = 0.28;
	SPECULAR = 0.6;
	EMISSION = mak_out(vec3(0.9, 0.97, 1.0) * sheen * 0.22 * up);
	RIM = 0.35;
	RIM_TINT = 0.4;
}
