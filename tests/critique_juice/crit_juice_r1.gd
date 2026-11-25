extends Node
## Critique JUICE round 1 (game-feel lens). Read only towards every track.
## Samples, every rendered frame: Engine.time_scale (hitstop), the gameplay camera shake state (mak_camera), Mak's
## squash spring (MakAnimator._sq), FOV kick and Juice.stats; logs every Juice.fired event and every JuiceSfx play.
## Modes:
##   --mode=lab   instances MoveLab and lets the real player run --replay=<json> (the hero showcase moveset)
##   --mode=world drives the real worlds (Router.enter_world) with scripted input: enemies, crates, acorns, checkpoints
## Output: --out=<abs dir> gets <tag>_frames.jsonl, <tag>_events.jsonl, <tag>_sfx.json, <tag>_summary.json.
##   python tools/godot.py movie res://tests/critique_juice/CritJuiceR1.tscn <avi> --frames 4400 --size 960x540 --
##       --profile=crit_juice_r1 --mode=lab --replay=<abs>/game/tests/replays/showcase_moveset.json --replay-hold --out=<abs>

var mode := "lab"
var out_dir := ""
var tag := "lab"
var _frames_f: FileAccess
var _events_f: FileAccess
var _frame := 0
var _player: Node
var _cam_rig: Node
var _sfx: Node
var _done := false
var _runner: Node
var _end_frame := -1
var _hold_after := 0
var notes: Array = []
var results: Array = []
var _t0 := 0


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.split("=", true, 1)[1]
	return d


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	_t0 = Time.get_ticks_msec()
	mode = _arg("mode", "lab")
	if mode == "world" and not has_meta("runner"):
		# Bootstrap: the runner lives under /root so it survives Router scene changes.
		var r := Node.new()
		r.name = "CritJuiceRunner"
		r.set_meta("runner", true)
		r.set_script(get_script())
		get_tree().root.add_child.call_deferred(r)
		set_process(false)
		return
	out_dir = _arg("out", OS.get_user_data_dir() + "/crit_juice")
	tag = _arg("tag", mode)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_frames_f = FileAccess.open(out_dir + "/" + tag + "_frames.jsonl", FileAccess.WRITE)
	_events_f = FileAccess.open(out_dir + "/" + tag + "_events.jsonl", FileAccess.WRITE)
	var j := get_node_or_null("/root/Juice")
	if j != null:
		j.connect("fired", _on_fired)
		_sfx = j.get_node_or_null("JuiceSfx")
		if _sfx != null:
			_sfx.set("log_plays", true)
	if mode == "scene":
		# Any scene as a child (for example the boss rooftop with --bosstest): sampling only.
		add_child((load(_arg("scene", "res://scenes/boss/WolfRooftop.tscn")) as PackedScene).instantiate())
	elif mode == "lab":
		var lab := (load("res://scenes/tests/MoveLab.tscn") as PackedScene).instantiate()
		add_child(lab)
		var rp := _arg("replay", "")
		if rp != "":
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(rp))
			if d is Dictionary:
				_end_frame = int((d as Dictionary).get("end_frame", -1))
	else:
		_world_script.call_deferred()


func _on_fired(event_name: String, position: Vector3, params: Dictionary) -> void:
	var p := {}
	for k in params.keys():
		var v: Variant = params[k]
		if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
			p[k] = "<freed>"
		elif v is Node:
			p[k] = "<%s>" % (v as Node).name if is_instance_valid(v) else "<freed>"
		elif v is Vector3:
			p[k] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
		elif v is float:
			p[k] = snappedf(v, 0.01)
		elif v is int or v is bool or v is String:
			p[k] = v
		else:
			p[k] = str(v)
	var cam := get_viewport().get_camera_3d()
	var dist := -1.0
	if cam != null and position != Vector3.INF:
		dist = cam.global_position.distance_to(position)
	var row := {"f": _frame, "drawn": Engine.get_frames_drawn(), "ms": Time.get_ticks_msec(), "name": event_name,
		"params": p, "cam_dist": snappedf(dist, 0.01), "pstate": _pstate(), "ts": Engine.time_scale}
	if position != Vector3.INF:
		row["pos"] = [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)]
	if _events_f != null:
		_events_f.store_line(JSON.stringify(row))


func _pstate() -> String:
	if _player != null and is_instance_valid(_player):
		return str(_player.get("state"))
	return ""


