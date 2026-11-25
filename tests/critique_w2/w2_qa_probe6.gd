extends Node
## Critique W2 round 1 (QA lens, pass r1c), probe 6. Read-only for the world.
##  R ray-invisible floor map: over the castle level (y 75 -> 40) and the garden/stalk level, compare what the
##    player's own body sweep lands on (test_move) with what a mask-1 ray finds (the ray w2_fix2's void catch
##    uses). Lists colliders the body lands on that the ray does not see.
##  G gatehouse drop: stand on S1's gatehouse roof (safe ground y 61.4), then drop onto the ray-invisible apron
##    and log whether the void catch throws Mak back up instead of letting him land.
## Run: python tools/godot.py capture res://tests/critique_w2/W2QA.tscn <png> --wait 999999 -- --profile=critic_w2_qa_p6 --w2-nointro --qa-probe=6 --qa-out=<abs dir>

var out_dir := ""
var world: Node
var player: CharacterBody3D
var report := {}
var _t0 := 0
var _trace_on := false
var _trace: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w2_qa6")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _physics_process(_d: float) -> void:
	if _trace_on and player:
		_trace.append([Time.get_ticks_msec() - _t0, player.global_position, player.is_on_floor(), player.velocity.y])


func _process(_d: float) -> void:
	if Time.get_ticks_msec() - _t0 > 280000:
		report["aborted"] = "cap"
		_save()
		get_tree().quit(3)


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _save() -> void:
	var f := FileAccess.open(out_dir.path_join("w2_qa_probe6.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()


func _ray(p: Vector3, dist: float, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -dist, 0), mask)
	return player.get_world_3d().direct_space_state.intersect_ray(q)


func _run() -> void:
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null and cs.get("play") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - _t0 > 180000:
			get_tree().quit(2)
			return
	await _wait(2.0)
	report["player_mask"] = player.collision_mask
	report["player_layer"] = player.collision_layer
	# R: map.
	report["_phase"] = "R"
	var found := {}
	var samples := 0
	for band: Array in [[75.0, 40.0, -30, 30, -46, -6], [40.0, 15.0, -30, 30, -30, 10], [15.0, -5.0, -40, 40, -10, 45]]:
		var y0: float = band[0]
		var y1: float = band[1]
		for gx in range(int(band[2]), int(band[3]) + 1, 2):
			for gz in range(int(band[4]), int(band[5]) + 1, 2):
				samples += 1
				var from := Transform3D(Basis(), Vector3(gx, y0, gz))
				var col := KinematicCollision3D.new()
				if not player.test_move(from, Vector3(0, y1 - y0, 0), col, 0.001, true):
					continue
				if col.get_normal().y < 0.7:
					continue
				var hit_y := col.get_position().y
				var r := _ray(Vector3(gx, y0, gz), y0 - y1 + 1.0, 1)
				var ray_y: float = float(r["position"].y) if not r.is_empty() else -999.0
				if absf(ray_y - hit_y) > 0.6:
					var c: Object = col.get_collider()
					var key := str((c as Node).get_path()) if c is Node else "?"
					if not found.has(key):
						var shape_info := ""
						var co := c as CollisionObject3D
						if co:
							var owners := co.get_shape_owners()
							if owners.size() > 0:
								var sh := co.shape_owner_get_shape(owners[0], 0)
								shape_info = sh.get_class()
								if sh is ConcavePolygonShape3D:
									shape_info += " backface=%s" % str((sh as ConcavePolygonShape3D).backface_collision)
						found[key] = {"class": c.get_class() if c else "", "layer": (c as CollisionObject3D).collision_layer if c is CollisionObject3D else -1, "shape": shape_info, "samples": []}
					if (found[key]["samples"] as Array).size() < 6:
						(found[key]["samples"] as Array).append({"xz": [gx, gz], "body_y": snappedf(hit_y, 0.01), "ray_y": snappedf(ray_y, 0.01)})
					found[key]["n"] = int(found[key].get("n", 0)) + 1
	report["R_samples"] = samples
	report["R_ray_invisible"] = found
	_save()
	# G: gatehouse drop.
	report["_phase"] = "G"
	var s1 := Vector3(14.0, 61.4, -25.4)
	var top := _ray(s1 + Vector3(0, 3, 0), 6.0, 0xFFFFFFFF)
	report["G_s1_top"] = _v(top["position"]) if not top.is_empty() else null
	player.call("respawn", Transform3D(Basis(), (top["position"] if not top.is_empty() else s1) + Vector3(0, 0.2, 0)))
	await _wait(1.2)
	report["G_on_s1_floor"] = player.is_on_floor()
	report["G_on_s1_pos"] = _v(player.global_position)
	var targets := [Vector3(10.41, 60.5, -16.31), Vector3(12.0, 60.5, -20.0), Vector3(8.0, 60.5, -19.5)]
	var res := []
	for t: Vector3 in targets:
		player.call("respawn", Transform3D(Basis(), (top["position"] if not top.is_empty() else s1) + Vector3(0, 0.2, 0)))
		await _wait(1.0)
		_trace.clear()
		_trace_on = true
		player.global_position = t
		await _wait(4.0)
		_trace_on = false
		var jumps := []
		var miny := 1e9
		for i in range(1, _trace.size()):
			var a: Vector3 = _trace[i - 1][1]
			var b: Vector3 = _trace[i][1]
			miny = minf(miny, b.y)
			if b.y - a.y > 2.5 or a.distance_to(b) > 6.0:
				jumps.append({"t_ms": _trace[i][0] - _trace[0][0], "from": _v(a), "to": _v(b)})
		var rr := _ray(t, 30.0, 1)
		res.append({"drop_at": _v(t), "ray_floor_y": snappedf(float(rr["position"].y), 0.01) if not rr.is_empty() else null, "teleports": jumps, "end": _v(player.global_position), "end_on_floor": player.is_on_floor(), "min_y": snappedf(miny, 0.01)})
	report["G_drops"] = res
	report["_phase"] = "done"
	_save()
	print("[QA6] done")
	get_tree().quit(0)
