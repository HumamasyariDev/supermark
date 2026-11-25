extends Node3D
## Enemies critique, round 1 pass C (animation and personality lens), on the impl3 build. Read-only driver.
## One Godot run covers several families (the two machine run slots are the bottleneck):
##   --crit-mode=reels : the lab's scripted state reel (_reel) per family, close tracking camera
##   --crit-mode=ai    : AI on, the lab stub player approaches, circles, flees, then a real stomp per family
## Args: --crit-families=a,b,...  --crit-view=three|side|front  --crit-log=<abs jsonl>  [--reel-defeat=stomp]
## Per-frame log rows: state, on_floor, yaw, yaw rate, velocity heading, rig scale, lowest leg/foot bone height above
## the floor (ground contact proxy), so turning, foot sink and float can be measured, not only eyeballed.
## Use: python tools/godot.py movie res://tests/critique_enemies/AnimCritiqueR1c.tscn <out.avi> --frames N --fps 30
##        --size 1280x720 -- --crit-mode=reels --crit-view=three --reel-defeat=stomp --profile=crit_enemies_r1c

const ALL := ["woolly_wolf", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]

var lab: Node3D
var cam: Camera3D
var view: String = "three"
var mode: String = "reels"
var fam: String = ""
var enemy: EnemyBase
var t: float = 0.0
var _cam_pos: Vector3
var _phase: String = "setup"
var _log_f: FileAccess
var _last_state: String = ""
var _last_yaw: float = 0.0
var _foot_bones: Array[int] = []
var _foot_skel: Skeleton3D


func _ready() -> void:
	view = Dev.arg("crit-view", "three")
	mode = Dev.arg("crit-mode", "reels")
	if Dev.has_arg("crit-log"):
		_log_f = FileAccess.open(Dev.arg("crit-log"), FileAccess.WRITE)
	lab = (load("res://scenes/enemies/EnemyLab.tscn") as PackedScene).instantiate() as Node3D
	add_child(lab)
	cam = Camera3D.new()
	cam.name = "CritCam"
	cam.fov = 42.0
	add_child(cam)
	await get_tree().process_frame
	await get_tree().process_frame
	cam.make_current()
	var fams: Array = ALL.duplicate()
	if Dev.has_arg("crit-families"):
		fams = Array(Dev.arg("crit-families").split(","))
	for f in fams:
		fam = String(f)
		print("[CritC] family ", fam, " t=", t)
		if mode == "reels":
			await _do_reel()
		else:
			await _do_ai()
	print("[CritC] done t=", t)
	if _log_f != null:
		_log_f.close()
		_log_f = null
	get_tree().quit()


func _bind(e: EnemyBase, reset_cam: bool = true) -> void:
	enemy = e
	_foot_bones.clear()
	_foot_skel = e.skeleton
	if _foot_skel != null:
		for i in _foot_skel.get_bone_count():
			var bn := _foot_skel.get_bone_name(i).to_lower()
			if bn.contains("foot") or bn.contains("toe") or bn.contains("shin") or bn.contains("calf") or bn.contains("leg") or bn.contains("ankle"):
				_foot_bones.append(i)
	if reset_cam:
		_cam_pos = _cam_want()
		cam.global_position = _cam_pos
	_last_yaw = e.rotation.y


func _do_reel() -> void:
	var done := [false]
	var runner := func() -> void:
		await lab.call("_reel", fam)
		done[0] = true
	runner.call()
	await get_tree().process_frame
	await get_tree().process_frame
	var en: Dictionary = lab.get("enemies")
	for k in en.keys():
		var e := en[k] as EnemyBase
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			_bind(e)
			break
	_phase = "reel"
	while not done[0]:
		await get_tree().process_frame


