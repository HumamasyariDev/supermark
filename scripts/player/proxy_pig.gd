class_name ProxyPig
extends Node3D
## Procedural placeholder hero ("proxy pig"): Mr. Mak built from smooth primitives.
## Feet at the origin, faces -Z, about 1.2 m tall with the beanie.
## Joint pivots carry the abstract rig names used by MakAnimator. Every pivot has an identity
## rest rotation so that pose rotations are character-space rotations (X right, Y up, -Z forward).

const JOINTS := ["root", "hips", "spine", "head", "ear_l", "ear_r", "arm_l", "forearm_l", "arm_r",
	"forearm_r", "thigh_l", "shin_l", "thigh_r", "shin_r", "tail", "backpack"]

const C_BODY := Color(0.97, 0.925, 0.85)
const C_BELLY := Color(0.995, 0.965, 0.91)
const C_PINK := Color(0.95, 0.55, 0.61)
const C_SNOUT := Color(0.96, 0.61, 0.66)
const C_NOSEPAD := Color(0.985, 0.70, 0.73)
const C_NOSTRIL := Color(0.40, 0.14, 0.19)
const C_HOOF := Color(0.37, 0.23, 0.14)
const C_PATCH := Color(0.74, 0.55, 0.38)
const C_EYE := Color(1.0, 0.99, 0.97)
const C_IRIS := Color(0.46, 0.27, 0.11)
const C_PUPIL := Color(0.05, 0.035, 0.03)
const C_BROW := Color(0.33, 0.20, 0.12)
const C_TAIL := Color(0.98, 0.80, 0.78)
const C_PACK := Color(0.56, 0.34, 0.18)
const C_PACK_DARK := Color(0.43, 0.25, 0.12)
const C_BEANIE := Color(0.58, 0.59, 0.62)
const C_BEANIE_CUFF := Color(0.49, 0.50, 0.53)

var joints := {}             ## joint name -> Node3D pivot
var eye_nodes: Array[Node3D] = []
var brow_nodes: Array[Node3D] = []
var hat_anchor: Node3D = null
var hat_id := ""
var _mats := {}


func _ready() -> void:
	if joints.is_empty():
		build()


