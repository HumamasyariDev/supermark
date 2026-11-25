class_name HubSpiral
extends Node3D
## H-G "The Huffed Catalogue" (HUB_amendments R2.5 + R3.4), post-7 set-piece: ten books hover in a spiral from the
## east gallery up to the chandelier rim. SP01/SP03/SP04/SP10 static bobbers, SP02/SP09 wing books (open 2.0 s,
## tilt 35 degrees outward 1.0 s, period 3 s), SP05-SP07 fallers (drop 0.5 s after landing, back after 4 s),
## SP08 Grand Atlas spinning 45 deg/s, A31 rim band at y 9.1. Built only at 7+ truffles or with --unlock-all.
## Fix round 1: EV_huff_7 (the books fly up into place on the first 7+ visit), the dome target on the clock top and
## EV_grand_bong (slam the clock from the rim: chimes, StoryCam_H, the monocle). The owl hand-off still waits for CH-04.

const BOOKS := [
	# id, kind, top centre, size (radial, thick, tangent), cover colour, wing phase
	# r1 feel round 2: covers grew (1.6-1.8 x 2.3 -> 1.9-2.0 x 2.5, centres unchanged) so a jog or a standing hop
	# lands mid-cover and a full-run jump lands on the cover after; the tightest corner gap is still 0.41 m.
	# Fix r1b: tangent depth 2.5 -> 2.7 (edge gaps now 0.6-1.4 m) so a jogging hop from the front edge lands on the
	# back third instead of past it.
	["SP01", "static", Vector3(6.56, 5.0, -7.81), Vector3(2.1, 0.35, 2.7), Color("8c2f39"), 0.0],
	["SP02", "wing", Vector3(7.16, 5.4, -4.25), Vector3(2.1, 0.35, 2.7), Color("2f5d8c"), 0.0],
	["SP03", "static", Vector3(6.89, 5.8, -0.68), Vector3(2.1, 0.35, 2.7), Color("3e7a3a"), 0.0],
	["SP04", "static", Vector3(5.81, 6.1, 2.67), Vector3(2.1, 0.35, 2.7), Color("7a4a8c"), 0.0],
	["SP05", "falling", Vector3(3.43, 6.2, 5.10), Vector3(2.0, 0.35, 2.7), Color("b8733a"), 0.0],
	["SP06", "falling", Vector3(0.22, 6.3, 5.92), Vector3(2.0, 0.35, 2.7), Color("c9a04a"), 0.0],
	["SP07", "falling", Vector3(-2.91, 6.4, 4.87), Vector3(2.0, 0.35, 2.7), Color("8c2f39"), 0.0],
	["SP08", "rotating", Vector3(-4.99, 6.5, 2.04), Vector3(2.7, 0.3, 2.7), Color("2e6b6b"), 0.0],
	["SP09", "wing", Vector3(-4.89, 6.5, -1.46), Vector3(2.0, 0.35, 1.8), Color("5a3420"), 1.5],
	["SP10", "static", Vector3(-2.62, 6.2, -4.26), Vector3(2.2, 0.6, 2.2), Color("3b2416"), 0.0],
]
## r1 fun/feel round 2: per-faller delay from the first grounded frame (a ramp: the first faller is the gentlest).
const FALL_DELAYS := {"SP05": 0.75, "SP06": 0.6, "SP07": 0.6}
const WING_PERIOD := 3.0
const WING_OPEN := 2.0
const FALL_DELAY := 0.7  # r1 feel: starts on the first grounded frame on the cover (was 0.5 s from a feet area 0.4 m up)
const FALL_RESPAWN := 4.0
const ATLAS_SPEED := 45.0
const RIM_Y := 9.1
const WING_TILT := 55.0  # r1 feel: 35 deg was under steep_slope_angle, so a standing Mak never slid off
const CLOCK_TOP := Vector3(0.0, 3.4, 1.0)  # the glass dome crown (hub_clock.gd now gives it a collision top)

var level: Node3D
var _t := 0.0
var _books: Array = []  # dictionaries: {id, kind, body, base, yaw, outward, phase, state, timer}
var _rim_done := false
var _player: CharacterBody3D
var _rise := 1.0  # EV_huff_7: the books fly up into place (0 -> 1)
var _bong_done := false
var _target: Node3D
var _rim_zone: Area3D


static func wanted(lvl: Node) -> bool:
	var dev := lvl.get_node_or_null("/root/Dev")
	if dev and bool(dev.call("has_arg", "unlock-all")):
		return true
	var game := lvl.get_node_or_null("/root/Game")
	return game != null and game.has_method("truffle_count") and int(game.call("truffle_count")) >= 7


