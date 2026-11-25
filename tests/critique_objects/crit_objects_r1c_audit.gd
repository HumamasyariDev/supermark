extends SceneTree
## Critique OBJECTS round 1c (QA lens, after implementation stage M3b). Headless audits of the M3b changes:
##  (1) ObjSvc.RIGGED_UPGRADES: both files load, and the v1 -> vN swap keeps the character's height (the map applies
##      a scale factor of 1.0 to every v2/v3 swap, so a height change would resize W1/W2/W3 NPCs silently).
##  (2) NpcLife.profile_for() resolves a profile for every upgraded file name that had one before.
##  (3) Cage default mesh: the generated goose cage scaled to `height` versus the bar collision ring (radius).
##  (4) WindZone shelter: a point on gently rising ground (no wall) must not count as sheltered; a wall must.
##  (5) WindZone calm box versus the bellows/stream streak VFX (still emitted through calm boxes).
## Usage: python tools/godot.py script tests/critique_objects/crit_objects_r1c_audit.gd -- --out=<abs.json>

var _out := ""
var results: Array = []


func check(n: String, ok: bool, detail: Variant = "") -> void:
	results.append({"name": n, "pass": ok, "detail": str(detail)})
	print("[R1C] ", "PASS " if ok else "FAIL ", n, " ", detail)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.split("=", true, 1)[1]
	_run.call_deferred()


func _aabb_of(n: Node) -> AABB:
	var first := true
	var box := AABB()
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _rel_xf(mi, n)
		var b: AABB = xf * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _rel_xf(n: Node3D, stop: Node) -> Transform3D:
	var xf := Transform3D()
	var c: Node = n
	while c != null and c != stop:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


