class_name HubEvents
extends Node3D
## Hub story beats and progress dressing from HUB_amendments.md round 2:
## EV_intro_wolf (the villain on screen in the first 10 s), the colour script (lighting presets by truffle count),
## rescued guests (Pip after W1-1, the Golden Goose after W2-2), the wolf's calling card on the clock, the tea-spill
## long-jump lesson (H-I) and the keyhole eye on the Wolf's Door.

const WOLF_GLB_V1 := "res://assets/characters/wolf_boss/wolf_boss.glb"
## Fix r2: round 5 asset fixes (AO bake, matte cloth; pure path swaps, rig byte-identical) when imported.
var WOLF_GLB := "res://assets/characters/wolf_boss/wolf_boss_v2.glb" if ResourceLoader.exists("res://assets/characters/wolf_boss/wolf_boss_v2.glb") else WOLF_GLB_V1
const PIP_GLB := "res://assets/characters/pip_v2/pip_v2.glb"  # rigged (r1 visual: the static cheer pose read wrong seated)
var GOOSE_GLB := "res://assets/characters/golden_goose/golden_goose_v2.glb" if ResourceLoader.exists("res://assets/characters/golden_goose/golden_goose_v2.glb") else "res://assets/characters/golden_goose/golden_goose.glb"

var level: Node3D
var _wolf: Node3D
var _wolf_skel: Skeleton3D
var _wolf_mesh: MeshInstance3D
var _intro_running := false
var _intro_t := 0.0
var _prev_cam: Camera3D
var _goose: Node3D
var _t := 0.0
var _lj_prompted := false
var _eye: Node3D
var _eye_cd := 0.0
var _own_banner := false
var _flight_cam: Camera3D
var _pip_rig: HubRig
## Fix r2 (fun major): the 7-truffle return played EV_huff_7, the flights and the Book 3 ceremony inside 3.5 s. The
## spiral now waits for this signal so the beats play one after another.
signal ceremonies_done
var ceremonies_busy := false
const BOOK_TITLES := {"W1": ["Book One", "The Three Little Pigs"], "W2": ["Book Two", "Jack and the Beanstalk"],
	"W3": ["Book Three", "Hansel and Gretel"]}


func _ready() -> void:
	_colour_script()
	_guests()
	_calling_card()
	_tea_spill()
	_keyhole_eye()
	# r1 fun: on the first visit the WorldRoot banner ("Jump into a storybook to begin") covered the wolf's line and
	# told the player to do the one thing the impostor is about to block. The hub shows its own banner instead,
	# after the intro. (Children are ready before WorldRoot, so the flag is still read in time.)
	var wr := level.get_parent() if level else null
	var first := _count() == 0
	if first and wr and "show_entry_banner" in wr:
		var was: bool = bool(wr.get("show_entry_banner"))
		wr.set("show_entry_banner", false)
		_own_banner = was
	if _should_play_intro():
		_play_intro.call_deferred()
	else:
		_return_flights.call_deferred()
		if _own_banner:
			_hub_banner.call_deferred(0.6)


func _game() -> Node:
	return get_node_or_null("/root/Game")


func _count() -> int:
	var g := _game()
	return int(g.call("truffle_count")) if g and g.has_method("truffle_count") else 0


func _has(id: String) -> bool:
	var g := _game()
	return g != null and g.has_method("has_truffle") and bool(g.call("has_truffle", id))


func _flag(f: String) -> bool:
	return HubKit.flag(self, f)


func _dev_arg(a: String) -> bool:
	var dev := get_node_or_null("/root/Dev")
	return dev != null and bool(dev.call("has_arg", a))


func _cams() -> Node:
	return get_parent().get_parent().get_node_or_null("StoryCams")


# ------------------------------------------------------------------ R1.7 EV_return_truffle_flight / gate ceremony