func _ready() -> void:
	name = "HG_Catalogue_Spiral"
	for spec in BOOKS:
		_book(spec)
	_rim()
	var holder := Node3D.new()
	holder.name = "AG16_spiral"
	add_child(holder)
	var i := 0
	for spec in BOOKS:
		# One-off ledger acorns (R3.6): the spiral counts toward the Library Ledger.
		if level and level.has_method("ledger_acorn"):
			level.call("ledger_acorn", holder, "AG16_spiral", i, (spec[2] as Vector3) + Vector3(0, 0.8, 0))
		i += 1
	_bong_done = HubKit.flag(self, "hat_monocle") or HubKit.flag(self, "hub_spiral_done")
	_rim_done = HubKit.flag(self, "hub_rim_reached") or _bong_done
	_dome_target()
	_camera_zones()
	_page_spring(HubKit.polar(4.55, 115.0, 0.0), "HG_page_spring")
	# Fix r1b (feel M5): a second spring in the gap under SP06-SP07, so a miss on the fallers is also a 3 s retry.
	_page_spring(Vector3(-1.35, 0.0, 5.45), "HG_page_spring_b")
	_connect_player.call_deferred()
	# R3.3: after the huff and before the Grand Bong the orrery stands still ("something is wrong").
	var clk: Node = level.get("clock") if level else null
	if clk and clk.has_method("freeze") and not _bong_done and (HubKit.flag(self, "hub_huff7_seen") or HubKit.flag(self, "hub_rim_reached")):
		clk.call("freeze")
	var dev := get_node_or_null("/root/Dev")
	var test_run := dev != null and dev.has_method("is_test_run") and bool(dev.call("is_test_run"))
	# Route tests start on the books, so the huff (books flying up from below) is skipped for them too.
	test_run = test_run or (dev != null and (bool(dev.call("has_arg", "hub-test")) or bool(dev.call("has_arg", "hub-seq"))))
	if (not HubKit.flag(self, "hub_huff7_seen") and not test_run) or (dev and bool(dev.call("has_arg", "hub-huff7"))):
		_huff_7.call_deferred()
	print("[Hub] H-G catalogue spiral built (%d books)" % _books.size())


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player and _player.has_signal("ground_pounded"):
		_player.connect("ground_pounded", _on_slam)


func _story_cam(cam_name: String, secs: float) -> void:
	var cams := get_parent().get_parent().get_node_or_null("StoryCams") if get_parent() else null
	var cam := cams.get_node_or_null(cam_name) as Camera3D if cams else null
	if cam == null:
		return
	var prev := get_viewport().get_camera_3d()
	cam.make_current()
	await get_tree().create_timer(secs).timeout
	if prev and is_instance_valid(prev):
		prev.make_current()


func _sfx(key: String, at: Vector3) -> void:
	var a := get_node_or_null("/root/Audio")
	if a and a.has_method("play_sfx"):
		a.call("play_sfx", key, at)


## EV_huff_7 (R3.3): a huff from behind the Wolf's Door blows the catalogue off the shelves; the books swirl up
## into the spiral. Fix r2 (fun major): it waits for the return flights and gate ceremonies to finish, then plays as
## its own 5.6 s beat: a close shot of the Wolf's Door rattling with the eye glowing in the keyhole (1.9 s), the huff
## and a gust of pages across the hall, then StoryCam_H holding while the books rise (3.7 s). Mak is held meanwhile.
func _huff_7() -> void:
	_rise = 0.0
	await get_tree().process_frame
	var ev: Node = level.get_node_or_null("Events") if level else null
	if ev and bool(ev.get("ceremonies_busy")):
		await ev.ceremonies_done
	await get_tree().create_timer(0.6).timeout
	var g := get_node_or_null("/root/Game")
	var dev := get_node_or_null("/root/Dev")
	if g and g.has_method("unlock") and not (dev and dev.has_method("is_test_run") and bool(dev.call("is_test_run"))):
		g.call("unlock", "hub_huff7_seen")
	print("[Hub] EV_huff_7")
	var clk: Node = level.get("clock") if level else null
	if clk and clk.has_method("freeze") and not _bong_done:
		clk.call("freeze")
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("clear_barks"):
		ui.call("clear_barks")
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		p.set_physics_process(false)
	var prev := get_viewport().get_camera_3d()
	# Beat 1: the door.
	var dcam := Camera3D.new()
	dcam.name = "HuffDoorCam"
	dcam.fov = 50.0
	level.add_child(dcam)
	dcam.global_position = Vector3(0.6, 5.0, -9.4)
	dcam.look_at(Vector3(0.0, 5.4, -15.9), Vector3.UP)
	dcam.make_current()
	var door: Node3D = level.get("wolf_door") as Node3D if level else null
	if ev and ev.has_method("peek_eye"):
		ev.call("peek_eye", 1.9)
	_sfx("wolf_growl", Vector3(0, 5.0, -15.5))
	var base_door := door.position if door else Vector3.ZERO
	var t := 0.0
	while t < 1.9:
		if door:
			var k := clampf(t / 1.2, 0.0, 1.0)
			door.position = base_door + Vector3(sin(t * 55.0) * 0.03 * k, 0, sin(t * 41.0) * 0.02 * k)
		if t > 1.1:
			dcam.global_position = Vector3(0.6, 5.0, -9.4) + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.04
		await get_tree().process_frame
		t += get_process_delta_time()
	if door:
		door.position = base_door
	_sfx("wolf_huff", Vector3(0, 6.0, -14.0))
	ObjSvc.burst(self, Vector3(0, 6.0, -14.6), Color(0.96, 0.92, 0.82), 60, 10.0, 0.24, -1.0, 1.6)
	# Beat 2: the gust crosses the hall and the books rise into the spiral.
	var hcam: Camera3D = null
	var cams := level.get_parent().get_node_or_null("StoryCams") if level and level.get_parent() else null
	if cams:
		hcam = cams.get_node_or_null("StoryCam_H") as Camera3D
	if hcam:
		hcam.make_current()
	dcam.queue_free()
	for k in 5:
		ObjSvc.burst(self, Vector3(0, 5.5, -12.0 + 4.5 * float(k)), Color(0.97, 0.93, 0.84), 14, 6.0, 0.16, 0.5, 1.0)
	for d in _books:
		var b: Node3D = d["body"]
		ObjSvc.burst(self, (d["base"] as Vector3) + Vector3(0, -6.0, 0), Color(0.95, 0.88, 0.7), 8, 3.0, 0.15, -2.0, 0.8)
		b.rotation_degrees.z = 0.0
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(self, "_rise", 1.0, 2.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(3.7).timeout
	if prev and is_instance_valid(prev):
		prev.make_current()
	if p and is_instance_valid(p):
		p.set_physics_process(true)
	if ui and ui.has_method("show_banner"):
		ui.call("show_banner", "The Huffed Catalogue", "Climb the flying books to the chandelier!", 3.0)


## DEC_dome_target: a gold ring on the clock top that lights once the rim is reached (where the slam goes).
func _dome_target() -> void:
	_target = Node3D.new()
	_target.name = "DEC_dome_target"
	_target.position = CLOCK_TOP + Vector3(0, 0.03, 0)
	add_child(_target)
	var b := HubKit.Buf.new()
	HubKit.lathe(b, HubKit.round_rect_profile(0.55, 0.75, 0.0, 0.04, 0.0, 0.0, 0.02, 0.02), 0.0, 360.0, 10.0, true, false)
	HubKit.lathe(b, HubKit.round_rect_profile(0.0, 0.22, 0.0, 0.04, 0.0, 0.0, 0.02, 0.02), 0.0, 360.0, 15.0, true, false)
	HubArchitecture.mi(_target, b.commit(), HubKit.emissive(Color(1.0, 0.82, 0.35), 2.5, "dome_target"), "Ring", Transform3D.IDENTITY, false)
	_target.visible = _rim_done and not _bong_done


func _process(_delta: float) -> void:
	if _target and _target.visible:
		_target.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 5.0))
		_target.rotation.y += 0.02


