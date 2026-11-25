extends Node3D
## Look-dev lineup for the TOPUP_CHARS batch (meshes workstream). Not gameplay.
## Every model is wrapped in a Visual node rotated 180 degrees about Y (glTF faces +Z, the game faces -Z),
## exactly as TECH_CONTRACT asks, and the cameras look at the faces from -Z.
## Cameras: Cam_Lineup (all small and mid characters with Mr. Mak for scale), Cam_Close (the W1 pigs + Jack),
## Cam_Big (Sleeping Giant and the wolf-mask scarecrow), Cam_Foreman (both Foreman meshes + Sergeant Snap).
## A few bones are posed in-engine (Skeleton3D) to prove the skins deform in Godot 4.7.

const C := "res://assets/characters/"

func _ready() -> void:
	_stage()
	var row := [
		["pip_v2/pip_v2.glb", -6.6, 0.0], ["hazel/hazel.glb", -5.6, 0.0], ["bertram/bertram.glb", -4.6, 0.0],
		["mak/mak.glb", -3.5, 0.0], ["jack/jack.glb", -2.2, 0.0], ["real_sheep/real_sheep.glb", -0.7, -35.0],
		["sergeant_snap/sergeant_snap.glb", 0.9, 0.0], ["foreman/foreman.glb", 2.8, 0.0],
		["foreman/foreman_underwear.glb", 5.0, 0.0], ["daisy_cow/daisy_cow.glb", 7.3, -40.0],
	]
	var made := {}
	for r in row:
		made[r[0]] = _spawn(C + r[0], Vector3(r[1], 0, 0), r[2])
	made["giant"] = _spawn(C + "sleeping_giant/sleeping_giant.glb", Vector3(-4.0, 0, 9.0), 0.0)
	made["scarecrow"] = _spawn(C + "wolf_scarecrow/wolf_scarecrow.glb", Vector3(4.5, 0, 9.0), 0.0)
	await get_tree().process_frame
	# in-engine pose checks (model-space axes of the glTF file: +X = character's left, +Z = front)
	var hz := _skel(made["hazel/hazel.glb"])
	_rot_model(hz, "arm_r", Vector3(0, 0, 1), -75.0)
	_rot_model(hz, "head", Vector3(0, 0, 1), 10.0)
	var jk := _skel(made["jack/jack.glb"])
	_rot_model(jk, "arm_l", Vector3(0, 0, 1), 60.0)
	_rot_model(jk, "forearm_l", Vector3(0, 0, 1), 20.0)
	var sn := _skel(made["sergeant_snap/sergeant_snap.glb"])
	_rot_model(sn, "arm_r", Vector3(1, 0, 0), -50.0)
	_attach(sn, "hand_r", C + "sergeant_snap/snap_sabre.glb", Vector3(-40, 0, 0))
	_attach(sn, "hips", C + "sergeant_snap/snap_drum.glb", Vector3(15, 0, 0), Vector3(0.3, -0.05, 0.25))
	var mace := (load(C + "sergeant_snap/snap_mace.glb") as PackedScene).instantiate() as Node3D
	add_child(mace)
	mace.position = Vector3(1.75, 0, 0.3)
	var fm := _skel(made["foreman/foreman.glb"])
	_rot_model(fm, "head", Vector3(1, 0, 0), -10.0)
	var fu := _skel(made["foreman/foreman_underwear.glb"])
	_rot_model(fu, "arm_l", Vector3(0, 0, 1), 70.0)
	_rot_model(fu, "arm_r", Vector3(0, 0, 1), -70.0)
	var gi := _skel(made["giant"])
	_rot_model(gi, "jaw", Vector3(1, 0, 0), 12.0)
	var sc := _skel(made["scarecrow"])
	_rot_model(sc, "can_l", Vector3(0, 0, 1), 15.0)
	_rot_model(sc, "jaw", Vector3(1, 0, 0), 18.0)
	_anim = {"giant": gi, "scarecrow": sc, "hazel": hz, "sheep": _skel(made["real_sheep/real_sheep.glb"]),
		"cow": _skel(made["daisy_cow/daisy_cow.glb"]), "pip": _skel(made["pip_v2/pip_v2.glb"]),
		"bertram": _skel(made["bertram/bertram.glb"])}
	for k in _anim:
		var s: Skeleton3D = _anim[k]
		_rest[k] = {}
		for i in s.get_bone_count():
			_rest[k][i] = s.get_bone_pose_rotation(i)

var _anim := {}
var _rest := {}
var _t := 0.0