## Every truffle won since the last hub visit flies out of its book and into its clock socket (StoryCam_E),
## one after another; the clock chimes. Seen truffles are remembered with Game flags "hub_seen_<id>".
func _return_flights() -> void:
	var g := _game()
	if g == null or not g.has_method("is_unlocked"):
		print("[Hub] return flights: no Game")
		return
	var pending: Array[String] = []
	for id in HubTruffleClock.SOCKET_IDS:
		if _has(id) and not _flag("hub_seen_" + id):
			pending.append(id)
	print("[Hub] EV_return_truffle_flight pending=%s" % str(pending))
	if pending.is_empty():
		return
	ceremonies_busy = true
	_ui_call("clear_barks")
	# r1 fun: the flights played on the wide StoryCam_E (a few pixels each) and Book 2's rope dropped before the cut.
	# The locks now wait; each truffle is followed by a close camera, then each newly opened book gets a short
	# gate ceremony on its own camera.
	level.set("hold_locks", true)
	var prev := get_viewport().get_camera_3d()
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		p.set_physics_process(false)
	_flight_cam = Camera3D.new()
	_flight_cam.name = "FlightCam"
	_flight_cam.fov = 55.0
	level.add_child(_flight_cam)
	await get_tree().create_timer(0.8).timeout
	_flight_cam.make_current()
	for id in pending:
		g.call("unlock", "hub_seen_" + id)
		await _fly_one(id)
	await get_tree().create_timer(0.4).timeout
	var opened: Node3D = await _gate_ceremony()
	level.set("hold_locks", false)
	if prev and is_instance_valid(prev):
		prev.make_current()
	# Fix r1b (fun): hand control back with Mak turned toward the book that just opened, camera snapped behind him.
	if opened and p and "facing_yaw" in p:
		var d := opened.global_position - p.global_position
		d.y = 0.0
		if d.length() > 0.5:
			var yaw := _clear_yaw(p.global_position, atan2(-d.x, -d.z))
			p.set("facing_yaw", yaw)
			p.rotation = Vector3(0.0, yaw, 0.0)
			# The Camera3D is a child of the MakCameraRig, which owns snap_behind.
			var rig: Node = prev
			while rig and not rig.has_method("snap_behind"):
				rig = rig.get_parent()
			if rig == null:
				for n in get_tree().root.find_children("*", "MakCameraRig", true, false):
					rig = n
					break
			if rig:
				rig.call("snap_behind")
	if _flight_cam:
		_flight_cam.queue_free()
		_flight_cam = null
	if p:
		p.set_physics_process(true)
	ceremonies_busy = false
	ceremonies_done.emit()


## Fix r2 (fun major): after the W2 return the snap put Bramwell's head and shell across the lower third of the
## frame. Turn up to 50 degrees off the book so no NPC sits within 1.3 m of the camera boom (5 m behind Mak).
func _clear_yaw(at: Vector3, yaw: float) -> float:
	var npcs: Array[Node3D] = []
	var bram: Node3D = level.get("bramwell") as Node3D
	if bram:
		npcs.append(bram)
	for off in [0.0, 25.0, -25.0, 50.0, -50.0]:
		var y := yaw + deg_to_rad(off)
		var cam := at + Vector3(sin(y), 0.0, cos(y)) * 5.0
		var clear := true
		for n in npcs:
			var q := Geometry3D.get_closest_point_to_segment(n.global_position, at, cam)
			if Vector2(q.x - n.global_position.x, q.z - n.global_position.z).length() < 1.3:
				clear = false
		if clear:
			return y
	return yaw