## EV_grand_bong (R3.3): a slam on the clock top after reaching the rim rings the clock, spins the orrery,
## and pays out the monocle (Tier A reward).
func _on_slam(at: Vector3) -> void:
	if not wants_slam():
		return
	# Dome crown, column or drum top: anything on the clock counts once the rim is reached (R3.3 miss recovery:
	# a slam that falls short onto the drum still rings it; no second climb is ever needed).
	if Vector2(at.x - CLOCK_TOP.x, at.z - CLOCK_TOP.z).length() > 1.75 or at.y < 0.8 or at.y > CLOCK_TOP.y + 0.6:
		return
	_bong_done = true
	print("[Hub] EV_grand_bong")
	var g := get_node_or_null("/root/Game")
	var dev := get_node_or_null("/root/Dev")
	if g and g.has_method("unlock") and not (dev and dev.has_method("is_test_run") and bool(dev.call("is_test_run"))):
		g.call("unlock", "hat_monocle")
		g.call("unlock", "hub_bong_done")
		g.call("unlock", "hub_spiral_done")
	if _target:
		_target.visible = false
	# Fix r2 (fun major): StoryCam_H framed the payoff from the floor with Mak 40 px tall and two barks on screen.
	# Two shots now: 0.8 s close on the dome impact (shake, shockwave ring), then 2.2 s medium on the orrery spinning
	# with the sockets lighting in sequence, Mak on the dome in frame. Barks are cleared for the event.
	_bong_shots()
	if ResourceLoader.exists("res://scenes/fx/SlamShockwave.tscn"):
		FxEffect.spawn(self, "res://scenes/fx/SlamShockwave.tscn", CLOCK_TOP + Vector3(0, 0.05, 0))
	_sfx("chime", CLOCK_TOP)
	var clock: Node = level.get("clock") if level else null
	if clock and clock.has_method("spin_up"):
		clock.call("spin_up")
	# The filled sockets chime up a scale in order.
	var sockets: Array = []
	if clock:
		var sd: Dictionary = clock.get("_sockets")
		for id in sd.keys():
			if (sd[id] as Node3D).visible:
				sockets.append(sd[id])
	for k in sockets.size():
		var sock: Node3D = sockets[k]
		var tw := create_tween()
		tw.tween_interval(0.35 + 0.12 * float(k))
		tw.tween_callback(func() -> void:
			var a := get_node_or_null("/root/Audio")
			if a and a.has_method("play_sfx"):
				a.call("play_sfx", "chime", sock.global_position, 0.0)
			sock.scale = Vector3.ONE * 1.6
			create_tween().tween_property(sock, "scale", Vector3.ONE, 0.25))
	for k in 3:
		var tw2 := create_tween()
		tw2.tween_interval(0.45 * float(k))
		tw2.tween_callback(func() -> void:
			ObjSvc.burst(self, CLOCK_TOP + Vector3(0, 0.4, 0), Color(1.0, 0.85, 0.4), 30, 5.0, 0.2, -3.0, 1.0))
	if ResourceLoader.exists("res://scenes/fx/Confetti.tscn"):
		FxEffect.spawn(self, "res://scenes/fx/Confetti.tscn", CLOCK_TOP + Vector3(0, 0.8, 0))
	# The goose (when it lives on the dome) is blown off its nest in a feather puff and flaps back.
	var ev := level.get_node_or_null("Events") if level else null
	var goose: Node3D = ev.get("_goose") as Node3D if ev else null
	if goose:
		var y0 := goose.position.y
		ObjSvc.burst(self, goose.global_position + Vector3(0, 0.4, 0), Color(1.0, 0.97, 0.9), 26, 3.5, 0.14, -2.0, 1.4)
		var gt := create_tween()
		gt.tween_property(goose, "position:y", y0 + 2.2, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		gt.parallel().tween_property(goose, "rotation:y", goose.rotation.y + TAU, 0.9)
		gt.tween_property(goose, "position:y", y0, 2.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_monocle_drop()
	if level and level.has_method("dome_bong_acorns"):
		level.call("dome_bong_acorns")
	if level and level.has_method("_bubble_on"):
		var bram: Node3D = level.get("bramwell") as Node3D
		if bram:
			var bt := create_tween()
			bt.tween_interval(3.1)
			bt.tween_callback(func() -> void:
				level.call("_bubble_on", bram, "The clock is ticking again, sir! And Grandfather's monocle. I took the liberty of oiling it in 1974.", 4.5))
	if _rim_zone:
		var tz := create_tween()
		tz.tween_interval(2.0)
		tz.tween_callback(func() -> void: _rim_zone.set_deferred("monitorable", false))


func _bong_shots() -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("clear_barks"):
		ui.call("clear_barks")
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "BongCam"
	cam.fov = 48.0
	level.add_child(cam)
	var c1 := CLOCK_TOP + Vector3(1.9, 0.9, 2.3)
	cam.global_position = c1
	cam.look_at(CLOCK_TOP + Vector3(0, 0.35, 0), Vector3.UP)
	cam.make_current()
	var t := 0.0
	while t < 0.8:
		var k := 1.0 - t / 0.8
		cam.global_position = c1 + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.07 * k
		await get_tree().process_frame
		t += get_process_delta_time()
	cam.fov = 58.0
	var c2 := Vector3(3.9, 3.6, 6.2)
	cam.global_position = c2
	cam.look_at(Vector3(0, 2.1, 1.0), Vector3.UP)
	var push := create_tween()
	push.tween_property(cam, "global_position", c2 + (Vector3(0, 2.1, 1.0) - c2) * 0.15, 2.2).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(2.2).timeout
	if prev and is_instance_valid(prev):
		prev.make_current()
	cam.queue_free()


## True while a slam on the clock should ring the Grand Bong (rim reached, bong not yet rung). Activities plays the
## plain EV_dome_bong for every other dome slam.
func wants_slam() -> bool:
	return _rim_done and not _bong_done


func _mak_face() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return Vector3(0, 2.0, 1.0)
	var yaw := float(_player.get("facing_yaw")) if _player.get("facing_yaw") != null else _player.global_rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return _player.global_position + Vector3(0, 0.98, 0) + fwd * 0.3 + right * 0.08


## The monocle tumbles down from the chandelier onto Mak's face (R3.3), sits there for the cheer, then goes to the
## hat stand (wearing it needs the core hat registry and the P-H08 mesh: requested).
func _monocle_drop() -> void:
	if _player == null:
		return
	var mono := Node3D.new()
	mono.name = "MonocleDrop"
	add_child(mono)
	var b := HubKit.Buf.new()
	HubKit.lathe(b, HubKit.round_rect_profile(0.05, 0.065, -0.008, 0.008, 0.004, 0.004, 0.004, 0.004), 0.0, 360.0, 15.0, true, false)
	HubArchitecture.mi(mono, b.commit(), HubArchitecture.brass(), "Rim", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), false)
	var lens := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 0.004
	lens.mesh = cyl
	lens.rotation.x = PI * 0.5
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.85, 0.95, 1.0, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.05
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.95, 0.8)
	gm.emission_energy_multiplier = 0.4
	lens.material_override = gm
	mono.add_child(lens)
	mono.scale = Vector3.ONE * 1.6
	var from := Vector3(0, RIM_Y + 0.6, 2.0)
	mono.global_position = from
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_method(func(k: float) -> void:
		var to := _mak_face()
		var p := from.lerp(to, k)
		p.y = lerpf(from.y, to.y, k * k)
		mono.global_position = p
		mono.rotation = Vector3(k * TAU * 3.0, k * TAU * 2.0, 0.0), 0.0, 1.0, 1.2)
	tw.tween_callback(func() -> void:
		_sfx("chime", mono.global_position)
		var ui := get_node_or_null("/root/UI")
		if ui and ui.has_method("toast"):
			ui.call("toast", "Grandfather's monocle! It now hangs on the hat stand."))
	tw.tween_method(func(_k: float) -> void:
		mono.global_position = _mak_face()
		var yaw := float(_player.get("facing_yaw")) if _player and _player.get("facing_yaw") != null else 0.0
		mono.rotation = Vector3(0.0, yaw, 0.0), 0.0, 1.0, 3.0)
	tw.tween_callback(func() -> void:
		ObjSvc.burst(self, mono.global_position, Color(1.0, 0.9, 0.6), 14, 2.0, 0.1, -2.0, 0.6)
		mono.queue_free())


