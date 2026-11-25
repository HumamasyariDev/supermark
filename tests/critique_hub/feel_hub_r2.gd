extends "res://tests/critique_hub/feel_hub_probe.gd"
## HUB critique round 2, lens GAME FEEL, MOVEMENT AND CAMERA. Read-only probe (changes nothing in the hub's files).
## Extends the round-1 probe (same per-frame camera log, same camera-relative real input) with round-2 tasks:
##   views2         extra fixed views (From_* spawns, mantel, Test_Cornice, rim cross, bay, stair head ...)
##   cornice2       long jumps from the short L2 run-up, edge/late long jumps, chained double at the edge
##   natural_fwd    a person holding only "forward" in the CHINT_cornice view, long jump at the runway end
##   rhythm_buf     spiral hops with the jump pressed 3-6 frames BEFORE landing (buffered), the natural rhythm
##   sp10           SP10 -> chandelier rim: backflip, chained double (HUB-D9 says it is accepted), standing single
##   mantel         south armchair seat -> back -> mantel hops (HJ7/HJ5) with CHINT_mantel
##   l2_walkpast    walk the gallery past the foot of ladder L2 without pressing anything (does it grab Mak?)
##   gallery_drop   run off the gallery rail gap at the Book 3 bay joint and over the rail (landing, camera, hp)
## Run: python game/tests/critique_hub/run_r2_feel.py <label> <task,task,...>


func _main() -> void:
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	for i in 600:
		await get_tree().physics_frame
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_rig = get_tree().get_first_node_in_group("game_camera") as Node3D
		if _player != null and _rig != null and i > 90:
			break
	if _player == null or _rig == null:
		push_error("[FeelHub] no player or camera")
		get_tree().quit(3)
		return
	_cam = _rig.get_node_or_null("Camera3D") as Camera3D
	# Let EV_huff_7 (books rising, 4 s) finish before anything touches the spiral.
	await _wait(300)
	print("[FeelHub] r2 start tasks ", _tasks)
	for t in _tasks:
		print("[FeelHub] task ", t)
		match t:
			"views": await task_views()
			"views2": await task_views2()
			"cornice": await task_cornice()
			"cornice2": await task_cornice2()
			"natural_fwd": await task_natural_fwd()
			"stick_right": await task_stick_right()
			"spiral_stand": await task_spiral_stand()
			"faller_chain": await task_faller_chain()
			"rhythm": await task_rhythm()
			"rhythm_buf": await task_rhythm_buf()
			"sp10": await task_sp10()
			"rim_slam": await task_rim_slam()
			"nook": await task_nook()
			"longjump_lane": await task_longjump_lane()
			"updraft": await task_updraft()
			"chimney": await task_chimney()
			"ladder": await task_ladder()
			"mantel": await task_mantel()
			"l2_walkpast": await task_l2_walkpast()
			"gallery_drop": await task_gallery_drop()
			"chimney_multi": await task_chimney_multi()
			"natural_lean": await task_natural_lean()
			"buffer_flat": await task_buffer_flat()
			"faller_soft": await task_faller_soft()
			"shots": await task_shots()
			_: push_warning("[FeelHub] unknown task " + t)
	_mark = "end"
	_release_all()
	if _res_out != "":
		var f := FileAccess.open(_res_out, FileAccess.WRITE)
		f.store_string(JSON.stringify(_results, " "))
		f.close()
	if _out != null:
		_out.flush()
	print("[FeelHub] done ", _results.size(), " results")
	await _wait(10)
	get_tree().quit()


func _hp() -> int:
	return int(get_tree().root.get_node("Game").get("health"))


# ------------------------------------------------------------------ extra views

