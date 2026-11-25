extends Node
## W2 critique round 1, lens GAME FEEL, MOVEMENT AND CAMERA (read-only probe; changes nothing in W2's files).
## Instances W2 (or --scene=...), lets the real MakPlayer play a replay (--replay=<json>) and logs, every rendered
## frame, to --cam-out=<abs jsonl>: player state, grounded, interpolated feet position, velocity, wind; gameplay
## camera position, rig yaw/pitch, distance to the chest, occlusion of chest/head from the camera (layer 1 rays),
## whether the camera sphere (r 0.12) is inside world geometry, the chest's screen position, the active camera
## zone (if any), the replay mark, and while airborne the landing spot under Mak (in frustum, occluded, screen y).
## --shots=<pf>,<pf>... saves a native PNG to --shot-dir the first rendered frame at or after each player physics
## frame (file name <label>_pf<pf>.png, label from --label). Quits at --quit-pf=<n> physics frames.
## Run: python tools/godot.py run res://tests/critique_w2/r1_feel/FeelW2Probe.tscn --seconds 60 -- \
##          --profile=crit-w2-feel --replay=<abs json> --cam-out=<abs jsonl> --shot-dir=<abs dir> --shots=120,300

var _player: Node3D
var _rig: Node3D
var _cam: Camera3D
var _out: FileAccess
var _frames := 0
var _quit_pf := -1
var _shots: Array[int] = []
var _shot_dir := ""
var _label := "probe"
var _last_mark := ""
var _audit_path := ""
var _audit_done := false
var _fix_origin := false
var _fix_done := false
var _dbg_pf := -1


func _ready() -> void:
	process_priority = 1000
	var dev := get_tree().root.get_node_or_null("Dev")
	var scene_path := "res://scenes/worlds/w2/W2.tscn"
	var out_path := ""
	if dev != null:
		scene_path = str(dev.call("arg", "scene", scene_path))
		out_path = str(dev.call("arg", "cam-out", ""))
		_quit_pf = int(str(dev.call("arg", "quit-pf", "-1")))
		_shot_dir = str(dev.call("arg", "shot-dir", ""))
		_label = str(dev.call("arg", "label", _label))
		_audit_path = str(dev.call("arg", "audit", ""))
		_fix_origin = bool(dev.call("has_arg", "fix-origin"))
		for s in str(dev.call("arg", "shots", "")).split(",", false):
			_shots.append(int(s))
	_shots.sort()
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_error("[FeelW2] cannot load " + scene_path)
		get_tree().quit(2)
		return
	add_child(ps.instantiate())
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		_out = FileAccess.open(out_path, FileAccess.WRITE)


func _excl() -> Array[RID]:
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	return ex


func _ray_blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, _excl())
	return not _cam.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _ray_hit_name(from: Vector3, to: Vector3) -> String:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, _excl())
	var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	var c: Object = hit.get("collider")
	if c is Node:
		var n := c as Node
		var par := n.get_parent()
		return str(n.name) + ("<" + str(par.name) if par != null else "")
	return "?"


func _cam_inside() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.12
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, _cam.global_position)
	q.collision_mask = 1
	return not _cam.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _screen(p: Vector3) -> Array:
	var vp := get_viewport().get_visible_rect().size
	if _cam.is_position_behind(p):
		return [-1.0, -1.0]
	var s := _cam.unproject_position(p)
	return [snappedf(s.x / vp.x, 0.001), snappedf(s.y / vp.y, 0.001)]


func _v(p: Vector3, d := 0.001) -> Array:
	return [snappedf(p.x, d), snappedf(p.y, d), snappedf(p.z, d)]


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
	var pf := int(_player.get("physics_frame"))
	var pp := _player.get_global_transform_interpolated().origin
	var chest := pp + Vector3.UP * 0.6
	var head := pp + Vector3.UP * 1.1
	var active := get_viewport().get_camera_3d()
	var cpos := _cam.global_position
	var grounded := bool(_player.get("grounded"))
	var z: Variant = _rig.get("zone")
	var inp: Variant = _player.get("inp")
	var mark := ""
	if inp != null and inp is Object and "mark" in (inp as Object):
		mark = str((inp as Object).get("mark"))
	var row := {
		"rf": _frames, "pf": pf, "s": str(_player.call("get_state_name")), "g": grounded,
		"p": _v(pp), "v": _v(_player.get("velocity") as Vector3, 0.01),
		"wind": _v(_player.get("wind_vel") as Vector3, 0.01),
		"hs": snappedf((_player.call("get_horizontal_velocity") as Vector3).length(), 0.01),
		"pyaw": snappedf(rad_to_deg(float(_player.get("facing_yaw"))), 0.1),
		"c": _v(cpos), "cyaw": snappedf(rad_to_deg(float(_rig.get("yaw"))), 0.01),
		"cpitch": snappedf(rad_to_deg(float(_rig.get("pitch"))), 0.01),
		"dist": snappedf(cpos.distance_to(chest), 0.001),
		"occ_chest": _ray_blocked(cpos, chest), "occ_head": _ray_blocked(cpos, head),
		"occ_by": _ray_hit_name(cpos, chest),
		"scr": _screen(chest), "inside": _cam_inside(), "fov": snappedf(_cam.fov, 0.1),
		"gamecam": active == _cam, "zone": (str((z as Node).name) if z is Node else ""),
		"hp": int(get_tree().root.get_node("Game").get("health")) if get_tree().root.has_node("Game") else -1,
	}
	if mark != "":
		row["mark"] = mark
	if not grounded:
		var space := _cam.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 0.1, pp + Vector3.DOWN * 60.0, 1, _excl()))
		if not hit.is_empty():
			var lp: Vector3 = hit["position"]
			row["land"] = {"y": snappedf(lp.y, 0.01), "fr": _cam.is_position_in_frustum(lp),
				"occ": _ray_blocked(cpos, lp + Vector3.UP * 0.05), "scr": _screen(lp)}
		else:
			row["land"] = {"y": null}
	if _out != null:
		_out.store_line(JSON.stringify(row))
	if _fix_origin and not _fix_done and pf >= 2:
		_fix_done = true
		_patch_origin_bodies()
	if _fix_origin and pf in [10, 30, 60] and _dbg_pf != pf:
		_dbg_pf = pf
		for nm in ["L06", "LB1", "LB2", "U02"]:
			var n := get_tree().root.find_child(nm, true, false) as Node3D
			if n:
				print("[FeelW2] pf ", pf, " ", nm, " at ", n.global_position, " inside ", n.is_inside_tree(), " proc ", n.is_physics_processing())
	if _audit_path != "" and not _audit_done and pf >= 20:
		_audit_done = true
		_audit()
	while not _shots.is_empty() and pf >= _shots[0] and _shot_dir != "":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			DirAccess.make_dir_recursive_absolute(_shot_dir)
			img.save_png(_shot_dir.path_join("%s_pf%05d.png" % [_label, _shots[0]]))
		_shots.pop_front()
	if _quit_pf > 0 and pf >= _quit_pf:
		get_tree().quit()


