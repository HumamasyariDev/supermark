extends Node
## W3 test bot (dev only): closed-loop input for truffle reachability checks. Activated by
## `--w3-bot=<plan>` together with a replay file (`--replay=...` with "steer": "world"), because it drives
## MakPlayer through its replay input layer (MakInput._r_stick / _hold_frames), exactly like recorded input.
## Every step and the result are printed as "[W3 bot] ..." lines for the evidence log.

var plan: Array = []
var step := 0
var pl: Node3D
var _frames := 0
var _step_frames := 0
var _hop_phase := 0
var _done := false
var _timeout := 60.0
var _name := ""
var _tnode: Node3D
var _tprev := Vector3.INF
var _tvel := Vector3.ZERO
var _hurts := 0
var _was_hurt := false
const G := 28.0


func setup(plan_name: String, steps: Array, timeout_s: float = 60.0) -> void:
	_name = plan_name
	plan = steps
	_timeout = timeout_s
	process_physics_priority = -100


func _physics_process(delta: float) -> void:
	if _done:
		return
	if pl == null or not is_instance_valid(pl):
		pl = get_tree().get_first_node_in_group("player") as Node3D
		return
	var inp: Object = pl.get("inp")
	if inp == null or not bool(inp.get("replay_active")):
		return
	_frames += 1
	_step_frames += 1
	if _frames > int(_timeout * 60.0):
		_finish("TIMEOUT at step %d" % step)
		return
	if step >= plan.size():
		_finish("PLAN COMPLETE")
		return
	var s: Dictionary = plan[step]
	var p := pl.global_position
	var vel: Vector3 = pl.get("velocity")
	var grounded := bool(pl.get("grounded"))
	# Count every hit (hurt state entered) so a "pass" that relied on a damage throw is visible in the result.
	var hurt_now := String(pl.call("get_state_name")).begins_with("hurt")
	if hurt_now and not _was_hurt:
		_hurts += 1
		print("[W3 bot] %s HURT at %s (frame %d, step %d)" % [_name, p, _frames, step])
	_was_hurt = hurt_now
	var kind := String(s.get("do", ""))
	match kind:
		"teleport":
			var at: Vector3 = s["at"]
			var yaw := deg_to_rad(float(s.get("yaw", 0.0)))
			if pl.has_method("respawn"):
				pl.call("respawn", Transform3D(Basis(Vector3.UP, yaw), at))
			_stick(inp, Vector2.ZERO)
			_next("teleport %s" % at)
		"wait":
			_stick(inp, s.get("stick", Vector2.ZERO))
			if _step_frames >= int(s.get("frames", 30)):
				_next("wait")
		"goto":
			var t: Vector3 = s["at"]
			var d := Vector2(t.x - p.x, t.z - p.z)
			var tol := float(s.get("tol", 0.5))
			if d.length() < tol:
				if bool(s.get("stop", false)):
					_stick(inp, Vector2.ZERO)
				_next("goto %s reached at %s" % [t, p])
				return
			var mag := clampf(d.length() / 1.5, float(s.get("min_mag", 0.35)), float(s.get("mag", 1.0)))
			_stick(inp, Vector2(d.x, -d.y).normalized() * mag)
			if _step_frames > int(float(s.get("max_s", 12.0)) * 60.0):
				_finish("FAIL goto %s stuck at %s" % [t, p])
		"press":
			var hf: Dictionary = inp.get("_hold_frames")
			hf[String(s["action"])] = int(s.get("frames", 12))
			if s.has("stick"):
				_stick(inp, s["stick"])
			_next("press %s" % s["action"])
		"hop":
			_hop(inp, s, p, vel, grounded)
		"until_y_below":
			if p.y < float(s["y"]):
				_next("y below %.2f at %s" % [float(s["y"]), p])
		"until_grounded":
			if s.has("stick"):
				_stick(inp, s["stick"])
			if grounded and _step_frames > 3:
				_next("grounded at %s state=%s" % [p, pl.call("get_state_name")])
		"until_truffle":
			if ObjSvc.has_truffle(String(s["id"])):
				_next("truffle %s collected" % s["id"])
			elif _step_frames > int(float(s.get("max_s", 10.0)) * 60.0):
				_finish("FAIL truffle %s not collected; at %s" % [s["id"], p])
		"ride_until_royal":
			var royal := get_parent().get_node_or_null("Lagoon/RoyalDigestive") as Node3D
			if _tnode == null or not is_instance_valid(_tnode) or royal == null:
				_finish("FAIL ride_until_royal: missing node")
				return
			var np := _tnode.global_position
			var dd := Vector2(np.x - p.x, np.z - p.z)
			_stick(inp, Vector2(dd.x, -dd.y) * 0.6 if dd.length() > 0.3 else Vector2.ZERO)
			if np.x >= royal.global_position.x + float(s.get("dx", 0.4)):
				_tnode = royal
				_next("alongside royal at %s (royal %s)" % [p, royal.global_position])
			elif _step_frames > 600:
				_finish("FAIL never alongside royal; biscuit %s royal %s" % [np, royal.global_position])
		"sniff":
			var hf2: Dictionary = inp.get("_hold_frames")
			hf2["sniff"] = 2
			_stick(inp, Vector2.ZERO)
			if _step_frames >= int(s.get("frames", 45)):
				var st: Variant = pl.get("sniff_target")
				var nm: String = String((st as Node).name) if st is Node else "none"
				var sp: Vector3 = (st as Node3D).global_position if st is Node3D else Vector3.ZERO
				_next("sniff target=%s at %s (state %s)" % [nm, sp, pl.call("get_state_name")])
		"follow_scent":
			# Walk to wherever the current sniff target (maze scent) points, until it is gone or `until` reached.
			var sc := get_parent().get_node_or_null("Woods/Maze/MazeScent") as Node3D
			var goal: Vector3 = s["until"]
			if Vector2(goal.x - p.x, goal.z - p.z).length() < 1.0:
				_next("follow_scent reached %s" % p)
				return
			var tgt := goal
			if sc and sc.visible:
				tgt = sc.global_position
			var d := Vector2(tgt.x - p.x, tgt.z - p.z)
			_stick(inp, Vector2(d.x, -d.y).normalized() * clampf(d.length() / 1.2, 0.45, 1.0))
			if _step_frames > 60 * 60:
				_finish("FAIL follow_scent timeout at %s" % p)
		"follow_slide":
			var c: PackedVector3Array = get_parent().get("_slide_c")
			var bi := 0
			var bd := 1e9
			for i in c.size():
				var dd2 := Vector2(c[i].x - p.x, c[i].z - p.z).length_squared()
				if dd2 < bd:
					bd = dd2
					bi = i
			var ahead := c[mini(bi + int(s.get("ahead", 5)), c.size() - 1)]
			# Joust lanes: "boost" steers onto the outer-half boost strips, "lat" holds a fixed half.
			var jo: Node = get_parent().get("_joust")
			var lat := float(s.get("lat", 0.0))
			if bool(s.get("boost", false)) and jo:
				lat = float(jo.call("bot_lat", float(jo.get("pa"))))
			if absf(lat) > 0.01:
				var ai := mini(bi + int(s.get("ahead", 5)), c.size() - 1)
				var f3 := c[ai] - c[maxi(ai - 1, 0)]
				f3.y = 0.0
				f3 = f3.normalized()
				ahead += Vector3(-f3.z, 0, f3.x) * lat
			var d := Vector2(ahead.x - p.x, ahead.z - p.z)
			_stick(inp, Vector2(d.x, -d.y).normalized())
			if not s.has("_t0"):
				s["_t0"] = _frames
			if bool(s.get("dive", true)) and not s.has("_dived") and float(pl.get("forward_speed")) > 6.2 and grounded:
				s["_dived"] = true
				(inp.get("_hold_frames") as Dictionary)["attack"] = 3
				print("[W3 bot] dive at %s speed %.1f" % [p, float(pl.get("forward_speed"))])
			var jo2: Node = get_parent().get("_joust")
			if bool(s.get("end_on_escape", false)) and jo2 and String(jo2.get("state")) in ["over", "rearm"]:
				_next("joust lost (crumb_escape) at %s" % p)
				return
			if bi >= c.size() - 2:
				_next("slide end reached at %s after %.2f s" % [p, (_frames - int(s["_t0"])) / 60.0])
			elif p.y < 0.5 or _step_frames > 60 * 40:
				_finish("FAIL follow_slide at %s" % p)
		"collect_acorns":
			# Teleport onto acorn after acorn until the visit count reaches `n` (W3-100 test).
			if ObjSvc.acorns_this_visit() >= int(s.get("n", 100)):
				_stick(inp, Vector2.ZERO)
				_next("acorns=%d at %s" % [ObjSvc.acorns_this_visit(), p])
				return
			if _step_frames % 5 == 1:
				var list := get_parent().find_children("*", "Acorn", true, false)
				for a in list:
					if a is Node3D and not bool(a.get("is_collected")):
						pl.call("respawn", Transform3D(Basis(), (a as Node3D).global_position - Vector3(0, 0.4, 0)))
						break
		"until_y_above":
			_stick(inp, Vector2.ZERO)
			if p.y > float(s["y"]):
				_next("y above %.1f at %s" % [float(s["y"]), p])
			elif _step_frames > int(float(s.get("max_s", 5.0)) * 60.0):
				_finish("FAIL never above y %.1f; at %s" % [float(s["y"]), p])
		"wait_oven_cold":
			_stick(inp, Vector2.ZERO)
			var lv := get_parent()
			if String(lv.get("_oven_state")) == "cold" and float(lv.get("_oven_t")) < 0.25:
				_next("oven cold window at t=%.2f" % float(lv.get("_oven_t")))
		"backflip":
			var hf3: Dictionary = inp.get("_hold_frames")
			_stick(inp, Vector2.ZERO)
			if _step_frames == 1:
				hf3["crouch"] = 26
			if _step_frames == 8:
				hf3["jump"] = 14
			if _step_frames > 12 and String(pl.call("get_state_name")) == "backflip":
				_next("backflip started at %s" % p)
			elif _step_frames > 60:
				_finish("FAIL no backflip; state %s" % pl.call("get_state_name"))
		"stomp_enemy":
			# Stomp an enemy (by id in the level's `enemies` dictionary) until it is defeated.
			var ev: Variant = (get_parent().get("enemies") as Dictionary).get(String(s["id"]))
			if ev == null or not is_instance_valid(ev):
				_next("%s defeated (freed) at %s" % [s["id"], p])
				return
			var en := ev as Node3D
			var dead := not en.is_inside_tree() or String(en.call("get_state_name") if en.has_method("get_state_name") else "") in ["defeated", "dead"]
			if not dead and en.get("hp") != null and int(en.get("hp")) <= 0:
				dead = true
			if dead:
				_next("%s defeated (at %s)" % [s["id"], p])
				return
			if _step_frames > int(float(s.get("max_s", 40.0)) * 60.0):
				_finish("FAIL could not stomp %s; it is at %s, Mak at %s" % [s["id"], en.global_position, p])
				return
			_tnode = en
			var ep := en.global_position
			var dd := Vector2(ep.x - p.x, ep.z - p.z)
			if grounded:
				s["_air"] = false
				if dd.length() > float(s.get("jump_at", 2.4)):
					_stick(inp, Vector2(dd.x, -dd.y).normalized())
				else:
					(inp.get("_hold_frames") as Dictionary)["jump"] = 14
					_stick(inp, Vector2(dd.x, -dd.y).normalized())
			else:
				_air_control(inp, {"top_off": float(s.get("head", 1.4))}, p, vel)
		"long_jump":
			# Run along `dir`; at `at` (crossing the plane) press crouch + jump together (long jump).
			var dr: Vector2 = s["dir"]
			var lp: Vector3 = s["at"]
			_stick(inp, Vector2(dr.x, -dr.y))
			var along := Vector2(p.x - lp.x, p.z - lp.z).dot(dr)
			if along >= 0.0 and not s.has("_go"):
				s["_go"] = true
				var hfl: Dictionary = inp.get("_hold_frames")
				hfl["crouch"] = 10
				hfl["jump"] = 14
				print("[W3 bot] long jump take-off at %s speed %.1f" % [p, float(pl.get("forward_speed"))])
			if s.has("_go") and _step_frames > 2 and String(pl.call("get_state_name")) == "long_jump":
				_next("long jump in the air at %s" % p)
			elif _step_frames > 600:
				_finish("FAIL long jump never started at %s state %s" % [p, pl.call("get_state_name")])
		"leapfrog":
			_leapfrog(inp, s, p, vel, grounded)
		"hop_royal":
			s["node"] = true
			s["top_off"] = 0.2
			_hop(inp, s, p, vel, grounded)
		"steer":
			_stick(inp, s["stick"])
			if _step_frames >= int(s.get("frames", 1)):
				_next("steer")
		"mark":
			_next(String(s.get("text", "mark")))
		"fort_wait":
			# Wait until the W3-2 controller reaches a phase (and optional sub-state).
			var fort := get_parent().get_node_or_null("FortEncounter")
			if fort == null:
				_finish("FAIL fort_wait: no FortEncounter")
				return
			_stick(inp, s.get("stick", Vector2.ZERO))
			var ok := int(fort.get("phase")) >= int(s.get("phase", 0))
			if s.has("subs"):
				ok = ok and String(fort.get("_sub")) in (s["subs"] as Array)
			if ok:
				_next("fort phase %d sub %s (snap at %s)" % [int(fort.get("phase")), fort.get("_sub"), (fort.get("_snap") as Node3D).global_position])
			elif _step_frames > int(float(s.get("max_s", 20.0)) * 60.0):
				_finish("FAIL fort_wait phase %s sub %s; fort phase %d sub %s" % [s.get("phase"), s.get("subs"), int(fort.get("phase")), fort.get("_sub")])
		"stomp_until":
			# Stomp the enemy `id` until the fort reaches `phase` (or is won).
			var fort2 := get_parent().get_node_or_null("FortEncounter")
			var en2 := (get_parent().get("enemies") as Dictionary).get(String(s["id"])) as Node3D
			if fort2 == null or en2 == null:
				_finish("FAIL stomp_until: missing node")
				return
			if bool(fort2.get("_won")) or int(fort2.get("phase")) >= int(s.get("phase", 99)):
				_next("fort phase %d hits %d won=%s (stomping %s)" % [int(fort2.get("phase")), int(fort2.get("hits")), fort2.get("_won"), s["id"]])
				return
			if _step_frames > int(float(s.get("max_s", 30.0)) * 60.0):
				_finish("FAIL stomp_until %s phase %s; fort phase %d sub %s snap state %s" % [s["id"], s.get("phase"), int(fort2.get("phase")), fort2.get("_sub"), en2.get("state")])
				return
			_tnode = en2
			var ep2 := en2.global_position
			var dd2 := Vector2(ep2.x - p.x, ep2.z - p.z)
			if grounded:
				if dd2.length() > float(s.get("jump_at", 2.4)):
					_stick(inp, Vector2(dd2.x, -dd2.y).normalized())
				else:
					(inp.get("_hold_frames") as Dictionary)["jump"] = 14
					_stick(inp, Vector2(dd2.x, -dd2.y).normalized())
			else:
				_air_control(inp, {"top_off": float(s.get("head", 1.8))}, p, vel)
		"brute_bounce":
			# W3-1 finale (R3.6): dodge the stalker's hop-slam, jump on its wobbling back, ride the bounce into the nest.
			var br := (get_parent().get("enemies") as Dictionary).get(String(s["id"])) as Node3D
			var goal: Vector3 = s["to"]
			if br == null:
				_finish("FAIL brute_bounce: no brute")
				return
			if grounded and p.y > goal.y - 0.6:
				_next("landed high at %s (goal %s)" % [p, goal])
				return
			if _step_frames > int(float(s.get("max_s", 40.0)) * 60.0):
				_finish("FAIL brute_bounce: Mak %s brute %s state %s" % [p, br.global_position, br.get("state")])
				return
			var bst := String(br.get("state"))
			var bp := br.global_position
			var db := Vector2(bp.x - p.x, bp.z - p.z)
			if _step_frames % 120 == 1:
				print("[W3 bot] brute %s t=%.1f at %s, Mak %s %s, onscreen %.2f" % [bst, float(br.get("state_time")), bp.snapped(Vector3(0.1, 0.1, 0.1)), p.snapped(Vector3(0.1, 0.1, 0.1)), pl.call("get_state_name"), float(br.get("_onscreen_t"))])
			if not grounded:
				if p.y > bp.y + 2.4 and vel.y > -2.0:
					# Completion pass: the nest (r 1.6, underside y 10.6) sits right over the trunk, so steering in
					# while rising bonked Mak's head on its underside (apex stuck at 9.3 for 20 bounces). Stay outside
					# its rim (2.3 m from the trunk) until the feet clear the rim top (11.0), then drift in.
					var dg := Vector2(goal.x - p.x, goal.z - p.z)
					if p.y < goal.y + 0.3 and dg.length() < 2.3:
						_stick(inp, Vector2(-dg.x, dg.y).normalized() * 0.6)
					elif p.y < goal.y + 0.3:
						_stick(inp, Vector2.ZERO)
					else:
						_stick(inp, Vector2(dg.x, -dg.y).normalized() * clampf(dg.length() / 1.2, 0.0, 1.0))
				else:
					# Completion pass: airborne before any recover-hop (knocked up by the slam, or a jump off the
					# trunk) left _tnode null and crashed _air_control every frame; aim at the brute's back.
					_tnode = br
					_air_control(inp, {"top_off": 1.5}, p, vel)
				return
			if bst == "windup" or bst == "attack":
				# Completion pass: the stalker's hop locks onto Mak's spot 0.6 s into the wind-up and lands there (the
				# 1.3 m disc); the old perpendicular sidestep "toward the trunk" ran into the trunk and was landed on
				# (hurt three times, then a fall back to the start). Wait out the aim near the trunk, then run straight
				# out of the disc and stop about 3.5 m from it, ready for the recover window.
				var jtv: Variant = br.get("_jump_to")
				var jt: Vector3 = jtv if jtv is Vector3 and (bst == "attack" or float(br.get("state_time")) >= 0.6) else p
				var away := Vector2(p.x - jt.x, p.z - jt.z)
				if away.length() < 0.05:
					away = Vector2(p.x - goal.x, p.z - goal.z)
					if away.length() < 0.05:
						away = Vector2(1, 0)
				if jt == p:
					_stick(inp, Vector2.ZERO)
				elif away.length() < 3.5:
					_stick(inp, Vector2(away.x, -away.y).normalized())
				else:
					_stick(inp, Vector2.ZERO)
				return
			# Its back wobbles for 1.9 s after the landing (recover); jump on from up to 3 m out.
			if bst == "recover" and db.length() < 3.0 and float(br.get("state_time")) > 0.2 and float(br.get("state_time")) < 1.5:
				_tnode = br
				(inp.get("_hold_frames") as Dictionary)["jump"] = 14
				_stick(inp, Vector2(db.x, -db.y).normalized())
				return
			# Bait outside the nest's shadow (r 1.6) so the brute lands where a bounce can clear the rim.
			var bait := Vector2(goal.x, goal.z) + Vector2(bp.x - goal.x, bp.z - goal.z).normalized() * 2.7
			var dbait := bait - Vector2(p.x, p.z)
			_stick(inp, Vector2(dbait.x, -dbait.y).normalized() * clampf(dbait.length(), 0.0, 1.0) if dbait.length() > 0.3 else Vector2.ZERO)
		"dive_trip":
			# Phase 2: run at Snap from a few metres and dive into his boots as his lance sweep winds up.
			var en3 := (get_parent().get("enemies") as Dictionary).get(String(s["id"])) as Node3D
			if en3 == null:
				_finish("FAIL dive_trip: missing enemy")
				return
			var est := String(en3.get("state"))
			if est == "tripped":
				_next("%s tripped at %s (Mak %s state %s)" % [s["id"], en3.global_position, p, pl.call("get_state_name")])
				return
			if _step_frames > int(float(s.get("max_s", 40.0)) * 60.0):
				_finish("FAIL dive_trip: %s state %s at %s, Mak at %s" % [s["id"], est, en3.global_position, p])
				return
			var d3 := Vector2(en3.global_position.x - p.x, en3.global_position.z - p.z)
			var mst := String(pl.call("get_state_name"))
			if mst in ["dive", "belly_slide", "rollout", "slide_getup", "hurt", "hurt_air", "knockback"]:
				_stick(inp, Vector2.ZERO)
				return
			if int(s.get("_back", 0)) > 0:
				s["_back"] = int(s["_back"]) - 1
				_stick(inp, Vector2(-d3.x, d3.y).normalized())
				return
			_stick(inp, Vector2(d3.x, -d3.y).normalized())
			var spd := Vector2(vel.x, vel.z).length()
			if d3.length() < 3.0 and spd >= 6.9 and grounded:
				(inp.get("_hold_frames") as Dictionary)["attack"] = 3
				print("[W3 bot] dive at %.2f m, snap state %s t=%.2f" % [d3.length(), est, float(en3.get("state_time"))])
			elif d3.length() < 2.0 and spd < 6.9:
				s["_back"] = 45   # too close and too slow: back off and take a run-up
		"wait_node":
			# Pick a moving child (e.g. a biscuit) of `path` whose x is inside [xmin, xmax].
			var root := get_parent().get_node_or_null(String(s["path"]))
			_stick(inp, Vector2.ZERO)
			if _step_frames % 120 == 1:
				var xs := []
				if root:
					for c in root.get_children():
						if c is Node3D:
							xs.append((c as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1)))
				print("[W3 bot] wait_node %s root=%s children=%s" % [s["path"], root != null, xs])
			if root:
				for c in root.get_children():
					if c is Node3D:
						var cp := (c as Node3D).global_position
						if cp.x >= float(s["xmin"]) and cp.x <= float(s["xmax"]) and absf(cp.z - float(s.get("z", cp.z))) < 1.5:
							_tnode = c
							_next("picked %s at %s" % [c.name, cp])
							return
		"ride":
			# Stand on _tnode until its x passes `x_until`, keeping centred on it.
			if _tnode == null or not is_instance_valid(_tnode):
				_finish("FAIL ride: node gone")
				return
			var np := _tnode.global_position
			var dd := Vector2(np.x - p.x, np.z - p.z)
			_stick(inp, Vector2(dd.x, -dd.y) * 0.6 if dd.length() > 0.3 else Vector2.ZERO)
			if np.x >= float(s["x_until"]):
				_next("ride done at %s (node %s)" % [p, np])
		_:
			_next("unknown step " + kind)


