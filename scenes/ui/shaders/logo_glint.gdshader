shader_type canvas_item;
// Title logo glint: a 12-degree highlight band sweeps across the lettering every few seconds.
// It only lifts the bright cream and gold areas (alpha-masked), so the dark rim never turns grey.

uniform float period = 4.6;
uniform float sweep_time = 1.05;
uniform float band = 0.075;
uniform float strength = 0.55;
uniform float phase = 0.0;

void fragment() {
	vec4 c = COLOR; // already TEXTURE * modulate
	float t = mod(TIME + phase, period) / sweep_time;
	float pos = mix(-0.35, 1.35, clamp(t, 0.0, 1.0));
	float d = UV.x + (1.0 - UV.y) * 0.2126; // tan(12 deg)
	float k = smoothstep(band, 0.0, abs(d - pos)) * step(t, 1.0);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float m = smoothstep(0.45, 0.8, lum);
	c.rgb += vec3(1.0, 0.97, 0.88) * k * strength * m;
	COLOR = c;
}
