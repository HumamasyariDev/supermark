// Painterly storybook sky: three-colour gradient, soft sun disc with halo, drifting painted clouds
// lit from the sun side, and a warm haze band at the horizon. Configure per world (see
// res://assets/shaders/environments/). The radiance (cubemap) pass skips the cloud detail for speed.
shader_type sky;

#include "res://assets/shaders/inc/noise.gdshaderinc"

uniform vec4 top_color : source_color = vec4(0.28, 0.52, 0.9, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.78, 0.88, 0.97, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.42, 0.55, 0.45, 1.0);
uniform vec4 haze_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float gradient_power = 0.65;
uniform float haze_height = 0.14;
uniform float haze_strength = 0.6;
uniform vec4 sun_color : source_color = vec4(1.0, 0.94, 0.78, 1.0);
uniform float sun_size = 0.035;
uniform float sun_glow = 0.35;
uniform float sun_glow_size = 0.25;
uniform vec4 cloud_light : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.66, 0.72, 0.9, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.08;
uniform float cloud_scale = 1.2;
uniform float cloud_speed = 0.006;
uniform float cloud_height_fade = 0.08;
// Number of painted value steps in the cloud shading (0 = smooth).
uniform float paint_steps = 4.0;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.95;
uniform vec2 wind = vec2(1.0, 0.25);
// Optional second high, thin, streaky layer (cirrus / storm streaks).
uniform float streak_amount : hint_range(0.0, 1.0) = 0.25;

float cloud_density(vec2 uv, float t) {
	vec2 w = normalize(wind) * t;
	vec2 q = uv * cloud_scale + w;
	// Domain warp gives billowing, rounded cloud bodies.
	vec2 warp = vec2(sm_fbm_rot(q * 0.7 + 3.3, 3), sm_fbm_rot(q * 0.7 + 7.9, 3)) - 0.5;
	float base = sm_fbm_rot(q + warp * 1.2, 5);
	float detail = sm_fbm_rot(q * 2.7 - w * 1.7 + 4.0 + warp, 4);
	float d = base * 0.78 + detail * 0.27;
	float thr = 1.0 - cloud_coverage;
	return smoothstep(thr - cloud_softness, thr + cloud_softness, d * 1.05);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dir.y;
	// Sky gradient.
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon_color.rgb, top_color.rgb, pow(clamp(y, 0.0, 1.0), gradient_power));
	} else {
		col = mix(horizon_color.rgb, bottom_color.rgb, smoothstep(0.0, 0.25, -y));
	}
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(0.3, 0.4, -1.0));
	float sd = dot(dir, sun_dir);
	// Halo around the sun warms the sky on that side.
	float halo = pow(clamp(sd * 0.5 + 0.5, 0.0, 1.0), 1.0 / max(sun_glow_size, 0.01) * 2.0);
	col += sun_color.rgb * halo * sun_glow;
	// Horizon haze band.
	float haze = exp(-abs(y) / max(haze_height, 0.001));
	col = mix(col, haze_color.rgb, haze * haze_strength * (0.7 + 0.3 * halo));

	if (!AT_CUBEMAP_PASS) {
		// Sun disc with a soft edge.
		float sun_angle = acos(clamp(sd, -1.0, 1.0));
		float disc = 1.0 - smoothstep(sun_size * 0.85, sun_size, sun_angle);
		col = mix(col, sun_color.rgb * 1.6, disc);

		if (y > 0.0) {
			vec2 uv = dir.xz / (y * 0.9 + 0.22);
			float t = TIME * cloud_speed;
			float d = cloud_density(uv, t);
			// Light the cloud by sampling density toward the sun.
			vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001)) * 0.12;
			float d2 = cloud_density(uv + to_sun, t);
			float lit = clamp(0.6 + (d - d2) * 1.6, 0.0, 1.0);
			if (paint_steps > 0.0) {
				lit = floor(lit * paint_steps + 0.5) / paint_steps;
				lit = mix(lit, clamp(0.6 + (d - d2) * 1.6, 0.0, 1.0), 0.35);
			}
			vec3 cc = mix(cloud_shade.rgb, cloud_light.rgb, lit);
			// Silver lining toward the sun.
			cc += sun_color.rgb * pow(clamp(sd, 0.0, 1.0), 6.0) * (1.0 - d) * 0.8;
			// Distant clouds melt into the haze.
			float fade = smoothstep(0.0, cloud_height_fade + 0.02, y);
			cc = mix(haze_color.rgb, cc, 0.35 + 0.65 * smoothstep(0.0, 0.35, y));
			col = mix(col, cc, d * fade * cloud_opacity);
			// High streaks.
			float s = sm_vnoise(vec2(uv.x * 0.6, uv.y * 4.0) + t * 2.0);
			s = smoothstep(0.62, 0.9, s) * streak_amount * fade * (1.0 - d);
			col = mix(col, cloud_light.rgb, s * 0.6);
		}
	}
	COLOR = col;
}
