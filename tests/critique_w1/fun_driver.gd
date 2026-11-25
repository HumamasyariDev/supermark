extends Node
## Critique W1 round 1 (FUN AND GAME DESIGN lens). A play driver that sits under /root and drives the real MakPlayer
## through its replay input layer, like w1_bot.gd, but plays the way a first-time player would (no script defeats,
## no teleports inside a case unless logged) and measures what a player feels: time per leg, damage taken, attempts,
## how long the camera spends on set pieces. Cases: --w1fun=walk|siege|hay|probe. --w1fun-out=<abs json>.
## Run through FunQA.tscn (it loads W1 after adding this node). Never writes to the world's files.

var p: CharacterBody3D
var inp: Object
var stick := Vector2.ZERO
var level: Node
var game: Node
var rows: Array = []
var _log: Array = []
var _t0 := 0


func _ready() -> void:
	process_physics_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 600:
		await get_tree().process_frame
		p = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if p and get_tree().current_scene and get_tree().current_scene.get_node_or_null("Level"):
			break
	if p == null:
		print("[W1 fun] FAIL no player")
		get_tree().quit()
		return
	await get_tree().create_timer(0.8).timeout
	level = get_tree().current_scene.get_node_or_null("Level")
	game = get_node_or_null("/root/Game")
	inp = p.get("inp")
	inp.call("setup", {"steer": "world", "events": []}, 0.2, 1.0)
	var dev := get_node_or_null("/root/Dev")
	var case_name := String(dev.call("arg", "w1fun", "probe"))
	_t0 = Time.get_ticks_msec()
	var res: Variant = await Callable(self, "c_" + case_name).call()
	var out := String(dev.call("arg", "w1fun-out", ""))
	var doc := {"case": case_name, "utc": Time.get_datetime_string_from_system(true), "result": res, "log": _log, "rows": rows}
	print("[W1 fun] ", JSON.stringify(doc))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(doc, "  "))
	get_tree().paused = false
	get_tree().quit()


func _physics_process(_d: float) -> void:
	if inp:
		inp.set("_r_stick", stick)


func note(s: String) -> void:
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	_log.append("%.1f %s" % [t, s])
	print("[W1 fun] note ", _log[-1])
	var dev := get_node_or_null("/root/Dev")
	var out := String(dev.call("arg", "w1fun-out", "")) if dev else ""
	if out != "":
		var f := FileAccess.open(out.replace(".json", ".partial.json"), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"log": _log}, "  "))


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	while get_tree().paused:
		await get_tree().process_frame


func pos() -> Vector3:
	return p.global_position


func hold(action: String, n: int) -> void:
	var hf: Dictionary = inp.get("_hold_frames")
	hf[action] = n


func steer_to(t: Vector3, mag: float = 1.0) -> float:
	var d := t - p.global_position
	d.y = 0.0
	if d.length() < 0.01:
		stick = Vector2.ZERO
		return 0.0
	stick = Vector2(d.x, -d.z).normalized() * mag
	return d.length()


func go(t: Vector3, tol: float = 0.6, timeout: float = 20.0) -> bool:
	var f := 0
	var last := pos()
	var stuck := 0
	while f < int(timeout * 60.0):
		var dist := steer_to(t)
		if dist < tol:
			stick = Vector2.ZERO
			return true
		# A player hops over small obstacles when stuck.
		if f % 30 == 0:
			if pos().distance_to(last) < 0.4:
				stuck += 1
				hold("jump", 12)
			last = pos()
		await frames(1)
		f += 1
	stick = Vector2.ZERO
	note("go timeout at (%.1f,%.1f,%.1f) target (%.1f,%.1f,%.1f)" % [pos().x, pos().y, pos().z, t.x, t.y, t.z])
	return false


func hp() -> int:
	return int(game.get("health")) if game else -1


func acorns() -> int:
	return int(game.get("acorns")) if game else -1


# ------------------------------------------------------------------ cases

