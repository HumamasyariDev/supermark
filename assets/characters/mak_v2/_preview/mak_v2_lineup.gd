extends Node3D
## Look-dev lineup for the hero v2 kit (hero v2 mesh/rig stage). Not used by gameplay.
## Row: top hat front, top hat 3/4, beanie front, beanie 3/4, top hat 3/4 blinking with arms up (rig check).

const BODY := preload("res://assets/characters/mak_v2/mak_v2_body.glb")
const TOPHAT := preload("res://assets/characters/mak_v2/mak_v2_tophat.glb")
const BEANIE := preload("res://assets/characters/mak_v2/mak_v2_beanie.glb")
const PACK := preload("res://assets/characters/mak_v2/mak_v2_backpack.glb")

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.87, 0.89)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.82, 0.84, 0.9)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 8)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.8, 0.8, 0.82); fm.roughness = 1.0
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var setups := [[TOPHAT, 0.0, false], [TOPHAT, 35.0, false], [BEANIE, 0.0, false], [BEANIE, 35.0, false], [TOPHAT, -30.0, true]]
	for i in setups.size():
		var s: Array = setups[i]
		var mak := _make(s[0], s[2])
		mak.position = Vector3((i - 2) * 1.12, 0, 0)
		mak.rotation_degrees.y = s[1]
		add_child(mak)
	var cam := Camera3D.new()
	cam.name = "LineupCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.9
	cam.position = Vector3(0, 0.95, 6.0)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	add_child(cam)
	cam.make_current()

func _make(hat_scene: PackedScene, pose: bool) -> Node3D:
	var root: Node3D = BODY.instantiate()
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var head_top := BoneAttachment3D.new(); head_top.bone_name = "head_top"; skel.add_child(head_top)
	head_top.add_child(hat_scene.instantiate())
	var pack_att := BoneAttachment3D.new(); pack_att.bone_name = "backpack_socket"; skel.add_child(pack_att)
	pack_att.add_child(PACK.instantiate())
	if pose:
		for lid in ["eyelid_l", "eyelid_r"]:
			var b := skel.find_bone(lid)
			skel.set_bone_pose_rotation(b, Quaternion(Vector3.RIGHT, deg_to_rad(115.0)))
		var al := skel.find_bone("arm_l"); var ar := skel.find_bone("arm_r")
		skel.set_bone_pose_rotation(al, skel.get_bone_rest(al).basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, deg_to_rad(-70)))
		skel.set_bone_pose_rotation(ar, skel.get_bone_rest(ar).basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, deg_to_rad(70)))
	return root
