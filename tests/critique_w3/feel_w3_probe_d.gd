extends "res://tests/critique_w3/feel_w3_probe_c.gd"
## Critique W3 round 1 pass C, second batch: "competent player" versions of the timing beats (candle wave in its
## out windows, gumdrop spiral with the stick on the next dome from the first bounce, kitchen run from the hearth
## inside one oven cycle, pillar and jelly jumps with a short run-up) and a state histogram on the slide.
## Phases: wave2, gum2, kitchen2, pillars2, jelly4, slidestate.


func _phase_list() -> Array:
	return ["wave2", "gum2", "kitchen2", "pillars2", "jelly4", "slidestate"]


func _cand_t(i: int) -> float:
	var c := _candle(i)
	return fposmod(float(c.get("_t")) - float(c.get("phase_s")), float(c.get("period_s")))


## Seconds of out window left on candle i (0 if lit).
func _out_left(i: int) -> float:
	var t := _cand_t(i)
	if t < 2.0:
		return 0.0
	return 3.5 - t


func _jump_at_run(t: Vector3, run_frames: int, hold := 14, label := "") -> Dictionary:
	# Short run-up straight at the target, then the naive jump.
	for i in run_frames:
		stick = _toward(t, 0.0)
		await _frames(1)
	return await _jump_at(t, hold, label)


func _ph_wave2() -> Dictionary:
	var out := {}
	var tops := [Vector3(42.6, 25.2, -44.6), Vector3(42.9, 26.4, -39.5), Vector3(40.9, 27.6, -38.3), Vector3(39.4, 28.0, -40.4)]
	var land := Vector3(43.3, 24.05, -42.0)
	for style in ["chain_on_land", "pause_0.25s", "runup_12f"]:
		var runs: Array = []
		for run in 2:
			await _tp(land, 0.0, 10)
			# wait until candle 1 has just gone out
			var w := 0
			while w < 400 and not (_out_left(1) > 1.35):
				await _frames(1)
				w += 1
			var dmg0 := damage_log.size()
			var jumps: Array = []
			var ok := true
			for i in 4:
				if i > 0 and i < 3:
					# a competent player jumps only into a window with >= 0.6 s left, otherwise waits for the next one
					var ww := 0
					while ww < 400 and _out_left(i + 1) < 0.6:
						await _frames(1)
						ww += 1
				var j: Dictionary
				if style == "chain_on_land":
					j = await _jump_at(tops[i], 14, "%s_r%d#%d" % [style, run, i + 1])
				elif style == "pause_0.25s":
					stick = Vector2.ZERO
					await _wait(0.25)
					j = await _jump_at(tops[i], 14, "%s_r%d#%d" % [style, run, i + 1])
				else:
					j = await _jump_at_run(tops[i], 12, 14, "%s_r%d#%d" % [style, run, i + 1])
				j["lit_on_land"] = bool(_candle(i + 1).get("_lit")) if i < 3 else false
				j["off_centre_m"] = snappedf(_hdist(tops[i]), 0.01)
				jumps.append(j)
				if not bool(j["ok"]):
					ok = false
					break
			runs.append({"ok": ok, "damage": damage_log.size() - dmg0, "jumps": jumps})
			var g := get_node_or_null("/root/Game")
			if g:
				g.call("heal", 8)
		out[style] = runs
	log_line("wave2 " + JSON.stringify(out).left(3000))
	return out