func _gate_ceremony() -> Node3D:
	var opened: Node3D = null
	var portals: Dictionary = level.get("portals")
	var locks: Dictionary = level.get("_locks")
	for wid in portals.keys():
		var portal: Node3D = portals[wid]
		var lock: Node3D = locks.get(wid)
		if lock == null or not lock.visible or not bool(portal.get("is_open")):
			continue
		var at := portal.global_position + Vector3(0, 2.4, 0)
		var toward := Vector3(0, at.y, 1.0) - at
		toward.y = 0.0
		var camp := at + toward.normalized() * 5.5 + Vector3(0, 1.6, 0)
		_flight_cam.global_position = camp
		_flight_cam.look_at(at, Vector3.UP)
		# Fix r2 (fun major/minor): at least 2.5 s on each book with the rope dropping on camera, and a banner (the
		# toast was a small corner line during the ceremony).
		await get_tree().create_timer(0.7).timeout
		if level.has_method("_drop_lock"):
			level.call("_drop_lock", lock)
		ObjSvc.burst(level, at, Color(1.0, 0.9, 0.55), 40, 5.0, 0.2, -2.0, 1.2)
		var bt: Array = BOOK_TITLES.get(wid, [wid, ""])
		_ui_call("show_banner", ["%s is open!" % bt[0], bt[1], 2.6])
		opened = portal
		# A slow push-in while the rope falls.
		var push := create_tween()
		push.tween_property(_flight_cam, "global_position", camp + (at - camp) * 0.22, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await get_tree().create_timer(2.4).timeout
	return opened


func _fly_one(id: String) -> void:
	var portals: Dictionary = level.get("portals")
	var wid := id.split("-")[0]
	var from := Vector3(0, 3.4, 1.0)
	if portals.has(wid):
		from = (portals[wid] as Node3D).global_position + Vector3(0, 2.6, 0)
	elif wid == "HUB":
		from = HubKit.polar(15.0, 190.0, 10.8)
	var clock: Node = level.get("clock")
	var socket: Node3D = null
	if clock:
		var sockets: Dictionary = clock.get("_sockets")
		socket = sockets.get(id)
	var tr := Node3D.new()
	level.add_child(tr)
	var ps := HubAssets.scene("res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb")
	if ps:
		var v := ps.instantiate() as Node3D
		v.scale = Vector3.ONE * 2.0
		tr.add_child(v)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.35)
	l.light_energy = 2.0
	l.omni_range = 3.0
	tr.add_child(l)
	tr.global_position = from
	ObjSvc.burst(level, from, Color(1.0, 0.9, 0.6), 30, 4.0, 0.2, -3.0, 1.0)
	var dur := 1.8
	var t := 0.0
	var trail := 0.0
	while t < dur:
		var to := socket.global_position if socket else Vector3(0, 2.9, 1.0)
		var k := t / dur
		var p := from.lerp(to, k)
		p.y += sin(k * PI) * 3.0
		tr.global_position = p
		tr.rotation.y += 0.25
		tr.scale = Vector3.ONE * lerpf(1.0, 0.35, k * k)
		trail += get_process_delta_time()
		if trail > 0.07:
			trail = 0.0
			ObjSvc.burst(level, p, Color(1.0, 0.86, 0.4), 4, 0.6, 0.1, 0.0, 0.5)
		if _flight_cam:
			# A two-point move about 6 m from the truffle, drifting toward the clock side.
			var side := (Vector3(0, 0, 1.0) - p)
			side.y = 0.0
			var off := (side.normalized() if side.length() > 0.5 else Vector3.BACK) * 5.0 + Vector3(0, 2.2, 0)
			var want := p + off.rotated(Vector3.UP, 0.5)
			_flight_cam.global_position = _flight_cam.global_position.lerp(want, 0.12) if t > 0.0 else want
			_flight_cam.look_at(p.lerp(to, 0.3), Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()
	if clock and clock.has_method("refresh"):
		clock.call("refresh")
	if socket:
		# The socket flashes gold and pops on a rising chime.
		socket.scale = Vector3.ONE * 0.2
		var sp := create_tween()
		sp.tween_property(socket, "scale", Vector3.ONE * 1.7, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		sp.tween_property(socket, "scale", Vector3.ONE, 0.25)
	var a := get_node_or_null("/root/Audio")
	if a and a.has_method("play_sfx"):
		a.call("play_sfx", "chime", tr.global_position)
	ObjSvc.burst(level, tr.global_position, Color(1.0, 0.85, 0.4), 24, 3.0, 0.16, -2.0, 0.8)
	if _goose:
		var tw := create_tween()
		tw.tween_property(_goose, "position:y", 3.9, 0.15)
		tw.tween_property(_goose, "position:y", 3.4, 0.3)
	tr.queue_free()


# ------------------------------------------------------------------ R2.8 colour script

func _colour_script() -> void:
	var n := _count()
	var boss_done := _has("BOSS-1")
	var sun := get_parent().get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var we := get_parent().get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun == null or we == null:
		return
	var env := we.environment
	var preset := "LP0"
	if boss_done:
		preset = "LP4"
	elif n >= 12:
		preset = "LP3"
	elif n >= 7:
		preset = "LP2"
	elif n >= 3:
		preset = "LP1"
	if _dev_arg("hub-preset"):
		var dev := get_node_or_null("/root/Dev")
		preset = String(dev.call("arg", "hub-preset", preset))
	var specs := {
		# Fix r2 (visual major): the LP0 frames were an orange-red mono-palette; a paler sun and more cool ambient.
		"LP0": [Color("ffd39a"), 14.0, 2.1, Color(0.56, 0.56, 0.7), 0.6],
		"LP1": [Color("ffb066"), 9.0, 2.3, Color("9a9fc4"), 0.48],
		"LP2": [Color("ff8a3d"), 5.0, 1.9, Color("7e7aa8"), 0.42],
		"LP3": [Color("9da8e0"), 25.0, 0.6, Color("5b4c8a"), 0.32],
		"LP4": [Color("fff0d0"), 20.0, 2.0, Color("a9bcd8"), 0.55],
	}
	var sp: Array = specs[preset]
	sun.light_color = sp[0]
	sun.rotation_degrees = Vector3(-float(sp[1]), -75.0, 0.0)
	sun.light_energy = sp[2]
	env.ambient_light_color = sp[3]
	env.ambient_light_energy = sp[4]
	if preset == "LP3":
		env.volumetric_fog_albedo = Color(0.7, 0.72, 0.95)
	if level and level.has_method("set_sky"):
		level.call("set_sky", preset)
	print("[Hub] colour preset %s (truffles %d)" % [preset, n])


# ------------------------------------------------------------------ R2.9 guests

func _guests() -> void:
	if _has("W1-1") or _dev_arg("hub-guests"):
		var ps := HubAssets.scene("res://scenes/objects/NPCTalker.tscn")
		var pip := ps.instantiate() as Node3D
		pip.name = "Guest_Pip"
		pip.set("visual_scene", HubAssets.scene(PIP_GLB))
		pip.set("speaker", "Pip")
		pip.set("talk_radius", 2.0)
		var lines := PackedStringArray(["Cousin Mak! Bramwell says I can stay till my house is put back up. These armchairs are huge!"])
		if _count() >= 7:
			lines.append("I can hear huffing behind that red door. Is that normal for libraries?")
		if _count() >= 12:
			lines.append("Twelve! Go and get him, Mak! I'll mind the biscuits.")
		pip.set("lines", lines)
		pip.position = Vector3(-12.3, 0.45, -3.2)
		pip.rotation_degrees.y = 60.0
		level.add_child(pip)
		var occ: Variant = level.get("_occluders")
		if occ is Array:
			(occ as Array).append({"node": pip, "y": 0.5, "r": 0.5})
		_pose_pip.call_deferred(pip)
	if _has("W2-2") or _dev_arg("hub-guests"):
		_goose = Node3D.new()
		_goose.name = "Guest_Goose"
		_goose.position = Vector3(0, 3.4, 1.0)
		level.add_child(_goose)
		var g := HubAssets.scene(GOOSE_GLB)
		if g:
			var v := g.instantiate() as Node3D
			v.rotation_degrees.y = 0.0
			_goose.add_child(v)


func _pose_pip(pip: Node3D) -> void:
	_pip_rig = HubRig.attach(pip)


## Pip sits in the armchair with the cheer arms lowered (README limit: 60 deg) and the legs forward over the seat.
func _pip_idle(delta: float) -> void:
	if _pip_rig == null:
		return
	var t := _t
	_pip_rig.pose({
		"arm_l": Vector3(-0.25, 0, 1.0), "arm_r": Vector3(-0.25, 0, -1.0),
		"forearm_l": Vector3(-0.3, 0, 0), "forearm_r": Vector3(-0.3 - maxf(0.0, sin(t * 1.3)) * 0.4, 0, 0),
		"leg_l": Vector3(-1.3, 0, 0), "leg_r": Vector3(-1.3, 0, 0), "shin_l": Vector3(1.3, 0, 0), "shin_r": Vector3(1.3, 0, 0),
		"head": Vector3(sin(t * 1.7) * 0.06, sin(t * 0.5) * 0.25, 0),
		"ear_l": Vector3(sin(t * 2.3) * 0.15, 0, 0), "ear_r": Vector3(sin(t * 2.1 + 1.0) * 0.15, 0, 0),
	}, delta, 8.0)


# ------------------------------------------------------------------ R2.6 the wolf's calling card

func _calling_card() -> void:
	var card := Node3D.new()
	card.name = "WolfCallingCard"
	card.position = Vector3(0.42, 3.05, 1.35)
	card.rotation_degrees = Vector3(-12, 18, 8)
	level.add_child(card)
	var b := HubKit.Buf.new()
	HubKit.rounded_box(b, Vector3(0.36, 0.22, 0.01), 0.005, Transform3D())
	HubArchitecture.mi(card, b.commit(), HubArchitecture.flat_toon(Color("f3e6c4"), 0.2, 0.2), "Card")
	var l := Label3D.new()
	l.text = "With compliments,\nSir R. H. III"
	l.font_size = 24
	l.pixel_size = 0.0035
	l.modulate = Color("7a1f2e")
	l.outline_size = 0
	l.position = Vector3(0, 0, 0.007)
	card.add_child(l)


# ------------------------------------------------------------------ R2.2 tea-spill long-jump lesson

func _tea_spill() -> void:
	var b := HubKit.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	for i in 14:
		var z := -0.4 - float(i) * 0.37
		var w := 1.6 * (0.7 + 0.3 * sin(float(i) * 1.7))
		HubKit.rounded_box(b, Vector3(w, 0.004, 0.55), 0.002, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(-8.4 + rng.randf_range(-0.15, 0.15), 0.018, z)))
	var m := StandardMaterial3D.new()
	# r1 visual round 2: the glossy spill mirrored the room and read as grey-blue tiles; a warm tea gloss instead.
	m.albedo_color = Color(0.55, 0.3, 0.11, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.3
	m.metallic_specular = 0.45
	HubArchitecture.mi(level, b.commit(), m, "DEC_tea_spill", Transform3D.IDENTITY, false)
	var holder := Node3D.new()
	holder.name = "AG14_tea_spill_arc"
	level.add_child(holder)
	# r1 fun: the arc sat low enough to walk under. It now follows a long jump's flat arc (1.75-2.15 m), starting
	# 1.2 m past the spill's edge, so walking and standing jumps miss it. One-off ledger acorns.
	var arc := [Vector3(-8.4, 1.75, -1.6), Vector3(-8.4, 2.0, -2.6), Vector3(-8.4, 2.15, -3.6), Vector3(-8.4, 2.15, -4.6), Vector3(-8.4, 2.0, -5.6)]
	for i in arc.size():
		level.call("ledger_acorn", holder, "AG14_tea_spill_arc", i, arc[i])
	# PROMPT_long_jump trigger.
	var area := Area3D.new()
	area.name = "PROMPT_long_jump"
	area.collision_layer = 1 << 7
	area.collision_mask = 1 << 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.6, 2.0, 2.6)
	cs.shape = bx
	area.add_child(cs)
	area.position = Vector3(-8.4, 1.0, 1.7)
	level.add_child(area)
	area.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("player") and not _lj_prompted and not _flag("hub_long_jump_done"):
			_lj_prompted = true
			var ui := get_node_or_null("/root/UI")
			if ui and ui.has_method("toast"):
				ui.call("toast", "Run, crouch, jump: long jump!")
			var bram: Node3D = level.get("bramwell") as Node3D
			if bram and level.has_method("_bubble_on"):
				level.call("_bubble_on", bram, "Do leap the spill, sir: long and low.", 3.0))
	area.body_exited.connect(func(_b: Node) -> void: _lj_prompted = false)
	# The lesson completes on any long jump in the lane (r1 fun: hub_long_jump_done was never set, so the toast
	# and Bramwell's line fired on every entry forever).
	_connect_long_jump.call_deferred()


