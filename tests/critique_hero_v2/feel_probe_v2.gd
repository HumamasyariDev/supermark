extends Node
## HERO V2 critique round 1, lens GAME FEEL AND CAMERA (read-only probe; changes nothing in other tracks' files).
## Extends the hero r1 probe (tests/critique_hero/feel_cam_probe_r1.gd) with the hero's VISUAL: per rendered frame it logs the
## camera, the controller state and the world positions of key skeleton bones (hips, head, head_top, hat top, feet, hands,
## ear tips), their screen positions, and the on-screen height of the whole hero (pixels and fraction of the viewport).
## Arguments: --scene=res://... (default MoveLab), --cam-out=<abs jsonl>, --shots=rf1,rf2,... --shot-dir=<abs dir>,
## --quit-frames=<n>. The player's own --replay / --trace / --hat / --night-hero arguments pass through.

var _player: Node3D
var _rig: Node3D
var _cam: Camera3D
var _skel: Skeleton3D
var _out: FileAccess
var _frames := 0
var _quit_frames := -1
var _shot_frames := {}
var _shot_dir := ""
var _bones := {}
var _body_h := 0.0
var _shot_pf := {}
const BONES := ["hips", "head", "head_top", "foot_l", "foot_r", "hand_l", "hand_r", "ear_l_2", "ear_r_2", "chest"]


func _ready() -> void:
	process_priority = 1000
	var dev := get_tree().root.get_node_or_null("Dev")
	var scene_path := "res://scenes/tests/MoveLab.tscn"
	var out_path := ""
	if dev != null:
		scene_path = str(dev.call("arg", "scene", scene_path))
		out_path = str(dev.call("arg", "cam-out", ""))
		_quit_frames = int(str(dev.call("arg", "quit-frames", "-1")))
		_shot_dir = str(dev.call("arg", "shot-dir", ""))
		for s in str(dev.call("arg", "shots", "")).split(",", false):
			_shot_frames[int(s)] = true
		for s in str(dev.call("arg", "shots-pf", "")).split(",", false):
			_shot_pf[int(s)] = true
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_error("[FeelV2] cannot load " + scene_path)
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


func _scr(p: Vector3) -> Array:
	var vp := get_viewport().get_visible_rect().size
	if _cam.is_position_behind(p):
		return [-1.0, -1.0]
	var s := _cam.unproject_position(p)
	return [snappedf(s.x / vp.x, 0.0001), snappedf(s.y / vp.y, 0.0001)]


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


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
	if _skel == null:
		var found := _player.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			_skel = found[0] as Skeleton3D
		if _skel != null:
			for b in BONES:
				_bones[b] = _skel.find_bone(b)
	var pp := _player.get_global_transform_interpolated().origin
	var cpos := _cam.global_position
	var grounded := bool(_player.get("grounded"))
	var row := {
		"rf": _frames, "pf": int(_player.get("physics_frame")), "s": str(_player.call("get_state_name")), "g": grounded,
		"p": _v(pp), "vy": snappedf(float(_player.get("vy")), 0.01),
		"hs": snappedf((_player.call("get_horizontal_velocity") as Vector3).length(), 0.01),
		"pyaw": snappedf(rad_to_deg(float(_player.get("facing_yaw"))), 0.1),
		"c": _v(cpos), "cyaw": snappedf(rad_to_deg(float(_rig.get("yaw"))), 0.01),
		"cpitch": snappedf(rad_to_deg(float(_rig.get("pitch"))), 0.01),
		"dist": snappedf(cpos.distance_to(pp + Vector3.UP * 0.6), 0.001),
		"occ_chest": _ray_blocked(cpos, pp + Vector3.UP * 0.6), "occ_head": _ray_blocked(cpos, pp + Vector3.UP * 1.0),
		"scr": _scr(pp + Vector3.UP * 0.6),
	}
	if _skel != null:
		var sx := _skel.global_transform
		var bw := {}
		var ys: Array[float] = []
		var xs: Array[float] = []
		for b in _bones:
			var i := int(_bones[b])
			if i < 0:
				continue
			var w := sx * _skel.get_bone_global_pose(i).origin
			bw[b] = _v(w - pp)
			var s := _scr(w)
			if s[0] >= 0.0:
				xs.append(s[0]); ys.append(s[1])
		_body_h = (ys.max() - ys.min()) if ys.size() > 2 else 0.0
		# The hat top: 0.24 m above head_top along the head_top bone's up axis (top hat height from the GLB).
		if int(_bones.get("head_top", -1)) >= 0:
			var ht := sx * _skel.get_bone_global_pose(int(_bones["head_top"]))
			var top := ht.origin + ht.basis.y.normalized() * 0.24
			bw["hat_top"] = _v(top - pp)
			var s2 := _scr(top)
			if s2[0] >= 0.0:
				xs.append(s2[0]); ys.append(s2[1])
		row["b"] = bw
		if ys.size() > 2:
			row["h_body"] = snappedf(_body_h, 0.0001)
			row["h_scr"] = snappedf(ys.max() - ys.min(), 0.0001)
			row["w_scr"] = snappedf(xs.max() - xs.min(), 0.0001)
			row["vp"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	if not grounded:
		var space := _cam.get_world_3d().direct_space_state
		var ex: Array[RID] = []
		if _player is CollisionObject3D:
			ex.append((_player as CollisionObject3D).get_rid())
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 0.1, pp + Vector3.DOWN * 40.0, 1, ex))
		if not hit.is_empty():
			var lp: Vector3 = hit["position"]
			row["land"] = {"y": snappedf(lp.y, 0.01), "fr": _cam.is_position_in_frustum(lp),
				"occ": _ray_blocked(cpos, lp + Vector3.UP * 0.05), "scr": _scr(lp)}
	if _out != null:
		_out.store_line(JSON.stringify(row))
	var pfn := int(_player.get("physics_frame"))
	var want := _shot_frames.has(_frames) or (_shot_pf.has(pfn) and not _shot_pf[pfn] is String)
	if want and _shot_pf.has(pfn):
		_shot_pf[pfn] = "done"
	if want and _shot_dir != "":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			DirAccess.make_dir_recursive_absolute(_shot_dir)
			img.save_png(_shot_dir.path_join(("pf%05d.png" % pfn) if _shot_pf.has(pfn) else ("rf%05d.png" % _frames)))
	if _quit_frames > 0 and _frames >= _quit_frames:
		get_tree().quit()


func _exit_tree() -> void:
	if _out != null:
		_out.flush()
		_out.close()
		_out = null
