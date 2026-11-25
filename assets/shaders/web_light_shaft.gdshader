shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 color : source_color = vec3(1.0, 0.76, 0.42);
uniform float strength = 0.025;
void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	float separation = -view.z / view.w + VERTEX.z;
	float edge = pow(max(0.0, 1.0 - abs(UV.x * 2.0 - 1.0)), 2.0);
	float ends = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.5, 1.0, UV.y));
	ALBEDO = color;
	ALPHA = strength * edge * ends * clamp(separation / 0.75, 0.0, 1.0);
}
