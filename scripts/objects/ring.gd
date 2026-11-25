class_name TrialRing
extends Area3D
## A golden hoop to fly or run through (time trials, cloud rings). Spins slowly; flashes when passed.
## `active` false dims it (used by TimeTrial for rings that are not yet live).

signal passed(ring: Node)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var radius: float = 1.3
@export var color: Color = Color(1.0, 0.76, 0.22)
@export var active: bool = true
@export var spin: bool = true

var is_passed := false
var _t := 0.0
var _hoop: Node3D
var _mat: StandardMaterial3D
var _pass_tw: Tween
var _bell_kick := 0.0


func _ready() -> void:
	add_to_group("trial_ring")
	collision_layer = ObjSvc.L_TRIGGER
	collision_mask = ObjSvc.L_PLAYER
	ObjSvc.add_shape(self, ObjSvc.cyl_shape(radius * 0.85, 0.8), Vector3.ZERO, Vector3(90, 0, 0))
	var v := ObjSvc.ensure_visual(self)
	_hoop = Node3D.new()
	add_child(_hoop)
	v.reparent(_hoop, false)
	if not ObjSvc.visual_has_content(v):
		_build_trial_hoop(v)
	body_entered.connect(_on_body)
	set_active(active)
	_t = randf() * TAU


## Critique objects r1 re-run: the ring was a plain gold torus. It is now a storybook trial hoop: a brass hoop wound
## with a red satin ribbon (a real helical strip, not stripes), a bow with tails on top and a little brass bell on a
## cord at the bottom that swings as the hoop sways and rings when Mak passes. A soft emissive inner edge keeps it
## readable against a pale sky. The hoop no longer spins about its axis (the bell would turn upside down); it sways.
var _bell: Node3D
var _bow: Node3D
var _ribbon_mat: StandardMaterial3D


func _build_trial_hoop(v: Node3D) -> void:
	var tube := 0.12
	_mat = ObjSvc.unique_mat(color, 0.28, 0.85, color, 0.5)
	ObjSvc.torus(v, radius - tube, radius + tube, _mat, Vector3.ZERO, Vector3(90, 0, 0))
	# Ink rim (inverted hull) so it reads on the white cloud sea.
	var rim := StandardMaterial3D.new()
	rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.albedo_color = Color(0.4, 0.2, 0.05)
	rim.cull_mode = BaseMaterial3D.CULL_FRONT
	var rt := ObjSvc.torus(v, radius - tube - 0.03, radius + tube + 0.03, rim, Vector3.ZERO, Vector3(90, 0, 0))
	rt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Soft glowing inner edge.
	var core := ObjSvc.unshaded(Color(1.0, 0.93, 0.62))
	var ct := ObjSvc.torus(v, radius - tube - 0.02, radius - tube + 0.03, core, Vector3.ZERO, Vector3(90, 0, 0))
	ct.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Ribbon wound round the tube.
	_ribbon_mat = ObjSvc.unique_mat(Color(0.78, 0.12, 0.14), 0.42, 0.0, Color(0.6, 0.05, 0.05), 0.15)
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rib := MeshInstance3D.new()
	rib.name = "Ribbon"
	rib.mesh = _helix_ribbon(radius, tube + 0.012, 14, 0.07)
	rib.material_override = _ribbon_mat
	v.add_child(rib)
	# Bow on top: two loops, a knot and two swallow-tailed tails.
	_bow = Node3D.new()
	_bow.name = "Bow"
	_bow.position = Vector3(0, radius + tube * 0.6, 0.02)
	v.add_child(_bow)
	for sx in [-1.0, 1.0]:
		var loop := ObjSvc.torus(_bow, 0.07, 0.17, _ribbon_mat, Vector3(sx * 0.17, 0.05, 0.0), Vector3(90, 0, sx * -18.0))
		loop.scale = Vector3(1.0, 0.45, 0.7)
		var tail := ObjSvc.box(_bow, Vector3(0.09, 0.34, 0.02), _ribbon_mat, Vector3(sx * 0.1, -0.2, 0.03), Vector3(0, 0, sx * 22.0))
		tail.name = "Tail"
	ObjSvc.sphere(_bow, 0.07, _ribbon_mat, Vector3(0, 0.03, 0.02), Vector3(1.0, 0.9, 0.8))
	# Bell on a short cord under the hoop.
	_bell = Node3D.new()
	_bell.name = "Bell"
	_bell.position = Vector3(0, -radius - tube, 0)
	v.add_child(_bell)
	var cord := ObjSvc.mat(Color(0.62, 0.1, 0.12), 0.6)
	ObjSvc.cylinder(_bell, 0.012, 0.012, 0.16, cord, Vector3(0, -0.08, 0))
	var bell_mesh := MeshInstance3D.new()
	bell_mesh.mesh = _bell_lathe(0.13, 0.2)
	bell_mesh.material_override = ObjSvc.mat(ObjSvc.BRASS, 0.25, 0.9, Color(1.0, 0.7, 0.3), 0.15)
	bell_mesh.position = Vector3(0, -0.16, 0)
	_bell.add_child(bell_mesh)
	ObjSvc.sphere(_bell, 0.035, ObjSvc.mat(ObjSvc.IRON, 0.4, 0.8), Vector3(0, -0.37, 0))