func _process(_delta: float) -> void:
	_frame += 1
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _cam_rig == null or not is_instance_valid(_cam_rig):
		_cam_rig = get_tree().get_first_node_in_group("game_camera")
	var row := {"f": _frame, "drawn": Engine.get_frames_drawn(), "ms": Time.get_ticks_msec(), "ts": snappedf(Engine.time_scale, 0.001)}
	if _cam_rig != null:
		row["sh_amp"] = snappedf(float(_cam_rig.get("_shake_amp")), 0.001)
		row["sh_t"] = snappedf(float(_cam_rig.get("_shake_time")), 0.001)
		row["sh_d"] = snappedf(float(_cam_rig.get("_shake_dur")), 0.001)
		row["fovk"] = snappedf(float(_cam_rig.get("_fov_kick")), 0.01)
	if _player != null and is_instance_valid(_player):
		var an: Node = _player.get("animator")
		if an != null:
			row["sq"] = snappedf(float(an.get("_sq")), 0.001)
		row["st"] = str(_player.get("state"))
		row["pf"] = int(_player.get("physics_frame"))
	var j := get_node_or_null("/root/Juice")
	if j != null:
		var s: Dictionary = j.get("stats")
		row["vfx"] = int(s.get("vfx", 0))
		row["drop"] = int(s.get("dropped", 0))
		row["cull"] = int(s.get("culled", 0))
		row["shk"] = int(s.get("shakes", 0))
		row["hs"] = int(s.get("hitstops", 0))
		row["unk"] = int(s.get("unknown", 0))
		row["act"] = int(j.get("_active"))
	if _frame == 90 and j != null:
		print("[CritJuice] probe: Juice._movie_fps=%s write_movie_path='%s' cmdline_has_fixed_fps=%s" % [str(j.get("_movie_fps")),
			Engine.get_write_movie_path(), str(OS.get_cmdline_args().has("--fixed-fps"))])
	if _frames_f != null:
		_frames_f.store_line(JSON.stringify(row))
		if _frame % 60 == 0:
			_frames_f.flush()
			if _events_f != null:
				_events_f.flush()
			_dump_sfx()
	if mode == "lab" and _end_frame > 0 and row.has("pf") and int(row["pf"]) >= _end_frame + 20 and not _done:
		_finish()


func _dump_sfx() -> void:
	if _sfx == null or not is_instance_valid(_sfx):
		return
	var f := FileAccess.open(out_dir + "/" + tag + "_sfx.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"t0_ms": _t0, "played": _sfx.get("played")}))
		f.close()


func _finish() -> void:
	_done = true
	_dump_sfx()
	var j := get_node_or_null("/root/Juice")
	var summary := {"mode": mode, "tag": tag, "frames": _frame, "stats": j.get("stats") if j != null else {},
		"results": results, "notes": notes, "seconds": (Time.get_ticks_msec() - _t0) / 1000.0}
	var f := FileAccess.open(out_dir + "/" + tag + "_summary.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	if _frames_f != null:
		_frames_f.close()
		_frames_f = null
	if _events_f != null:
		_events_f.close()
		_events_f = null
	print("[CritJuice] DONE %s frames=%d" % [tag, _frame])
	get_tree().paused = false
	get_tree().quit(0)


func _exit_tree() -> void:
	if not _done and _frames_f != null:
		_frames_f.flush()
		_events_f.flush()
		_dump_sfx()


# =====================================================================================================
# world mode: scripted play in the real worlds

func note(s: String) -> void:
	notes.append(s)
	print("[CritJuice] NOTE ", s)


func check(n: String, ok: bool, detail: Variant = "") -> void:
	results.append({"name": n, "pass": ok, "detail": detail, "f": _frame})
	print("[CritJuice] %s %s  %s" % ["PASS" if ok else "FAIL", n, str(detail)])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func until_unpaused(max_frames: int = 900) -> void:
	var i := 0
	while get_tree().paused and i < max_frames:
		await get_tree().process_frame
		i += 1


func player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("player") as CharacterBody3D


func release_all() -> void:
	for a in ["jump", "crouch", "attack", "sniff", "move_left", "move_right", "move_forward", "move_back"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func tap(action: String, hold: int = 3) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)


func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return rad_to_deg(atan2(-d.x, -d.z))


func put(p: Vector3, yaw_deg: float = 0.0) -> void:
	var pl := player()
	if pl == null:
		return
	release_all()
	pl.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), p))
	pl.velocity = Vector3.ZERO


func enter(wid: String) -> bool:
	await until_unpaused()
	Router.enter_world(wid, "")
	var i := 0
	while i < 1800:
		await get_tree().process_frame
		i += 1
		var sr := get_tree().current_scene
		if sr != null and "world_id" in sr and String(sr.get("world_id")) == wid and player() != null and not get_tree().paused:
			break
	await frames(120)
	await until_unpaused()
	var sr2 := get_tree().current_scene
	return sr2 != null and "world_id" in sr2 and String(sr2.get("world_id")) == wid


