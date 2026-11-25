extends Node
## QA COPY (critique W1 r1 QA, r1c): byte-for-byte copy of res://scripts/worlds/w1_bot.gd at 2026-10-18 21:20 Bangkok with
## only the three type annotations fixed (lines ~868-877 failed to parse: "Cannot infer the type"). Run via W1BotQA.tscn.
## W1 reachability bot (dev only, --w1bot=<test>[,<test>...]). Drives the real MakPlayer through its replay input
## layer (world-steered stick, held buttons) with closed-loop steering, so every jump, ride, wall kick and Ham Slam
## below runs through the shipping movement code. Teleports are used only to start a leg; each one is logged.
## Prints "[W1 bot] PASS|FAIL <test> ..." and, with --w1bot-out=<abs json>, writes the results, then quits.

var p: CharacterBody3D
var inp: Object
var stick := Vector2.ZERO
var results: Array = []
var _log: Array = []
var level: Node


func _ready() -> void:
	process_physics_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(0.6).timeout
	p = get_tree().get_first_node_in_group("player") as CharacterBody3D
	level = get_parent().get_node_or_null("Level")
	if p == null:
		_finish_fail("no player")
		return
	inp = p.get("inp")
	inp.call("setup", {"steer": "world", "events": []}, 0.2, 1.0)
	var dev := get_node_or_null("/root/Dev")
	var tests := String(dev.call("arg", "w1botqa", "all")).split(",")
	if tests.size() == 1 and tests[0] == "all":
		tests = PackedStringArray(["w1-3", "w1-2", "w1-6", "w1-1", "w1-4", "w1-5", "w1-8", "w1-7", "w1-100"])
	for t in tests:
		_calm_enemies(t != "w1-1")
		var t0 := Time.get_ticks_msec()
		_log = []
		var ok: bool = await Callable(self, "t_" + t.replace("-", "_")).call()
		var row := {"test": t, "pass": ok, "seconds": (Time.get_ticks_msec() - t0) / 1000.0, "log": _log.duplicate(), "truffles": _owned()}
		results.append(row)
		print("[W1 bot] %s %s %.1fs %s" % ["PASS" if ok else "FAIL", t, row["seconds"], " | ".join(_log)])
		stick = Vector2.ZERO
		await frames(20)
	var out := String(dev.call("arg", "w1bot-out", ""))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"utc": Time.get_datetime_string_from_system(true), "results": results}, "  "))
	get_tree().paused = false
	get_tree().quit()


func _calm_enemies(calm: bool) -> void:
	var qdev := get_node_or_null("/root/Dev")
	if qdev and qdev.has_arg("qa-ai-on"):
		calm = false  # QA: enemies stay live for every test
	for e in get_tree().get_nodes_in_group("enemy"):
		e.set("ai_enabled", not calm)
	if calm:
		note("enemy AI paused for the movement test")


func _finish_fail(msg: String) -> void:
	print("[W1 bot] FAIL setup ", msg)
	get_tree().quit()


func _physics_process(_d: float) -> void:
	if inp:
		inp.set("_r_stick", stick)


func note(s: String) -> void:
	_log.append(s)


func _owned() -> Array:
	var g := get_node_or_null("/root/Game")
	var out := []
	if g:
		for id in ["W1-1", "W1-2", "W1-3", "W1-4", "W1-5", "W1-6", "W1-7", "W1-8", "W1-100"]:
			if g.call("has_truffle", id):
				out.append(id)
	return out


func has(id: String) -> bool:
	var g := get_node_or_null("/root/Game")
	return g != null and bool(g.call("has_truffle", id))


# ------------------------------------------------------------------ primitives

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	# The truffle celebration pauses the tree; wait it out.
	while get_tree().paused:
		await get_tree().process_frame


func secs(t: float) -> void:
	await frames(int(t * 60.0))


func tp(pos: Vector3, yaw_deg: float = 0.0) -> void:
	stick = Vector2.ZERO
	p.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos + Vector3(0, 0.05, 0)))
	note("tp(%.1f,%.1f,%.1f)" % [pos.x, pos.y, pos.z])
	await frames(12)


func pos() -> Vector3:
	return p.global_position


func steer_to(t: Vector3, mag: float = 1.0) -> float:
	var d := t - p.global_position
	d.y = 0.0
	if d.length() < 0.01:
		stick = Vector2.ZERO
		return 0.0
	stick = Vector2(d.x, -d.z).normalized() * mag
	return d.length()


func go(t: Vector3, tol: float = 0.35, timeout: float = 10.0) -> bool:
	var f := 0
	while f < int(timeout * 60.0):
		var dist := steer_to(t)
		if dist < tol:
			stick = Vector2.ZERO
			return true
		if dist < 1.2:
			stick *= clampf(dist / 1.2, 0.35, 1.0)
		await frames(1)
		f += 1
	stick = Vector2.ZERO
	note("go timeout at (%.1f,%.1f,%.1f) target (%.1f,%.1f,%.1f)" % [pos().x, pos().y, pos().z, t.x, t.y, t.z])
	return false


