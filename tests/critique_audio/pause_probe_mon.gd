extends Node
## Critic audio QA (resumed production, round 1): pause-menu audio probe through the REAL flow.
## Router -> hub, wait, open the real pause menu (UI.pause_menu.open()), sample every Audio pool player each frame for
## 1.5 s (stream, bus, playing, stream_paused, playback position), resume through pause_menu.resume(), sample 1.5 s more.
## Question: is the pause sound itself (ui_pause -> book_open/ui_pause key, played in the same frame the tree pauses)
## frozen by JuiceSfx._pause_treatment and replayed on resume? Also: music/ambience bus effects while paused.
## Read-only. Run: python tools/godot.py run res://tests/critique_audio/PauseProbe.tscn --seconds 90 -- --profile=critique_audio_r1qa

var rows: Array = []


func _snap(tag: String) -> void:
	var a := get_node("/root/Audio")
	var pl: Array = []
	for pool in [a.get("_pool2d"), a.get("_pool3d")]:
		for p in pool:
			if p.stream != null and (p.playing or p.stream_paused):
				pl.append([p.stream.resource_path.get_file(), String(p.bus), p.playing, p.stream_paused, snappedf(p.get_playback_position(), 0.01)])
	var fx := {}
	for bus in ["Music", "Ambience"]:
		var bi := AudioServer.get_bus_index(bus)
		var on: Array = []
		for i in AudioServer.get_bus_effect_count(bi):
			if AudioServer.is_bus_effect_enabled(bi, i):
				on.append(AudioServer.get_bus_effect(bi, i).get_class())
		fx[bus] = on
	rows.append({"tag": tag, "f": Engine.get_process_frames(), "paused": get_tree().paused, "pool": pl, "fx": fx})


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node("/root/Router").call("go_to_hub", "")
	await get_tree().create_timer(9.0, true).timeout
	var ui := get_node("/root/UI")
	var pm: Node = ui.get("pause_menu")
	print("[PauseProbe] pause_menu=", pm, " current=", get_tree().current_scene)
	_snap("before_open")
	pm.call("open")
	for i in 90:
		_snap("open_%d" % i)
		await get_tree().process_frame
	pm.call("resume")
	for i in 90:
		_snap("resume_%d" % i)
		await get_tree().process_frame
	var out := ProjectSettings.globalize_path("res://").path_join("../Docs/progress/critique/audio/r1_qa/resume_pause_probe.json")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, " "))
	f.close()
	# compact summary
	for r in rows:
		if r["tag"] in ["before_open", "open_0", "open_1", "open_2", "open_5", "open_60", "resume_0", "resume_9", "resume_10", "resume_11", "resume_12", "resume_20", "resume_40"]:
			print("[PauseProbe] ", r["tag"], " paused=", r["paused"], " fx=", r["fx"], " pool=", r["pool"])
	get_tree().quit()
