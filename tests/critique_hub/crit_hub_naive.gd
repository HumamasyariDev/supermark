extends Node
## CRITIC round 2, FUN lens, HUB: the "first-time player" bot for the critical-path sheep chase (R3.2 pass test 6).
## Loads the real Hub.tscn on a fresh profile (intro plays), waits for the intro to end, then plays like a newcomer:
## run straight at the sheep/cub with the real move actions and mash attack within 1.6 m. No corner cutting, no dive,
## no waiting out charges. Logs the chase state, Game.health and Mak's position every second, saves a JPG every
## --every seconds, and records the time the gag ends (hub_cub_done) or gives up at --limit seconds.
## Args (after --): --profile=<fresh> --out=<abs dir> [--tag=naive] [--every=4] [--limit=170] [--start=11] [--stick=1.0]
## Run: python tools/godot.py run res://tests/critique_hub/CritHubNaive.tscn --seconds 200 -- --profile=crit_hub_r2_naive --out=<abs>

var _out := ""
var _tag := "naive"
var _every := 4.0
var _limit := 170.0
var _start := 11.0
var _stick := 1.0
var _t := 0.0
var _next_shot := 0.0
var _next_log := 0.0
var _atk_cd := 0.0
var _atk_release := 0
var _done_t := -1.0
var _woke_t := -1.0
var _phase2_t := -1.0
var _quit_at := -1.0
var _lines: PackedStringArray = []
var _min_health := 99


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--every="):
			_every = float(a.substr(8))
		elif a.begins_with("--limit="):
			_limit = float(a.substr(8))
		elif a.begins_with("--start="):
			_start = float(a.substr(8))
		elif a.begins_with("--stick="):
			_stick = float(a.substr(8))
	add_child(load("res://scenes/hub/Hub.tscn").instantiate())
	_log("[Naive] start limit=%.0f start=%.1f stick=%.2f" % [_limit, _start, _stick])


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _acts() -> Node:
	return find_child("Activities", true, false)


func _flag(f: String) -> bool:
	var g := get_node_or_null("/root/Game")
	return g != null and g.has_method("is_unlocked") and bool(g.call("is_unlocked", f))


func _steer(p: Node3D, dir: Vector3) -> void:
	var yaw := 0.0
	if p.has_method("_camera_yaw"):
		yaw = float(p.call("_camera_yaw"))
	if bool(p.get("_steer_locked")) and p.get("_steer_yaw") != null:
		yaw = float(p.get("_steer_yaw"))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var sx := dir.dot(right) * _stick
	var sy := dir.dot(fwd) * _stick
	_release()
	if sx > 0.0:
		Input.action_press("move_right", sx)
	else:
		Input.action_press("move_left", -sx)
	if sy > 0.0:
		Input.action_press("move_forward", sy)
	else:
		Input.action_press("move_back", -sy)


func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _shot() -> void:
	if _out == "":
		return
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_jpg("%s/%s_t%05.1f.jpg" % [_out, _tag, _t], 0.85)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= _next_shot:
		_next_shot += _every
		_shot()
	var p := _player()
	var g := get_node_or_null("/root/Game")
	if g:
		_min_health = mini(_min_health, int(g.get("health")))
	if _quit_at > 0.0:
		if _t >= _quit_at:
			_finish()
		return
	if p == null or _t < _start:
		return
	var acts := _acts()
	var cst := String(acts.get("_cub_state")) if acts else ""
	var cub := find_child("WoollyWolfCub", true, false) as Node3D
	if _woke_t < 0.0 and cst != "" and cst != "rug":
		_woke_t = _t
		_log("[Naive] woke state=%s at t=%.2f" % [cst, _t])
	if _phase2_t < 0.0 and cst in ["aim", "windup", "charge", "skid", "dizzy"]:
		_phase2_t = _t
		_log("[Naive] phase2 at t=%.2f" % _t)
	if _t >= _next_log:
		_next_log += 1.0
		_log("[Naive] t=%.1f cub_state=%s cub=%s mak=%s mak_state=%s health=%s" % [_t, cst, str(cub.global_position) if cub else "-", str(p.global_position), String(p.call("get_state_name")) if p.has_method("get_state_name") else "?", str(g.get("health")) if g else "?"])
	if _flag("hub_cub_done"):
		_done_t = _t
		_log("[Naive] RESULT caught at t=%.2f (woke %.2f, phase2 %.2f, chase %.2f s) min_health=%d" % [_t, _woke_t, _phase2_t, _t - maxf(_woke_t, _start), _min_health])
		_release()
		Input.action_release("attack")
		_quit_at = _t + 4.0
		return
	if _t > _limit:
		_log("[Naive] RESULT not caught after %.1f s (woke %.2f, phase2 %.2f) state=%s min_health=%d" % [_t, _woke_t, _phase2_t, cst, _min_health])
		_release()
		_quit_at = _t + 1.0
		return
	# Before the wake: walk toward Book 1 (the paw prints lead there). After: straight at the sheep.
	var target := Vector3(-7.07, 0, 7.07)
	if cub and _woke_t > 0.0:
		target = cub.global_position
	var d := target - p.global_position
	d.y = 0.0
	if d.length() > 0.5:
		_steer(p, d.normalized())
	else:
		_release()
	_atk_cd -= delta
	if cub and _woke_t > 0.0 and d.length() < 1.6 and _atk_cd <= 0.0:
		_atk_cd = 0.45
		Input.action_press("attack")
		_atk_release = 2
	if _atk_release > 0:
		_atk_release -= 1
		if _atk_release == 0:
			Input.action_release("attack")


func _finish() -> void:
	if _out != "":
		var f := FileAccess.open("%s/%s.log" % [_out, _tag], FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines))
	get_tree().quit()