## A first-time player's main route: Page Lane -> green -> Hill Lane -> Brick Hill -> Saddle Lane -> windmill ridge,
## then back down the brick chute. Measures seconds per leg, acorns picked up and damage on the way.
func c_walk() -> Dictionary:
	note("walk start at (%.1f,%.1f,%.1f)" % [pos().x, pos().y, pos().z])
	var legs := [
		["spawn->bridge", [Vector3(-2, 0, 44), Vector3(-5, 0, 34), Vector3(-6, 0, 22), Vector3(-6, 0, 15), Vector3(-6, 0, 5)]],
		["bridge->green", [Vector3(-3, 0, 1), Vector3(1, 0, -2)]],
		["green->plateau (Hill Lane)", [Vector3(-7, 0, -9), Vector3(-13, 0, -14), Vector3(-17, 0, -21), Vector3(-16.5, 0, -28.5), Vector3(-12.5, 0, -35), Vector3(-7, 0, -38), Vector3(-3, 0, -37)]],
		["plateau->ridge (Saddle Lane)", [Vector3(6, 0, -30), Vector3(14, 0, -34), Vector3(18, 0, -37.5), Vector3(22, 0, -40.5), Vector3(26.5, 0, -42.5), Vector3(30, 0, -42), Vector3(40, 0, -37)]],
	]
	var out := {}
	for leg in legs:
		var t0 := Time.get_ticks_msec()
		var a0 := acorns()
		var h0 := hp()
		var ok := true
		for w in leg[1]:
			if not await go(w, 1.0, 25.0):
				ok = false
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		out[leg[0]] = {"ok": ok, "seconds": dt, "acorns": acorns() - a0, "damage": h0 - hp(), "end": [snappedf(pos().x, 0.1), snappedf(pos().y, 0.1), snappedf(pos().z, 0.1)]}
		note("%s ok=%s %.1fs acorns+%d dmg %d" % [leg[0], str(ok), dt, acorns() - a0, h0 - hp()])
	return out


## W1-1 played for real: approach the meadow, let each wolf notice and charge, sidestep the charge and punch it in the
## skid or recover. No script defeats. Logs how long the siege takes, damage taken and hits that landed.
func c_siege() -> Dictionary:
	var ids := ["WW1", "WW2", "WW3", "WW4"]
	var t0 := Time.get_ticks_msec()
	var h_lost := 0
	var last_h := hp()
	var attacks := 0
	var max_f := 60 * 150
	for f in max_f:
		if hp() < last_h:
			h_lost += last_h - hp()
			note("hit taken, cake %d" % hp())
		last_h = hp()
		if game and game.call("has_truffle", "W1-1"):
			break
		var alive: Array = []
		for id in ids:
			var w := level.get_node_or_null(id)
			if w and is_instance_valid(w) and not bool(w.get("is_defeated")):
				alive.append(w)
		if alive.is_empty():
			# Wait for the blow-down and walk to Pip's doorstep for the truffle.
			await go(Vector3(-20, 0, 31.5), 0.4, 12.0)
			await frames(120)
			continue
		alive.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(pos()) < b.global_position.distance_to(pos()))
		var w: Node3D = alive[0]
		var st := String(w.get("state"))
		var d := w.global_position - pos()
		d.y = 0
		if st in ["windup", "attack"] and d.length() < 9.0:
			# Sidestep perpendicular to the wolf's line.
			var side := Vector3(-d.z, 0, d.x).normalized()
			stick = Vector2(side.x, -side.z)
		elif st in ["skid", "recover", "dizzy", "hurt"] or (st in ["idle", "notice", "prowl"] and d.length() < 4.0):
			if d.length() > 1.2:
				steer_to(w.global_position)
			else:
				stick = Vector2.ZERO
				if f % 12 == 0:
					hold("attack", 2)
					attacks += 1
		else:
			if d.length() > 5.0:
				steer_to(w.global_position)
			else:
				stick = Vector2.ZERO
		if f % 300 == 0:
			var states := []
			for id in ids:
				var ww := level.get_node_or_null(id)
				states.append("%s:%s" % [id, String(ww.get("state")) if ww and is_instance_valid(ww) else "gone"])
			note("states " + " ".join(states))
		await frames(1)
	stick = Vector2.ZERO
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	var owned := game != null and bool(game.call("has_truffle", "W1-1"))
	note("siege done owned=%s in %.1fs, cake lost %d, attacks %d" % [str(owned), dt, h_lost, attacks])
	return {"owned": owned, "seconds": dt, "cake_lost": h_lost, "attack_presses": attacks}