## Procedural motion check (not authored clips): snore cycle, nod, tail flick, wave, sway, graze.
func _process(delta: float) -> void:
	if _anim.is_empty():
		return
	_t += delta
	var snore := (sin(_t * TAU / 3.0) + 1.0) * 0.5
	_pose("giant", "jaw", Vector3.RIGHT, 4.0 + 14.0 * snore)
	_pose("giant", "head", Vector3.RIGHT, -5.0 * snore)
	_pose("giant", "chest", Vector3.RIGHT, -2.5 * snore)
	_pose("giant", "cap_tip", Vector3.FORWARD, 12.0 * sin(_t * 2.2))
	_pose("scarecrow", "body", Vector3.FORWARD, 3.0 * sin(_t * 1.7))
	_pose("scarecrow", "jaw", Vector3.RIGHT, 18.0 * max(0.0, sin(_t * 9.0)))
	_pose("scarecrow", "can_l", Vector3.FORWARD, 18.0 * sin(_t * 3.1))
	_pose("scarecrow", "can_r", Vector3.FORWARD, 18.0 * sin(_t * 3.1 + 1.3))
	_pose("hazel", "arm_r", Vector3.FORWARD, -75.0 + 20.0 * sin(_t * 8.0))
	_pose("pip", "forearm_l", Vector3.FORWARD, 20.0 * sin(_t * 7.0))
	_pose("pip", "forearm_r", Vector3.FORWARD, -20.0 * sin(_t * 7.0))
	_pose("bertram", "head", Vector3.UP, 25.0 * sin(_t * 1.3))
	_pose("sheep", "head", Vector3.RIGHT, 30.0 * (0.5 + 0.5 * sin(_t * 1.6)))
	_pose("cow", "tail", Vector3.FORWARD, 30.0 * sin(_t * 4.0))
	_pose("cow", "tail_2", Vector3.FORWARD, 25.0 * sin(_t * 4.0 - 0.8))
	_pose("cow", "head", Vector3.UP, 20.0 * sin(_t * 0.9))

## Rotate a bone from its rest by an angle about a model-space axis (parents posed first).
func _pose(k: String, bone: String, axis: Vector3, deg: float) -> void:
	var s: Skeleton3D = _anim[k]
	var i := s.find_bone(bone)
	if i < 0:
		return
	s.set_bone_pose_rotation(i, _rest[k][i])
	_rot_model(s, bone, axis, deg)

func _spawn(path: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var visual := Node3D.new()
	visual.name = path.get_file().get_basename() + "_Visual"
	add_child(visual)
	visual.position = pos
	visual.rotation_degrees = Vector3(0, 180.0 + yaw_deg, 0)
	var n := (load(path) as PackedScene).instantiate() as Node3D
	visual.add_child(n)
	return n

func _skel(n: Node3D) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return s[0] as Skeleton3D if s.size() > 0 else null

func _attach(skel: Skeleton3D, bone: String, path: String, global_euler_deg: Vector3, model_offset := Vector3.ZERO) -> void:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	var p := (load(path) as PackedScene).instantiate() as Node3D
	ba.add_child(p)
	await get_tree().process_frame
	var want := Basis.from_euler(global_euler_deg * PI / 180.0)
	p.global_basis = (skel.global_basis * want).orthonormalized()
	if model_offset != Vector3.ZERO:
		p.global_position = ba.global_position + skel.global_basis * model_offset

## Rotate a bone about a model-space axis through its own origin.
func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	if skel == null:
		return
	var i := skel.find_bone(bone)
	if i < 0:
		push_warning("bone missing: " + bone)
		return
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

func _stage() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.62, 0.9)
	sm.sky_horizon_color = Color(0.86, 0.88, 0.92)
	sm.ground_horizon_color = Color(0.8, 0.76, 0.7)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 155, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, -20, 0)
	rim.light_color = Color(0.8, 0.88, 1.0)
	rim.light_energy = 0.6
	add_child(rim)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.72, 0.42)
	fm.roughness = 0.95
	pm.material = fm
	floor.mesh = pm
	add_child(floor)
	_cam("Cam_Lineup", Vector3(0.3, 2.2, -13.5), Vector3(0.3, 0.9, 0), 42.0, true)
	_cam("Cam_Close", Vector3(-4.4, 1.3, -5.2), Vector3(-4.4, 0.6, 0), 40.0, false)
	_cam("Cam_Foreman", Vector3(2.9, 1.6, -6.0), Vector3(2.9, 1.0, 0), 42.0, false)
	_cam("Cam_Big", Vector3(0.3, 4.8, -9.0), Vector3(0.3, 2.8, 9.0), 55.0, false)

func _cam(n: String, pos: Vector3, target: Vector3, fov: float, cur: bool) -> void:
	var cam := Camera3D.new()
	cam.name = n
	cam.fov = fov
	add_child(cam)
	cam.look_at_from_position(pos, target)
	cam.current = cur
