extends Node
## Enemies critique r1c (lens: encounter design and fairness). Plays REAL encounters inside the shipped worlds with
## the real player, the real gameplay camera and the real move actions (Input.action_press), two player models:
##   naive   - a first-time player: runs straight at the enemy and mashes attack (jump + attack if it flies).
##   skilled - reads the telegraph the game shows (lane, disc, ring), dodges it, then punishes in the open window.
##   vault   - wolf/bee only: stands in the lane and jumps over the charge with a real jump (design: "jump over").
## Logs every damage event with the hurting source, whether that source was inside the gameplay camera frustum and
## how long it had been on screen, every player hit on any enemy (landed or blocked), the target's state timeline,
## time-to-defeat and damage per segment. Read-only: nothing here edits track files.
## Args (after --): --world=res://scenes/worlds/w1/W1.tscn --plan=woolly_wolf:naive:0,woolly_wolf:skilled:1
##   --out=<abs json> [--shots=<abs dir>] [--seg-limit=30] [--approach=9] [--every=2.0] [--quit-when-done]
## Always pass --profile=crit-enemies-r1c.

var world: Node
var out: Dictionary = {"segments": []}
var _t := 0.0
var _seg: Dictionary = {}
var _target: EnemyBase
var _fam := ""
var _policy := ""
var _seg_t := 0.0
var _seg_limit := 30.0
var _health_prev := 6
var _active := false
var _atk_release := -1
var _jump_release := -1
var _atk_cd := 0.0
var _jump_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _dodge_until := -1.0
var _last_state := ""
var _next_shot := 0.0
var _shots := ""
var _every := 2.0
var _shot_n := 0
var _connected: Dictionary = {}
var _next_track := 0.0
var _cc_t := 0.0
var _want_name := ""


func _ready() -> void:
	var path := Dev.arg("world", "res://scenes/worlds/w1/W1.tscn")
	world = (load(path) as PackedScene).instantiate()
	add_child(world)
	out["world"] = path
	out["utc"] = Time.get_datetime_string_from_system(true) + "Z"
	_shots = Dev.arg("shots", "")
	_every = float(Dev.arg("every", "2.0"))
	_seg_limit = float(Dev.arg("seg-limit", "30"))
	_run.call_deferred()


func _player() -> Node3D:
	return EnemyKit.find_player(get_tree())


func _health() -> int:
	return int(EnemyKit.game_get(self, "health", 6))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _connect_all() -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as EnemyBase
		if e == null or _connected.has(e.get_instance_id()):
			continue
		_connected[e.get_instance_id()] = true
		var en := String(e.name)
		var fam := e.enemy_id
		e.hit_taken.connect(func(kind: String, landed: bool) -> void:
			if _active:
				(_seg["player_hits"] as Array).append({"t": snappedf(_seg_t, 0.01), "enemy": en, "family": fam,
					"kind": kind, "landed": landed, "enemy_state": e.state if is_instance_valid(e) else "freed"}))


func _run() -> void:
	await _frames(150)
	_connect_all()
	var plan := Dev.arg("plan", "woolly_wolf:naive:0").split(",")
	for item in plan:
		var parts := item.split(":")
		_want_name = parts[2] if parts.size() > 2 and not parts[2].is_valid_int() else ""
		await _segment(parts[0], parts[1] if parts.size() > 1 else "naive", int(parts[2]) if parts.size() > 2 and parts[2].is_valid_int() else 0)
	_finish()


func _pick(fam: String, idx: int) -> EnemyBase:
	var found: Array[EnemyBase] = []
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as EnemyBase
		if e != null and e.enemy_id == fam and not e.is_defeated:
			if _want_name != "" and String(e.name) == _want_name:
				return e
			found.append(e)
	if _want_name != "":
		return null
	found.sort_custom(func(a: EnemyBase, b: EnemyBase) -> bool: return String(a.name) < String(b.name))
	if found.is_empty():
		return null
	return found[clampi(idx, 0, found.size() - 1)]