func hold(action: String, n: int) -> void:
	var hf: Dictionary = inp.get("_hold_frames")
	hf[action] = n


func grounded() -> bool:
	return p.is_on_floor()


## Walks to a take-off point on the current surface (toward t, `run` metres back from the edge), then jumps toward
## t while steering, and waits for the landing. Returns true when it lands within `tol` of t's height.
func hop(t: Vector3, takeoff: Vector3 = Vector3.INF, hold_frames: int = 18, tol_y: float = 0.35) -> bool:
	if takeoff != Vector3.INF:
		await go(takeoff, 0.3, 6.0)
	steer_to(t)
	hold("jump", hold_frames)
	await frames(4)
	var f := 0
	while f < 240:
		var d := steer_to(t)
		if d < 0.25:
			stick = Vector2.ZERO
		await frames(1)
		f += 1
		if f > 6 and grounded():
			break
	stick = Vector2.ZERO
	await frames(3)
	var ok := pos().y > t.y - tol_y and pos().y < t.y + 2.5
	if not ok:
		note("hop miss: at (%.2f,%.2f,%.2f) wanted y %.2f" % [pos().x, pos().y, pos().z, t.y])
	return ok


## Hop across a chain of platform tops; the take-off point is 0.55 m inside the current top toward the next one.
func chain(tops: Array, half: float = 0.6) -> bool:
	for i in tops.size():
		var t: Vector3 = tops[i]
		var here := pos()
		var dir := Vector3(t.x - here.x, 0, t.z - here.z).normalized()
		var take := here + dir * minf(half, maxf(0.0, Vector3(t.x - here.x, 0, t.z - here.z).length() - 1.0))
		var ok := await hop(t, take)
		if not ok:
			# One retry from where we stand.
			ok = await hop(t)
			if not ok:
				note("chain failed at step %d" % (i + 1))
				return false
	return true


func slam() -> void:
	hold("jump", 10)
	await frames(22)
	hold("crouch", 6)
	await frames(60)


func top_of(id: String) -> Vector3:
	var pl: Dictionary = level.get("plat")
	var a: Array = pl[id]["top"]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ------------------------------------------------------------------ tests

func t_w1_3() -> bool:
	# Stick Scaffold: grove floor -> sc1..sc9 -> pole landing -> deck -> truffle, all real jumps.
	var sc1 := top_of("scaffold_sc1")
	await tp(Vector3(sc1.x + 1.6, W1Terrain.height(sc1.x + 1.6, sc1.z + 1.6), sc1.z + 1.6), 45.0)
	var tops: Array = []
	for i in range(1, 4):
		tops.append(top_of("scaffold_sc%d" % i))
	var ok := await chain(tops)
	if ok:
		# Fix round 1 (R3.2): J14 jump to the greased pole's climbable top, climb, orbit to face sc7, pole jump.
		ok = await _pole_leg()
	if ok:
		# Crumbling sticks: no dawdling, jump straight on.
		ok = await chain([top_of("scaffold_sc8")], 0.0)
	if ok:
		ok = await chain([top_of("scaffold_sc9"), Vector3(-42.9, 16.0, -27.0)])
	note("reached y %.2f" % pos().y)
	if not ok:
		return false
	await go(Vector3(-46.2, 16.0, -31.4), 0.3, 6.0)
	await secs(1.0)
	return has("W1-3")


func _pole_leg() -> bool:
	var pt := top_of("scaffold_pole")
	var s7 := top_of("scaffold_sc7")
	var here := pos()
	var dir := Vector3(pt.x - here.x, 0, pt.z - here.z).normalized()
	await go(here + dir * 0.6, 0.25, 3.0)
	steer_to(pt)
	hold("jump", 18)
	var f := 0
	while f < 120 and String(p.call("get_state_name")) != "pole_climb":
		steer_to(pt)
		await frames(1)
		f += 1
	stick = Vector2.ZERO
	if String(p.call("get_state_name")) != "pole_climb":
		note("pole grab missed at (%.2f,%.2f,%.2f)" % [pos().x, pos().y, pos().z])
		return false
	note("pole grabbed at feet %.2f" % pos().y)
	stick = Vector2(0, 1)
	await frames(50)
	# Orbit until Mak sits on the far side of the pole from sc7 (the jump goes radially away from the pole).
	var want := Vector3(s7.x - pt.x, 0, s7.z - pt.z).normalized()
	var sgn := 1.0
	var last := -2.0
	for k in 420:
		var radial := Vector3(pos().x - pt.x, 0, pos().z - pt.z).normalized()
		var dd := radial.dot(want)
		if dd > 0.985:
			break
		if k % 20 == 19:
			if dd < last - 0.01:
				sgn = -sgn
			last = dd
		stick = Vector2(sgn * 0.6, 0.0)
		await frames(1)
	stick = Vector2.ZERO
	note("pole feet %.2f, jumping" % pos().y)
	hold("jump", 6)
	f = 0
	while f < 120:
		await frames(1)
		f += 1
		if f > 8 and grounded():
			break
	await frames(4)
	var ok := pos().y > s7.y - 0.35 and pos().y < s7.y + 1.0
	note("pole jump landed (%.2f,%.2f,%.2f) ok=%s" % [pos().x, pos().y, pos().z, str(ok)])
	return ok


