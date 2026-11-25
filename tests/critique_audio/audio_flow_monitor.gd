extends Node
## Critique audio r1: the monitor half of AudioFlowQA (see audio_flow_qa.gd). Lives under /root.

const BUSES := ["Master", "Music", "Ambience", "SFX", "Voice", "Jingle"]

var out_dir := ""
var short := false
var steps: Array = []
var step_i := -1
var step_t := 0.0
var t := 0.0
var waiting_router := false

var logger: Object = null
var players: Dictionary = {}  # instance_id -> {node, was, pos, stream, len, loop}
var refresh_t := 0.0
var tl_t := 0.0
var starts: Array = []
var timeline: Array = []
var marks: Array = []
var conc_max: Dictionary = {}  # scene|bus -> max concurrent
var conc_hist: Dictionary = {}  # bus -> {n: frames}
var drive_on := false
var drive_t := 0.0
var _pressed: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = String(dev.call("arg", "qa-out", "")) if dev else ""
	short = dev != null and bool(dev.call("has_arg", "qa-short"))
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://critique_audio")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if ClassDB.class_exists("Logger") and OS.has_method("add_logger"):
		logger = load("res://tests/critique_audio/qa_logger.gd").new()
		OS.call("add_logger", logger)
	var drive_s := 6.0 if short else 14.0
	steps = [
		{"do": "title", "dur": 8.0},
		{"do": "hub", "dur": 4.0}, {"do": "drive", "dur": drive_s}, {"do": "idle", "dur": 4.0},
		{"do": "world", "w": "W1", "dur": 4.0}, {"do": "drive", "dur": drive_s}, {"do": "idle", "dur": 2.0},
		{"do": "truffle", "id": "W1-5", "dur": 8.0},
		{"do": "reload", "dur": 6.0},
		{"do": "hub", "spawn": "Book_W1", "dur": 6.0},
		{"do": "world", "w": "W2", "dur": 4.0}, {"do": "drive", "dur": drive_s}, {"do": "idle", "dur": 2.0},
		{"do": "die", "dur": 10.0},
		{"do": "world", "w": "W3", "dur": 4.0}, {"do": "drive", "dur": drive_s}, {"do": "idle", "dur": 2.0},
		{"do": "world", "w": "BOSS", "dur": 22.0}, {"do": "drive", "dur": drive_s},
		{"do": "title", "dur": 7.0},
		{"do": "quit", "dur": 0.0},
	]
	var plan := String(dev.call("arg", "qa-plan", "")) if dev else ""
	if plan != "":
		## Single-scene plan: --qa-plan=res://path.tscn --qa-seconds=N (scene loaded with change_scene_to_file).
		steps = [{"do": "scene", "path": plan, "dur": float(dev.call("arg", "qa-seconds", "120"))}, {"do": "quit", "dur": 0.0}]
	var route := String(dev.call("arg", "qa-route", "")) if dev else ""
	if route != "":
		## Critic r2 (audio director): --qa-route=W3,W1 [--qa-drive=25] enters each world through the Router and
		## drives the bot there, to measure enemy and scatter density per world.
		var dr := float(dev.call("arg", "qa-drive", "25"))
		steps = []
		for w in route.split(","):
			steps.append({"do": "world", "w": w.strip_edges(), "dur": 4.0})
			steps.append({"do": "drive", "dur": dr})
			steps.append({"do": "idle", "dur": 4.0})
		steps.append({"do": "quit", "dur": 0.0})
	print("[AudioQA] monitor up, out=", out_dir)
	_next_step()


func _scene_name() -> String:
	var cs := get_tree().current_scene
	if cs == null:
		return "(none)"
	if "world_id" in cs:
		return String(cs.get("world_id"))
	return String(cs.name)


func _mark(what: String) -> void:
	marks.append({"t": snappedf(t, 0.01), "scene": _scene_name(), "mark": what})
	print("[AudioQA] %.2f %s (%s)" % [t, what, _scene_name()])


