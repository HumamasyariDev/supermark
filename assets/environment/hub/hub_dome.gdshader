shader_type spatial;
render_mode cull_disabled;
// Hub dome: painted storybook sky ceiling with soft clouds; UV.y runs from the rim (0) up the profile in metres.
uniform vec4 sky_top : source_color = vec4(0.45, 0.62, 0.86, 1.0);
uniform vec4 sky_rim : source_color = vec4(0.98, 0.84, 0.62, 1.0);
uniform vec4 cloud_col : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.86, 0.78, 0.82, 1.0);
uniform float rim_len = 9.0;
uniform float glow = 0.22;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float h = clamp(UV.y / rim_len, 0.0, 1.0);
	vec3 col = mix(sky_rim.rgb, sky_top.rgb, smoothstep(0.0, 0.75, h));
	vec2 cp = vec2(UV.x * 0.16, UV.y * 0.35);
	float c = fbm(cp * 1.4 + vec2(TIME * 0.004, 0.0));
	float cl = smoothstep(0.5, 0.64, c) * (1.0 - smoothstep(0.85, 1.0, h));
	vec3 cloud = mix(cloud_shade.rgb, cloud_col.rgb, smoothstep(0.45, 0.8, fbm(cp * 2.2 + 3.0)));
	col = mix(col, cloud, cl * 0.9);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	EMISSION = col * glow;
}