func _sail_steps() -> Array:
	var out: Array = []
	var rp := level.get_node_or_null("SailSteps")
	if rp:
		for n in rp.find_children("*", "AnimatableBody3D", true, false):
			out.append(n)
	return out


func t_w1_2() -> bool:
	# Windmill: Mill Stage -> board a sail step at the bottom -> ride -> jump north onto the weathervane deck.
	await tp(Vector3(40, 17.05, -38.4), 0.0)
	var steps := _sail_steps()
	if steps.is_empty():
		note("no sail steps found")
		return false
	note("%d sail steps" % steps.size())
	await go(Vector3(40, 17.05, -40.1), 0.25, 4.0)
	var rider: Node3D = null
	for f in 60 * 30:
		for st in steps:
			var sp := (st as Node3D).global_position
			if sp.y < 18.6 and absf(sp.x - 40.0) < 2.2:
				# Approaching the bottom: its next position is closer to x 40.
				var v := sp.x - 40.0
				await frames(1)
				var sp_next := (st as Node3D).global_position
				if absf(sp_next.x - 40.0) < absf(v) and absf(sp_next.x - 40.0) < 1.0:
					rider = st
					break
		if rider:
			break
		await frames(1)
	if rider == null:
		note("no step passed the bottom")
		return false
	note("boarding step at (%.1f,%.2f,%.1f)" % [rider.global_position.x, rider.global_position.y, rider.global_position.z])
	hold("jump", 8)
	for f in 70:
		steer_to(rider.global_position)
		await frames(1)
		if f > 8 and grounded():
			break
	stick = Vector2.ZERO
	await frames(6)
	note("on step: y %.2f (step %.2f)" % [pos().y, rider.global_position.y])
	if absf(pos().y - rider.global_position.y) > 1.0:
		return false
	# Ride, keeping centred on the step, until it nears the crest.
	var top_y := 0.0
	for f in 60 * 14:
		var sp2 := rider.global_position
		top_y = maxf(top_y, pos().y)
		var d := steer_to(sp2)
		if d < 0.3:
			stick = Vector2.ZERO
		else:
			stick *= 0.4
		# The top of the wheel moves east at about 3.6 m/s: leave just before the crest so the carry lands on the deck.
		if sp2.y > 32.0 and sp2.x > 36.9 and sp2.x < 38.0:
			break
		await frames(1)
	note("ride peak y %.2f" % top_y)
	var deck := Vector3(40, 28.1, -45.2)
	var aim := deck - Vector3(1.6, 0, 0)  # lean against the wheel's eastward carry
	steer_to(aim)
	hold("jump", 18)
	for f in 150:
		steer_to(aim if f < 30 else deck)
		await frames(1)
		if f > 10 and grounded():
			break
	stick = Vector2.ZERO
	await secs(1.0)
	note("landed at (%.1f,%.2f,%.1f)" % [pos().x, pos().y, pos().z])
	await go(deck, 0.3, 3.0)
	await secs(0.8)
	return has("W1-2")


func t_w1_6() -> bool:
	# Chimney: enter by the soot door, then alternate wall kicks between the east (x 12.8) and west (x 9.8) walls.
	await tp(Vector3(14.2, 12.05, -36.0), -90.0)
	await go(Vector3(10.3, 12.05, -36.0), 0.3, 5.0)
	note("inside shaft x %.2f" % pos().x)
	var east := true
	var kicks := 0
	var best := pos().y
	stick = Vector2(1.0, 0.0)
	await frames(14)
	hold("jump", 12)
	await frames(8)
	var since_kick := 99
	for f in 60 * 14:
		stick = Vector2(1.0 if east else -1.0, 0.0)
		best = maxf(best, pos().y)
		if pos().y > 26.0:
			stick = Vector2(clampf((11.3 - pos().x) * 2.0, -1.0, 1.0), 0.0)
		since_kick += 1
		if p.is_on_wall() and not grounded() and since_kick > 6:
			east = not east
			stick = Vector2(1.0 if east else -1.0, 0.0)
			hold("jump", 3)
			kicks += 1
			since_kick = 0
		elif grounded() and since_kick > 10:
			# Landed (floor or soot ledge): back up to the far wall, run and jump again.
			east = pos().x < 11.3
			stick = Vector2(-1.0 if east else 1.0, 0.0)
			await frames(10)
			stick = Vector2(1.0 if east else -1.0, 0.0)
			await frames(12)
			hold("jump", 12)
			since_kick = 0
		if has("W1-6"):
			break
		await frames(1)
	note("kicks %d, best y %.2f" % [kicks, best])
	await secs(0.5)
	return has("W1-6")