## A start point about `approach` m from the enemy on walkable floor with a clear line of sight.
func _start_point(e: EnemyBase) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var dist := float(Dev.arg("approach", "9"))
	var base := e.global_position
	var ground_y := base.y
	if e.enemy_id in ["crow_bandit", "bumble_bruiser"]:
		var q0 := PhysicsRayQueryParameters3D.create(base, base + Vector3(0, -40, 0))
		q0.collision_mask = 1
		var h0 := space.intersect_ray(q0)
		if not h0.is_empty():
			ground_y = (h0.position as Vector3).y
	var f := -e.global_transform.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	for d in [dist, dist * 0.75, dist * 1.2]:
		for i in 12:
			var a := deg_to_rad(float(i / 2) * 30.0 * (1.0 if i % 2 == 0 else -1.0))
			var dir := f.rotated(Vector3.UP, a)
			var p := Vector3(base.x, ground_y, base.z) + dir * float(d)
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 4, 0), p + Vector3(0, -6, 0))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var fy := (hit.position as Vector3).y
			if absf(fy - ground_y) > 1.6:
				continue
			var eye := Vector3(p.x, fy + 1.2, p.z)
			var q2 := PhysicsRayQueryParameters3D.create(eye, base + Vector3(0, e.head_height * 0.5, 0))
			q2.collision_mask = 1
			if not space.intersect_ray(q2).is_empty():
				continue
			return Vector3(p.x, fy + 0.1, p.z)
	return base + f * dist + Vector3(0, 0.2, 0)


func _segment(fam: String, policy: String, idx: int) -> void:
	var e := _pick(fam, idx)
	_seg = {"family": fam, "policy": policy, "index": idx, "player_hits": [], "damage": [], "states": [], "result": "",
		"attack_presses": 0, "jump_presses": 0, "track": [], "attack_pass": {}}
	_next_track = 0.0
	_cc_t = 0.0
	if e == null:
		_seg["result"] = "no_target"
		(out["segments"] as Array).append(_seg)
		return
	_target = e
	_fam = fam
	_policy = policy
	_seg["target"] = String(e.name)
	_seg["target_pos"] = [snappedf(e.global_position.x, 0.1), snappedf(e.global_position.y, 0.1), snappedf(e.global_position.z, 0.1)]
	EnemyKit.game_call(self, "full_heal")
	var p := _player()
	var sp := _start_point(e)
	var look := e.global_position - sp
	look.y = 0
	p.call("respawn", Transform3D(Basis.looking_at(look.normalized() if look.length() > 0.1 else Vector3.FORWARD, Vector3.UP), sp))
	_seg["start"] = [snappedf(sp.x, 0.1), snappedf(sp.y, 0.1), snappedf(sp.z, 0.1)]
	# W2 freezes enemies within 12 m for 3 s after any 6 m teleport (respawn grace): settle past it.
	await _frames(int(float(Dev.arg("settle", "0.75")) * 60.0))
	EnemyKit.game_call(self, "full_heal")
	_health_prev = _health()
	_seg_t = 0.0
	_last_state = ""
	_dodge_until = -1.0
	_active = true
	print("[CritEnc] segment ", fam, " ", policy, " target ", e.name, " start ", sp)
	while _active:
		await get_tree().physics_frame
	_release_all()
	(out["segments"] as Array).append(_seg)
	_write()
	print("[CritEnc] result ", JSON.stringify({"family": fam, "policy": policy, "result": _seg["result"], "time": _seg.get("time", -1),
		"damage": (_seg["damage"] as Array).size(), "hits": (_seg["player_hits"] as Array).size()}))
	await _frames(90)


func _end(result: String) -> void:
	_seg["result"] = result
	_seg["time"] = snappedf(_seg_t, 0.01)
	_active = false


# ------------------------------------------------------------------ input

func _steer(dir: Vector3, mag: float = 1.0) -> void:
	var p := _player()
	var yaw := float(p.call("_camera_yaw")) if p.has_method("_camera_yaw") else 0.0
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
	var sx := dir.dot(right) * mag
	var sy := dir.dot(fwd) * mag
	_release_moves()
	if sx > 0.0:
		Input.action_press("move_right", sx)
	elif sx < 0.0:
		Input.action_press("move_left", -sx)
	if sy > 0.0:
		Input.action_press("move_forward", sy)
	elif sy < 0.0:
		Input.action_press("move_back", -sy)


func _release_moves() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _release_all() -> void:
	_release_moves()
	Input.action_release("attack")
	Input.action_release("jump")


func _attack() -> void:
	if _atk_cd > 0.0:
		return
	_atk_cd = 0.32
	Input.action_press("attack")
	_atk_release = 2
	_seg["attack_presses"] = int(_seg["attack_presses"]) + 1


func _jump(hold_frames: int = 14) -> void:
	if _jump_cd > 0.0:
		return
	_jump_cd = 0.7
	Input.action_press("jump")
	_jump_release = hold_frames
	_seg["jump_presses"] = int(_seg["jump_presses"]) + 1


# ------------------------------------------------------------------ per-frame