func build() -> void:
	_make_materials()
	var root := _pivot("root", self, Vector3.ZERO)
	var hips := _pivot("hips", root, Vector3(0.0, 0.30, 0.0))
	_mesh(hips, _sphere(0.215, 0.36), "body", Vector3(0.0, 0.05, 0.015), Vector3.ZERO, Vector3(1.0, 1.0, 0.95))
	var spine := _pivot("spine", hips, Vector3(0.0, 0.04, 0.0))
	_mesh(spine, _sphere(0.245, 0.56), "body", Vector3(0.0, 0.16, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.93))
	_mesh(spine, _sphere(0.19, 0.40), "belly", Vector3(0.0, 0.10, -0.088), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))

	# Head: a big round skull, chubby cheeks, snout, eyes with a brown patch on the right eye.
	var head := _pivot("head", spine, Vector3(0.0, 0.40, -0.01))
	_mesh(head, _sphere(0.265, 0.50), "body", Vector3(0.0, 0.13, 0.0))
	_mesh(head, _sphere(0.085, 0.16), "body", Vector3(0.13, 0.03, -0.15), Vector3.ZERO, Vector3(1.0, 0.85, 0.8))
	_mesh(head, _sphere(0.085, 0.16), "body", Vector3(-0.13, 0.03, -0.15), Vector3.ZERO, Vector3(1.0, 0.85, 0.8))
	_mesh(head, _sphere(0.112, 0.224), "snout", Vector3(0.0, 0.065, -0.245), Vector3.ZERO, Vector3(1.0, 0.8, 0.55))
	_mesh(head, _sphere(0.09, 0.18), "nosepad", Vector3(0.0, 0.068, -0.282), Vector3.ZERO, Vector3(1.0, 0.76, 0.22))
	_mesh(head, _sphere(0.021, 0.042), "nostril", Vector3(0.036, 0.066, -0.302), Vector3.ZERO, Vector3(0.8, 1.25, 0.5))
	_mesh(head, _sphere(0.021, 0.042), "nostril", Vector3(-0.036, 0.066, -0.302), Vector3.ZERO, Vector3(0.8, 1.25, 0.5))
	_mesh(head, _sphere(0.078, 0.156), "patch", Vector3(0.112, 0.17, -0.224), Vector3(0.0, 20.0, 0.0), Vector3(1.1, 1.0, 0.28))
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.name = "eye_l" if side < 0.0 else "eye_r"
		eye.position = Vector3(0.1 * side, 0.168, -0.226)
		eye.rotation_degrees = Vector3(0.0, -14.0 * side, 0.0)
		head.add_child(eye)
		_mesh(eye, _sphere(0.062, 0.124), "eye", Vector3.ZERO, Vector3.ZERO, Vector3(0.92, 1.12, 0.55))
		_mesh(eye, _sphere(0.043, 0.086), "iris", Vector3(0.0, -0.004, -0.024), Vector3.ZERO, Vector3(1.0, 1.1, 0.5))
		_mesh(eye, _sphere(0.026, 0.052), "pupil", Vector3(0.0, -0.004, -0.035), Vector3.ZERO, Vector3(1.0, 1.1, 0.5))
		_mesh(eye, _sphere(0.012, 0.024), "shine", Vector3(0.014 * side, 0.018, -0.047), Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
		eye_nodes.append(eye)
		var brow := Node3D.new()
		brow.name = "brow_l" if side < 0.0 else "brow_r"
		brow.position = Vector3(0.1 * side, 0.252, -0.212)
		brow.rotation_degrees = Vector3(-18.0, -14.0 * side, -12.0 * side)
		head.add_child(brow)
		_mesh(brow, _capsule(0.015, 0.095), "brow", Vector3.ZERO, Vector3(0.0, 0.0, 90.0))
		brow_nodes.append(brow)
	# Ears: big triangle-ish cones, pink inside. The tilt lives in the mesh, the pivot stays identity.
	for side in [-1.0, 1.0]:
		var ear := _pivot("ear_l" if side < 0.0 else "ear_r", head, Vector3(0.215 * side, 0.215, 0.02))
		var tilt := Vector3(-14.0, 0.0, -66.0 * side)
		var outer := _mesh(ear, _cone(0.125, 0.27), "body", Vector3.ZERO, tilt, Vector3(1.0, 1.0, 0.38))
		outer.position = Basis.from_euler(tilt * PI / 180.0) * Vector3(0.0, 0.12, 0.0)
		var inner := _mesh(ear, _cone(0.085, 0.19), "pink", Vector3.ZERO, tilt, Vector3(1.0, 1.0, 0.25))
		inner.position = Basis.from_euler(tilt * PI / 180.0) * Vector3(0.0, 0.095, -0.03)
	hat_anchor = Node3D.new()
	hat_anchor.name = "hat_anchor"
	hat_anchor.position = Vector3(0.0, 0.215, 0.015)
	hat_anchor.rotation_degrees = Vector3(9.0, 0.0, 0.0)
	head.add_child(hat_anchor)

	# Arms: stubby, cream, with dark-brown hooves.
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var arm := _pivot("arm_" + side, spine, Vector3(0.205 * sx, 0.27, 0.0))
		_mesh(arm, _capsule(0.07, 0.21), "body", Vector3(0.0, -0.065, 0.0))
		var fore := _pivot("forearm_" + side, arm, Vector3(0.0, -0.13, 0.0))
		_mesh(fore, _capsule(0.066, 0.17), "body", Vector3(0.0, -0.045, 0.0))
		_mesh(fore, _sphere(0.072, 0.11), "hoof", Vector3(0.0, -0.112, 0.0))
	# Legs: thigh 0.13 m + shin 0.16 m; hoof soles at y = 0.
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var thigh := _pivot("thigh_" + side, hips, Vector3(0.11 * sx, -0.01, 0.0))
		_mesh(thigh, _capsule(0.092, 0.22), "body", Vector3(0.0, -0.05, 0.0))
		var shin := _pivot("shin_" + side, thigh, Vector3(0.0, -0.13, 0.0))
		_mesh(shin, _capsule(0.086, 0.17), "body", Vector3(0.0, -0.055, 0.0))
		_mesh(shin, _cyl(0.088, 0.097, 0.07), "hoof", Vector3(0.0, -0.125, -0.012))
	# Curly tail.
	var tail := _pivot("tail", hips, Vector3(0.0, 0.05, 0.205))
	_mesh(tail, _torus(0.022, 0.058), "tail", Vector3(0.0, 0.045, 0.035), Vector3(0.0, 0.0, 90.0))
	_mesh(tail, _sphere(0.024, 0.048), "tail", Vector3(0.0, 0.09, 0.02))
	# Backpack.
	var pack := _pivot("backpack", spine, Vector3(0.0, 0.20, 0.215))
	_mesh(pack, _sphere(0.19, 0.42), "pack", Vector3(0.0, 0.0, 0.05), Vector3.ZERO, Vector3(1.0, 1.0, 0.62))
	_mesh(pack, _sphere(0.175, 0.35), "pack_dark", Vector3(0.0, 0.11, 0.06), Vector3(-10.0, 0.0, 0.0), Vector3(1.06, 0.42, 0.64))
	_mesh(pack, _sphere(0.08, 0.16), "pack_dark", Vector3(0.0, -0.07, 0.155), Vector3.ZERO, Vector3(1.25, 0.85, 0.5))
	_mesh(pack, _sphere(0.022, 0.044), "brass", Vector3(0.0, 0.05, 0.172), Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
	for side in [-1.0, 1.0]:
		_mesh(spine, _capsule(0.024, 0.2), "pack_dark", Vector3(0.13 * side, 0.32, -0.035), Vector3(60.0, 0.0, 0.0))
	set_hat("beanie")


func set_hat(id: String) -> void:
	if hat_anchor == null:
		return
	hat_id = id
	for c in hat_anchor.get_children():
		c.queue_free()
	for ext in ["tscn", "glb"]:
		var path := "res://assets/characters/hats/%s.%s" % [id, ext]
		if ResourceLoader.exists(path):
			var ps := load(path) as PackedScene
			if ps != null:
				var n := ps.instantiate() as Node3D
				if n != null:
					if ext == "glb":
						n.rotation.y = PI
					hat_anchor.add_child(n)
					return
	if id == "top_hat":
		_mesh(hat_anchor, _cyl(0.27, 0.27, 0.022), "hat_black", Vector3(0.0, 0.12, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.92))
		_mesh(hat_anchor, _cyl(0.16, 0.148, 0.3), "hat_black", Vector3(0.0, 0.27, 0.0))
		_mesh(hat_anchor, _cyl(0.151, 0.151, 0.06), "hat_band", Vector3(0.0, 0.16, 0.0))
	else:
		var dome := SphereMesh.new()
		dome.radius = 0.262
		dome.height = 0.36
		dome.is_hemisphere = true
		dome.radial_segments = 40
		dome.rings = 14
		_mesh(hat_anchor, dome, "beanie", Vector3.ZERO)
		var cuff := TorusMesh.new()
		cuff.inner_radius = 0.228
		cuff.outer_radius = 0.29
		cuff.rings = 40
		cuff.ring_segments = 12
		_mesh(hat_anchor, cuff, "beanie_cuff", Vector3(0.0, 0.012, 0.0), Vector3.ZERO, Vector3(1.0, 1.55, 1.0))


# ------------------------------------------------------------------ builders

func _pivot(n: String, parent: Node3D, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = at
	parent.add_child(p)
	joints[n] = p
	return p


func _mesh(parent: Node3D, m: Mesh, mat: String, at: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mats.get(mat)
	mi.position = at
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 36
	m.rings = 18
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 24
	m.rings = 8
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 28
	m.rings = 2
	return m


func _cone(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.012
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 20
	m.rings = 3
	return m


func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 10
	return m


func _make_materials() -> void:
	_mats["body"] = _skin(C_BODY)
	_mats["belly"] = _skin(C_BELLY)
	_mats["pink"] = _skin(C_PINK)
	_mats["snout"] = _skin(C_SNOUT)
	_mats["nosepad"] = _skin(C_NOSEPAD)
	_mats["tail"] = _skin(C_TAIL)
	_mats["patch"] = _skin(C_PATCH)
	_mats["nostril"] = _plain(C_NOSTRIL, 0.6)
	_mats["hoof"] = _plain(C_HOOF, 0.55)
	_mats["eye"] = _plain(C_EYE, 0.25)
	_mats["iris"] = _plain(C_IRIS, 0.3)
	_mats["pupil"] = _plain(C_PUPIL, 0.15)
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = Color(1, 1, 1)
	_mats["shine"] = shine
	_mats["brow"] = _plain(C_BROW, 0.7)
	_mats["pack"] = _plain(C_PACK, 0.75)
	_mats["pack_dark"] = _plain(C_PACK_DARK, 0.8)
	var brass := _plain(Color(0.86, 0.66, 0.28), 0.35)
	brass.metallic = 0.7
	_mats["brass"] = brass
	_mats["beanie"] = _knit(C_BEANIE, Vector3(28.0, 7.0, 1.0))
	_mats["beanie_cuff"] = _knit(C_BEANIE_CUFF, Vector3(40.0, 2.0, 1.0))
	_mats["hat_black"] = _plain(Color(0.07, 0.065, 0.075), 0.35)
	_mats["hat_band"] = _plain(Color(0.50, 0.08, 0.13), 0.5)


func _skin(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.62
	m.rim_enabled = true
	m.rim = 0.45
	m.rim_tint = 0.35
	return m


func _plain(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _knit(c: Color, uv_scale: Vector3) -> StandardMaterial3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1), Color(0.72, 0.72, 0.74), Color(1, 1, 1)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 32
	tex.height = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = tex
	m.uv1_scale = uv_scale
	m.roughness = 1.0
	m.rim_enabled = true
	m.rim = 0.3
	return m