func _next_step() -> void:
	_release_all()
	drive_on = false
	step_i += 1
	step_t = 0.0
	if step_i >= steps.size():
		_finish()
		return
	var s: Dictionary = steps[step_i]
	var r := get_node_or_null("/root/Router")
	var g := get_node_or_null("/root/Game")
	_mark("step %d %s %s" % [step_i, s["do"], str(s.get("w", s.get("id", s.get("spawn", ""))))])
	waiting_router = false
	match String(s["do"]):
		"title":
			r.call("go_to_title")
			waiting_router = true
		"hub":
			r.call("go_to_hub", String(s.get("spawn", "")))
			waiting_router = true
		"world":
			r.call("enter_world", String(s["w"]), "")
			waiting_router = true
		"reload":
			r.call("reload_at_checkpoint")
			waiting_router = true
		"truffle":
			g.call("collect_truffle", String(s["id"]))
		"scene":
			get_tree().change_scene_to_file(String(s["path"]))
		"die":
			g.call("damage", int(g.get("health")))
		"drive":
			drive_on = true
			drive_t = 0.0
		"quit":
			_finish()


func _process(delta: float) -> void:
	t += delta
	if logger != null:
		logger.set("t", t)
		logger.set("scene_name", _scene_name())
	_track_players()
	tl_t -= delta
	if tl_t <= 0.0:
		tl_t = 0.1
		_timeline_row()
	# r2: checkpoint the data every 15 s so a run killed by the machine cap still leaves evidence
	_ckpt_t -= delta
	if _ckpt_t <= 0.0 and not _saved:
		_ckpt_t = 15.0
		_checkpoint()
	if step_i < 0 or step_i >= steps.size():
		return
	var r := get_node_or_null("/root/Router")
	if waiting_router:
		if r != null and (bool(r.get("busy")) or step_t < 0.2):
			step_t += delta
			if step_t > 60.0:
				_mark("router stuck")
				waiting_router = false
			return
		waiting_router = false
		step_t = 0.0
		_mark("arrived")
	step_t += delta
	_unstick_dialog(delta)
	if drive_on:
		_drive(delta)
	if step_t >= float(steps[step_i]["dur"]):
		_next_step()


# ------------------------------------------------------------------ input

var _dlg_t := 0.0
var blocked_time: Dictionary = {}  # scene -> seconds the UI blocked input


## Input.action_press makes no InputEvent, so dialog boxes (which advance on _input) would hold the
## pad driver forever. Advance any open dialog every 0.35 s, like a player tapping through.
func _unstick_dialog(delta: float) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui == null:
		return
	if ui.has_method("is_input_blocked") and bool(ui.call("is_input_blocked")):
		var k := _scene_name()
		blocked_time[k] = float(blocked_time.get(k, 0.0)) + delta
	var d: Variant = ui.get("dialog")
	if d is Node and is_instance_valid(d) and d.has_method("is_open") and bool(d.call("is_open")):
		_dlg_t -= delta
		if _dlg_t <= 0.0:
			_dlg_t = 0.35
			d.call("advance")
			marks.append({"t": snappedf(t, 0.01), "scene": _scene_name(), "mark": "dialog advance"})

func _press(a: String, strength: float = 1.0) -> void:
	if InputMap.has_action(a):
		Input.action_press(a, strength)
		_pressed[a] = true


func _release(a: String) -> void:
	if InputMap.has_action(a):
		Input.action_release(a)
	_pressed.erase(a)


func _release_all() -> void:
	for a in _pressed.keys():
		_release(String(a))