## CHINT_spiral (r1 feel/visual round 2): from the hall side looking out at Mak, leaning 30 degrees ahead along the
## climb, pitched down so the next cover and Mak's drop shadow are in frame. CHINT_rim_drop: an overhead hold from
## the rim to the clock (r 3 cylinder, y 2.6-12.4) that only listens once the rim is reached, so the camera does
## not let go halfway down the 5.7 m slam.
func _camera_zones() -> void:
	var script := load("res://scripts/worlds/hub_camera_zone.gd")
	var z := Area3D.new()
	z.name = "CHINT_spiral"
	z.set_script(script)
	# Fix r2 (fun/feel/QA major): the hall-side camera filmed the climb through the chandelier (candles and brass arms
	# over 20-50 % of the frame). Amendment R2.10 literally: the camera now sits outward of Mak (at most r 12, between
	# him and the gallery), trailing 22 degrees behind along the climb and looking in over him, so the next cover is
	# ahead and the chandelier, the goal, is behind him in the picture.
	z.set("mode", "outside")
	# Verified 17:19Z: chandelier now behind Mak; trailing 22 degrees put the previous covers large in the foreground,
	# so the lean is 10 degrees and the view a little steeper and closer.
	z.set("yaw_offset", 10.0)
	z.set("outer_radius", 12.2)
	z.set("min_outside_distance", 3.4)
	z.set("camera_pitch_deg", -38.0)
	z.set("camera_distance", 5.0)
	z.set("camera_blend", 4.0)
	z.set("camera_priority", 6)
	var th0 := 25.0
	var th1 := 340.0
	var n := int(ceil((th1 - th0) / 8.0))
	for i in n:
		var a := th0 + (th1 - th0) * float(i) / float(n)
		var c := th0 + (th1 - th0) * float(i + 1) / float(n)
		var cs := CollisionShape3D.new()
		cs.shape = HubKit.sector_hull(3.3, 11.2, 5.85, 9.6, a, c)
		z.add_child(cs)
	add_child(z)
	_rim_zone = Area3D.new()
	_rim_zone.name = "CHINT_rim_drop"
	_rim_zone.set_script(script)
	_rim_zone.set("mode", "fixed")
	_rim_zone.set("fixed_yaw", 0.0)  # camera on the +z (south) side behind Mak at the hop cross, looking in and down
	_rim_zone.set("camera_pitch_deg", -58.0)
	_rim_zone.set("camera_distance", 6.5)
	_rim_zone.set("camera_blend", 5.0)
	_rim_zone.set("camera_priority", 8)
	var rcs := CollisionShape3D.new()
	var rcyl := CylinderShape3D.new()
	rcyl.radius = 3.0
	rcyl.height = 9.8
	rcs.shape = rcyl
	rcs.position = Vector3(0, 7.5, 1.0)
	_rim_zone.add_child(rcs)
	add_child(_rim_zone)
	_rim_zone.set_deferred("monitorable", _rim_done and not _bong_done)


