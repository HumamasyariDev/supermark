extends Node
## Scripted EnemyLab test. Drives the lab player (EnemyLabPlayer) through the counter of every
## family (sidestep + punch, stomps, blocked frontal punches, trampoline bounces) and reports
## pass/fail per check. Started by enemy_lab.gd when --labtest or --showcase is passed.
## Output: printed "[LabTest]" lines plus JSON at --labtest-out=<abs path> (default user://labtest.json).
## --shots=<abs dir> saves viewport captures at key moments. --quit-when-done ends the run.

var lab: Node3D
var player: EnemyLabPlayer
var results: Array = []
var _cur: Dictionary = {}
var _hits: Array = []
var _focus: Node3D
var _t0: int = 0


func start(l: Node3D) -> void:
	lab = l
	player = lab.get("player") as EnemyLabPlayer
	if player == null:
		push_error("[LabTest] needs the EnemyLabPlayer stub (do not pass --real-player)")
		return
	player.keyboard = false
	player.hit_result.connect(func(kind: String, target: Node, ok: bool) -> void:
		_hits.append({"kind": kind, "target": String(target.name) if target != null else "", "landed": ok}))
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> void:
	if lab == null:
		return
	var tgt: Vector3 = player.global_position if player != null else Vector3.ZERO
	if _focus != null and is_instance_valid(_focus):
		tgt = tgt.lerp(_focus.global_position, 0.5)
	lab.set("cam_target", tgt)


# ------------------------------------------------------------------ helpers

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func secs(s: float) -> void:
	await frames(int(s * 60.0))


func drive(pos: Vector3, timeout: float = 6.0, speed: float = 7.0) -> bool:
	player.drive_target = pos
	player.drive_speed = speed
	var t := 0.0
	while t < timeout:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var d := pos - player.global_position
		d.y = 0
		if d.length() < 0.35:
			break
	player.drive_target = Vector3.INF
	return t < timeout


func chase_and_punch(e: Variant, timeout: float = 4.0, reach: float = 1.25) -> bool:
	var t := 0.0
	while t < timeout and is_instance_valid(e):
		var en := e as Node3D
		var d := en.global_position - player.global_position
		d.y = 0
		player.drive_target = en.global_position
		player.drive_speed = 7.5
		if d.length() < reach:
			player.drive_target = Vector3.INF
			player.rotation.y = atan2(-d.x, -d.z)
			player.punch()
			await frames(16)
			return true
		await get_tree().physics_frame
		t += 1.0 / 60.0
	player.drive_target = Vector3.INF
	return false


func drop_on(e: Variant, height: float = 2.4) -> void:
	if not is_instance_valid(e):
		return
	var top: float = float(e.get("head_height"))
	player.drive_target = Vector3.INF
	player.teleport((e as Node3D).global_position + Vector3(0, top + height, 0), player.rotation.y)
	await frames(40)


