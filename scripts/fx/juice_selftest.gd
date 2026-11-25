extends Node3D
## Juice self-test: every event's effects resolve, every event fires without errors, pooling reuses nodes,
## loops start and stop, hitstop always restores Engine.time_scale, unknown events warn once.
## python tools/godot.py run res://scenes/fx/JuiceSelfTest.tscn --seconds 25 -- --profile=juice
## Prints one line per check and "[JuiceSelfTest] done, failures=N"; results JSON in user://juice_selftest.json.

const FAMILIES := ["woolly_wolf", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]

var _fails := 0
var _checks := 0
var _log: Array = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	var line := ("PASS " if ok else "FAIL ") + what
	_log.append(line)
	print("[JuiceSelfTest] ", line)


func _real_wait(seconds: float) -> void:
	# Under Movie Maker wall time runs slower than video time: wait in video frames there (juice fix r2).
	var juice := get_node_or_null("/root/Juice")
	if juice != null and juice.has_method("movie_step") and float(juice.movie_step()) > 0.0:
		for _f in int(ceilf(seconds / float(juice.movie_step()))):
			await get_tree().process_frame
		return
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _items_of(e: Dictionary) -> Array:
	var out: Array = []
	out.append_array(e.get("vfx", []))
	var bp: Variant = e.get("by_param")
	if bp is Dictionary:
		for k in bp.get("map", {}):
			out.append_array(bp["map"][k].get("vfx", []))
	var t: Variant = e.get("tiers")
	if t is Dictionary:
		for s in t.get("steps", []):
			out.append_array(s.get("vfx", []))
	return out


