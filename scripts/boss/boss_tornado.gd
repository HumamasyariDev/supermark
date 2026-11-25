class_name BossTyphoon
extends Node3D
## The Teapot Typhoon (BOSS_amendments R1.5 HZ_twister, reworked; the r1 lift-and-fling tornado is gone):
## a spout-shaped column of tea steam, 14 m tall (base r 1.6, top flare r 4.5), with eight cups and saucers
## spinning in it. The core (r 1.0) is a hazard (1 slice); the push band (r 1.0-2.6, y < 5) is wind that
## WolfBoss.wind_at() computes.

var core: Area3D
var _layers: Array[MeshInstance3D] = []
var _cups: Node3D
var _mat: ShaderMaterial
var _t := 0.0
var alpha := 1.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded;
uniform vec4 col : source_color = vec4(0.93, 0.84, 0.72, 1.0);
uniform vec4 col2 : source_color = vec4(0.62, 0.42, 0.3, 1.0);
uniform float alpha = 0.55;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(h(i), h(i+vec2(1,0)), f.x), mix(h(i+vec2(0,1)), h(i+vec2(1,1)), f.x), f.y); }
void fragment(){
	vec2 uv = vec2(UV.x * 6.0 + TIME * 1.4 + UV.y * 3.0, UV.y * 3.0 - TIME * 0.6);
	float s = n(uv * 2.0) * 0.6 + n(uv * 5.0) * 0.4;
	float band = smoothstep(0.35, 0.75, s);
	ALBEDO = mix(col2.rgb, col.rgb, band);
	float edge = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.8, UV.y);
	ALPHA = alpha * edge * (0.45 + 0.55 * band);
}
"""
	_mat.shader = sh
	var radii := [[1.6, 1.3], [1.4, 1.7], [1.8, 2.4], [2.5, 3.4], [3.4, 4.5]]
	for i in radii.size():
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = float(radii[i][0])
		cm.top_radius = float(radii[i][1])
		cm.height = 2.9
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 24
		mi.mesh = cm
		mi.material_override = _mat
		mi.position = Vector3(0, 1.45 + float(i) * 2.75, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_layers.append(mi)
	_cups = Node3D.new()
	add_child(_cups)
	var white := Color(0.97, 0.95, 0.92)
	for k in 8:
		var cup := Node3D.new()
		_cups.add_child(cup)
		var a := TAU * float(k) / 8.0
		var r := 1.4 + float(k % 3) * 0.8
		cup.position = Vector3(cos(a) * r, 1.5 + float(k) * 1.3, sin(a) * r)
		# Real teacup model whirling in the funnel (r1 m10: cylinder and torus stand-ins).
		var real := EnemyKit.teacup(0.45 if k % 2 == 0 else 0.32)
		if real != null:
			cup.add_child(real)
			real.rotation_degrees = Vector3(25.0 * float(k % 3), 0, 15.0 * float(k % 2))
		elif k % 2 == 0:
			EnemyKit.cylinder(cup, 0.24, 0.18, 0.26, white, Vector3.ZERO)
			EnemyKit.ring(cup, 0.06, 0.1, white, Vector3(0.26, 0, 0), Vector3(90, 0, 0))
		else:
			var s := EnemyKit.cylinder(cup, 0.36, 0.3, 0.05, white, Vector3.ZERO)
			EnemyKit.ring(cup, 0.3, 0.36, Color(0.85, 0.68, 0.3), Vector3(0, 0.03, 0))
			s.rotation_degrees.x = 25.0
	core = Area3D.new()
	core.name = "Core"
	core.collision_layer = 16
	core.collision_mask = 0
	core.add_to_group("hazard")
	core.set_meta("damage", 1)
	core.set_meta("knockback_up", 6.0)
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 1.0
	c.height = 5.0
	cs.shape = c
	cs.position = Vector3(0, 2.5, 0)
	core.add_child(cs)
	add_child(core)


func set_alpha(a: float) -> void:
	alpha = a
	# LOOK finish: the funnel filled a third of some phase-3 frames as a wall; it now reads as a gust.
	_mat.set_shader_parameter("alpha", 0.32 * a)


func _process(delta: float) -> void:
	_t += delta
	for i in _layers.size():
		_layers[i].rotation.y += delta * (5.0 - float(i) * 0.6)
		_layers[i].position.x = sin(_t * 1.3 + float(i) * 0.8) * 0.25 * float(i)
	_cups.rotation.y += delta * 4.0
	for c in _cups.get_children():
		(c as Node3D).rotation += Vector3(delta * 3.0, delta * 5.0, 0)
