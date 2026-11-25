// Gameplay-pop pass (D034, Docs/ART_V3_RETRO.md "Visual hierarchy and finish").
// RetroLook chains this as a next_pass on the materials of nodes in the gameplay groups (player, enemy, npc, pickup,
// truffle ...), so heroes, enemies and collectibles separate from the matte environment.
// Fix round 1 (critic M2 / hero major): the rim is blended (not added), so it never washes out on light grounds;
// it is gated to the shadow side of the sun (light_dir, set per world by RetroLook), so it reads as a back-light edge
// and not as a white band on the lit hat brim; and with ink = 1 it becomes a dark ink edge for the high-key worlds.
// The truffle glint lives in retro_glint.gdshader (additive). Never writes depth; works on skinned meshes and keeps hit
// flashes (material_overlay) intact.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 rim_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.42;
// 0 = light rim, 1 = dark ink rim (no gating: an ink edge outlines the whole silhouette).
uniform float ink : hint_range(0.0, 1.0) = 0.0;
// Direction toward the sun in world space; shadow_gate 1 keeps the light rim on the unlit side only.
uniform vec3 light_dir = vec3(0.4, 0.8, 0.45);
uniform float shadow_gate : hint_range(0.0, 1.0) = 0.6;
// Fades the whole pass out with distance so far pickups do not shimmer.
uniform float fade_far = 60.0;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);
	// Stepped (two-level) rim: crisp like a painted highlight rather than a soft modern glow.
	float rim = smoothstep(rim_threshold, rim_threshold + 0.06, fres) * 0.65 + smoothstep(rim_threshold + 0.22, rim_threshold + 0.28, fres) * 0.35;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float ndl = dot(wn, normalize(light_dir));
	float gate = mix(1.0, 1.0 - smoothstep(-0.15, 0.45, ndl), shadow_gate * (1.0 - ink));
	float dist = length(VERTEX);
	float a = rim * gate * rim_strength * (1.0 - smoothstep(fade_far * 0.7, fade_far, dist));
	ALBEDO = rim_color.rgb;
	ALPHA = clamp(a, 0.0, 0.85);
}