func _physics_process(delta: float) -> void:
	_t += delta
	if _atk_release >= 0:
		_atk_release -= 1
		if _atk_release < 0:
			Input.action_release("attack")
	if _jump_release >= 0:
		_jump_release -= 1
		if _jump_release < 0:
			Input.action_release("jump")
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_jump_cd = maxf(0.0, _jump_cd - delta)
	if not _active:
		return
	_seg_t += delta
	_connect_all()
	var p := _player()
	if _shots != "" and _seg_t >= _next_shot:
		_next_shot = _seg_t + _every
		_shot("t%04.1f" % _seg_t)
	if not is_instance_valid(_target) or _target.is_defeated:
		_end("defeated")
		_next_shot = 0.0
		return
	if _target.state != _last_state:
		_last_state = _target.state
		(_seg["states"] as Array).append([snappedf(_seg_t, 0.01), _last_state])
	var camv := get_viewport().get_camera_3d()
	var tc := _target.global_position + Vector3(0, _target.head_height * 0.5, 0)
	var vis: bool = camv.is_position_in_frustum(tc) if camv != null else false
	if _seg_t >= _next_track:
		_next_track = _seg_t + 0.5
		(_seg["track"] as Array).append([snappedf(_seg_t, 0.1), _target.state, snappedf(_flat(_target.global_position, p.global_position), 0.1),
			snappedf(_target.global_position.y - p.global_position.y, 0.1), vis, snappedf(_target.on_screen_for(), 0.1)])
	if _target.state == "attack":
		var ap: Dictionary = _seg["attack_pass"]
		var fd := _flat(_target.global_position, p.global_position)
		if not ap.has("n") or fd < float(ap.get("min_flat", 99.0)):
			ap["n"] = 1
			ap["min_flat"] = snappedf(fd, 0.01)
			ap["feet_rel_at_min"] = snappedf(p.global_position.y - _target.global_position.y, 0.01)
			ap["mak_state_at_min"] = String(p.call("get_state_name"))
			ap["t"] = snappedf(_seg_t, 0.01)
	var h := _health()
	if h < _health_prev:
		_log_damage(_health_prev - h)
		if h <= 2:
			EnemyKit.game_call(self, "full_heal")
			h = _health()
	_health_prev = h
	if _seg_t > _seg_limit:
		_end("timeout")
		_next_shot = 0.0
		return
	var st := String(p.call("get_state_name"))
	if st in ["hurt", "hurt_air", "dead", "fallout"]:
		_release_moves()
		return
	match _policy:
		"naive":
			_naive(p)
		"vault":
			_vault(p)
		_:
			_skilled(p)


func _log_damage(n: int) -> void:
	var p := _player()
	var cam := get_viewport().get_camera_3d()
	var srcs: Array = []
	for nd in get_tree().get_nodes_in_group("enemy"):
		var e := nd as EnemyBase
		if e == null or e.is_defeated:
			continue
		var d := e.global_position.distance_to(p.global_position)
		if d < 6.0:
			var c := e.global_position + Vector3(0, e.head_height * 0.5, 0)
			srcs.append({"enemy": String(e.name), "family": e.enemy_id, "state": e.state, "state_time": snappedf(e.state_time, 0.01),
				"dist": snappedf(d, 0.01), "in_frustum": cam.is_position_in_frustum(c) if cam != null else null,
				"on_screen_for": snappedf(e.on_screen_for(), 0.01)})
	for nd in get_tree().root.find_children("*", "Area3D", true, false):
		if nd is PeaProjectile and (nd as Node3D).global_position.distance_to(p.global_position) < 2.0:
			srcs.append({"projectile": "pea", "in_frustum": cam.is_position_in_frustum((nd as Node3D).global_position) if cam != null else null})
	var row := {"t": snappedf(_seg_t, 0.01), "amount": n, "mak_state": String(p.call("get_state_name")),
		"mak_pos": [snappedf(p.global_position.x, 0.1), snappedf(p.global_position.y, 0.1), snappedf(p.global_position.z, 0.1)],
		"sources": srcs, "target_state": _target.state if is_instance_valid(_target) else "freed"}
	(_seg["damage"] as Array).append(row)
	print("[CritEnc] damage ", JSON.stringify(row))
	_shot("dmg%02d" % (_seg["damage"] as Array).size())


