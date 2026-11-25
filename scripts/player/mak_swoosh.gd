class_name MakSwoosh
extends MeshInstance3D
## Cartoon strike swoosh: a tapered ribbon that sweeps along an arc around Mak and fades.
## Built in the parent's space (Mak's Visual node: forward = -Z). One-shot; frees itself.
##   MakSwoosh.spawn(parent, {"a0": -100, "a1": 10, "r": 0.55, "h": 0.45, "w": 0.16, "life": 0.2})
## Angles are degrees around +Y measured from forward (-Z); positive turns to Mak's left.
## "axis": "y" (horizontal sweep, default) or "x" (vertical sweep in the sagittal plane: angle from up toward forward).

var a0 := -100.0
var a1 := 10.0
var radius := 0.55
var height := 0.45
var width := 0.16
var life := 0.2
var axis := "y"
var color := Color(1.0, 0.96, 0.84, 0.85)
var _t := 0.0
var _im := ImmediateMesh.new()

static var _mat: StandardMaterial3D = null


static func spawn(parent: Node3D, cfg: Dictionary) -> MakSwoosh:
	var s := MakSwoosh.new()
	s.a0 = float(cfg.get("a0", -100.0))
	s.a1 = float(cfg.get("a1", 10.0))
	s.radius = float(cfg.get("r", 0.55))
	s.height = float(cfg.get("h", 0.45))
	s.width = float(cfg.get("w", 0.16))
	s.life = float(cfg.get("life", 0.2))
	s.axis = str(cfg.get("axis", "y"))
	if cfg.has("color"):
		s.color = cfg["color"]
	parent.add_child(s)
	return s


func _ready() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.no_depth_test = false
	material_override = _mat
	_build()


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	_build()


func _point(a_deg: float, r: float, lift: float = 0.0) -> Vector3:
	var a := deg_to_rad(a_deg)
	if axis == "x":
		# Sagittal arc around the hip: 0 = up, 90 = forward. "lift" spreads the band sideways (X).
		return Vector3(lift, height + cos(a) * r, -sin(a) * r)
	return Vector3(-sin(a) * r, height + lift, -cos(a) * r)


func _build() -> void:
	_im.clear_surfaces()
	var u := clampf(_t / life, 0.0, 1.0)
	# The head races ahead in the first 45 % of the life; the tail follows and the whole ribbon fades.
	var head := clampf(u / 0.45, 0.0, 1.0)
	head = 1.0 - (1.0 - head) * (1.0 - head)
	var tail := clampf((u - 0.2) / 0.8, 0.0, 1.0)
	tail = tail * tail
	if head - tail < 0.01:
		return
	var fade := 1.0 - smoothstep(0.55, 1.0, u)
	# A crescent smear: the band in the sweep plane is bright on its outer (leading) edge and fades to clear at
	# the inner edge, a faint band across the plane keeps it readable edge-on, and two thin speed lines trail
	# outside it. Together they read as a swoosh from any camera angle without hiding Mak.
	_strip(tail, head, fade, width, 0.0, true, color, 0.08)
	var edge := Color(1.0, 1.0, 1.0, minf(1.0, color.a))
	_strip(lerpf(tail, head, 0.3), head, fade, width * 0.18, width * 0.42, true, edge, 1.0)
	var cross := Color(color.r, color.g, color.b, color.a * 0.32)
	_strip(lerpf(tail, head, 0.3), head, fade, width * 0.45, width * 0.25, false, cross, 1.0)
	var line := Color(color.r, color.g, color.b, color.a * 0.6)
	_strip(lerpf(tail, head, 0.25), lerpf(tail, head, 0.85), fade, width * 0.1, width * 0.85, true, line, 1.0)
	_strip(lerpf(tail, head, 0.45), lerpf(tail, head, 0.95), fade, width * 0.08, width * 1.15, true, line, 1.0)


## One tapered strip from fraction f0 to f1 of the arc. radial: width across the radius, otherwise across the
## sweep plane. offset shifts the strip outward (radial) for the speed lines; inner_alpha scales the inner edge.
func _strip(f0: float, f1: float, fade: float, w0: float, offset: float, radial: bool, col: Color, inner_alpha: float) -> void:
	var n := 22
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n + 1:
		var k := float(i) / float(n)
		var f := lerpf(f0, f1, k)
		var a := lerpf(a0, a1, f)
		var taper := sin(k * PI * 0.5) * (1.0 - 0.25 * k)
		var w := w0 * taper
		var c := col
		c.a = col.a * fade * (0.15 + 0.85 * k)
		var r := radius + offset
		_im.surface_set_color(c)
		if radial:
			_im.surface_add_vertex(_point(a, r + w * 0.5))
			var ci := c
			ci.a = c.a * inner_alpha
			_im.surface_set_color(ci)
			_im.surface_add_vertex(_point(a, r - w * 0.5))
		else:
			_im.surface_add_vertex(_point(a, r, w * 0.5))
			_im.surface_set_color(c)
			_im.surface_add_vertex(_point(a, r, -w * 0.5))
	_im.surface_end()
