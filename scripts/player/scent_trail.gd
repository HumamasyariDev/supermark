class_name MakScentTrail
extends Node3D
## Fallback Snout Sniff trail used when res://scenes/fx/ScentTrail.tscn does not exist:
## glowing golden motes that drift from Mak's snout toward the sniffed target along a soft arc.

const COUNT := 28
const SPAN := 9.0          ## m of trail shown from the snout
var source: Node3D = null
var target: Node3D = null
var _motes: Array[MeshInstance3D] = []
var _t := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.2)
	mat.emission_energy_multiplier = 2.6
	mat.roughness = 0.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 10
	mesh.rings = 5
	for i in COUNT:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_motes.append(m)


func _process(delta: float) -> void:
	if source == null or target == null or not is_instance_valid(source) or not is_instance_valid(target):
		visible = false
		return
	visible = true
	_t += delta
	var yaw := source.global_rotation.y
	var a := source.get_global_transform_interpolated().origin + Vector3(0.0, 0.78, 0.0) + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.33
	var b := target.global_position + Vector3(0.0, 0.3, 0.0)
	var d := b - a
	var dist := d.length()
	if dist < 0.01:
		return
	var dir := d / dist
	var right := dir.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	var span := minf(dist, SPAN)
	for i in COUNT:
		var m := _motes[i]
		var u := fmod(float(i) / COUNT + _t * 0.32, 1.0)
		var p := a + dir * (u * span)
		p.y += sin(u * PI) * 0.5 * minf(span / 4.0, 1.0) + sin(_t * 3.1 + i * 0.9) * 0.06
		p += right * sin(_t * 2.3 + i * 1.7) * 0.14 * u
		m.global_position = p
		var fade := sin(u * PI)
		m.scale = Vector3.ONE * (0.35 + 1.0 * fade)
