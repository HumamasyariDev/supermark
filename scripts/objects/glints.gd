class_name ObjGlints
extends Node3D
## Twinkling four-point star glints scattered over a sphere around the parent (pickup sparkle).
## Each glint fades in, flares and fades out at a random point, then moves somewhere else.

@export var count: int = 3
@export var radius: float = 0.3
@export var size: float = 0.32
@export var color: Color = Color(1.0, 0.95, 0.7)
@export var period: float = 1.4
@export var center: Vector3 = Vector3.ZERO

static var _star: Texture2D

var _quads: Array[MeshInstance3D] = []
var _phase: Array[float] = []
var _t := 0.0


static func star_tex() -> Texture2D:
	if _star != null:
		return _star
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / n * 2.0 - 1.0
			var v := (float(y) + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ray := exp(-absf(u) * 26.0) * maxf(0.0, 1.0 - absf(v)) + exp(-absf(v) * 26.0) * maxf(0.0, 1.0 - absf(u))
			var core := exp(-r * r * 40.0)
			var a := clampf(ray * 0.9 + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_star = ImageTexture.create_from_image(img)
	return _star


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = star_tex()
	m.albedo_color = color
	m.no_depth_test = false
	m.render_priority = 2
	for i in count:
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_quads.append(mi)
		_phase.append(float(i) / float(maxi(count, 1)) + randf() * 0.2)
		_move(i)


func _move(i: int) -> void:
	var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)).normalized()
	# Prefer the side facing the camera so glints are seen.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var to_cam := (cam.global_position - global_position).normalized()
		d = (d + to_cam * 0.9).normalized()
		d = global_basis.inverse() * d
	_quads[i].position = center + d * radius


func _process(delta: float) -> void:
	_t += delta
	for i in _quads.size():
		var ph := fposmod(_t / period + _phase[i], 1.0)
		var prev := fposmod((_t - delta) / period + _phase[i], 1.0)
		if ph < prev:
			_move(i)
		# Flare in the first 35 % of the cycle, dark the rest.
		var k := 0.0
		if ph < 0.35:
			k = sin(ph / 0.35 * PI)
		var s := 0.15 + k * 0.85
		_quads[i].scale = Vector3.ONE * s
		_quads[i].visible = k > 0.02
