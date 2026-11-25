// Storybook page-turn transition. The "front page" (a screen snapshot or a procedural parchment
// page) curls away from the bottom-right corner around a cylinder, revealing whatever is drawn
// beneath this ColorRect. progress 0 = page flat and fully covering, 1 = page gone.
shader_type canvas_item;
render_mode blend_mix;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D page_tex : source_color, filter_linear;
uniform bool use_tex = false;
uniform float aspect = 1.7777;
uniform float radius = 0.11;
uniform vec2 curl_dir = vec2(1.0, 0.32);
uniform vec4 paper : source_color = vec4(0.96, 0.9, 0.76, 1.0);
uniform vec4 paper_back : source_color = vec4(0.93, 0.86, 0.7, 1.0);
uniform vec4 ink : source_color = vec4(0.42, 0.27, 0.14, 1.0);
uniform sampler2D grain_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_grain = false;



float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

vec3 parchment(vec2 uv) {
	vec3 c = paper.rgb;
	if (use_grain) {
		float n = noise(uv * vec2(aspect, 1.0) * 7.0) * 0.6 + noise(uv * vec2(aspect, 1.0) * 23.0) * 0.4;
		// two offset, rotated samples hide the parchment texture's wrap seam (critique UI r1)
		vec2 g1 = uv * vec2(aspect, 1.0) * 0.7 + vec2(0.13, 0.31);
		vec2 g2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * g1 * 0.83 + vec2(0.41, 0.67);
		vec3 t = (texture(grain_tex, g1).rgb + texture(grain_tex, g2).rgb) * 0.5;
		c = mix(paper.rgb * (0.94 + n * 0.08), t, 0.45);
	} else {
		float n = noise(uv * vec2(aspect, 1.0) * 9.0) * 0.6 + noise(uv * vec2(aspect, 1.0) * 31.0) * 0.4;
		c *= 0.93 + n * 0.1;
	}
	// darker deckled edge
	vec2 e = min(uv, 1.0 - uv) * vec2(aspect, 1.0);
	float edge = min(e.x, e.y);
	c = mix(c * vec3(0.78, 0.66, 0.5), c, smoothstep(0.0, 0.12, edge));
	// thin ink frame
	float f = abs(edge - 0.035);
	c = mix(ink.rgb, c, smoothstep(0.0015, 0.004, f));
	return c;
}

vec4 front(vec2 uv) {
	if (use_tex) {
		return vec4(texture(page_tex, uv).rgb, 1.0);
	}
	return vec4(parchment(uv), 1.0);
}

bool inside(vec2 uv) { return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0; }

void fragment() {
	vec2 dir = normalize(curl_dir);
	vec2 p = vec2(UV.x * aspect, UV.y);
	float maxd = max(max(dot(vec2(aspect, 1.0), dir), dot(vec2(aspect, 0.0), dir)), dot(vec2(0.0, 1.0), dir));
	float start = maxd + 0.02;
	float finish = -PI * radius - radius - 0.05;
	float line = mix(start, finish, smoothstep(0.0, 1.0, progress));
	float d = dot(p, dir) - line;
	vec4 col = vec4(0.0);
	// Soft shadow cast by the curl onto the revealed scene
	if (d > 0.0) {
		float s = 1.0 - smoothstep(radius * 0.2, radius * 2.2, d);
		col = vec4(0.08, 0.05, 0.02, s * 0.45 * (1.0 - progress * 0.5));
	}
	bool drawn = false;
	if (d < 0.0) {
		// back flap lying over the flat page
		float arc = PI * radius - d;
		vec2 src = p + dir * (arc - d);
		vec2 suv = vec2(src.x / aspect, src.y);
		if (inside(suv)) {
			vec3 back = mix(paper_back.rgb, front(suv).rgb, 0.12);
			float shade = 0.82 + 0.18 * smoothstep(0.0, radius * 1.5, -d);
			col = vec4(back * shade, 1.0);
			drawn = true;
		} else {
			vec3 f = front(UV).rgb;
			// darken the page near the curl (ambient occlusion)
			float ao = 1.0 - (1.0 - smoothstep(0.0, radius * 1.2, -d)) * 0.25;
			col = vec4(f * ao, 1.0);
			drawn = true;
		}
	} else if (d < radius) {
		float theta = asin(clamp(d / radius, -1.0, 1.0));
		// top layer: the page's back on the upper half of the cylinder
		float arc_top = radius * (PI - theta);
		vec2 src_top = p + dir * (arc_top - d);
		vec2 tuv = vec2(src_top.x / aspect, src_top.y);
		if (inside(tuv)) {
			float light = 0.65 + 0.35 * sin(theta + PI * 0.5);
			col = vec4(mix(paper_back.rgb, front(tuv).rgb, 0.12) * light, 1.0);
			drawn = true;
		} else {
			float arc_bot = radius * theta;
			vec2 src_bot = p + dir * (arc_bot - d);
			vec2 buv = vec2(src_bot.x / aspect, src_bot.y);
			if (inside(buv)) {
				float light = 0.6 + 0.4 * cos(theta);
				col = vec4(front(buv).rgb * light, 1.0);
				drawn = true;
			}
		}
	}
	COLOR = col;
}
