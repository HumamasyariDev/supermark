extends "res://scripts/boss/boss_bot.gd"
## BOSS critique round 1, lens BOSS FIGHT DESIGN. Read-only probe: drives the REAL Player.tscn through MakInput exactly
## like game/scripts/boss/boss_bot.gd (it reuses the bot's movement helpers by inheritance) but plays the way a first-time
## human would, and measures fairness and clarity. Nothing in the boss track is modified.
##
## Modes (after --):  --crit-mode=p1  idle through cycle 1 at the spawn, then hide in the C3 lee (the shelter nearest the
##                                    spawn) and run for the pant only after a 0.25 s reaction delay from the hop-down
##                    --crit-mode=p3  dud puff, then plug launches with a NEUTRAL stick (slam only when over the head),
##                                    a fall at 1 slice after hit 1, and a 1.6 s hesitation beside the next vent (crows)
## Always measured: wolf on screen (frustum + line of sight from the gameplay camera) per phase/step, the P3 gold
## head ring while Mak is above the head, health and acorn changes. Use --boss-phase / --no-cine / --profile=crit_boss.
## Writes Docs/progress/critique/boss/r1_fun/<UTC>__probe_<mode>.json and a few native screenshots.

var cmode := "p1"
var stage := "boot"
var stage_t := 0.0
var react := 0.25
var vis: Dictionary = {}
var ring := {"over_head_frames": 0, "ring_visible_frames": 0}
var shots: Dictionary = {}
var notes: Array = []
var health_log: Array = []
var attempts: Array = []
var cur: Dictionary = {}
var game: Node
var out_dir := ""
var _hits_before := 0
var _duds_before := 0
var _hes_done := false
var _fall_done := false
var _fall: Dictionary = {}
var _hes: Dictionary = {}
var _idle: Dictionary = {}
var _hop_t := -1.0
var _pant_t := -1.0
var _pant_end_t := -1.0
var _c3_tries: Array = []
var _last_kind := ""
var _boot_wait := 0.0
var _skip_dud := false
var _dump_t := 0.0
var _stamp := ""


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	if dev != null:
		cmode = String(dev.call("arg", "crit-mode", "p1"))
		_timeout = float(dev.call("arg", "crit-timeout", "150"))
		var skip := String(dev.call("arg", "crit-skip", ""))
		_fall_done = skip.contains("fall")
		_hes_done = skip.contains("hes")
		_skip_dud = skip.contains("dud")
	out_dir = ProjectSettings.globalize_path("res://").path_join("../Docs/progress/critique/boss/r1_fun").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = get_node_or_null("/root/Game")
	if game != null:
		game.connect("damaged", func(n: int) -> void: _note("DAMAGED %d -> health %d" % [n, int(game.get("health"))]))
		game.connect("player_respawned", func() -> void: _note("player_respawned (health %d)" % int(game.get("health"))))
		game.connect("cake_empty", func() -> void: _note("CAKE EMPTY"))


func _note(s: String) -> void:
	var row := {"t": snappedf(t, 0.01), "stage": stage, "e": s}
	if boss != null:
		row["boss"] = "P%d h%d %s" % [boss.phase, boss.hits, boss.state]
	notes.append(row)
	print("[CritBoss] t=%.2f %s %s" % [t, stage, s])


func _set_stage(s: String) -> void:
	stage = s
	stage_t = 0.0
	_note("stage -> " + s)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if arena == null:
		_boot_wait += delta
		var sc := get_tree().current_scene
		if sc is WolfRooftop and (sc as WolfRooftop).boss != null and (sc as WolfRooftop).player != null:
			start(sc as WolfRooftop)
			_timeout = maxf(_timeout, 60.0)
			_set_stage("start")
		return
	p = arena.player
	boss = arena.boss
	if p == null or boss == null or not is_instance_valid(p):
		return
	frame += 1
	t += delta
	stage_t += delta
	var inp := _inp()
	inp.set("replay_active", true)
	inp.set("steer_world", true)
	if frame % 15 == 0:
		health_log.append([snappedf(t, 0.01), int(game.get("health")) if game else -1, int(game.get("acorns")) if game else -1,
			snappedf(p.global_position.x, 0.1), snappedf(p.global_position.z, 0.1), snappedf(p.global_position.y, 0.1)])
	if t > _timeout:
		_write("timeout")
		return
	if get_tree().paused:
		_stick(Vector2.ZERO)
		return
	_dump_t += delta
	if _dump_t > 3.0:
		_dump_t = 0.0
		_write("partial (still running)", false)
	if cmode == "p3":
		_p3_probe(delta)
	else:
		_p1_probe(delta)