## A 6 s pad pattern: run forward while the camera swings, single/double jumps, a ground pound,
## a punch combo, a crouch long jump, then repeat.
func _drive(delta: float) -> void:
	drive_t += delta
	var c := fmod(drive_t, 6.0)
	_press("move_forward", 1.0)
	var swing := "cam_right" if int(drive_t / 3.0) % 2 == 0 else "cam_left"
	_release("cam_left" if swing == "cam_right" else "cam_right")
	_press(swing, 0.55)
	var want := {}
	want["jump"] = (c < 0.25) or (c >= 1.5 and c < 1.8) or (c >= 4.2 and c < 4.45) or (c >= 5.2 and c < 5.4) or (c >= 5.55 and c < 5.8)
	want["attack"] = (c >= 0.9 and c < 0.95) or (c >= 2.8 and c < 2.85) or (c >= 3.1 and c < 3.15) or (c >= 3.4 and c < 3.45)
	want["crouch"] = (c >= 1.95 and c < 2.05) or (c >= 4.0 and c < 4.5)
	for a in want.keys():
		if want[a]:
			_press(String(a))
		elif _pressed.has(a):
			_release(String(a))


# ------------------------------------------------------------------ audio tracking

func _track_players() -> void:
	refresh_t -= get_process_delta_time()
	if refresh_t <= 0.0:
		refresh_t = 0.25
		for n in get_tree().root.find_children("*", "AudioStreamPlayer", true, false) + get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
			var id := n.get_instance_id()
			if not players.has(id):
				players[id] = {"node": n, "was": false, "pos": 0.0, "stream": null, "len": 0.0}
	var cam := get_viewport().get_camera_3d()
	var counts := {}
	var scn := _scene_name()
	for id in players.keys():
		var rec: Dictionary = players[id]
		var n: Variant = rec["node"]
		if not is_instance_valid(n):
			players.erase(id)
			continue
		var p := n as Node
		var playing := bool(p.get("playing"))
		var stream: AudioStream = p.get("stream")
		var pos := 0.0
		if playing:
			pos = float(p.call("get_playback_position"))
		var slen := stream.get_length() if stream != null else 0.0
		var loop := _is_loop(stream)
		var restarted: bool = playing and bool(rec["was"]) and stream == rec["stream"] and pos + 0.05 < float(rec["pos"]) and not (loop and float(rec["pos"]) > slen - 0.4)
		var started: bool = playing and (not bool(rec["was"]) or stream != rec["stream"] or restarted)
		if started:
			var prev: AudioStream = rec["stream"]
			var steal: bool = bool(rec["was"]) and prev != null and (stream != prev or restarted) and (_is_loop(prev) or float(rec["len"]) - float(rec["pos"]) > 0.15)
			var row := {"t": snappedf(t, 0.001), "scene": scn, "node": "%s/%s" % [p.get_parent().name if p.get_parent() else "", p.name],
				"file": _file(stream), "bus": String(p.get("bus")), "vol": snappedf(float(p.get("volume_db")), 0.1),
				"pitch": snappedf(float(p.get("pitch_scale")), 0.01), "len": snappedf(slen, 0.01), "loop": loop,
				"3d": p is AudioStreamPlayer3D, "paused_tree": get_tree().paused}
			if p is AudioStreamPlayer3D and cam != null:
				row["dist"] = snappedf((p as Node3D).global_position.distance_to(cam.global_position), 0.1)
			if steal:
				row["steal_of"] = _file(prev)
				row["steal_left"] = snappedf(float(rec["len"]) - float(rec["pos"]), 0.01)
			if restarted:
				row["restart"] = true
			starts.append(row)
		if playing:
			var b := String(p.get("bus"))
			counts[b] = int(counts.get(b, 0)) + 1
		rec["was"] = playing
		rec["pos"] = pos
		rec["stream"] = stream
		rec["len"] = slen
	for b in counts.keys():
		var k := scn + "|" + String(b)
		conc_max[k] = maxi(int(conc_max.get(k, 0)), int(counts[b]))
		var h: Dictionary = conc_hist.get(b, {})
		h[str(counts[b])] = int(h.get(str(counts[b]), 0)) + 1
		conc_hist[b] = h