func task_views2() -> void:
	var v := [
		["From_W1", Vector3(-5.23, 0.02, 5.23), -51.03],
		["From_W2", Vector3(5.23, 0.02, 5.23), 51.03],
		["From_W3", Vector3(8.6, 4.92, 0.0), 90.0],
		["From_BOSS", Vector3(0.0, 4.52, -13.6), 180.0],
		["Test_Cornice", Vector3(14.97, 8.52, 2.64), -170.0],
		["mantel_top_n", Vector3(-14.2, 2.02, -1.2), 0.0],
		["mantel_top_s", Vector3(-14.2, 2.02, 1.2), 180.0],
		["armchair_back_s", Vector3(-12.1, 1.6, 3.47), yaw_for(Vector3(-2.0, 0, -2.0).normalized())],
		["gallery_n_door", Vector3(0.0, 4.52, -14.6), 0.0],
		["gallery_e_95", pp(14.2, 95.0, 4.52), yaw_for(tangent(95.0))],
		["gallery_w_270", pp(14.2, 270.0, 4.52), yaw_for(tangent(270.0))],
		["gallery_s_200", pp(14.2, 200.0, 4.52), yaw_for(-tangent(200.0))],
		["top_balcony_200", pp(14.6, 200.0, 9.72), yaw_for(-tangent(200.0))],
		["cornice_B_166", pp(15.2, 166.0, 8.52), yaw_for(tangent(166.0))],
		["clock_drum", Vector3(0.0, 1.02, 2.3), 0.0],
		["landing_e", Vector3(3.4, 2.27, -8.25), 0.0],
	]
	for e in v:
		_mark = "view:" + str(e[0])
		_teleport(e[1], float(e[2]))
		await _wait(90)
		var chest := _player.global_position + Vector3.UP * 0.6
		_record({"task": "view2", "name": e[0], "pos": _v(_player.global_position), "state": _state(), "floor": _floor_name(),
			"cam": _v(_cam.global_position), "dist": snappedf(_cam.global_position.distance_to(chest), 0.01),
			"inside": _cam_inside(), "occ_chest": _ray_hit(_cam.global_position, chest),
			"zone": (str((_rig.get("zone") as Node).name) if _rig.get("zone") is Node else ""), "scr": _screen(chest)})
		await _shot("view_" + str(e[0]))


# ------------------------------------------------------------------ cornice round 2

func task_cornice2() -> void:
	# Short run-up straight from the L2 exit (theta 110), as a player who does not back up to theta 100 would.
	for th in [122.0, 125.0, 127.5]:
		await _cornice_attempt("long", th, 110.0)
	# Full run-up, long jump at the very edge and from the last ledge frame.
	for th in [128.5, 129.2]:
		await _cornice_attempt("long", th)
	# Chained double at the edge: hop at 117, land, jump again at once (the double must bonk the lintel).
	await _chain_attempt(117.0)
	await _chain_attempt(121.0)


func _chain_attempt(th_hop: float) -> void:
	_mark = "cornice:chain@%.1f" % th_hop
	_teleport(pp(15.2, 101.0, 8.55), yaw_for(tangent(101.0)))
	await _wait(45)
	var phase := 0
	var f := 0
	var states: Array[String] = []
	var max_th := 0.0
	var result := "timeout"
	for i in 520:
		var p := _player.global_position
		var th := theta_of(p)
		var r := Vector2(p.x, p.z).length()
		var st := _state()
		if states.is_empty() or states[-1] != st:
			states.append(st)
		_steer((tangent(th) + pp(1, th, 0) * clampf((15.15 - r) * 1.2, -0.6, 0.6)).normalized())
		max_th = maxf(max_th, th)
		if phase == 0 and th >= th_hop and _grounded():
			Input.action_press("jump")
			phase = 1
			f = 0
		elif phase == 1:
			f += 1
			if f == 8:
				Input.action_release("jump")
			if f > 10 and _grounded():
				Input.action_press("jump")
				phase = 2
				f = 0
		elif phase == 2:
			f += 1
			if f == 18:
				Input.action_release("jump")
			if f > 20 and _grounded():
				if p.y > 8.3 and th > 147.0:
					result = "crossed"
				elif p.y > 8.3:
					result = "stayed_on_A"
				else:
					result = "fell"
				break
		await _pf()
	_release_all()
	_record({"task": "cornice_chain", "th_hop": th_hop, "states": states, "max_th": snappedf(max_th, 0.1), "end": _v(_player.global_position),
		"end_th": snappedf(theta_of(_player.global_position), 0.1), "result": result, "hp": _hp()})
	await _wait(20)


