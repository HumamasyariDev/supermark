extends Node3D
## CoverShot (marketing stills): loads a world as the current scene, freezes the real Mr. Mak in a PoseLab preset at a spot
## in front of a camera and saves native captures with every overlay hidden. Lives in tests/, which the export excludes.
##
##   python tools/godot.py capture res://scenes/tests/CoverShot.tscn C:/abs/unused.png --wait 999999 --size 1920x1080 \
##       -- --profile=cover --spec=C:/abs/spec.json
##
## spec.json: {"world": "res://scenes/worlds/w1/W1.tscn", "out": "C:/abs/dir", "settle": 120,
##   "shots": [{"name": "a", "cam": "StoryCam_D" or {"pos": [x, y, z], "look": [x, y, z]}, "fov": 50,
##              "mak": [right, up, forward] in camera space (m) or "mak_at": [x, y, z],
##              "ground": 1.6 (optional: Mak this high above the ground under him),
##              "turn": 35 (degrees from facing the camera), "pose": "double_jump@0.2"}]}

const PoseLab := preload("res://scenes/tests/pose_lab.gd")
const DT := 1.0 / 60.0

var player: Node3D
var anim: Node
var cam: Camera3D
var spec: Dictionary = {}


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	spec = JSON.parse_string(FileAccess.get_file_as_string(str(dev.call("arg", "spec", "")))) as Dictionary
	if not has_meta("runner"):
		# The world must be the current scene (WorldRoot spawns Mak, RetroLook follows it), so a runner outlives this scene.
		var r := Node3D.new()
		r.set_meta("runner", true)
		r.set_script(get_script())
		get_tree().root.add_child.call_deferred(r)
		get_tree().change_scene_to_file.call_deferred(str(spec["world"]))
		return
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _frames(int(spec.get("settle", 120)))
	var world := get_tree().current_scene
	player = world.get("player") as Node3D
	player.set_physics_process(false)
	var pc := player.get_node_or_null("MakCamera")
	if pc != null:
		pc.process_mode = Node.PROCESS_MODE_DISABLED
	anim = player.get_node("Animator")
	anim.set_process(false)
	cam = Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	var out := str(spec["out"])
	DirAccess.make_dir_recursive_absolute(out)
	for shot in spec["shots"]:
		_hide_overlays()
		_place(shot as Dictionary)
		await _frames(int(shot.get("frames", 4)))
		await RenderingServer.frame_post_draw
		var path := out.path_join(str(shot["name"]) + ".png")
		get_viewport().get_texture().get_image().save_png(path)
		print("[CoverShot] saved ", path, " mak at ", player.global_position)
	get_tree().quit()


func _hide_overlays() -> void:
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for lb in get_tree().root.find_children("*", "Label3D", true, false):
		(lb as Node3D).visible = false


func _v(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _place(shot: Dictionary) -> void:
	var c: Variant = shot["cam"]
	if c is String:
		var sc := get_tree().current_scene.find_child(str(c), true, false) as Camera3D
		cam.global_transform = sc.global_transform
		cam.fov = sc.fov
	else:
		cam.global_position = _v(c["pos"])
		cam.look_at(_v(c["look"]), Vector3.UP)
	if shot.has("fov"):
		cam.fov = float(shot["fov"])
	var p: Vector3
	if shot.has("mak_at"):
		p = _v(shot["mak_at"])
	else:
		var rel := _v(shot.get("mak", [0.0, 0.0, 5.0]))
		p = cam.global_transform * Vector3(rel.x, rel.y, -rel.z)
	if shot.has("ground"):
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0)
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			p.y = (hit["position"] as Vector3).y + float(shot["ground"])
	player.global_position = p
	var d := cam.global_position - p
	var yaw := atan2(-d.x, -d.z) + deg_to_rad(float(shot.get("turn", 0.0)))
	player.set("facing_yaw", yaw)
	player.rotation = Vector3(0.0, yaw, 0.0)
	_pose(str(shot.get("pose", "double_jump")))


func _apply_preset(cfg: Dictionary, st_name: String, step_field: String) -> void:
	player.set("state", str(cfg.get(st_name, "idle")))
	var sp := float(cfg.get("speed", 0.0))
	var yaw := player.rotation.y
	player.set("velocity", Vector3(-sin(yaw) * sp, float(cfg.get("vy", 0.0)), -cos(yaw) * sp))
	player.set("vy", float(cfg.get("vy", 0.0)))
	player.set("forward_speed", sp)
	player.set("grounded", not bool(cfg.get("air", false)))
	player.set("combo_step", int(cfg.get(step_field, 1)))
	player.set("pole_climb_travel", float(cfg.get("travel", 0.0)))
	player.set("braking", false)


func _pose(spec_str: String) -> void:
	var name := spec_str.get_slice("@", 0)
	var cfg: Dictionary = (PoseLab.PRESETS.get(name, {"s": name, "t": 0.5}) as Dictionary).duplicate()
	if spec_str.contains("@"):
		cfg["t"] = float(spec_str.get_slice("@", 1))
	var pre_cfg := cfg.duplicate()
	pre_cfg["pre_s"] = str(cfg.get("pre", "idle"))
	_apply_preset(pre_cfg, "pre_s", "pre_step")
	for i in 30:
		anim.call("_process", DT)
	_apply_preset(cfg, "s", "step")
	for i in int(round(float(cfg.get("t", 0.5)) / DT)):
		anim.call("_process", DT)