## TEST-ONLY runtime patch (--fix-origin), never saved: the droopy leaves L06-L08 and the Leaf Bouncer pads LB1-LB5
## are found at the world origin because W2Life caches body.position (0,0,0 for these AnimatableBody3Ds) as their
## rest position. This puts the cached rest/mean positions back to the level JSON values (and recomputes the pad swing
## axis from the JSON chain) so the intended design can be measured. It mirrors the fix proposed in the report.
func _patch_origin_bodies() -> void:
	var life := get_tree().root.find_child("W2Life", true, false)
	if life == null:
		return
	var f := FileAccess.open("res://assets/environment/w2/w2_level.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var pos := {}
	for p in data.get("platforms", []):
		var a: Array = p.get("pos", [0, 0, 0])
		pos[str(p.get("id"))] = Vector3(float(a[0]), float(a[1]), float(a[2]))
	for d in life.get("droops"):
		var nm := str((d[0] as Node).name)
		if pos.has(nm):
			d[1] = pos[nm]
	var ids := ["LB1", "LB2", "LB3", "LB4", "LB5"]
	for m in life.get("movers"):
		var nm2 := str((m[0] as Node).name)
		var i := ids.find(nm2)
		if i >= 0:
			var chain: Vector3 = pos[ids[mini(i + 1, 4)]] - pos[ids[maxi(i - 1, 0)]]
			chain.y = 0.0
			m[1] = pos[nm2]
			m[2] = Vector3(-chain.z, 0, chain.x).normalized()
	print("[FeelW2] test-only patch applied: droop and Leaf Bouncer rest positions restored from the level JSON")
	for d in life.get("droops"):
		print("[FeelW2] droop ", (d[0] as Node).name, " base ", d[1], " now ", (d[0] as Node3D).global_position)
	for m in life.get("movers"):
		print("[FeelW2] mover ", (m[0] as Node).name, " mean ", m[1], " dir ", m[2], " amp ", m[3], " now ", (m[0] as Node3D).global_position)


## Geometry audit: for every platform in the level JSON, cast a ray down through its listed top (centre, and 8
## points at 85 % of its radius) and record the collider top that is actually there (layer 1).
func _audit() -> void:
	var f := FileAccess.open("res://assets/environment/w2/w2_level.json", FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return
	var space := _cam.get_world_3d().direct_space_state
	var out := []
	for p in (data as Dictionary).get("platforms", []):
		var pos: Array = p.get("pos", [0, 0, 0])
		var c := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var rx := float(p.get("rx", p.get("r", float(p.get("sx", 1.0)) * 0.5)))
		var rz := float(p.get("rz", p.get("r", float(p.get("sz", 1.0)) * 0.5)))
		var samples := []
		var pts: Array[Vector3] = [c]
		for k in 8:
			var a := TAU * k / 8.0
			pts.append(c + Vector3(cos(a) * rx * 0.85, 0, sin(a) * rz * 0.85))
		for q in pts:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 3.0, q + Vector3.DOWN * 4.0, 1, _excl()))
			if hit.is_empty():
				samples.append(null)
			else:
				var hp: Vector3 = hit["position"]
				var col: Object = hit.get("collider")
				samples.append([snappedf(hp.y - c.y, 0.01), str((col as Node).name) if col is Node else "?"])
		out.append({"id": p.get("id"), "kind": p.get("kind"), "pos": pos, "samples": samples})
	var nodes := {}
	for nm in ["L05", "L06", "L07", "L08", "LB1", "LB2", "LB3", "LB4", "LB5", "U02", "V1", "V3"]:
		var n := get_tree().root.find_child(nm, true, false)
		if n is Node3D:
			var gp := (n as Node3D).global_position
			nodes[nm] = {"global": _v(gp), "class": n.get_class(), "parent": str(n.get_parent().name),
				"shapes": n.find_children("*", "CollisionShape3D", true, false).size()}
	out.append({"nodes": nodes})
	var w := FileAccess.open(_audit_path, FileAccess.WRITE)
	if w != null:
		w.store_string(JSON.stringify(out, " "))
		w.close()


func _exit_tree() -> void:
	if _out != null:
		_out.flush()
		_out.close()
		_out = null
