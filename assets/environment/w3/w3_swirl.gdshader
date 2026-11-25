// Lollipop swirl disc: polar spiral stripes in up to four colours, glossy candy.
// UV = local position / radius (centre 0,0). Used on the Great Lollipop and procedural lollipops.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 c1 : source_color = vec4(1.0, 0.5, 0.69, 1.0);
uniform vec4 c2 : source_color = vec4(1.0, 0.97, 0.93, 1.0);
uniform vec4 c3 : source_color = vec4(0.5, 0.88, 0.76, 1.0);
uniform vec4 c4 : source_color = vec4(1.0, 0.88, 0.48, 1.0);
uniform float arms = 4.0;
uniform float twist = 5.0;
uniform float spin_speed = 0.0;

void fragment() {
	vec2 q = UV;
	float r = length(q);
	float a = atan(q.y, q.x) + TIME * spin_speed;
	float s = fract((a / 6.2831853) * arms + r * twist);
	vec3 col;
	if (s < 0.25) { col = c1.rgb; } else if (s < 0.5) { col = c2.rgb; } else if (s < 0.75) { col = c3.rgb; } else { col = c4.rgb; }
	// soft blend between stripes
	float edge = min(min(abs(s - 0.25), abs(s - 0.5)), min(abs(s - 0.75), min(s, 1.0 - s)));
	col = mix(col * 0.92, col, smoothstep(0.0, 0.03, edge));
	col = mix(col, vec3(1.0), smoothstep(0.96, 1.0, r) * 0.3);
	ALBEDO = col;
	ROUGHNESS = 0.18;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.08;
	RIM = 0.25;
	RIM_TINT = 0.5;
}