func _is_loop(s: AudioStream) -> bool:
	if s == null:
		return false
	if "loop" in s:
		return bool(s.get("loop"))
	if s is AudioStreamWAV:
		return (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false


func _file(s: AudioStream) -> String:
	if s == null:
		return ""
	return s.resource_path.get_file() if s.resource_path != "" else s.get_class()


func _player_state(p: Variant) -> Dictionary:
	if not (p is Node) or not is_instance_valid(p):
		return {}
	var n := p as Node
	return {"on": bool(n.get("playing")), "file": _file(n.get("stream")), "vol": snappedf(float(n.get("volume_db")), 0.1)}


func _timeline_row() -> void:
	var a := get_node_or_null("/root/Audio")
	var r := get_node_or_null("/root/Router")
	var row := {"t": snappedf(t, 0.01), "scene": _scene_name(), "busy": bool(r.get("busy")) if r else false, "paused": get_tree().paused}
	if a != null:
		row["music_key"] = String(a.get("current_music"))
		row["amb_key"] = String(a.get("current_ambience"))
		row["mA"] = _player_state(a.get("_music_a"))
		row["mB"] = _player_state(a.get("_music_b"))
		row["amb"] = _player_state(a.get("_ambience"))
		row["jin"] = _player_state(a.get("_jingle"))
		row["voice"] = _player_state(a.get("_voice"))
	var peaks := {}
	var vols := {}
	for b in BUSES:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			peaks[b] = snappedf(maxf(-99.0, maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))), 0.1)
			vols[b] = snappedf(AudioServer.get_bus_volume_db(i), 0.1)
	row["peak"] = peaks
	row["busvol"] = vols
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
		row["pp"] = [snappedf(pl.global_position.x, 0.1), snappedf(pl.global_position.y, 0.1), snappedf(pl.global_position.z, 0.1)]
		if pl.has_method("get_state_name"):
			row["ps"] = String(pl.call("get_state_name"))
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("is_input_blocked"):
		row["blocked"] = bool(ui.call("is_input_blocked"))
	var js := _juice_sfx()
	if js != null:
		var loops: Dictionary = js.get("_loops")
		row["jloops"] = loops.keys() if loops != null else []
	timeline.append(row)


func _juice_sfx() -> Node:
	var j := get_node_or_null("/root/Juice")
	if j == null:
		return null
	return j.get_node_or_null("JuiceSfx")


func _save(name: String, data: Variant) -> void:
	var f := FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " " if name == "summary.json" else ""))
		f.close()


var _saved := false
var _ckpt_t := 15.0


func _checkpoint() -> void:
	var logs: Array = logger.call("take") if logger != null else []
	_save("starts.json", starts)
	_save("timeline.json", timeline)
	_save("log.json", logs)
	_save("marks.json", marks)
	_save("summary.json", {"t": t, "starts": starts.size(), "timeline_rows": timeline.size(), "log_rows": logs.size(),
		"conc_max": conc_max, "conc_hist": conc_hist, "blocked_time": blocked_time, "marks": marks.size(), "partial": true})


## Something else may quit the game first (BossBot quits when it is done): save what we have.
func _exit_tree() -> void:
	if not _saved:
		_write_all()


func _finish() -> void:
	_write_all()
	get_tree().quit(0)


func _write_all() -> void:
	_saved = true
	_release_all()
	_mark("finish")
	var logs: Array = logger.call("take") if logger != null else []
	_save("starts.json", starts)
	_save("timeline.json", timeline)
	_save("log.json", logs)
	_save("marks.json", marks)
	_save("summary.json", {"t": t, "starts": starts.size(), "timeline_rows": timeline.size(), "log_rows": logs.size(),
		"conc_max": conc_max, "conc_hist": conc_hist, "blocked_time": blocked_time, "marks": marks.size(), "logger": logger != null})
	print("[AudioQA] DONE starts=%d timeline=%d logs=%d -> %s" % [starts.size(), timeline.size(), logs.size(), out_dir])
