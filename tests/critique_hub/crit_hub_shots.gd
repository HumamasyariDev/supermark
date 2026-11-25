extends Node
## CRITIC round 1b, FUN lens, HUB: instance the real Hub scene and save gameplay-view screenshots at fixed times,
## so one run gives a strip of the flight / gate ceremony / gag beats without a Movie Maker AVI (C: is nearly full).
## Args (after --): --shots=1.5,3,4.5 --out=<abs dir> --tag=<label>; any hub args (--spawn, --hub-test...) pass through.
## Run: python tools/godot.py run res://tests/critique_hub/CritHubShots.tscn --seconds 40 -- --profile=X --shots=... --out=...

var _times: Array = []
var _out := ""
var _tag := "shot"
var _t := 0.0
var _i := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			for s in a.substr(8).split(","):
				_times.append(float(s))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
	add_child(load("res://scenes/hub/Hub.tscn").instantiate())
	print("[CritShots] start ", _times)


func _process(delta: float) -> void:
	_t += delta
	if _i < _times.size() and _t >= float(_times[_i]):
		var img := get_viewport().get_texture().get_image()
		img.resize(960, 540)
		var p := "%s/%s_t%05.1f.jpg" % [_out, _tag, _t]
		img.save_jpg(p, 0.85)
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		print("[CritShots] saved %s mak=%s" % [p, str(pl.global_position) if pl else "-"])
		_i += 1
		if _i >= _times.size():
			await get_tree().create_timer(0.5).timeout
			get_tree().quit()