## Miss recovery for the middle of the climb (r1 feel round 2): a fall from SP04-SP07 used to mean the walk back to
## the gallery and SP01-SP04 again (about 30 s). A sprung stack of fat dictionaries on the floor under SP04's inner
## edge throws Mak back up beside SP04 (bounce 20 m/s, apex about y 7.6), one stick-nudge from its cover.
func _page_spring(at: Vector3, node_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.add_to_group("bouncy")
	body.set_meta("bounce_velocity", 20.0)
	add_child(body)
	var b := HubKit.Buf.new()
	for k in 7:
		HubKit.lathe(b, HubKit.round_rect_profile(0.32, 0.38, 0.04 + float(k) * 0.05, 0.08 + float(k) * 0.05, 0.015, 0.015, 0.015, 0.015), 0.0, 360.0, 15.0, true, false)
	HubArchitecture.mi(body, b.commit(), HubArchitecture.brass(), "Coil")
	var cols := [Color("2f5d8c"), Color("c9a04a"), Color("8c2f39")]
	for k in 3:
		var bk := HubKit.Buf.new()
		HubKit.rounded_box(bk, Vector3(1.05 - float(k) * 0.08, 0.16, 0.8 - float(k) * 0.05), 0.05,
			Transform3D(Basis(Vector3.UP, 0.25 * float(k) - 0.2), Vector3(0, 0.46 + float(k) * 0.16, 0)))
		HubArchitecture.mi(body, bk.commit(), HubArchitecture.flat_toon(cols[k], 0.45, 0.35), "Book%d" % k)
	var arrow := HubKit.Buf.new()
	HubKit.rounded_box(arrow, Vector3(0.12, 0.02, 0.4), 0.01, Transform3D(Basis(), Vector3(0, 0.0, 0.1)))
	for k in 4:
		HubKit.rounded_box(arrow, Vector3(0.36 * (1.0 - float(k) / 4.0), 0.02, 0.07), 0.01, Transform3D(Basis(), Vector3(0, 0.0, -0.15 - float(k) * 0.06)))
	# The arrow stands upright on the top book, pointing up.
	HubArchitecture.mi(body, arrow.commit(), HubKit.emissive(Color("ffc93c"), 1.4, "spring_arrow"), "Arrow",
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.15, 0)), false)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = 0.94
	cs.shape = cyl
	cs.position.y = 0.47
	body.add_child(cs)


