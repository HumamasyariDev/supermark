extends Node3D
## FaceLab (Mak face fix, 2026-10-19): native close-ups of the shipped hero (Player.tscn -> mak_v2_body_v3.glb, toon look)
## with the eyelid bones forced open, mid-blink and closed, from the front, three-quarter and side, plus one shot at
## gameplay-camera distance. Test scene only.
##   python tools/godot.py run res://tests/face_fix/FaceLab.tscn --seconds 90 -- --profile=face-lab --out=C:/abs/dir --prefix=after_

const LID_CLOSED_DEG := 115.0
const DT := 1.0 / 60.0

var player: Node3D
var anim: Node
var cam: Camera3D
var skel: Skeleton3D
var _dev: Node
var _out := ""
var _prefix := ""


func _ready() -> void:
	_dev = get_tree().root.get_node_or_null("Dev")
	_build_stage()
	var ps := load("res://scenes/player/Player.tscn") as PackedScene
	player = ps.instantiate() as Node3D
	add_child(player)
	player.set_physics_process(false)
	var pc := player.get_node_or_null("MakCamera")
	if pc != null:
		pc.process_mode = Node.PROCESS_MODE_DISABLED
	anim = player.get_node("Animator")
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	_out = _arg("out")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://facelab")
	_prefix = _arg("prefix")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _arg(k: String) -> String:
	if _dev != null and _dev.has_method("arg"):
		return str(_dev.call("arg", k, ""))
	return ""


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var env_path := "res://assets/shaders/environments/env_W1.tres"
	if ResourceLoader.exists(env_path):
		we.environment = load(env_path)
	else:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.8, 0.88, 0.96)
		we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 145, 0)   # key light from Mak's front-left, like the W1 hub morning
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.72, 0.42)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var wall := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(40, 12)
	wall.mesh = wm
	wall.rotation_degrees = Vector3(-90, 0, 0)
	wall.position = Vector3(0, 6, 9)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.86, 0.9, 0.95)
	wall.material_override = wmat
	add_child(wall)


func _head() -> Vector3:
	var hb := skel.find_bone("head")
	return (skel.global_transform * skel.get_bone_global_pose(hb)).origin


func _set_lids(deg: float) -> void:
	for n in ["eyelid_l", "eyelid_r"]:
		var bi := skel.find_bone(n)
		if bi >= 0:
			var rest := skel.get_bone_rest(bi).basis.get_rotation_quaternion()
			skel.set_bone_pose_rotation(bi, rest * Quaternion(Vector3.RIGHT, deg_to_rad(deg)))


func _shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join("%s%s.png" % [_prefix, name])
	img.save_png(path)
	print("[FaceLab] saved ", path)


func _view(yaw_deg: float, dist: float, dy: float, look: Vector3, fov: float) -> void:
	# The body faces -Z (MakPlayer turns the glTF model by PI). yaw 0 = straight in front of the face.
	var dir := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	cam.fov = fov
	cam.global_position = look + dir * dist + Vector3(0, dy, 0)
	cam.look_at(look, Vector3.UP)


func _run() -> void:
	anim.set_process(false)
	player.set("state", "idle")
	player.set("velocity", Vector3.ZERO)
	player.set("grounded", true)
	for i in 40:
		anim.call("_process", DT)
	for c in player.find_children("*", "Skeleton3D", true, false):
		skel = c as Skeleton3D
		break
	if skel == null:
		print("[FaceLab] no skeleton")
		get_tree().quit()
		return
	await get_tree().process_frame
	var face := _head() + Vector3(0, 0.22, 0)
	var lids := {"open": 0.0, "mid": LID_CLOSED_DEG * 0.5, "closed": LID_CLOSED_DEG}
	var views := {"front": [0.0, 0.08], "3q": [35.0, 0.12], "side": [80.0, 0.05]}
	for lk in lids:
		for vk in views:
			_set_lids(float(lids[lk]))
			var v: Array = views[vk]
			_view(float(v[0]), 1.15, float(v[1]), face, 30.0)
			await _shot("%s-%s" % [vk, lk])
	# Snout close-up (front and from below-left), eyes open.
	_set_lids(0.0)
	_view(20.0, 0.62, -0.06, face + Vector3(0, -0.08, 0), 30.0)
	await _shot("snout-closeup")
	# Gameplay-camera distance (about 6 m, fov 55, a little above), front three-quarter so the face shows.
	for lk in ["open", "closed"]:
		_set_lids(float(lids[lk]))
		_view(30.0, 6.0, 1.6, player.global_position + Vector3(0, 0.6, 0), 55.0)
		await _shot("gameplay-3q-%s" % lk)
	get_tree().quit()
