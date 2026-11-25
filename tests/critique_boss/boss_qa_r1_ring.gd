extends "res://tests/critique_boss/boss_qa_r1.gd"
## CRITIC round 1, QA lens, BOSS track: invisible-hazard check (test only, read-only on the track).
## --qa=ringcheck: enters the boss through the Router (P1, --no-cine), waits for the intro prewarm, logs every P3 tea-ring
## piece (visible, monitorable, hazard group, position) and then parks Mak for 1.5 s at (a) a control spot far from the
## roof centre and (b) under a parked ring piece at the roof centre, recording health before/after each.
## Run: python tools/godot.py run res://tests/critique_boss/BossQaR1Ring.tscn --seconds 90 -- --qa=ringcheck --no-cine --profile=crit_boss_qa_ring
## Writes Docs/progress/critique/boss/r1_qa/<UTC>__qa_ringcheck_results.json plus captures.


func _ready() -> void:
	if not has_meta("driver"):
		var d := Node.new()
		d.set_meta("driver", true)
		d.name = "BossQaRingDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	mode = "ringcheck"
	out_dir = ProjectSettings.globalize_path("res://").path_join("../Docs/progress/critique/boss/r1_qa").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var d2 := Time.get_datetime_dict_from_system(true)
	stamp = "%04d%02d%02dT%02d%02d%02dZ" % [d2.year, d2.month, d2.day, d2.hour, d2.minute, d2.second]
	res = {"mode": mode, "utc": stamp, "steps": []}
	_ringcheck()


func _health() -> int:
	return int(_game().get("health"))


func _park(at: Vector3, sec: float) -> Dictionary:
	var p := _player()
	var h0 := _health()
	var t0 := t
	var b := _boss()
	var st0 := String(b.get("state")) if b != null else ""
	while t - t0 < sec:
		p.global_position = at
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO
		await get_tree().physics_frame
	return {"at": str(at), "health_before": h0, "health_after": _health(), "boss_state_before": st0,
		"boss_state_after": String(b.get("state")) if b != null else ""}


func _ringcheck() -> void:
	var ok := await _enter_boss()
	_step("entered BOSS: %s" % ok)
	var g := _game()
	await _wait(2.0)
	var b := _boss()
	var rows: Array = []
	var ring: Node3D = b.get("ring") if b != null else null
	res["ring_exists"] = ring != null
	res["boss_state"] = String(b.get("state")) if b != null else ""
	res["phase"] = int(b.get("phase")) if b != null else -1
	if ring != null:
		res["ring_visible"] = ring.visible
		res["ring_global"] = str(ring.global_position)
		for a in b.get("ring_pieces"):
			var ar := a as Area3D
			rows.append({"pos": str(ar.global_position.snapped(Vector3.ONE * 0.01)), "monitorable": ar.monitorable,
				"layer": ar.collision_layer, "hazard": ar.is_in_group("hazard"), "visible_in_tree": ar.is_visible_in_tree()})
	res["pieces"] = rows
	if g != null and g.has_method("heal"):
		g.call("heal", 99)
	# (a) control spot, away from the centre and the wolf.
	res["control"] = await _park(Vector3(-7.0, 0.05, 7.0), 1.5)
	await _wait(1.6)
	# (b) under the lowest parked piece (tier 0, r 2.4, y 1.2 relative to the ring).
	var target := Vector3(2.4, 0.05, 0.0)
	if ring != null and rows.size() > 0:
		var a0 := (b.get("ring_pieces") as Array)[0] as Area3D
		target = Vector3(a0.global_position.x, 0.05, a0.global_position.z)
	res["under_piece"] = await _park(target, 1.5)
	await _shot("qa_ring_under_invisible_piece")
	var lost := int(res["under_piece"]["health_before"]) - int(res["under_piece"]["health_after"])
	var lost_c := int(res["control"]["health_before"]) - int(res["control"]["health_after"])
	res["verdict"] = "INVISIBLE HAZARD" if lost > 0 and lost_c == 0 and not bool(res.get("ring_visible", true)) else ("ok" if lost == 0 else "inconclusive")
	_step("ringcheck: control lost %d, under piece lost %d -> %s" % [lost_c, lost, res["verdict"]])
	var f := FileAccess.open(out_dir.path_join("%s__qa_ringcheck_results.json" % stamp), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  ", true))
	f.close()
	print("[BossQA] ringcheck written")
	get_tree().quit()
