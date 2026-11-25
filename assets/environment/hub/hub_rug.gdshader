shader_type spatial;
// Round library rug: burgundy field, gold and teal borders, a woven medallion.
// UV = world xz in metres (the rug mesh is a disc with planar UVs).
uniform vec4 field : source_color = vec4(0.48, 0.12, 0.16, 1.0);
uniform vec4 field_dark : source_color = vec4(0.36, 0.08, 0.12, 1.0);
uniform vec4 gold : source_color = vec4(0.86, 0.66, 0.3, 1.0);
uniform vec4 teal : source_color = vec4(0.18, 0.42, 0.42, 1.0);
uniform vec4 cream : source_color = vec4(0.93, 0.84, 0.66, 1.0);
uniform float radius = 6.0;
uniform vec2 centre = vec2(0.0, 1.0);

float band(float r, float a, float b) {
	return smoothstep(a - 0.02, a + 0.02, r) * (1.0 - smoothstep(b - 0.02, b + 0.02, r));
}

void fragment() {
	vec2 p = UV - centre;
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec3 col = mix(field_dark.rgb, field.rgb, 0.5 + 0.5 * cos(r * 3.2));
	float petals = 0.5 + 0.5 * cos(ang * 12.0);
	col = mix(col, gold.rgb, band(r, 2.2 + petals * 0.35, 2.45 + petals * 0.35) * 0.9);
	col = mix(col, teal.rgb, band(r, 1.2, 1.6));
	col = mix(col, cream.rgb, band(r, 1.6, 1.7));
	col = mix(col, gold.rgb, 1.0 - smoothstep(0.55, 0.62, r));
	col = mix(col, gold.rgb, band(r, radius - 0.75, radius - 0.62));
	// Fix r2 (visual minor): the cream dashes read as road markings; gold scallops instead.
	float sc = abs(sin(ang * 24.0));
	col = mix(col, teal.rgb, band(r, radius - 0.6, radius - 0.2));
	col = mix(col, gold.rgb, band(r, radius - 0.48, radius - 0.42 + 0.1 * sc));
	col = mix(col, gold.rgb, band(r, radius - 0.2, radius - 0.08));
	float weave = 0.94 + 0.06 * sin(UV.x * 160.0) * sin(UV.y * 160.0);
	ALBEDO = col * weave;
	ROUGHNESS = 0.92;
}
