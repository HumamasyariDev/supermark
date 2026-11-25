class_name GustSwirl
extends Node3D
## Wind lines for gust zones, bellows blasts and the boss's huff: curling white streaks that
## corkscrew along the local -Z axis (the node's forward), plus drifting motes and leaves.
## Place it at the gust source and rotate it so -Z points along the wind. Size it with length/radius.
##   set_active(false) fades it out; play() / emit() fades in again.

@export var length := 10.0
@export var radius := 1.4
@export var lines := 6
@export var width := 0.12
@export var swirl_turns := 1.5
@export var strength := 1.0
@export var color := Color(1, 1, 1, 0.9)
@export var with_motes := true

var _im: ImmediateMesh
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _vis := 1.0
var _on := true
var _time := 0.0
var _motes: FxEffect


func _ready() -> void:
	_im = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.top_level = true
	_mi.mesh = _im
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/fx_ribbon.gdshader")
	_mat.set_shader_parameter("color", Color(0.85, 0.93, 1.0))
	_mat.set_shader_parameter("core_color", Color(1, 1, 1))
	_mat.set_shader_parameter("dash_count", 1.6)
	_mat.set_shader_parameter("dash_fill", 0.45)
	_mat.set_shader_parameter("scroll_speed", 1.1 * strength)
	_mat.set_shader_parameter("intensity", 0.9)
	_mat.set_shader_parameter("wisp", 0.3)
	_mi.material_override = _mat
	add_child(_mi)
	_mi.global_transform = Transform3D.IDENTITY
	if with_motes:
		_motes = FxEffect.new()
		_motes.preset = "gust_motes"
		_motes.free_when_done = false
		add_child(_motes)
		# The motes preset blows along +X; turn it to blow along -Z and centre it on the gust.
		_motes.rotation = Vector3(0, PI * 0.5, 0)
		_motes.position = Vector3(0, 0, -length * 0.4)


func play() -> void:
	_on = true
	if _motes:
		_motes.set_active(true)


func emit() -> void:
	play()


func set_active(on: bool) -> void:
	_on = on
	if _motes:
		_motes.set_active(on)


func _process(delta: float) -> void:
	_time += delta
	_vis = move_toward(_vis, 1.0 if _on else 0.0, delta * 3.0)
	_im.clear_surfaces()
	if _vis <= 0.001:
		return
	_mat.set_shader_parameter("visibility", _vis * color.a)
	var cam := FxRibbonUtil.camera_position(self)
	var xf := global_transform
	var seg := 28
	for l in lines:
		var ph := float(l) / float(lines) * TAU
		var r := radius * (0.55 + 0.45 * fmod(float(l) * 0.618, 1.0))
		var off := fmod(float(l) * 0.37, 1.0) * length * 0.3
		var seg_len := length * 0.6
		var pts := PackedVector3Array()
		for i in seg + 1:
			var t := float(i) / float(seg)
			var z := -(off + t * seg_len)
			var a := ph + t * swirl_turns * TAU - _time * 2.2 * strength
			# Lines curl at the end like a cartoon gust.
			var curl := smoothstep(0.6, 1.0, t)
			var local := Vector3(cos(a) * r * (1.0 - curl * 0.5), sin(a) * r * 0.6 + curl * r * 0.4, z)
			pts.append(xf * local)
		FxRibbonUtil.draw(_im, pts, width, cam)