func wait_state(e: Variant, states: Array, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if not is_instance_valid(e):
			return false
		if String(e.get("state")) in states:
			return true
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return false


func wait_gone(e: Variant, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if not is_instance_valid(e):
			return true
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return not is_instance_valid(e)


func check(name: String, ok: bool, detail: String = "") -> void:
	_cur["checks"].append({"name": name, "pass": ok, "detail": detail})
	print("[LabTest] %s | %s | %s %s" % [_cur["family"], name, "PASS" if ok else "FAIL", detail])


func shot(moment: String) -> void:
	if not Dev.has_arg("shots"):
		return
	await RenderingServer.frame_post_draw
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var path := Dev.arg("shots").path_join("%sZ__%s_%s.png" % [stamp, _cur.get("family", "lab"), moment])
	Dev.save_screenshot(path)


func begin(family: String) -> Node3D:
	_cur = {"family": family, "checks": [], "damage_before": player.damage_taken, "t": Time.get_ticks_msec()}
	_hits.clear()
	var enemies: Dictionary = lab.get("enemies")
	var e: Node3D = null
	if is_instance_valid(enemies.get(family)):
		e = enemies.get(family) as Node3D
	for k in enemies.keys():
		var raw: Variant = enemies[k]
		if is_instance_valid(raw) and raw is EnemyBase:
			(raw as EnemyBase).ai_enabled = String(k).begins_with(family)
	_focus = e
	var pens: Dictionary = lab.get("pens")
	var pen := pens.get(family) as Node3D
	if pen != null:
		player.teleport(pen.global_position + Vector3(0, 0.1, 6.5), 0.0)
		lab.set("cam_offset", Vector3(2.4, 2.6, 5.6))
	return e


func finish() -> void:
	_cur["damage_taken"] = player.damage_taken - int(_cur["damage_before"])
	_cur["seconds"] = (Time.get_ticks_msec() - int(_cur["t"])) / 1000.0
	_cur["hits"] = _hits.duplicate()
	results.append(_cur)
	player.drive_target = Vector3.INF


func wants(family: String) -> bool:
	if not Dev.has_arg("only"):
		return true
	return family in Dev.arg("only").split(",")


# ------------------------------------------------------------------ the run

func _run() -> void:
	await frames(30)
	if wants("woolly_wolf"):
		await _test_wolf()
	if wants("crow_bandit"):
		await _test_crow()
	if wants("peapod_popper"):
		await _test_peapod()
	if wants("bumble_bruiser"):
		await _test_bee()
	if wants("gingerbread_grenadier"):
		await _test_grenadier()
	if wants("gummy_brute"):
		await _test_gummy()
	_report()


func _test_wolf() -> void:
	var e := begin("woolly_wolf")
	if e == null:
		return
	await drive(e.global_position + Vector3(0, 0, 5.0), 3.0, 3.0)
	check("notices and rips costume", await wait_state(e, ["notice", "windup"], 4.0) and await wait_state(e, ["windup"], 3.0))
	await shot("windup")
	await wait_state(e, ["attack"], 2.0)
	# Sidestep the committed charge.
	var side := player.global_position + Vector3(3.0, 0, 0)
	player.drive_target = side
	player.drive_speed = 8.0
	check("charges", await wait_state(e, ["attack"], 1.0))
	await secs(0.35)
	await shot("charge")
	check("skids after the charge", await wait_state(e, ["skid", "dizzy"], 3.0))
	await shot("skid")
	await chase_and_punch(e, 1.8)
	check("punch during skid defeats it", await wait_gone(e, 3.0), str(_hits))
	await secs(0.5)
	await shot("defeat_gag")
	finish()


func _test_crow() -> void:
	var e := begin("crow_bandit")
	if e == null:
		return
	await drive(e.global_position + Vector3(0, 0, 4.0) - Vector3(0, e.global_position.y, 0), 3.0, 3.0)
	check("notices from the perch", await wait_state(e, ["notice", "windup"], 4.0))
	await wait_state(e, ["windup"], 2.0)
	await secs(0.3)
	await shot("windup_marker")
	await secs(0.3)
	# Sidestep just before the dive locks on.
	player.drive_target = player.global_position + Vector3(-3.5, 0, 0)
	player.drive_speed = 8.0
	await wait_state(e, ["attack"], 2.0)
	await secs(0.25)
	await shot("dive")
	check("recovers low after the dive", await wait_state(e, ["recover"], 3.0))
	await shot("recover_low")
	await chase_and_punch(e, 1.6, 1.3)
	if is_instance_valid(e) and not bool(e.get("is_defeated")):
		player.jump()
		await frames(10)
		player.punch()
	check("punch in the low recovery defeats it", await wait_gone(e, 2.0), str(_hits))
	await shot("feathers")
	finish()


func _test_peapod() -> void:
	var e := begin("peapod_popper")
	if e == null:
		return
	await drive(e.global_position + Vector3(0, 0, 7.0), 2.0, 3.0)
	check("lobs a volley", await wait_state(e, ["attack"], 4.0))
	await secs(0.5)
	await shot("volley_arcs")
	check("reloads after the volley", await wait_state(e, ["recover"], 4.0))
	await drive(e.global_position + Vector3(0, 0, 1.6), 2.0, 8.0)
	await drop_on(e, 1.6)
	check("stomp between volleys defeats it", await wait_gone(e, 2.0))
	await shot("peas_scatter")
	finish()


func _test_bee() -> void:
	var e := begin("bumble_bruiser")
	if e == null:
		return
	# Stand in front of the wall so a dodged charge ends in a wall hit.
	var wall_spot := Vector3(e.global_position.x, 0.1, -3.6)
	(e as EnemyBase).ai_enabled = false
	await drive(wall_spot, 4.0, 6.0)
	(e as EnemyBase).ai_enabled = true
	check("lines up a charge", await wait_state(e, ["windup"], 5.0))
	await secs(0.3)
	await shot("windup_line")
	await secs(0.3)
	player.drive_target = player.global_position + Vector3(3.2, 0, 1.0)
	player.drive_speed = 8.0
	check("charges", await wait_state(e, ["attack"], 2.0))
	var dizzy := await wait_state(e, ["dizzy"], 2.5)
	check("dizzy after the wall hit", dizzy, String(e.get("state")) if is_instance_valid(e) else "gone")
	await secs(0.6)
	await shot("dizzy")
	if dizzy:
		await drop_on(e, 1.4)
	else:
		await wait_state(e, ["recover", "hover"], 2.0)
		await drop_on(e, 1.4)
	check("stomp while dizzy defeats it", await wait_gone(e, 2.5))
	await secs(0.3)
	await shot("on_its_back")
	finish()


func _test_grenadier() -> void:
	var e := begin("gingerbread_grenadier")
	if e == null:
		return
	var enemies: Dictionary = lab.get("enemies")
	await drive(e.global_position + Vector3(0, 0, 5.0), 3.0, 3.0)
	check("squad halts and advances", await wait_state(e, ["advance", "windup"], 5.0))
	await shot("halt")
	var front: EnemyBase = e as EnemyBase
	# Frontal punch must be blocked by the lance.
	_hits.clear()
	var d := front.forward()
	player.teleport(front.global_position + d * 1.0 + Vector3(0, 0.05, 0), atan2(d.x, d.z))
	await frames(2)
	player.punch()
	await frames(12)
	var blocked := false
	for h in _hits:
		if not bool(h["landed"]):
			blocked = true
	check("lance blocks a frontal punch", blocked and is_instance_valid(front) and not front.is_defeated, str(_hits))
	await shot("clang")
	# Stomp from above.
	await drop_on(front, 1.8)
	check("stomp from above crumbles it", await wait_gone(front, 2.5))
	await shot("crumbs")
	# Punch from behind on a squad mate.
	var mate: EnemyBase = null
	if is_instance_valid(enemies.get("gingerbread_grenadier_0")):
		mate = enemies.get("gingerbread_grenadier_0") as EnemyBase
	if mate != null:
		_focus = mate
		mate.ai_enabled = false
		var f := mate.forward()
		player.teleport(mate.global_position - f * 1.0 + Vector3(0, 0.05, 0), atan2(-f.x, -f.z))
		player.rotation.y = mate.rotation.y
		await frames(2)
		player.punch()
		check("punch from behind defeats it", await wait_gone(mate, 2.5), str(_hits))
	finish()


func _test_gummy() -> void:
	var e := begin("gummy_brute")
	if e == null:
		return
	var b := e as EnemyBase
	var hp0 := b.hp
	var top: float = b.head_height
	player.teleport(e.global_position + Vector3(0, top + 2.0, 0), 0.0)
	var max_vy := -100.0
	for i in 50:
		await get_tree().physics_frame
		max_vy = maxf(max_vy, player.velocity.y)
	check("its head is a trampoline", is_instance_valid(e) and b.hp == hp0 and max_vy > 12.0, "hp=%d max_bounce_vy=%.1f" % [b.hp, max_vy])
	await secs(0.3)
	await shot("trampoline")
	await secs(1.2)
	player.teleport(e.global_position + Vector3(0, 0.1, 5.5), 0.0)
	check("winds up and slams", await wait_state(e, ["attack"], 6.0))
	await secs(0.5)
	await shot("bounce_slam")
	player.jump()
	check("winded after the slam", await wait_state(e, ["recover"], 3.0))
	await shot("shockwave")
	await chase_and_punch(e, 1.6, 1.6)
	await frames(30)
	if is_instance_valid(e) and not b.is_defeated:
		await chase_and_punch(e, 1.0, 1.6)
	if is_instance_valid(e) and not b.is_defeated and b.state == "hurt":
		await frames(20)
	if is_instance_valid(e) and not b.is_defeated:
		await wait_state(e, ["recover"], 6.0)
		await chase_and_punch(e, 1.6, 1.6)
	check("two punches after slams melt it", await wait_gone(e, 3.0), str(_hits))
	await secs(0.2)
	await shot("melt")
	finish()


func _report() -> void:
	var passed := 0
	var total := 0
	for r in results:
		for c in r["checks"]:
			total += 1
			if c["pass"]:
				passed += 1
	var out := {"utc": Time.get_datetime_string_from_system(true) + "Z", "passed": passed, "total": total,
		"seconds": (Time.get_ticks_msec() - _t0) / 1000.0, "player": "EnemyLabPlayer stub", "families": results}
	var path := Dev.arg("labtest-out", "user://labtest.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	print("[LabTest] DONE %d/%d checks passed -> %s" % [passed, total, path])
	if Dev.has_arg("quit-when-done"):
		get_tree().quit()