func t_w1_1() -> bool:
	# Straw House Siege: fight WW1 for real (stomp from above), then the other three are defeated by script.
	var ww1 := level.get_node_or_null("WW1") as Node3D
	if ww1 == null:
		note("WW1 missing")
		return false
	var wp := ww1.global_position
	await tp(wp + Vector3(0, 3.5, 0.0), 0.0)
	await frames(60)
	note("WW1 state %s" % str(ww1.get("state")))
	for id in ["WW1", "WW2", "WW3", "WW4"]:
		var w := level.get_node_or_null(id)
		if w and is_instance_valid(w) and String(w.get("state")) != "defeated":
			if w.has_method("defeat"):
				w.call("defeat", "stomp", w.global_position + Vector3(0, 1, 0))
				note("%s defeated by script" % id)
		elif w == null or not is_instance_valid(w):
			note("%s gone (defeated in play)" % id)
	await secs(3.0)
	await tp(Vector3(-20, 0.5, 34.0), 180.0)
	await go(Vector3(-20, 0.5, 31.5), 0.3, 5.0)
	await secs(1.2)
	return has("W1-1")


func double_jump_onto(top: Vector3, from: Vector3) -> bool:
	# Run in from `from`, hop once, then chain the second (higher) jump on landing.
	await tp(from, 0.0)
	steer_to(top)
	await frames(30)
	hold("jump", 6)
	await frames(4)
	for f in 80:
		steer_to(top)
		await frames(1)
		if f > 3 and grounded():
			break
	hold("jump", 18)
	await frames(4)
	for f in 120:
		var d := steer_to(top)
		if d < 0.3:
			stick = Vector2.ZERO
		await frames(1)
		if f > 6 and grounded():
			break
	stick = Vector2.ZERO
	await frames(6)
	return pos().y > top.y - 0.4


func t_w1_4() -> bool:
	# Bust the Bellows: B1 from its crate; B2 and B3 (no crates, R1.7) with a running chained double jump, then Ham Slam.
	var broken := 0
	for lid in ["bellows_B1", "bellows_B2", "bellows_B3"]:
		var bel := level.get_node_or_null("Bellows_" + lid) as Node3D
		if bel == null:
			note("missing " + lid)
			continue
		var top := bel.global_position + Vector3(0, 2.35, 0)
		var ok := false
		var cr := level.get_node_or_null(lid + "_crate") as Node3D
		if cr:
			await tp(cr.global_position + Vector3(0, 0.05, 0), bel.rotation_degrees.y)
			ok = await hop(top, Vector3.INF, 18, 0.5)
		else:
			var tries := 0
			for k in 12:
				var ang := TAU * k / 12.0
				var from := bel.global_position + Vector3(cos(ang), 0, sin(ang)) * 6.0
				from.y = W1Terrain.height(from.x, from.z)
				if absf(from.y - bel.global_position.y) > 0.25:
					continue
				var mid := bel.global_position + Vector3(cos(ang), 0, sin(ang)) * 3.0
				if absf(W1Terrain.height(mid.x, mid.z) - bel.global_position.y) > 0.25:
					continue
				from.y += 0.05
				ok = await double_jump_onto(top, from)
				tries += 1
				if ok or tries >= 3:
					break
		note("%s on top=%s y %.2f" % [lid, str(ok), pos().y])
		await slam()
		if bool(bel.get("is_broken")):
			broken += 1
			note("%s busted" % lid)
	if broken < 3:
		return false
	await secs(3.5)
	# R2.4: the well erupts; hop onto the rim and let the spout carry you up to the truffle at y 12.5.
	await tp(Vector3(2, 0.45, 0.6), 180.0)
	var best := 0.0
	steer_to(Vector3(2, 0, -3))
	hold("jump", 18)
	for f in 60 * 8:
		var d := steer_to(Vector3(2, 0, -3))
		if d < 0.3:
			stick = Vector2.ZERO
		best = maxf(best, pos().y)
		if grounded() and f > 30 and pos().y < 1.0:
			hold("jump", 18)
		if has("W1-4"):
			break
		await frames(1)
	note("spout ride best y %.2f" % best)
	await secs(1.0)
	return has("W1-4")


func _page(i: int) -> Node3D:
	return level.get_node_or_null("Page_P%d" % i) as Node3D


func _speed() -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