func _book(spec: Array) -> void:
	var id: String = spec[0]
	var kind: String = spec[1]
	var top: Vector3 = spec[2]
	var size: Vector3 = spec[3]
	var theta := atan2(top.x, -top.z)  # from north, clockwise
	var yaw := -(rad_to_deg(theta) + 90.0)
	var body := AnimatableBody3D.new()
	body.name = id
	body.sync_to_physics = kind != "falling"
	body.position = top - Vector3(0, size.y * 0.5, 0)
	body.rotation_degrees.y = yaw
	# r1 feel round 2: a second hop inside the 0.25 s chain window became a double jump and overshot. The player
	# owner is asked to skip double/triple chaining from floors with this meta (requested; harmless until then).
	body.set_meta("no_chain", true)
	add_child(body)
	# Book: leather cover with gilt bands, cream page block on three sides.
	# Fix r1b (visual): the old solid cover box hid the pages and its 1 cm page overhang made every underside a
	# blank cream slab in StoryCam_H. Now two cover boards (top and bottom, leather) sandwich a page block that is
	# inset 6 cm on the three open sides, so the book reads as a book from above, from the side and from below.
	var b := HubKit.Buf.new()
	var board := size.y * 0.24
	for sy in [1.0, -1.0]:
		HubKit.rounded_box(b, Vector3(size.x, board, size.z), 0.05, Transform3D(Basis(), Vector3(0, sy * (size.y - board) * 0.5, 0)), 2, Color.WHITE)
	HubArchitecture.mi(body, b.commit(), HubArchitecture.flat_toon(spec[4], 0.45, 0.35), "Cover")
	var pb := HubKit.Buf.new()
	HubKit.rounded_box(pb, Vector3(size.x - 0.12, size.y - board * 1.9, size.z - 0.12), 0.015, Transform3D(Basis(), Vector3(0.0, 0.0, 0)))
	HubArchitecture.mi(body, pb.commit(), HubArchitecture.flat_toon(Color("eadab0"), 0.4, 0.1), "Pages")
	var lines := HubKit.Buf.new()
	for k in 3:
		var yy := -size.y * 0.16 + float(k) * size.y * 0.16
		HubKit.rounded_box(lines, Vector3(size.x - 0.1, 0.008, size.z - 0.1), 0.002, Transform3D(Basis(), Vector3(0.0, yy, 0)))
	HubArchitecture.mi(body, lines.commit(), HubArchitecture.flat_toon(Color("c8b48a"), 0.2, 0.05), "PageLines")
	var sb := HubKit.Buf.new()
	HubKit.rounded_box(sb, Vector3(0.14, size.y + 0.06, size.z + 0.06), 0.05, Transform3D(Basis(), Vector3(-size.x * 0.5 + 0.05, 0, 0)))
	HubArchitecture.mi(body, sb.commit(), HubArchitecture.flat_toon((spec[4] as Color).darkened(0.35), 0.45, 0.3), "Spine")
	var gb := HubKit.Buf.new()
	for k in [-0.3, 0.3]:
		HubKit.rounded_box(gb, Vector3(0.08, size.y + 0.02, size.z + 0.02), 0.02, Transform3D(Basis(), Vector3(-size.x * 0.5 + 0.12 + k * 0.2, 0, 0)))
	HubArchitecture.mi(body, gb.commit(), HubArchitecture.brass(), "Bands")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	body.add_child(cs)
	var outward := Vector3(top.x, 0, top.z).normalized()
	var d := {"id": id, "kind": kind, "body": body, "base": body.position, "yaw": yaw, "outward": outward,
		"phase": float(spec[5]), "state": "idle", "timer": 0.0, "shape": cs, "top": top, "size": size}
	if kind == "falling":
		var feet := Area3D.new()
		feet.collision_layer = 0
		feet.collision_mask = 0xFFFFFFFF
		var fs := CollisionShape3D.new()
		var fb := BoxShape3D.new()
		fb.size = Vector3(size.x - 0.2, 0.4, size.z - 0.2)
		fs.shape = fb
		fs.position.y = size.y * 0.5 + 0.2
		feet.add_child(fs)
		body.add_child(feet)
		feet.body_entered.connect(func(n: Node) -> void:
			if n.is_in_group("player") and d["state"] == "idle":
				d["state"] = "armed"
				d["timer"] = 0.0)
		feet.body_exited.connect(func(n: Node) -> void:
			if n.is_in_group("player") and d["state"] == "armed":
				d["state"] = "idle")
	_books.append(d)


