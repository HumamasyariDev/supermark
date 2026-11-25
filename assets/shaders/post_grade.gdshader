// Storybook grade (canvas_item, full-screen ColorRect under the HUD): gentle split-tone, saturation,
// a vignette and a faint paper grain. Reads the finished 3D frame, including transparent water.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D paper_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float vignette = 0.18;
uniform vec4 grade_shadows : source_color = vec4(0.98, 0.97, 1.03, 1.0);
uniform vec4 grade_highlights : source_color = vec4(1.03, 1.01, 0.97, 1.0);
uniform float paper_amount = 0.025;
uniform float paper_scale = 2.5;
uniform float saturation = 1.1;
uniform float aspect = 1.7777;

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col *= mix(grade_shadows.rgb, grade_highlights.rgb, smoothstep(0.1, 0.8, lum));
	col = mix(vec3(lum), col, saturation);
	float paper = texture(paper_tex, SCREEN_UV * vec2(aspect, 1.0) * paper_scale).r;
	col *= mix(1.0, paper * 1.08, paper_amount);
	vec2 c = SCREEN_UV - 0.5;
	col *= 1.0 - dot(c, c) * vignette * 1.6;
	COLOR = vec4(col, 1.0);
}