## A person who has just climbed L2: holds only the stick "forward" (camera-relative, no line correction), runs, and
## long-jumps when Mak reaches theta `th_jump`. Variants start at the L2 exit and at the north end (theta 101).
func task_natural_fwd() -> void:
	for spec in [[110.0, 126.0], [101.0, 126.0], [101.0, 127.5], [110.0, 127.5]]:
		_mark = "natural_fwd:%.0f->%.1f" % [spec[0], spec[1]]
		_teleport(pp(15.0, float(spec[0]), 8.55), yaw_for(tangent(float(spec[0]))))
		_release_all()
		await _wait(90)
		var fired := false
		var f := 0
		var states: Array[String] = []
		var log := {}
		var launch := {}
		var result := "timeout"
		var max_th := 0.0
		for i in 480:
			var p := _player.global_position
			var th := theta_of(p)
			var r := Vector2(p.x, p.z).length()
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			max_th = maxf(max_th, th)
			for k in [112.0, 116.0, 120.0, 124.0, 126.0]:
				if th >= k and not log.has(str(k)):
					log[str(k)] = [snappedf(r, 0.02), snappedf((_player.call("get_horizontal_velocity") as Vector3).length(), 0.01),
						snappedf(rad_to_deg(float(_rig.get("yaw"))), 0.1), st]
			if not fired:
				Input.action_press("move_forward", 1.0)
				if th >= float(spec[1]) and _grounded():
					fired = true
					f = 0
					launch = {"th": snappedf(th, 0.1), "r": snappedf(r, 0.02),
						"speed": snappedf((_player.call("get_horizontal_velocity") as Vector3).length(), 0.01),
						"facing_vs_tangent_deg": snappedf(rad_to_deg(Vector3(-sin(float(_player.get("facing_yaw"))), 0, -cos(float(_player.get("facing_yaw")))).signed_angle_to(tangent(th), Vector3.UP)), 0.1)}
				if p.y < 8.0 or (i > 200 and not fired and th < 112.0):
					result = "fell_before_jump" if p.y < 8.0 else "stuck"
					break
			else:
				if f == 0: Input.action_press("crouch")
				if f == 2: Input.action_press("jump")
				if f == 6: Input.action_release("crouch")
				if f == 16: Input.action_release("jump")
				if f == 1:
					launch["state"] = st
				f += 1
				if f > 20 and _grounded():
					if p.y > 8.3 and th > 147.0:
						result = "crossed"
					elif p.y > 8.3:
						result = "stayed_on_A"
					else:
						result = "fell"
					break
			await _pf()
		_release_all()
		_record({"task": "natural_fwd", "start_th": spec[0], "th_jump": spec[1], "at_theta[r, speed, cam_yaw, state]": log, "launch": launch,
			"states": states, "max_th": snappedf(max_th, 0.1), "end": _v(_player.global_position), "end_th": snappedf(theta_of(_player.global_position), 0.1),
			"floor": _floor_name(), "result": result, "hp": _hp()})
		await _wait(30)


# ------------------------------------------------------------------ spiral: buffered rhythm, SP10 to the rim

