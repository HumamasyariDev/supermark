// W3 falling liquid curtain (syrup falls, chocolate falls): UV scroll downward, soft side edges.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;
#define CURTAIN
#include "res://assets/environment/w3/w3_liquid_body.gdshaderinc"