func _ready() -> void:
	Engine.max_fps = 60
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 4, 12)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	await get_tree().process_frame
	var juice := get_node_or_null("/root/Juice")
	_check(juice != null, "Juice autoload present")
	if juice == null:
		_finish()
		return
	var events: Dictionary = juice.vfx_events
	_check(events.size() >= 90, "catalogue has %d events" % events.size())

	# 1. Every referenced preset or scene resolves.
	var bad: Array = []
	var presets := {}
	for name in events:
		for item in _items_of(events[name]):
			if item.has("preset"):
				presets[item["preset"]] = true
				if FxPresets.get_preset(String(item["preset"])).is_empty():
					bad.append("%s: preset %s" % [name, item["preset"]])
			elif item.has("scene"):
				var sc := String(item["scene"])
				var path := sc if sc.begins_with("res://") else "res://scenes/fx/%s.tscn" % sc
				if not ResourceLoader.exists(path):
					bad.append("%s: scene %s" % [name, path])
	_check(bad.is_empty(), "all effect references resolve (%d presets) %s" % [presets.size(), str(bad)])

	# 2. Fire every event with representative params.
	var dummy := Node3D.new()
	add_child(dummy)
	dummy.position = Vector3(0, 0, 0)
	var before_vfx: int = juice.stats["vfx"]
	var unknown_before: int = juice.stats["unknown"]
	var i := 0
	for name in events:
		var pos := Vector3((i % 10) * 2.0 - 9.0, 0.0, -float(i / 10) * 2.0)
		var params := {"node": dummy, "direction": Vector3(0, 0, -1), "normal": Vector3(1, 0, 0), "impact": 14.0, "speed": 6.0,
			"family": FAMILIES[i % FAMILIES.size()], "kind": "punch", "surface": "grass", "combo": 2}
		juice.event(name, pos, params)
		i += 1
		if i % 12 == 0:
			await get_tree().process_frame
	await get_tree().process_frame
	_check(int(juice.stats["vfx"]) - before_vfx > 60, "fired %d events, %d effects spawned (dropped %d, culled %d)" % [i, int(juice.stats["vfx"]) - before_vfx, int(juice.stats["dropped"]), int(juice.stats["culled"])])
	_check(int(juice.stats["unknown"]) == unknown_before, "no catalogue event reported unknown")
	juice.end_hitstop()
	juice.stop_loops()
	await _real_wait(0.3)

	# 3. Unknown events warn and count.
	juice.event("definitely_not_an_event", Vector3.ZERO)
	juice.event("definitely_not_an_event", Vector3.ZERO)
	_check(int(juice.stats["unknown"]) == unknown_before + 2, "unknown events are counted (warn once)")

	# 4. Aliases and kind suffixes.
	_check(juice._canonical("player_jump", {"kind": "double"}) == "player_jump_2", "kind suffix resolves player_jump+double")
	_check(juice._canonical("player_ground_pound", {}) == "player_ham_slam", "alias player_ground_pound")

	# 5. Hitstop restores time scale.
	var t_start := Time.get_ticks_msec()
	juice.hitstop(200.0)
	var frames := 0
	while juice.is_hitstop_active() and frames < 400:
		await get_tree().process_frame
		frames += 1
	print("[JuiceSelfTest] diag: 200 ms hitstop lasted %d ms over %d frames" % [Time.get_ticks_msec() - t_start, frames])
	var ts0 := Engine.time_scale
	juice.hitstop(100.0)
	_check(Engine.time_scale < ts0 * 0.1, "hitstop slows time (%.3f)" % Engine.time_scale)
	await _real_wait(0.05)
	juice.hitstop(150.0)
	await _real_wait(0.12)
	_check(juice.is_hitstop_active(), "overlapping hitstop extends to the longest end (left %.3f s)" % juice._hitstop_left)
	await _real_wait(0.2)
	_check(not juice.is_hitstop_active() and is_equal_approx(Engine.time_scale, ts0), "time scale restored to %.2f" % Engine.time_scale)
	juice.hitstop(5000.0)
	await _real_wait(0.35)
	_check(is_equal_approx(Engine.time_scale, ts0), "hitstop is capped at 220 ms")
	Engine.time_scale = 0.5
	juice.hitstop(60.0)
	await _real_wait(0.2)
	_check(is_equal_approx(Engine.time_scale, 0.5), "hitstop restores a non-default time scale (0.5)")
	Engine.time_scale = ts0

	# 6. Pooling: the same effect is reused after it finishes.
	var reused0: int = juice.stats["reused"]
	juice.event("object_acorn_collect", Vector3(0, 1, 0))
	await _real_wait(1.2)
	juice.event("object_acorn_collect", Vector3(1, 1, 0))
	_check(int(juice.stats["reused"]) > reused0, "pooled effect reused (reused %d -> %d)" % [reused0, int(juice.stats["reused"])])

	# 7. Loops attach and stop.
	var mover := Node3D.new()
	add_child(mover)
	juice.event("player_slide_start", Vector3.INF, {"node": mover})
	await get_tree().process_frame
	var has_fx := false
	for c in mover.get_children():
		has_fx = has_fx or c is FxEffect
	_check(has_fx, "slide trail attached to the node")
	juice.event("player_slide_end", Vector3.INF, {"node": mover})
	await _real_wait(1.9)
	var still := 0
	for c in mover.get_children():
		if c is FxEffect:
			still += 1
	_check(still == 0, "slide trail stopped and freed")

	# 8. Shake fallback restores the camera offsets.
	juice.shake(0.5, 0.2)
	await _real_wait(0.08)
	var moved := absf(cam.h_offset) + absf(cam.v_offset) > 0.0001
	await _real_wait(0.3)
	_check(moved and is_zero_approx(cam.h_offset) and is_zero_approx(cam.v_offset), "fallback shake moves and restores the camera")

	# 8b. Juice fix r3: with a hero camera that shakes on scaled time (group game_camera, add_shake), the active camera
	# still jitters through a hitstop (h/v offsets) and is restored exactly when the freeze ends.
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar shakes := 0\nfunc add_shake(_s: float, _d: float = 0.3) -> void:\n\tshakes += 1\n"
	gs.reload()
	var gc := Node.new()
	gc.set_script(gs)
	gc.add_to_group("game_camera")
	add_child(gc)
	juice.event("player_ham_slam", Vector3(0, 0, 4), {"impact": 14.0, "no_vfx": true, "silent": true})
	var jit_max := 0.0
	var jf := 0
	while juice.is_hitstop_active() and jf < 60:
		await get_tree().process_frame
		jit_max = maxf(jit_max, absf(cam.h_offset) + absf(cam.v_offset))
		jf += 1
	await get_tree().process_frame
	_check(int(gc.get("shakes")) > 0 and jit_max > 0.005 and is_zero_approx(cam.h_offset) and is_zero_approx(cam.v_offset),
		"hitstop jitter moves the camera during the freeze (max %.3f m over %d frames) and restores it" % [jit_max, jf])
	gc.remove_from_group("game_camera")
	gc.queue_free()

	# 9. Budget: a flood of events never exceeds the cap.
	for n in 200:
		juice.event("player_footstep", Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)), {"surface": "grass", "speed": 7.0, "scale": 1.0})
	await get_tree().process_frame
	_check(juice._active <= juice.MAX_ACTIVE_ONESHOTS, "one-shot budget holds (%d active, %d dropped)" % [juice._active, int(juice.stats["dropped"])])
	await _real_wait(1.0)

	# 10. Juice fix r2: VFX and SFX beats share one timeline. Every non-voice sound layer at 0.2 s or later needs a visual
	# beat within 50 ms (world_lightning is exempt: thunder follows the flash on purpose).
	_check_beats(juice)

	# 11. Juice fix r2 (perf guard): 12 heavy events in one frame, pools warm. The Juice side (VFX, shake, hitstop; sounds
	# skipped with `silent`) must stay under 4 ms of script time; the full cost including JuiceSfx (audio track) is a diag.
	var heavy := [["player_ham_slam", {"impact": 14.0}], ["enemy_defeat", {"family": "woolly_wolf"}], ["enemy_defeat", {"family": "crow_bandit"}],
		["enemy_defeat", {"family": "gummy_brute"}], ["enemy_defeat", {"family": "gingerbread_grenadier"}], ["player_jump_3", {}],
		["enemy_hurt", {"family": "crow_bandit"}], ["enemy_hurt", {"family": "woolly_wolf"}], ["enemy_hurt", {"family": "bumble_bruiser"}],
		["object_crate_break", {}], ["player_land", {"impact": 16.0}], ["player_hurt", {}]]
	var times := {}
	for variant in [{}, {"silent": true}, {"silent": true}, {}, {"no_vfx": true}]:
		var t0 := Time.get_ticks_usec()
		for j in heavy.size():
			var pp: Dictionary = (heavy[j][1] as Dictionary).duplicate()
			pp.merge(variant)
			juice.event(String(heavy[j][0]), Vector3(j * 1.5 - 8.0, 0.0, -2.0), pp)
		times[str(variant)] = (Time.get_ticks_usec() - t0) / 1000.0
		juice.end_hitstop()
		await _real_wait(2.5)
	print("[JuiceSelfTest] diag: 12 heavy events, ms of script time by variant (warm, last run): %s" % str(times))
	var vfx_ms := float(times[str({"silent": true})])
	_check(vfx_ms < 4.0, "12 heavy events in one frame: Juice side %.2f ms (target < 4 ms; with JuiceSfx sounds %.2f ms; lite copies %d)" % [vfx_ms, float(times[str({})]), int(juice.stats.get("lite", 0))])

	# 12. Juice fix r2 (the video blocker): under Movie Maker a 60 ms hitstop holds 3-4 rendered frames at 60 fps.
	if juice.is_movie():
		juice.hitstop(60.0)
		var mf := 0
		while juice.is_hitstop_active() and mf < 30:
			await get_tree().process_frame
			mf += 1
		_check(mf >= 3 and mf <= 5, "movie: a 60 ms hitstop held %d rendered frames (want 3-4 at 60 fps)" % mf)
		juice.hitstop(90.0)
		mf = 0
		while juice.is_hitstop_active() and mf < 30:
			await get_tree().process_frame
			mf += 1
		_check(mf >= 5 and mf <= 7, "movie: a 90 ms hitstop held %d rendered frames (want 5-6)" % mf)
	else:
		print("[JuiceSelfTest] diag: not under Movie Maker; run 'godot.py movie' on this scene for the hitstop frame check")
	await _checks_r4(juice)
	_finish()


