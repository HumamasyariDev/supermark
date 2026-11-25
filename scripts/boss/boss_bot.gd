extends Node
## Scripted player for the boss fight (--bosstest): drives the REAL Player.tscn through its own MakInput
## (replay mode, world-space stick, held/tapped buttons), reacting to the wolf like a player would:
## P1 hide in a chimney's lee, run to the pant spot and stomp/slam the head; P2 bait the charge behind a
## chimney and Ham Slam the stuck wolf's tail; P3 step on the plug, slam it, drift in and slam the head;
## defeat: hop onto the plinth, double jump into the belly and Ham Slam it; collect the Great Truffle.
## Writes Docs/progress/boss/<UTC>__bosstest_realplayer_results.json and an input log, then quits.
## Dev args: --bosstest-timeout=<s> (default 420), --bosstest-hold (do not quit, for Movie Maker).

var arena: WolfRooftop
var boss: WolfBoss
var p: Node3D
var paused := false
var frame := 0
var t := 0.0
var events: Array = []
var _last_stick := Vector2(99, 99)
var _plan := ""
var _air_slam_armed := false
var _jumped_at := -100
var _hits_seen := 0
var _done := false
var _timeout := 420.0
var _result := {}
var _phase_seen := {}
var _plinth_jumps := 0
var _land_count := 0
var _was_grounded := true
var _defeat_t := 0.0
var _launched := false
var _from_plinth := false
var mode_pop := false
var mode_chimney := false
var _pop_done := false
var _bf_t := -1
var debug := false


func start(a: WolfRooftop) -> void:
	arena = a
	process_physics_priority = -100
	var dev := get_node_or_null("/root/Dev")
	if dev != null and dev.call("has_arg", "bosstest-timeout"):
		_timeout = float(dev.call("arg", "bosstest-timeout", "420"))
	if dev != null:
		mode_pop = bool(dev.call("has_arg", "bosstest-pop"))
		mode_chimney = bool(dev.call("has_arg", "bosstest-chimney"))
		debug = bool(dev.call("has_arg", "bosstest-debug"))
	print("[BossBot] armed, timeout %.0f s pop=%s chimney=%s" % [_timeout, str(mode_pop), str(mode_chimney)])


func _inp() -> Object:
	return p.get("inp") as Object


func _stick(v: Vector2) -> void:
	var inp := _inp()
	inp.set("_r_stick", v)
	if v.distance_to(_last_stick) > 0.05:
		_last_stick = v
		events.append({"f": frame, "stick": [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]})


func _hold(action: String, frames: int) -> void:
	var hf: Dictionary = _inp().get("_hold_frames")
	hf[action] = frames
	events.append({"f": frame, "hold": action, "frames": frames})


func _held(action: String) -> bool:
	var hf: Dictionary = _inp().get("_hold_frames")
	return int(hf.get(action, 0)) > 0


## World-space steering: stick up = world -Z, right = +X. Routes around chimneys (and the terrace) on the way.
func _move_to(target: Vector3, stop_r: float = 0.3, speed: float = 1.0) -> bool:
	if _grounded():
		var way := _detour(p.global_position, target)
		if way != Vector3.INF:
			var dd := way - p.global_position
			dd.y = 0.0
			var nn := dd.normalized()
			_stick(Vector2(nn.x, -nn.z) * speed)
			return false
	var d := target - p.global_position
	d.y = 0.0
	var dist := d.length()
	if dist <= stop_r:
		_stick(Vector2.ZERO)
		return true
	var mag := clampf(dist / 1.5, 0.35, 1.0) * speed
	var n := d / dist
	_stick(Vector2(n.x, -n.z) * mag)
	return false


