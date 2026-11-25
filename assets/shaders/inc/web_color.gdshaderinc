// Colour-space bridge between the desktop and web renderers (OPUSLOOK, Docs/GODOT_WEB.md).
// Forward+ (desktop, the art reference) hands source_color uniforms and textures to fragment()/light() as linear values,
// treats COLOR, raw vec3 constants and scalar multipliers as linear, and lights ALBEDO/EMISSION as written.
// Compatibility (web) hands the same inputs over unconverted (sRGB) and converts ALBEDO/EMISSION from sRGB to linear
// after fragment(). Dark vertex colours therefore collapsed to black on the web, shade tints were too light and rim
// emission too weak. A shader that wraps its source_color inputs in mak_lin() and its outputs in mak_out() computes the
// desktop's values on both renderers. Both functions are identities on the desktop (OUTPUT_IS_SRGB is false there).

vec3 mak_lin(vec3 c) {
	if (!OUTPUT_IS_SRGB) {
		return c;
	}
	c = max(c, vec3(0.0));
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

// Exact inverse of the web renderer's own conversion, unclamped so HDR emission survives the round trip.
vec3 mak_out(vec3 c) {
	if (!OUTPUT_IS_SRGB) {
		return c;
	}
	c = max(c, vec3(0.0));
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}
