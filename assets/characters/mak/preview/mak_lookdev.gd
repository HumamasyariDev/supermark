extends Node3D
## Look-dev stage for the Mr. Mak kit (meshes workstream). Not gameplay.
## Left: mak.glb (default outfit). Centre: mak_body.glb + top hat + backpack attached from attach.json,
## with a test pose. Right: mak.glb from behind.

const DIR := "res://assets/characters/mak/"

func _ready() -> void:
	var attach: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "attach.json"))
	_stage()
	var a := _spawn(DIR + "mak.glb", Vector3(-1.15, 0, 0), 28.0)
	var b := _spawn(DIR + "mak_body.glb", Vector3(0, 0, 0.15), -12.0)
	var skel := b.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_attach(skel, "head_top", DIR + "mak_tophat.glb", attach["mak_tophat"])
	_attach(skel, "backpack", DIR + "mak_backpack.glb", attach["mak_backpack"])
	_rot_model(skel, "arm_l", Vector3(0, 0, 1), 62.0)
	_rot_model(skel, "arm_r", Vector3(0, 0, 1), -20.0)
	_rot_model(skel, "head", Vector3(0, 1, 0), 14.0)
	_rot_model(skel, "thigh_l", Vector3(1, 0, 0), -25.0)
	_spawn(DIR + "mak.glb", Vector3(1.15, 0, 0), 205.0)

func _spawn(path: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw_deg, 0)
	return n

func _attach(skel: Skeleton3D, bone: String, path: String, a: Dictionary) -> void:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	var p := (load(path) as PackedScene).instantiate() as Node3D
	ba.add_child(p)
	var o: Array = a["offset"]
	p.position = Vector3(o[0], o[1], o[2])
	var r: Array = a.get("rotation_deg_xyz", a.get("rotation_deg", [0, 0, 0]))
	p.rotation_degrees = Vector3(r[0], r[1], r[2])

## Rotate a bone about a model-space axis through its own origin.
func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var i := skel.find_bone(bone)
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
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 200, 0)
	rim.light_color = Color(0.8, 0.88, 1.0)
	rim.light_energy = 0.6
	add_child(rim)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.72, 0.42)
	fm.roughness = 0.95
	pm.material = fm
	floor.mesh = pm
	add_child(floor)
	var cam := Camera3D.new()
	cam.fov = 34.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.95, 4.3), Vector3(0, 0.55, 0))
	cam.current = true
