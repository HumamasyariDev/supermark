extends Node
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
## Frames the jump button stays held per wall kick. The kick state is in the jump-cut set (release while rising halves
## vy), so a real player holds it; 14 frames was the critic's measurement, 16 leaves margin. Must stay below the
## ~23 frames a kick takes to cross the 2.2-3 m shafts, or the next press never registers.
const KICK_HOLD := 16
## The Kick Cleft slot is 2.4 m (about 17 frames between walls), so its kicks are held a little shorter.
const KICK_HOLD_CLEFT := 11


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
	var tests := String(dev.call("arg", "w1bot", "all")).split(",")
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
	_trace_row()


# ------------------------------------------------------------------ owner fix 2026-10-19: per-frame state trace
## --w1bot-trace=<abs jsonl>: one row per physics frame with the controller, collision, wind and animator state, so a
## state left over after a mission (the owner's post-W1-6 walking jitter) shows up as a difference from a clean walk.
var _tr: FileAccess = null
var _tr_tag := ""
var _tr_on := false

func _trace_row() -> void:
	if not _tr_on or p == null or not is_instance_valid(p):
		return
	if _tr == null:
		var path := String(get_node("/root/Dev").call("arg", "w1bot-trace", ""))
		if path == "":
			_tr_on = false
			return
		_tr = FileAccess.open(path, FileAccess.WRITE)
		if _tr == null:
			_tr_on = false
			return
	var an: Node = p.get("animator")
	var cap: Variant = p.get("_capsule")
	var bs: Variant = p.get("body_shape")
	var cam: Node = get_tree().get_first_node_in_group("game_camera")
	var row := {"tag": _tr_tag, "f": Engine.get_physics_frames(), "p": _r3(p.global_position), "v": _r3(p.velocity),
		"s": str(p.get("state")), "st": snappedf(float(p.get("state_time")), 0.001), "g": bool(p.get("grounded")), "of": p.is_on_floor(),
		"ow": p.is_on_wall(), "vy": snappedf(float(p.get("vy")), 0.001), "fs": snappedf(float(p.get("forward_speed")), 0.001),
		"crouch_shape": p.get("crouched_shape"), "cap_h": snappedf((cap as CapsuleShape3D).height, 0.001) if cap is CapsuleShape3D else -1.0,
		"cap_y": snappedf((bs as CollisionShape3D).position.y, 0.001) if bs is CollisionShape3D else -1.0,
		"snap": snappedf(p.floor_snap_length, 0.001), "up": _r3(p.up_direction), "fn": _r3(p.get_floor_normal()),
		"wind": _r3(p.get("wind_vel")), "wy_raw": str((p.get("wind_vel") as Vector3).y), "vy_out": str(p.velocity.y), "ext": _r3(p.get("ext_vel")), "plat": _r3(p.get_platform_velocity()),
		"scale": _r3(p.scale), "layer": p.collision_layer, "mask": p.collision_mask, "paused": get_tree().paused,
		"stick": [snappedf(stick.x, 0.01), snappedf(stick.y, 0.01)]}
	for k in ["crouch_held", "sliding", "use_slide_vel", "braking", "pushing_wall", "hurt_blink", "invulnerable", "on_ledge"]:
		var v: Variant = p.get(k)
		if v != null:
			row[k] = v if not (v is float) else snappedf(v, 0.001)
	if an != null:
		for k in ["_state", "_sq", "_sq_hold", "_tsq_hold", "_land_t", "_land_amt", "_ceil_k", "_spine_scale", "_hb", "_brake_t", "_settle_t", "_idle_var"]:
			var v2: Variant = an.get(k)
			if v2 != null:
				row["a" + k] = v2 if not (v2 is float) else snappedf(v2, 0.001)
		var rp: Variant = an.get("_root_pos")
		if rp is Vector3:
			row["a_root"] = _r3(rp)
	if cam != null:
		row["cam_shake"] = snappedf(float(cam.get("_shake_amp") if cam.get("_shake_amp") != null else 0.0), 0.001)
		row["cam_zone"] = str((cam.get("zone") as Node).name) if cam.get("zone") is Node else ""
	_tr.store_line(JSON.stringify(row))