## Static facts a player meets, read from the live tree: which W1 truffles are live, which sniff targets exist at the
## spawn, NPC lines, signs, the hay-yard work-order board, the twine crows, the stack contents per round.
func c_probe() -> Dictionary:
	var out := {}
	var tr := []
	for t in get_tree().get_nodes_in_group("truffle"):
		tr.append("%s@(%.0f,%.0f,%.0f) vis=%s" % [String(t.get("truffle_id")), t.global_position.x, t.global_position.y, t.global_position.z, str(t.visible)])
	out["truffles_live"] = tr
	var sn := []
	for s in get_tree().get_nodes_in_group("sniff_target"):
		sn.append("%s@(%.0f,%.0f,%.0f)" % [s.name, s.global_position.x, s.global_position.y, s.global_position.z])
	out["sniff_targets"] = sn
	var npcs := {}
	for n in ["Pip", "Hazel", "Bertram"]:
		var node := level.get_node_or_null(n)
		if node:
			npcs[n] = node.get("lines")
	out["npc_lines"] = npcs
	var signs := []
	for s in level.find_children("*", "", true, false):
		if s.get("board_text") != null:
			signs.append("%s: %s | %s" % [s.name, str(s.get("board_text")), str(s.get("lines"))])
	out["signs"] = signs
	out["SIGN_hayyard_present"] = level.get_node_or_null("SIGN_hayyard") != null
	var en := []
	for e in get_tree().get_nodes_in_group("enemy"):
		en.append("%s %s state=%s notice=%s" % [e.name, e.get_class(), str(e.get("state")), str(e.get("notice_radius"))])
	out["enemies"] = en
	out["enemy_count"] = en.size()
	var acorn_n := get_tree().get_nodes_in_group("acorn").size()
	out["acorns_placed"] = acorn_n
	out["crates"] = get_tree().get_nodes_in_group("breakable_crate").size()
	var hy := level.get_node_or_null("HayYard_W1-7")
	if hy:
		var fm: Node3D = hy.get("foreman")
		var model := fm.get_node_or_null("Model") if fm else null
		var anim := 0
		if model:
			anim = model.find_children("*", "AnimationPlayer", true, false).size()
		out["foreman_model_children"] = model.get_child_count() if model else -1
		out["foreman_animation_players"] = anim
	var pip := level.get_node_or_null("Pip")
	if pip:
		out["pip_animation_players"] = pip.find_children("*", "AnimationPlayer", true, false).size()
	var cams := []
	for c in get_tree().current_scene.get_node("StoryCams").get_children():
		cams.append(c.name)
	out["story_cams"] = cams
	var hints := []
	for h in get_tree().get_nodes_in_group("camera_hint"):
		hints.append(h.name)
	out["camera_hints"] = hints
	note("probe done")
	return out


