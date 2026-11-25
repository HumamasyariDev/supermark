extends Node
## W2 fix round 2 (critique round 1 digest, 2026-10-18 11:30-15:30 Bangkok).
## patch_data() edits the level dictionary before anything is built (the JSON copy in res:// stays the plan's):
## puff chain fairness, PUFF07 moved, Pea Pod lanes that can hold a STRIKE, pickups lifted out of collision.
## The node part (setup) adds runtime fairness: a void catch for falls off the castle bank and the Upper Runner
## (Mak lands back on his last safe ground with no heart lost), the Cloud Hopper's last-five-seconds tick, and
## the Leaf Bouncer's soft aim assist.

const VOID_RAY := 75.0

var world: Node3D
var b
var play
var life: Node
var player: CharacterBody3D
var _safe := Vector3.INF
var _safe_yaw := 0.0
var _safe_y := -999.0
var _on_static_t := 0.0
var _catching := false
var _tick_last := -1
var _trial: Node
var _aim_cd := 0.0


static func _set_point(g: Dictionary, i: int, v: Array) -> void:
	var pts: Array = g.get("points", [])
	if i < pts.size():
		pts[i] = v
		if i == 0:
			g["pos"] = v


static func patch_data(d: Dictionary) -> void:
	for p in d.get("platforms", []):
		var id := String(p.get("id", ""))
		match id:
			"PUFF04", "PUFF05", "PUFF06":
				# Puff chain: a readable 0.6 s wobble before a flat puff goes (the object adds the squash tell),
				# back after 3 s.
				p["vanish"] = {"after_touch_s": 0.6, "respawn_s": 3.0}
			"PUFF07":
				# 6.5 m and +1.0 m from PUFF06 (was 8.0 m and +2.0 m): a chained double clears it, the triple through R3
				# is the stylish line, not a gate.
				p["pos"] = [-35.38, 32.5, -5.76]
	for r in d.get("cloud_hopper_rings", []):
		if String(r.get("id", "")) == "R4":
			# Long-jump ring re-centred between the moved PUFF07 and PUFF08.
			r["pos"] = [-31.78, 33.1, -5.16]
			r["facing_rot_y"] = -99.5
	for e in d.get("enemies", []):
		match String(e.get("id", "")):
			# Pea Pod Patrol: lane R1 (z -13.5) holds three pods, R4 (z 1.5) two, so SPARE and STRIKE both exist.
			"E07":
				e["pos"] = [22.2, 24.4, -13.5]
				e["start_mound"] = "PM02"
			"E09":
				e["pos"] = [24.4, 24.4, 1.5]
				e["start_mound"] = "PM10"
	for g in d.get("acorn_groups", []):
		var gid := String(g.get("id", ""))
		var pts: Array = g.get("points", [])
		match gid:
			"A12a":
				g["pos"] = [17.0, 24.0, -11.0]  # inward from the Allotment rim (its acorns scattered into the void)
			"A35":
				_set_point(g, 0, [12.0, 50.6, -17.0])  # above the bank lip, not inside BANK
			"A15":
				var lift := [0.2, 0.3, 0.4, 0.4]
				for i in pts.size():
					pts[i][1] = float(pts[i][1]) + float(lift[mini(i, 3)])
				g["pos"] = pts[0]
			"A38":
				for i in pts.size():
					pts[i][1] = float(pts[i][1]) + (0.6 if i < 2 else 0.7)
				g["pos"] = pts[0]
			"A09":
				if pts.size() >= 5:
					pts[4][1] = float(pts[4][1]) + 0.7
			"A29":
				if pts.size() >= 3:
					pts[2][1] = float(pts[2][1]) + 0.3
			"A30":
				g["pos"] = [g["pos"][0], float(g["pos"][1]) + 0.2, g["pos"][2]]
			"A22":
				g["pos"] = [-40.72, 46.0, -38.21]  # ObjSvc moved the ring by (-0.22, 0, -0.21) out of the islet tree
			"A16":
				# The Cloud Hopper trail follows PUFF07's new spot.
				if pts.size() >= 7:
					pts[6] = [-35.38, 33.1, -5.76]
			"A25":
				# The chase ring now follows the goose's wider oval (centre (12.4, -34), radii 3.9 x 6.8).
				g["shape"] = "POINTS"
				var np: Array = []
				for k in 8:
					var a := TAU * (float(k) + 0.5) / 8.0
					np.append([12.4 + cos(a) * 3.9, 50.55, -34.0 + sin(a) * 6.8])
				g["points"] = np
				g["pos"] = np[0]
	for pg in d.get("pages", []):
		if int(pg.get("index", -1)) == 0:
			pg["pos"] = [pg["pos"][0], float(pg["pos"][1]) + 0.4, pg["pos"][2]]


