extends "res://tests/critique_w2/r1_feel/feel_w2_probe_r1c.gd"
## W2 critique r1 (feel lens) relaunch r1c, segment mode: many station replays in ONE Godot run (the machine has two
## shared run slots). --segments=<abs json>: [{"label", "start", "reactive": [...], "ride_bell": bool, "descent": bool}].
## At start + 5 physics frames the probe installs that segment's reactive events into the player's MakInput, clears
## its tag counters (so "nth" counts per segment) and restores full health. Read-only test file.

var _segs: Array = []
var _seg_i := -1


func _ready() -> void:
	super._ready()
	var dev := get_tree().root.get_node_or_null("Dev")
	if dev != null:
		var p := str(dev.call("arg", "segments", ""))
		if p != "":
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				_segs = JSON.parse_string(f.get_as_text())


func _process(delta: float) -> void:
	if _player != null and not _segs.is_empty():
		var pf := int(_player.get("physics_frame"))
		while _seg_i + 1 < _segs.size() and pf >= int(_segs[_seg_i + 1]["start"]) + 5:
			_seg_i += 1
			_begin(_segs[_seg_i] as Dictionary, pf)
	var was_rode := _rode
	super._process(delta)
	if _rode and not was_rode and _player != null:
		var inp: Object = _player.get("inp")
		if inp != null:
			inp.call("notify", "ridebell")


func _begin(s: Dictionary, pf: int) -> void:
	var inp: Object = _player.get("inp")
	if inp != null:
		var r: Array = []
		for e in s.get("reactive", []):
			var d: Dictionary = (e as Dictionary).duplicate()
			for k in ["f", "nth", "delay", "frames"]:
				if d.has(k):
					d[k] = int(d[k])
			r.append(d)
		inp.set("_reactive", r)
		inp.set("_tag_counts", {})
	var game := get_tree().root.get_node_or_null("Game")
	if game != null and game.has_method("full_heal"):
		game.call("full_heal")
	if bool(s.get("ride_bell", false)):
		_ride_pf = pf + 15
		_rode = false
	if bool(s.get("descent", false)):
		var d := get_tree().root.find_child("W2Descent", true, false)
		if d != null and d.has_method("start"):
			d.call("start")
	print("[FeelW2seg] pf %d segment %s (%d reactive)" % [pf, str(s.get("label", "")), (s.get("reactive", []) as Array).size()])