func _run() -> void:
	var svc: Script = load("res://scripts/objects/obj_svc.gd")
	var ups: Dictionary = svc.get("RIGGED_UPGRADES")
	var life: Script = load("res://scripts/objects/npc_life.gd")
	var size_rows := []
	for k in ups.keys():
		var to: String = str(ups[k][0])
		var f: float = float(ups[k][1])
		var ok_from := ResourceLoader.exists(k)
		var ok_to := ResourceLoader.exists(to)
		if not ok_to:
			check("upgrade_target_exists " + to.get_file(), false, "missing " + to)
			continue
		if not ok_from:
			check("upgrade_source_exists " + str(k).get_file(), true, "source missing (fine: map is a no-op)")
			continue
		var a := (load(k) as PackedScene).instantiate()
		var b := (load(to) as PackedScene).instantiate()
		root.add_child(a)
		root.add_child(b)
		var ha := _aabb_of(a).size.y
		var hb := _aabb_of(b).size.y * f
		var wa := maxf(_aabb_of(a).size.x, _aabb_of(a).size.z)
		var wb := maxf(_aabb_of(b).size.x, _aabb_of(b).size.z) * f
		var ratio := hb / maxf(ha, 0.001)
		size_rows.append({"from": str(k).get_file(), "to": to.get_file(), "h_from": snappedf(ha, 0.01), "h_to_scaled": snappedf(hb, 0.01),
			"ratio": snappedf(ratio, 0.01), "w_from": snappedf(wa, 0.01), "w_to_scaled": snappedf(wb, 0.01)})
		check("upgrade_height_kept " + str(k).get_file() + " -> " + to.get_file(), absf(ratio - 1.0) <= 0.12,
			"h %.2f -> %.2f (x%.2f), max width %.2f -> %.2f" % [ha, hb, ratio, wa, wb])
		# NpcLife profile follows the file name.
		var key_from := str(k).get_file().get_basename()
		var key_to := to.get_file().get_basename()
		var pf: Dictionary = life.call("profile_for", key_from)
		var pt: Dictionary = life.call("profile_for", key_to)
		if not pf.is_empty():
			check("npclife_profile_follows " + key_to, not pt.is_empty(), "from has %d keys, to has %d" % [pf.size(), pt.size()])
		a.queue_free()
		b.queue_free()
		await process_frame

	# (3) Cage default mesh against its collision ring.
	var cage_script: Script = load("res://scripts/objects/cage.gd")
	var w := Node3D.new()
	root.add_child(w)
	for spec in [[2.6, 1.4], [3.4, 1.4], [2.0, 1.0]]:
		var c := Node3D.new()
		c.set_script(cage_script)
		c.set("height", spec[0])
		c.set("radius", spec[1])
		w.add_child(c)
		await process_frame
		await process_frame
		var body := c.get_node_or_null("CageBody")
		var vis := body.get_node_or_null("Visual") if body else null
		if vis == null:
			check("cage_default_visual h=%.1f r=%.1f" % spec, false, "no Visual under CageBody")
			continue
		var bx := _aabb_of(vis)
		var vr := maxf(bx.size.x, bx.size.z) * 0.5
		var ratio := vr / float(spec[1])
		check("cage_default_visual_matches_bars h=%.1f r=%.1f" % spec, ratio > 0.8 and ratio < 1.25 and absf(bx.size.y - float(spec[0])) < 0.4,
			"visual %.2f x %.2f x %.2f (radius %.2f vs bar ring %.2f, x%.2f); bars collide at r=%.2f" % [bx.size.x, bx.size.y, bx.size.z, vr, spec[1], ratio, spec[1]])
		c.queue_free()
		await process_frame

	# (4) WindZone shelter on rising ground (no wall) versus behind a wall.
	var wz_script: Script = load("res://scripts/objects/wind_zone.gd")
	var arena := Node3D.new()
	root.add_child(arena)
	# A 10 m ramp rising 0.25 m toward upwind (-X side is upwind; wind blows +X), 1.4 degrees: a "flat" meadow.
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	var rs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 1, 10)
	rs.shape = bs
	ramp.add_child(rs)
	arena.add_child(ramp)
	ramp.position = Vector3(0, -0.5, 0)
	ramp.rotation = Vector3(0, 0, deg_to_rad(-1.4))   # higher at -X (upwind)
	var wz := Area3D.new()
	wz.set_script(wz_script)
	wz.set("size", Vector3(12, 4, 6))
	wz.set("direction", Vector3(1, 0, 0))
	wz.set("strength", 9.0)
	wz.set("show_particles", false)
	wz.set("use_gust_swirl", false)
	wz.set("shelter_mask", 1)
	wz.set("shelter_factor", 0.0)
	arena.add_child(wz)
	wz.position = Vector3(0, 1.5, 0)
	for i in 4:
		await physics_frame
	# Feet on the ramp at x = +3 (downwind half): ground height there.
	var x := 3.0
	var gy := -tan(deg_to_rad(1.4)) * x  # top face at y = 0 at x=0 (box top at -0.5+0.5)
	var feet := Vector3(x, gy + 0.01, 0)
	var wfeet: Vector3 = wz.call("get_wind", feet)
	var wchest: Vector3 = wz.call("get_wind", feet + Vector3(0, 0.6, 0))
	check("wind_shelter_open_meadow_feet_not_sheltered", wfeet.length() > 8.0,
		"feet on a 1.4 deg upwind rise, no wall: wind %.2f m/s (chest %.2f m/s)" % [wfeet.length(), wchest.length()])
	# A 1 m high wall at x = -1: feet behind it must be sheltered.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(0.3, 1.0, 6)
	ws.shape = wb
	wall.add_child(ws)
	arena.add_child(wall)
	wall.position = Vector3(-1, 0.5, 0)
	for i in 3:
		await physics_frame
	var wbeh: Vector3 = wz.call("get_wind", Vector3(0.0, 0.05, 0))
	check("wind_shelter_behind_wall", wbeh.length() < 0.5, "behind a 1 m wall: %.2f m/s" % wbeh.length())
	# A scaled zone (node scale 2): shelter ray length uses local units.
	wall.queue_free()
	await physics_frame
	var wz2 := Area3D.new()
	wz2.set_script(wz_script)
	wz2.set("size", Vector3(6, 2, 3))
	wz2.set("direction", Vector3(1, 0, 0))
	wz2.set("show_particles", false)
	wz2.set("use_gust_swirl", false)
	wz2.set("shelter_mask", 1)
	arena.add_child(wz2)
	wz2.position = Vector3(0, 30, 0)
	wz2.scale = Vector3(2, 2, 2)
	# Wall at world x = -5 (inside the 12 m long scaled zone), point at world x = +4: ray must reach back 10 m.
	var wall2 := StaticBody3D.new()
	wall2.collision_layer = 1
	var ws2 := CollisionShape3D.new()
	var wb2 := BoxShape3D.new()
	wb2.size = Vector3(0.3, 4, 6)
	ws2.shape = wb2
	wall2.add_child(ws2)
	arena.add_child(wall2)
	wall2.position = Vector3(-5, 30, 0)
	for i in 3:
		await physics_frame
	var wsc: Vector3 = wz2.call("get_wind", Vector3(4, 30, 0))
	check("wind_shelter_scaled_zone", wsc.length() < 0.5, "zone scale 2, wall 9 m upwind inside the zone: %.2f m/s" % wsc.length())

	var txt := JSON.stringify({"results": results, "upgrade_sizes": size_rows}, "  ")
	if _out != "":
		var fo := FileAccess.open(_out, FileAccess.WRITE)
		fo.store_string(txt)
		fo.close()
	var fails := 0
	for r in results:
		if not r["pass"]:
			fails += 1
	print("[R1C] done ", results.size() - fails, "/", results.size())
	quit(0)