func t_w1_5() -> bool:
	# R1.5: five pages, five moves, each with the real moveset.
	var g := get_node_or_null("/root/Game")
	# P1 Hollow Log: crouch-walk through the 1.0 m tunnel from the east mouth.
	await tp(Vector3(-11.5, W1Terrain.height(-11.5, 1.5) + 0.05, 1.5), -90.0)
	await go(Vector3(-13.2, 0, 1.5), 0.3, 4.0)
	hold("crouch", 400)
	await frames(6)
	await go(Vector3(-17.0, 0, 1.5), 0.3, 6.0)
	await secs(0.4)
	hold("crouch", 0)
	note("P1 at (%.1f,%.2f,%.1f)" % [pos().x, pos().y, pos().z])
	# P2 Stone Finger: long jump east from the Tor top (run, crouch + jump).
	await tp(Vector3(30.0, 7.05, 3.0), -90.0)
	stick = Vector2(1, 0)
	for f in 120:
		await frames(1)
		if pos().x > 38.5:
			break
	hold("crouch", 4)
	await frames(1)
	hold("jump", 10)
	for f in 150:
		steer_to(Vector3(50.75, 0, 3.0))
		await frames(1)
		if f > 10 and grounded():
			break
	stick = Vector2.ZERO
	await secs(0.6)
	note("P2 long jump landed (%.1f,%.2f,%.1f)" % [pos().x, pos().y, pos().z])
	# P3 backflip onto the hut roof: stand at the door with your back to it (facing east), crouch, jump.
	await tp(Vector3(-44.85, 16.05, -28.6), -90.0)
	stick = Vector2(0.25, 0)
	await frames(8)
	stick = Vector2.ZERO
	await frames(10)
	hold("crouch", 20)
	await frames(8)
	note("P3 pre-jump state %s" % str(p.call("get_state_name")))
	hold("jump", 16)
	await frames(10)
	note("P3 state %s vy %.1f" % [str(p.call("get_state_name")), p.velocity.y])
	await secs(1.4)
	note("P3 backflip landed (%.1f,%.2f,%.1f)" % [pos().x, pos().y, pos().z])
	await go(Vector3(-47.5, 0, -28.6), 0.3, 2.0)
	hold("jump", 16)
	await secs(1.2)
	# P4 Kick Cleft: wall kicks in the 2.4 m slot, then step onto the east wall top.
	await tp(Vector3(-54.0, W1Terrain.height(-54, -8.5) + 0.1, -8.5), 0.0)
	var east := true
	var since := 99
	stick = Vector2(-1, 0)
	await frames(8)
	stick = Vector2(1, 0)
	await frames(8)
	hold("jump", 12)
	await frames(6)
	var best := 0.0
	for f in 60 * 10:
		since += 1
		best = maxf(best, pos().y)
		if pos().y > 7.3 and (p.velocity.x > 0.5 or pos().x > -52.6):
			var dd := steer_to(Vector3(-51.4, 0, -7.75))
			if dd < 0.4:
				stick = Vector2.ZERO
			if grounded():
				break
		else:
			stick = Vector2(1.0 if east else -1.0, 0.0)
			if p.is_on_wall() and not grounded() and since > 6:
				east = not east
				stick = Vector2(1.0 if east else -1.0, 0.0)
				hold("jump", 3)
				since = 0
			elif grounded() and since > 10:
				east = pos().x < -54.0
				stick = Vector2(-1.0 if east else 1.0, 0.0)
				await frames(8)
				stick = Vector2(1.0 if east else -1.0, 0.0)
				await frames(10)
				hold("jump", 12)
				since = 0
		await frames(1)
	await go(Vector3(-51.4, 0, -7.75), 0.3, 3.0)
	await secs(0.5)
	note("P4 best y %.2f, at (%.1f,%.2f,%.1f)" % [best, pos().x, pos().y, pos().z])
	# P5 Scarecrow Run: triple jump along the mown alley onto the boater.
	var a0 := Vector3(-4.0, 0, 21.2)
	var dir := (Vector3(16, 0, 40) - a0).normalized()
	await tp(Vector3(a0.x, W1Terrain.height(a0.x, a0.z) + 0.05, a0.z), 0.0)
	var mark0 := Vector3(2.5, 0, 27.35)
	var target := Vector3(16, 4.48, 40)
	for f in 240:
		steer_to(target)
		await frames(1)
		if (pos() - a0).dot(dir) > (mark0 - a0).dot(dir) - 0.3:
			break
	for k in 3:
		hold("jump", 14 if k < 2 else 18)
		await frames(5)
		for f in 120:
			steer_to(target)
			await frames(1)
			if f > 4 and grounded():
				break
	steer_to(target)
	await frames(6)
	stick = Vector2.ZERO
	await secs(0.8)
	note("P5 after triple at (%.1f,%.2f,%.1f)" % [pos().x, pos().y, pos().z])
	if pos().y > 4.2:
		await go(Vector3(16, 0, 40), 0.2, 2.0)
		hold("jump", 16)
		await secs(1.2)
	var left := []
	for i in range(1, 6):
		var pg := _page(i)
		if pg and is_instance_valid(pg) and pg.visible and bool(pg.get("monitoring")):
			left.append("P%d" % i)
	note("pages still in the world: %s" % str(left))
	var ford := top_of("ford_rock")
	await tp(Vector3(ford.x, ford.y + 0.05, ford.z + 0.9), 0.0)
	await go(Vector3(ford.x, ford.y, ford.z), 0.3, 3.0)
	await secs(1.5)
	return has("W1-5")