func _connect_long_jump() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not p.has_signal("jumped"):
		return
	p.connect("jumped", func(kind: String) -> void:
		if kind != "long_jump" or _flag("hub_long_jump_done"):
			return
		var pp := (p as Node3D).global_position
		if pp.x > -10.0 and pp.x < -6.8 and pp.z > -6.0 and pp.z < 3.4:
			var g := _game()
			if g and g.has_method("unlock"):
				g.call("unlock", "hub_long_jump_done")
			var ui := get_node_or_null("/root/UI")
			if ui and ui.has_method("toast"):
				ui.call("toast", "Long and low. Splendid!"))


# ------------------------------------------------------------------ EV_keyhole_eye

func _keyhole_eye() -> void:
	var door: Node3D = level.get("wolf_door") as Node3D
	if door == null:
		return
	# A real model behind the keyhole: the wolf's own head, lit by a small light, peeking through the door.
	_eye = Node3D.new()
	_eye.name = "KeyholeEye"
	_eye.position = Vector3(0.02, 4.5 + 1.0, -16.35)
	_eye.visible = false
	level.add_child(_eye)
	var ws := HubAssets.scene(WOLF_GLB)
	if ws:
		var w := ws.instantiate() as Node3D
		w.scale = Vector3.ONE * 0.6
		w.position = Vector3(0, -1.55, -0.3)
		_eye.add_child(w)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 2.0
	l.omni_range = 1.5
	l.position = Vector3(0, 0.0, 0.3)
	_eye.add_child(l)
	if door.has_signal("opened"):
		pass


