// Storybook UI panel: parchment (or leather) fill, rounded corners, ink border, inner gilt line,
// soft drop shadow and a warm vignette. Used on PanelContainers whose StyleBoxFlat is expanded
// by `shadow_px` so the shadow has geometry. Set `size` from script (UIStyle does it).
shader_type canvas_item;
render_mode blend_mix;

uniform vec2 size = vec2(400.0, 200.0);
uniform sampler2D fill_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = true;
uniform vec4 tint : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 fill_color : source_color = vec4(0.97, 0.91, 0.78, 1.0);
uniform vec4 border_color : source_color = vec4(0.36, 0.22, 0.12, 1.0);
uniform vec4 gilt_color : source_color = vec4(0.82, 0.64, 0.28, 1.0);
uniform vec4 vignette_color : source_color = vec4(0.62, 0.42, 0.2, 1.0);
uniform float radius = 18.0;
uniform float border = 4.0;
uniform float gilt_inset = 9.0;
uniform float gilt_width = 1.6;
uniform float shadow_px = 14.0;
uniform float shadow_alpha = 0.35;
uniform float vignette = 0.45;
uniform float tex_scale = 640.0;
uniform float alpha = 1.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = size * 0.5;
	vec2 p = local - half_size;
	float d = sd_round_rect(p, half_size, radius);
	float aa = 1.0;
	// Shadow (offset down)
	float ds = sd_round_rect(p - vec2(0.0, shadow_px * 0.35), half_size, radius);
	float sh = (1.0 - smoothstep(-shadow_px * 0.3, shadow_px, ds)) * shadow_alpha;
	vec4 col = vec4(0.12, 0.06, 0.02, sh);
	if (d < aa) {
		vec3 fill = fill_color.rgb;
		if (use_tex) {
			// two offset, rotated samples hide the texture's wrap seam and patch edges (critique UI r1)
			vec2 uv = local / tex_scale;
			vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.77 + vec2(0.37, 0.61);
			vec3 ta = texture(fill_tex, uv).rgb;
			vec3 tb = texture(fill_tex, uv2).rgb;
			vec3 tm = (ta + tb) * 0.5;
			float lum = dot(tm, vec3(0.299, 0.587, 0.114));
			fill = mix(vec3(lum), tm, 1.1) * tint.rgb;
		}
		// vignette toward the edges
		float edge = clamp(-d / (min(half_size.x, half_size.y) * 0.9), 0.0, 1.0);
		fill = mix(fill, fill * vignette_color.rgb * 1.25, (1.0 - smoothstep(0.0, 0.55, edge)) * vignette);
		// gilt inner line
		float g = abs(d + gilt_inset) - gilt_width * 0.5;
		fill = mix(fill, gilt_color.rgb, (1.0 - smoothstep(-0.6, 0.8, g)) * gilt_color.a);
		// ink border
		float b = smoothstep(-border - 0.8, -border + 0.6, d);
		fill = mix(fill, border_color.rgb, b);
		float inside = 1.0 - smoothstep(-0.8, 0.6, d);
		col = mix(col, vec4(fill, 1.0), inside);
		col.a = max(col.a, inside);
	}
	col.a *= alpha;
	COLOR = col;
}