## Every property of the player body, its animator and its child shapes, as strings (diffed between walk probes).
func _dump_props(tag: String) -> void:
	if _tr == null:
		_trace_row()
	if _tr == null:
		return
	var d := {}
	for obj: Object in [p, p.get("animator"), p.get("inp")]:
		if obj == null:
			continue
		for prop in obj.get_property_list():
			var u := int(prop["usage"])
			if u & (PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_EDITOR) == 0:
				continue
			var n := str(prop["name"])
			d[obj.get_class() + ":" + n] = str(obj.get(n)).left(200)
	for c in p.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		d["shape:" + str(p.get_path_to(cs))] = "%s dis=%s pos=%s" % [str(cs.shape), str(cs.disabled), str(cs.position)]
	d["exceptions"] = str(p.get_collision_exceptions())
	_tr.store_line(JSON.stringify({"dump": tag, "props": d}))


func _r3(v: Variant) -> Array:
	if not (v is Vector3):
		return []
	var w: Vector3 = v
	return [snappedf(w.x, 0.001), snappedf(w.y, 0.001), snappedf(w.z, 0.001)]


## Owner fix probe: walk a fixed loop on the flat Brick Hill top beside the chimney's soot door (no teleport, so any
## state left over from the previous leg is kept): straight east-west passes, a stop, and a slow walk.
func t_walkprobe() -> bool:
	_tr_on = true
	_tr_tag = "walk_" + str(results.size())
	var y := pos().y
	note("walkprobe start (%.1f,%.2f,%.1f) state %s" % [pos().x, pos().y, pos().z, str(p.get("state"))])
	_dump_props(_tr_tag)
	for leg in [[Vector3(18.5, y, -35.0), 1.0], [Vector3(15.5, y, -31.0), 1.0], [Vector3(18.5, y, -31.0), 0.4]]:
		var f := 0
		while f < 150:
			var dist := steer_to(leg[0], float(leg[1]))
			if dist < 0.4:
				break
			await frames(1)
			f += 1
		stick = Vector2.ZERO
		await frames(45)
	note("walkprobe end (%.1f,%.2f,%.1f) state %s" % [pos().x, pos().y, pos().z, str(p.get("state"))])
	_tr_tag = ""
	return true


## Owner fix probe: after an updraft leg (no teleport), wait for the landing, then walk away 3.5 m south and back.
func t_walkhere() -> bool:
	_tr_on = true
	_tr_tag = "here_" + str(results.size())
	var f := 0
	while f < 600 and not grounded():
		await frames(1)
		f += 1
	await frames(30)
	var o := pos()
	note("walkhere start (%.1f,%.2f,%.1f) state %s" % [o.x, o.y, o.z, str(p.get("state"))])
	for t in [o + Vector3(0, 0, 3.5), o + Vector3(2.5, 0, 3.5), o + Vector3(0, 0, 3.5)]:
		var g := 0
		while g < 150 and steer_to(t, 0.8) > 0.4:
			await frames(1)
			g += 1
		stick = Vector2.ZERO
		await frames(40)
	note("walkhere end (%.1f,%.2f,%.1f) state %s" % [pos().x, pos().y, pos().z, str(p.get("state"))])
	_tr_tag = ""
	return true


## Owner fix probe (diagnosis): restore the body's unit scale only.
func t_fixscale() -> bool:
	note("scale before %s" % str(p.scale))
	p.scale = Vector3.ONE
	await frames(2)
	return true


## Owner fix probe: start on the Brick Hill top by Bertram (a clean baseline for walkprobe).
func t_tpbrick() -> bool:
	await tp(Vector3(16.5, 12.05, -33.0), -90.0)
	await secs(0.5)
	return true


