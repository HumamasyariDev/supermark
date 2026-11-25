extends Node
## Foot-slip probe (hero track): instances MoveLab, lets the real MakPlayer run a replay (--replay=<json>) and samples
## the skinned model's foot bones every rendered frame. A foot counts as planted while the player is grounded and the
## foot is within 1.5 cm of its lowest height in the current speed band. The planted foot's horizontal world speed is
## the foot slide (0 = perfect contact). Writes JSON to --slip-out=<path> and quits at the replay end.

const BANDS := [[0.3, 1.5], [1.5, 3.0], [3.0, 5.0], [5.0, 6.5], [6.5, 9.0]]

var _player: Node3D
var _skel: Skeleton3D
var _feet := {}
var _prev := {}
var _win_t := {}
var _minh := {}
var _samples := []   # [band_index, foot, slip_speed, body_speed]
var _frames := 0
var _cam: Camera3D   ## --side-cam: low side view that tracks Mak (Movie Maker A/B clips of the feet)


func _ready() -> void:
	process_priority = 1000   # sample after the player and the animator have posed this frame
	var lab := (load("res://scenes/tests/MoveLab.tscn") as PackedScene).instantiate()
	add_child(lab)
	var dev := get_tree().root.get_node_or_null("Dev")
	if dev != null and bool(dev.call("has_arg", "side-cam")):
		_cam = Camera3D.new()
		_cam.fov = 38.0
		add_child(_cam)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null


func _band(hs: float) -> int:
	for i in BANDS.size():
		if hs >= BANDS[i][0] and hs < BANDS[i][1]:
			return i
	return -1


func _process(delta: float) -> void:
	_frames += 1
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _skel == null:
		var m := _player.get_node_or_null("Visual/Model")
		if m == null:
			return
		_skel = _find_skel(m)
		if _skel == null:
			return
		for s in ["l", "r"]:
			_feet[s] = _skel.find_bone("foot_" + s)
		print("[FootSlip] skeleton ", _skel.get_path(), " feet ", _feet)
		return
	if _cam != null:
		var pp := _player.get_global_transform_interpolated().origin
		_cam.global_position = pp + Vector3(0.0, 0.45, 3.4)
		_cam.look_at(pp + Vector3(0.0, 0.35, 0.0))
		_cam.make_current()
	if delta <= 0.0:
		return
	var hv: Vector3 = _player.call("get_horizontal_velocity")
	var hs := hv.length()
	var b := _band(hs)
	var grounded := bool(_player.get("grounded"))
	var st := str(_player.call("get_state_name"))
	for s in _feet:
		var idx: int = _feet[s]
		if idx < 0:
			continue
		var p := (_skel.global_transform * _skel.get_bone_global_pose(idx)).origin
		var key := "%s_%d" % [s, b]
		if not _minh.has(key) or p.y < float(_minh[key]):
			_minh[key] = p.y
		var planted := grounded and b >= 0 and (st == "walk" or st == "run") and p.y <= float(_minh[key]) + 0.015
		# Windows of at least one physics tick (1/60 s), so render-rate jitter does not inflate the speed.
		if not planted:
			_prev.erase(s)
			continue
		if not _prev.has(s):
			_prev[s] = p
			_win_t[s] = 0.0
			continue
		_win_t[s] = float(_win_t[s]) + delta
		if float(_win_t[s]) >= 1.0 / 60.0:
			var d: Vector3 = p - (_prev[s] as Vector3)
			d.y = 0.0
			var along := d.dot(hv.normalized()) / float(_win_t[s]) if hs > 0.01 else 0.0
			var side_v := absf(d.dot(Vector3.UP.cross(hv.normalized()))) / float(_win_t[s]) if hs > 0.01 else 0.0
			_samples.append([b, s, d.length() / float(_win_t[s]), hs, along, side_v])
			_prev[s] = p
			_win_t[s] = 0.0
	if _frames % 30 == 0:
		_flush()


func _exit_tree() -> void:
	_flush()


func _flush() -> void:
	var out := {"bands": []}
	for i in BANDS.size():
		var sl := []
		var bs := 0.0
		var al := 0.0
		var sv := 0.0
		for smp in _samples:
			if int(smp[0]) == i:
				sl.append(float(smp[2]))
				bs += float(smp[3])
				al += float(smp[4])
				sv += float(smp[5])
		if sl.is_empty():
			continue
		sl.sort()
		var mean := 0.0
		for v in sl:
			mean += v
		mean /= sl.size()
		out["bands"].append({"speed_band": BANDS[i], "planted_samples": sl.size(), "body_speed_mean": bs / sl.size(),
			"slip_mean": mean, "slip_along_travel_mean": al / sl.size(), "slip_sideways_mean": sv / sl.size(), "slip_p50": sl[sl.size() / 2], "slip_p90": sl[int(sl.size() * 0.9)]})
	var path := ""
	var dev := get_tree().root.get_node_or_null("Dev")
	if dev != null:
		path = str(dev.call("arg", "slip-out", ""))
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out, " "))
