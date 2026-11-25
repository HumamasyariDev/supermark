// W3 liquid surface: hot chocolate (hazard, orange bubble pops) or pink syrup (safe). Opaque.
// Vertex colour r = shore foam. Body: w3_liquid_body.gdshaderinc.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;
#include "res://assets/environment/w3/w3_liquid_body.gdshaderinc"