## W1-7 played as a player who sniffs every round: measures round lengths, how often the slam on the right stack
## actually lands, damage taken in the charges, and whether sniff still solves round 3.
func c_hay() -> Dictionary:
	var hy := level.get_node_or_null("HayYard_W1-7")
	if hy == null:
		return {"error": "no hay yard"}
	var c: Vector3 = hy.get("center")
	await go(Vector3(-31.8, 0, -46.6), 0.5, 10.0)
	await go(Vector3(-35.1, 0, -47.1), 0.5, 6.0)
	await go(c, 0.6, 6.0)
	var t0 := Time.get_ticks_msec()
	var last_state := ""
	var st_t0 := Time.get_ticks_msec()
	var phases: Array = []
	var slam_tries := 0
	var slam_hits := 0
	var h_lost := 0
	var last_h := hp()
	var sniff_in_round: Dictionary = {}
	var sniff_works_r3 := false
	for f in 60 * 240:
		if hp() < last_h:
			h_lost += last_h - hp()
		last_h = hp()
		if game.call("has_truffle", "W1-7") or String(hy.get("state")) == "done":
			break
		var st := String(hy.get("state"))
		if st != last_state:
			phases.append([last_state, snappedf((Time.get_ticks_msec() - st_t0) / 1000.0, 0.1), int(hy.get("round_i")), int(hy.get("hp"))])
			last_state = st
			st_t0 = Time.get_ticks_msec()
		if st == "window":
			var r := int(hy.get("round_i"))
			var i := int(hy.call("foreman_stack"))
			var stacks: Array = hy.get("stacks")
			# Count active sniff targets that point at the Foreman's stack (sniff = full solve?).
			var targets := get_tree().get_nodes_in_group("sniff_target")
			var on_fm := false
			for s in targets:
				if s.get("active") == true and i >= 0 and s.get_parent() == stacks[i]:
					on_fm = true
			sniff_in_round[str(r)] = on_fm
			if r == 2 and on_fm:
				sniff_works_r3 = true
			hold("sniff", 70)
			await frames(70)
			if String(hy.get("state")) != "window":
				continue
			i = int(hy.call("foreman_stack"))
			if i < 0:
				continue
			var sp := (stacks[i] as Node3D).global_position
			# Approach to 1.4 m, then a running double jump with the slam timed at the top of the second jump.
			var from := sp + (pos() - sp).normalized() * 2.6
			await go(Vector3(from.x, 0, from.z), 0.4, 3.0)
			var hp_before := int(hy.get("hp"))
			slam_tries += 1
			steer_to(sp)
			hold("jump", 6)
			await frames(5)
			for k in 60:
				steer_to(sp)
				await frames(1)
				if k > 3 and p.is_on_floor():
					break
			hold("jump", 18)
			for k in 40:
				var dd := steer_to(sp)
				if dd < 0.35:
					stick = Vector2.ZERO
				await frames(1)
				if p.velocity.y < 0.5 and k > 10:
					break
			stick = Vector2.ZERO
			hold("crouch", 6)
			await frames(70)
			if int(hy.get("hp")) < hp_before:
				slam_hits += 1
				note("round %d: slam hit on HS%d" % [r + 1, i + 1])
			else:
				note("round %d: slam missed (feet y %.2f, stack %d)" % [r + 1, pos().y, i + 1])
		elif st in ["charge_windup", "charge"]:
			var fm: Node3D = hy.get("foreman")
			if fm and is_instance_valid(fm):
				var d := pos() - fm.global_position
				d.y = 0
				var side := Vector3(-d.z, 0, d.x).normalized()
				var tgt := pos() + side * 3.0
				if Vector2(tgt.x - c.x, tgt.z - c.z).length() > 5.5:
					tgt = pos() - side * 3.0
				steer_to(tgt)
		else:
			if Vector2(pos().x - c.x, pos().z - c.z).length() > 1.5:
				steer_to(c)
			else:
				stick = Vector2.ZERO
		await frames(1)
	stick = Vector2.ZERO
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	return {"owned": bool(game.call("has_truffle", "W1-7")), "seconds": dt, "slam_tries": slam_tries, "slam_hits": slam_hits,
		"cake_lost": h_lost, "sniff_points_at_foreman_by_round": sniff_in_round, "sniff_solves_round3": sniff_works_r3, "phases": phases}


## R3.4 puff toy, re-check after W1 fix round 2: drop Mak onto B1's plate (logged teleport above the plate, a player
## would hop up from the bale tier), then watch what the one puff does to WW4, the sheep and Pip. Lands twice.
func c_puff() -> Dictionary:
	var bel := level.find_child("Bellows_bellows_B1", true, false) as Node3D
	var ww4 := level.find_child("WW4", true, false) as Node3D
	if bel == null:
		return {"error": "no B1"}
	var out := {"landings": []}
	await go(Vector3(-11.5, 0, 31.0), 0.6, 8.0)
	stick = Vector2.ZERO
	await frames(30)
	for k in 2:
		var w0 := "%s disguised=%s state=%s" % [str(ww4 != null and is_instance_valid(ww4)), str(ww4.get("disguised")) if ww4 and is_instance_valid(ww4) else "-", str(ww4.get("state")) if ww4 and is_instance_valid(ww4) else "-"]
		var top := bel.global_position + Vector3(0, 3.6, 0)
		note("landing %d: teleport above B1 plate at (%.1f,%.1f,%.1f); WW4 %s" % [k + 1, top.x, top.y, top.z, w0])
		p.global_position = top
		p.velocity = Vector3.ZERO
		await frames(150)
		var ww4p := ww4.global_position if ww4 and is_instance_valid(ww4) else Vector3.ZERO
		var w1 := "%s disguised=%s state=%s at (%.1f,%.1f,%.1f)" % [str(ww4 != null and is_instance_valid(ww4)), str(ww4.get("disguised")) if ww4 and is_instance_valid(ww4) else "-", str(ww4.get("state")) if ww4 and is_instance_valid(ww4) else "-", ww4p.x, ww4p.y, ww4p.z]
		note("after landing %d: Mak (%.1f,%.1f,%.1f) WW4 %s cake %d" % [k + 1, pos().x, pos().y, pos().z, w1, hp()])
		out["landings"].append({"before": w0, "after": w1})
		# Step off and wait out the cooldown.
		await go(Vector3(-11.5, 0, 29.0), 0.6, 4.0)
		await frames(240)
	return out
