extends Node
## CRITIC round 1, FUN lens, HUB: can a skilled, rhythm-aware player finish the Huffed Catalogue spiral (H-G)?
## Instances the real Hub scene and drives the real input actions (camera-relative stick, like a pad).
## Strategy of a good human: on a faller, jump again on the first grounded frame; before a wing book, wait on
## the current book until the wing will be open on arrival; otherwise run to the edge and take a full jump.
## Each attempt after a fall restarts from SP04 (teleport, as a checkpoint would) so the faller run is sampled.
## Run: python tools/godot.py run res://tests/critique_hub/CritHubSpiral.tscn --seconds 150 -- --profile=crit_hub_fun_sp --unlock-all --spawn=Test_Spiral

const MAX_ATTEMPTS := 6
var hub: Node
var spiral: Node
var _t := 0.0
var _cur := -1          # index of the book Mak stands on (-1 = gallery)
var _target := 0
var _jump_frames := 0
var _ground_frames := 0
var _attempt := 1
var _best := -1
var _log: Array = []
var _done := false
var _air_t := 0.0


func _ready() -> void:
	hub = load("res://scenes/hub/Hub.tscn").instantiate()
	add_child(hub)
	print("[CritSpiral] start")


func _p() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _books() -> Array:
	return HubSpiral.BOOKS


func _book_at(pos: Vector3) -> int:
	var books := _books()
	for i in books.size():
		var c: Vector3 = books[i][2]
		var sz: Vector3 = books[i][3]
		if Vector2(pos.x - c.x, pos.z - c.z).length() < maxf(sz.x, sz.z) * 0.75 and absf(pos.y - c.y) < 0.7:
			return i
	return -1


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if spiral == null:
		spiral = hub.find_child("HG_Catalogue_Spiral", true, false)
		return
	var p := _p()
	if p == null or _t < 1.0:
		return
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)
	var st := String(p.call("get_state_name"))
	var grounded := st in ["idle", "walk", "run", "skid", "land", "crouch", "turn"]
	_ground_frames = _ground_frames + 1 if grounded else 0
	_air_t = 0.0 if grounded else _air_t + delta
	var books := _books()
	# Fell: log, restart the attempt from SP04.
	if p.global_position.y < 4.0:
		_log.append("attempt %d fell after SP%02d at t=%.1f" % [_attempt, _cur + 1, _t])
		print("[CritSpiral] ", _log[-1])
		_attempt += 1
		if _attempt > MAX_ATTEMPTS:
			_finish()
			return
		var c4: Vector3 = books[3][2]
		p.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(150.0)), c4 + Vector3(0, 0.05, 0)))
		_cur = 3
		_target = 4
		return
	if grounded and _ground_frames == 2:
		var b := _book_at(p.global_position)
		if b >= 0 and b != _cur:
			_cur = b
			_target = b + 1
			_best = maxi(_best, b)
			print("[CritSpiral] attempt %d landed SP%02d t=%.2f state=%s" % [_attempt, b + 1, _t, st])
			if b == books.size() - 1:
				_log.append("attempt %d reached SP10 at t=%.1f" % [_attempt, _t])
				_finish()
				return
	if _target >= books.size():
		return
	var tgt: Vector3 = books[_target][2]
	var d := tgt - p.global_position
	d.y = 0.0
	var go := true
	var kind_next := String(books[_target][1])
	var kind_cur := String(books[_cur][1]) if _cur >= 0 else "gallery"
	if grounded and kind_next == "wing" and kind_cur != "falling":
		# Arrive while the cover is open: launch when (phase + 0.7 s flight) lands in [0.1, 1.1].
		var ph := fposmod(float(spiral.get("_t")) + float(books[_target][5]) + 0.7, HubSpiral.WING_PERIOD)
		go = ph > 0.1 and ph < 1.1
	if go:
		_steer(p, d.normalized())
	var from_c := Vector3.ZERO
	if _cur >= 0:
		from_c = books[_cur][2]
	var off := Vector2(p.global_position.x - from_c.x, p.global_position.z - from_c.z).length() if _cur >= 0 else 99.0
	var want_jump := false
	if grounded and go:
		if kind_cur == "falling" and _ground_frames >= 1:
			want_jump = true
		elif _cur >= 0 and off > 0.45:
			want_jump = true
		elif _cur < 0 and d.length() < 3.2:
			want_jump = true
	if want_jump and _jump_frames == 0:
		_jump_frames = 18
	if _jump_frames > 0:
		Input.action_press("jump")
		_jump_frames -= 1
		if _jump_frames == 0:
			Input.action_release("jump")
	if _t > 140.0:
		_log.append("timeout")
		_finish()


func _steer(p: Node3D, dir: Vector3) -> void:
	var yaw := float(p.call("_camera_yaw")) if p.has_method("_camera_yaw") else 0.0
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var sx := dir.dot(right)
	var sy := dir.dot(fwd)
	if sx > 0.0:
		Input.action_press("move_right", sx)
	else:
		Input.action_press("move_left", -sx)
	if sy > 0.0:
		Input.action_press("move_forward", sy)
	else:
		Input.action_press("move_back", -sy)


func _finish() -> void:
	_done = true
	Input.action_release("jump")
	print("[CritSpiral] RESULT best=SP%02d attempts=%d log=%s" % [_best + 1, mini(_attempt, MAX_ATTEMPTS), _log])
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()
