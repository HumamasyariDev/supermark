// W3 Gingerbread Grove terrain: painted colour fields, no photo textures.
// Vertex colour: r = biscuit-crumb path, g = chocolate mud near water, b = pink rock candy (falls cliff),
// a = icing lip at the top of steep slopes. Flat ground = coconut-ice grass, steep = gingerbread rock.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/inc/noise.gdshaderinc"
#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform vec4 grass_color : source_color = vec4(0.62, 0.87, 0.64, 1.0);   // mint frosting grass (key art)
uniform vec4 grass_light : source_color = vec4(0.82, 0.96, 0.80, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.46, 0.76, 0.52, 1.0);
uniform vec4 path_color : source_color = vec4(0.886, 0.718, 0.478, 1.0);    // #E2B77A
uniform vec4 crumb_color : source_color = vec4(0.72, 0.50, 0.28, 1.0);
uniform vec4 rock_color : source_color = vec4(0.722, 0.451, 0.227, 1.0);    // #B8733A
uniform vec4 rock_dark : source_color = vec4(0.478, 0.271, 0.137, 1.0);     // #7A4523
uniform vec4 mud_color : source_color = vec4(0.353, 0.196, 0.129, 1.0);     // #5A3221
uniform vec4 pink_color : source_color = vec4(1.0, 0.56, 0.72, 1.0);        // #FF8FB8
uniform vec4 pink_dark : source_color = vec4(0.78, 0.45, 0.80, 1.0);
uniform vec4 icing_color : source_color = vec4(1.0, 0.97, 0.93, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.52, 0.72, 1.0);
uniform float slope_start = 0.80;
uniform float slope_end = 0.66;

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying vec4 v_col;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

void fragment() {
	vec3 n = normalize(v_wnorm);
	vec2 p = v_wpos.xz;
	float nz = sm_fbm_rot(p * 0.22, 3);
	float fine = sm_vnoise(p * 1.7);
	// Grass: soft macro patches and lighter mounds on top (painted gradient).
	vec3 grass = mix(mak_lin(grass_dark.rgb), mak_lin(grass_color.rgb), smoothstep(0.25, 0.6, nz));
	grass = mix(grass, mak_lin(grass_light.rgb), smoothstep(0.55, 0.85, nz) * 0.6);
	grass *= 0.96 + fine * 0.08;
	// Little sugar sprinkle dots on the grass.
	vec2 cp = p * 2.2;
	vec2 cell = floor(cp);
	float rnd = sm_hash21(cell);
	vec2 cc = cell + 0.5 + (vec2(sm_hash21(cell + 4.1), sm_hash21(cell + 9.3)) - 0.5) * 0.6;
	float dotm = (1.0 - smoothstep(0.05, 0.09, length(cp - cc))) * step(rnd, 0.16);
	vec3 sprinkle = mix(vec3(1.0, 0.55, 0.75), vec3(0.6, 0.85, 1.0), step(0.08, rnd));
	sprinkle = mix(sprinkle, vec3(1.0, 0.9, 0.45), step(0.12, rnd));
	grass = mix(grass, sprinkle, dotm * 0.85);
	// Biscuit-crumb path with crumbs.
	float crumbs = sm_cells(p * 3.0);
	vec3 path = mix(mak_lin(path_color.rgb), mak_lin(crumb_color.rgb), (1.0 - smoothstep(0.08, 0.2, crumbs)) * 0.55);
	path *= 0.95 + fine * 0.08;
	// Gingerbread rock: horizontal baked strata, warm.
	float strata = sin(v_wpos.y * 3.2 + nz * 4.0) * 0.5 + 0.5;
	vec3 rock = mix(mak_lin(rock_dark.rgb), mak_lin(rock_color.rgb), 0.45 + strata * 0.45 + (fine - 0.5) * 0.2);
	// Pink rock candy facets (cells give broad crystal facets).
	float fac = sm_cells(vec2(p.x + v_wpos.y * 0.6, p.y - v_wpos.y * 0.4) * 0.45);
	vec3 pink = mix(mak_lin(pink_dark.rgb), mak_lin(pink_color.rgb), smoothstep(0.1, 0.7, fac));
	pink = mix(pink, vec3(1.0, 0.88, 0.95), smoothstep(0.75, 0.95, fac) * 0.6);

	float flat_w = smoothstep(slope_end, slope_start, n.y + (nz - 0.5) * 0.12);
	float pathw = smoothstep(0.35, 0.65, v_col.r + (nz - 0.5) * 0.5);
	vec3 top = mix(grass, path, pathw);
	vec3 col = mix(rock, top, flat_w);
	col = mix(col, pink, smoothstep(0.3, 0.7, v_col.b));
	// Chocolate mud at the water's edge (hazard banks read darker).
	col = mix(col, mak_lin(mud_color.rgb) * (0.9 + fine * 0.2), smoothstep(0.3, 0.75, v_col.g + (fine - 0.5) * 0.3));
	// Icing lip with drips at slope tops.
	float drip = sm_vnoise(vec2((p.x + p.y) * 1.3, 0.0));
	float lip = smoothstep(0.35 + drip * 0.35, 0.5 + drip * 0.35, v_col.a);
	col = mix(col, mak_lin(icing_color.rgb), lip * (1.0 - v_col.g));
	ALBEDO = mak_out(col);
	ROUGHNESS = mix(0.9, 0.45, lip);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		// Sun: ATTENUATION is the shadow term; shadowed ground keeps a tinted fill.
		float lit = smoothstep(-0.15, 0.55, ndl) * smoothstep(0.05, 0.7, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(mak_lin(shadow_tint.rgb), vec3(1.0), lit) * 1.05;
	} else {
		// Omni/spot (effect flashes): ATTENUATION carries the distance falloff, so it scales the whole term
		// (without it the shadow-tint fill lit every light's full cluster cell: stair-stepped rectangles).
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * smoothstep(-0.15, 0.55, ndl) * ATTENUATION * 1.05;
	}
}