func _shot(tag: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.resize(960, 540)
	_shot_n += 1
	img.save_jpg("%s/%s_%s_%s.jpg" % [_shots, _fam, _policy, tag], 0.85)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _to_target(p: Node3D) -> Vector3:
	var d := _target.global_position - p.global_position
	d.y = 0
	return d


## Naive: straight at it, mash attack within 1.7 m (jump first if it is above Mak's head).
func _naive(p: Node3D) -> void:
	var d := _to_target(p)
	var fl := d.length()
	var above := _target.global_position.y - p.global_position.y
	_steer(d, 1.0 if fl > 1.0 else 0.3)
	if fl < 1.7:
		if above > 0.9 and bool(p.get("grounded")):
			_jump()
		_attack()


## Vault: hold position in the lane facing the charger; jump when the charge is 2.2 m away.
func _vault(p: Node3D) -> void:
	var d := _to_target(p)
	var fl := d.length()
	var s := _target.state
	if s == "attack":
		_release_moves()
		if fl < float(Dev.arg("vault-at", "2.4")):
			_jump(20)
		return
	if s in ["skid", "dizzy", "recover", "hurt"]:
		_steer(d)
		if fl < 1.7:
			_attack()
		return
	_keep(p, d, fl, 5.0)


func _skilled(p: Node3D) -> void:
	var d := _to_target(p)
	var fl := d.length()
	var s := _target.state
	var tt := _target.state_time
	var above := _target.global_position.y - p.global_position.y
	if _seg_t < _dodge_until:
		_steer(_dodge_dir)
		return
	var punish := ["skid", "dizzy", "recover", "hurt", "tripped", "gloat"]
	match _fam:
		"woolly_wolf", "bumble_bruiser":
			if (s == "windup" and tt > 0.5) or s == "attack":
				var cd: Vector3 = _target.get("charge_dir")
				var side := cd.cross(Vector3.UP).normalized()
				var rel := p.global_position - _target.global_position
				_dodge_dir = side if rel.dot(side) >= 0.0 else -side
				_dodge_until = _seg_t + 0.45
				_steer(_dodge_dir)
				return
			if s in punish:
				_steer(d)
				if fl < 1.8:
					if above > 0.9 and bool(p.get("grounded")):
						_jump()
					_attack()
				return
			_keep(p, d, fl, 5.0)
		"crow_bandit":
			if (s == "windup" and tt > float(_target.windup_len) - 0.3) or s == "attack":
				var rel := p.global_position - _target.global_position
				rel.y = 0
				_dodge_dir = rel.normalized().cross(Vector3.UP)
				_dodge_until = _seg_t + 0.5
				_steer(_dodge_dir)
				return
			if s in punish or s == "return":
				_steer(d)
				if fl < 1.9:
					if above > 0.6 and bool(p.get("grounded")):
						_jump()
					_attack()
				return
			_keep(p, d, fl, 6.0)
		"peapod_popper":
			if s == "attack":
				var side2 := d.normalized().cross(Vector3.UP)
				_steer(d.normalized() * 0.4 + side2 * (1.0 if int(_seg_t * 1.4) % 2 == 0 else -1.0))
				return
			_steer(d)
			if fl < 1.7:
				_attack()
		"gingerbread_grenadier":
			if s == "sweep" and tt < 1.6:
				_steer(-d)
				return
			if s == "windup" or (s == "attack" and fl < 3.0):
				_steer(-d)
				return
			_steer(d)
			if fl < 2.1 and bool(p.get("grounded")):
				_jump(18)
		"gummy_brute":
			if s == "windup" or s == "attack":
				var jt: Variant = _target.get("_jump_to")
				var away := p.global_position - (jt as Vector3 if jt is Vector3 else _target.global_position)
				away.y = 0
				_steer(away if away.length() > 0.05 else -d)
				return
			if s in punish:
				_steer(d)
				if fl < 2.0:
					_attack()
				return
			_keep(p, d, fl, 5.0)
		_:
			_naive(p)


## Bait range: hover at about `want` m so the enemy commits to an attack.
func _keep(_p: Node3D, d: Vector3, fl: float, want: float) -> void:
	# A player keeps the threat in view: face it (tiny step toward it) and re-centre the camera now and then.
	_cc_t -= get_physics_process_delta_time()
	if _cc_t <= 0.0 and InputMap.has_action("cam_center"):
		_cc_t = 1.5
		Input.action_press("cam_center")
		get_tree().create_timer(0.05, true, true).timeout.connect(func() -> void: Input.action_release("cam_center"))
	if fl > want + 1.0:
		_steer(d, 0.7)
	elif fl < want - 1.5:
		_steer(-d, 0.7)
	else:
		_steer(d, 0.22)


func _write() -> void:
	var path := Dev.arg("out", "")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out, "  "))
			f.close()


func _finish() -> void:
	var path := Dev.arg("out", "")
	_write()
	print("[CritEnc] DONE -> ", path)
	if Dev.has_arg("quit-when-done"):
		get_tree().quit()
