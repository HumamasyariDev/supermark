extends "res://tests/critique_hub/crit_hub_qa_r1.gd"
## CRITIC round 2, QA AND TECHNICAL lens, HUB (night 01). Test-only; no level uses it.
## Re-uses the round-1 harness (probe / exploit / exploit2 / cub / fps / fps12) and adds:
##   --qa=probe2  the r1 static probe, plus: characters on screen (real GLB or primitive), ledger plan vs placed groups,
##                forced acorn bursts (tea chest AG11, dome bong AG15, cub drop AG18 at several catch spots) checked for
##                acorns inside solids or floating, clock sockets, portals and their thresholds
##   --qa=save    save and progress: collect ledger acorns with the real player body, check the flags reach the save file,
##                wake the impostor, reload the save and the hub mid-chase (chase must reset, acorns must not respawn),
##                then catch the cub and check hub_cub_done / hat_bowler / the AG18 drop survive a second reload
##   --qa=fps2    windowed 1920x1080 frame times at gameplay spots and the current story cameras (A_v6, E-J)
## Run: python tools/godot.py run res://tests/critique_hub/CritHubQaR2.tscn --seconds 600 -- --profile=crit_hub_qa_r2_<mode>_<stamp> --qa=<mode> --qa_out=<abs dir>

var _sv_phase := ""
var _sv_t := 0.0
var _sv_reloads := 0
var _sv_c0 := 0
var _sv_targets: Array = []
var _sv_ti := 0
var _sv_wait := 0


func _log(s: String) -> void:
	super._log(s)
	if out_dir != "":
		var path := out_dir.path_join("qa_%s_live.log" % mode)
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if f:
			f.seek_end()
			f.store_line(s)
			f.close()


func _physics_process(delta: float) -> void:
	if not has_meta("driver") or _done:
		return
	if mode != "probe2" and mode != "save" and mode != "fps2":
		super._physics_process(delta)
		return
	var sc := get_tree().current_scene
	if sc == null or sc.name != "Hub":
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
		_wait = 150
		_log("[QA] hub loaded, player found (reloads so far %d)" % _sv_reloads)
	if _wait > 0:
		_wait -= 1
		return
	if not _started:
		_started = true
		match mode:
			"probe2":
				_probe(sc)
				await _probe2(sc)
				_finish()
			"save":
				_save_begin(sc)
			"fps2":
				_fps2_start(sc)
		return
	if mode == "save":
		_save_step(sc, delta)


func _process(delta: float) -> void:
	if not has_meta("driver") or _done or not _started:
		return
	if mode == "fps" or mode == "fps12" or mode == "fps2":
		_fps_step(delta)


# ======================================================================= PROBE 2

