extends Node
## W1 critique round 1, lens GAME FEEL, MOVEMENT AND CAMERA (read-only probe; changes nothing in W1's files).
## Instances W1 (or --scene=...). Two ways to drive the real MakPlayer:
##   --w1bot=<tests>   the builder's reachability bot (w1_bot.gd) plays the truffle routes, this probe only watches;
##   --feel=<file>     this probe's own scenario list (JSON array, see run_r1_feel.py): views with camera orbit sweeps,
##                     gust stand/run tests, scripted walks and hops.
## Every rendered frame it logs to --cam-out=<abs jsonl>: player state, grounded, interpolated feet, velocity, wind,
## camera position/yaw/pitch/distance, occlusion of chest and head (layer 1 rays), camera sphere inside geometry,
## chest screen position, active camera, bot note / scenario label, and while airborne the landing spot under Mak
## (in frustum, occluded, screen position). Auto-shots: bad camera frames (occluded or inside for 10+ frames),
## rate-limited, at most --max-auto shots, into --shot-dir. --dump=<abs json> writes the built geometry (platform table,
## checkpoints, wind zones, camera hints/zones, climbables, spawns, kill_y) 1.5 s after load.

var _player: Node3D
var _rig: Node3D
var _cam: Camera3D
var _out: FileAccess
var _frames := 0
var _shot_dir := ""
var _label := "probe"
var _max_auto := 30
var _auto_n := 0
var _bad_run := 0
var _last_auto_rf := -9999
var _dump_path := ""
var _dumped := false
var _ctx := ""
var _bot: Node
var _bot_log_n := 0
var _feel_file := ""
var _results: Array = []
var _res_path := ""
var _period_shot := 0
var _ctx_shots := false
var _t0 := 0


func _ready() -> void:
	process_priority = 1000
	var dev := get_tree().root.get_node_or_null("Dev")
	var scene_path := "res://scenes/worlds/w1/W1.tscn"
	var out_path := ""
	if dev != null:
		scene_path = str(dev.call("arg", "scene", scene_path))
		out_path = str(dev.call("arg", "cam-out", ""))
		_shot_dir = str(dev.call("arg", "shot-dir", ""))
		_label = str(dev.call("arg", "label", _label))
		_max_auto = int(str(dev.call("arg", "max-auto", "30")))
		_dump_path = str(dev.call("arg", "dump", ""))
		_feel_file = str(dev.call("arg", "feel", ""))
		_res_path = str(dev.call("arg", "res-out", ""))
		_period_shot = int(str(dev.call("arg", "period-shot", "0")))
		_ctx_shots = dev.has_method("has_arg") and bool(dev.call("has_arg", "ctx-shots"))
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_error("[FeelW1] cannot load " + scene_path)
		get_tree().quit(2)
		return
	var world := ps.instantiate()
	add_child(world)
	# Pass 3 (20:55 Bangkok): the shipped w1_bot.gd has parse errors since 11:54, so --w1bot2 runs a copy with only
	# the three type annotations fixed (game/tests/critique_w1/r1_feel/w1_bot_copy.gd), added under the world root.
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "w1bot2")):
		var bot := Node.new()
		bot.name = "W1Bot"
		bot.set_script(load("res://tests/critique_w1/r1_feel/w1_bot_copy.gd"))
		world.add_child(bot)
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		_out = FileAccess.open(out_path, FileAccess.WRITE)
	_t0 = Time.get_ticks_msec()
	if _feel_file != "":
		_run_feel.call_deferred()


# ------------------------------------------------------------------ helpers

func _excl() -> Array[RID]:
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	return ex


func _ray_hit(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, _excl())
	return get_viewport().get_camera_3d().get_world_3d().direct_space_state.intersect_ray(q)


