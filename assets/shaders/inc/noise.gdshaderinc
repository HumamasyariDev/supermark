// Small procedural noise helpers (value noise, fbm, cells), shared by Super Mak 64 shaders.
// Integer hash of the cell containing p (stable at large coordinates, unlike fract/sin hashes).
float sm_hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)));
	q = q * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	n ^= n >> 16u;
	return float(n) * (1.0 / 4294967295.0);
}

float sm_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = sm_hash21(i);
	float b = sm_hash21(i + vec2(1.0, 0.0));
	float c = sm_hash21(i + vec2(0.0, 1.0));
	float d = sm_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sm_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * sm_vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Rotated-octave fbm: avoids the grid-aligned straight edges plain value noise shows when thresholded.
float sm_fbm_rot(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < octaves; i++) {
		v += a * sm_vnoise(p);
		p = r * p * 2.02 + vec2(11.3, 5.7);
		a *= 0.5;
	}
	return v;
}

// Cellular distance (foam, bubbles).
float sm_cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = vec2(sm_hash21(i + o), sm_hash21(i + o + 31.7));
			d = min(d, length(o + r - f));
		}
	}
	return d;
}