func t_w1_8() -> bool:
	# Three-dig map hunt (R2.3): willow mud (sniff + slam), gravel bar by the Ford Rock, bare ring in the orchard.
	await tp(Vector3(45.0, W1Terrain.height(45, 18.5) + 0.05, 18.5), 0.0)
	hold("sniff", 150)
	await secs(2.8)
	await go(Vector3(45.0, 0, 14.5), 0.3, 6.0)
	await slam()
	note("dig1 -> current %d" % int(level.get("dig_i")))
	var ford := top_of("ford_rock")
	await tp(Vector3(ford.x, ford.y + 0.05, ford.z), 0.0)
	var gb := top_of("gravel_bar")
	var ok := await hop(gb, Vector3.INF, 14, 0.6)
	note("gravel bar hop ok=%s y %.2f" % [str(ok), pos().y])
	await go(gb, 0.3, 2.0)
	await slam()
	note("dig2 -> current %d" % int(level.get("dig_i")))
	await tp(Vector3(36.0, W1Terrain.height(36, 45.5) + 0.05, 45.5), 0.0)
	hold("sniff", 80)
	await secs(1.4)
	await go(Vector3(36.0, 0, 42.0), 0.3, 5.0)
	await slam()
	note("dig3 -> current %d" % int(level.get("dig_i")))
	await secs(1.5)
	await go(Vector3(36.0, 0, 42.0), 0.3, 2.0)
	hold("jump", 16)
	await secs(1.5)
	return has("W1-8")


func double_jump_here(top: Vector3) -> bool:
	steer_to(top)
	hold("jump", 6)
	await frames(4)
	for f in 80:
		steer_to(top)
		await frames(1)
		if f > 3 and grounded():
			break
	hold("jump", 18)
	await frames(4)
	for f in 120:
		var d := steer_to(top)
		if d < 0.3:
			stick = Vector2.ZERO
		await frames(1)
		if f > 6 and grounded():
			break
	stick = Vector2.ZERO
	await frames(4)
	return pos().y > top.y - 0.4


func t_w1_7() -> bool:
	# The Foreman's Haystacks: enter the pen, and in each guess window double-jump onto the occupied stack and slam.
	# The bot knows the right stack (as a player who tracked it or sniffed it would); it sniffs once to exercise the trail.
	var hy := level.get_node_or_null("HayYard_W1-7")
	if hy == null:
		note("hay yard missing")
		return false
	var c: Vector3 = hy.get("center")
	await tp(Vector3(-34.0, W1Terrain.height(-34, -41.5) + 0.05, -41.5), 52.0)
	await go(Vector3(-31.8, 0, -46.6), 0.4, 6.0)
	await go(Vector3(-35.1, 0, -47.1), 0.4, 6.0)
	await go(c, 0.5, 6.0)
	note("in pen, state %s" % String(hy.get("state")))
	var slams := 0
	var sniffed := false
	for f in 60 * 320:
		if has("W1-7"):
			break
		var st := String(hy.get("state"))
		if f % 120 == 0:
			print("[W1 bot] hay t=%d state=%s hp=%d stack=%d pos=(%.1f,%.1f,%.1f)" % [f, st, int(hy.get("hp")), int(hy.call("foreman_stack")), pos().x, pos().y, pos().z])
		if st == "window":
			var i := int(hy.call("foreman_stack"))
			if i >= 0:
				if not sniffed:
					hold("sniff", 60)
					await secs(1.1)
					sniffed = true
				var stacks: Array = hy.get("stacks")
				var sp := (stacks[i] as Node3D).global_position
				var from := c + (c - sp).normalized() * 0.5
				if pos().distance_to(Vector3(from.x, pos().y, from.z)) > 0.6 or pos().y > c.y + 1.0:
					await go(from, 0.4, 3.0)
				var ok := await double_jump_here(sp + Vector3(0, 1.87, 0))
				await slam()
				slams += 1
				note("slam %d on HS%d (on top=%s), hp now %d" % [slams, i + 1, str(ok), int(hy.get("hp"))])
				continue
		elif st in ["charge_windup", "charge"]:
			# Dodge sideways relative to the Foreman, and hop over him if he gets close.
			var fm: Node3D = hy.get("foreman")
			if fm and is_instance_valid(fm):
				var d := pos() - fm.global_position
				d.y = 0
				var side := Vector3(-d.z, 0, d.x).normalized()
				var tgt := pos() + side * 3.0
				if Vector2(tgt.x - c.x, tgt.z - c.z).length() > 5.5:
					tgt = pos() - side * 3.0
				steer_to(tgt)
				if st == "charge" and d.length() < 3.2 and grounded():
					hold("jump", 18)
		elif st == "idle" and Vector2(pos().x - c.x, pos().z - c.z).length() > 7.0:
			note("outside the pen (knocked out or respawned); walking back in")
			await go(Vector3(-31.8, 0, -46.6), 0.4, 8.0)
			await go(Vector3(-35.1, 0, -47.1), 0.4, 6.0)
			await go(c, 0.5, 6.0)
		else:
			if Vector2(pos().x - c.x, pos().z - c.z).length() > 1.0:
				steer_to(c)
			else:
				stick = Vector2.ZERO
		await frames(1)
	stick = Vector2.ZERO
	note("slams %d, final state %s" % [slams, String(hy.get("state"))])
	await secs(2.5)
	await go(c, 0.3, 4.0)
	hold("jump", 16)
	await secs(1.5)
	return has("W1-7")