func ground_below(p: Vector3) -> Vector3:
	var pl := player()
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, 1)
	q.exclude = [pl.get_rid()]
	var r := space.intersect_ray(q)
	return r["position"] if not r.is_empty() else p


func _enemies() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node3D and not bool(e.get("is_defeated")) and (e as Node3D).is_inside_tree():
			out.append(e)
	var pl := player()
	if pl != null:
		out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_to(pl.global_position) < b.global_position.distance_to(pl.global_position))
	return out


func _mark(s: String) -> void:
	var j := get_node_or_null("/root/Juice")
	print("[CritJuice] MARK f%d %s" % [_frame, s])
	if _events_f != null:
		_events_f.store_line(JSON.stringify({"f": _frame, "drawn": Engine.get_frames_drawn(), "ms": Time.get_ticks_msec(), "mark": s}))


func _world_script() -> void:
	await frames(20)
	Game.new_game()
	var worlds := _arg("worlds", "W1,W3").split(",")
	for w in worlds:
		if not await enter(w):
			check("enter_" + w, false)
			continue
		check("enter_" + w, true)
		await frames(60)
		await _fight_enemies(w, int(_arg("enemies", "3")))
		await _crate(w)
		await _acorns(w)
	_finish()


func _fight_enemies(w: String, n: int) -> void:
	var done := 0
	var tried := {}
	for _k in 8:
		if done >= n:
			break
		var list := _enemies()
		var e: Node3D = null
		for c in list:
			if not tried.has(c.get_instance_id()) and String(c.get_script().resource_path).find("boss") < 0:
				e = c
				break
		if e == null:
			break
		tried[e.get_instance_id()] = true
		var fam := String(e.get_script().resource_path.get_file().get_basename())
		_mark("%s enemy %s (%s)" % [w, e.name, fam])
		var ep := e.global_position
		# Approach from 6 m so the enemy notices, then walk in and punch.
		var dir := Vector3(1, 0, 0.3).normalized()
		var start := ground_below(ep + dir * 6.0) + Vector3.UP * 0.1
		put(start, yaw_to(start, ep))
		await frames(50)
		var pl := player()
		var hits := 0
		for attempt in 6:
			if not is_instance_valid(e) or bool(e.get("is_defeated")):
				break
			ep = e.global_position
			var near := ground_below(ep + (pl.global_position - ep).normalized() * 1.25) + Vector3.UP * 0.1
			put(near, yaw_to(near, ep))
			await frames(4)
			for _c in 3:
				await tap("attack", 3)
				await frames(12)
			await frames(30)
			hits += 1
		var defeated := not is_instance_valid(e) or bool(e.get("is_defeated"))
		if not defeated and is_instance_valid(e):
			# Stomp from above.
			ep = e.global_position
			put(ep + Vector3.UP * 3.2, 0.0)
			await frames(70)
			defeated = not is_instance_valid(e) or bool(e.get("is_defeated"))
		check("%s_%s_defeated" % [w, fam], defeated, "punch rounds %d" % hits)
		await frames(150)
		done += 1


func _crate(w: String) -> void:
	var crates: Array = []
	for n in get_tree().current_scene.find_children("*", "", true, false):
		if n is BreakableCrate:
			crates.append(n)
	if crates.is_empty():
		note("%s: no BreakableCrate" % w)
		return
	var c: Node3D = crates[0]
	_mark("%s crate %s" % [w, c.name])
	var cp := c.global_position
	var at := ground_below(cp + Vector3(1.3, 0, 0)) + Vector3.UP * 0.1
	put(at, yaw_to(at, cp))
	await frames(6)
	for _i in 3:
		await tap("attack", 3)
		await frames(14)
	await frames(60)
	if is_instance_valid(c) and c.is_inside_tree() and c.visible:
		# Ham Slam onto it.
		put(cp + Vector3.UP * 3.0, 0.0)
		await frames(14)
		await tap("crouch", 3)
		await frames(90)
	check("%s_crate_broken" % w, not is_instance_valid(c) or not c.is_inside_tree() or not c.visible or bool(c.get("broken") if "broken" in c else false))
	await frames(60)


func _acorns(w: String) -> void:
	var acorns := get_tree().get_nodes_in_group("acorn")
	var got := 0
	for a in acorns:
		if got >= 4:
			break
		if not (a is Node3D) or not is_instance_valid(a) or not (a as Node3D).is_visible_in_tree():
			continue
		_mark("%s acorn %s" % [w, (a as Node).name])
		put((a as Node3D).global_position + Vector3(0, -0.2, 0), 0.0)
		await frames(20)
		got += 1
	await frames(40)