## Juice fix r4 checks: spark placement off Mak's body, the attached-copy count after an owner is freed, surface variants,
## block escalation, and the real-time screen flash through a hitstop.
func _checks_r4(juice: Node) -> void:
	await _real_wait(0.5)
	# 13. A contact spark that would land on Mak (between the camera and the target) moves to the target's edge.
	var mak := Node3D.new()
	add_child(mak)
	mak.add_to_group("player")
	mak.global_position = Vector3(0, 0.55, 2.0)
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(0.05, 0.0, 0.0)
	var moved0 := int(juice.stats.get("spark_moved", 0))
	juice.event("enemy_hurt", Vector3(0.05, 0.7, 0.0), {"family": "crow_bandit", "node": target, "silent": true})
	juice.end_hitstop()
	_check(int(juice.stats.get("spark_moved", 0)) > moved0, "a contact spark on the camera-to-Mak ray moves to the target's edge (moves %d)" % int(juice.stats.get("spark_moved", 0)))
	mak.remove_from_group("player")
	mak.queue_free()
	target.queue_free()
	await _real_wait(0.3)
	# 14. An attached copy freed with its owner no longer leaks the attached count.
	var n0: int = juice._attached_n()
	var owner_node := Node3D.new()
	add_child(owner_node)
	juice.event("player_jump_3", Vector3(0, 0, 0), {"node": owner_node, "silent": true})
	juice.end_hitstop()
	var n1: int = juice._attached_n()
	owner_node.free()
	await get_tree().process_frame
	var n2: int = juice._attached_n()
	_check(n1 == n0 + 1 and n2 == n0, "attached count after an owner is freed mid-play: %d -> %d -> %d" % [n0, n1, n2])
	# 15. Surface variants recolour ground layers and drop grass-only flecks.
	var cloud: Dictionary = FxPresets.get_preset("land_heavy@cloud")
	var dust_ok := false
	for layer in cloud.get("layers", []):
		if String(layer.get("tex", "")) == "dust_crescent":
			var c: Color = layer["colors"][0][1]
			dust_ok = c.is_equal_approx(Color(FxPresetsJuice.SURFACES["cloud"]["dust"], c.a))
	var flecks := 0
	for layer in FxPresets.get_preset("footstep_grass@candy").get("layers", []):
		if String(layer.get("tex", "")) == "leaf":
			flecks += 1
	_check(dust_ok and flecks == 0, "surface variants: cloud dust recoloured (%s), no grass flecks on candy (%d)" % [dust_ok, flecks])
	# 16. Consecutive blocks on one node escalate (params.repeat).
	var shield := Node3D.new()
	add_child(shield)
	for _b in 3:
		juice.event("enemy_block", Vector3(2, 1, 0), {"family": "gingerbread_grenadier", "node": shield, "silent": true})
		juice.end_hitstop()
	var rep_n := 0
	for key in juice._repeats:
		rep_n = maxi(rep_n, int(juice._repeats[key][0]))
	_check(rep_n == 3, "consecutive blocks escalate (repeat %d)" % rep_n)
	shield.queue_free()
	# 17. The screen flash runs on real time: a 200 ms hitstop does not hold it.
	juice.hitstop(200.0)
	juice.screen_flash(0.5)
	var vis0: bool = juice._flash_rect.visible
	await _real_wait(0.16)
	var vis1: bool = juice._flash_rect.visible
	_check(vis0 and not vis1 and juice.is_hitstop_active(), "screen flash fades on real time during a hitstop (visible %s -> %s, hitstop %s)" % [vis0, vis1, juice.is_hitstop_active()])
	juice.end_hitstop()
	await _real_wait(0.3)


