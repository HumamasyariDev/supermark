class_name ScentTrail
extends Node3D
## Snout Sniff scent trail: two intertwined golden wisps that flow from this node (put it on Mak,
## at the snout height or at the body origin with start_offset) toward a target position, plus
## sparkle dust drifting along the path.
##   trail.set_target(world_pos)   # starts/updates the trail, fades in
##   trail.clear_target()          # fades out
## Far targets: the visible trail is capped at max_length metres along the curve, so it points the way.

@export var start_offset := Vector3(0, 0.7, 0)
@export var end_offset := Vector3(0, 0.4, 0)
@export var max_length := 14.0
@export var width := 0.18
@export var arc_height := 1.6
@export var segments := 40
@export var color := Color(1.0, 0.8, 0.3)
@export var fade_speed := 2.5

var _target := Vector3.ZERO
var _has_target := false
var _vis := 0.0
var _im: ImmediateMesh
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _dust: Variant # GPU on desktop, equivalent CPU emitter on web.
var _time := 0.0


func _ready() -> void:
	_im = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.top_level = true
	_mi.mesh = _im
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/fx_ribbon.gdshader")
	_mat.set_shader_parameter("color", color)
	_mat.set_shader_parameter("dash_count", 4.0)
	_mat.set_shader_parameter("dash_fill", 0.6)
	_mat.set_shader_parameter("scroll_speed", 0.9)
	_mat.set_shader_parameter("intensity", 1.1)
	_mat.set_shader_parameter("wisp", 0.9)
	_mi.material_override = _mat
	add_child(_mi)
	_mi.global_transform = Transform3D.IDENTITY
	_dust = FxPresets.make_particles({"tex": "sparkle", "amount": 24, "lifetime": 0.9, "explosiveness": 0.0, "emit": "sphere", "radius": 0.25,
		"spread": 180.0, "vel": Vector2(0.05, 0.3), "gravity": Vector3(0, 0.25, 0), "size": Vector2(0.1, 0.2), "curve": "pop", "add": true, "world": true,
		"colors": [[0.0, Color(1, 0.95, 0.7)], [1.0, Color(1, 0.75, 0.3, 0.0)]]}, 1.0, Color.WHITE, false)
	_dust.top_level = true
	add_child(_dust)


func set_target(world_pos: Vector3) -> void:
	_target = world_pos
	_has_target = true


func clear_target() -> void:
	_has_target = false


func set_active(on: bool) -> void:
	if not on:
		clear_target()


func _process(delta: float) -> void:
	_time += delta
	_vis = move_toward(_vis, 1.0 if _has_target else 0.0, delta * fade_speed)
	_im.clear_surfaces()
	_dust.emitting = _vis > 0.3
	if _vis <= 0.001:
		return
	_mat.set_shader_parameter("visibility", _vis)
	_mat.set_shader_parameter("reveal", clampf(_vis * 1.2, 0.0, 1.0))
	var start := global_position + start_offset
	if is_inside_tree() and has_method("get_global_transform_interpolated"):
		start = get_global_transform_interpolated().origin + start_offset
	var end := _target + end_offset
	var full := end - start
	var dist := full.length()
	var cap := 1.0
	if dist > max_length:
		cap = max_length / dist
	var flat := Vector3(full.x, 0.0, full.z)
	var side := flat.cross(Vector3.UP).normalized() if flat.length() > 0.01 else Vector3.RIGHT
	var p1 := start + Vector3.UP * arc_height + full * 0.25
	var p2 := end + Vector3.UP * arc_height * 0.8 - full * 0.2
	var cam := FxRibbonUtil.camera_position(self)
	for strand in 2:
		var pts := PackedVector3Array()
		var ph := float(strand) * PI
		for i in segments + 1:
			var t := float(i) / float(segments) * cap
			var p := FxRibbonUtil.bezier(start, p1, p2, end, t)
			var wob := sin(t * dist * 0.9 - _time * 3.0 + ph) * 0.25 * sin(t * PI / maxf(cap, 0.01))
			p += side * wob + Vector3.UP * cos(t * dist * 0.7 - _time * 2.4 + ph) * 0.12
			pts.append(p)
		FxRibbonUtil.draw(_im, pts, width * (1.0 if strand == 0 else 0.7), cam)
	# Sparkle dust travels along the curve.
	var tt := fmod(_time * 0.35, 1.0) * cap
	_dust.global_position = FxRibbonUtil.bezier(start, p1, p2, end, tt)