func _probe2(sc: Node) -> void:
	var space := (sc as Node3D).get_world_3d().direct_space_state
	var level := sc.get_node_or_null("Level")
	# --- characters: every node that looks like a creature, and what draws it
	var char_words := ["bramwell", "wolf", "cub", "sheep", "owl", "goose", "pip", "reginald", "grandfather", "butterfl", "impostor", "bird", "mouse", "cat"]
	var seen := {}
	for n in sc.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower()
		var hit := false
		for w in char_words:
			if nm.contains(w):
				hit = true
				break
		if not hit:
			continue
		var p := String(n.get_path())
		var skip := false
		for k in seen.keys():
			if p.begins_with(String(k) + "/"):
				skip = true
				break
		if skip:
			continue
		seen[p] = true
		var meshes := (n as Node).find_children("*", "MeshInstance3D", true, false)
		if n is MeshInstance3D:
			meshes.append(n)
		var prims := 0
		var arrays := 0
		var glb := 0
		var src := ""
		for m in meshes:
			var mi := m as MeshInstance3D
			if mi.mesh is PrimitiveMesh:
				prims += 1
			elif mi.mesh is ArrayMesh:
				arrays += 1
				var owner_scene := ""
				var o := mi.owner
				if o and o.scene_file_path != "":
					owner_scene = o.scene_file_path
				if owner_scene.ends_with(".glb") or owner_scene.ends_with(".gltf"):
					glb += 1
					src = owner_scene
		var vis := (n as Node3D).is_visible_in_tree()
		_log("[QA][char] %s visible=%s meshes=%d glb_meshes=%d array=%d primitive=%d src=%s pos=%s" % [p.replace(String(sc.get_path()) + "/", ""), vis, meshes.size(), glb, arrays, prims, src, (n as Node3D).global_position])
	# --- primitive-mesh census of everything visible (sizeable ones only)
	var prim_big: Array = []
	for m2 in sc.find_children("*", "MeshInstance3D", true, false):
		var mi2 := m2 as MeshInstance3D
		if mi2.mesh is PrimitiveMesh and mi2.is_visible_in_tree():
			var bb := mi2.get_aabb()
			var s := bb.size * mi2.global_basis.get_scale()
			if maxf(s.x, maxf(s.y, s.z)) > 0.5 and not (mi2.mesh is PlaneMesh or mi2.mesh is QuadMesh):
				prim_big.append("%s(%s %.1fm)" % [String(mi2.get_path()).get_file(), mi2.mesh.get_class(), maxf(s.x, maxf(s.y, s.z))])
	_log("[QA][prims] visible primitive meshes larger than 0.5 m: %d %s" % [prim_big.size(), prim_big.slice(0, 40)])
	# --- ledger plan vs placed
	if level:
		var plan: Dictionary = level.get("LEDGER_PLAN") if level.get("LEDGER_PLAN") != null else {}
		var groups: Dictionary = level.get("_ledger_groups")
		_log("[QA][ledger] total=%d count=%d placed_groups=%s" % [int(level.call("ledger_total")), int(level.call("ledger_count")), groups])
		for k in plan.keys():
			var placed := int(groups.get(k, -1))
			var flag := ""
			if placed >= 0 and placed != int(plan[k]):
				flag = " [FAIL placed %d != plan %d]" % [placed, int(plan[k])]
			_log("[QA][ledger] %s plan=%d placed=%d%s" % [k, int(plan[k]), placed, flag])
		# Forced bursts: tea chest, dome bong, and the cub drop at catch spots round the loop.
		level.call("_burst_ledger", "AG11_crate", Vector3(6.85, 4.5, 12.89), 0.9, 5)
		level.call("dome_bong_acorns")
		var acts := level.get_node_or_null("Activities")
		var spots := [Vector3(-11.6, 0, -1.6), Vector3(-6.0, 0, -6.0), Vector3(4.2, 0, -10.2), Vector3(11.0, 0, -3.0), Vector3(11.4, 0, 4.0), Vector3(-11.4, 0, 7.0), Vector3(0.0, 2.3, -8.25), Vector3(-3.0, 0, -10.5)]
		if acts:
			for i in spots.size():
				var holder_name := "AG18_cub_drop"
				var old := acts.get_node_or_null(holder_name)
				if old:
					old.name = "AG18_old_%d" % i
				acts.call("_cub_acorns", spots[i])
				var h := acts.get_node_or_null(holder_name)
				if h:
					h.name = "AG18_spot%d" % i
		await get_tree().create_timer(1.5).timeout
		for holder in sc.find_children("AG1*", "Node3D", true, false):
			var hn := String(holder.name)
			if not (hn.begins_with("AG11") or hn.begins_with("AG15") or hn.begins_with("AG18")):
				continue
			var bad := 0
			var lines: Array = []
			for a in holder.get_children():
				var ap: Vector3 = (a as Node3D).global_position
				var pq := PhysicsPointQueryParameters3D.new()
				pq.position = ap + Vector3(0, 0.25, 0)
				pq.collision_mask = 1
				var inside := space.intersect_point(pq, 1)
				var dn := _ray(space, ap + Vector3(0, 0.3, 0), ap + Vector3(0, -6.0, 0))
				var gap := ap.y - ((dn["position"] as Vector3).y if not dn.is_empty() else -99.0)
				var tag := ""
				if not inside.is_empty():
					tag = "INSIDE %s" % (inside[0]["collider"] as Node).name
					bad += 1
				elif gap > 1.6:
					tag = "floating %.2f" % gap
					bad += 1
				lines.append("%s%s" % [ap.snapped(Vector3(0.01, 0.01, 0.01)), (" " + tag) if tag != "" else ""])
			_log("[QA][burst] %s n=%d bad=%d %s" % [hn, holder.get_child_count(), bad, lines])
	# --- clock sockets
	var clock := sc.find_child("*Clock*", true, false)
	for c in sc.find_children("*", "Node3D", true, false):
		var scr: Script = c.get_script()
		if scr and String(scr.resource_path).ends_with("hub_clock.gd"):
			clock = c
			break
	if clock:
		_log("[QA][clock] %s socket ids const=%s" % [clock.get_path(), clock.get("SOCKET_IDS") if clock.get("SOCKET_IDS") != null else "?"])
	_log("[QA][unlocks] %s" % [(get_node("/root/Game").get("data") as Dictionary).get("unlocks", {}).keys()])
	_log("[QA][hats] available=%s" % [get_node("/root/Game").call("available_hats")])