func setup(w: Node3D, builder, gameplay, life_node: Node) -> void:
	world = w
	b = builder
	play = gameplay
	life = life_node
	if play and play.nodes.has("CloudHopper"):
		_trial = play.nodes["CloudHopper"]
	# Motion pass (visual critic): violet bean-flower petals and leaves drifting down round the stalk.
	var fl := "res://scenes/fx/FallingLeaves.tscn"
	if ResourceLoader.exists(fl):
		for e in [[13.0, Color(0.78, 0.62, 1.0)], [31.0, Color(1, 1, 1)], [49.0, Color(0.85, 0.7, 1.0)]]:
			var fx := (load(fl) as PackedScene).instantiate() as Node3D
			fx.name = "StalkPetals_%d" % int(e[0])
			fx.set("area", Vector3(9.0, 4.0, 9.0))
			fx.set("tint", e[1])
			fx.set("free_when_done", false)
			fx.position = b.stalk_center(float(e[0])) + Vector3(0, float(0), 0)
			world.add_child(fx)
	if world.has_signal("player_spawned"):
		world.connect("player_spawned", func(p: Node3D) -> void:
			player = p as CharacterBody3D
			if player and player.has_signal("jumped"):
				player.connect("jumped", _on_jumped))


func _physics_process(delta: float) -> void:
	_aim_cd = maxf(0.0, _aim_cd - delta)
	if player == null or not is_instance_valid(player) or not player.is_physics_processing():
		return
	_void_catch(delta)
	_trial_tick()
	_lb_home(delta)


## Finishing pass (WORLDS, 2026-10-19; feel critic r1c BLOCKER "0/6 past LB2 with real input"): the one-shot aim at
## take-off ignored air acceleration from the held stick, the H4 crosswind and the pad's own swing, so Mak overshot.
## Now the bounce stays locked on its target pad for the whole arc: every physics frame the horizontal speed is
## re-solved so the landing point meets the pad's predicted position. A neutral stick homes back onto the pad Mak
## bounced from (in-place bounces for the sack kicks); pulling the stick more than 110 degrees away releases it.
var _lb_node: Node3D = null
var _lb_point := Vector3.INF
var _lb_prev := Vector3.INF
var _lb_vel := Vector3.ZERO
var _lb_t := 0.0
var _lb_dbg := OS.get_cmdline_user_args().has("--lb-debug")


func _lb_target_pos() -> Vector3:
	if _lb_node != null and is_instance_valid(_lb_node):
		return _lb_node.global_position
	return _lb_point