func _hit_name(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	var c: Object = hit.get("collider")
	if c is Node:
		var n := c as Node
		var par := n.get_parent()
		return str(n.name) + ("<" + str(par.name) if par != null else "")
	return "?"


func _cam_inside(at: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.12
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = 1
	q.exclude = _excl()
	return not _cam.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _screen(p: Vector3) -> Array:
	var vp := get_viewport().get_visible_rect().size
	var c := get_viewport().get_camera_3d()
	if c.is_position_behind(p):
		return [-1.0, -1.0]
	var s := c.unproject_position(p)
	return [snappedf(s.x / vp.x, 0.001), snappedf(s.y / vp.y, 0.001)]


func _v(p: Vector3, d := 0.001) -> Array:
	return [snappedf(p.x, d), snappedf(p.y, d), snappedf(p.z, d)]


func _shot(name: String) -> void:
	if _shot_dir == "":
		return
	var img := get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		img.save_png(_shot_dir.path_join("%s__%s.png" % [_label, name.validate_filename()]))


# ------------------------------------------------------------------ geometry dump

func _dump() -> void:
	_dumped = true
	if _dump_path == "":
		return
	var world := get_child(0)
	var d := {"kill_y": world.get("kill_y")}
	var level := world.get_node_or_null("Level")
	if level != null:
		var pl: Variant = level.get("plat")
		if pl is Dictionary:
			d["plat"] = pl
	var cps := []
	for n in get_tree().get_nodes_in_group("checkpoint"):
		cps.append({"name": str(n.name), "pos": _v((n as Node3D).global_position, 0.01)})
	d["checkpoints"] = cps
	var winds := []
	for n in get_tree().get_nodes_in_group("wind_zone"):
		var n3 := n as Node3D
		var row := {"name": str(n.name), "path": str(n.get_path()), "pos": _v(n3.global_position, 0.01),
			"dir_world": _v((n3.global_transform.basis * (n.get("direction") as Vector3)).normalized(), 0.01) if n.get("direction") is Vector3 else null,
			"size": _v(n.get("size") as Vector3, 0.01) if n.get("size") is Vector3 else null,
			"strength": n.get("strength"), "mode": n.get("mode"), "enabled": n.get("enabled"),
			"pulse_period": n.get("pulse_period"), "pulse_duty": n.get("pulse_duty")}
		winds.append(row)
	d["wind_zones"] = winds
	var hints := []
	for g in ["camera_hint", "camera_zone"]:
		for n in get_tree().get_nodes_in_group(g):
			var metas := {}
			for m in n.get_meta_list():
				metas[str(m)] = str(n.get_meta(m))
			hints.append({"group": g, "name": str(n.name), "pos": _v((n as Node3D).global_position, 0.01), "metas": metas})
	d["camera_hints"] = hints
	var climbs := []
	for n in get_tree().get_nodes_in_group("climbable"):
		climbs.append({"name": str(n.name), "path": str(n.get_path()), "pos": _v((n as Node3D).global_position, 0.01)})
	d["climbables"] = climbs
	var sp := []
	var spawns := world.get_node_or_null("Spawns")
	if spawns != null:
		for n in spawns.get_children():
			if n is Node3D:
				sp.append({"name": str(n.name), "pos": _v((n as Node3D).global_position, 0.01), "yaw": snappedf((n as Node3D).global_rotation_degrees.y, 0.1)})
	d["spawns"] = sp
	var hz := []
	for n in get_tree().get_nodes_in_group("hazard"):
		if n is Node3D:
			hz.append({"name": str(n.name), "pos": _v((n as Node3D).global_position, 0.01)})
	d["hazards"] = hz
	var nl := []
	for n in get_tree().get_nodes_in_group("no_ledge_grab"):
		nl.append(str(n.name))
	d["no_ledge_grab"] = nl
	var bouncy := []
	for n in get_tree().get_nodes_in_group("bouncy"):
		if n is Node3D:
			bouncy.append({"name": str(n.name), "pos": _v((n as Node3D).global_position, 0.01), "v": n.get_meta("bounce_velocity", null)})
	d["bouncy"] = bouncy
	DirAccess.make_dir_recursive_absolute(_dump_path.get_base_dir())
	var f := FileAccess.open(_dump_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, " "))


# ------------------------------------------------------------------ per-frame log

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
	if not _dumped and Time.get_ticks_msec() - _t0 > 1500:
		_dump()
	if _bot == null:
		_bot = get_tree().root.find_child("W1Bot", true, false)
	if _bot != null:
		var lg: Variant = _bot.get("_log")
		if lg is Array and (lg as Array).size() != _bot_log_n:
			_bot_log_n = (lg as Array).size()
			if _bot_log_n > 0:
				_ctx = "bot:" + str((lg as Array)[_bot_log_n - 1])
				if _ctx_shots:
					_shot.call_deferred("ctx%03d_%s" % [_bot_log_n, _ctx.substr(4, 40)])
	var pf := int(_player.get("physics_frame"))
	var pp := _player.get_global_transform_interpolated().origin
	var chest := pp + Vector3.UP * 0.6
	var head := pp + Vector3.UP * 1.1
	var active := get_viewport().get_camera_3d()
	var cpos := active.global_position
	var grounded := bool(_player.get("grounded"))
	var z: Variant = _rig.get("zone")
	var hc := _ray_hit(cpos, chest)
	var hh := _ray_hit(cpos, head)
	var inside := _cam_inside(_cam.global_position)
	var row := {
		"rf": _frames, "pf": pf, "s": str(_player.call("get_state_name")), "g": grounded,
		"p": _v(pp), "v": _v(_player.get("velocity") as Vector3, 0.01),
		"wind": _v(_player.get("wind_vel") as Vector3, 0.01),
		"pyaw": snappedf(rad_to_deg(float(_player.get("facing_yaw"))), 0.1),
		"c": _v(cpos), "cyaw": snappedf(rad_to_deg(float(_rig.get("yaw"))), 0.01),
		"cpitch": snappedf(rad_to_deg(float(_rig.get("pitch"))), 0.01),
		"dist": snappedf(cpos.distance_to(chest), 0.001),
		"occ_chest": not hc.is_empty(), "occ_head": not hh.is_empty(), "occ_by": _hit_name(hc),
		"scr": _screen(chest), "inside": inside, "fov": snappedf(active.fov, 0.1),
		"gamecam": active == _cam, "zone": (str((z as Node).name) if z is Node else ""),
		"ctx": _ctx,
	}
	if not grounded:
		var hit := _ray_hit(pp + Vector3.UP * 0.1, pp + Vector3.DOWN * 60.0)
		if not hit.is_empty():
			var lp: Vector3 = hit["position"]
			row["land"] = {"y": snappedf(lp.y, 0.01), "fr": active.is_position_in_frustum(lp),
				"occ": not _ray_hit(cpos, lp + Vector3.UP * 0.05).is_empty(), "scr": _screen(lp), "on": _hit_name(hit)}
		else:
			row["land"] = {"y": null}
	if _out != null:
		_out.store_line(JSON.stringify(row))
	# Auto-shots on sustained bad camera frames (only for the gameplay camera).
	var bad: bool = bool(row["gamecam"]) and (bool(row["occ_chest"]) or inside)
	_bad_run = _bad_run + 1 if bad else 0
	if _bad_run == 10 and _auto_n < _max_auto and _frames - _last_auto_rf > 90:
		_auto_n += 1
		_last_auto_rf = _frames
		_shot("auto%02d_rf%05d_%s" % [_auto_n, _frames, "inside" if inside else "occ"])
	if _period_shot > 0 and _frames % _period_shot == 0:
		_shot("per_rf%05d" % _frames)


func _exit_tree() -> void:
	if _out != null:
		_out.flush()
		_out.close()
		_out = null


# ------------------------------------------------------------------ scenario driver (--feel)

var _inp: Object
var _stick := Vector2.ZERO
var _camv := Vector2.ZERO


func _physics_process(_d: float) -> void:
	if _inp != null:
		_inp.set("_r_stick", _stick)
		_inp.set("_r_cam", _camv)
		_inp.set("cam", _camv)


func _pf(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	while get_tree().paused:
		await get_tree().process_frame


func _hold(action: String, n: int) -> void:
	var hf: Dictionary = _inp.get("_hold_frames")
	hf[action] = n


func _tp(pos: Vector3, yaw_deg: float) -> void:
	_stick = Vector2.ZERO
	_camv = Vector2.ZERO
	_player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos + Vector3(0, 0.05, 0)))
	await _pf(4)
	if _rig != null and _rig.has_method("snap_behind"):
		_rig.call("snap_behind")
	await _pf(8)