func _check_beats(juice: Node) -> void:
	var f := FileAccess.open("res://assets/audio/juice_sfx.json", FileAccess.READ)
	if f == null:
		_check(true, "beat sync skipped (no juice_sfx.json)")
		return
	var j: Variant = JSON.parse_string(f.get_as_text())
	if not (j is Dictionary):
		return
	var sfx: Dictionary = (j as Dictionary).get("events", j)
	var bad: Array = []
	var checked := 0
	for name in sfx:
		var se: Variant = sfx[name]
		if not (se is Dictionary) or name == "world_lightning" or not juice.vfx_events.has(name):
			continue
		var vd: Array = []
		for it in (juice.vfx_events[name] as Dictionary).get("vfx", []):
			vd.append(float((it as Dictionary).get("delay", 0.0)))
		if vd.is_empty():
			continue
		for l in (se as Dictionary).get("layers", []):
			if not (l is Dictionary) or (l as Dictionary).get("voice", false) or String((l as Dictionary).get("key", "")).begins_with("voice_"):
				continue
			var d := float((l as Dictionary).get("delay", 0.0))
			if d < 0.2:
				continue
			checked += 1
			var ok := false
			for v in vd:
				ok = ok or absf(float(v) - d) <= 0.05
			if not ok:
				bad.append("%s@%.2f" % [name, d])
	_check(bad.is_empty(), "VFX/SFX beats line up within 50 ms (%d sound beats checked) %s" % [checked, str(bad)])


func _finish() -> void:
	print("[JuiceSelfTest] done, checks=%d failures=%d" % [_checks, _fails])
	var f := FileAccess.open("user://juice_selftest.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": _checks, "failures": _fails, "log": _log}, "  "))
	Engine.time_scale = 1.0
	get_tree().quit(1 if _fails > 0 else 0)