# ======================================================================= SAVE / PROGRESS

func _acorn_nodes(sc: Node, prefix: String) -> Array:
	var out: Array = []
	for holder in sc.find_children(prefix + "*", "Node3D", true, false):
		for a in holder.get_children():
			if a is Area3D:
				out.append(a)
	return out


func _save_begin(sc: Node) -> void:
	var level := sc.get_node_or_null("Level")
	_sv_c0 = int(level.call("ledger_count"))
	_sv_targets = _acorn_nodes(sc, "AG02") + _acorn_nodes(sc, "AG07").slice(0, 2)
	_log("[QA][save] start: ledger %d / %d, targets %d, profile save %s" % [_sv_c0, int(level.call("ledger_total")), _sv_targets.size(), get_node("/root/Game").call("save_path")])
	_sv_phase = "collect"
	_sv_ti = 0
	_sv_wait = 0


func _read_save_unlocks() -> Dictionary:
	var g := get_node("/root/Game")
	var path := String(g.call("save_path"))
	if not FileAccess.file_exists(path):
		return {"_missing": path}
	var txt := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return {"_unparsable": path}
	return (d as Dictionary).get("unlocks", {})


func _save_step(sc: Node, delta: float) -> void:
	_sv_t += delta
	var level := sc.get_node_or_null("Level")
	var acts := level.get_node_or_null("Activities") if level else null
	_release()
	match _sv_phase:
		"collect":
			if _sv_wait > 0:
				_sv_wait -= 1
				return
			if _sv_ti >= _sv_targets.size():
				_sv_phase = "check1"
				_sv_wait = 30
				return
			var a: Variant = _sv_targets[_sv_ti]
			_sv_ti += 1
			if is_instance_valid(a):
				_player.call("respawn", Transform3D(Basis(), (a as Node3D).global_position + Vector3(0, -0.1, 0)))
			_sv_wait = 20
		"check1":
			if _sv_wait > 0:
				_sv_wait -= 1
				return
			var c1 := int(level.call("ledger_count"))
			var su := _read_save_unlocks()
			var flags_on_disk := 0
			for k in su.keys():
				if String(k).begins_with("hub_acorn_"):
					flags_on_disk += 1
			_log("[QA][save] after collecting %d acorns: ledger %d (was %d), hub_acorn flags in the save file: %d, acorns_total=%s" % [_sv_targets.size(), c1, _sv_c0, flags_on_disk, (get_node("/root/Game").get("data") as Dictionary).get("acorns_total")])
			if c1 - _sv_c0 != _sv_targets.size():
				_log("[QA][save][FAIL] ledger moved by %d, expected %d" % [c1 - _sv_c0, _sv_targets.size()])
			# Wake the impostor by walking at Book 1 from beyond 6.5 m.
			_player.call("respawn", Transform3D(Basis.looking_at(Vector3(-7.07, 0, 7.07) - Vector3(-1.0, 0, 10.4), Vector3.UP), Vector3(-1.0, 0.05, 10.4)))
			_sv_phase = "wake"
			_sv_t = 0.0
		"wake":
			_toward(Vector3(-7.07, 0, 7.07), 0.5)
			var st := String(acts.get("_cub_state"))
			if st == "run":
				_log("[QA][save] impostor running after %.2f s; chase_active=%s; reloading the save and the hub mid-chase" % [_sv_t, acts.call("chase_active")])
				_sv_phase = "reload1"
			elif _sv_t > 12.0:
				_log("[QA][save][FAIL] impostor never started running (state %s)" % st)
				_sv_phase = "reload1"
		"reload1":
			_reload_hub("after_chase_start")
		"after_chase_start":
			var c2 := int(level.call("ledger_count"))
			var left := _acorn_nodes(sc, "AG02").size()
			var st2 := String(acts.get("_cub_state")) if acts else "?"
			var b1 := (level.get("portals") as Dictionary).get("W1") as Node
			_log("[QA][save] after reload 1: ledger %d (before reload %d), AG02 acorns rebuilt %d (0 expected), impostor state %s (rug expected), Book 1 bounce guard %s" % [c2, _sv_c0 + _sv_targets.size(), left, st2, b1.get_node_or_null("Book1ChaseBounce") != null if b1 else "?"])
			if c2 != _sv_c0 + _sv_targets.size():
				_log("[QA][save][FAIL] ledger not persisted across reload")
			if left != 0:
				_log("[QA][save][FAIL] collected acorns respawned")
			if st2 != "rug":
				_log("[QA][save][FAIL] chase state survived the reload")
			# Catch the cub: wake, reveal, wait for a skid / dizzy, hit.
			_player.call("respawn", Transform3D(Basis.looking_at(Vector3(-7.07, 0, 7.07) - Vector3(-1.0, 0, 10.4), Vector3.UP), Vector3(-1.0, 0.05, 10.4)))
			_sv_phase = "catch"
			_sv_t = 0.0
		"catch":
			var st3 := String(acts.get("_cub_state"))
			if st3 == "rug":
				_toward(Vector3(-7.07, 0, 7.07), 0.5)
			elif st3 == "run":
				acts.call("cub_hit", "punch")
			elif st3 == "skid" or st3 == "dizzy":
				# Park Mak away from the cub first, so the acorn magnet (1.8 m) does not swallow the drop at once.
				var cubn := acts.get("_cub") as Node3D
				var best := Vector3(0, 0.05, 11.5)
				for cand in [Vector3(0, 0.05, 11.5), Vector3(-10.5, 0.05, 1.8), Vector3(9.0, 0.05, -4.0), Vector3(-3.0, 0.05, -10.6)]:
					if cubn and cand.distance_to(cubn.global_position) > best.distance_to(cubn.global_position):
						best = cand
				_player.call("respawn", Transform3D(Basis(), best))
				acts.call("cub_hit", "punch")
			elif st3 == "caught" or st3 == "gone":
				_log("[QA][save] cub caught at t=%.2f; hub_cub_done=%s hat_bowler=%s available_hats=%s" % [_sv_t, get_node("/root/Game").call("has_flag", "hub_cub_done"), get_node("/root/Game").call("has_flag", "hat_bowler"), get_node("/root/Game").call("available_hats")])
				var drop := _acorn_nodes(sc, "AG18").filter(func(x): return is_instance_valid(x))
				_log("[QA][save] AG18 drop acorns live: %d at %s" % [drop.size(), drop.map(func(x): return (x as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
				# Pick up three of them, leave five, then reload: five should wait by the rug.
				_sv_targets = drop.slice(0, 3)
				_sv_ti = 0
				_sv_phase = "collect2"
				_sv_wait = 90
			if _sv_t > 60.0:
				_log("[QA][save][FAIL] catch did not finish in 60 s (state %s)" % st3)
				_finish()
		"collect2":
			if _sv_wait > 0:
				_sv_wait -= 1
				return
			if _sv_ti >= _sv_targets.size():
				_sv_phase = "reload2"
				return
			var a2: Variant = _sv_targets[_sv_ti]
			_sv_ti += 1
			if is_instance_valid(a2):
				_player.call("respawn", Transform3D(Basis(), (a2 as Node3D).global_position + Vector3(0, -0.1, 0)))
			else:
				_log("[QA][save] drop acorn %d already collected (magnet) before the scripted pickup" % (_sv_ti - 1))
			_sv_wait = 20
		"reload2":
			_reload_hub("after_catch")
		"after_catch":
			var drop2 := _acorn_nodes(sc, "AG18")
			var rug := acts.get_node_or_null("SheepskinRug") as Node3D if acts else null
			_log("[QA][save] after reload 2: ledger %d / %d, AG18 acorns waiting %d (5 expected) at %s, rug visible=%s at %s, impostor node=%s, Book 1 bounce guard=%s" % [int(level.call("ledger_count")), int(level.call("ledger_total")), drop2.size(), drop2.map(func(x): return (x as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1))), rug.visible if rug else "?", rug.global_position if rug else "?", acts.get("_cub"), ((level.get("portals") as Dictionary).get("W1") as Node).get_node_or_null("Book1ChaseBounce") != null])
			var su2 := _read_save_unlocks()
			_log("[QA][save] save file: hub_cub_done=%s hat_bowler=%s hub_acorn flags=%d" % [su2.has("hub_cub_done"), su2.has("hat_bowler"), su2.keys().filter(func(k): return String(k).begins_with("hub_acorn_")).size()])
			_finish()


func _reload_hub(next_phase: String) -> void:
	_sv_reloads += 1
	var g := get_node("/root/Game")
	var ok := bool(g.call("load_game"))
	g.call("set_transient_flag", "hub_intro_seen", true)
	_log("[QA][save] Game.load_game() -> %s; reloading %s" % [ok, HUB])
	_player = null
	_sv_phase = next_phase
	_started = true
	get_tree().change_scene_to_file(HUB)


# ======================================================================= FPS 2

func _fps2_start(sc: Node) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_log("[QA][fps] window=%s viewport=%s vsync=%d max_fps=%d screen=%s" % [DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, DisplayServer.window_get_vsync_mode(), Engine.max_fps, DisplayServer.screen_get_size()])
	_fps_points = [
		["spawn_default", Vector3(0, 0.05, 11.5), Vector3(0, 0, 0), ""],
		["intro_mark_look_north", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), ""],
		["book1_side", Vector3(-4.0, 0.05, 9.0), Vector3(-7, 0, 7), ""],
		["fireside", Vector3(-10.5, 0.05, 1.8), Vector3(0, 0, 0), ""],
		["nook", Vector3(-3.0, 0.05, -10.6), Vector3(0, 0, -11.8), ""],
		["stair_landing_look_south", Vector3(0.0, 2.35, -8.25), Vector3(0, 2, 10), ""],
		["gallery_east", pp(13.4, 80.0, 4.55), Vector3(0, 4.5, 0), ""],
		["balcony_outdoor", Vector3(0, 4.55, 19.5), Vector3(0, 4.5, 30), ""],
		["cornice_a", pp(15.2, 115.0, 8.55), pp(15.2, 140.0, 8.5), ""],
		["top_balcony", pp(14.6, 186.0, 9.75), Vector3(0, 5, 0), ""],
		["rim", Vector3(0, 9.15, 2.6), Vector3(0, 9, -5), ""],
		["cam_A_v6", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_A_v6"],
		["cam_B", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_B"],
		["cam_C", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_C"],
		["cam_D", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_D"],
		["cam_E", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_E"],
		["cam_H", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_H"],
		["TitleCam", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "TitleCam"],
	]
	_fps_i = -1
	_fps_next(sc)