## Bounce/jump to a target top: aim at the next target just before landing (so a bouncy surface re-aims the
## facing), then predictive air control toward the target centre.
func _hop(inp: Object, s: Dictionary, p: Vector3, vel: Vector3, grounded: bool) -> void:
	var t: Vector3 = s["at"] if s.has("at") else Vector3.ZERO
	if bool(s.get("node", false)) and _tnode and is_instance_valid(_tnode):
		var np := _tnode.global_position
		if _tprev != Vector3.INF:
			_tvel = _tvel.lerp((np - _tprev) * 60.0, 0.3)
		_tprev = np
		t = np + Vector3(0, float(s.get("top_off", 0.35)), 0)
	var top := t.y
	var nxt: Vector3 = s.get("next", t)
	var dxz := Vector2(t.x - p.x, t.z - p.z)
	if _hop_phase == 0:
		# Wait until rising (launched).
		if pl.get("vy") != null and float(pl.get("vy")) > 1.0:
			_hop_phase = 1
		_stick(inp, Vector2(dxz.x, -dxz.y).normalized())
		if _step_frames > 90:
			_hop_phase = 1
		return
	var vy := float(pl.get("vy")) if pl.get("vy") != null else vel.y
	var aim_y := top + (float(s.get("aim_h", 2.0)) if bool(s.get("slam", false)) else 0.0)
	var disc := vy * vy + 2.0 * G * (p.y - aim_y)
	if disc < 0.0:
		# Below the target top height (still rising): steer straight at it.
		_stick(inp, Vector2(dxz.x, -dxz.y).normalized() * float(s.get("rise_mag", 1.0)))
	else:
		var tl := maxf((vy + sqrt(disc)) / G, 0.08)
		var lead := Vector2(_tvel.x, _tvel.z) * tl if bool(s.get("node", false)) else Vector2.ZERO
		var want := (dxz + lead) / tl + Vector2(_tvel.x, _tvel.z) * 0.0
		var have := Vector2(vel.x, vel.z)
		var corr := (want - have) * float(s.get("gain", 1.2))
		var st := Vector2(corr.x, -corr.y)
		if st.length() > 1.0:
			st = st.normalized()
		_stick(inp, st)
		# Pre-aim at the next target in the last frames before touching down.
		if tl < float(s.get("preaim", 0.22)) and dxz.length() < 2.2 and nxt != t:
			var dn := Vector2(nxt.x - p.x, nxt.z - p.z)
			_stick(inp, Vector2(dn.x, -dn.y).normalized())
	if vy > 5.0 and s.has("_did_slam") and bool(s.get("end_on_slam", false)):
		_next("slam rebound off %s at %s" % [t, p])
		return
	if vy > 1.0:
		s.erase("_slammed")
	if bool(s.get("slam", false)) and not s.has("_slammed") and vy < 0.0 and dxz.length() < 1.0 and p.y > top + float(s.get("slam_h", 0.8)) and String(pl.call("get_state_name")) != "ham_slam":
		s["_slammed"] = true
		s["_did_slam"] = true
		var hf: Dictionary = inp.get("_hold_frames")
		hf["crouch"] = 4
		print("[W3 bot] slam over %s at %s" % [t, p])
	if grounded and dxz.length() < 2.0 and absf(p.y - top) < 0.6:
		_next("landed on %s at %s" % [t, p])
		return
	if vy < -1.0:
		s["_desc"] = true
	var min_vy := 15.0 if bool(s.get("slam", false)) else 2.0
	if vy > min_vy and s.has("_desc") and _step_frames > 10 and absf(p.y - top) < 1.0 and dxz.length() < 1.8:
		_next("bounced off %s at %s" % [t, p])
		return
	if p.y < top - 3.0 and vy < 0.0:
		_finish("FAIL hop to %s: fell at %s" % [t, p])