func _steer(t: Vector3, mag := 1.0) -> float:
	var d := t - _player.global_position
	d.y = 0.0
	if d.length() < 0.01:
		_stick = Vector2.ZERO
		return 0.0
	_stick = Vector2(d.x, -d.z).normalized() * mag
	return d.length()


func _cam_metrics() -> Dictionary:
	var pp := _player.global_position
	var cpos := _cam.global_position
	return {"occ_chest": not _ray_hit(cpos, pp + Vector3.UP * 0.6).is_empty(),
		"occ_head": not _ray_hit(cpos, pp + Vector3.UP * 1.1).is_empty(),
		"inside": _cam_inside(cpos), "dist": snappedf(cpos.distance_to(pp + Vector3.UP * 0.6), 0.01),
		"by": _hit_name(_ray_hit(cpos, pp + Vector3.UP * 0.6))}


func _run_feel() -> void:
	while _player == null or _cam == null or not _dumped:
		await get_tree().process_frame
	await _pf(40)
	_inp = _player.get("inp")
	_inp.call("setup", {"steer": "world", "events": []}, 0.2, 1.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.set("ai_enabled", false)
	var txt := FileAccess.get_file_as_string(_feel_file)
	var list: Variant = JSON.parse_string(txt)
	if not (list is Array):
		push_error("[FeelW1] bad --feel file")
		get_tree().quit(3)
		return
	for sc in list:
		var s: Dictionary = sc
		_ctx = "feel:" + str(s.get("name", "?"))
		var kind := str(s.get("kind", "view"))
		var r: Dictionary = {"name": s.get("name"), "kind": kind}
		match kind:
			"view":
				r.merge(await _sc_view(s))
			"stand":
				r.merge(await _sc_stand(s))
			"walk":
				r.merge(await _sc_walk(s))
			"hop":
				r.merge(await _sc_hop(s))
			"kicks":
				r.merge(await _sc_kicks(s))
			"longjump":
				r.merge(await _sc_longjump(s))
		_results.append(r)
		print("[FeelW1] ", JSON.stringify(r))
	if _res_path != "":
		var f := FileAccess.open(_res_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(_results, " "))
	await _pf(5)
	get_tree().quit()


func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## View: teleport facing `yaw`, settle, shot, then an orbit sweep in 8 steps of 45 deg (camera stick), sampling
## occlusion/inside at each step, with shots at 90/180/270 deg when `orbit_shots`.
func _sc_view(s: Dictionary) -> Dictionary:
	await _tp(_v3(s["pos"]), float(s.get("yaw", 0.0)))
	await _pf(int(s.get("settle", 60)))
	var m0 := _cam_metrics()
	m0["pos"] = _v(_player.global_position, 0.01)
	_shot(str(s["name"]) + "_rest")
	var samples := []
	if bool(s.get("orbit", true)):
		var occ := 0
		var ins := 0
		var mind := 99.0
		for k in 8:
			# 45 deg at 160 deg/s = 0.28 s = 17 frames
			_camv = Vector2(1.0, 0.0)
			for i in 17:
				await _pf(1)
				var mm := _cam_metrics()
				occ += 1 if mm["occ_chest"] else 0
				ins += 1 if mm["inside"] else 0
				mind = minf(mind, float(mm["dist"]))
			_camv = Vector2.ZERO
			await _pf(10)
			var m := _cam_metrics()
			m["step"] = (k + 1) * 45
			samples.append(m)
			if bool(s.get("orbit_shots", false)) and (k + 1) % 2 == 0 and k < 7:
				_shot("%s_orbit%03d" % [str(s["name"]), (k + 1) * 45])
		return {"rest": m0, "orbit_occ_frac": snappedf(occ / 136.0, 0.01), "orbit_inside_frac": snappedf(ins / 136.0, 0.01),
			"orbit_min_dist": snappedf(mind, 0.01), "orbit": samples}
	return {"rest": m0}


## Stand: teleport, hold the stick (world) for `seconds`, record displacement, min y, max wind, state changes.
func _sc_stand(s: Dictionary) -> Dictionary:
	await _tp(_v3(s["pos"]), float(s.get("yaw", 0.0)))
	await _pf(20)
	var p0 := _player.global_position
	var st: Array = s.get("stick", [0, 0])
	_stick = Vector2(float(st[0]), float(st[1]))
	var miny := p0.y
	var maxw := 0.0
	var maxh := 0.0
	var jump_every := int(s.get("jump_every", 0))
	var n := int(float(s.get("seconds", 6.0)) * 60.0)
	var states := {}
	for f in n:
		if jump_every > 0 and f % jump_every == 5:
			_hold("jump", 16)
		await _pf(1)
		var pp := _player.global_position
		miny = minf(miny, pp.y)
		maxw = maxf(maxw, (_player.get("wind_vel") as Vector3).length())
		maxh = maxf(maxh, Vector2(pp.x - p0.x, pp.z - p0.z).length())
		states[str(_player.call("get_state_name"))] = true
		if f == n / 2 and bool(s.get("shot", false)):
			_shot(str(s["name"]) + "_mid")
	_stick = Vector2.ZERO
	var p1 := _player.global_position
	return {"p0": _v(p0, 0.01), "p1": _v(p1, 0.01), "disp": _v(p1 - p0, 0.01), "max_horiz_disp": snappedf(maxh, 0.01),
		"min_y": snappedf(miny, 0.01), "max_wind": snappedf(maxw, 0.01), "states": states.keys()}


## Walk: teleport, then steer through `path` points (x,z; y ignored); `jump_at` indices press jump when reaching that
## point. Logs the camera metrics along the way (frames occluded / inside).
func _sc_walk(s: Dictionary) -> Dictionary:
	await _tp(_v3(s["pos"]), float(s.get("yaw", 0.0)))
	await _pf(20)
	var occ := 0
	var ins := 0
	var total := 0
	var jumps: Array = s.get("jump_at", [])
	var mag := float(s.get("mag", 1.0))
	var shots_at: Array = s.get("shot_at", [])
	var miny := _player.global_position.y
	var reached := 0
	var path: Array = s["path"]
	for i in path.size():
		var t := _v3(path[i])
		var f := 0
		var did_jump := false
		while f < 60 * 12:
			var d := _steer(t, mag)
			if jumps.has(i) and not did_jump and d < float(s.get("jump_dist", 1.0)):
				_hold("jump", int(s.get("jump_hold", 16)))
				did_jump = true
			if d < 0.5:
				break
			await _pf(1)
			f += 1
			total += 1
			var m := _cam_metrics()
			occ += 1 if m["occ_chest"] else 0
			ins += 1 if m["inside"] else 0
			miny = minf(miny, _player.global_position.y)
		if f >= 60 * 12:
			break
		reached = i + 1
		if shots_at.has(i):
			_shot("%s_pt%02d" % [str(s["name"]), i])
	_stick = Vector2.ZERO
	await _pf(30)
	return {"reached": reached, "of": path.size(), "end": _v(_player.global_position, 0.01), "min_y": snappedf(miny, 0.01),
		"occ_frac": snappedf(float(occ) / maxf(total, 1), 0.01), "inside_frac": snappedf(float(ins) / maxf(total, 1), 0.01), "frames": total}


## Hop: teleport at `pos`, walk to `takeoff` (optional run-up from `pos`), jump toward `target` holding the stick,
## report the landing point and whether it landed within tol of target.y. `kind`: single (default) or double (land
## then jump again inside the chain window). Records apex, airtime and landing visibility.
func _sc_hop(s: Dictionary) -> Dictionary:
	await _tp(_v3(s["pos"]), float(s.get("yaw", 0.0)))
	await _pf(20)
	var target := _v3(s["target"])
	if s.has("takeoff"):
		var to := _v3(s["takeoff"])
		var f0 := 0
		while f0 < 600 and _steer(to, float(s.get("mag", 1.0))) > float(s.get("takeoff_tol", 0.3)):
			await _pf(1)
			f0 += 1
	var speed0 := Vector2(_player.velocity.x, _player.velocity.z).length()
	_steer(target)
	_hold("jump", int(s.get("hold", 18)))
	var y0 := _player.global_position.y
	var apex := y0
	var air := 0
	var land_vis := 0
	var land_occ := 0
	await _pf(4)
	var f := 0
	var release := bool(s.get("release", false))
	while f < 300:
		var d := _steer(target)
		if d < 0.2 or (release and f > int(s.get("release_after", 6))):
			_stick = Vector2.ZERO
		await _pf(1)
		f += 1
		apex = maxf(apex, _player.global_position.y)
		if not bool(_player.get("grounded")):
			air += 1
		if f > 6 and bool(_player.get("grounded")):
			break
	_stick = Vector2.ZERO
	await _pf(20)
	var pe := _player.global_position
	var ok := absf(pe.y - target.y) < float(s.get("tol_y", 0.35)) and Vector2(pe.x - target.x, pe.z - target.z).length() < float(s.get("tol_xz", 1.4))
	_shot(str(s["name"]) + "_landed")
	return {"ok": ok, "end": _v(pe, 0.01), "target": _v(target, 0.01), "takeoff_speed": snappedf(speed0, 0.01),
		"apex_rise": snappedf(apex - y0, 0.01), "air_s": snappedf(air / 60.0, 0.01), "state": str(_player.call("get_state_name"))}


## Kicks: chimney wall-kick climb holding jump like a player (hold `hold` frames per kick), alternating along x.
## Reports kicks used, best y, the rise of each kick and whether the top (`top_y`) was reached within `seconds`.
func _sc_kicks(s: Dictionary) -> Dictionary:
	await _tp(_v3(s["pos"]), float(s.get("yaw", 90.0)))
	await _pf(20)
	var east := false
	_stick = Vector2(-1.0, 0.0)
	await _pf(int(s.get("runup", 10)))
	_hold("jump", int(s.get("hold", 14)))
	var kicks := 0
	var best := _player.global_position.y
	var rises := []
	var last_y := best
	var since := 99
	var top_y := float(s.get("top_y", 26.0))
	var n := int(float(s.get("seconds", 14.0)) * 60.0)
	var t_top := -1.0
	for f in n:
		since += 1
		_stick = Vector2(1.0 if east else -1.0, 0.0)
		var py := _player.global_position.y
		best = maxf(best, py)
		if py > top_y and t_top < 0.0:
			t_top = f / 60.0
			_stick = Vector2.ZERO
			break
		var st := str(_player.call("get_state_name"))
		if (_player as CharacterBody3D).is_on_wall() and not bool(_player.get("grounded")) and since > 6:
			east = not east
			_stick = Vector2(1.0 if east else -1.0, 0.0)
			_hold("jump", int(s.get("hold", 14)))
			kicks += 1
			rises.append(snappedf(py - last_y, 0.01))
			last_y = py
			since = 0
		elif bool(_player.get("grounded")) and since > 10:
			east = _player.global_position.x < float(s.get("mid_x", 11.3))
			_stick = Vector2(-1.0 if east else 1.0, 0.0)
			await _pf(10)
			_stick = Vector2(1.0 if east else -1.0, 0.0)
			await _pf(12)
			_hold("jump", int(s.get("hold", 14)))
			since = 0
			last_y = _player.global_position.y
		await _pf(1)
	_stick = Vector2.ZERO
	return {"kicks": kicks, "best_y": snappedf(best, 0.01), "t_top_s": snappedf(t_top, 0.01), "rises": rises}


## Long jump (pass 3): teleport at `pos`, run toward `target` for `run_s` seconds (full stick), then crouch for
## `crouch_f` frames and press jump with the stick held; reports the jump kind, landing point, airtime and whether
## it ended within tol of the target top. Landing visibility comes from the per-frame camera log.
func _sc_longjump(s: Dictionary) -> Dictionary:
	await _tp(_v3(s["pos"]), float(s.get("yaw", 0.0)))
	await _pf(20)
	var target := _v3(s["target"])
	var kinds := []
	if _player.has_signal("jumped"):
		_player.connect("jumped", func(k: String) -> void: kinds.append(k))
	var nrun := int(float(s.get("run_s", 1.6)) * 60.0)
	for i in nrun:
		_steer(target)
		await _pf(1)
	var speed0 := Vector2(_player.velocity.x, _player.velocity.z).length()
	var x0 := _player.global_position
	_hold("crouch", int(s.get("crouch_f", 3)))
	await _pf(int(s.get("crouch_f", 3)) - 1)
	_hold("jump", int(s.get("hold", 20)))
	var air := 0
	var apex := x0.y
	var f := 0
	await _pf(3)
	while f < 300:
		_steer(target)
		await _pf(1)
		f += 1
		apex = maxf(apex, _player.global_position.y)
		if not bool(_player.get("grounded")):
			air += 1
		if f > 6 and bool(_player.get("grounded")):
			break
	_stick = Vector2.ZERO
	await _pf(20)
	var pe := _player.global_position
	var ok := absf(pe.y - target.y) < float(s.get("tol_y", 0.4)) and Vector2(pe.x - target.x, pe.z - target.z).length() < float(s.get("tol_xz", 1.6))
	_shot(str(s["name"]) + "_landed")
	return {"ok": ok, "kinds": kinds, "takeoff": _v(x0, 0.01), "takeoff_speed": snappedf(speed0, 0.01), "end": _v(pe, 0.01),
		"target": _v(target, 0.01), "dist_xz": snappedf(Vector2(pe.x - x0.x, pe.z - x0.z).length(), 0.01),
		"apex_rise": snappedf(apex - x0.y, 0.01), "air_s": snappedf(air / 60.0, 0.01), "state": str(_player.call("get_state_name"))}