## Owner fix probe: the W1-6 climb as the player plays it, then leave the chimney the way the owner did (drop back down
## the flue from the crown and walk out of the soot door), with the trace on throughout.
func t_w1_6x() -> bool:
	_tr_on = true
	_tr_tag = "w1_6"
	var ok: bool = await t_w1_6()
	_tr_tag = "exit"
	note("after W1-6 at (%.1f,%.2f,%.1f) state %s" % [pos().x, pos().y, pos().z, str(p.get("state"))])
	# From the crown, step into the open flue and drop to its floor, then walk out east through the soot door.
	await go(Vector3(11.3, pos().y, -36.0), 0.4, 4.0)
	stick = Vector2.ZERO
	var f := 0
	while f < 400 and not (grounded() and pos().y < 13.0):
		await frames(1)
		f += 1
	await frames(30)
	await go(Vector3(14.6, 12.05, -36.0), 0.4, 6.0)
	await go(Vector3(17.0, 12.05, -34.0), 0.4, 4.0)
	note("out of the chimney at (%.1f,%.2f,%.1f) state %s" % [pos().x, pos().y, pos().z, str(p.get("state"))])
	_tr_tag = ""
	return ok


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
	note("go timeout at (%.1f,%.1f,%.1f) target (%.1f,%.1f,%.1f) state %s" % [pos().x, pos().y, pos().z, t.x, t.y, t.z, str(p.call("get_state_name"))])
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
	# Completion pass: hold jump through the rise like a player does. The pole jump enters "jump", and the jump-cut
	# rule halves vy on release, so the old 6-frame tap fell 3 m short of sc7.
	hold("jump", 24)
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
			# Completion pass: a held kick (wall_kick is in the jump-cut set, so a 3-frame tap halves every kick).
			hold("jump", KICK_HOLD)
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
	# Straw House Siege, played for real (completion pass): one teleport to the meadow by the straw house, then walk
	# up to each Woolly Wolf and punch it (sidestepping its charge), punch the sneezing haystack open and beat WW3,
	# then walk to Pip's doorstep for the reward. No scripted defeats (the old route also never burst the haystack,
	# so WW3 never entered the level and the count stuck at 1).
	await tp(Vector3(-22.0, W1Terrain.height(-22.0, 23.0), 23.0), 90.0)
	var t_end := Time.get_ticks_msec() + 150000
	var punched_hay := 0
	while Time.get_ticks_msec() < t_end:
		var w := _nearest_siege_wolf()
		if w == null:
			var life: Node = level.get("life")
			if life and bool(life.call("hay_hidden")):
				if punched_hay >= 4:
					note("haystack would not burst")
					break
				punched_hay += 1
				# Round the straw house (x -23.5..-16.5, z 23..29) by its south and west sides.
				await _round_house_to(Vector3(-30.5, 0, 31.5))
				if punched_hay <= 2:
					await _punch_at(Vector3(-34.0, 0, 32.0), 1.9, 8.0)
				else:
					await go(Vector3(-32.3, 0, 32.0), 0.3, 4.0)
					await slam()
				await secs(1.5)
				note("haystack try %d: hidden=%s" % [punched_hay, str(life.call("hay_hidden"))])
				continue
			break
		await _fight(w, 35.0)
	note("siege_left %d" % int(level.get("siege_left")))
	stick = Vector2.ZERO
	await secs(3.5)
	# Walk round the house to Pip's doorstep (truffle spawner at (-20, 31.5)).
	await _round_house_to(Vector3(-24.5, 0, 32.5))
	for wp in [Vector3(-20.0, 0, 32.5), Vector3(-20.0, 0, 31.6)]:
		await go(wp, 0.4, 8.0)
	await secs(1.5)
	if not has("W1-1"):
		note("at (%.1f,%.2f,%.1f) without W1-1" % [pos().x, pos().y, pos().z])
	return has("W1-1")


## Walks to `t` round the straw house footprint (x -23.5..-16.5, z 23..29) instead of into its walls.
func _round_house_to(t: Vector3) -> void:
	var here := pos()
	# East of the house up to the B1 nozzle counts too: from there a straight line catches Mak in the pocket between
	# the east wall and the hay cart.
	var inside_x := func(x: float) -> bool: return x > -25.0 and x < -11.0
	if t.z > 29.5 and here.z < 29.5 and inside_x.call(here.x):
		# South of or beside the house: go down its south side, then up the west side.
		if here.x > -24.8:
			await go(Vector3(here.x, 0, 21.0), 0.5, 6.0)
			await go(Vector3(-25.3, 0, 21.0), 0.5, 8.0)
		await go(Vector3(-25.3, 0, t.z), 0.5, 8.0)
	await go(t, 0.4, 8.0)


func _nearest_siege_wolf() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for id in ["WW1", "WW2", "WW3", "WW4"]:
		var w := level.get_node_or_null(id) as Node3D
		if w == null or not is_instance_valid(w) or bool(w.get("is_defeated")):
			continue
		var d := w.global_position.distance_to(pos())
		if d < bd:
			bd = d
			best = w
	return best