func _rim() -> void:
	# A31: the chandelier's gilt rim band, r 2.3-2.9, top y 9.1, 0.3 thick. Only the band collides.
	var rim := AnimatableBody3D.new()
	rim.name = "A31_chandelier_rim"
	rim.position = Vector3(0, RIM_Y - 0.15, 0)
	add_child(rim)
	var b := HubKit.Buf.new()
	var n := 32
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var mid := Vector3(sin(a0), 0, -cos(a0)) * 2.6
		var seg_len := 2.0 * PI * 2.6 / float(n) + 0.04
		var xf := Transform3D(Basis(Vector3.UP, -a0), mid)
		HubKit.rounded_box(b, Vector3(seg_len, 0.3, 0.6), 0.05, xf)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(seg_len, 0.3, 0.6)
		cs.shape = bx
		cs.transform = xf
		rim.add_child(cs)
	HubArchitecture.mi(rim, b.commit(), HubArchitecture.brass(), "RimBand")
	var top := Area3D.new()
	top.name = "RimReached"
	top.collision_layer = 0
	top.collision_mask = 0xFFFFFFFF
	for i in 8:
		var a0 := TAU * float(i) / 8.0
		var cs2 := CollisionShape3D.new()
		var bx2 := BoxShape3D.new()
		bx2.size = Vector3(2.2, 0.6, 0.8)
		cs2.shape = bx2
		cs2.transform = Transform3D(Basis(Vector3.UP, -a0), Vector3(sin(a0) * 2.6, 0.45, -cos(a0) * 2.6))
		top.add_child(cs2)
	rim.add_child(top)
	top.body_entered.connect(_on_rim)


func _on_rim(n: Node) -> void:
	if not n.is_in_group("player"):
		return
	if _rim_zone and not _bong_done:
		_rim_zone.set_deferred("monitorable", true)
	if _rim_done:
		return
	_rim_done = true
	print("[Hub] EV_rim_reached")
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("unlock"):
		var dev := get_node_or_null("/root/Dev")
		if not (dev and dev.has_method("is_test_run") and bool(dev.call("is_test_run"))):
			game.call("unlock", "hub_rim_reached")  # R3.3: hub_spiral_done waits for the Grand Bong
	if ResourceLoader.exists("res://scenes/fx/Confetti.tscn"):
		FxEffect.spawn(self, "res://scenes/fx/Confetti.tscn", (n as Node3D).global_position + Vector3(0, 1.0, 0))
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play_sfx"):
		audio.call("play_sfx", "chime", (n as Node3D).global_position)
	if _target:
		_target.visible = true
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.call("toast", "Hop off the rim and Ham Slam the gold ring on the clock!")
	if level and level.has_method("_bubble_on"):
		level.call("_bubble_on", n, "The whole library from up here! Splendid.", 3.0, 1.9)
		var bram: Node3D = level.get("bramwell") as Node3D
		if bram:
			level.call("_bubble_on", bram, "Mind the drop, sir. Or do mind the clock, rather.", 3.5)


func _on_cover(d: Dictionary, margin := 0.15) -> bool:
	if _player == null or not _player.is_on_floor():
		return false
	var body: Node3D = d["body"]
	var sz: Vector3 = d["size"]
	var local := body.global_transform.affine_inverse() * _player.global_position
	return absf(local.x) < sz.x * 0.5 + margin and absf(local.z) < sz.z * 0.5 + margin and local.y > sz.y * 0.5 - 0.25 and local.y < sz.y * 0.5 + 0.45


func _physics_process(delta: float) -> void:
	_t += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_slam_assist(delta)
	_no_chain()
	_landing_brake()
	var lift := Vector3(0, -7.0 * (1.0 - _rise), 0)
	for d in _books:
		var body: AnimatableBody3D = d["body"]
		var base: Vector3 = (d["base"] as Vector3) + lift
		match String(d["kind"]):
			"static":
				body.position = base + Vector3(0, sin(_t * TAU / 3.0 + base.x) * 0.08, 0)
			"rotating":
				var prev := body.rotation_degrees.y
				body.rotation_degrees.y = float(d["yaw"]) + _t * ATLAS_SPEED
				body.position = base + Vector3(0, sin(_t * TAU / 3.0) * 0.05, 0)
				# r1 feel: the atlas neither carried nor threw its rider. Carry Mak round with it.
				if _on_cover(d, 0.3):
					var dy := deg_to_rad(body.rotation_degrees.y - prev)
					var c := body.global_position
					var rel := _player.global_position - c
					_player.global_position = c + rel.rotated(Vector3.UP, dy)
			"wing":
				# r1 round 2 (fun first): open 2.0 s (last 0.5 s quivers with a rustle), clap 0.2 s, tilted 0.6 s,
				# reopen 0.2 s. The old 1.6 s window left a skilled bot arriving exactly as it clapped.
				var ph := fposmod(_t + float(d["phase"]), WING_PERIOD)
				var tilt := 0.0
				var quiver := 0.0
				if ph < WING_OPEN:
					tilt = 0.0
					if ph > WING_OPEN - 0.5:
						quiver = sin(_t * 60.0) * 0.8
				elif ph < WING_OPEN + 0.2:
					tilt = (ph - WING_OPEN) / 0.2
				elif ph < WING_PERIOD - 0.2:
					tilt = 1.0
				else:
					tilt = 1.0 - (ph - (WING_PERIOD - 0.2)) / 0.2
				var out: Vector3 = d["outward"]
				var axis := Vector3(-out.z, 0, out.x)  # horizontal, perpendicular to outward: tips the outer edge down
				var basis := Basis(axis, deg_to_rad(WING_TILT * tilt + quiver)) * Basis(Vector3.UP, deg_to_rad(float(d["yaw"])))
				# The clap flicks a rider off the outer edge (r1 feel: a still player never fell).
				var prev_ph := fposmod(_t - delta + float(d["phase"]), WING_PERIOD)
				if prev_ph < WING_OPEN and ph >= WING_OPEN and _on_cover(d) and _player.has_method("add_impulse"):
					_player.call("add_impulse", out * 3.5 + Vector3(0, 2.5, 0))
				body.transform = Transform3D(basis, base)
			"falling":
				_faller(d, delta)


