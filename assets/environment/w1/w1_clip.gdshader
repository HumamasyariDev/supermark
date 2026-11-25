shader_type spatial;
// W1 fix round 1: splits one generated house mesh into two parts at a model-space height (the straw house's roof
// cap folds off as a separate copy while the walls stay). keep_above = 1 keeps the part above clip_y.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_tex = false;
uniform float clip_y = 0.0;
uniform float keep_above = 0.0;
uniform float roughness_v = 0.85;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	bool above = local_y >= clip_y;
	if ((keep_above > 0.5 && !above) || (keep_above < 0.5 && above)) {
		discard;
	}
	vec4 c = albedo_color;
	if (has_tex) {
		c *= texture(albedo_tex, UV);
	}
	ALBEDO = c.rgb;
	ROUGHNESS = roughness_v;
}