## Dunk Run convoy: ride a lane biscuit, hop forward to the next one before it sinks, and hop onto the
## Royal Digestive when it is alongside. Phases kept in the step dictionary.
func _leapfrog(inp: Object, s: Dictionary, p: Vector3, vel: Vector3, grounded: bool) -> void:
	var lane := get_parent().get_node_or_null(String(s.get("lane", "Lagoon/lane_E")))
	var royal := get_parent().get_node_or_null("Lagoon/RoyalDigestive") as Node3D
	if lane == null or royal == null or _tnode == null or not is_instance_valid(_tnode):
		_finish("FAIL leapfrog: missing nodes")
		return
	var ph := String(s.get("_ph", "ride"))
	if p.y < -0.2:
		_finish("FAIL leapfrog: fell in the chocolate at %s" % p)
		return
	# W3-3 fairness pass: a hot-chocolate splash throws Mak to the bank in "hurt_air"; report it instead of
	# leapfrogging on from wherever he lands.
	if String(pl.call("get_state_name")).begins_with("hurt"):
		_finish("FAIL leapfrog: hurt (%s) at %s" % [pl.call("get_state_name"), p])
		return
	if ph == "ride":
		var np := _tnode.global_position
		var dd := Vector2(np.x - p.x, np.z - p.z)
		_stick(inp, Vector2(dd.x, -dd.y) * 0.6 if dd.length() > 0.3 else Vector2.ZERO)
		s["_t"] = float(s.get("_t", 0.0)) + 1.0 / 60.0
		var rp := royal.global_position
		# Settle 0.3 s after a landing first: a jump pressed in the landing window chains into a double jump that
		# keeps the leapfrog's eastward speed and overshot the royal by 2.5 m (fairness pass run 3).
		if grounded and float(s["_t"]) > 0.3 and Vector2(rp.x - p.x, rp.z - p.z).length() < 5.0 and rp.x < p.x + 2.0:
			s["_ph"] = "aim"
			s["_t"] = 0.0
			return
		if grounded and float(s["_t"]) > float(s.get("wait_s", 1.4)):
			var best: Node3D = null
			for c in lane.get_children():
				if c is Node3D and c != _tnode:
					var cx := (c as Node3D).global_position.x
					if cx > np.x + 2.0 and (best == null or cx < best.global_position.x):
						best = c
			if best:
				s["_next"] = best
				s["_ph"] = "back"
				s["_t"] = 0.0
	elif ph == "aim":
		# Like a player: turn and step toward the royal for 0.3 s, then hop (air control leads its drift).
		var rp := royal.global_position
		s["_t"] = float(s.get("_t", 0.0)) + 1.0 / 60.0
		var d := Vector2(rp.x - p.x, rp.z - p.z)
		_stick(inp, Vector2(d.x, -d.y).normalized() * float(s.get("aim_mag", 0.7)))
		if float(s["_t"]) > float(s.get("aim_s", 0.3)):
			_tnode = royal
			_tprev = Vector3.INF
			_tvel = Vector3.ZERO
			s["_ph"] = "hop"
			s["_t"] = 0.0
			(inp.get("_hold_frames") as Dictionary)["jump"] = 12
			print("[W3 bot] hop to royal from %s (royal %s)" % [p, rp])
	elif ph == "back" or ph == "runup":
		var cur := _tnode.global_position
		var nb: Node3D = s["_next"]
		if not is_instance_valid(nb):
			s["_ph"] = "ride"
			return
		var dir := Vector2(nb.global_position.x - cur.x, nb.global_position.z - cur.z).normalized()
		var rel := Vector2(p.x - cur.x, p.z - cur.z)
		s["_t"] = float(s.get("_t", 0.0)) + 1.0 / 60.0
		if ph == "back":
			var rear := -dir * float(s.get("back_r", 0.95))
			var d := rear - rel
			_stick(inp, Vector2(d.x, -d.y).normalized() * 0.5 if d.length() > 0.15 else Vector2.ZERO)
			if d.length() < 0.2 or float(s["_t"]) > float(s.get("back_s", 0.8)):
				s["_ph"] = "runup"
				s["_t"] = 0.0
		else:
			_stick(inp, Vector2(dir.x, -dir.y))
			if rel.dot(dir) > float(s.get("front_r", 0.85)) or float(s["_t"]) > float(s.get("runup_s", 0.6)):
				_tnode = nb
				# The velocity estimate must restart on the new biscuit (it was differencing two biscuits).
				_tprev = Vector3.INF
				_tvel = Vector3.ZERO
				s["_ph"] = "hop"
				s["_t"] = 0.0
				(inp.get("_hold_frames") as Dictionary)["jump"] = 14
				print("[W3 bot] leapfrog from %s to %s" % [p, nb.global_position])
	else:
		s["_t"] = float(s.get("_t", 0.0)) + 1.0 / 60.0
		var hs := {"node": true, "top_off": 0.2 if _tnode == royal else 0.35}
		_air_control(inp, hs, p, vel)
		if grounded and float(s["_t"]) > 0.15:
			if _tnode == royal:
				_next("landed on the Royal Digestive at %s" % p)
				return
			s["_ph"] = "ride"
			s["_t"] = 0.0