func t_w1_100() -> bool:
	var n := 0
	for a in get_tree().get_nodes_in_group("acorn"):
		n += 1
	var crates := get_tree().get_nodes_in_group("breakable_crate").size()
	note("acorns placed %d, crates %d" % [n, crates])
	var ah := level.get_node_or_null("AcornHundred_W1-100")
	if ah == null:
		return false
	await tp(Vector3(0, 0.45, 48), 0.0)
	ah.call("on_acorn_collected", 100)
	await secs(1.0)
	var tr := get_tree().get_nodes_in_group("truffle")
	var t100: Node3D = null
	for t in tr:
		if String(t.get("truffle_id")) == "W1-100":
			t100 = t
	if t100 == null:
		for t in get_parent().find_children("*", "Area3D", true, false):
			if String(t.get("truffle_id")) == "W1-100":
				t100 = t
	if t100 == null:
		note("no W1-100 truffle node")
		return false
	note("W1-100 at (%.1f,%.1f,%.1f)" % [t100.global_position.x, t100.global_position.y, t100.global_position.z])
	await go(t100.global_position, 0.3, 4.0)
	hold("jump", 18)
	await secs(1.5)
	return has("W1-100")


func t_chute() -> bool:
	# R3.5 brick chute: walk off the Brick Hill rim at (9, 12, -22) and slide down to the green.
	await tp(Vector3(9.0, W1Terrain.height(9.0, -22.5) + 0.05, -22.5), 180.0)
	var t0 := Time.get_ticks_msec()
	var best_speed := 0.0
	for f in 60 * 6:
		steer_to(Vector3(4.4, 0, -6.6))
		best_speed = maxf(best_speed, p.velocity.length())
		await frames(1)
		if pos().y < 1.0:
			break
	stick = Vector2.ZERO
	note("chute end (%.1f,%.2f,%.1f) in %.1fs, top speed %.1f m/s, state %s" % [pos().x, pos().y, pos().z, (Time.get_ticks_msec() - t0) / 1000.0, best_speed, str(p.call("get_state_name"))])
	return pos().y < 1.2 and pos().z > -12.0


# ------------------------------------------------------------------ fix round 2 checks

## R3.4 Huff back: a normal landing on B1's plate fires one puff; WW4 (disguised, in B1's lane) is unmasked, B1 survives.
func t_puff() -> bool:
	_calm_enemies(false)
	var bel := level.get_node_or_null("Bellows_bellows_B1") as Node3D
	var ww4 := level.get_node_or_null("WW4")
	if bel == null or ww4 == null:
		note("B1 or WW4 missing")
		return false
	note("WW4 disguised before: %s at (%.1f,%.1f)" % [str(ww4.get("disguised")), (ww4 as Node3D).global_position.x, (ww4 as Node3D).global_position.z])
	var cr := level.get_node_or_null("bellows_B1_crate") as Node3D
	await tp(cr.global_position + Vector3(0, 0.05, 0), bel.rotation_degrees.y)
	var ok := await hop(bel.global_position + Vector3(0, 2.35, 0), Vector3.INF, 18, 0.5)
	note("on plate=%s y %.2f" % [str(ok), pos().y])
	await secs(1.5)
	var puffed := level.get_node_or_null("Puff_bellows_B1") != null
	note("WW4 disguised after: %s, B1 broken: %s" % [str(ww4.get("disguised")) if is_instance_valid(ww4) else "gone", str(bel.get("is_broken"))])
	return ok and not bool(bel.get("is_broken")) and is_instance_valid(ww4) and not bool(ww4.get("disguised"))