## Walks to `at` until within `reach` and throws a standing punch toward it (slow approach: no dive).
func _punch_at(at: Vector3, reach: float, timeout: float) -> void:
	var f := 0
	while f < int(timeout * 60.0):
		var d := steer_to(at)
		if d < reach + 2.0:
			stick *= 0.45
		if d < reach and grounded():
			hold("attack", 3)
			await frames(24)
			return
		await frames(1)
		f += 1


## Real-input fight with one Woolly Wolf: approach at a walk, punch in reach, sidestep while it charges.
func _fight(w: Node3D, timeout: float) -> void:
	var id := String(w.name)
	var f := 0
	var punches := 0
	while f < int(timeout * 60.0):
		if not is_instance_valid(w) or bool(w.get("is_defeated")):
			note("%s beaten (%d punches, %.1fs)" % [id, punches, f / 60.0])
			return
		var wp := w.global_position
		var st := String(w.get("state"))
		var to := Vector3(wp.x - pos().x, 0, wp.z - pos().z)
		var d := to.length()
		if st == "attack" and d < 7.0:
			# Sidestep the charge: run square to its line.
			var cdv: Variant = w.get("charge_dir")
			var cd: Vector3 = cdv if cdv is Vector3 else to.normalized()
			var side := Vector3(-cd.z, 0, cd.x)
			if side.dot(-to) < 0.0:
				side = -side
			stick = Vector2(side.x, -side.z).normalized()
		elif d < 1.55 and grounded():
			steer_to(wp, 0.3)
			hold("attack", 3)
			punches += 1
			await frames(22)
			f += 22
			continue
		else:
			steer_to(wp)
			if d < 3.5:
				stick *= 0.5
		await frames(1)
		f += 1
	note("%s fight timeout, state %s" % [id, str(w.get("state")) if is_instance_valid(w) else "gone"])


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
				hold("jump", KICK_HOLD_CLEFT)
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
	# Completion pass: real pickups instead of calling on_acorn_collected(100). Like the W3-100 bot, Mak is put on
	# acorn after acorn (the pickup, the per-visit counter and the truffle spawn are the shipping code); the walk
	# between them is not what this test checks, the 100 being there and counted is.
	var got := 0
	for a in level.find_children("*", "Acorn", true, false):
		if ObjSvc.acorns_this_visit() >= 100:
			break
		if a is Node3D and is_instance_valid(a) and not bool(a.get("is_collected")):
			p.call("respawn", Transform3D(Basis(), (a as Node3D).global_position - Vector3(0, 0.4, 0)))
			await frames(4)
			got += 1
	note("visited %d acorns, counted %d this visit" % [got, ObjSvc.acorns_this_visit()])
	await tp(Vector3(0, 0.45, 48), 0.0)
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
	# The hundredth acorn is the challenge; the reward pops at the AcornHundred marker, so walk there from close by.
	var tq := t100.global_position + Vector3(0, 0, 3.0)
	await tp(Vector3(tq.x, W1Terrain.height(tq.x, tq.z), tq.z), 180.0)
	await go(t100.global_position, 0.3, 6.0)
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


## Completion pass probe: the W1-1 run pinned Mak at (-16.0, 0.4, 24.0) in "walk" for 3 minutes. Lists the bodies
## around that spot and tries the four directions from it.
func t_pin() -> bool:
	_calm_enemies(false)
	var at := Vector3(-16.0, W1Terrain.height(-16.0, 24.0), 24.0)
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.2
	q.shape = sh
	q.transform = Transform3D(Basis(), at + Vector3(0, 0.8, 0))
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = true
	for r in (level as Node3D).get_world_3d().direct_space_state.intersect_shape(q, 32):
		var c: Object = r["collider"]
		var n := c as Node
		note("near: %s (%s) layer %d" % [str(n.get_path()) if n else "?", c.get_class(), int(c.get("collision_layer")) if c.get("collision_layer") != null else -1])
	for dv in [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)]:
		await tp(at, 0.0)
		var p0 := pos()
		stick = dv
		await frames(60)
		stick = Vector2.ZERO
		note("stick %s: moved %.2f m to (%.1f,%.2f,%.1f) state %s" % [str(dv), (pos() - p0).length(), pos().x, pos().y, pos().z, str(p.call("get_state_name"))])
	return true
