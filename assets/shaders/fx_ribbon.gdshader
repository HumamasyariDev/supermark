// Animated ribbon for wind lines (GustSwirl) and the Snout Sniff scent trail (ScentTrail).
// UV.x runs along the ribbon (0 start, 1 end), UV.y across it. Dashes scroll along UV.x.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
uniform float intensity = 1.4;
uniform float scroll_speed = 0.6;
uniform float dash_count = 3.0;
uniform float dash_fill : hint_range(0.0, 1.0) = 0.55;
uniform float wisp = 0.6;
uniform float fade_in = 0.08;
uniform float fade_out = 0.25;
// Global visibility 0..1 (scripts animate this for appear/disappear).
uniform float visibility : hint_range(0.0, 1.0) = 1.0;
// How far the ribbon has grown from its start (0..1), for draw-on animation.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float x = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float t = TIME * scroll_speed;
	float dash = fract(x * dash_count - t);
	float d = smoothstep(0.0, 0.08, dash) * (1.0 - smoothstep(dash_fill - 0.08, dash_fill, dash));
	if (dash_fill >= 0.99) {
		d = 1.0;
	}
	float n = sm_fbm(vec2(x * 6.0 - t * 2.0, UV.y * 2.0 + t));
	float width = mix(0.55, 1.0, n * wisp + (1.0 - wisp) * 0.6);
	float core = 1.0 - smoothstep(0.0, width * 0.35, across);
	float body = 1.0 - smoothstep(width * 0.3, width, across);
	float ends = smoothstep(0.0, fade_in, x) * (1.0 - smoothstep(1.0 - fade_out, 1.0, x));
	float grow = 1.0 - smoothstep(reveal - 0.05, reveal, x);
	float a = body * d * ends * grow * visibility;
	vec3 c = mix(mak_lin(color.rgb), mak_lin(core_color.rgb), core);
	ALBEDO = c * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