func _air_control(inp: Object, s: Dictionary, p: Vector3, vel: Vector3) -> void:
	var np := _tnode.global_position
	if _tprev != Vector3.INF:
		_tvel = _tvel.lerp((np - _tprev) * 60.0, 0.3)
	_tprev = np
	var t := np + Vector3(0, float(s.get("top_off", 0.35)), 0)
	var dxz := Vector2(t.x - p.x, t.z - p.z)
	var vy := float(pl.get("vy"))
	var disc := vy * vy + 2.0 * G * (p.y - t.y)
	if disc < 0.0:
		_stick(inp, Vector2(dxz.x, -dxz.y).normalized() * 0.6)
		return
	var tl := maxf((vy + sqrt(disc)) / G, 0.08)
	var want := (dxz + Vector2(_tvel.x, _tvel.z) * tl) / tl
	var corr := (want - Vector2(vel.x, vel.z)) * 0.5
	var st := Vector2(corr.x, -corr.y)
	_stick(inp, st.normalized() if st.length() > 1.0 else st)


func _stick(inp: Object, v: Variant) -> void:
	var vv: Vector2 = v if v is Vector2 else Vector2(float(v[0]), float(v[1]))
	inp.set("_r_stick", vv)


func _next(msg: String) -> void:
	_tprev = Vector3.INF
	_tvel = Vector3.ZERO
	print("[W3 bot] %s step %d: %s (frame %d)" % [_name, step, msg, _frames])
	step += 1
	_step_frames = 0
	_hop_phase = 0


func _finish(msg: String) -> void:
	_done = true
	var inp: Object = pl.get("inp") if pl else null
	if inp:
		inp.set("_r_stick", Vector2.ZERO)
	print("[W3 bot] %s RESULT: %s (frame %d) truffles=%s acorns=%d hurts=%d" % [_name, msg, _frames, str(ObjSvc.truffle_count()), ObjSvc.acorns_this_visit(), _hurts])