func _ph_gum2() -> Dictionary:
	var out := {}
	var tops: Array = []
	for i in range(1, 8):
		tops.append(level.call("_gum", i))
	tops.append(Vector3(20, 24.4, 38))
	for style in ["stick_on_next", "stick_on_next_slam_grumpy_early"]:
		await _tp(Vector3(9.4, 2.1, 38.0), -90.0, 20)
		await _goto(Vector3(11.0, 2.0, 38.0), 0.3, 3.0)
		var dmg0 := damage_log.size()
		var cur := 0          # index of the dome we are heading to
		var bounces := 0
		var log_: Array = []
		var prev := _st()
		stick = _toward(tops[0])
		_press("jump", 16)
		var f := 0
		var maxy := 0.0
		while f < 60 * 25:
			await _frames(1)
			f += 1
			var st := _st()
			var p := player.global_position
			maxy = maxf(maxy, p.y)
			if st == "bounce" and prev != "bounce":
				bounces += 1
				# which dome did we bounce on?
				var best := -1
				var bd := 9.0
				for k in tops.size():
					var tk: Vector3 = tops[k]
					var dd := Vector2(tk.x - p.x, tk.z - p.z).length()
					if dd < bd and absf(p.y - tk.y) < 1.2:
						bd = dd
						best = k
				log_.append({"bounce": bounces, "on": best + 1, "at": _v(p), "f": f})
				if best >= 0:
					cur = mini(best + 1, tops.size() - 1)
				maxy = p.y
			prev = st
			var tgt: Vector3 = tops[cur]
			stick = _toward(tgt)
			var vy := float(player.get("vy"))
			var grumpy := cur >= 4 and cur <= 6
			var slam_h := 1.0 if style == "stick_on_next" else 2.5
			if grumpy and vy < 0.0 and _hdist(tgt) < 0.8 and p.y > tgt.y + 0.6 and p.y < tgt.y + slam_h + 1.5 and st != "ham_slam":
				_press("crouch", 4)
			if cur == tops.size() - 1 and _grounded() and absf(p.y - 24.4) < 0.4:
				log_.append({"saucer": true, "f": f})
				break
			if p.y < 2.6 and f > 40:
				log_.append({"fell": true, "heading_to": cur + 1, "at": _v(p), "f": f, "apex_last": snappedf(maxy, 0.01)})
				break
		stick = Vector2.ZERO
		out[style] = {"log": log_, "reached_dome": cur, "damage": damage_log.size() - dmg0, "seconds": snappedf(f / 60.0, 0.01)}
	log_line("gum2 " + JSON.stringify(out).left(3000))
	return out


func _ph_kitchen2() -> Dictionary:
	var out := {}
	var runs: Array = []
	for k in 3:
		await _tp(Vector3(-2.4, 100.3, -29.0), 90.0, 20)
		# wait for the start of a cold window (a player who watched one cycle)
		var w := 0
		while w < 500 and not (String(level.get("_oven_state")) == "cold" and float(level.get("_oven_t")) < 0.05):
			await _frames(1)
			w += 1
		var dmg0 := damage_log.size()
		var t_start := float(level.get("_oven_t"))
		await _goto(Vector3(-6.0, 100.0, -29.9), 0.25 if k < 2 else 0.6, 3.0)
		stick = Vector2.ZERO
		await _frames(3 if k == 0 else 10)
		var t_mark := float(level.get("_oven_t"))
		_press("crouch", 26)
		await _frames(6)
		_press("jump", 14)
		await _land_wait(200)
		await _frames(4)
		runs.append({"variant": ["fast_stop", "settle_10f", "sloppy_0.6m"][k], "oven_t_start": snappedf(t_start, 0.02), "oven_t_at_mark": snappedf(t_mark, 0.02),
			"oven_t_at_land": snappedf(float(level.get("_oven_t")), 0.02), "landed": _v(player.global_position), "on_oven": player.global_position.y > 103.0,
			"damage": damage_log.size() - dmg0})
		var g := get_node_or_null("/root/Game")
		if g:
			g.call("heal", 8)
	out["runs"] = runs
	# Bypass check (R3.4 negative): walk at the oven face, single then a chained double into the face (vault/mantle?).
	var byp: Array = []
	for startz in [-27.4, -28.6]:
		await _tp(Vector3(-6.0, 100.05, startz), 0.0, 20)
		await _oven_cold_start()
		var d0 := damage_log.size()
		stick = Vector2(0, 1)
		await _frames(10)
		var a := await _jump_at(Vector3(-6.0, 103.4, -32.6), 14, "oven_moving#1")
		var b := await _jump_at(Vector3(-6.0, 103.4, -32.6), 14, "oven_moving#2")
		await _frames(10)
		byp.append({"start_z": startz, "a": a, "b": b, "on_oven": player.global_position.y > 103.0, "damage": damage_log.size() - d0})
		var g2 := get_node_or_null("/root/Game")
		if g2:
			g2.call("heal", 8)
	out["bypass_moving_double"] = byp
	# From the oven top, wait for a cold window, drop south into the lane and run for the door.
	await _tp(Vector3(-6.0, 103.5, -32.4), 180.0, 20)
	var w2 := 0
	while w2 < 500 and not (String(level.get("_oven_state")) == "cold" and float(level.get("_oven_t")) < 0.05):
		await _frames(1)
		w2 += 1
	var dmg1 := damage_log.size()
	var t0 := Time.get_ticks_msec()
	var ok := await _goto(Vector3(-6.0, 100.0, -24.3), 0.3, 4.0)
	var t_end := float(level.get("_oven_t"))
	await _frames(40)
	out["exit_from_oven"] = {"reached": ok, "secs": snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.01), "oven_t_at_door": snappedf(t_end, 0.02),
		"damage": damage_log.size() - dmg1, "end": _v(player.global_position)}
	log_line("kitchen2 " + JSON.stringify(out))
	return out


