extends Node
## Finishing pass (ENEMIES-BOSS-UI, 2026-10-19). Test-only; no level uses it.
## Enters the boss through the real Router, then:
##   --ebu=intro  timed native captures through the intro cine (first visit: use a fresh --profile), lists large
##                visible geometry near the camera on the first shots, then quits.
##   --ebu=full   with --bosstest --bosstest-hold: the track's real-player bot plays the fight; one capture on the first
##                frame of each phase state; writes a results json (defeated, fight time, slices lost, errors).
## Run: python tools/godot.py run res://tests/finish_ebu/EbuBossShots.tscn --seconds 120 -- --ebu=intro --profile=ebu_intro_1 --tag=before
##      python tools/godot.py run res://tests/finish_ebu/EbuBossShots.tscn --seconds 900 -- --ebu=full --bosstest --bosstest-hold --no-cine --profile=ebu_full_1

var mode := "intro"
var tag := ""
var out_dir := ""
var t := 0.0
var res := {"steps": []}
var _errs := 0


func _ready() -> void:
	if not has_meta("driver"):
		var d := Node.new()
		d.set_meta("driver", true)
		d.name = "EbuDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	if dev != null:
		mode = String(dev.call("arg", "ebu", "intro"))
		tag = String(dev.call("arg", "tag", ""))
	out_dir = ProjectSettings.globalize_path("res://").path_join("../Docs/progress/finish/enemies_boss_ui").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _process(delta: float) -> void:
	t += delta


func _step(s: String) -> void:
	print("[EBU] t=%.2f %s" % [t, s])
	(res["steps"] as Array).append({"t": snappedf(t, 0.01), "s": s})


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _boss() -> Node:
	var sc := get_tree().current_scene
	if sc == null or sc.get("world_id") == null or String(sc.get("world_id")) != "BOSS":
		return null
	return sc.get("boss")


func _shot(caption: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := out_dir.path_join("%s%s.png" % [(tag + "_") if tag != "" else "", caption])
	img.save_png(p)
	_step("capture " + p.get_file())


func _near_geometry() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var out: Array = []
	for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var aabb := gi.get_aabb()
		var c := gi.global_transform * aabb.get_center()
		var size := (gi.global_basis * aabb.size).length()
		var d := cam.global_position.distance_to(c)
		if d < 9.0 and size > 2.0 and cam.is_position_in_frustum(c):
			out.append("%s (d %.1f, size %.1f)" % [str(gi.get_path()).right(90), d, size])
	_step("near large geometry: " + str(out))


func _run() -> void:
	await _wait(0.5)
	var r := get_node_or_null("/root/Router")
	r.call("enter_world", "BOSS", "")
	var t0 := t
	while (_boss() == null or bool(r.get("busy"))) and t - t0 < 40.0:
		await get_tree().process_frame
	_step("in BOSS: %s" % str(_boss() != null))
	if mode == "intro":
		var times := [0.1, 0.45, 1.0, 2.0, 3.2, 4.6, 6.0, 7.5, 9.0, 11.0]
		var last := 0.0
		for i in times.size():
			await _wait(float(times[i]) - last)
			last = float(times[i])
			var b := _boss()
			await _shot("intro_%02d_%.1fs_%s" % [i, last, String(b.get("state")) if b != null else "-"])
			if i < 3:
				_near_geometry()
		await _wait(0.2)
		get_tree().quit()
		return
	# full fight
	var seen := {}
	t0 = t
	var next_tick := 6.0
	while t - t0 < 400.0:
		var b := _boss()
		if b == null:
			break
		if t - t0 > next_tick and next_tick < 90.0:
			next_tick += 8.0
			await _shot("tick_%03ds_P%d_%s" % [int(t - t0), int(b.get("phase")), String(b.get("state"))])
		var key := "P%d_%s" % [int(b.get("phase")), String(b.get("state"))]
		if not seen.has(key) and seen.size() < 40:
			seen[key] = true
			_step("state " + key)
			if key.contains("open") or key.contains("charge") or key.contains("dizzy") or key.contains("wedged") or key.contains("popped") or key in ["P1_p1_huff", "P3_p3"]:
				await _shot("full_" + key.to_lower())
		res["boss_last"] = {"phase": int(b.get("phase")), "total": int(b.get("total")), "state": String(b.get("state")),
			"defeated": bool(b.get("defeated")), "fight_time": snappedf(float(b.get("fight_time")), 0.01),
			"stats": b.get("stats")}
		if bool(b.get("defeated")) and not res.has("defeated_at"):
			res["defeated_at"] = snappedf(t - t0, 0.1)
			await _wait(2.0)
			await _shot("full_defeated")
			await _wait(4.0)
			break
		await get_tree().process_frame
	_step("done: " + str(res.get("boss_last", {})))
	var f := FileAccess.open(out_dir.path_join("%sfull_results.json" % [(tag + "_") if tag != "" else ""]), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  ", true))
	f.close()
	get_tree().quit()
