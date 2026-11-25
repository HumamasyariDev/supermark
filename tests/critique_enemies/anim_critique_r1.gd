extends Node3D
## Enemies critique, round 1 (animation and personality lens). Read-only driver: instances EnemyLab.tscn
## with --only=<family>, keeps the family's AI ON, and drives the lab stub player through a fixed script
## so the clip shows real locomotion: idle/patrol, notice, chase or attack, turning while the player
## circles, losing the player, coming back, then a stomp (or second hit) and the stomp defeat gag.
## Args: --crit-family=<id> (required), --crit-view=three|side|ground|front, --profile=critique_enemies
## Use with: python tools/godot.py movie res://tests/critique_enemies/AnimCritiqueR1.tscn <out.avi> --frames 540 --fps 30
##   -- --only=<id> --crit-family=<id> --crit-view=three --profile=critique_enemies

var lab: Node3D
var fam: String = ""
var enemy: EnemyBase
var cam: Camera3D
var view: String = "three"
var t: float = 0.0
var _cam_pos: Vector3
var _log: Array[String] = []
var _last_state: String = ""
var _phase: String = "setup"
var mode: String = "ai"


func _ready() -> void:
	fam = Dev.arg("crit-family", "woolly_wolf")
	view = Dev.arg("crit-view", "three")
	lab = (load("res://scenes/enemies/EnemyLab.tscn") as PackedScene).instantiate() as Node3D
	add_child(lab)
	cam = Camera3D.new()
	cam.name = "CritCam"
	cam.fov = 42.0
	add_child(cam)
	if Dev.has_arg("reel"):
		# Lab --reel=<family> scripts the states (AI off); this camera frames it close and centred.
		mode = "reel"
		await get_tree().process_frame
		enemy = lab.get("enemies").get(fam + "_0") as EnemyBase
		cam.make_current()
		_cam_pos = _cam_want()
		cam.global_position = _cam_pos
		return
	enemy = lab.get("enemies").get(fam) as EnemyBase
	if enemy == null:
		push_error("[Crit] no enemy for " + fam)
		return
	# Drop the other grenadiers? No: the squad is part of the grenadier's personality, keep it.
	var p := lab.get("player") as Node3D
	p.set("keyboard", false)
	var start := enemy.global_position
	p.global_position = start + Vector3(0, 0.1 - start.y + 0.05, 13.0)
	p.set("drive_target", p.global_position)
	cam.make_current()
	_cam_pos = _cam_want()
	cam.global_position = _cam_pos
	_run_script(p, start)


func _cam_want() -> Vector3:
	var c := enemy.global_position if is_instance_valid(enemy) else _cam_pos
	var d := 4.6
	var h := 0.9
	if mode == "reel":
		d = 3.0
		h = 0.75
	if fam == "gummy_brute":
		d = 6.8 if mode == "ai" else 5.0
		h = 1.4
	elif fam == "gingerbread_grenadier":
		d = 6.0 if mode == "ai" else 3.8
		h = 1.1
	match view:
		"side":
			return Vector3(c.x + d, c.y + h * 0.7, c.z)
		"ground":
			return Vector3(c.x + d * 0.85, c.y + 0.22, c.z + d * 0.35)
		"front":
			return Vector3(c.x, c.y + h, c.z + d)
	return Vector3(c.x + d * 0.62, c.y + h, c.z + d * 0.78)


func _process(delta: float) -> void:
	t += delta
	if cam == null or not is_instance_valid(enemy):
		return
	_cam_pos = _cam_pos.lerp(_cam_want(), 1.0 - exp(-6.0 * delta))
	cam.global_position = _cam_pos
	var look := enemy.global_position + Vector3(0, 0.45 if fam != "gummy_brute" else 0.8, 0)
	if view == "ground":
		look.y = enemy.global_position.y + 0.35
	cam.look_at(look, Vector3.UP)
	if String(enemy.state) != _last_state:
		_last_state = String(enemy.state)
		var line := "%.2f %s state=%s y=%.2f floor=%s" % [t, _phase, _last_state, enemy.global_position.y, str(enemy.is_on_floor())]
		_log.append(line)
		print("[Crit] ", line)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run_script(p: Node3D, start: Vector3) -> void:
	# A: unaware (idle / patrol / perch) for 3 s with the player 13 m away.
	_phase = "unaware"
	await _wait(3.0)
	# B: approach to about 4.5 m: notice, wind-up, attack.
	_phase = "approach"
	p.set("drive_speed", 5.0)
	p.set("drive_target", start + Vector3(0, 0.1 - start.y + 0.05, 4.5))
	await _wait(3.2)
	# C: circle the enemy at 4 m so it has to keep turning (two thirds of a lap each way).
	_phase = "circle"
	var steps := 18
	for i in steps:
		var a := TAU * 0.66 * float(i + 1) / float(steps)
		p.set("drive_target", start + Vector3(sin(a) * 4.0, 0.1 - start.y + 0.05, cos(a) * 4.0))
		await _wait(0.2)
	for i in steps:
		var a := TAU * 0.66 * (1.0 - float(i + 1) / float(steps))
		p.set("drive_target", start + Vector3(sin(a) * 4.0, 0.1 - start.y + 0.05, cos(a) * 4.0))
		await _wait(0.2)
	# D: run far away: lose interest, return home.
	_phase = "flee"
	p.set("drive_speed", 7.5)
	var away := -signf(start.x) if absf(start.x) > 1.0 else 1.0
	p.set("drive_target", start + Vector3(away * 14.0, 0.1 - start.y + 0.05, 5.0))
	await _wait(3.0)
	# E: stomp defeat (the most common defeat in play). Two-hit families take a punch first.
	_phase = "defeat"
	if not is_instance_valid(enemy):
		return
	p.set("drive_target", p.global_position)
	var above := enemy.global_position + Vector3(0, enemy.head_height + 0.6, 0)
	if enemy.max_hp > 1:
		if fam == "gummy_brute":
			enemy.set_state("recover")
		enemy.hit_by_player("punch", enemy.global_position + enemy.global_transform.basis.z * 1.5 + Vector3(0, 0.5, 0))
		await _wait(1.3)
		if not is_instance_valid(enemy):
			return
		above = enemy.global_position + Vector3(0, enemy.head_height + 0.6, 0)
	if fam == "gummy_brute":
		enemy.set_state("recover")
	# Real stomp path (hit_by_player), so the lethal-stomp squash is judged as the player will see it.
	var ok := enemy.hit_by_player("stomp", above)
	print("[Crit] stomp landed=", ok, " defeated=", enemy.is_defeated)
	if not enemy.is_defeated:
		await _wait(0.6)
		if is_instance_valid(enemy) and not enemy.is_defeated:
			enemy.defeat("stomp", above)
	await _wait(3.0)
	print("[Crit] done ", fam)
	for l in _log:
		print("[CritLog] ", l)
