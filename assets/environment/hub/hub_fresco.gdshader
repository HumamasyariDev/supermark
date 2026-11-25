shader_type spatial;
render_mode cull_disabled;
// Upper-drum fresco panels (r1 visual round 2): hand-painted colour blocks of the three tales and trompe-l'oeil
// sky windows, so the drum above the gallery carries story, blue sky (cool counterpoint) and a little motion.
// UV: x 0..1 across the panel, y 0 at the bottom, 1 at the top.
// tale: 0 Three Little Pigs (houses + turning windmill), 1 Jack's beanstalk (stalk + cloud castle),
//       2 Hansel and Gretel (gingerbread house + lollipop trees), 3 sky window (arched, clouds drifting).

uniform float tale = 0.0;
uniform float seed = 0.0;
uniform vec4 sky_top : source_color = vec4(0.42, 0.62, 0.86, 1.0);
uniform vec4 sky_low : source_color = vec4(0.82, 0.9, 0.96, 1.0);
uniform vec4 frame_gold : source_color = vec4(0.79, 0.63, 0.29, 1.0);
uniform vec4 ink : source_color = vec4(0.23, 0.14, 0.09, 1.0);
uniform vec4 parchment : source_color = vec4(0.92, 0.85, 0.69, 1.0);
uniform float glow = 0.12;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	// signed-ish inside test for a triangle (negative inside)
	vec2 e0 = b - a; vec2 e1 = c - b; vec2 e2 = a - c;
	vec2 v0 = p - a; vec2 v1 = p - b; vec2 v2 = p - c;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
		vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
		vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}
// paint a shape with an ink outline
vec3 paint(vec3 col, float d, vec3 fill, float aa) {
	col = mix(col, ink.rgb, 1.0 - smoothstep(0.0, aa, d - 0.0078));
	return mix(col, fill, 1.0 - smoothstep(0.0, aa, d));
}

// Fix r2 (visual major, D032): the panels read as smooth vector clip-art with thick black outlines. They are now
// painted on a 128 x 96 texel grid (hard texel edges, 1-texel ink lines, no anti-aliasing), the colours are
// quantised to a small palette, and `mirror` flips repeats so no two panels of a tale match.
uniform float mirror = 0.0;
uniform vec2 texels = vec2(128.0, 96.0);