## Buffered bunny-hop chain: from the current cover, jump toward targets[0]; while falling toward each target, the jump
## is pressed again when the feet are within `early_y` above its top (a natural early press). The buffered jump then
## fires on the landing frame (inside the chain window) toward the next target. The last target gets no early press.
func _hop_chain(targets: Array, names: Array, early_y: float) -> Array:
	var out := []
	var k := 0
	Input.action_press("jump")
	var f := 0
	var pressed_early := false
	var was_ground := true
	var lp := _player.global_position
	var kind := ""
	for i in 900:
		var p := _player.global_position
		var tgt: Vector3 = targets[k]
		var d := tgt - p
		d.y = 0
		var st := _state()
		var g := _grounded()
		if f == 1:
			kind = st
		if f == 12 and not pressed_early:
			Input.action_release("jump")
		_steer(d.normalized() if d.length() > 0.3 else Vector3.ZERO)
		var vy := (_player.get("velocity") as Vector3).y
		if not g and f > 6 and vy < 0.0 and not pressed_early and k + 1 < targets.size() and p.y - tgt.y < early_y and p.y > tgt.y - 0.2:
			Input.action_release("jump")
			await _pf()
			Input.action_press("jump")
			pressed_early = true
		if g and not was_ground and f > 4:
			out.append({"to": names[k], "kind": kind, "from": _v(lp, 0.01), "land": _v(p, 0.01),
				"miss_xz": snappedf(Vector2(p.x - tgt.x, p.z - tgt.z).length(), 0.01), "on": p.y > tgt.y - 0.4,
				"floor": _floor_name(), "early_pressed": pressed_early})
			if p.y < tgt.y - 0.4 or k + 1 >= targets.size():
				break
			k += 1
			f = 0
			lp = p
			kind = ""
			pressed_early = false
		elif not g and p.y < tgt.y - 2.5:
			out.append({"to": names[k], "kind": kind, "fell": true, "pos": _v(p, 0.01)})
			break
		was_ground = g
		f += 1
		await _pf()
	Input.action_release("jump")
	return out


func task_rhythm_buf() -> void:
	# SP03 -> SP04 -> ... -> SP08 as a bunny-hop with early presses (the natural rhythm of a player in a hurry).
	var bk := HubSpiral.BOOKS
	for early_y in [0.3, 0.8]:
		for i in 400:
			if _fallers_idle():
				break
			await _pf()
		_mark = "rhythm_buf:%.2f" % early_y
		var start: Vector3 = bk[2][2]
		var d0 := (bk[3][2] as Vector3) - start
		d0.y = 0
		_teleport(start + Vector3(0, 0.12, 0), yaw_for(d0.normalized()))
		await _wait(30)
		var tg := []
		var nm := []
		for idx in [3, 4, 5, 6, 7]:
			tg.append(bk[idx][2])
			nm.append(bk[idx][0])
		var hops: Array = await _hop_chain(tg, nm, early_y)
		_release_all()
		_record({"task": "rhythm_buf", "early_y": early_y, "hops": hops, "hp": _hp()})
		await _wait(30)


func task_sp10() -> void:
	var bk := HubSpiral.BOOKS
	var sp09: Vector3 = bk[8][2]
	var sp10: Vector3 = bk[9][2]
	var to_c := Vector3(-sp10.x, 0, -sp10.z).normalized()
	# a) backflip from the ribbon cross facing away from the hall axis (R2.5 HJ16).
	for variant in ["backflip", "standing_single", "running_single_in", "chain_from_sp09"]:
		_mark = "sp10:" + variant
		var states: Array[String] = []
		var max_y := 0.0
		if variant == "chain_from_sp09":
			_teleport(sp09 + Vector3(0, 0.12, 0), yaw_for((sp10 - sp09).normalized()))
			await _wait(20)
			# wait for SP09's open window start
			var sp := _spiral()
			for i in 240:
				var ph := fposmod(float(sp.get("_t")) + 1.5, 3.0) if sp else 0.0
				if ph > 0.05 and ph < 0.2:
					break
				await _pf()
			var h: Dictionary = await _hop(sp10, 2)
			states.append("hop1:" + str(h["kind"]) + ":on=" + str(h["on"]))
			# immediate second jump toward the hall axis (would be a double if the chain survived)
		elif variant == "running_single_in":
			_teleport(sp10 - to_c * 0.9 + Vector3(0, 0.32, 0), yaw_for(to_c))
			await _wait(30)
		else:
			_teleport(sp10 + to_c * 0.0 + Vector3(0, 0.32, 0), yaw_for(-to_c))
			await _wait(30)
		var f := 0
		var reached := false
		for i in 200:
			var p := _player.global_position
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			max_y = maxf(max_y, p.y)
			match variant:
				"backflip":
					if f == 0: Input.action_press("crouch")
					if f == 6: Input.action_press("jump")
					if f == 30:
						Input.action_release("jump")
						Input.action_release("crouch")
				"standing_single":
					_steer(to_c)
					if f == 4: Input.action_press("jump")
					if f == 24: Input.action_release("jump")
				"running_single_in", "chain_from_sp09":
					_steer(to_c)
					if f == 1: Input.action_press("jump")
					if f == 24: Input.action_release("jump")
			if f > 8 and _grounded():
				reached = p.y > 9.0 and Vector2(p.x, p.z).length() < 3.2
				break
			f += 1
			await _pf()
		_release_all()
		var e := _player.global_position
		_record({"task": "sp10", "variant": variant, "states": states, "max_y": snappedf(max_y, 0.01), "end": _v(e),
			"r_end": snappedf(Vector2(e.x, e.z).length(), 0.01), "reached_rim": reached, "floor": _floor_name(), "hp": _hp()})
		await _shot("sp10_" + variant)
		await _wait(40)


