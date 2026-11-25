extends Node
## Entry test (boss track): boots the real hub through the Router, finds the Wolf's Door, walks the REAL player
## through it with world-space replay input (no teleport through the doorway: Mak is placed 4 m in front of the
## door and walks), and checks that the Router lands in WolfRooftop with the fight running.
## Run: python tools/godot.py run res://scenes/boss/BossEntryTest.tscn --seconds 90 -- --unlock-all --profile=boss_entry
## Writes Docs/progress/boss/<UTC>__entry_from_hub_results.json plus two native captures (door, arena arrival).

var _f := 0
var _phase := "boot"
var _door: Node3D
var _t_phase := 0
var _res := {"steps": []}
var _shots: Array = []


func _ready() -> void:
	process_physics_priority = -100
	# Survive the scene changes: the scene node spawns a runner under /root and stays inert.
	if name != "BossEntryRunner":
		set_physics_process(false)
		var runner := Node.new()
		runner.name = "BossEntryRunner"
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		var r := get_node_or_null("/root/Router")
		if r != null:
			r.call("go_to_hub", ""))


func _log(s: String) -> void:
	print("[BossEntry] ", s)
	(_res["steps"] as Array).append({"f": _f, "s": s})


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _stick(p: Node3D, v: Vector2) -> void:
	var inp: Object = p.get("inp")
	if inp == null:
		return
	inp.set("replay_active", true)
	inp.set("steer_world", true)
	inp.set("_r_stick", v)


func _physics_process(_d: float) -> void:
	_f += 1
	_t_phase += 1
	if _f > 60 * 80:
		_finish(false, "timeout in " + _phase)
		return
	var scene := get_tree().current_scene
	match _phase:
		"boot":
			if scene != null and scene.scene_file_path.ends_with("Hub.tscn") and _player() != null:
				_door = get_tree().get_first_node_in_group("wolf_door") as Node3D
				if _door == null:
					return
				_log("hub loaded, door at %s unlocked=%s" % [str(_door.global_position.snapped(Vector3.ONE * 0.01)), str(_door.get("is_unlocked"))])
				_set_phase("place")
		"place":
			if _t_phase < 30:
				return
			var p := _player()
			var fwd := _door.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			# Stand on the side of the door that has floor (probe both sides with a ray).
			var side := 1.0
			var space := p.get_world_3d().direct_space_state
			for s in [1.0, -1.0]:
				var a: Vector3 = _door.global_position + fwd * 4.0 * s + Vector3(0, 2.0, 0)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, a + Vector3(0, -4.0, 0), 1))
				if not hit.is_empty():
					side = s
					break
			var at := _door.global_position + fwd * 4.0 * side + Vector3(0, 0.1, 0)
			p.call("respawn", Transform3D(Basis.looking_at(-fwd * side, Vector3.UP), at))
			_res["approach_side"] = side
			_log("Mak placed 4 m in front of the door at %s" % str(at.snapped(Vector3.ONE * 0.01)))
			_set_phase("walk")
		"walk":
			if scene != null and scene.scene_file_path.ends_with("WolfRooftop.tscn"):
				_log("Router changed scene to WolfRooftop")
				_set_phase("arena")
				return
			var p := _player()
			if p == null or not is_instance_valid(_door):
				return
			if _t_phase == 45:
				_shot("door_open_approach")
			var fwd := _door.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() * float(_res["approach_side"])
			var target := _door.global_position - fwd * 3.0
			var d := target - p.global_position
			d.y = 0.0
			var n := d.normalized()
			# Wait for the swing before walking in.
			if not bool(_door.get("is_open")) and _t_phase < 240:
				_stick(p, Vector2.ZERO)
			else:
				_stick(p, Vector2(n.x, -n.z) * 0.8)
		"arena":
			if scene == null or not scene.scene_file_path.ends_with("WolfRooftop.tscn"):
				return
			var boss: Variant = scene.get("boss")
			if _t_phase == 400:
				_shot("arrival_in_arena")
			if _t_phase == 430:
				_res["boss_state"] = String(boss.get("state")) if boss != null else ""
				_res["world_id"] = String(scene.get("world_id"))
				var g := get_node_or_null("/root/Game")
				_res["current_world"] = String(g.get("current_world")) if g != null else ""
				_finish(boss != null and _res["world_id"] == "BOSS", "arrived")


func _set_phase(p: String) -> void:
	_phase = p
	_t_phase = 0


func _shot(cap: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var dir := ProjectSettings.globalize_path("res://").path_join("../Docs/progress/boss").simplify_path()
	var path := dir.path_join("%sZ__entry_%s.png" % [stamp, cap])
	img.save_png(path)
	_shots.append(path)
	_log("capture " + path)


func _finish(ok: bool, why: String) -> void:
	set_physics_process(false)
	_res["passed"] = ok
	_res["why"] = why
	_res["captures"] = _shots
	_res["utc"] = Time.get_datetime_string_from_system(true)
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var dir := ProjectSettings.globalize_path("res://").path_join("../Docs/progress/boss").simplify_path()
	var f := FileAccess.open(dir.path_join("%sZ__entry_from_hub_results.json" % stamp), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_res, "  "))
		f.close()
	print("[BossEntry] %s (%s)" % ["PASS" if ok else "FAIL", why])
	get_tree().create_timer(1.0, true).timeout.connect(func() -> void: get_tree().quit())
