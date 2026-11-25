// Velocity-aligned streak particle (hit sparks, speed lines, splash droplets, ember trails).
// The particle process material must use particle_flag_align_y so the particle's Y axis follows its
// velocity. The quad is then billboarded around that axis: the head sits at the particle position and
// the tail trails behind it. Width = particle X scale, length = particle Y scale * stretch.
// Uses the particle colour (sRGB authored) as tint. Cheap: no texture lookups beyond one optional sprite.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;

uniform float stretch = 3.0;
// 0 = soft round body, 1 = sharp tapered needle (cartoon spark).
uniform float taper : hint_range(0.0, 1.0) = 0.85;
uniform float brightness = 1.0;
// Head gets a hot white core.
uniform float core = 0.6;

varying vec2 v_uv;

void vertex() {
	vec3 axis_raw = MODEL_MATRIX[1].xyz;
	float len = max(length(axis_raw), 0.0001);
	vec3 axis = axis_raw / len;
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : normalize(INV_VIEW_MATRIX[0].xyz);
	// VERTEX.y in [-0.5, 0.5]: head at +0.5 (the particle position), tail behind.
	float along = (VERTEX.y - 0.5) * len * stretch;
	vec3 world = center + side * VERTEX.x * wid + axis * along;
	v_uv = vec2(VERTEX.x + 0.5, VERTEX.y + 0.5);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	// v_uv.y: 0 tail .. 1 head. Width narrows toward the tail (needle) and rounds at the head.
	float y = v_uv.y;
	float across = abs(v_uv.x * 2.0 - 1.0);
	float w = mix(1.0, y, taper);
	float body = 1.0 - smoothstep(w * 0.55, w, across);
	float head = smoothstep(1.0, 0.86, y);
	float tail = smoothstep(0.0, 0.35, y);
	float a = body * head * tail * COLOR.a;
	vec3 pc = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	float hot = smoothstep(0.55, 1.0, y) * (1.0 - smoothstep(0.0, 0.4, across)) * core;
	ALBEDO = mix(pc, vec3(1.0), hot) * brightness;
	ALPHA = clamp(a, 0.0, 1.0);
}