# ------------------------------------------------------------------ measurement (render side)

func _process(_delta: float) -> void:
	if arena == null or boss == null or p == null or _done or not is_instance_valid(p):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var key := "P%d_%s" % [boss.phase, boss._cur_step_kind() if boss.state == "p1" else boss.state]
	if boss.defeated:
		key = "defeat_" + boss.state
	var head := boss.rig.bone_world("head")
	var on := cam.is_position_in_frustum(head)
	var clear := on
	if on:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, head, 1)
		var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(head) > 0.6:
			clear = false
	var mak_on := cam.is_position_in_frustum(p.global_position + Vector3(0, 0.6, 0))
	var row: Array = vis.get(key, [0, 0, 0, 0])
	row[0] += 1
	if on:
		row[1] += 1
	if clear:
		row[2] += 1
	if mak_on and clear:
		row[3] += 1
	vis[key] = row
	if boss.phase == 3 and not boss.defeated:
		var d := p.global_position - boss.global_position
		if Vector2(d.x, d.z).length() < 1.6 and p.global_position.y > 3.6:
			ring["over_head_frames"] += 1
			if boss._gold_ring.visible:
				ring["ring_visible_frames"] += 1
			_shot("over_head_launch%d" % attempts.size())
		if boss.updraft == "apex":
			_shot("updraft_apex")
	if boss.phase == 1 and boss.state == "p1" and boss._cur_step_kind() == "gust" and boss.sheltered(p.global_position) and stage == "c3_hide":
		_shot("p1_hiding_C3_wolf_hidden")


func _shot(tag: String) -> void:
	if shots.has(tag):
		return
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var path := out_dir.path_join("%sZ__probe_%s_%s.png" % [stamp, cmode, tag])
	img.save_png(path)
	shots[tag] = path
	_note("screenshot " + path.get_file())


# ------------------------------------------------------------------ P1: idle cycle, then the C3 lee with reaction delay

func _p1_probe(_delta: float) -> void:
	var k := boss._cur_step_kind() if boss.state == "p1" else ""
	if k != _last_kind:
		if k == "hop_down":
			_hop_t = t
		if k == "pant":
			_pant_t = t
		if _last_kind == "pant":
			_pant_end_t = t
		_last_kind = k
	match stage:
		"start":
			_idle = {"health0": int(game.get("health")), "start_t": t}
			_set_stage("idle")
		"idle":
			# A first-timer who just watches: no input through the opener and the whole first cycle.
			_stick(Vector2.ZERO)
			if boss.cycle >= 2 or boss.phase != 1:
				_idle["health_end"] = int(game.get("health"))
				_idle["seconds"] = snappedf(t - float(_idle["start_t"]), 0.01)
				_idle["pos_end"] = str(p.global_position.snapped(Vector3.ONE * 0.1))
				_set_stage("c3_hide")
		"c3_hide":
			var spot: Vector3 = WolfRooftop.CHIMNEYS["C3"] + WolfRooftop.bearing_dir(float(WolfRooftop.LEE["C3"])) * 4.5
			_move_to(spot, 0.25)
			if k == "hop_down" and t - _hop_t >= react:
				_hits_before = boss.hits
				cur = {"hit_index": boss.hits + 1, "from": str(p.global_position.snapped(Vector3.ONE * 0.1)), "hop_t": snappedf(_hop_t, 0.01),
					"run_start": snappedf(t, 0.01), "pant_spot": str(boss.pant_spot)}
				_set_stage("c3_run")
		"c3_run":
			var head := boss.pant_spot + boss.facing * 0.35
			if k == "hop_down" or k == "pant":
				_attack_from_air(head, 2.2, 1.9, 0.75)
				if k == "pant" and not cur.has("arrive_t") and Vector2(p.global_position.x - head.x, p.global_position.z - head.z).length() < 2.2:
					cur["arrive_t"] = snappedf(t, 0.01)
					cur["arrive_after_pant_start"] = snappedf(t - _pant_t, 0.01)
			if boss.hits > _hits_before:
				cur["result"] = "HIT"
				cur["hit_after_pant_start"] = snappedf(t - _pant_t, 0.01)
				_c3_tries.append(cur)
				_set_stage("c3_hide" if boss.hits < 2 and boss.phase == 1 else "done")
			elif k == "hop_back" or (k != "hop_down" and k != "pant"):
				cur["result"] = "MISS (pant ended)"
				cur["pant_len"] = snappedf(t - _pant_t, 0.01)
				_c3_tries.append(cur)
				_set_stage("c3_hide")
			if _c3_tries.size() >= 5:
				_set_stage("done")
		"done":
			_stick(Vector2.ZERO)
			if stage_t > 1.0:
				_write("complete")