## A flat strip wound helically round a torus of major radius R and tube radius r (turns around the tube over one
## lap). The hoop lies in the XY plane.
static func _helix_ribbon(R: float, r: float, turns: int, w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := turns * 24
	for i in steps + 1:
		var u := TAU * float(i) / float(steps)
		var vv := float(turns) * u
		var c := Vector3(cos(u), sin(u), 0.0)
		var out := c * cos(vv) + Vector3(0, 0, 1) * sin(vv)
		var p := c * R + out * r
		var tan_u := Vector3(-sin(u), cos(u), 0.0)
		var side := tan_u.normalized() * w * 0.5
		st.set_normal(out)
		st.set_uv(Vector2(0, float(i) / 24.0))
		st.add_vertex(p - side)
		st.set_normal(out)
		st.set_uv(Vector2(1, float(i) / 24.0))
		st.add_vertex(p + side)
	for i in steps:
		var a := i * 2
		st.add_index(a)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 3)
		st.add_index(a + 2)
	return st.commit()


## A small hand bell turned on a lathe: shoulder, waist and a flared lip, open underneath.
static func _bell_lathe(rad: float, h: float) -> ArrayMesh:
	var prof: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.35, -0.02), Vector2(0.5, -0.1), Vector2(0.52, -0.3),
		Vector2(0.6, -0.6), Vector2(0.82, -0.88), Vector2(1.0, -1.0), Vector2(0.94, -1.03)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	for j in prof.size():
		for i in seg + 1:
			var a := TAU * float(i) / float(seg)
			st.add_vertex(Vector3(cos(a) * prof[j].x * rad, prof[j].y * h, sin(a) * prof[j].x * rad))
	for j in prof.size() - 1:
		for i in seg:
			var a := j * (seg + 1) + i
			var b := a + seg + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_normals()
	return st.commit()


func set_active(on: bool) -> void:
	active = on
	if _ribbon_mat:
		_ribbon_mat.albedo_color = Color(0.78, 0.12, 0.14) if on else Color(0.5, 0.4, 0.42)
	if _mat:
		_mat.emission_energy_multiplier = 0.5 if on else 0.0
		_mat.albedo_color = color if on else Color(color.r, color.g, color.b, 0.35)
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if on else BaseMaterial3D.TRANSPARENCY_ALPHA


func reset() -> void:
	if _pass_tw != null and _pass_tw.is_valid():
		_pass_tw.kill()
	_pass_tw = null
	is_passed = false
	_hoop.scale = Vector3.ONE
	visible = true


func _process(delta: float) -> void:
	_t += delta
	if spin and not is_passed:
		if _bell == null:
			_hoop.rotation.z += delta * 0.6
		else:
			# A gentle sway; the bell swings a beat behind and the bow tails flutter.
			_hoop.rotation.y = sin(_t * 0.9) * 0.18
			_hoop.rotation.z = sin(_t * 0.7) * 0.03
			_bell.rotation.z = sin(_t * 0.7 - 0.8) * 0.12 + sin(_t * 9.0) * 0.5 * _bell_kick * _bell_kick
			_bell.rotation.x = sin(_t * 0.9 - 0.6) * 0.1
			for c in _bow.get_children():
				if c.name.begins_with("Tail"):
					(c as Node3D).rotation.x = sin(_t * 3.3 + c.get_index()) * 0.15
		_bell_kick = move_toward(_bell_kick, 0.0, delta * 1.2)
		var s := 1.0 + sin(_t * 3.0) * (0.04 if active else 0.0)
		_hoop.scale = Vector3(s, s, s)


func _on_body(body: Node) -> void:
	if is_passed or not active or not ObjSvc.is_player(body):
		return
	is_passed = true
	ObjSvc.feedback("object_ring_pass", global_position, {"index": get_index(), "tint": color}, "ring")
	passed.emit(self)
	if not ObjSvc.juice_handles("object_ring_pass", "vfx"):
		ObjSvc.burst(get_parent(), global_position, color, 24, 4.0, 0.15, 0.0, 0.6)
	_bell_kick = 1.0
	_pass_tw = create_tween()
	_pass_tw.tween_property(_hoop, "scale", Vector3.ONE * 1.5, 0.2)
	_pass_tw.tween_property(_hoop, "scale", Vector3.ONE * 0.01, 0.15)
	_pass_tw.tween_callback(func() -> void: visible = false)
