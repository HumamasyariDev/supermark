extends Node
## HERO critique round 1 (animation director lens). Read-only probe: instances MoveLab, lets the real MakPlayer
## play a replay (--replay=<json>) and films it with a close critique camera that follows the body:
##   --view=side|3q|front|back   camera relative to the segment's heading (re-based on every teleport)
##   --dist=<m> (default 3.7)  --fov=<deg> (default 40)  --yfollow=<k> (vertical follow rate, default 10; 0 = fixed height)
##   --bones-out=<abs jsonl>     per-frame world positions of feet, hips, head, ears, tail, backpack, head_top + state
## Nothing in the track's files is modified.

const BONES := ["foot_l", "foot_r", "shin_l", "shin_r", "hips", "head", "ear_l", "ear_r", "tail", "backpack", "head_top",
	"hand_l", "hand_r", "forearm_l", "forearm_r"]

var _player: Node3D
var _skel: Skeleton3D
var _idx := {}
var _cam: Camera3D
var _view := "side"
var _dist := 3.7
var _yk := 10.0
var _base_yaw := 0.0
var _cam_y := 0.0
var _prev_p := Vector3.INF
var _f := 0
var _out: FileAccess


func _ready() -> void:
	process_priority = 1000
	var lab := (load("res://scenes/tests/MoveLab.tscn") as PackedScene).instantiate()
	add_child(lab)
	var dev := get_tree().root.get_node_or_null("Dev")
	if dev != null:
		_view = str(dev.call("arg", "view", "side"))
		_dist = float(dev.call("arg", "dist", "3.7"))
		_yk = float(dev.call("arg", "yfollow", "10"))
		var bo := str(dev.call("arg", "bones-out", ""))
		if bo != "":
			_out = FileAccess.open(bo, FileAccess.WRITE)
	_cam = Camera3D.new()
	_cam.fov = float(dev.call("arg", "fov", "40")) if dev != null else 40.0
	add_child(_cam)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null


func _process(delta: float) -> void:
	_f += 1
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var pp := _player.get_global_transform_interpolated().origin
	var yaw := float(_player.get("facing_yaw"))
	if _prev_p == Vector3.INF or pp.distance_to(_prev_p) > 2.5:
		_base_yaw = yaw
		_cam_y = pp.y
	_prev_p = pp
	if _yk <= 0.0:
		pass
	else:
		_cam_y = lerpf(_cam_y, pp.y, 1.0 - exp(-_yk * maxf(delta, 1.0 / 60.0)))
	var fwd := Vector3(-sin(_base_yaw), 0.0, -cos(_base_yaw))
	var right := fwd.cross(Vector3.UP)
	var off := Vector3.ZERO
	match _view:
		"side":
			off = right * _dist
		"3q":
			off = (right * 0.72 + fwd * 0.72).normalized() * _dist
		"front":
			off = fwd * _dist
		"back":
			off = -fwd * _dist
		_:
			off = right * _dist
	var tgt := Vector3(pp.x, _cam_y + 0.55, pp.z)
	_cam.global_position = tgt + off + Vector3(0, 0.12, 0)
	_cam.look_at(tgt, Vector3.UP)
	_cam.make_current()
	if _skel == null:
		var m := _player.get_node_or_null("Visual/Model")
		if m != null:
			_skel = _find_skel(m)
			if _skel != null:
				for b in BONES:
					_idx[b] = _skel.find_bone(b)
				var names := []
				for i in _skel.get_bone_count():
					names.append(_skel.get_bone_name(i))
				print("[HeroCrit] bones ", names)
		return
	if _out != null:
		var row := {"f": _f, "t": snappedf(float(_f) / 60.0, 0.001), "s": str(_player.call("get_state_name")),
			"g": bool(_player.get("grounded")), "p": _v(pp), "pr": _v(_player.global_position), "yaw": snappedf(yaw, 0.001)}
		var hv: Vector3 = _player.call("get_horizontal_velocity")
		row["hs"] = snappedf(hv.length(), 0.01)
		for b in _idx:
			var i: int = _idx[b]
			if i >= 0:
				row[b] = _v((_skel.global_transform * _skel.get_bone_global_pose(i)).origin)
		_out.store_line(JSON.stringify(row))


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _exit_tree() -> void:
	if _out != null:
		_out.close()