# ------------------------------------------------------------------ P3: dud, neutral launches, fall at 1 slice, hesitation

func _p3_probe(_delta: float) -> void:
	var pos := p.global_position
	var v := boss.active_vent
	match stage:
		"start":
			if boss.state == "p3" and v != null:
				_duds_before = boss._duds
				_set_stage("launch" if _skip_dud else "dud")
			else:
				_move_to(Vector3(0, 0, 7.5), 0.4)
		"dud":
			# A first-timer walks onto the glowing plug.
			if v != null:
				_move_to(v.global_position, 0.15, 0.8)
			if boss._duds > _duds_before:
				_note("dud puff (duds %d)" % boss._duds)
				_set_stage("dud_land")
			elif stage_t > 8.0:
				_set_stage("launch")
		"dud_land":
			_stick(Vector2.ZERO)
			if _grounded() and stage_t > 0.5:
				_set_stage("launch")
		"launch":
			if _try_begin_fly(v):
				return
			if boss.state == "p3_dizzy":
				_stick(Vector2.ZERO)
				return
			if v == null or (boss.state != "p3" and boss.state != "p3_cough"):
				_move_to(Vector3(0, 0, 7.0), 0.4)
				return
			if boss.hits == 1 and not _fall_done:
				_set_stage("fall_setup")
				return
			if boss.hits == 1 and not _hes_done:
				_set_stage("hesitate")
				return
			_approach_and_slam_plug(v)
		"fly":
			# NEUTRAL stick: no drift input at all. Slam only when the head is directly below.
			_stick(Vector2.ZERO)
			var r := Vector2(pos.x, pos.z).length()
			if r < float(cur["min_r"]):
				cur["min_r"] = snappedf(r, 0.01)
				cur["min_r_y"] = snappedf(pos.y, 0.01)
			if not cur.has("apex") and _vy() <= 0.0:
				cur["apex"] = snappedf(pos.y, 0.01)
				cur["apex_r"] = snappedf(r, 0.01)
			if r < 1.4 and _vy() < 0.0 and pos.y > 4.0 and _state() != "ham_slam" and not bool(cur["slammed"]):
				_slam()
				cur["slammed"] = true
				cur["slam_at"] = str(pos.snapped(Vector3.ONE * 0.01))
			if boss.hits > _hits_before or boss.defeated:
				cur["result"] = "HIT"
				attempts.append(cur)
				_set_stage("done" if boss.defeated else "launch")
			elif _grounded() and stage_t > 0.3:
				cur["result"] = "MISS"
				cur["land_r"] = snappedf(r, 0.01)
				cur["land"] = str(pos.snapped(Vector3.ONE * 0.1))
				attempts.append(cur)
				if attempts.size() >= 6:
					_set_stage("done")
				else:
					_set_stage("launch")
		"fall_setup":
			# Fall test (R3.4: "if the last slice is lost to a fall, the defeat rule applies").
			_fall = {"health_before": 1, "hits_before": boss.hits, "hit2_armed_before": boss.hit2_armed}
			game.set("health", 1)
			p.call("respawn", Transform3D(Basis(), WolfRooftop.polar(76.0, 16.6, 0.1)))
			_set_stage("fall_walk")
		"fall_walk":
			var outw := WolfRooftop.polar(76.0, 1.0)
			_stick(Vector2(outw.x, -outw.z))
			if stage_t > 0.2 and pos.distance_to(Vector3(0, 0, 14)) < 1.5:
				_fall["health_after"] = int(game.get("health"))
				_fall["hits_after"] = boss.hits
				_fall["hit2_armed_after"] = boss.hit2_armed
				_fall["boss_state_after"] = boss.state
				_fall_done = true
				_set_stage("launch")
			elif stage_t > 8.0:
				_fall["result"] = "did not fall"
				_fall_done = true
				_set_stage("launch")
		"hesitate":
			# Lining up beside the next vent for 1.6 s, as a human does, inside the crow's visit radius (r 2).
			if v == null or boss.state != "p3":
				_move_to(Vector3(0, 0, 7.0), 0.4)
				return
			var vp := v.global_position
			var side := Vector3(vp.x, 0, vp.z).normalized()
			var spot := vp + side * 1.3
			if not _hes.has("arrive_t"):
				if _move_to(spot, 0.2):
					_hes = {"arrive_t": snappedf(t, 0.01), "vent": v.vid, "health0": int(game.get("health")), "acorns0": int(game.get("acorns"))}
			else:
				_stick(Vector2.ZERO)
				if t - float(_hes["arrive_t"]) >= 1.6:
					_hes["health1"] = int(game.get("health"))
					_hes["acorns1"] = int(game.get("acorns"))
					_hes_done = true
					_set_stage("launch")
		"done":
			_stick(Vector2.ZERO)
			if stage_t > 1.0:
				_write("complete")


