// Shared stylized lighting for Super Mak 64 ("Storybook toybox").
// Include inside a spatial shader that declares these uniforms:
//   ramp_threshold, ramp_softness, shadow_tint (vec3 colour), spec_strength, spec_size
// and call stylized_light(...) from light().

float sm_ramp(float ndl, float threshold, float softness) {
	return smoothstep(threshold - softness, threshold + softness, ndl);
}

// Two-tone diffuse with a coloured terminator, a soft glossy blob specular.
void sm_light(vec3 n, vec3 l, vec3 v, vec3 light_color, float attenuation,
		float threshold, float softness, vec3 shadow_tint, float spec_strength, float spec_size,
		inout vec3 diffuse, inout vec3 specular) {
	float ndl = dot(n, l);
	float lit = sm_ramp(ndl, threshold, softness);
	// Shadows (attenuation) are also ramped so they stay crisp but soft-edged.
	float sh = smoothstep(0.05, 0.6, attenuation);
	lit *= sh;
	vec3 lc = light_color / PI;
	// The terminator gets a warm band so the edge between light and shade looks painted.
	float band = (1.0 - abs(lit * 2.0 - 1.0)) * 0.18;
	diffuse += lc * (mix(shadow_tint, vec3(1.0), lit) + band * vec3(1.0, 0.55, 0.3));
	vec3 h = normalize(l + v + vec3(0.0, 1e-4, 0.0));
	float ndh = max(dot(n, h), 0.0);
	float s = pow(ndh, mix(256.0, 12.0, spec_size));
	s = smoothstep(0.45, 0.55, s) * lit;
	specular += lc * s * spec_strength;
}
