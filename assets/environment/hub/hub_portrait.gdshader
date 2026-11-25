shader_type spatial;
render_mode cull_disabled;  // the lathed canvas faces away from the hall (r1 fun: the revealed portrait read as a blank gold panel)
// Painted still lifes for the hub's frames (no characters: Grandfather Mak's likeness waits for the CH-06 model).
// variant 0: Grandfather's keepsakes (top hat, pipe and a golden truffle on a velvet cushion) under a warm oval vignette.
// variant 1: the young explorer's spade and a truffle map pinned to a green wall.
uniform float variant = 0.0;
uniform vec4 bg : source_color = vec4(0.13, 0.27, 0.22, 1.0);
uniform vec4 gold : source_color = vec4(0.92, 0.7, 0.28, 1.0);
uniform vec4 velvet : source_color = vec4(0.48, 0.1, 0.15, 1.0);
// Fix r2 (visual/fun major): until the CH-06 Grandfather Mak model exists, variant 0 shows a real render of the
// generated Mak model in Grandfather's top hat (a SubViewport set up in hub_activities.gd), painted in sepia-oil
// tones with a crisp texel grid, inside the oval gilt frame.
uniform sampler2D portrait_tex : filter_nearest, source_color;
uniform float use_tex = 0.0;

float sdbox(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
float fill(float d) { return 1.0 - smoothstep(0.0, 0.012, d); }

void fragment() {
	vec2 uv = UV;
	// Lathe UVs are in metres; normalise to 0..1 using the frame size.
	vec2 p = variant < 0.5 ? vec2(uv.x / 3.2, uv.y / 4.2) : vec2(uv.x, uv.y);
	if (variant >= 0.5) { p = vec2(fract(uv.x * 1.0), uv.y); }
	vec2 c = p - vec2(0.5, 0.5);
	vec3 col = mix(bg.rgb * 0.6, bg.rgb * 1.3, smoothstep(0.65, 0.0, length(c * vec2(1.0, 0.8))));
	if (variant < 0.5) {
		if (use_tex > 0.5) {
			vec2 tp = vec2(p.x, 1.0 - p.y);
			vec4 t = texture(portrait_tex, tp);
			float l = dot(t.rgb, vec3(0.3, 0.55, 0.15));
			vec3 sep = mix(vec3(l) * vec3(1.08, 0.92, 0.7), t.rgb, 0.45);
			col = mix(col, sep, t.a);
			col = floor(col * 14.0 + 0.5) / 14.0;
		} else {
		// Cushion.
		float cush = length((c - vec2(0.0, -0.18)) * vec2(1.2, 3.2)) - 0.36;
		col = mix(col, velvet.rgb, fill(cush));
		// Truffle.
		float tr = length((c - vec2(0.08, -0.1)) * vec2(1.0, 1.25)) - 0.1;
		col = mix(col, gold.rgb * (1.1 + 0.3 * (c.y + 0.1) * 4.0), fill(tr));
		// Top hat.
		float brim = sdbox(c - vec2(-0.14, -0.05), vec2(0.16, 0.018));
		float crown = sdbox(c - vec2(-0.14, 0.09), vec2(0.1, 0.13));
		col = mix(col, vec3(0.07, 0.06, 0.07), fill(min(brim, crown)));
		col = mix(col, velvet.rgb, fill(sdbox(c - vec2(-0.14, 0.0), vec2(0.1, 0.025))));
		// Pipe.
		float bowl = sdbox(c - vec2(0.22, -0.2), vec2(0.03, 0.04));
		float stem = sdbox(c - vec2(0.14, -0.22), vec2(0.07, 0.008));
		col = mix(col, vec3(0.35, 0.2, 0.1), fill(min(bowl, stem)));
		}
		// Oval gilt inner frame.
		float ov = abs(length(c * vec2(1.0, 0.78)) - 0.42) - 0.012;
		col = mix(col, gold.rgb, fill(ov));
	} else {
		// Spade.
		float shaft = sdbox(c - vec2(-0.15, 0.05), vec2(0.015, 0.32));
		float blade = sdbox(c - vec2(-0.15, -0.3), vec2(0.07, 0.08));
		col = mix(col, vec3(0.55, 0.36, 0.2), fill(shaft));
		col = mix(col, vec3(0.6, 0.62, 0.66), fill(blade));
		// Map with an X.
		float map = sdbox(c - vec2(0.15, 0.05), vec2(0.17, 0.2));
		col = mix(col, vec3(0.93, 0.85, 0.66), fill(map));
		vec2 q = c - vec2(0.18, 0.0);
		float x1 = abs(q.x - q.y) - 0.01;
		float x2 = abs(q.x + q.y) - 0.01;
		col = mix(col, vec3(0.7, 0.15, 0.12), fill(max(min(x1, x2), length(q) - 0.05)));
	}
	// Canvas texture and varnish.
	col *= 0.95 + 0.05 * sin(UV.x * 300.0) * sin(UV.y * 300.0);
	ALBEDO = col;
	ROUGHNESS = 0.5;
}
