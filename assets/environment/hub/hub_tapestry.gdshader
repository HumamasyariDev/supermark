shader_type spatial;
render_mode cull_disabled;
// Mak family crest tapestry: burgundy velvet, gold border and fringe, a gold shield with a pig snout and a truffle.
// UV.x = arc length along the curtain (0..~3.74 m), UV.y = height from the bottom hem (0..6.8 m).
uniform vec4 velvet : source_color = vec4(0.48, 0.1, 0.15, 1.0);
uniform vec4 velvet_dark : source_color = vec4(0.3, 0.05, 0.09, 1.0);
uniform vec4 gold : source_color = vec4(0.9, 0.68, 0.28, 1.0);
uniform vec4 cream : source_color = vec4(0.95, 0.86, 0.68, 1.0);
uniform vec4 pink : source_color = vec4(0.95, 0.6, 0.64, 1.0);
uniform float width = 3.74;
uniform float height = 6.8;

float sdbox(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }

void vertex() {
	float sway = sin(TIME * 0.9 + UV.x * 1.3) * 0.04 * (1.0 - UV.y / height);
	VERTEX.x += sway * 0.6;
	VERTEX.z += sway;
}

void fragment() {
	vec2 p = vec2(UV.x - width * 0.5, UV.y);
	// Folds.
	float fold = 0.5 + 0.5 * sin(UV.x * 9.0);
	vec3 col = mix(velvet_dark.rgb, velvet.rgb, 0.55 + 0.45 * fold);
	// Gold border.
	float bx = min(UV.x, width - UV.x);
	float by = min(UV.y - 0.25, height - UV.y);
	float border = step(bx, 0.22) + step(by, 0.22);
	col = mix(col, gold.rgb, clamp(border, 0.0, 1.0) * 0.95);
	float inner = (1.0 - step(bx, 0.3)) * (1.0 - step(by, 0.3)) * (step(bx, 0.34) + step(by, 0.34));
	col = mix(col, cream.rgb, clamp(inner, 0.0, 1.0) * 0.8);
	// Fringe tassels below the hem.
	if (UV.y < 0.25) {
		float t = step(0.5, fract(UV.x * 7.0));
		if (t < 0.5 && UV.y < 0.2) { discard; }
		col = gold.rgb * 0.9;
	}
	// Shield crest in the middle.
	vec2 c = p - vec2(0.0, height * 0.52);
	float shield = sdbox(c + vec2(0.0, -0.25), vec2(1.0, 0.8));
	float tip = length(c * vec2(0.85, 1.0) + vec2(0.0, 0.45)) - 1.05;
	float sh = max(min(shield, tip), -(c.y + 1.45));
	float sh_in = sh + 0.1;
	col = mix(col, gold.rgb, 1.0 - smoothstep(0.0, 0.02, sh));
	col = mix(col, vec3(0.18, 0.36, 0.25), 1.0 - smoothstep(0.0, 0.02, sh_in));
	// Pig snout.
	float snout = length((c - vec2(0.0, 0.35)) * vec2(0.8, 1.1)) - 0.42;
	col = mix(col, pink.rgb, 1.0 - smoothstep(0.0, 0.02, snout));
	float n1 = length(c - vec2(-0.14, 0.35)) - 0.08;
	float n2 = length(c - vec2(0.14, 0.35)) - 0.08;
	col = mix(col, vec3(0.45, 0.18, 0.2), 1.0 - smoothstep(0.0, 0.02, min(n1, n2)));
	// Golden truffle below.
	float tr = length((c - vec2(0.0, -0.45)) * vec2(1.0, 1.25)) - 0.3;
	col = mix(col, gold.rgb * 1.15, 1.0 - smoothstep(0.0, 0.02, tr));
	// Top hat above the shield.
	float brim = sdbox(c - vec2(0.0, 1.32), vec2(0.65, 0.07));
	float crown = sdbox(c - vec2(0.0, 1.75), vec2(0.42, 0.42));
	col = mix(col, vec3(0.12, 0.1, 0.11), 1.0 - smoothstep(0.0, 0.02, min(brim, crown)));
	float band = sdbox(c - vec2(0.0, 1.47), vec2(0.42, 0.08));
	col = mix(col, velvet.rgb * 1.2, 1.0 - smoothstep(0.0, 0.02, band));
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// Velvet sheen.
	RIM = 0.4;
	RIM_TINT = 0.6;
}