func _detour(a: Vector3, b: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_k := 2.0
	var obstacles: Array = []
	for c in arena.chimneys.values():
		var ch := c as BossChimney
		obstacles.append([ch.global_position, 2.75 if not ch.smashed else 2.3])
	if boss.phase == 3 and not boss.defeated:
		obstacles.append([Vector3.ZERO, 4.4])
	for ob in obstacles:
		var cp: Vector3 = ob[0]
		var r: float = ob[1]
		if Vector2(b.x - cp.x, b.z - cp.z).length() < r:
			continue
		if not _blocked_by(cp, a, b, r):
			continue
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var k := clampf(Vector2(cp.x - a.x, cp.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if k >= best_k:
			continue
		best_k = k
		var perp := Vector3(-ab.y, 0, ab.x).normalized()
		var side := 1.0 if perp.dot(a - cp) > 0.0 else -1.0
		best = cp + perp * side * (r + 0.9)
	return best


func _grounded() -> bool:
	return bool(p.get("grounded"))


func _vy() -> float:
	return float(p.get("vy"))


func _state() -> String:
	return String(p.call("get_state_name"))


func _jump(frames: int = 12) -> void:
	if frame - _jumped_at < 8:
		return
	_jumped_at = frame
	_hold("jump", frames)


func _slam() -> void:
	_hold("crouch", 2)


func _physics_process(delta: float) -> void:
	if arena == null or _done:
		return
	p = arena.player
	boss = arena.boss
	if p == null or boss == null:
		return
	frame += 1
	t += delta
	var inp := _inp()
	inp.set("replay_active", true)
	inp.set("steer_world", true)
	var g := _grounded()
	if g and not _was_grounded:
		_land_count += 1
	_was_grounded = g
	if not _phase_seen.has(boss.phase):
		_phase_seen[boss.phase] = snappedf(t, 0.01)
	if t > _timeout:
		_finish("timeout")
		return
	if paused or get_tree().paused:
		_stick(Vector2.ZERO)
		return
	if boss.defeated:
		_play_defeat()
		return
	match boss.phase:
		1:
			_play_p1()
		2:
			_play_p2()
		3:
			_play_p3()


# ------------------------------------------------------------------ P1

func _play_p1() -> void:
	var k := boss._cur_step_kind() if boss.state == "p1" else ""
	if mode_pop and not _pop_done and not boss._guarded and (boss.state == "p1_open" or boss.state == "p1_hurt" or k == "inhale" or k == "hop_back"):
		# Pop the Bellows: wait ON the terrace beside the wolf's stand (he inhales right after hopping back), then
		# jump-kick the ballooning chest during the inhale.
		var chest := Vector3(0, 0, -13.0)
		var wait := Vector3(1.6, 1.0, -11.2)
		if debug and frame % 6 == 0:
			print("[BossBot] f%d pop k=%s st_b=%s mak=%s st=%s vy=%.1f g=%s" % [frame, k, boss.state, str(p.global_position.snapped(Vector3.ONE * 0.01)), _state(), _vy(), str(_grounded())])
		var on_terrace := p.global_position.y > 0.7
		if _grounded() and not on_terrace:
			_move_to(wait, 0.2)
			var tc := Vector2(p.global_position.x, p.global_position.z + 15.0).length()
			if tc < 6.0:
				_jump(12)
			return
		if k != "inhale":
			_move_to(wait, 0.2)
			return
		if _grounded():
			_move_to(chest, 0.0)
			if Vector2(p.global_position.x - chest.x, p.global_position.z - chest.z).length() < 2.9:
				_jump(14)
		else:
			_move_to(chest, 0.0)
			if Vector2(p.global_position.x - chest.x, p.global_position.z - chest.z).length() < 2.6 and p.global_position.y > 1.9 and _state() != "jump_kick":
				_hold("attack", 2)
		return
	if boss.state == "raspberry":
		_pop_done = true
	var attack := (k == "pant") or (k == "hop_down" and boss.step_t > 0.45)
	if attack:
		var head := boss.global_position + boss.facing * 0.35
		if boss.state == "p1" and k == "hop_down":
			head = boss.pant_spot + boss.facing * 0.35
		_attack_from_air(head, 2.2, 1.9, 0.75)
		return
	_air_slam_armed = false
	# Hide: the far band of the nearest chimney's lee (3.2-6.0 m along the lee bearing is safe from the sweep).
	var best := Vector3.ZERO
	var bd := 1e9
	for id in WolfRooftop.CHIMNEYS.keys():
		var c: Vector3 = WolfRooftop.CHIMNEYS[id]
		var spot := c + WolfRooftop.bearing_dir(float(WolfRooftop.LEE[id])) * (4.3 if boss.hits >= 1 else 3.6)
		var dd := spot.distance_to(p.global_position)
		if boss.hits >= 1 and (id == "C1" or id == "C4"):
			dd -= 6.0
		if dd < bd:
			bd = dd
			best = spot
	_plan = "hide"
	_move_to(best, 0.25)


## Approach a target, jump at it, and slam/stomp from above.
func _attack_from_air(target: Vector3, jump_r: float, top_y: float, slam_r: float) -> void:
	var d := target - p.global_position
	d.y = 0.0
	var flat := d.length()
	if debug and frame % 15 == 0:
		print("[BossBot] f%d atk target=%s mak=%s st=%s flat=%.2f g=%s vy=%.1f" % [frame, str(target.snapped(Vector3.ONE * 0.01)), str(p.global_position.snapped(Vector3.ONE * 0.01)), _state(), flat, str(_grounded()), _vy()])
	if _grounded():
		_air_slam_armed = false
		if flat < jump_r and frame - _jumped_at > 20:
			_move_to(target, 0.0)
			_jump(14)
			_air_slam_armed = true
		else:
			_move_to(target, 0.0)
		return
	_move_to(target, 0.05, 0.9)
	if _air_slam_armed and flat < slam_r and p.global_position.y > top_y - 0.2 and _vy() < 2.0 and _state() != "ham_slam":
		_slam()
		_air_slam_armed = false


# ------------------------------------------------------------------ P2

func _play_p2() -> void:
	if debug and frame % 10 == 0:
		print("[BossBot] f%d p2 b=%s mak=%s st=%s vy=%.1f g=%s wolf=%s face=%s" % [frame, boss.state, str(p.global_position.snapped(Vector3.ONE * 0.01)), _state(), _vy(), str(_grounded()), str(boss.global_position.snapped(Vector3.ONE * 0.01)), str(boss.facing.snapped(Vector3.ONE * 0.01))])
	match boss.state:
		"stuck":
			var tail := boss.global_position - boss.facing * 1.2
			var ch := boss.stuck_chimney
			if mode_chimney and ch != null and not ch.smashed:
				_down_the_chimney(ch)
				return
			# Go around the chimney if it stands between Mak and the tail.
			if ch != null and _blocked_by(ch.global_position, p.global_position, tail, 2.6):
				var perp := Vector3(-boss.facing.z, 0, boss.facing.x)
				var side := 1.0 if perp.dot(p.global_position - ch.global_position) > 0.0 else -1.0
				_move_to(ch.global_position + perp * side * 3.4 - boss.facing * 1.0, 0.6)
				return
			_attack_from_air(tail, 1.8, 1.6, 0.7)
		"teeter":
			var back := boss.global_position - boss.facing * 1.3
			if _move_to(back, 1.0):
				_hold("attack", 2)
		_:
			_air_slam_armed = false
			# Bait: stand behind the nearest chimney with the wolf on the far side.
			var best: BossChimney = null
			var bd := 1e9
			for c in arena.chimneys.values():
				var ch := c as BossChimney
				var dd := ch.global_position.distance_to(p.global_position) + ch.global_position.distance_to(boss.global_position) * 0.3
				if dd < bd:
					bd = dd
					best = ch
			if best == null:
				return
			var away := best.global_position - boss.global_position
			away.y = 0.0
			var spot := best.global_position + away.normalized() * 3.3
			if Vector2(spot.x, spot.z).length() > 16.0:
				spot = best.global_position + (spot - best.global_position).normalized() * 2.6
			_plan = "bait"
			if boss.state == "charge":
				_stick(Vector2.ZERO)
			else:
				_move_to(spot, 0.3)


## Down the Chimney: onto the plinth on the side away from the wolf, backflip to the crown, Ham Slam it.
func _down_the_chimney(ch: BossChimney) -> void:
	var c := ch.global_position
	var u := boss.facing
	var pos := p.global_position
	var back_ground := c + u * 2.9
	var back_plinth := c + u * 1.45
	if debug and frame % 6 == 0:
		print("[BossBot] f%d chim mak=%s st=%s vy=%.1f g=%s bf=%d c=%s u=%s" % [frame, str(pos.snapped(Vector3.ONE * 0.01)), _state(), _vy(), str(_grounded()), _bf_t, str(c.snapped(Vector3.ONE * 0.01)), str(u.snapped(Vector3.ONE * 0.01))])
	if _grounded():
		if pos.y < 0.9:
			if pos.distance_to(back_ground) < 1.2:
				# Run-up hop onto the plinth (toward the stack), not straight up.
				_move_to(back_plinth, 0.0)
				_jump(14)
			else:
				_move_to(back_ground, 0.5)
		elif pos.y < 2.0:
			# On the plinth: face away from the stack and backflip (crouch, then jump).
			if not _move_to(back_plinth, 0.25, 0.6):
				return
			if _bf_t < 0:
				_bf_t = frame
				_stick(Vector2(u.x, -u.z) * 0.2)
			if frame - _bf_t == 3:
				_stick(Vector2.ZERO)
				_hold("crouch", 14)
			if frame - _bf_t == 8:
				_hold("jump", 14)
			if frame - _bf_t > 40:
				_bf_t = -1
	else:
		_bf_t = -1
		if pos.y <= 3.0 and _vy() > -2.0 and pos.y < 1.3:
			_move_to(back_plinth, 0.05, 0.8)
		if pos.y > 3.0:
			_move_to(c, 0.05, 0.7)
			if pos.y > 4.7 and _vy() < 0.0 and Vector2(pos.x - c.x, pos.z - c.z).length() < 0.8 and _state() != "ham_slam":
				_slam()


func _blocked_by(c: Vector3, a: Vector3, b: Vector3, r: float) -> bool:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var l := ab.length_squared()
	if l < 0.01:
		return false
	var k := clampf(ac.dot(ab) / l, 0.0, 1.0)
	var closest := Vector2(a.x, a.z) + ab * k
	return closest.distance_to(Vector2(c.x, c.z)) < r and k > 0.05 and k < 0.95


# ------------------------------------------------------------------ P3

func _play_p3() -> void:
	var st := _state()
	var pos := p.global_position
	if boss.state == "p3_tell" or boss.updraft != "" and boss.updraft != "miss":
		# Air phase: drift to the axis and slam from above.
		_move_to(Vector3.ZERO, 0.05, 1.0)
		if not _grounded() and Vector2(pos.x, pos.z).length() < 0.9 and pos.y > 4.2 and _vy() < 0.0 and st != "ham_slam":
			_slam()
		return
	if _grounded():
		_launched = false
	elif _vy() > 14.0:
		_launched = true
	if debug and frame % 20 == 0:
		print("[BossBot] f%d p3 mak=%s st=%s vy=%.1f launched=%s vent=%s bstate=%s" % [frame, str(pos.snapped(Vector3.ONE * 0.01)), st, _vy(), str(_launched), boss.active_vent.vid if boss.active_vent != null else "-", boss.state])
	if not _grounded() and _launched:
		if debug and frame % 6 == 0:
			print("[BossBot] f%d fly mak=%s st=%s vy=%.1f r=%.2f bst=%s" % [frame, str(pos.snapped(Vector3.ONE * 0.01)), st, _vy(), Vector2(pos.x, pos.z).length(), boss.state])
		# Launched off a plug: drift in, slam the head.
		_move_to(Vector3.ZERO, 0.05, 1.0)
		if Vector2(pos.x, pos.z).length() < 0.9 and _vy() < 0.0 and pos.y > 4.0 and st != "ham_slam":
			_slam()
		return
	var v := boss.active_vent
	if v == null or boss.state != "p3":
		# Wait at r 6 away from the typhoon.
		var away := Vector3.ZERO
		if boss.typhoon != null:
			away = -boss.typhoon.global_position
		away.y = 0
		_move_to(away.normalized() * 6.0 if away.length() > 0.1 else Vector3(0, 0, 6), 0.4)
		return
	var vp := v.global_position
	var d := vp - pos
	d.y = 0.0
	if _grounded():
		_move_to(vp, 0.0, 0.7 if d.length() < 3.0 else 1.0)
		# Hop at the plug from a little way out and slam onto it (stepping on it only gives the dud puff).
		if d.length() < 1.9 and d.length() > 0.5 and frame - _jumped_at > 30:
			_jump(9)
		_air_slam_armed = true
	else:
		_move_to(vp, 0.05, 1.0)
		if _air_slam_armed and d.length() < 1.2 and _vy() < 0.5 and pos.y < 3.4 and pos.y > 0.6 and st != "ham_slam":
			_slam()
			_air_slam_armed = false


# ------------------------------------------------------------------ defeat

func _play_defeat() -> void:
	match boss.state:
		"wedged":
			_defeat_t += get_physics_process_delta_time()
			var c := boss.cork.global_position
			var u := boss.cork_u
			var side := Vector3(-u.z, 0, u.x)
			var ground_spot := c + side * 2.9 + u * 0.9
			var plinth_spot := c + u * 1.52
			var pos := p.global_position
			if debug and frame % 10 == 0:
				print("[BossBot] f%d cork mak=%s st=%s vy=%.1f g=%s" % [frame, str(pos.snapped(Vector3.ONE * 0.01)), _state(), _vy(), str(_grounded())])
			if _grounded():
				_air_slam_armed = true
				if pos.y < 0.9:
					_from_plinth = false
					if _move_to(ground_spot, 0.5):
						_jump(14)
				else:
					_from_plinth = true
					var rel := pos - c
					var u_l := rel.x * u.x + rel.z * u.z
					var s_l := rel.x * side.x + rel.z * side.z
					if u_l < 1.3:
						_from_plinth = false
						_move_to(c + side * signf(s_l if absf(s_l) > 0.01 else 1.0) * 1.47 + u * 1.5, 0.1)
						return
					var there := _move_to(plinth_spot, 0.3, 1.0)
					if there and frame - _jumped_at > 20:
						_jump(16)
			else:
				var tgt := boss.belly if _from_plinth else c + side * 1.47 + u * 1.5
				if _from_plinth and pos.y < 2.7 and _vy() > 0.0:
					_stick(Vector2.ZERO)
				else:
					_move_to(tgt, 0.05, 1.0)
				if _air_slam_armed and pos.y > boss.belly.y + 0.3 and _vy() < 0.0 and Vector2(pos.x - boss.belly.x, pos.z - boss.belly.z).length() < 1.3 and _state() != "ham_slam":
					_slam()
					_air_slam_armed = false
		"popped", "swell", "drift":
			if boss.state == "popped" and boss.st > 1.8:
				var tr := arena.get_node_or_null("GreatTruffle") as Node3D
				if tr != null:
					_move_to(tr.global_position, 0.0)
				else:
					_stick(Vector2.ZERO)
			else:
				_move_to(Vector3(0, 0, 6), 0.5)
		_:
			_stick(Vector2.ZERO)
	var g := get_node_or_null("/root/Game")
	if g != null and bool(g.call("has_truffle", "BOSS-1")) and not _result.has("truffle_t"):
		_result["truffle_t"] = snappedf(t, 0.01)
		# The outro (3.5 s cine) hands control to the Router (back to the hub), which frees this node: report first.
		get_tree().create_timer(2.0, true).timeout.connect(func() -> void: _finish("complete"))


func _finish(why: String) -> void:
	if _done:
		return
	_done = true
	_stick(Vector2.ZERO)
	var g := get_node_or_null("/root/Game")
	var hits: Array = boss.stats["hits"]
	var by_phase := {1: [], 2: [], 3: []}
	for h in hits:
		(by_phase[int(h["phase"])] as Array).append(String(h["what"]))
	var events_boss: Array = boss.stats["events"]
	var ev_text: Array = []
	for e in events_boss:
		ev_text.append(String(e["e"]))
	var popped_by := "fallback" if ev_text.has("cork fallback") else ("belly slam" if ev_text.has("POP") else "none")
	var res := {
		"utc": Time.get_datetime_string_from_system(true),
		"why": why,
		"seconds": snappedf(t, 0.01),
		"fight_time": snappedf(boss.fight_time, 0.01),
		"real_player": p.get_script() != null and String(p.get_script().resource_path).ends_with("mak_player.gd"),
		"phases_seen": _phase_seen,
		"hits_p1": by_phase[1],
		"hits_p2": by_phase[2],
		"hits_p3": by_phase[3],
		"popped_by": popped_by,
		"has_truffle_BOSS_1": g != null and bool(g.call("has_truffle", "BOSS-1")),
		"top_hat_unlocked": g != null and bool(g.call("is_unlocked", "golden_top_hat")),
		"slices_lost": boss.stats["slices_lost"],
		"falls": boss.stats["falls"],
		"boss_events": events_boss,
	}
	var checks := {
		"P1 two pant hits": (by_phase[1] as Array).size() == 2 and String(by_phase[1][0]).begins_with("pant"),
		"Pop the Bellows (when asked)": (not mode_pop) or ev_text.has("POP THE BELLOWS"),
		"Down the Chimney (when asked)": (not mode_chimney) or (by_phase[2] as Array).has("down the chimney"),
		"P2 two tail slams or teeter": (by_phase[2] as Array).size() == 2,
		"P3 two head slams": (by_phase[3] as Array).size() == 2,
		"cork popped by belly slam": popped_by == "belly slam",
		"BOSS-1 collected": res["has_truffle_BOSS_1"],
		"golden_top_hat unlocked": res["top_hat_unlocked"],
	}
	var passed := 0
	for k in checks.keys():
		if bool(checks[k]):
			passed += 1
	res["checks"] = checks
	res["passed"] = "%d/%d" % [passed, checks.size()]
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var dir := ProjectSettings.globalize_path("res://").path_join("../Docs/progress/boss").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("%sZ__bosstest_realplayer_results.json" % stamp), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	var f2 := FileAccess.open(dir.path_join("%sZ__bosstest_realplayer_inputs.json" % stamp), FileAccess.WRITE)
	if f2 != null:
		f2.store_string(JSON.stringify({"fps": 60, "steer": "world", "note": "inputs the scripted player fed into MakInput; reactive to the boss, so a static replay of these frames diverges", "events": events}))
		f2.close()
	print("[BossBot] DONE (%s) %s  %s" % [why, res["passed"], JSON.stringify(checks)])
	var dev := get_node_or_null("/root/Dev")
	if dev == null or not bool(dev.call("has_arg", "bosstest-hold")):
		get_tree().create_timer(0.5, true).timeout.connect(func() -> void: get_tree().quit())