func _do_ai() -> void:
	var en: Dictionary = lab.get("enemies")
	var raw: Variant = en.get(fam)
	if raw == null or not is_instance_valid(raw):
		push_error("[CritC] no enemy " + fam)
		return
	var e := raw as EnemyBase
	if e == null:
		push_error("[CritC] no enemy " + fam)
		return
	# Freeze every other family so only this one acts in frame.
	for k in en.keys():
		if not is_instance_valid(en[k]):
			continue
		var o := en[k] as EnemyBase
		if o != e:
			o.ai_enabled = false
	e.ai_enabled = true
	_bind(e)
	var p := lab.get("player") as Node3D
	p.set("keyboard", false)
	var start := e.global_position
	var gy := 0.15
	p.global_position = Vector3(start.x, gy, start.z + 13.0)
	if p.has_method("reset_physics_interpolation"):
		p.reset_physics_interpolation()
	p.set("drive_target", p.global_position)
	_phase = "unaware"
	await _wait(2.5)
	_phase = "approach"
	p.set("drive_speed", 5.0)
	p.set("drive_target", Vector3(start.x, gy, start.z + 4.5))
	await _wait(3.2)
	_phase = "circle"
	var steps := 18
	for i in steps:
		var a := TAU * 0.66 * float(i + 1) / float(steps)
		p.set("drive_target", Vector3(start.x + sin(a) * 4.0, gy, start.z + cos(a) * 4.0))
		await _wait(0.2)
	for i in steps:
		var a := TAU * 0.66 * (1.0 - float(i + 1) / float(steps))
		p.set("drive_target", Vector3(start.x + sin(a) * 4.0, gy, start.z + cos(a) * 4.0))
		await _wait(0.2)
	_phase = "flee"
	p.set("drive_speed", 7.5)
	p.set("drive_target", Vector3(start.x, gy, start.z + 16.0))
	await _wait(2.6)
	_phase = "defeat"
	if not is_instance_valid(e):
		return
	p.set("drive_target", p.global_position)
	if e.max_hp > 1:
		if fam == "gummy_brute":
			e.set_state("recover")
		e.hit_by_player("punch", e.global_position + e.global_transform.basis.z * 1.5 + Vector3(0, 0.5, 0))
		await _wait(1.3)
		if not is_instance_valid(e):
			return
	if fam == "gummy_brute":
		e.set_state("recover")
	var above := e.global_position + Vector3(0, e.head_height + 0.6, 0)
	var ok := e.hit_by_player("stomp", above)
	print("[CritC] stomp landed=", ok, " defeated=", e.is_defeated)
	if not e.is_defeated:
		await _wait(0.6)
		if is_instance_valid(e) and not e.is_defeated:
			e.defeat("stomp", above)
	await _wait(3.0)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _cam_want() -> Vector3:
	var c := enemy.global_position if is_instance_valid(enemy) else _cam_pos
	var d := 3.2 if mode == "reels" else 5.2
	var h := 0.8
	if fam == "gummy_brute":
		d = 5.0 if mode == "reels" else 7.0
		h = 1.3
	elif fam == "gingerbread_grenadier":
		d = 3.9 if mode == "reels" else 6.0
		h = 1.05
	elif fam == "crow_bandit" and mode == "ai":
		d = 6.5
	match view:
		"side":
			return Vector3(c.x + d, c.y + h * 0.7, c.z)
		"front":
			return Vector3(c.x, c.y + h, c.z + d)
	return Vector3(c.x + d * 0.62, c.y + h, c.z + d * 0.78)


func _process(delta: float) -> void:
	t += delta
	if cam == null or not is_instance_valid(enemy):
		return
	_cam_pos = _cam_pos.lerp(_cam_want(), 1.0 - exp(-6.0 * delta))
	cam.global_position = _cam_pos
	var look := enemy.global_position + Vector3(0, 0.45 if fam != "gummy_brute" else 0.8, 0)
	cam.look_at(look, Vector3.UP)
	var st := String(enemy.state)
	if st != _last_state:
		_last_state = st
		print("[CritC] %.2f %s %s state=%s" % [t, fam, _phase, st])
	if enemy.skeleton != _foot_skel:
		# Mesh swap (the wolf's costume rip): re-read the leg bones from the new skeleton.
		var keep_yaw := _last_yaw
		_bind(enemy, false)
		_last_yaw = keep_yaw
	if _log_f != null:
		var yaw := enemy.rotation.y
		var dy := wrapf(yaw - _last_yaw, -PI, PI)
		_last_yaw = yaw
		var v := enemy.velocity
		var low := INF
		if _foot_skel != null and is_instance_valid(_foot_skel):
			for i in _foot_bones:
				var gp := _foot_skel.global_transform * _foot_skel.get_bone_global_pose(i).origin
				low = minf(low, gp.y)
		var fy := enemy.floor_y_at(enemy.global_position)
		var row := {
			"t": snappedf(t, 0.001), "fam": fam, "phase": _phase, "state": st,
			"y": snappedf(enemy.global_position.y, 0.001), "floor": enemy.is_on_floor(), "floor_y": snappedf(fy, 0.001),
			"yaw": snappedf(rad_to_deg(yaw), 0.1), "yaw_rate": snappedf(rad_to_deg(dy) / maxf(delta, 0.0001), 0.1),
			"vel_h": snappedf(Vector2(v.x, v.z).length(), 0.01),
			"vel_heading": snappedf(rad_to_deg(atan2(-v.x, -v.z)), 0.1),
			"rig_scale": [snappedf(enemy.rig.scale.x, 0.001), snappedf(enemy.rig.scale.y, 0.001)] if enemy.rig != null else [],
			"rig_y": snappedf(enemy.rig.position.y, 0.001) if enemy.rig != null else 0.0,
			"low_leg_y": snappedf(low, 0.001) if low != INF else null,
			"defeated": enemy.is_defeated,
		}
		_log_f.store_line(JSON.stringify(row))
