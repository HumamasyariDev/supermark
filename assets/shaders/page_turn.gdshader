// Storybook page-turn transition (canvas_item). Put on a full-screen ColorRect/TextureRect.
// page_texture = a snapshot of the outgoing screen. As progress goes 0 -> 1 that page curls
// from the bottom-right corner over a cylinder and lifts away, showing its parchment back,
// and reveals whatever is drawn underneath (the new scene), or reveal_color if reveal_alpha is 0.
// Driven by res://scripts/fx/page_turn.gd (PageTurn), which any scene can call.
shader_type canvas_item;

uniform sampler2D page_texture : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float radius = 0.12;
uniform vec2 curl_direction = vec2(-1.0, -0.35);
uniform vec4 back_color : source_color = vec4(0.97, 0.91, 0.78, 1.0);
uniform vec4 back_edge_color : source_color = vec4(0.82, 0.68, 0.48, 1.0);
uniform vec4 reveal_color : source_color = vec4(0.16, 0.1, 0.07, 1.0);
// 0 = reveal is fully transparent (new scene shows through), 1 = solid reveal_color.
uniform float reveal_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float shadow_strength = 0.45;
uniform float aspect = 1.7777;

bool inside(vec2 p) {
	return p.x >= 0.0 && p.x <= aspect && p.y >= 0.0 && p.y <= 1.0;
}

vec2 to_uv(vec2 p) {
	return vec2(p.x / aspect, p.y);
}

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);
	// n points the way the page travels (towards the top-left). s measures distance past the fold.
	vec2 n = normalize(curl_direction);
	vec2 back_dir = -n;
	// Project the four corners to find the travel range of the fold line.
	float p0 = dot(vec2(0.0, 0.0), back_dir);
	float p1 = dot(vec2(aspect, 0.0), back_dir);
	float p2 = dot(vec2(0.0, 1.0), back_dir);
	float p3 = dot(vec2(aspect, 1.0), back_dir);
	float pmax = max(max(p0, p1), max(p2, p3));
	float pmin = min(min(p0, p1), min(p2, p3));
	float ease = progress * progress * (3.0 - 2.0 * progress);
	float line = mix(pmax, pmin - radius * 1.2, ease);
	float s = dot(p, back_dir) - line;

	vec4 out_col = vec4(reveal_color.rgb, reveal_alpha);
	// Shadow cast by the curl onto the revealed area.
	float shadow = 0.0;
	if (s > 0.0) {
		shadow = (1.0 - smoothstep(radius, radius * 2.6, s)) * shadow_strength;
	}
	bool drawn = false;
	if (s < radius) {
		// Upper (back side) candidates first: they sit on top.
		float a_up;
		if (s >= 0.0) {
			a_up = radius * (PI - asin(clamp(s / radius, -1.0, 1.0)));
		} else {
			a_up = PI * radius - s;
		}
		vec2 src_up = p + back_dir * (a_up - s);
		if (inside(src_up)) {
			float shade = (s >= 0.0) ? mix(0.75, 1.0, clamp(1.0 - s / radius, 0.0, 1.0)) : 1.0;
			// Show a faded, mirrored hint of the print through the paper.
			vec3 ghost = texture(page_texture, to_uv(src_up)).rgb;
			float lum = dot(ghost, vec3(0.299, 0.587, 0.114));
			vec3 paper = mix(back_color.rgb, back_edge_color.rgb, (1.0 - lum) * 0.18);
			float edge_d = min(min(src_up.x, aspect - src_up.x), min(src_up.y, 1.0 - src_up.y));
			paper = mix(back_edge_color.rgb, paper, smoothstep(0.0, 0.03, edge_d));
			out_col = vec4(paper * shade, 1.0);
			drawn = true;
		} else if (s >= 0.0) {
			float a_dn = radius * asin(clamp(s / radius, -1.0, 1.0));
			vec2 src_dn = p + back_dir * (a_dn - s);
			if (inside(src_dn)) {
				float shade = mix(1.0, 0.55, pow(clamp(s / radius, 0.0, 1.0), 2.0));
				out_col = vec4(texture(page_texture, to_uv(src_dn)).rgb * shade, 1.0);
				drawn = true;
			}
		}
		if (!drawn && s < 0.0) {
			// Flat, untouched part of the page; darken slightly near the fold.
			float near = 1.0 - smoothstep(0.0, radius * 1.5, -s);
			out_col = vec4(texture(page_texture, UV).rgb * (1.0 - near * 0.12), 1.0);
			drawn = true;
		}
	}
	if (!drawn) {
		out_col = vec4(mix(reveal_color.rgb, vec3(0.0), shadow), max(reveal_alpha, shadow));
	}
	COLOR = out_col;
}
