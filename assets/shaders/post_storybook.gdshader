// Storybook ink lines on a 2x2 QuadMesh (see res://scenes/fx/StorybookPost.tscn, FxPost).
// Draws a soft ink line where depth or normals break (silhouettes of props, terrain ridges) as an alpha
// overlay. It deliberately does NOT read the screen texture, so water/refraction shaders keep working.
// Lines fade out with distance so far scenery stays soft. Grade, vignette and paper live in post_grade.gdshader.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec4 line_color : source_color = vec4(0.24, 0.15, 0.13, 1.0);
uniform float line_strength : hint_range(0.0, 1.0) = 0.55;
uniform float line_width = 1.2;
uniform float depth_threshold = 0.06;
uniform float normal_threshold = 0.45;
uniform float line_fade_start = 12.0;
uniform float line_fade_end = 45.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 normal_at(vec2 uv) {
	return texture(normal_tex, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 px = line_width / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float d0 = linear_depth(uv, INV_PROJECTION_MATRIX);
	float d1 = linear_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float d2 = linear_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float d3 = linear_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d4 = linear_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// Relative depth jump (second derivative style, ignores smooth slopes).
	float dd = abs(d1 + d2 - 2.0 * d0) + abs(d3 + d4 - 2.0 * d0);
	float depth_edge = smoothstep(depth_threshold, depth_threshold * 2.0, dd / max(d0, 0.1));
	vec3 n0 = normal_at(uv);
	float nd = (1.0 - dot(n0, normal_at(uv + vec2(px.x, 0.0)))) + (1.0 - dot(n0, normal_at(uv + vec2(0.0, px.y))));
	float normal_edge = smoothstep(normal_threshold, normal_threshold * 1.6, nd);
	float edge = max(depth_edge, normal_edge * 0.7);
	edge *= 1.0 - smoothstep(line_fade_start, line_fade_end, d0);
	// No lines on the sky.
	edge *= step(texture(depth_tex, uv).r, 0.99999) * step(0.00001, texture(depth_tex, uv).r);

	ALBEDO = line_color.rgb;
	ALPHA = clamp(edge * line_strength, 0.0, 1.0);
}