# ------------------------------------------------------------------ mantel climb (HJ7/HJ5)

func task_mantel() -> void:
	_mark = "mantel"
	_teleport(Vector3(-11.6, 0.02, 5.4), yaw_for(Vector3(-0.7, 0, -2.2).normalized()))
	await _wait(40)
	var hops := []
	var h1: Dictionary = await _hop(Vector3(-12.3, 0.63, 3.2), 4)
	h1["to"] = "seat"
	hops.append(h1)
	var h2: Dictionary = await _hop(Vector3(-12.1, 1.58, 3.47), 10)
	h2["to"] = "back"
	hops.append(h2)
	var h3: Dictionary = await _hop(Vector3(-14.2, 2.0, 1.4), 10)
	h3["to"] = "mantel"
	hops.append(h3)
	await _shot("mantel_after_hops")
	# A direct running jump at the mantel from the floor (should be too high: 2.0 m > 1.89 standing apex; a run gives 2.64).
	_mark = "mantel:run_jump"
	_teleport(Vector3(-9.6, 0.02, 1.4), -90.0)
	await _wait(30)
	var h4: Dictionary = await _hop(Vector3(-14.2, 2.0, 1.4), 26)
	h4["to"] = "mantel_from_floor_run"
	hops.append(h4)
	_record({"task": "mantel", "hops": hops, "hp": _hp()})
	await _wait(20)


# ------------------------------------------------------------------ L2 walk past

func task_l2_walkpast() -> void:
	for rr in [13.1, 13.5, 14.0]:
		_mark = "l2_walkpast:%.1f" % rr
		_teleport(pp(rr, 98.0, 4.55), yaw_for(tangent(98.0)))
		await _wait(30)
		var states: Array[String] = []
		for i in 300:
			var p := _player.global_position
			var th := theta_of(p)
			var r := Vector2(p.x, p.z).length()
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			if th > 122.0 or st == "pole_climb":
				break
			_steer((tangent(th) + pp(1, th, 0) * clampf((rr - r) * 1.5, -0.5, 0.5)).normalized())
			await _pf()
		_release_all()
		await _wait(10)
		_record({"task": "l2_walkpast", "r": rr, "states": states, "grabbed": states.has("pole_climb"), "end": _v(_player.global_position)})
		if states.has("pole_climb"):
			await _shot("l2_walkpast_grab_%.1f" % rr)
		Input.action_press("crouch")
		await _wait(6)
		Input.action_release("crouch")
		await _wait(30)


# ------------------------------------------------------------------ gallery drop

