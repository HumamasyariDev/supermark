shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 haze_color : source_color = vec3(0.50, 0.39, 0.30);
// OPUSLOOK: 0.02 (was 0.012). The desktop hall's volumetric haze lifts its shadows (luma p5 0.09, web 0.04) and
// softens the far shelves; a thicker card does that here, so the global grade no longer desaturates the actors.
uniform float density = 0.02;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec3 end = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	vec3 origin = INV_VIEW_MATRIX[3].xyz;
	float distance_to_surface = length(end - origin);
	vec3 ray = (end - origin) / max(distance_to_surface, 0.0001);
	// The native HallHaze cylinder: radius 16.5, y 1.5..21.5. Integrate
	// only its visible thickness so outside scenery and foreground stay clear.
	float a = dot(ray.xz, ray.xz);
	float b = dot(origin.xz, ray.xz);
	float c = dot(origin.xz, origin.xz) - 16.5 * 16.5;
	float d = b*b - a*c;
	float thickness = 0.0;
	if (d > 0.0 && a > 0.00001) {
		float near_t = max(0.0, (-b - sqrt(d)) / a);
		float far_t = min(distance_to_surface, (-b + sqrt(d)) / a);
		if (abs(ray.y) > 0.00001) {
			float y1 = (1.5 - origin.y) / ray.y;
			float y2 = (21.5 - origin.y) / ray.y;
			near_t = max(near_t, min(y1, y2));
			far_t = min(far_t, max(y1, y2));
		} else if (origin.y < 1.5 || origin.y > 21.5) {
			far_t = near_t;
		}
		thickness = max(0.0, far_t - near_t);
	}
	ALBEDO = haze_color;
	ALPHA = 1.0 - exp(-density * thickness);
}