## r1 feel (fix round 1b): a Ham Slam pressed right after the hop off the rim (within ~14 frames) used to drop Mak
## straight back onto the rim band with no feedback. While the Grand Bong is armed, a slam started above y 4 within
## 3.4 m of the clock axis drifts toward the dome crown at up to 4.5 m/s, so any slam from the hop lands on target.
## Fix r1b (feel M3): rhythmic hops across the covers landed inside the 0.25 s chain window and became double jumps
## that overshot the next cover (spiral bot, 15:05Z: SP04 -> SP05 double jump landed on the far edge, then the faller
## dropped). While Mak stands on a spiral cover his chain is cleared, so the next hop is always a plain single jump.
## (The player owner is also asked to honour the covers' `no_chain` meta inside the player, which would also catch a
## jump buffered on the landing frame.)
func _no_chain() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_on_floor():
		return
	if String(_player.get("chain_kind")) == "":
		return
	for d in _books:
		if _on_cover(d, 0.3):
			_player.set("chain_kind", "")
			return


## Fix r2 (feel major): natural hops overshot the fallers (SP05 -> SP06 failed 4/5, landing 2.5-3.2 m past the
## centre) because run speed carried across the covers. On the first grounded frame on a cover Mak's speed is trimmed
## to 3.5 m/s, and while he stands on a faller (SP05-SP07) it is capped at 6.5 m/s, so a hop from mid-cover lands
## mid-cover on the next one. (A 5 m/s cap on every cover left the SP07 -> SP08 hop 1.2 m short: verified 17:19Z.)
var _was_on_cover := false


func _landing_brake() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var on: Dictionary = {}
	if _player.is_on_floor():
		for d in _books:
			if _on_cover(d, 0.1):
				on = d
				break
	if not on.is_empty():
		var cap := 3.5
		if _was_on_cover:
			cap = 6.5 if String(on["kind"]) == "falling" else 99.0
		var fs := float(_player.get("forward_speed"))
		if fs > cap:
			_player.set("forward_speed", cap)
		var ev: Vector3 = _player.get("ext_vel")
		if not _was_on_cover and ev.length() > cap:
			_player.set("ext_vel", ev.limit_length(cap))
	_was_on_cover = not on.is_empty()


func _slam_assist(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not wants_slam():
		return
	if not _player.has_method("get_state_name") or String(_player.call("get_state_name")) != "ham_slam":
		return
	var p := _player.global_position
	if p.y < 4.0:
		return
	var to := Vector2(CLOCK_TOP.x - p.x, CLOCK_TOP.z - p.z)
	var dist := to.length()
	if dist < 0.12 or dist > 3.4:
		return
	var step := minf(dist, 4.5 * delta)
	var mv := to / dist * step
	_player.global_position = Vector3(p.x + mv.x, p.y, p.z + mv.y)


func _faller(d: Dictionary, delta: float) -> void:
	var body: AnimatableBody3D = d["body"]
	# Fix r2: the fallers ignored EV_huff_7's rise, so they hung in place during the return flights.
	var base: Vector3 = (d["base"] as Vector3) + Vector3(0, -7.0 * (1.0 - _rise), 0)
	d["timer"] = float(d["timer"]) + delta
	var tm: float = d["timer"]
	match String(d["state"]):
		"idle":
			body.position = base + Vector3(0, sin(_t * TAU / 3.0 + base.x) * 0.06, 0)
		"armed":
			body.position = base + Vector3(0, sin(_t * TAU / 3.0 + base.x) * 0.06, 0)
			if _on_cover(d):
				d["state"] = "shudder"
				d["timer"] = 0.0
				_sfx("crate_creak", base)
			elif tm >= 1.2:
				d["state"] = "shudder"  # brushed past without settling: still drops, a little later
				d["timer"] = 0.0
		"shudder":
			# r1 round 2 bug fix: "shudder" had no branch, so a faller Mak stood on never fell at all.
			var delay := float(FALL_DELAYS.get(d["id"], FALL_DELAY))
			var k := clampf(tm / delay, 0.0, 1.0)
			body.position = base + Vector3(sin(_t * 70.0) * (0.02 + 0.04 * k), -0.05 * k, 0)
			if tm >= delay:
				d["state"] = "fall"
				d["timer"] = 0.0
				(d["shape"] as CollisionShape3D).set_deferred("disabled", true)
		"fall":
			body.position = base - Vector3(0, 0.5 * 9.0 * tm * tm, 0)
			body.visible = tm < 0.6
			if tm >= FALL_RESPAWN:
				d["state"] = "idle"
				d["timer"] = 0.0
				body.visible = true
				body.position = base
				(d["shape"] as CollisionShape3D).set_deferred("disabled", false)
