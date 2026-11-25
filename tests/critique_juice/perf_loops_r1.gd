extends Node3D
## Critique JUICE r1, PERFORMANCE lens: freed loop owners. Mak (or an enemy) is freed while an attached loop runs:
## a death or a level exit mid belly slide, an enemy freed while dizzy. Checks the Juice VFX loop table, the
## JuiceSfx sound loop, and whether the sound is still playing seconds later, then frees through a scene change.
##   python tools/godot.py run res://tests/critique_juice/PerfLoopsR1.tscn --seconds 120 -- --profile=crit_juice_perf --out=<abs dir>

var out := ""
var results := {}


func _log(msg: String) -> void:
	print("[CritJuiceLoops] ", msg)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if out == "":
		out = OS.get_user_data_dir().path_join("crit_juice_perf")
	Engine.max_fps = 60
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 3, 9)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	_run.call_deferred()


func _sfx_loop_state() -> Dictionary:
	var sfx := Juice.get_node_or_null("JuiceSfx")
	if sfx == null:
		return {"juicesfx": false}
	var loops: Dictionary = sfx.get("_loops")
	var d := {"juicesfx_loops": loops.size(), "playing": []}
	for id in loops:
		var l: Dictionary = loops[id]
		var p: Variant = l.get("player")
		if is_instance_valid(p):
			(d["playing"] as Array).append("%s:%s" % [id, str((p as Node).get("playing"))])
	return d


func _run() -> void:
	await _frames(30)
	# The player node stands in for Mak: a Node3D that emits the slide start (as mak_player.gd does) and is freed
	# without the slide end (scene change on death or level exit).
	var mak := Node3D.new()
	mak.name = "FakeMak"
	add_child(mak)
	Juice.event("player_slide_start", Vector3.INF, {"node": mak, "impact": 8.0, "surface": "grass"})
	var wolf := Node3D.new()
	add_child(wolf)
	wolf.position = Vector3(2, 0, 0)
	Juice.event("enemy_stunned", wolf.global_position + Vector3.UP, {"node": wolf, "family": "woolly_wolf"})
	await _frames(10)
	results["during"] = {"juice_loops": (Juice.get("_loops") as Dictionary).size(), "sfx": _sfx_loop_state()}
	mak.queue_free()
	wolf.queue_free()
	await _frames(2)
	_log("owners freed; watching 3 s (errors per frame below mean JuiceSfx._process aborts)")
	var t0 := Time.get_ticks_msec()
	await _frames(180)
	results["after_3s"] = {"juice_loops": (Juice.get("_loops") as Dictionary).size(), "sfx": _sfx_loop_state(),
		"elapsed_ms": Time.get_ticks_msec() - t0}
	_log("after 3 s: " + JSON.stringify(results.after_3s))
	# Juice.stop_loops() is what every scene change calls.
	Juice.stop_loops()
	results["after_stop_loops"] = {"juice_loops": (Juice.get("_loops") as Dictionary).size(), "sfx": _sfx_loop_state()}
	_log("after Juice.stop_loops(): " + JSON.stringify(results.after_stop_loops))
	await _frames(60)
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("loops_freed_owner.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	_log("done " + JSON.stringify(results))
	get_tree().quit()
