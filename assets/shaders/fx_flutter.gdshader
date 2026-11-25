// Billboard particle sprite that flaps or flips (butterflies, falling leaves, feathers, lost pages).
// Uses the particle colour (COLOR) as tint and INSTANCE_CUSTOM.x as the in-plane rotation.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

#include "res://assets/shaders/inc/web_color.gdshaderinc"

uniform sampler2D sprite : source_color, filter_linear_mipmap, hint_default_white;
uniform float flap_speed = 14.0;
// 0 = no flap. 1 = full flap (wings close to 20% width). Leaves/pages use smaller values with flip on.
uniform float flap_amount = 0.8;
// Flip mode mirrors the sprite through zero width (a tumbling leaf) instead of a symmetric wing flap.
uniform bool flip_mode = false;
uniform float alpha_cut = 0.35;
uniform float brightness = 1.0;
uniform vec4 shade_color : source_color = vec4(0.86, 0.8, 0.7, 1.0);
// Pages (juice fix r1): emissive lift so they never drop below mid-tone, and a gold glint when facing the camera.
uniform float lift = 0.0;
uniform float glint = 0.0;
uniform float min_width = 0.0;

varying float v_shade;

void vertex() {
	float phase = float(INSTANCE_ID) * 1.618;
	float f;
	if (flip_mode) {
		f = cos(TIME * flap_speed + phase);
		v_shade = f;
		// Never fully edge-on (a curled page keeps some width).
		float w = mix(1.0, f, flap_amount);
		w = sign(w + 0.0001) * max(abs(w), min_width);
		VERTEX.x *= w;
	} else {
		f = abs(sin(TIME * flap_speed + phase));
		v_shade = f;
		VERTEX.x *= mix(1.0, mix(0.2, 1.0, f), flap_amount);
	}
	float a = INSTANCE_CUSTOM.x;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	VERTEX.xy = rot * VERTEX.xy;
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
}

void fragment() {
	vec4 t = texture(sprite, UV);
	// Particle colours are authored in sRGB.
	vec3 pc = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	vec3 tc = mak_lin(t.rgb);
	vec3 c = tc * pc * brightness;
	// Darken the sprite as it turns edge-on or shows its back.
	float s = flip_mode ? smoothstep(-1.0, 1.0, v_shade) : mix(0.75, 1.0, v_shade);
	c *= mix(mak_lin(shade_color.rgb), vec3(1.0), s);
	c = mix(c, tc * pc, lift);
	c += vec3(1.0, 0.8, 0.35) * glint * smoothstep(0.9, 1.0, v_shade) * t.a;
	// OPUSLOOK: computed in linear like the desktop; mak_out() encodes the unlit result for the web (inc/web_color).
	ALBEDO = mak_out(c);
	ALPHA = t.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