func task_gallery_drop() -> void:
	for spec in [["bay_joint_gap", pp(13.6, 74.0, 4.55), pp(9.0, 74.0, 0.0)], ["over_rail_w", pp(13.8, 290.0, 4.55), pp(9.0, 290.0, 0.0)]]:
		_mark = "gallery_drop:" + str(spec[0])
		var tgt: Vector3 = spec[2]
		var start: Vector3 = spec[1]
		var d0 := tgt - start
		d0.y = 0
		_teleport(start, yaw_for(d0.normalized()))
		await _wait(30)
		var hp0 := _hp()
		var states: Array[String] = []
		var f := 0
		for i in 240:
			var p := _player.global_position
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			_steer(d0.normalized())
			if spec[0] == "over_rail_w" and i == 10:
				Input.action_press("jump")
			if i == 28:
				Input.action_release("jump")
			if i > 20 and _grounded() and p.y < 1.0:
				break
			await _pf()
		_release_all()
		await _wait(20)
		_record({"task": "gallery_drop", "name": spec[0], "states": states, "end": _v(_player.global_position), "hp_before": hp0, "hp_after": _hp()})


# ------------------------------------------------------------------ chimney repeatability, natural cornice with a lean

func task_chimney_multi() -> void:
	# The same closed-loop input as hub_autopilot's chimney step, five times from slightly different run-up spots.
	for start_th in [206.6, 206.6, 206.0, 207.2, 206.6]:
		_mark = "chimney_multi:%.1f" % start_th
		_teleport(pp(14.5, start_th, 4.55), yaw_for(tangent(start_th)))
		await _wait(60)
		var dir := 1.0
		var kicks := 0
		var jumped := false
		var jf := 0
		var prev := ""
		var t := 0
		var states: Array[String] = []
		var kick_log := []
		var result := "timeout"
		var max_y := 0.0
		for i in 900:
			var p := _player.global_position
			var th := theta_of(p)
			var st := _state()
			max_y = maxf(max_y, p.y)
			if states.is_empty() or states[-1] != st:
				states.append(st)
			var tang := tangent(th)
			if _grounded() and p.y > 9.6:
				result = "top_balcony"
				break
			if p.y > 10.2:
				_steer(-tang)
			else:
				_steer(tang * dir)
			if not jumped and _grounded() and t > 15:
				jumped = true
				jf = 16
			if st == "wall_slide" and prev != "wall_slide":
				jf = 10
				kicks += 1
				dir = -dir
				kick_log.append([snappedf(p.y, 0.01), snappedf((_player.get("velocity") as Vector3).y, 0.01)])
			if prev == "wall_slide" and st == "wall_kick":
				kick_log.append(["kick_vy", snappedf((_player.get("velocity") as Vector3).y, 0.01)])
			prev = st
			if jf > 0:
				Input.action_press("jump")
				jf -= 1
				if jf == 0:
					Input.action_release("jump")
			if jumped and _grounded() and t > 60 and p.y < 5.0:
				result = "fell_back"
				break
			t += 1
			await _pf()
		_release_all()
		_record({"task": "chimney_multi", "start_th": start_th, "result": result, "kicks": kicks, "kick_log": kick_log,
			"max_y": snappedf(max_y, 0.01), "time_s": snappedf(t / 60.0, 0.01), "states": states, "end": _v(_player.global_position)})
		await _wait(30)