void fragment() {
	vec2 uv = UV;
	if (mirror > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	uv = (floor(uv * texels) + 0.5) / texels;
	float aa = 0.0001;
	float asp = 1.38; // panel width / height (about 4.97 x 3.6 m)
	vec2 p = vec2(uv.x * asp, uv.y);
	// sky
	vec3 col = mix(sky_low.rgb, sky_top.rgb, smoothstep(0.25, 1.0, uv.y));
	// soft painted clouds drifting
	float cn = noise(vec2(p.x * 3.0 + TIME * 0.02 + seed * 7.0, p.y * 5.0)) * 0.6 + noise(vec2(p.x * 7.0 - TIME * 0.015, p.y * 11.0 + seed)) * 0.4;
	float cloud = smoothstep(0.58, 0.68, cn) * smoothstep(0.45, 0.75, uv.y);
	col = mix(col, vec3(1.0, 0.98, 0.94), cloud * 0.85);
	if (tale < 2.5) {
		// rolling hills: meadow and deep grass
		float h1 = 0.3 + 0.06 * sin(p.x * 4.0 + seed * 3.0) + 0.03 * sin(p.x * 9.0 + seed);
		float h2 = 0.2 + 0.05 * sin(p.x * 5.5 + 1.7 + seed * 2.0);
		col = paint(col, uv.y - h1, vec3(0.43, 0.75, 0.27), aa);
		col = paint(col, uv.y - h2, vec3(0.25, 0.56, 0.23), aa);
	}
	if (tale < 0.5) {
		// three little houses: straw, sticks, bricks
		vec3 cols[3] = vec3[](vec3(0.93, 0.78, 0.36), vec3(0.6, 0.4, 0.22), vec3(0.75, 0.27, 0.2));
		for (int i = 0; i < 3; i++) {
			float x = 0.18 + float(i) * 0.24;
			col = paint(col, box(p, vec2(x, 0.27), vec2(0.075, 0.07)), cols[i], aa);
			col = paint(col, tri(p, vec2(x - 0.1, 0.33), vec2(x + 0.1, 0.33), vec2(x, 0.45)), cols[i] * 0.8, aa);
			col = paint(col, box(p, vec2(x, 0.24), vec2(0.018, 0.04)), vec3(0.3, 0.18, 0.1), aa);
		}
		// windmill with turning sails
		vec2 hub = vec2(1.08, 0.62);
		col = paint(col, tri(p, vec2(0.98, 0.22), vec2(1.18, 0.22), vec2(1.08, 0.64)), vec3(0.96, 0.92, 0.84), aa);
		float a = TIME * 0.6 + seed;
		for (int k = 0; k < 4; k++) {
			float ang = a + float(k) * 1.5708;
			vec2 dir = vec2(cos(ang), sin(ang));
			vec2 q = p - hub;
			float along = dot(q, dir);
			float side = dot(q, vec2(-dir.y, dir.x));
			float d = max(abs(side - 0.02) - 0.028, max(-along + 0.02, along - 0.27));
			col = paint(col, d, vec3(0.82, 0.3, 0.26), aa);
		}
		col = paint(col, length(p - hub) - 0.025, vec3(0.79, 0.63, 0.29), aa);
	} else if (tale < 1.5) {
		// the beanstalk winding up into a cloud castle
		float sx = 0.62 + 0.08 * sin(uv.y * 9.0 + seed);
		float d = abs(p.x - sx) - 0.035 * (1.2 - uv.y * 0.6);
		col = paint(col, max(d, uv.y - 0.86), vec3(0.32, 0.65, 0.2), aa);
		for (int k = 0; k < 6; k++) {
			float y = 0.2 + float(k) * 0.11;
			float lx = 0.62 + 0.08 * sin(y * 9.0 + seed) + (k % 2 == 0 ? 0.07 : -0.07);
			vec2 q = (p - vec2(lx, y)) * vec2(1.0, 1.9);
			col = paint(col, length(q) - 0.05, vec3(0.45, 0.78, 0.28), aa);
		}
		// cloud and castle
		float cl = min(min(length((p - vec2(0.62, 0.84)) * vec2(0.8, 1.6)) - 0.12, length(p - vec2(0.48, 0.83)) - 0.07), length(p - vec2(0.77, 0.83)) - 0.07);
		col = paint(col, cl, vec3(1.0, 0.98, 0.95), aa);
		col = paint(col, box(p, vec2(0.62, 0.92), vec2(0.08, 0.05)), vec3(0.62, 0.66, 0.82), aa);
		col = paint(col, box(p, vec2(0.52, 0.95), vec2(0.022, 0.07)), vec3(0.55, 0.58, 0.78), aa);
		col = paint(col, box(p, vec2(0.72, 0.95), vec2(0.022, 0.07)), vec3(0.55, 0.58, 0.78), aa);
		col = paint(col, tri(p, vec2(0.49, 1.02), vec2(0.55, 1.02), vec2(0.52, 1.07)), vec3(0.82, 0.3, 0.26), aa);
		col = paint(col, tri(p, vec2(0.69, 1.02), vec2(0.75, 1.02), vec2(0.72, 1.07)), vec3(0.82, 0.3, 0.26), aa);
	} else if (tale < 2.5) {
		// gingerbread house with icing and lollipop trees
		vec2 c = vec2(0.69, 0.3);
		col = paint(col, box(p, c, vec2(0.16, 0.1)), vec3(0.66, 0.4, 0.2), aa);
		float roof = tri(p, vec2(0.49, 0.39), vec2(0.89, 0.39), vec2(0.69, 0.58));
		col = paint(col, roof, vec3(0.55, 0.3, 0.16), aa);
		float zig = abs(fract((p.x - 0.49) * 18.0) - 0.5) * 0.03;
		float icing = abs(p.y - (0.39 + zig)) - 0.012;
		if (p.x > 0.49 && p.x < 0.89) col = mix(col, vec3(1.0, 0.98, 0.95), 1.0 - smoothstep(0.0, aa, icing));
		col = paint(col, box(p, vec2(0.69, 0.25), vec2(0.035, 0.05)), vec3(0.95, 0.5, 0.62), aa);
		col = paint(col, length(p - vec2(0.6, 0.33)) - 0.025, vec3(0.3, 0.75, 0.75), aa);
		col = paint(col, length(p - vec2(0.78, 0.33)) - 0.025, vec3(1.0, 0.82, 0.3), aa);
		for (int k = 0; k < 3; k++) {
			float x = 0.14 + float(k) * 0.12 + (k == 2 ? 0.9 : 0.0);
			col = paint(col, box(p, vec2(x, 0.25), vec2(0.008, 0.08)), vec3(0.96, 0.94, 0.9), aa);
			float sw = length(p - vec2(x, 0.38)) - 0.05;
			vec3 lc = k == 1 ? vec3(0.3, 0.72, 0.74) : vec3(0.85, 0.38, 0.5);
			float spiral = sin(atan(p.y - 0.38, p.x - x) * 2.0 + length(p - vec2(x, 0.38)) * 60.0);
			col = paint(col, sw, mix(lc, vec3(1.0), step(0.6, spiral) * 0.6), aa);
		}
	} else {
		// trompe-l'oeil arched sky window with walnut mullions
		vec2 q = vec2((uv.x - 0.5) * asp, uv.y);
		float arch_d = max(abs(q.x) - 0.42, q.y - 0.68);
		arch_d = min(arch_d, length(q - vec2(0.0, 0.68)) - 0.42);
		arch_d = max(arch_d, 0.06 - q.y);
		float frame = abs(arch_d) - 0.035;
		vec3 wood = vec3(0.42, 0.26, 0.17);
		float mull = min(abs(q.x) - 0.018, abs(q.y - 0.5) - 0.018);
		if (arch_d < 0.0 && mull < 0.0) col = mix(col, wood, 1.0);
		if (arch_d > 0.0) col = parchment.rgb * (0.96 + 0.04 * noise(uv * 40.0));
		col = mix(col, ink.rgb, 1.0 - smoothstep(0.0, aa, abs(frame) - 0.004));
		col = mix(col, wood, 1.0 - smoothstep(0.0, aa, frame));
	}
	// gilt painted border
	float bx = min(min(uv.x, 1.0 - uv.x) * asp, min(uv.y, 1.0 - uv.y));
	col = mix(col, frame_gold.rgb, 1.0 - smoothstep(0.035, 0.04, bx));
	col = mix(col, ink.rgb, (1.0 - smoothstep(0.0, 0.006, abs(bx - 0.04))) * 0.8);
	// a little fresco grain
	col *= 0.94 + 0.06 * noise(uv * vec2(90.0, 65.0) + seed);
	// Quantise to a small painted palette (about 10 levels per channel).
	col = floor(col * 10.0 + 0.5) / 10.0;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = col * glow;
}