## Shows the wolf's eye in the keyhole for `secs` (EV_huff_7 in hub_spiral.gd).
func peek_eye(secs: float) -> void:
	if _eye == null:
		return
	_eye.visible = true
	_eye_cd = maxf(_eye_cd, secs + 1.0)
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(func() -> void: _eye.visible = false)


func _process(delta: float) -> void:
	_t += delta
	_eye_cd = maxf(0.0, _eye_cd - delta)
	if _goose:
		_goose.rotation.y = sin(_t * 0.6) * 0.4
		_goose.position.y = 3.4 + absf(sin(_t * 1.1)) * 0.02
	if _intro_running:
		_intro_step(delta)
	_pip_idle(delta)
	_keyhole_check()


func _keyhole_check() -> void:
	if _eye == null or _eye_cd > 0.0:
		return
	var door: Node3D = level.get("wolf_door") as Node3D
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if door == null or p == null or bool(door.get("is_unlocked")):
		return
	if p.global_position.distance_to(door.global_position + Vector3(0, 0, 0.8)) < 1.6:
		_eye_cd = 20.0
		_eye.visible = true
		var tw := create_tween()
		tw.tween_interval(2.0)
		tw.tween_callback(func() -> void: _eye.visible = false)
		if level.has_method("_bubble_on"):
			level.call("_bubble_on", door, "Twelve, piglet. I counted.", 2.4)