func _ph_pillars2() -> Dictionary:
	var out := {}
	var t := [Vector3(-21.6, 9.6, -36.0), Vector3(-26.2, 11.2, -37.4), Vector3(-30.8, 12.8, -38.2), Vector3(-35.4, 14.4, -37.6), Vector3(-36.6, 16.0, -43.2)]
	# careful-with-run-up: on each pillar walk back to the far edge, then run and jump at the near edge.
	await _tp(Vector3(-16.6, 8.1, -35.8), 90.0)
	await _goto(t[0], 3.4, 6.0)
	var jumps: Array = []
	var j := await _jump_at(t[0], 14, "p2_runup#1")
	jumps.append(j)
	for i in range(1, t.size()):
		if not bool(jumps[-1]["ok"]):
			break
		var here: Vector3 = t[i - 1]
		var nxt: Vector3 = t[i]
		var back := here - (Vector3(nxt.x - here.x, 0, nxt.z - here.z).normalized() * 0.8)
		await _goto(back, 0.2, 2.0)
		stick = Vector2.ZERO
		await _frames(10)
		var f := 0
		while f < 60 and _hdist(here) < 0.85:
			stick = _toward(nxt, 0.0)
			await _frames(1)
			f += 1
		jumps.append(await _jump_at(nxt, 14, "p2_runup#%d" % (i + 1)))
	out["runup"] = jumps
	# rhythm but releasing jump between presses so the third press is a fresh single (stop 0.2 s on each top)
	out["stop_0.2"] = await _seq("pillars_stop02", Vector3(-16.6, 8.1, -35.8), 90.0, t, 0.2, 3.4)
	return out


func _ph_jelly4() -> Dictionary:
	var out := {}
	var t := [Vector3(26.3, 9.0, -25.0), Vector3(29.4, 10.5, -26.1), Vector3(32.6, 12.0, -28.6)]
	await _tp(Vector3(22.8, 8.25, -24.2), -90.0)
	await _goto(t[0], 2.2, 6.0)
	var j1 := await _jump_at(t[0], 14, "jelly4#1")
	stick = Vector2.ZERO
	await _wait(0.4)
	var j2 := await _jump_at_run(t[1], 8, 14, "jelly4#2")
	stick = Vector2.ZERO
	await _wait(0.4)
	var j3 := await _jump_at_run(t[2], 10, 14, "jelly4#3")
	out["pause_then_runup"] = [j1, j2, j3]
	return out


func _ph_slidestate() -> Dictionary:
	var plans: Dictionary = level.call("_bot_plans")
	var bot := Node.new()
	bot.set_script(load("res://scripts/worlds/w3_bot.gd"))
	level.add_child(bot)
	bot.call("setup", "feel_slidestate", plans["w34"], 40.0)
	drive = false
	var hist := {}
	var fast := {}
	var vmax := 0.0
	var f := 0
	while f < 60 * 35:
		await _frames(1)
		f += 1
		var st := _st()
		hist[st] = int(hist.get(st, 0)) + 1
		var v: Vector3 = player.velocity
		var hs := Vector2(v.x, v.z).length()
		vmax = maxf(vmax, hs)
		if hs > 9.0:
			fast[st] = int(fast.get(st, 0)) + 1
		if bool(bot.get("_done")):
			break
	drive = true
	bot.queue_free()
	var r := {"frames": f, "state_frames": hist, "states_above_9mps": fast, "max_hspeed": snappedf(vmax, 0.1)}
	log_line("slidestate " + JSON.stringify(r))
	return r