## A person who learned that "up" pushes into the wall: holds up plus a 35-degree lean to the left, then long-jumps.
func task_natural_lean() -> void:
	for spec in [[110.0, 126.0, 0.6], [101.0, 126.5, 0.6], [110.0, 126.0, 0.4]]:
		_mark = "natural_lean:%.0f->%.1f/%.1f" % [spec[0], spec[1], spec[2]]
		_teleport(pp(15.0, float(spec[0]), 8.55), yaw_for(tangent(float(spec[0]))))
		_release_all()
		await _wait(90)
		var fired := false
		var f := 0
		var states: Array[String] = []
		var launch := {}
		var result := "timeout"
		for i in 480:
			var p := _player.global_position
			var th := theta_of(p)
			var r := Vector2(p.x, p.z).length()
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			if not fired:
				Input.action_press("move_forward", 1.0)
				Input.action_press("move_left", float(spec[2]))
				if th >= float(spec[1]) and _grounded():
					fired = true
					launch = {"th": snappedf(th, 0.1), "r": snappedf(r, 0.02), "speed": snappedf((_player.call("get_horizontal_velocity") as Vector3).length(), 0.01)}
				if p.y < 8.0:
					result = "fell_before_jump"
					break
				if i > 300:
					result = "stuck"
					break
			else:
				if f == 0: Input.action_press("crouch")
				if f == 2: Input.action_press("jump")
				if f == 6: Input.action_release("crouch")
				if f == 16: Input.action_release("jump")
				f += 1
				if f > 20 and _grounded():
					result = "crossed" if (p.y > 8.3 and th > 147.0) else ("stayed_on_A" if p.y > 8.3 else "fell")
					break
			await _pf()
		_release_all()
		_record({"task": "natural_lean", "spec": spec, "launch": launch, "states": states, "end": _v(_player.global_position),
			"end_th": snappedf(theta_of(_player.global_position), 0.1), "result": result})
		await _wait(30)


## Jump buffer check: drop 1.4 m onto (a) the gallery floor and (b) static cover SP04, press jump while still falling
## `early` physics frames before touchdown (estimated from height and fall speed); does a jump fire on landing?
func task_buffer_flat() -> void:
	var bk := HubSpiral.BOOKS
	var sp04: Vector3 = bk[3][2]
	for spec in [["gallery", pp(14.0, 300.0, 5.95), 4.5], ["SP04", sp04 + Vector3(0, 1.45, 0), sp04.y], ["SP01", (bk[0][2] as Vector3) + Vector3(0, 1.45, 0), (bk[0][2] as Vector3).y]]:
		for early in [2, 5, 9]:
			_mark = "buffer:%s:%d" % [spec[0], early]
			_teleport(spec[1], 0.0)
			var pressed := -1
			var landed := -1
			var states: Array[String] = []
			for i in 120:
				var p := _player.global_position
				var vy := (_player.get("velocity") as Vector3).y
				var st := _state()
				if states.is_empty() or states[-1] != st:
					states.append(st)
				var h := p.y - float(spec[2])
				if pressed < 0 and vy < -1.0 and h < absf(vy) * float(early) / 60.0 + 0.02:
					Input.action_press("jump")
					pressed = i
				if landed < 0 and pressed >= 0 and _grounded():
					landed = i
				if landed >= 0 and i > landed + 20:
					break
				await _pf()
			Input.action_release("jump")
			_record({"task": "buffer", "where": spec[0], "early_frames": early, "pressed_at": pressed, "landed_at": landed, "states": states,
				"jumped_after_landing": states.has("jump") or states.has("double_jump")})
			await _wait(40)


## A careful player on the fallers: hops after a short pause and lets the stick go halfway through each jump.
func task_faller_soft() -> void:
	var bk := HubSpiral.BOOKS
	for air in [0.0, 0.35]:
		for i in 400:
			if _fallers_idle():
				break
			await _pf()
		_mark = "faller_soft:%.2f" % air
		var start: Vector3 = bk[3][2]
		var d0 := (bk[4][2] as Vector3) - start
		d0.y = 0
		_teleport(start + Vector3(0, 0.12, 0), yaw_for(d0.normalized()))
		await _wait(30)
		var hops := []
		for idx in [4, 5, 6, 7]:
			var h: Dictionary = await _hop(bk[idx][2], 6, 18, air)
			h["to"] = bk[idx][0]
			hops.append(h)
			if not h["on"]:
				break
		_release_all()
		_record({"task": "faller_soft", "stick_air": air, "hops": hops})
		await _wait(30)