func _try_begin_fly(v: BossVent) -> bool:
	if _grounded() or _vy() < 14.0:
		return false
	_hits_before = boss.hits
	cur = {"n": attempts.size() + 1, "hit2_armed": boss.hit2_armed, "vent": v.vid if v != null else "-", "min_r": 99.0, "min_r_y": 0.0,
		"slammed": false, "launch_t": snappedf(t, 0.01), "launch_from": str(p.global_position.snapped(Vector3.ONE * 0.1)),
		"h_speed_at_launch": snappedf(Vector2(p.get("velocity").x, p.get("velocity").z).length(), 0.01)}
	_set_stage("fly")
	return true


func _approach_and_slam_plug(v: BossVent) -> void:
	var vp := v.global_position
	var d := vp - p.global_position
	d.y = 0.0
	if _grounded():
		_move_to(vp, 0.0, 0.7 if d.length() < 3.0 else 1.0)
		if d.length() < 1.9 and d.length() > 0.5 and frame - _jumped_at > 30:
			_jump(9)
		_air_slam_armed = true
	else:
		_move_to(vp, 0.05, 1.0)
		if _air_slam_armed and d.length() < 1.2 and _vy() < 0.5 and p.global_position.y < 3.4 and p.global_position.y > 0.6 and _state() != "ham_slam":
			_slam()
			_air_slam_armed = false


# ------------------------------------------------------------------ report

func _write(why: String, final: bool = true) -> void:
	if _done:
		return
	if final:
		_done = true
		if p != null and is_instance_valid(p):
			_stick(Vector2.ZERO)
	var vis_out := {}
	for k in vis.keys():
		var r: Array = vis[k]
		vis_out[k] = {"frames": r[0], "wolf_in_frustum": snappedf(float(r[1]) / maxf(1.0, float(r[0])), 0.01),
			"wolf_unoccluded": snappedf(float(r[2]) / maxf(1.0, float(r[0])), 0.01), "mak_and_wolf_clear": snappedf(float(r[3]) / maxf(1.0, float(r[0])), 0.01)}
	var res := {
		"utc": Time.get_datetime_string_from_system(true) + "Z", "mode": cmode, "why": why, "seconds": snappedf(t, 0.01),
		"note": "offline probe with the real Player.tscn via MakInput (critique r1, boss fight design lens)",
		"wolf_visibility_by_step": vis_out, "p3_head_ring": ring, "screenshots": shots,
		"p1_idle_first_cycle": _idle, "p1_c3_reaction_runs": _c3_tries, "reaction_delay_s": react,
		"p3_neutral_launches": attempts, "p3_fall_at_one_slice": _fall, "p3_hesitation_by_vent": _hes,
		"boss_events": boss.stats["events"] if boss != null else [], "notes": notes, "health_log_t_h_acorns_x_z_y": health_log,
	}
	if _stamp == "":
		_stamp = Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var f := FileAccess.open(out_dir.path_join("%sZ__probe_%s.json" % [_stamp, cmode]), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	if not final:
		return
	print("[CritBoss] DONE (%s) mode=%s" % [why, cmode])
	get_tree().create_timer(0.5, true).timeout.connect(func() -> void: get_tree().quit())
