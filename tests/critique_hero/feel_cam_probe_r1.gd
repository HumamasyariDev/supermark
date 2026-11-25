extends Node
## HERO critique round 1, lens GAME FEEL AND CAMERA (read-only probe; changes nothing in the track's files).
## Instances a scene (--scene=res://..., default MoveLab), lets the real MakPlayer play a replay (--replay=<json>)
## and logs the gameplay camera every rendered frame to --cam-out=<abs jsonl>:
##   player state, grounded, interpolated position, velocity; camera position, rig yaw/pitch, distance to the chest;
##   occlusion of chest and head from the camera (layer 1 rays); screen position of the chest; whether the camera
##   sphere (r 0.12) overlaps world geometry; and, while airborne, the landing spot below Mak (in frustum, occluded,
##   screen y). Quits when the player finishes the replay (or --quit-frames=<n> rendered frames).
## Run: python tools/godot.py run res://tests/critique_hero/FeelCamProbeR1.tscn --seconds 60 -- --profile=crit-hero-feel \
##          --replay=<abs json> --cam-out=<abs jsonl> [--scene=res://scenes/worlds/w1/W1.tscn] [--replay-hold]

var _player: Node3D
var _rig: Node3D
var _cam: Camera3D
var _out: FileAccess
var _frames := 0
var _quit_frames := -1
var _shot_frames := {}
var _shot_dir := ""


func _ready() -> void:
	process_priority = 1000   # after the player's visual and the camera rig have updated this frame
	var dev := get_tree().root.get_node_or_null("Dev")
	var scene_path := "res://scenes/tests/MoveLab.tscn"
	var out_path := ""
	if dev != null:
		scene_path = str(dev.call("arg", "scene", scene_path))
		out_path = str(dev.call("arg", "cam-out", ""))
		_quit_frames = int(str(dev.call("arg", "quit-frames", "-1")))
		_shot_dir = str(dev.call("arg", "shot-dir", ""))
		var shots := str(dev.call("arg", "shots", ""))
		for s in shots.split(",", false):
			_shot_frames[int(s)] = true
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_error("[FeelCam] cannot load " + scene_path)
		get_tree().quit(2)
		return
	add_child(ps.instantiate())
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		_out = FileAccess.open(out_path, FileAccess.WRITE)


func _ray_blocked(from: Vector3, to: Vector3) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, ex)
	return not space.intersect_ray(q).is_empty()


func _cam_inside() -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.12
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, _cam.global_position)
	q.collision_mask = 1
	return not space.intersect_shape(q, 1).is_empty()


func _screen(p: Vector3) -> Array:
	var vp := get_viewport().get_visible_rect().size
	if _cam.is_position_behind(p):
		return [-1.0, -1.0]
	var s := _cam.unproject_position(p)
	return [snappedf(s.x / vp.x, 0.001), snappedf(s.y / vp.y, 0.001)]


func _process(_delta: float) -> void:
	_frames += 1
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _rig == null:
		_rig = get_tree().get_first_node_in_group("game_camera") as Node3D
		if _rig != null:
			_cam = _rig.get_node_or_null("Camera3D") as Camera3D
		return
	if _cam == null:
		return
	var pp := _player.get_global_transform_interpolated().origin
	var chest := pp + Vector3.UP * 0.6
	var head := pp + Vector3.UP * 1.1
	var cpos := _cam.global_position
	var grounded := bool(_player.get("grounded"))
	var row := {
		"rf": _frames, "pf": int(_player.get("physics_frame")), "s": str(_player.call("get_state_name")), "g": grounded,
		"p": [snappedf(pp.x, 0.001), snappedf(pp.y, 0.001), snappedf(pp.z, 0.001)],
		"vy": snappedf(float(_player.get("vy")), 0.01),
		"hs": snappedf((_player.call("get_horizontal_velocity") as Vector3).length(), 0.01),
		"pyaw": snappedf(rad_to_deg(float(_player.get("facing_yaw"))), 0.1),
		"c": [snappedf(cpos.x, 0.001), snappedf(cpos.y, 0.001), snappedf(cpos.z, 0.001)],
		"cyaw": snappedf(rad_to_deg(float(_rig.get("yaw"))), 0.01),
		"cpitch": snappedf(rad_to_deg(float(_rig.get("pitch"))), 0.01),
		"dist": snappedf(cpos.distance_to(chest), 0.001),
		"occ_chest": _ray_blocked(cpos, chest), "occ_head": _ray_blocked(cpos, head),
		"scr": _screen(chest), "inside": _cam_inside(), "fov": snappedf(_cam.fov, 0.1),
	}
	if not grounded:
		var space := _cam.get_world_3d().direct_space_state
		var ex: Array[RID] = []
		if _player is CollisionObject3D:
			ex.append((_player as CollisionObject3D).get_rid())
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 0.1, pp + Vector3.DOWN * 40.0, 1, ex))
		if not hit.is_empty():
			var lp: Vector3 = hit["position"]
			row["land"] = {"y": snappedf(lp.y, 0.01), "fr": _cam.is_position_in_frustum(lp),
				"occ": _ray_blocked(cpos, lp + Vector3.UP * 0.05), "scr": _screen(lp)}
	if _out != null:
		_out.store_line(JSON.stringify(row))
	if _shot_frames.has(_frames) and _shot_dir != "":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			DirAccess.make_dir_recursive_absolute(_shot_dir)
			img.save_png(_shot_dir.path_join("rf%05d.png" % _frames))
	if _quit_frames > 0 and _frames >= _quit_frames:
		get_tree().quit()


func _exit_tree() -> void:
	if _out != null:
		_out.flush()
		_out.close()
		_out = null