func _lb_home(delta: float) -> void:
	if _lb_node == null and _lb_point == Vector3.INF:
		return
	_lb_t += delta
	var tp := _lb_target_pos()
	if _lb_prev != Vector3.INF and delta > 0.0:
		_lb_vel = _lb_vel.lerp((tp - _lb_prev) / delta, 0.5)
	_lb_prev = tp
	var pp := player.global_position
	var st := String(player.call("get_state_name")) if player.has_method("get_state_name") else ""
	if (player.is_on_floor() and _lb_t > 0.15) or _lb_t > 2.5 or st in ["ham_slam", "slam_land", "dive", "ledge_hang", "hurt", "wall_slide"]:
		if _lb_dbg:
			print("[LBH] clear: floor=%s t=%.2f st=%s" % [player.is_on_floor(), _lb_t, st])
		_lb_clear()
		return
	var stick: Variant = player.get("intended_dir")
	var d2 := Vector2(tp.x - pp.x, tp.z - pp.z)
	if stick is Vector3 and (stick as Vector3).length() > 0.5 and d2.length() > 0.6:
		var sd := Vector2((stick as Vector3).x, (stick as Vector3).z).normalized()
		if absf(rad_to_deg(sd.angle_to(d2.normalized()))) > 110.0:
			if _lb_dbg:
				print("[LBH] clear: stick %s away from %s" % [stick, d2])
			_lb_clear()
			return
	var vy := float(player.get("vy")) if player.get("vy") != null else player.velocity.y
	var g := 28.125
	var dh := tp.y - pp.y
	var disc := vy * vy - 2.0 * g * dh
	if disc <= 0.0:
		if _lb_dbg:
			print("[LBH] t=%.2f no solution vy=%.2f dh=%.2f" % [_lb_t, vy, dh])
		return
	var t_land := (vy + sqrt(disc)) / g
	if t_land < 0.04:
		if _lb_dbg:
			print("[LBH] t=%.2f landing now" % _lb_t)
		return
	var aim := tp + Vector3(_lb_vel.x, 0.0, _lb_vel.z) * t_land
	var need := Vector3(aim.x - pp.x, 0.0, aim.z - pp.z) / t_land
	var ext: Variant = player.get("ext_vel")
	if ext is Vector3:
		player.set("ext_vel", Vector3(0.0, 0.0, 0.0))
	var wind: Variant = player.get("wind_vel")
	if wind is Vector3:
		need -= Vector3((wind as Vector3).x, 0.0, (wind as Vector3).z)
	var sp := minf(need.length(), 8.5)
	if sp > 0.05:
		var dir := need.normalized()
		player.set("facing_yaw", atan2(-dir.x, -dir.z))
	player.set("side_speed", 0.0)
	player.set("forward_speed", sp)
	if _lb_dbg:
		print("[LBH] t=%.2f st=%s pp=%s tp=%s tl=%.2f need=%.2f vel=%s" % [_lb_t, st, pp, tp, t_land, sp, player.velocity])


## The first hop from the Upper Cloudbank's west rim onto LB1 (4.6 m, 0.6 m down) gets the same lock when the
## stick points within 35 degrees of LB1.
func _lb_entry(kind: String) -> void:
	if kind == "pole_jump" and b != null:
		_t3_entry()
		return
	if not kind in ["jump", "long_jump", "double_jump", "triple_jump", "side_flip"] or b == null:
		return
	var lb1: Node3D = b.bodies.get("LB1")
	if lb1 == null:
		return
	var pp := player.global_position
	if pp.y < 43.0 or pp.y > 46.5:
		return
	var d2 := Vector2(lb1.global_position.x - pp.x, lb1.global_position.z - pp.z)
	if d2.length() > 8.0 or d2.length() < 2.0:
		return
	# Either the stick or the run-up velocity may point at LB1 (right after a respawn the camera is still turning,
	# so the stick alone missed the lock in 1 of 3 verify attempts).
	var ok := false
	var stick: Variant = player.get("intended_dir")
	if stick is Vector3 and (stick as Vector3).length() >= 0.4:
		var sd := Vector2((stick as Vector3).x, (stick as Vector3).z).normalized()
		ok = absf(rad_to_deg(sd.angle_to(d2.normalized()))) <= 40.0
	var hv := Vector2(player.velocity.x, player.velocity.z)
	if not ok and hv.length() > 2.0:
		ok = absf(rad_to_deg(hv.normalized().angle_to(d2.normalized()))) <= 40.0
	if _lb_dbg:
		print("[LBH] entry %s ok=%s stick=%s hv=%s d=%.2f" % [kind, ok, stick, hv, d2.length()])
	if not ok:
		return
	_lb_clear()
	_lb_node = lb1