# ------------------------------------------------------------------ R2.7 EV_intro_wolf

func _hub_banner(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	var ui := get_node_or_null("/root/UI")
	if ui == null or not ui.has_method("show_banner"):
		return
	if not _flag("hub_cub_done"):
		ui.call("show_banner", "The Grand Library", "Something is odd about Book One...", 4.4)
	else:
		ui.call("show_banner", "The Grand Library", "Jump into a storybook to begin", 4.4)


func _ui_call(m: String, args: Array = []) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method(m):
		ui.callv(m, args)


func _should_play_intro() -> bool:
	if _dev_arg("hub-intro"):
		return true
	# Never behind the title logo (UI r1 blocker; core also sets a transient hub_intro_seen while it builds the
	# backdrop): the title marks the hub root with the meta "title_backdrop".
	var root := level.get_parent() if level else null
	if root and (root.has_meta("title_backdrop") or root.is_in_group("title_backdrop")):
		return false
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("is_test_run") and bool(dev.call("is_test_run")):
		return false
	if _dev_arg("hub-test") or _dev_arg("hub-seq") or _dev_arg("spawn"):
		return false
	return not _flag("hub_intro_seen") and _count() == 0


func _play_intro() -> void:
	var g := _game()
	if g and g.has_method("unlock"):
		g.call("unlock", "hub_intro_seen")
	_intro_running = true
	_intro_t = 0.0
	_prev_cam = get_viewport().get_camera_3d()
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		if p.has_method("respawn"):
			p.call("respawn", Transform3D(Basis(), Vector3(-0.4, 0, 9.0)))
		p.set_physics_process(false)
	_wolf = Node3D.new()
	_wolf.name = "IntroWolf"
	_wolf.position = Vector3(0, 4.5, -13.4)
	level.add_child(_wolf)
	var ws := HubAssets.scene(WOLF_GLB)
	if ws:
		var v := ws.instantiate() as Node3D
		v.rotation_degrees.y = 0.0  # glTF +Z faces south, toward the hall
		_wolf.add_child(v)
		_wolf_skel = v.find_child("*", true, false) as Skeleton3D
		for n in v.find_children("*", "Skeleton3D", true, false):
			_wolf_skel = n as Skeleton3D
		for n in v.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh and mi.mesh.get_blend_shape_count() > 0:
				_wolf_mesh = mi
	_cut("StoryCam_A_v3")
	_ui_call("set_hud_visible", [false])
	print("[Hub] EV_intro_wolf start")


func _cut(cam_name: String) -> void:
	var c := _cams()
	if c == null:
		return
	var cam := c.get_node_or_null(cam_name) as Camera3D
	if cam:
		cam.make_current()


func _blend(shape: String, v: float) -> void:
	if _wolf_mesh == null:
		return
	var idx := _wolf_mesh.find_blend_shape_by_name(shape)
	if idx >= 0:
		_wolf_mesh.set_blend_shape_value(idx, v)


func _bone_rot(bone: String, euler: Vector3) -> void:
	if _wolf_skel == null:
		return
	var i := _wolf_skel.find_bone(bone)
	if i >= 0:
		_wolf_skel.set_bone_pose_rotation(i, _wolf_skel.get_bone_rest(i).basis.get_rotation_quaternion() * Quaternion.from_euler(euler))


func _intro_step(delta: float) -> void:
	var t0 := _intro_t
	_intro_t += delta
	var t := _intro_t
	if Input.is_action_just_pressed("jump") and t > 1.0:
		t = 99.0
	if t0 < 2.5 and t >= 2.5:
		_cut("StoryCam_J")
		var ui := get_node_or_null("/root/UI")
		if ui and ui.has_method("bark"):
			ui.call("bark", _wolf, "Twelve truffles, piglet, and my door is yours. Ta-ta.", 3.0, {"height": 3.6})
		elif level.has_method("_bubble_on"):
			level.call("_bubble_on", _wolf, "Twelve truffles, piglet, and my door is yours. Ta-ta.", 3.0, 3.6)
	if t >= 2.5 and t < 5.5:
		var k := t - 2.5
		# Bow with the cane (0-1.2 s), inhale (1.2-2.2 s), huff (2.2-3.0 s).
		_bone_rot("spine_2", Vector3(clampf(sin(clampf(k / 1.2, 0.0, 1.0) * PI) * 0.6, 0.0, 0.6), 0, 0))
		_blend("chest_inflate", clampf((k - 1.2) / 1.0, 0.0, 1.0) * (1.0 if k < 2.3 else maxf(0.0, 1.0 - (k - 2.3) * 3.0)))
		_blend("cheeks_puff", 1.0 if k > 2.1 and k < 2.8 else 0.0)
		if t0 < 4.7 and t >= 4.7:
			ObjSvc.burst(level, Vector3(0, 6.0, -11.5), Color(1.0, 0.97, 0.9), 40, 9.0, 0.22, 0.0, 1.2)
			var a := get_node_or_null("/root/Audio")
			if a and a.has_method("play_sfx"):
				a.call("play_sfx", "wolf_huff", Vector3(0, 6, -12))
	if t0 < 5.5 and t >= 5.5:
		_cut("StoryCam_I")
		_blend("chest_inflate", 0.0)
		_blend("cheeks_puff", 0.0)
		_bone_rot("spine_2", Vector3.ZERO)
		_wolf.rotation_degrees.y = 180.0
	if t >= 5.5 and t < 7.0 and _wolf and _wolf.visible:
		_wolf.position.z = lerpf(-13.4, -15.0, clampf((t - 5.5) / 1.2, 0.0, 1.0))
		_wolf.position.y = 4.5 + absf(sin(t * 7.0)) * 0.06
		_bone_rot("spine_2", Vector3(0.15, 0, sin(t * 7.0) * 0.06))
	if t0 < 6.8 and t >= 6.8 and _wolf:
		# He bows out at the door in a puff of torn pages (r1 fun: he used to slide through the closed door).
		ObjSvc.burst(level, _wolf.global_position + Vector3(0, 1.4, 0), Color(0.95, 0.9, 0.8), 36, 4.0, 0.2, -2.0, 1.0)
		_wolf.visible = false
	if t0 < 7.0 and t >= 7.0 and _wolf:
		var a2 := get_node_or_null("/root/Audio")
		if a2 and a2.has_method("play_sfx"):
			a2.call("play_sfx", "door_slam", Vector3(0, 6, -15.8))
	if t0 < 7.5 and t >= 7.5:
		_cut("StoryCam_A_v3")
	if t >= 9.5:
		_end_intro()


func _end_intro() -> void:
	_intro_running = false
	if _wolf:
		_wolf.queue_free()
		_wolf = null
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		p.set_physics_process(true)
	_ui_call("set_hud_visible", [true])
	if _own_banner:
		_hub_banner(0.3)
	print("[Hub] EV_intro_wolf end")
