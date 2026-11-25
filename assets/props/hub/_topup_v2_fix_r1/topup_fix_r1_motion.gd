extends Node3D
## TOPUP_HUB fix round 1 (night 01): motion look-dev for Movie Maker. Four 3 s shots: the clock dial with the hands turning (no ghost
## hands), the pendulum at the 4 degree swing and 1.6 s period, the chandelier from the floor with its sway, Mr. Mak v2 with the ear
## bones wiggling under the beanie, and the golden truffle spinning. Not gameplay; no level uses it.
## Record: python tools/godot.py movie res://assets/props/hub/_topup_v2_fix_r1/TopupFixR1Motion.tscn <out.avi> --frames 900 -- --profile=topup_hub_fix_r1
## or one shot at a time (Movie Maker crashed with an allocation failure after about 146 frames tonight): -- --shot=<0..4>

const HUB := "res://assets/props/hub/"
const PICK := "res://assets/props/pickups/"
const MAK := "res://assets/characters/mak/"
const SHOT_LEN := 3.0

var _t := 0.0
var _cams: Array[Camera3D] = []
var _hh: Node3D
var _hm: Node3D
var _pend: Node3D
var _sway: Node3D
var _truffle: Node3D
var _sk: Skeleton3D
var _ear_rest := {}
var _shot := -1

func _ready() -> void:
	_stage()
	var clk := _spawn(self, HUB + "grandfather_clock_v2/grandfather_clock_v2.glb", Vector3(0, 0, 0), 0.0)
	_hh = clk.find_child("hand_hour", true, false) as Node3D
	_hm = clk.find_child("hand_minute", true, false) as Node3D
	_pend = clk.find_child("pendulum", true, false) as Node3D
	_add_cam("Cam_Dial", Vector3(0.12, 1.95, 1.05), Vector3(0.0, 1.9, 0.0), 30.0)
	_add_cam("Cam_Pendulum", Vector3(0.0, 1.25, 1.9), Vector3(0.0, 1.0, 0.0), 38.0)
	var ch := _spawn(self, HUB + "brass_chandelier_v2/brass_chandelier_v2.glb", Vector3(10, 3.0, 0), 0.0)
	ch.scale = Vector3.ONE * 1.7
	_sway = ch.find_child("sway_pivot", true, false) as Node3D
	_add_cam("Cam_Chandelier", Vector3(14.5, 1.2, 3.5), Vector3(10.0, 4.6, 0.0), 58.0)
	var mak := _spawn(self, MAK + "mak_v2.glb", Vector3(20, 0, 0), 0.0)
	_sk = mak.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for b in ["ear_l", "ear_r"]:
		var i := _sk.find_bone(b)
		if i >= 0:
			_ear_rest[b] = _sk.get_bone_pose_rotation(i)
	_add_cam("Cam_Mak", Vector3(20.9, 1.25, 1.7), Vector3(20.0, 1.0, 0.0), 30.0)
	_truffle = _spawn(self, PICK + "golden_truffle_v2/golden_truffle_v2.glb", Vector3(30, 0.3, 0), 0.0)
	_add_cam("Cam_Truffle", Vector3(30.0, 0.75, 1.7), Vector3(30.0, 0.55, 0.0), 35.0)
	_shot = int(Dev.arg("shot", "-1"))
	if _shot >= 0:
		_t = _shot * SHOT_LEN
	_cams[maxi(_shot, 0)].make_current()

func _add_cam(n: String, pos: Vector3, look: Vector3, fov: float) -> void:
	var c := Camera3D.new()
	c.name = n
	add_child(c)
	c.fov = fov
	c.look_at_from_position(pos, look, Vector3.UP)
	_cams.append(c)

func _process(delta: float) -> void:
	_t += delta
	var k := mini(int(_t / SHOT_LEN), _cams.size() - 1) if _shot < 0 else _shot
	if not _cams[k].current:
		_cams[k].make_current()
	_hm.rotation.z = -_t * 1.2
	_hh.rotation.z = -_t * 0.1
	_pend.rotation.z = deg_to_rad(4.0) * sin(_t * TAU / 1.6)
	_sway.rotation.z = deg_to_rad(1.5) * sin(_t * TAU / 6.0)
	_truffle.rotation.y = _t * 1.6
	_truffle.position.y = 0.3 + 0.06 * sin(_t * TAU / 1.4)
	# ear wiggle through the animator's range: forward 45, back 25, spread
	var a := sin(_t * TAU / 1.5)
	for b in _ear_rest.keys():
		var i := _sk.find_bone(b)
		var q: Quaternion = _ear_rest[b]
		var sgn := 1.0 if b == "ear_l" else -1.0
		var rx := deg_to_rad(35.0 * a + 10.0)
		var rz := deg_to_rad(15.0 * sgn * cos(_t * TAU / 1.5))
		_sk.set_bone_pose_rotation(i, q * Quaternion(Vector3.RIGHT, rx) * Quaternion(Vector3.BACK, rz))

func _spawn(parent: Node, path: String, pos: Vector3, yaw: float) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	return n

func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var i := skel.find_bone(bone)
	if i < 0:
		push_warning("no bone " + bone)
		return
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

func _stage() -> void:
	var we := WorldEnvironment.new()
	we.environment = load("res://assets/shaders/environments/env_HUB.tres") as Environment
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.76, 0.48)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, 35, 0)
	add_child(sun)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.36, 0.23, 0.13)
	floor_mat.roughness = 0.7
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 40)
	f.mesh = pm
	f.material_override = floor_mat
	f.position = Vector3(50, 0, 0)
	add_child(f)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-25, 200, 0)
	add_child(fill)