## Finishing pass (feel critic r1c major, W2-8 route): the pole jump off the top of vine V3 rose 2.2 m and carried
## 3.9 m with no input, overshooting the tip leaf T3 (1.4 m away, 1.2 m up). A pole jump from V3's top third now
## homes onto T3 with the same lock (pulling the stick away still releases it).
func _t3_entry() -> void:
	var pp := player.global_position
	var t3 := Vector3(-8.6, 62.8, -16.6)
	var t3n: Node3D = b.bodies.get("T3")
	if t3n:
		t3 = t3n.global_position
	if pp.y < 57.5 or pp.y > 63.0 or Vector2(t3.x - pp.x, t3.z - pp.z).length() > 4.0:
		return
	_lb_clear()
	if t3n:
		_lb_node = t3n
	else:
		_lb_point = t3
	if _lb_dbg:
		print("[LBH] T3 lock from %s to %s" % [pp, t3])


func _lb_clear() -> void:
	_lb_node = null
	_lb_point = Vector3.INF
	_lb_prev = Vector3.INF
	_lb_vel = Vector3.ZERO
	_lb_t = 0.0


## Falls off the castle bank, the Upper Runner or the stalk tip used to drop 65 m to kill_y (about 4 s plus a
## heart). Now: while Mak's last safe ground was above y 40 and he is falling with nothing under him (a 75 m ray
## finds no world collision), a cloud catches him and he is set back on that safe ground. The Leaf Bouncer, the
## Cloud Hopper and the bell keep their own catch clouds (they reset to the section start).
func _void_catch(delta: float) -> void:
	var pp := player.global_position
	if player.is_on_floor():
		var fl: Object = null
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			if c.get_normal().y > 0.7:
				fl = c.get_collider()
				break
		if fl is StaticBody3D and not (fl as Node).is_in_group("bouncy"):
			_on_static_t += delta
			if _on_static_t > 0.35:
				_safe = pp
				_safe_y = pp.y
				_safe_yaw = float(player.get("facing_yaw")) if player.get("facing_yaw") != null else 0.0
		else:
			_on_static_t = 0.0
		return
	_on_static_t = 0.0
	if _catching or _safe_y < 40.0 or _safe == Vector3.INF:
		return
	if pp.y > _safe_y - 7.0 or player.velocity.y > -6.0:
		return
	if life and bool(life.get("_sneezing")):
		return
	var lb: AABB = life.get("LB_BOX") if life else AABB()
	if lb.has_point(pp):
		return
	var q := PhysicsRayQueryParameters3D.create(pp, pp + Vector3(0, -VOID_RAY, 0), 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return
	_catching = true
	_fx("CloudPuff", pp)
	_sfx("cloud_poof", pp)
	var to := _safe + Vector3(0, 0.1, 0)
	var xf := Transform3D(Basis(Vector3.UP, _safe_yaw), to)
	if player.has_method("respawn"):
		player.call_deferred("respawn", xf)
	else:
		player.set_deferred("global_transform", xf)
	_toast("A passing cloud catches you and puffs you back up!")
	_fx.call_deferred("CloudPuff", to + Vector3(0, 0.5, 0))
	get_tree().create_timer(0.5, false).timeout.connect(func() -> void: _catching = false)


## Cloud Hopper tension: a tick each second of the last five, a bigger one at the last second.
func _trial_tick() -> void:
	if _trial == null or not is_instance_valid(_trial):
		return
	var lim: Variant = _trial.get("time_limit")
	var el: Variant = _trial.get("elapsed")
	var running: Variant = _trial.get("running")
	if lim == null or el == null:
		return
	if running != null and not bool(running):
		_tick_last = -1
		return
	var left := float(lim) - float(el)
	if left <= 0.0 or left > 5.0 or float(el) <= 0.05:
		if left > 5.0:
			_tick_last = -1
		return
	var s := int(ceil(left))
	if s != _tick_last:
		_tick_last = s
		_sfx("ui_move" if s > 1 else "ui_select")
		var ui := get_node_or_null("/root/UI")
		if ui and ui.has_method("toast") and s == 5:
			ui.toast("Five seconds!")
		var juice := get_node_or_null("/root/Juice")
		if juice and juice.has_method("shake"):
			juice.call("shake", 0.06 if s > 1 else 0.18, 0.15)


## Leaf Bouncer soft aim assist (feel critic): on a pad bounce with the stick within 40 degrees of the next pad,
## Mak's facing and forward speed are set so the 1.09 s bounce arc lands on that pad's current position.
## Full stick control continues in the air.
func _on_jumped(kind: String) -> void:
	if _lb_dbg:
		print("[LBH] jumped %s at %s vel %s" % [kind, player.global_position, player.velocity])
	if kind != "bounce":
		if _lb_node != null or _lb_point != Vector3.INF:
			_lb_clear()
		_lb_entry(kind)
		return
	if _aim_cd > 0.0 or life == null:
		return
	var pp := player.global_position
	var lb: AABB = life.get("LB_BOX")
	if not lb.has_point(pp):
		return
	_lb_clear()
	var pads: Array[Node3D] = []
	for id in ["LB1", "LB2", "LB3", "LB4", "LB5"]:
		var body: Node3D = b.bodies.get(id)
		if body:
			pads.append(body)
	var stick: Variant = player.get("intended_dir")
	if not (stick is Vector3) or (stick as Vector3).length() < 0.3:
		# Neutral stick: bounce in place on the pad underneath (it keeps swinging under Mak).
		for pad in pads:
			if Vector2(pad.global_position.x - pp.x, pad.global_position.z - pp.z).length() < 2.2:
				_lb_node = pad
				break
		return
	var sd := Vector2((stick as Vector3).x, (stick as Vector3).z).normalized()
	if _lb_dbg:
		print("[LBH] bounce stick %s" % [stick])
	var best := Vector3.INF
	var best_d := 1e9
	var best_node: Node3D = null
	var targets: Array[Vector3] = []
	for pad in pads:
		targets.append(pad.global_position)
	targets.append(Vector3(-40.5, 46.0, -36.2))   # the islet's near half
	targets.append(Vector3(-17.0, 44.0, -9.6))    # back onto the Upper Cloudbank rim
	for tp in targets:
		var d2 := Vector2(tp.x - pp.x, tp.z - pp.z)
		var dl := d2.length()
		if dl < 2.0 or dl > 9.5:
			continue
		if rad_to_deg(sd.angle_to(d2 / dl)) > 40.0 or rad_to_deg(sd.angle_to(d2 / dl)) < -40.0:
			continue
		if dl < best_d:
			best_d = dl
			best = tp
	if best == Vector3.INF:
		# No pad ahead within 40 degrees: stay on the pad underneath instead of flying off it.
		for pad in pads:
			if Vector2(pad.global_position.x - pp.x, pad.global_position.z - pp.z).length() < 2.4:
				_lb_node = pad
				break
		return
	for pad in pads:
		if pad.global_position == best:
			best_node = pad
	if best_node:
		_lb_node = best_node
	else:
		_lb_point = best
	if _lb_dbg:
		print("[LBH] bounce target %s node %s" % [best, best_node])
	var vy := player.velocity.y
	var g := 28.125
	# Time to come down to the target's height on this bounce.
	var dh := best.y - pp.y
	var disc := vy * vy - 2.0 * g * dh
	if disc <= 0.0:
		return
	var t_air := (vy + sqrt(disc)) / g
	var need := clampf(best_d / maxf(t_air, 0.3), 2.0, 7.4)
	var dir := Vector2(best.x - pp.x, best.z - pp.z).normalized()
	player.set("facing_yaw", atan2(-dir.x, -dir.y))
	player.set("side_speed", 0.0)
	player.set("forward_speed", need)
	_aim_cd = 0.3


func _toast(text: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.toast(text)


func _sfx(key: String, at := Vector3.INF) -> void:
	var a := get_node_or_null("/root/Audio")
	if a:
		a.play_sfx(key, at)


func _fx(scene: String, pos: Vector3) -> void:
	var path := "res://scenes/fx/%s.tscn" % scene
	if ResourceLoader.exists(path):
		var fx := (load(path) as PackedScene).instantiate() as Node3D
		world.add_child(fx)
		fx.global_position = pos