## Gameplay-camera evidence frames of the key moments (native viewport PNGs).
func task_shots() -> void:
	# 1) Long jump under the lintel: shots at take-off, mid-gap and just before landing.
	_mark = "shots:long"
	_teleport(pp(15.2, 101.0, 8.55), yaw_for(tangent(101.0)))
	await _wait(60)
	var fired := false
	var f := 0
	for i in 480:
		var p := _player.global_position
		var th := theta_of(p)
		var r := Vector2(p.x, p.z).length()
		_steer((tangent(th) + pp(1, th, 0) * clampf((15.15 - r) * 1.2, -0.6, 0.6)).normalized())
		if not fired and th >= 126.0 and _grounded():
			fired = true
		if fired:
			if f == 0: Input.action_press("crouch")
			if f == 2: Input.action_press("jump")
			if f == 6: Input.action_release("crouch")
			if f == 16: Input.action_release("jump")
			if f in [0, 20, 45, 70, 90]:
				await _shot("shot_longjump_f%02d" % f)
			f += 1
			if f > 20 and _grounded():
				await _shot("shot_longjump_landed")
				break
		await _pf()
	_release_all()
	await _wait(30)
	# 2) Holding only "forward" on the cornice: where Mak stops.
	_mark = "shots:natural_fwd"
	_teleport(pp(15.0, 110.0, 8.55), yaw_for(tangent(110.0)))
	await _wait(90)
	for i in 240:
		Input.action_press("move_forward", 1.0)
		await _pf()
	await _shot("shot_cornice_hold_forward_stuck")
	_release_all()
	await _wait(20)
	# 3) Faller overshoot: SP05 -> SP06 hop, shots in the air.
	var bk := HubSpiral.BOOKS
	for i in 400:
		if _fallers_idle():
			break
		await _pf()
	_mark = "shots:faller"
	var a: Vector3 = bk[4][2]
	var b: Vector3 = bk[5][2]
	var d0 := b - a
	d0.y = 0
	_teleport(a + Vector3(0, 0.12, 0), yaw_for(d0.normalized()))
	await _wait(8)
	for i in 120:
		var p := _player.global_position
		var d := b - p
		d.y = 0
		_steer(d.normalized() if d.length() > 0.3 else Vector3.ZERO)
		if i == 10: Input.action_press("jump")
		if i == 28: Input.action_release("jump")
		if i in [24, 40]:
			await _shot("shot_faller_hop_f%02d" % i)
		if i > 14 and _grounded():
			break
		await _pf()
	await _shot("shot_faller_hop_end")
	_release_all()
	await _wait(30)
	# 4) Rim drop slam (first time: Grand Bong armed).
	_mark = "shots:rim"
	_teleport(Vector3(0, 9.2, 2.6), 0.0)
	await _wait(60)
	for i in 200:
		if i == 0: Input.action_press("jump")
		if i == 6: Input.action_release("jump")
		_steer(Vector3(0, 0, -1) if i < 14 else Vector3.ZERO)
		if i == 14: Input.action_press("crouch")
		if i == 17: Input.action_release("crouch")
		if i in [30, 60, 85]:
			await _shot("shot_rim_slam_f%02d" % i)
		if i > 20 and _grounded():
			break
		await _pf()
	_release_all()
	await _wait(260)
	# 5) Nook slam (last: its reward dialog is modal).
	_mark = "shots:nook"
	_teleport(Vector3(-1.4, 0.02, -11.6), -90.0)
	await _wait(40)
	for i in 200:
		var p := _player.global_position
		var d := Vector3(0, 0, -11.8) - p
		d.y = 0
		if d.length() < 0.15:
			break
		_steer(d.normalized() * (1.0 if d.length() > 1.0 else 0.35))
		await _pf()
	_release_all()
	await _wait(30)
	await _shot("shot_nook_on_board")
	Input.action_press("jump")
	for i in 70:
		if i == 10: Input.action_release("jump")
		if i == 20: Input.action_press("crouch")
		if i == 23: Input.action_release("crouch")
		if i in [8, 30]:
			await _shot("shot_nook_slam_f%02d" % i)
		await _pf()
	_record({"task": "shots", "done": true})