## R2.8: WW3 hides in the sneezing haystack at (-34, 32); a Ham Slam beside it bursts it and WW3 appears unmasked.
func t_hay3() -> bool:
	_calm_enemies(false)
	if level.get_node_or_null("WW3") != null:
		note("WW3 already in the level before the burst")
		return false
	await tp(Vector3(-32.4, W1Terrain.height(-32.4, 32.0), 32.0), -90.0)
	await secs(4.0)
	await slam()
	await secs(1.0)
	var w := level.get_node_or_null("WW3")
	note("WW3 after slam: %s disguised=%s" % [str(w != null), str(w.get("disguised")) if w else "-"])
	return w != null and not bool(w.get("disguised"))


## QA r1: W1-3 can no longer be taken round Hazel's gate: standing on the deck shows no truffle until the scaffold top.
func t_gate() -> bool:
	await tp(Vector3(-44.0, 16.05, -32.0), 90.0)
	await go(Vector3(-46.2, 16.0, -31.4), 0.3, 4.0)
	await secs(1.0)
	var early := has("W1-3")
	note("deck first (gate route): owned=%s" % str(early))
	var s9 := top_of("scaffold_sc9")
	await tp(s9, 0.0)
	await secs(1.2)
	await tp(Vector3(-44.0, 16.05, -32.0), 90.0)
	await go(Vector3(-46.2, 16.0, -31.4), 0.3, 4.0)
	await secs(1.5)
	note("after the scaffold top: owned=%s" % str(has("W1-3")))
	return not early and has("W1-3")


## QA + visual r1: every crow perch sits on the surface below it (gap 0 to 0.4 m), and B3's gust is zero in the flue.
func t_perch() -> bool:
	var ok := true
	var space: PhysicsDirectSpaceState3D = (level as Node3D).get_world_3d().direct_space_state
	for id in ["CB1", "CB2", "CB3", "CB4", "CB5", "CB6", "CB7"]:
		var c := level.get_node_or_null(id) as Node3D
		if c == null:
			continue
		var p0 := c.global_position
		var q := PhysicsRayQueryParameters3D.create(p0 + Vector3(0, 0.3, 0), p0 + Vector3(0, -3.0, 0), 1)
		var r: Dictionary = space.intersect_ray(q)
		var gap := p0.y - ((r["position"] as Vector3).y if not r.is_empty() else -99.0)
		var inside: bool = space.intersect_point(_pp(p0 + Vector3(0, 0.3, 0)), 1).size() > 0
		note("%s y %.2f gap %.2f inside=%s" % [id, p0.y, gap, str(inside)])
		if gap < -0.05 or gap > 0.45 or inside:
			ok = false
	var z := level.get_node_or_null("Gust_bellows_B3")
	if z:
		var worst := 0.0
		for x in [10.2, 11.3, 12.5]:
			for zz in [-35.1, -36.0, -36.9]:
				worst = maxf(worst, (z.call("get_wind", Vector3(x, 12.1, zz)) as Vector3).length())
		note("B3 wind on the flue floor max %.2f m/s" % worst)
		ok = ok and worst < 0.01
	return ok


func _pp(at: Vector3) -> PhysicsPointQueryParameters3D:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = at
	q.collision_mask = 1
	return q


## Fun r1 W1-7: a Ham Slam from the ground at the foot of the occupied stack counts (no double jump onto the top).
func t_hayfoot() -> bool:
	var hy := level.get_node_or_null("HayYard_W1-7")
	if hy == null:
		return false
	var c: Vector3 = hy.get("center")
	await tp(Vector3(-34.0, W1Terrain.height(-34, -41.5) + 0.05, -41.5), 52.0)
	await go(Vector3(-31.8, 0, -46.6), 0.4, 6.0)
	await go(Vector3(-35.1, 0, -47.1), 0.4, 6.0)
	await go(c, 0.5, 6.0)
	var hp0 := int(hy.get("hp"))
	for f in 60 * 40:
		if String(hy.get("state")) == "window":
			break
		await frames(1)
	var i := int(hy.call("foreman_stack"))
	if i < 0:
		note("no window")
		return false
	var stacks: Array = hy.get("stacks")
	var sp := (stacks[i] as Node3D).global_position
	await go(sp + (c - sp).normalized() * 1.55, 0.3, 3.0)
	note("at the foot of HS%d, %.2f m from its centre, feet y %.2f" % [i + 1, Vector2(pos().x - sp.x, pos().z - sp.z).length(), pos().y])
	await slam()
	await secs(0.5)
	note("hp %d -> %d, state %s" % [hp0, int(hy.get("hp")), String(hy.get("state"))])
	return int(hy.get("hp")) < hp0
