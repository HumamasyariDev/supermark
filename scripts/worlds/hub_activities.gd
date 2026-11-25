class_name HubActivities
extends Node3D
## Hub activities from Docs/levels/HUB_amendments.md round 1: H-A Grandfather's Nook (Sniff + Slam), H-B the rug
## that baa'd (Woolly Wolf cub chase), H-D the upgraded HUB-1 (long-jump gap, slam board, bell-cage, tapestry drop and
## portrait reveal), H-E/H-F shortcuts (beanstalk vine, bellows updraft) and the sniff-target chain. None of it can hurt Mak.

const CUB_GLB := "res://assets/enemies/woolly_wolf_cub/woolly_wolf_cub.glb"
## Fix r2 (QA/feel major): waypoints 2-5 went through the nook under flight 2 and the landing, where the chase camera
## collapsed to 1.3 m looking straight down. The loop now swings across the stair foot (between the stair and the
## clock drum); corners 3 and 4 are the stair-foot corners where Mak can cut across and wait.
const CUB_LOOP := [Vector3(-11.6, 0, -1.6), Vector3(-6.4, 0, -1.2), Vector3(-5.4, 0, -3.6), Vector3(-3.4, 0, -2.05), Vector3(3.4, 0, -2.05),
	Vector3(5.4, 0, -3.6), Vector3(6.6, 0, -1.0), Vector3(10.2, 0, 2.8), Vector3(10.4, 0, 8.4), Vector3(6.0, 0, 10.8), Vector3(0.8, 0, 9.4),
	Vector3(-4.2, 0, 10.2), Vector3(-8.6, 0, 11.2), Vector3(-11.4, 0, 7.0), Vector3(-10.6, 0, 3.7), Vector3(-12.0, 0, 1.6)]

var level: Node3D
var _player: Node3D
var _t := 0.0
# Nook
var _nook_board: Node3D
var _nook_done := false
var _st_nook: Node3D
var _st_ladder: Node3D
# HUB-1
var _slam_board: Node3D
var _cage: Node3D
var _revealed := false
var _portrait_light: SpotLight3D
# Cub
var _cub: Node3D
var _cub_visual: Node3D
var _rug: Node3D
var _cub_state := "rug"  # rug, waking, run (phase 1 sheep), aim, windup, charge, skid, dizzy, caught, gone
var _sheep_visual: Node3D
var _cub_real: Node3D
var _phase := 1
var _state_t := 0.0
var _run_t := 0.0
var _dodge_cd := 0.0
var _charge_dir := Vector3.ZERO
var _charge_left := 0.0
var _charge_blocked := false
var _dizzy_stars: Node3D
var _phase2_t := 0.0
var _tripped := false
var _duel_hits := 0
var _blocked_t := 0.0
const CORNERS := [0, 1, 3, 4, 8, 12]
const SHEEP_GLB := "res://assets/enemies/woolly_wolf/woolly_wolf.glb"
var _cub_i := 0
var _cub_pause := 0.0
var _cub_ear_t := 7.0
var _cub_contact_cd := 0.0
var _cub_arm_ready := false  # edge trigger: Mak must approach Book 1 from beyond 6.5 m
var _cub_spawn_d := -1.0
var _sheep_rig: HubRig
var _cub_rig: HubRig
var _lane: MeshInstance3D
var _bang: Label3D
var _cue_shown := false
var _cue_arrow: Node3D
var _impostor_key: OmniLight3D
const CUB_MASK := 1 | (1 << 2)


func _ready() -> void:
	process_physics_priority = -20
	_camera_zones()
	_tea_run_setup.call_deferred()
	_nook()
	_hub1_upgrade()
	_cub_gag()
	_shortcuts()
	_sniff_chain()
	var game := _game()
	if game and game.has_signal("unlocked"):
		game.unlocked.connect(func(_f: String) -> void: _sniff_chain())
	_connect_player.call_deferred()


func _game() -> Node:
	return get_node_or_null("/root/Game")


func _flag(f: String) -> bool:
	return HubKit.flag(self, f)


func _unlock(f: String) -> void:
	var g := _game()
	if g and g.has_method("unlock"):
		g.call("unlock", f)


func _has(id: String) -> bool:
	var g := _game()
	return g != null and g.has_method("has_truffle") and bool(g.call("has_truffle", id))


func _say(lines: Array, speaker := "") -> void:
	if not ObjSvc.show_dialog(lines, speaker):
		print("[Hub] %s: %s" % [speaker, lines])


func _sfx(key: String, at := Vector3.INF) -> void:
	var a := get_node_or_null("/root/Audio")
	if a and a.has_method("play_sfx"):
		a.call("play_sfx", key, at)


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player and _player.has_signal("ground_pounded"):
		_player.connect("ground_pounded", _on_ground_pounded)


func _on_ground_pounded(at: Vector3) -> void:
	if _nook_board and not _nook_done and Vector2(at.x - 0.0, at.z + 11.8).length() < 1.2 and at.y < 1.0:
		_open_nook()
	if _slam_board and not _revealed and at.distance_to(Vector3(-1.53, 9.7, 14.52)) < 0.8:
		_reveal_portrait()
	if _cub and at.distance_to(_cub.global_position) < 2.5:
		cub_hit("slam")
	# EV_dome_bong (R3.3 egg): any slam on the glass dome crown that is not the Grand Bong rings the clock.
	if Vector2(at.x, at.z - 1.0).length() < 0.8 and at.y > 3.0 and at.y < 4.0:
		var sp := level.get_node_or_null("HG_Catalogue_Spiral") if level else null
		if not (sp and sp.has_method("wants_slam") and bool(sp.call("wants_slam"))):
			var clk: Node = level.get("clock") if level else null
			if clk and clk.has_method("bong"):
				print("[Hub] EV_dome_bong")
				clk.call("bong")
				if level.has_method("dome_bong_acorns"):
					level.call("dome_bong_acorns")


# ------------------------------------------------------------------ R2.10 camera hints

var _chase_zone: Area3D


func _camera_zones() -> void:
	var script := load("res://scripts/worlds/hub_camera_zone.gd")
	# r1 critique round (feel + visual): cornice pitched down to look across and into the hall, zone yaw blended fast
	# enough to beat auto-follow; the top balcony is a fixed hall-side view of Mak, the jar and the portrait (the old
	# radial boom sat behind the crest tapestry); the chimney looks down the fins; shelf-ring and mantel hints keep the
	# boom out of the bookcases and the chimney breast.
	# name, mode, fixed yaw, pitch, distance, blend, priority, [r_in, r_out, y0, y1, th0, th1]
	var specs := [
		# r1 visual/feel round 2: the radial view filled 60 % of the frame with damask and shrank Mak. The cornice now
		# uses a tangent view from behind and inside (camera at r about 12.8, above the inner lintel board) looking
		# along the walk, so the ledge ahead, the gap and the hall are all in frame.
		# Fix r2 (feel major): yaw_offset 55 put camera-forward 35 degrees into the wall, so a held "up" pinned Mak.
		# 72 is close to the walk (hall-side, clear of the drum frescoes) and the steering assist in _physics_process
		# maps "up" onto the tangent; pitch -18 shows the ledge ahead.
		["CHINT_cornice", "tangent", 0.0, -18.0, 5.5, 6.0, 5, [14.0, 16.2, 8.3, 11.0, 98.0, 170.0]],
		# Cornice B (after the gap): the boom behind Mak reaches back over the gap, so it stays low (pitch -8,
		# camera about y 10.2) and passes under the lintel's hanging books (bottoms y 11.3); seqF 17:27Z had Mak
		# x-rayed behind them on landing.
		["CHINT_cornice_b", "tangent", 0.0, -8.0, 5.0, 6.0, 6, [14.0, 16.2, 8.3, 11.0, 150.0, 170.0]],
		# Fix r2 (feel blocker): the HUB-1 long jump. The tangent boom hit lintel A30 at take-off and filmed the gap
		# from inside the lintel. A side view from the hall (camera about r 8, y 10, under the lintel's 11.3 cap)
		# keeps the take-off stub, the gap and cornice B in one frame.
		["CHINT_gap", "fixed", -138.0, -6.0, 7.0, 4.0, 7, [14.0, 16.2, 8.3, 11.2, 118.0, 152.0]],
		["CHINT_top_balcony", "fixed", -190.0, -26.0, 5.0, 5.0, 6, [13.4, 16.2, 9.4, 12.5, 170.0, 207.0]],
		# Fix r2 (feel major): the chimney camera looked down the fins and never showed the goal. It now looks up
		# (pitch +8) from closer in so the balcony lip and the next fin are in frame during the kicks.
		["CHINT_chimney", "fixed", -211.4, 8.0, 6.0, 5.0, 6, [12.9, 15.3, 4.4, 11.5, 205.0, 218.0]],
		["CHINT_shelf_ring_floor_e", "radial", 0.0, -34.0, 4.6, 1.8, 1, [14.0, 16.2, -0.2, 2.6, 0.0, 160.0]],
		["CHINT_shelf_ring_floor_w", "radial", 0.0, -34.0, 4.6, 1.8, 1, [14.0, 16.2, -0.2, 2.6, 200.0, 360.0]],
		["CHINT_shelf_ring_gallery", "radial", 0.0, -34.0, 4.6, 1.8, 1, [14.0, 16.2, 4.3, 7.0, 0.0, 360.0]],
	]
	for sp in specs:
		var z := Area3D.new()
		z.name = sp[0]
		z.set_script(script)
		z.set("mode", sp[1])
		z.set("fixed_yaw", sp[2])
		z.set("camera_pitch_deg", sp[3])
		z.set("camera_distance", sp[4])
		z.set("camera_blend", sp[5])
		z.set("camera_priority", sp[6])
		if sp[1] == "tangent":
			# 72, not 82: at 82 the boom reached r 15.9 at y 11 and sat behind the drum frescoes (seqD 17:21Z).
			z.set("yaw_offset", 72.0)
		var v: Array = sp[7]
		var span: float = v[5] - v[4]
		var n := int(ceil(span / 8.0))
		for i in n:
			var a: float = v[4] + span * float(i) / float(n)
			var b: float = v[4] + span * float(i + 1) / float(n)
			var cs := CollisionShape3D.new()
			cs.shape = HubKit.sector_hull(v[0], v[1], v[2], v[3], a, b)
			z.add_child(cs)
		add_child(z)
	var nook := Area3D.new()
	nook.name = "CHINT_nook"
	nook.set_script(script)
	nook.set("mode", "mouth")
	# Fix r2 (feel major): the camera was inside the stair in 195 of 626 frames on the sniff-trail approach. Shorter
	# boom (3.5 m, stays under flight 2), a zone as tall as the nook's headroom and a side that only flips 1 m past
	# the axis (hub_camera_zone.gd "mouth").
	nook.set("camera_pitch_deg", -9.0)
	nook.set("camera_distance", 3.5)
	nook.set("camera_priority", 5)
	var ncs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(7.0, 3.6, 3.2)
	ncs.shape = bx
	ncs.position = Vector3(0, 1.8, -10.6)
	nook.add_child(ncs)
	add_child(nook)
	# Mantel (HJ5 / AG03): a steep boom from the hall side so the screen is never the inside of the chimney breast.
	_box_zone(script, "CHINT_mantel", "fixed", 90.0, -45.0, 3.8, 4.0, 7, Vector3(1.6, 2.2, 4.4), Vector3(-14.2, 3.0, 0.0))
	# Fix r1b (visual): on the outdoor balcony the boom sat inside the French-door reveal, so damask walls filled
	# 40 % of the frame (seqM capture, Balcony spawn). A side view from the east, out over the balustrade, shows
	# Mak, the balcony and the countryside instead. Only the outer part of the balcony (z > 17.3) is covered.
	# 19 Oct 2026 (camera review): yaw 75 looked west-north-west into the rotunda wall by the French doors. Yaw 120 keeps
	# the boom east of Mak, out past the balustrade (no wall pushes it in), and looks west-south-west over the balcony
	# and the telescope to the hills, the windmill and the terraced gardens.
	_box_zone(script, "CHINT_balcony", "fixed", 98.0, -15.0, 5.0, 4.0, 6, Vector3(11.0, 3.5, 5.2), Vector3(0.0, 5.9, 19.9))
	# Rim drop (R3.3) and the spiral hint now live in hub_spiral.gd (built only with the spiral; r1 feel round 2).
	# Phase-2 cub duel: both actors in frame (enabled only while the cub is loose in phase 2).
	_chase_zone = Area3D.new()
	_chase_zone.name = "CHINT_cub_chase"
	_chase_zone.set_script(script)
	_chase_zone.set("mode", "chase")
	# Fix r2: at 7.5 m / -22 the boom ended inside the gallery fascia (r 12.3, y 3.5-4.1, visual only) near the
	# west wall and Mak showed as an x-ray silhouette (seqA 17:14Z, t 9.5). 6.5 m / -18 keeps the camera under it.
	_chase_zone.set("camera_pitch_deg", -18.0)
	_chase_zone.set("camera_distance", 6.5)
	_chase_zone.set("camera_blend", 3.0)
	_chase_zone.set("camera_priority", 4)
	var ccs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 15.5
	cyl.height = 3.0
	ccs.shape = cyl
	ccs.position = Vector3(0, 1.5, 0)
	_chase_zone.add_child(ccs)
	add_child(_chase_zone)
	_chase_zone.monitorable = false


func _box_zone(script: Script, n: String, mode: String, yaw: float, pitch: float, dist: float, blend: float, prio: int, size: Vector3, at: Vector3) -> Area3D:
	var z := Area3D.new()
	z.name = n
	z.set_script(script)
	z.set("mode", mode)
	z.set("fixed_yaw", yaw)
	z.set("camera_pitch_deg", pitch)
	z.set("camera_distance", dist)
	z.set("camera_blend", blend)
	z.set("camera_priority", prio)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = at
	z.add_child(cs)
	add_child(z)
	return z


func _set_chase_cam(on: bool) -> void:
	if _chase_zone:
		_chase_zone.set("target", _cub if on else null)
		_chase_zone.set_deferred("monitorable", on)


# ------------------------------------------------------------------ H-A Grandfather's Nook

func _nook() -> void:
	_nook_done = _flag("hub_nook_done")
	_nook_board = Node3D.new()
	_nook_board.name = "NookBoard"
	_nook_board.position = Vector3(0, 0.0, -11.8)
	add_child(_nook_board)
	var b := HubKit.Buf.new()
	HubKit.rounded_box(b, Vector3(1.1, 0.08, 0.32), 0.02, Transform3D(Basis(Vector3.UP, 0.12) * Basis(Vector3.RIGHT, -0.05), Vector3(0, 0.03, 0)))
	HubArchitecture.mi(_nook_board, b.commit(), HubArchitecture.toon("wood_planks", Color(0.8, 0.62, 0.5), 0.9), "LooseBoard")
	var nail := CylinderMesh.new()
	nail.top_radius = 0.012
	nail.bottom_radius = 0.012
	nail.height = 0.09
	HubArchitecture.mi(_nook_board, nail, HubArchitecture.iron(), "Nail").position = Vector3(0.42, 0.1, 0.03)
	var glint := HubArchitecture.mi(_nook_board, SphereMesh.new(), HubKit.emissive(Color(1.0, 0.85, 0.4), 3.0, "nook_glint"), "Glint")
	(glint.mesh as SphereMesh).radius = 0.03
	(glint.mesh as SphereMesh).height = 0.06
	glint.position = Vector3(-0.3, 0.09, 0.0)
	glint.add_to_group("hub_glint")
	if _nook_done:
		_nook_board.rotation_degrees.x = -70.0
	# Grandfather's portrait (young, with a shovel) is a character, so it waits for CH-06; the nook keeps a frame.
	var fr := HubKit.Buf.new()
	HubKit.rounded_box(fr, Vector3(1.2, 0.9, 0.08), 0.04, Transform3D(Basis(), Vector3(0, 1.35, -12.37)))
	HubArchitecture.mi(self, fr.commit(), HubArchitecture.brass(), "NookFrame")
	var canvas := HubKit.Buf.new()
	HubKit.rounded_box(canvas, Vector3(1.0, 0.7, 0.02), 0.01, Transform3D(Basis(), Vector3(0, 1.35, -12.32)))
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/environment/hub/hub_portrait.gdshader")
	sm.set_shader_parameter("variant", 1.0)
	HubArchitecture.mi(self, canvas.commit(), sm, "NookPainting")


func _open_nook() -> void:
	_nook_done = true
	_unlock("hub_nook_done")
	_unlock("hat_deerstalker")
	_sfx("chest_open", _nook_board.global_position)
	var tw := create_tween()
	tw.tween_property(_nook_board, "rotation_degrees:x", -70.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The deerstalker pops out on a spring.
	var hat := _deerstalker()
	hat.position = Vector3(0, 0.1, -11.8)
	add_child(hat)
	var t2 := create_tween()
	t2.tween_property(hat, "position:y", 1.6, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t2.parallel().tween_property(hat, "rotation:y", TAU * 2.0, 0.9)
	t2.tween_property(hat, "position:y", 1.2, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	hat.add_to_group("hub_spin_hat")
	ObjSvc.burst(self, Vector3(0, 0.4, -11.8), Color(1.0, 0.85, 0.4), 30, 4.0, 0.16, -6.0, 1.0)
	# Fix r2 (fun minor): the reveal opened on a dialog with the camera behind Mak facing a bookcase. A 1.3 s
	# close-up of the panel springing and the hat bouncing plays first, then the note.
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "NookRevealCam"
	cam.fov = 50.0
	add_child(cam)
	cam.global_position = Vector3(1.25, 1.35, -9.55)
	cam.look_at(Vector3(0.0, 0.95, -11.8), Vector3.UP)
	cam.make_current()
	await get_tree().create_timer(1.3).timeout
	if prev and is_instance_valid(prev):
		prev.make_current()
	cam.queue_free()
	_say(["Boing! A deerstalker on a spring! It shall hang on the hat stand by the doors.", "And a note in Grandfather's hand: \"Look up, where the cornice fell.\""], "Grandfather's Nook")
	_sniff_chain()
	print("[Hub] nook opened: hat_deerstalker, hub_nook_done")


## Procedural tweed deerstalker (prop stand-in until the P-H03 mesh exists).
func _deerstalker() -> Node3D:
	var n := Node3D.new()
	n.name = "Deerstalker"
	var b := HubKit.Buf.new()
	HubKit.turned(b, PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.17, 0.06), Vector2(0.15, 0.12), Vector2(0.1, 0.17), Vector2(0.0, 0.19)]), 18)
	HubKit.rounded_box(b, Vector3(0.18, 0.03, 0.12), 0.012, Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.02, -0.2)))
	HubKit.rounded_box(b, Vector3(0.18, 0.03, 0.12), 0.012, Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.02, 0.2)))
	HubKit.rounded_box(b, Vector3(0.06, 0.03, 0.05), 0.012, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	HubArchitecture.mi(n, b.commit(), HubArchitecture.flat_toon(Color("8a6a46"), 0.35, 0.2), "Hat")
	return n


# ------------------------------------------------------------------ H-D HUB-1 upgrade

func _hub1_upgrade() -> void:
	_revealed = _has("HUB-1") or _flag("hub_portrait_revealed")
	# Gilded loose floorboard (SS_balcony) that rattles when walked on.
	_slam_board = Node3D.new()
	_slam_board.name = "SS_balcony"
	_slam_board.position = Vector3(-1.53, 9.7, 14.52)
	_slam_board.rotation_degrees.y = HubKit.yaw_facing_centre(186.0)
	add_child(_slam_board)
	var b := HubKit.Buf.new()
	HubKit.rounded_box(b, Vector3(0.9, 0.06, 0.9), 0.03, Transform3D(Basis(), Vector3(0, 0.03, 0)))
	HubArchitecture.mi(_slam_board, b.commit(), HubKit.emissive(Color("d8a640"), 0.35, "gilt_board"), "GiltBoard")
	var ring := HubKit.Buf.new()
	HubKit.lathe(ring, HubKit.round_rect_profile(0.5, 0.56, 0.0, 0.04, 0.0, 0.02, 0.02, 0.0), 0.0, 360.0, 15.0, true, false)
	HubArchitecture.mi(_slam_board, ring.commit(), HubArchitecture.brass(), "SlamRing")
	# Brass bell-cage clamping the jar (prop P-H06 stand-in): bars from the table top to a crown.
	_cage = Node3D.new()
	_cage.name = "BellCage"
	_cage.position = HubKit.polar(15.0, 190.0, 9.7 + 0.68)
	add_child(_cage)
	var cb := HubKit.Buf.new()
	for k in 10:
		var a := TAU * float(k) / 10.0
		HubKit.rounded_box(cb, Vector3(0.035, 0.95, 0.035), 0.015, Transform3D(Basis(), Vector3(cos(a) * 0.36, 0.48, sin(a) * 0.36)))
	HubKit.lathe(cb, HubKit.round_rect_profile(0.32, 0.4, 0.0, 0.06, 0.02, 0.02, 0.02, 0.02), 0.0, 360.0, 15.0, true, false)
	HubKit.lathe(cb, HubKit.round_rect_profile(0.3, 0.4, 0.94, 1.0, 0.02, 0.02, 0.02, 0.02), 0.0, 360.0, 15.0, true, false)
	HubKit.turned(cb, PackedVector2Array([Vector2(0.32, 1.0), Vector2(0.2, 1.12), Vector2(0.06, 1.18), Vector2(0.05, 1.3), Vector2(0.09, 1.34)]), 14)
	HubArchitecture.mi(_cage, cb.commit(), HubArchitecture.brass(), "Cage")
	# Grandfather's portrait behind the tapestry (A28) and its light (off until the reveal).
	var pf := HubKit.Buf.new()
	HubKit.lathe(pf, HubKit.round_rect_profile(15.7, 15.95, 10.5, 15.3, 0.05, 0.05, 0.05, 0.05), 183.5, 196.5, 1.5, true, true)
	HubArchitecture.mi(self, pf.commit(), HubArchitecture.brass(), "PortraitFrame")
	var pc := HubKit.Buf.new()
	HubKit.lathe(pc, PackedVector2Array([Vector2(15.68, 10.8), Vector2(15.68, 15.0)]), 184.3, 195.7, 1.0, false, false, 10.0, 1.0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/environment/hub/hub_portrait.gdshader")
	sm.set_shader_parameter("variant", 0.0)
	HubArchitecture.mi(self, pc.commit(), sm, "Portrait")
	_portrait_render.call_deferred(sm)
	_portrait_light = SpotLight3D.new()
	_portrait_light.name = "LT_portrait"
	_portrait_light.light_color = Color("ffd38a")
	_portrait_light.light_energy = 0.0
	_portrait_light.spot_angle = 18.0
	_portrait_light.spot_range = 22.0
	_portrait_light.light_volumetric_fog_energy = 0.0
	add_child(_portrait_light)
	_portrait_light.look_at_from_position(Vector3(0, 8, 6), Vector3(-2.77, 12.9, 15.71), Vector3.UP)
	if _revealed:
		_apply_revealed(false)
	else:
		_set_truffle_locked(true)


## Fix r2 (visual/fun major): the HUB-1 reveal ended on an abstract still life (gold "9"-like shapes on green).
## Until CH-06 exists, the portrait is a one-off render of the real generated Mak model (mak.glb, beanie hidden) in
## Grandfather's top hat (mak_tophat.glb on the head_top socket), from a private SubViewport world.
const PORTRAIT_BODY := "res://assets/characters/mak/mak.glb"
const PORTRAIT_HAT := "res://assets/characters/mak/mak_tophat.glb"


func _portrait_render(sm: ShaderMaterial) -> void:
	var bps := HubAssets.scene(PORTRAIT_BODY)
	if bps == null:
		return
	var sv := SubViewport.new()
	sv.name = "PortraitViewport"
	sv.size = Vector2i(160, 210)
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var root := Node3D.new()
	sv.add_child(root)
	var body := bps.instantiate() as Node3D
	body.set_meta("retro_skip", true)
	root.add_child(body)
	for n in body.find_children("*", "Node3D", true, false):
		if String(n.name).to_lower().contains("beanie"):
			(n as Node3D).visible = false
	var skel := body.find_children("*", "Skeleton3D", true, false)
	var hps := HubAssets.scene(PORTRAIT_HAT)
	if hps and not skel.is_empty():
		var sk := skel[0] as Skeleton3D
		var bi := sk.find_bone("head_top")
		if bi >= 0:
			var hat := hps.instantiate() as Node3D
			root.add_child(hat)
			var rest := sk.global_transform * sk.get_bone_global_rest(bi)
			hat.global_transform = Transform3D(rest.basis * Basis.from_euler(Vector3(deg_to_rad(-5.0), 0.0, deg_to_rad(8.0))), rest * Vector3(0.0, -0.0825, -0.01))
	# Frame head and shoulders from the front (the model faces +Z).
	var aabb := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	if first:
		sv.queue_free()
		return
	var h := aabb.size.y
	var look := aabb.get_center() + Vector3(0, h * 0.18, 0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	cam.position = look + Vector3(h * 0.35, h * 0.08, h * 1.9)
	cam.look_at(look, Vector3.UP)
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe2b0")
	key.light_energy = 1.4
	root.add_child(key)
	key.rotation_degrees = Vector3(-30.0, 35.0, 0.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.45)
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)
	sm.set_shader_parameter("portrait_tex", sv.get_texture())
	sm.set_shader_parameter("use_tex", 1.0)
	# Render a few frames, then freeze the picture.
	for i in 4:
		await get_tree().process_frame
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _set_truffle_locked(locked: bool) -> void:
	var tr: Area3D = level.get("hub_truffle") as Area3D if level else null
	if tr:
		tr.set_deferred("monitoring", not locked)


func _reveal_portrait() -> void:
	_revealed = true
	_unlock("hub_portrait_revealed")
	print("[Hub] EV_portrait_reveal")
	_sfx("switch_press", _slam_board.global_position)
	var tw := create_tween()
	tw.tween_property(_slam_board, "position:y", 9.66, 0.08)
	# StoryCam_F for three seconds, with Mak held still so the shot is not spoiled (r1 fun).
	var cam := get_parent().get_parent().get_node_or_null("StoryCams/StoryCam_F") as Camera3D
	var prev := get_viewport().get_camera_3d()
	if cam:
		cam.make_current()
	if _player:
		_player.set_physics_process(false)
	_apply_revealed(true)
	await get_tree().create_timer(3.0).timeout
	if _player:
		_player.set_physics_process(true)
	if prev and is_instance_valid(prev):
		prev.make_current()


func _apply_revealed(animate: bool) -> void:
	var tap: Node3D = level.get("_tapestry") as Node3D if level else null
	if tap:
		if animate:
			var tw := create_tween()
			tw.tween_interval(0.4)
			tw.tween_property(tap, "position:y", -5.2, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			tap.position.y = -5.2
	if _cage:
		if animate:
			var tc := create_tween()
			tc.tween_interval(1.0)
			tc.tween_property(_cage, "position:y", _cage.position.y + 1.6, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tc.tween_callback(func() -> void: _cage.visible = false)
		else:
			_cage.visible = false
	if _portrait_light:
		if animate:
			create_tween().tween_property(_portrait_light, "light_energy", 1.2, 1.2)
		else:
			_portrait_light.light_energy = 1.2
	# Fix r1b (fun): the jar opened at the start of the 3 s StoryCam_F reveal, so a Mak standing beside it collected
	# HUB-1 under the portrait shot and TRUFFLE GET overlapped the reveal. The jar opens as the camera hands back.
	if animate:
		get_tree().create_timer(3.05).timeout.connect(func() -> void: _set_truffle_locked(false))
	else:
		_set_truffle_locked(false)
	if animate:
		_sfx("chime", _slam_board.global_position)
		ObjSvc.burst(self, HubKit.polar(15.0, 190.0, 10.8), Color(1.0, 0.85, 0.4), 40, 5.0, 0.18, -4.0, 1.2)


# ------------------------------------------------------------------ H-B the rug that baa'd

func _cub_gag() -> void:
	_rug = Node3D.new()
	_rug.name = "SheepskinRug"
	_rug.position = Vector3(-12.0, 0, 0)
	_rug.rotation_degrees.y = 90.0
	add_child(_rug)
	if _flag("hub_cub_done"):
		# R3.2 callback: after the catch the flung costume lies at the hearth as a sheepskin rug.
		_build_fleece(_rug)
		_cub_acorns(Vector3(-10.6, 0, 0))  # any cub-drop acorns not picked up last visit wait by the rug
		return
	for i in 8:
		_register_cub_acorn(i)
	if level and level.has_method("_ledger_refresh"):
		level.call_deferred("_ledger_refresh")
	_rug.visible = false
	_build_fleece(_rug)
	# The impostor (CH-03a, real woolly_wolf model) rests on Book 1's pop-up pages until Mak comes close.
	_cub = Node3D.new()
	_cub.name = "WoollyWolfCub"
	# Fix r2 (QA major): moved from behind the lectern (-7.6, 1.78, 7.6) to the hall-facing page edge, facing the
	# hall, so the first-minute hook is seen from the Default spawn and clear of the HUD.
	_cub.position = Vector3(-6.75, 1.85, 6.75)
	_cub.rotation_degrees.y = -45.0
	add_child(_cub)
	_build_cub_body()
	# Fix r1b (visual minor): a warm key on the diorama so the impostor reads as a cloud-white sheep suit, not a
	# lilac lump against the bright fireplace. Freed when the chase ends.
	var key := OmniLight3D.new()
	key.name = "ImpostorKey"
	key.position = Vector3(-6.4, 3.3, 6.2)
	key.light_color = Color("fff0dc")
	key.light_energy = 0.7
	key.omni_range = 3.6
	key.light_volumetric_fog_energy = 0.0
	add_child(key)
	_impostor_key = key


## The cub drop (8 acorns) counts toward the Library Ledger as one-off flags (r1 QA / fun).
func _register_cub_acorn(i: int) -> void:
	var groups: Dictionary = level.get("_ledger_groups") if level else {}
	groups["AG18"] = maxi(int(groups.get("AG18", 0)), i + 1)


func _cub_acorns(at: Vector3) -> void:
	if level == null or not level.has_method("ledger_acorn"):
		return
	var holder := get_node_or_null("AG18_cub_drop") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "AG18_cub_drop"
		add_child(holder)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var pos := at + Vector3(cos(a) * 1.3, 0.9, sin(a) * 1.3)
		# r1 QA: clamp radially (the hall is round; shelf faces at r 15.2), then step toward the hall centre
		# until a 0.35 m sphere at the acorn is clear of solids, so no acorn spawns inside a shelf or the stair.
		var flat := Vector2(pos.x, pos.z).limit_length(12.6)
		pos = Vector3(flat.x, 0.9, flat.y)
		pos = _clear_spot(pos)
		level.call("ledger_acorn", holder, "AG18_cub_drop", i, pos)


func _clear_spot(pos: Vector3) -> Vector3:
	if not is_inside_tree():
		return pos
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.35
	q.shape = sph
	q.collision_mask = 1
	var p := pos
	for k in 30:
		q.transform = Transform3D(Basis(), p)
		if space.intersect_shape(q, 1).is_empty():
			return p
		var toward := Vector3(-p.x, 0, 1.0 - p.z)
		if toward.length() < 0.5:
			break
		p += toward.normalized() * 0.4
	return Vector3(clampf(pos.x, -4.5, 4.5), 0.9, 5.6)


func _build_fleece(rug: Node3D) -> void:
	# The flung sheep costume as a sheepskin rug (prop P-H01 stand-in). Owner (19 Oct 2026) read the old one, a
	# 16 cm white slab with a gold bar and two grey ears, as a placeholder. Now a low rug with the classic sheepskin
	# outline (four leg flaps), curly wool tufts in warm creams, the costume's floppy hood with its button eyes and
	# the two wolf ears poking out of it. Vertex colours are linear (the toon shader multiplies COLOR as is).
	var b := HubKit.Buf.new()
	b.use_color = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var cream := Color("eadcc0")
	HubKit.rounded_box(b, Vector3(1.3, 0.06, 0.82), 0.03, Transform3D(Basis(), Vector3(0, 0.03, 0)), 2, cream.srgb_to_linear())
	for fx in [-1.0, 1.0]:
		for fz in [-1.0, 1.0]:
			# Leg flaps splayed out at the corners.
			var flap := Transform3D(Basis(Vector3.UP, deg_to_rad(28.0 * fx * fz)), Vector3(fx * 0.62, 0.025, fz * 0.42))
			HubKit.rounded_box(b, Vector3(0.36, 0.05, 0.2), 0.025, flap, 1, cream.darkened(0.04).srgb_to_linear())
	for i in 34:
		var p := Vector3(rng.randf_range(-0.58, 0.5), 0.06, rng.randf_range(-0.36, 0.36))
		var s := rng.randf_range(0.13, 0.2)
		var tone := Color("f4ead6").lerp(Color("d9c6a2"), rng.randf())
		HubKit.rounded_box(b, Vector3(s, 0.07, s * 0.9), s * 0.45, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), 1, tone.srgb_to_linear())
	# The hood at the head end: a woolly cap, a soft grey-brown face patch with two button eyes, and the wolf ears.
	HubKit.rounded_box(b, Vector3(0.34, 0.16, 0.4), 0.08, Transform3D(Basis(), Vector3(0.74, 0.08, 0.0)), 2, Color("f1e6d0").srgb_to_linear())
	HubKit.rounded_box(b, Vector3(0.16, 0.1, 0.24), 0.05, Transform3D(Basis(), Vector3(0.9, 0.06, 0.0)), 1, Color("8a7a6c").srgb_to_linear())
	for ez in [-0.06, 0.06]:
		HubKit.rounded_box(b, Vector3(0.04, 0.03, 0.04), 0.015, Transform3D(Basis(), Vector3(0.97, 0.1, ez)), 1, Color("2b2220").srgb_to_linear())
	for ez in [-1.0, 1.0]:
		HubKit.rounded_box(b, Vector3(0.12, 0.18, 0.07), 0.03, Transform3D(Basis(Vector3.RIGHT, ez * 0.5) * Basis(Vector3.BACK, -0.35), Vector3(0.7, 0.2, ez * 0.13)), 1, Color("6e6a78").srgb_to_linear())
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/toon.gdshader")
	m.set_shader_parameter("albedo", Color.WHITE)
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("triplanar", false)
	m.set_shader_parameter("rim_strength", 0.25)
	m.set_shader_parameter("spec_strength", 0.0)
	HubArchitecture.mi(rug, b.commit(), m, "Fleece")


func _build_cub_body() -> void:
	_cub_visual = Node3D.new()
	_cub_visual.name = "Visual"
	_cub.add_child(_cub_visual)
	# Phase 1 wears the real W1 sheep disguise (woolly_wolf), phase 2 is the cub itself (woolly_wolf_cub).
	var sheep_ps := HubAssets.scene(SHEEP_GLB)
	if sheep_ps:
		_sheep_visual = sheep_ps.instantiate() as Node3D
		_sheep_visual.rotation_degrees.y = 180.0
		_cub_visual.add_child(_sheep_visual)
		# Fix r2 (QA/visual major): the white overlay plus RetroLook's pop made the suit a translucent grey ghost. The
		# real woolly_wolf albedo now shows untouched; only the warm diorama key below helps it read.
	var ps := HubAssets.scene(CUB_GLB)
	if ps:
		_cub_real = ps.instantiate() as Node3D
		_cub_real.rotation_degrees.y = 180.0
		_cub_real.scale = Vector3.ONE * 0.95
		_cub_real.visible = false
		_cub_visual.add_child(_cub_real)
	# Real bone animation on both generated models (r1 fun: they slid around in rest pose).
	_sheep_rig = HubRig.attach(_sheep_visual)
	_cub_rig = HubRig.attach(_cub_real)
	# Warm key so the slate cub never melts into the walnut floor (r1 fun: unreadable at chase distance).
	var rim := OmniLight3D.new()
	rim.name = "CubRim"
	rim.light_color = Color("ffe2b8")
	rim.light_energy = 0.9
	rim.omni_range = 2.6
	rim.position = Vector3(0, 1.6, 0.6)
	rim.shadow_enabled = false
	_cub.add_child(rim)
	# Hurtbox (enemy_hurtbox layer 7) so every player attack can catch it; contact zone for the harmless bump.
	var hurt := Area3D.new()
	hurt.name = "Hurtbox"
	hurt.collision_layer = 1 << 6
	hurt.collision_mask = 0
	hurt.monitorable = true
	hurt.set_script(load("res://scripts/worlds/hub_cub_hurtbox.gd"))
	hurt.set("owner_gag", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.1
	cs.shape = cap
	cs.position = Vector3(0, 0.55, 0)
	hurt.add_child(cs)
	_cub.add_child(hurt)
	var touch := Area3D.new()
	touch.name = "Touch"
	touch.collision_layer = 0
	touch.collision_mask = 1 << 1
	var cs2 := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.6
	cs2.shape = sph
	cs2.position = Vector3(0, 0.5, 0)
	touch.add_child(cs2)
	touch.body_entered.connect(_on_cub_touch)
	_cub.add_child(touch)


func cub_hit(_kind: String) -> bool:
	match _cub_state:
		"run":
			_reveal_cub()
			return true
		"windup", "aim":
			# A hit during the wind-up only makes it sidestep.
			_sidestep()
			return false
		"skid", "dizzy":
			# Fix r2 (fun major): a skilled player caught it 2 s into the duel. The first opening only knocks it
			# back (dodge lesson learnt once); the second catches it.
			_duel_hits += 1
			if _duel_hits < 2:
				_sfx("wolf_cub_yelp", _cub.global_position)
				if ResourceLoader.exists("res://scenes/fx/HitStars.tscn"):
					FxEffect.spawn(self, "res://scenes/fx/HitStars.tscn", _cub.global_position + Vector3(0, 1.0, 0))
				var away := _cub.global_position - _player.global_position
				away.y = 0.0
				if away.length() > 0.05:
					var kb := away.normalized() * 1.6
					var tw := create_tween()
					tw.tween_property(_cub, "global_position", _cub.global_position + kb * _cub_free(kb), 0.25)
				_bubble(_cub, "Ow! Best of three, bacon!", 1.4)
				_set_cub_state("aim")
				_state_t = -0.6
				return true
			_catch_cub()
			return true
	return false


func _reveal_cub() -> void:
	_phase = 2
	if _cue_arrow:
		_cue_arrow.visible = false
	print("[Hub] GAG_rug_cub revealed")
	_sfx("costume_rip", _cub.global_position)
	_sfx("wolf_growl", _cub.global_position)
	if _sheep_visual:
		_sheep_visual.visible = false
	if _cub_real:
		_cub_real.visible = true
	ObjSvc.burst(self, _cub.global_position + Vector3(0, 0.6, 0), Color(1.0, 0.98, 0.92), 30, 4.0, 0.25, -6.0, 1.0)
	# The costume lands as the rug wherever it burst.
	if _rug:
		_rug.global_position = _cub.global_position + Vector3(0.6, 0, 0.4)
		_rug.rotation_degrees = Vector3(0, randf() * 360.0, 0)
		_rug.visible = true
	_bubble(_cub, "GRRR!", 1.2)
	_set_cub_state("aim")


func _sidestep() -> void:
	var side := _cub.global_basis.x * (1.0 if randf() < 0.5 else -1.0)
	var free := _cub_free(side * 1.2)
	if free < 0.3:
		side = -side
		free = _cub_free(side * 1.2)
	if free < 0.05:
		return
	var tw := create_tween()
	tw.tween_property(_cub, "global_position", _cub.global_position + side * 1.2 * free, 0.3)


## Fraction (0-1) of `motion` the cub's body (sphere r 0.42 at knee-to-chest height) can travel without entering
## solid geometry (r1 QA: the cub charged through the stair and the globe). Starting inside something returns 0.
func _cub_free(motion: Vector3) -> float:
	if _cub == null or motion.length() < 0.0001:
		return 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.42
	q.shape = sph
	q.transform = Transform3D(Basis(), _cub.global_position + Vector3(0, 0.62, 0))
	q.motion = motion
	q.collision_mask = CUB_MASK
	var r := get_world_3d().direct_space_state.cast_motion(q)
	if r.size() < 2:
		return 1.0
	return float(r[0])


func _set_cub_state(st: String) -> void:
	_cub_state = st
	_state_t = 0.0
	_set_chase_cam(st in ["run", "aim", "windup", "charge", "skid", "dizzy"])
	if _lane and st != "windup" and st != "charge":
		_lane.visible = false
	if _dizzy_stars:
		_dizzy_stars.visible = st == "dizzy"


func _on_cub_touch(body: Node) -> void:
	if _cub_state in ["rug", "waking", "caught", "gone"] or _cub_contact_cd > 0.0 or not body.is_in_group("player"):
		return
	_cub_contact_cd = 0.6
	var away := (body as Node3D).global_position - _cub.global_position
	away.y = 0.0
	if body.has_method("add_impulse"):
		body.call("add_impulse", away.normalized() * (4.0 if _phase == 1 else 6.0) + Vector3(0, 2.0, 0))
	_sfx("wolf_cub_yelp", _cub.global_position)


func _wake_cub() -> void:
	_cub_state = "waking"
	print("[Hub] GAG_rug_cub woke")
	if _impostor_key:
		var kt := create_tween()
		kt.tween_property(_impostor_key, "light_energy", 0.0, 1.0)
		kt.tween_callback(_impostor_key.queue_free)
		_impostor_key = null
	_sfx("wolf_cub_baa", _rug.global_position)
	var bubble := Label3D.new()
	bubble.text = "Baa?"
	bubble.font_size = 72
	bubble.pixel_size = 0.005
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.outline_size = 14
	bubble.modulate = Color("3b2416")
	bubble.outline_modulate = Color(1, 0.96, 0.86)
	bubble.position = Vector3(0, 1.6, 0)
	_cub.add_child(bubble)
	_set_book1_armed(false)
	var tw := create_tween()
	# Snatch the bookmark and hop off the back of the book to J0, then run.
	tw.tween_interval(0.4)
	tw.tween_callback(func() -> void: bubble.text = "Baa! (This bookmark is mine.)")
	tw.tween_property(_cub, "position", Vector3(-9.0, 0.0, 9.4), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_cub_visual, "position:y", 0.6, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.2)
	tw.tween_callback(func() -> void:
		var bram: Node3D = level.get("bramwell") as Node3D if level else null
		if bram:
			_bubble(bram, "I say! My teacup!", 2.0)
		bubble.queue_free()
		_set_cub_state("run")
		_run_t = 0.0
		_cub_i = 13)


func _bubble(n: Node3D, text: String, secs: float) -> void:
	# r1 fun: Label3D bubbles could not be read at gameplay distance; the screen-space bark UI can.
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("bark") and n:
		ui.call("bark", n, text, secs, {"height": 2.05})
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 14
	l.modulate = Color("3b2416")
	l.outline_modulate = Color(1, 0.96, 0.86)
	l.position = Vector3(0, 2.05, 0)
	n.add_child(l)
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(l.queue_free)


func _catch_cub() -> void:
	if _cub_state in ["caught", "gone", "rug", "waking"]:
		return
	_set_cub_state("caught")
	print("[Hub] GAG_rug_cub caught")
	_sfx("wolf_cub_yelp", _cub.global_position)
	if ResourceLoader.exists("res://scenes/fx/Confetti.tscn"):
		FxEffect.spawn(self, "res://scenes/fx/Confetti.tscn", _cub.global_position + Vector3(0, 0.6, 0))
	_cub_acorns(_cub.global_position)
	_unlock("hub_cub_done")
	_unlock("hat_bowler")
	_set_book1_armed(true)
	var tw := create_tween()
	tw.tween_property(_cub_visual, "rotation:y", TAU * 4.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _set_cub_state("gone"))
	_say(["My teacup! And a bowler for your trouble, sir. I shall hang it on the hat stand by the doors."], "Bramwell")


func _process(delta: float) -> void:
	_t += delta
	_tea_process(delta)
	for g in get_tree().get_nodes_in_group("hub_glint"):
		(g as Node3D).scale = Vector3.ONE * (0.6 + 0.6 * maxf(0.0, sin(_t * 2.3)))
	for h in get_tree().get_nodes_in_group("hub_spin_hat"):
		(h as Node3D).rotation.y += delta * 1.5
	if _player == null:
		return
	_cub_contact_cd = maxf(0.0, _cub_contact_cd - delta)
	# The slam board rattles when Mak walks on it.
	if _slam_board and not _revealed and _player.global_position.distance_to(_slam_board.global_position) < 0.7:
		_slam_board.rotation_degrees.z = sin(_t * 40.0) * 1.5
	if _cub == null:
		return
	_animate_cub(delta)
	match _cub_state:
		"rug":
			_cub_ear_t -= delta
			var to_p := _player.global_position - _cub.global_position
			_cub.rotation.y = lerp_angle(_cub.rotation.y, atan2(-to_p.x, -to_p.z), minf(1.0, delta * 2.0))
			if _cub_ear_t <= 0.0:
				_cub_ear_t = 6.0
				if to_p.length() < 10.0:
					_sfx("wolf_cub_baa", _cub.global_position)
					_bubble(_cub, "Baa.", 1.0)
			var dbook := Vector2(_player.global_position.x + 7.07, _player.global_position.z - 7.07).length()
			# Fix r2 (QA major): the wake used x/z distance only, so the chase started under a Mak 4-8 m up on the
			# spiral, the chimney foot or the gallery. Above the floor level the impostor neither arms nor wakes.
			var low := _player.global_position.y < 2.6  # floor and the book page (1.85); the gallery starts at 4.3
			# Edge trigger: spawning beside Book 1 (Return to library, Continue) must not disarm it;
			# the gag starts only when Mak walks in from beyond 6.5 m.
			# Also arm once Mak walks 1 m closer than where he appeared (Test_Cub spawns 5.9 m out).
			if _cub_spawn_d < 0.0:
				_cub_spawn_d = dbook
			if low and (dbook > 6.5 or dbook < _cub_spawn_d - 1.0):
				_cub_arm_ready = true
			if low and dbook < 4.8 and _cub_arm_ready:
				_wake_cub()
		"run":
			_run_t += delta
			_dodge_cd = maxf(0.0, _dodge_cd - delta)
			if _cub_pause > 0.0:
				_cub_pause -= delta
				_cub_visual.rotation.z = sin(_t * 12.0) * 0.15
				return
			# Dodge jabs: a grounded Mak within 1.4 m who is not diving, sliding or long jumping gets side-stepped.
			var pst := String(_player.call("get_state_name")) if _player.has_method("get_state_name") else ""
			var near := _player.global_position.distance_to(_cub.global_position) < 1.4 and absf(_player.global_position.y - _cub.global_position.y) < 0.5
			# Fix r1b (fun): the dodge only answers a jab from behind or beside. A Mak who cut the corner and waits
			# ahead of the sheep gets his hit, which is exactly the lesson Bramwell's corner cue teaches.
			var cub_fwd := (CUB_LOOP[_cub_i] as Vector3) - _cub.global_position
			cub_fwd.y = 0.0
			var to_mak := _player.global_position - _cub.global_position
			to_mak.y = 0.0
			var ahead := cub_fwd.length() > 0.05 and to_mak.length() > 0.05 and cub_fwd.normalized().dot(to_mak.normalized()) > 0.35
			if _dodge_cd <= 0.0 and near and not ahead and not pst in ["dive", "crouch_slide", "slide", "long_jump", "jump_kick", "ham_slam"]:
				_dodge_cd = 2.0
				_sidestep()
				_sfx("wolf_cub_baa", _cub.global_position)
			# r1 fun round 2: the first beat of the game must not drag. After 12 s with no hit Bramwell points at the
			# corner cut and a gold arrow marks the next corner; after 35 s (was 75) the sheep trips at its next corner.
			if _run_t > 12.0 and not _cue_shown:
				_cue_shown = true
				_corner_cue()
			if _cue_arrow and _cue_arrow.visible:
				_update_corner_cue()
			# Fix r2 (fun minor): a newcomer stuck behind the clock drum made no progress for 5 s while the sheep
			# orbited. With the drum between them for 2 s the sheep stops, turns and taunts, a free chance to close in.
			var seg_q := Geometry3D.get_closest_point_to_segment(Vector3(0, 0, 1.0), Vector3(_player.global_position.x, 0, _player.global_position.z), Vector3(_cub.global_position.x, 0, _cub.global_position.z))
			if seg_q.distance_to(Vector3(0, 0, 1.0)) < 1.7 and _player.global_position.y < 1.0:
				_blocked_t += delta
			else:
				_blocked_t = 0.0
			if _blocked_t > 2.0:
				_blocked_t = -4.0
				_cub_pause = 1.2
				var tm := _player.global_position - _cub.global_position
				_cub.rotation.y = atan2(-tm.x, -tm.z)
				_bubble(_cub, "Baa-ha-ha!", 1.0)
				return
			if _run_t > 35.0 and not _tripped and CORNERS.has(_cub_i) and (CUB_LOOP[_cub_i] - _cub.global_position).length() < 0.6:
				_tripped = true
				_cub_pause = 3.0
				_bubble(_cub, "Oof! Tripped on my own wool...", 2.5)
				return
			var target: Vector3 = CUB_LOOP[_cub_i]
			var d := target - _cub.global_position
			d.y = 0.0
			# r1 fun round 2: 7.7 m/s (R3.2's 77.6 m loop in 10.05 s) from the start, 6.8 m/s after 20 s (was 8.6 for 40 s).
			var cruise := 7.7 if _run_t < 20.0 else 6.8
			var spd := 5.0 if (CORNERS.has(_cub_i) and d.length() < 1.0) else cruise
			var step := spd * delta
			if d.length() <= step:
				_cub.global_position = Vector3(target.x, 0.0, target.z)
				_cub_i = (_cub_i + 1) % CUB_LOOP.size()
				if _run_t > 20.0 and (_cub_i == 4 or _cub_i == 10):
					_cub_pause = 0.8
					_bubble(_cub, "Baa-ha-ha!", 0.8)
			else:
				_cub.global_position += d.normalized() * step
				_cub.rotation.y = lerp_angle(_cub.rotation.y, atan2(-d.x, -d.z), minf(1.0, delta * 12.0))
			# r1 fun minor: the bone run cycle carries the motion now, so the whole-body bob and roll are halved.
			_cub_visual.position.y = absf(sin(_t * 14.0)) * 0.06
			_cub_visual.rotation.z = sin(_t * 14.0) * 0.05
		"aim", "windup", "charge", "skid", "dizzy":
			_cub_phase2(delta)
		"gone":
			var exit := Vector3(0, 0, 15.6)
			var d2 := exit - _cub.global_position
			d2.y = 0.0
			if d2.length() < 0.4:
				_cub.queue_free()
				_cub = null
				return
			_cub.global_position += d2.normalized() * 7.0 * delta
			_cub.rotation.y = atan2(-d2.x, -d2.z)
			_cub_visual.position.y = absf(sin(_t * 16.0)) * 0.15


## Phase 2: aim (1.2 s, trots closer if far) -> wind-up (0.6 s) -> straight charge at 9 m/s for up to 8 m -> skid (1 s),
## or dizzy (1.6 s) when the charge ends against something. Hits during the skid or the dizzy spell catch it.
func _cub_phase2(delta: float) -> void:
	_state_t += delta
	_phase2_t += delta
	var to_mak := _player.global_position - _cub.global_position
	to_mak.y = 0.0
	match _cub_state:
		"aim":
			if to_mak.length() > 0.1:
				_cub.rotation.y = lerp_angle(_cub.rotation.y, atan2(-to_mak.x, -to_mak.z), minf(1.0, delta * 8.0))
			# Trot closer only while Mak is on the floor; up the stairs or on furniture the cub waits and taunts.
			var mak_up := _player.global_position.y > _cub.global_position.y + 1.5
			if to_mak.length() > 7.0 and not mak_up:
				var mv := to_mak.normalized() * 4.0 * delta
				_cub.global_position += mv * _cub_free(mv)
			elif mak_up and fmod(_state_t, 1.5) < delta:
				_bubble(_cub, "Come down here, bacon!", 0.9)
			_cub_visual.position.y = absf(sin(_t * 9.0)) * 0.06
			if _state_t >= 1.2 and not mak_up:
				_set_cub_state("windup")
				_charge_dir = to_mak.normalized() if to_mak.length() > 0.1 else -_cub.global_basis.z
				_sfx("wolf_charge", _cub.global_position)
				_telegraph()
		"windup":
			_cub_visual.rotation.z = sin(_t * 40.0) * 0.08
			_cub_visual.position.y = 0.0
			if fmod(_state_t, 0.2) < delta:
				ObjSvc.burst(self, _cub.global_position - _charge_dir * 0.4 + Vector3(0, 0.1, 0), Color(0.85, 0.78, 0.66), 5, 1.2, 0.18, -3.0, 0.5)
			if _state_t >= 0.8:
				# Charge: up to 8 m; the body is swept every frame, so a wall, stair or globe ends it in a bonk.
				_charge_blocked = _phase2_t > 15.0  # failsafe: after 15 s every charge ends in a bonk
				_charge_left = 8.0
				_set_cub_state("charge")
		"charge":
			var step := minf(9.0 * delta, _charge_left)
			var fr := _cub_free(_charge_dir * step)
			_cub.global_position += _charge_dir * step * fr
			_charge_left -= step
			if fr < 0.999:
				_charge_blocked = true
				_charge_left = 0.0
			_cub.rotation.y = atan2(-_charge_dir.x, -_charge_dir.z)
			_cub_visual.position.y = absf(sin(_t * 20.0)) * 0.1
			if _charge_left <= 0.001:
				if _charge_blocked:
					_sfx("bonk", _cub.global_position)
					if ResourceLoader.exists("res://scenes/fx/HitStars.tscn"):
						FxEffect.spawn(self, "res://scenes/fx/HitStars.tscn", _cub.global_position + Vector3(0, 1.0, 0))
					_ensure_stars()
					_set_cub_state("dizzy")
					_bubble(_cub, "BONK!", 0.9)
					_state_t = -0.8 if _phase2_t > 15.0 else 0.0
				else:
					_set_cub_state("skid")
					_bubble(_cub, "Whoa-oa!", 0.9)
		"skid":
			_cub_visual.rotation.x = -0.2
			if _state_t < 0.5:
				var sk := _charge_dir * (4.0 * (1.0 - _state_t / 0.5)) * delta
				_cub.global_position += sk * _cub_free(sk)
			if _state_t >= 1.6:
				_cub_visual.rotation.x = 0.0
				_set_cub_state("aim")
		"dizzy":
			_cub_visual.rotation.z = sin(_t * 6.0) * 0.2
			if _dizzy_stars:
				_dizzy_stars.rotation.y += delta * 6.0
			if _state_t >= 2.4:
				_cub_visual.rotation.z = 0.0
				_set_cub_state("aim")


## Bone poses for the impostor sheep (phase 1) and the cub (phase 2), per state (r1 fun: R3.2 clips).
func _animate_cub(delta: float) -> void:
	var rig := _cub_rig if (_cub_real and _cub_real.visible) else _sheep_rig
	if rig == null:
		return
	var t := _t
	var p: Dictionary = {}
	match _cub_state:
		"rug":
			# Standing in the diorama: a smug graze with a sideways glance, ears twitching.
			p = {"head": Vector3(-0.25 + sin(t * 7.0) * 0.05, sin(t * 0.7) * 0.35, 0), "jaw": Vector3(maxf(0.0, sin(t * 7.0)) * 0.2, 0, 0),
				"arm_l": Vector3(0, 0, 0.6), "arm_r": Vector3(0, 0, -0.6), "ear_l": Vector3(sin(t * 3.1) * 0.3, 0, 0.2),
				"ear_r": Vector3(sin(t * 2.7 + 1.0) * 0.3, 0, -0.2), "tail": Vector3(0.2, sin(t * 5.0) * 0.4, 0), "body": Vector3(0.12, 0, 0)}
		"waking":
			# Snatch the bookmark: arms up, head back, then a crouch before the hop.
			p = {"arm_l": Vector3(-1.6, 0, 0.3), "arm_r": Vector3(-1.2, 0, -0.3), "head": Vector3(0.3, 0, 0), "jaw": Vector3(0.45, 0, 0),
				"leg_l": Vector3(0.5, 0, 0), "leg_r": Vector3(0.5, 0, 0), "shin_l": Vector3(-0.8, 0, 0), "shin_r": Vector3(-0.8, 0, 0)}
		"run", "gone", "caught":
			if _cub_pause > 0.0:
				p = {"head": Vector3(0.2, sin(t * 10.0) * 0.4, 0), "jaw": Vector3(0.5, 0, 0), "arm_l": Vector3(-0.8, 0, 0.9),
					"arm_r": Vector3(-0.8, 0, -0.9), "tail": Vector3(0.3, sin(t * 14.0) * 0.6, 0)}
			else:
				p = HubRig.run_pose(t, 3.0)
		"aim":
			# Prowl: low crouch, head on Mak, a paw scrape every second.
			p = {"body": Vector3(0.3, 0, 0), "head": Vector3(-0.25, 0, 0), "ear_l": Vector3(0.5, 0, 0.3), "ear_r": Vector3(0.5, 0, -0.3),
				"arm_l": Vector3(-0.35, 0, 0.45), "arm_r": Vector3(-0.35, 0, -0.45), "leg_l": Vector3(0.35, 0, 0), "leg_r": Vector3(0.35, 0, 0),
				"shin_l": Vector3(-0.6, 0, 0), "shin_r": Vector3(-0.6 + maxf(0.0, sin(t * 6.0)) * 0.5, 0, 0), "jaw": Vector3(0.2, 0, 0),
				"tail": Vector3(-0.3, sin(t * 11.0) * 0.2, 0)}
		"windup":
			# Crouch and scrape: spine pitched 25 deg, back paw scraping fast, snarl.
			p = {"body": Vector3(0.44, 0, 0), "head": Vector3(-0.35, 0, sin(t * 18.0) * 0.05), "jaw": Vector3(0.4 + sin(t * 20.0) * 0.08, 0, 0),
				"ear_l": Vector3(0.6, 0, 0.4), "ear_r": Vector3(0.6, 0, -0.4), "arm_l": Vector3(-0.9, 0, 0.3), "arm_r": Vector3(-0.9, 0, -0.3),
				"leg_l": Vector3(0.3, 0, 0), "leg_r": Vector3(-0.3 + sin(t * 22.0) * 0.6, 0, 0), "shin_l": Vector3(-0.5, 0, 0),
				"tail": Vector3(-0.9, sin(t * 20.0) * 0.25, 0)}
		"charge":
			p = HubRig.run_pose(t, 4.6, 1.2)
			p["body"] = Vector3(0.55, 0, 0)
			p["head"] = Vector3(-0.3, 0, 0)
			p["ear_l"] = Vector3(0.9, 0, 0.3)
			p["ear_r"] = Vector3(0.9, 0, -0.3)
			p["tail"] = Vector3(-1.0, sin(t * 18.0) * 0.12, 0)
		"skid":
			p = {"body": Vector3(-0.45, 0, 0), "head": Vector3(0.35, 0, 0), "jaw": Vector3(0.55, 0, 0), "arm_l": Vector3(-1.8 + sin(t * 16.0) * 0.6, 0, 0.4),
				"arm_r": Vector3(-1.8 - sin(t * 16.0) * 0.6, 0, -0.4), "leg_l": Vector3(-0.7, 0, 0), "leg_r": Vector3(-0.5, 0, 0)}
		"dizzy":
			p = {"head": Vector3(sin(t * 4.0) * 0.25, sin(t * 3.0) * 0.35, sin(t * 5.0) * 0.2), "jaw": Vector3(0.35, 0, 0),
				"ear_l": Vector3(sin(t * 7.0) * 0.6, 0, 0.3), "ear_r": Vector3(-sin(t * 7.0) * 0.6, 0, -0.3),
				"arm_l": Vector3(0.2, 0, 1.0 + sin(t * 5.0) * 0.25), "arm_r": Vector3(0.2, 0, -1.0 - sin(t * 5.0) * 0.25),
				"leg_l": Vector3(0.2, 0, 0.15), "leg_r": Vector3(0.2, 0, -0.15)}
	rig.pose(p, delta, 16.0)


## r1 fun round 2: the corner-cut cue. Bramwell's cub_hint plus a bobbing gold floor arrow at the sheep's next
## corner waypoint, pointing along its exit, so the player sees where to cut across and wait.
func _corner_cue() -> void:
	var bram: Node3D = level.get("bramwell") as Node3D if level else null
	if bram:
		_bubble(bram, "That sheep has your bookmark, sir. I am told wolves are poor at corners.", 4.0)
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.call("toast", "Cut the corner and wait for the sheep!")
	_cue_arrow = Node3D.new()
	_cue_arrow.name = "CornerCue"
	add_child(_cue_arrow)
	var b := HubKit.Buf.new()
	HubKit.rounded_box(b, Vector3(0.5, 0.05, 1.0), 0.02, Transform3D(Basis(), Vector3(0, 0.0, 0.25)))
	for k in 6:
		var w := 1.1 * (1.0 - float(k) / 6.0)
		HubKit.rounded_box(b, Vector3(maxf(w, 0.1), 0.05, 0.12), 0.02, Transform3D(Basis(), Vector3(0, 0.0, -0.3 - float(k) * 0.1)))
	HubArchitecture.mi(_cue_arrow, b.commit(), HubKit.emissive(Color("ffc93c"), 1.6, "corner_cue"), "Arrow", Transform3D.IDENTITY, false)
	_update_corner_cue()


func _update_corner_cue() -> void:
	if _cue_arrow == null:
		return
	var nxt := -1
	for k in CUB_LOOP.size():
		var i := (_cub_i + k) % CUB_LOOP.size()
		if CORNERS.has(i):
			nxt = i
			break
	if nxt < 0:
		return
	var here: Vector3 = CUB_LOOP[nxt]
	var after: Vector3 = CUB_LOOP[(nxt + 1) % CUB_LOOP.size()]
	var dir := after - here
	dir.y = 0.0
	var at := here + Vector3(0, 0.06 + absf(sin(_t * 4.0)) * 0.12, 0)
	_cue_arrow.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), at)
	_cue_arrow.visible = _cub_state == "run"


## Charge telegraph (r1 fun): a red "!" pop, a dust ring, and a faint 8 m charge lane on the floor.
func _telegraph() -> void:
	ObjSvc.burst(self, _cub.global_position + Vector3(0, 0.15, 0), Color(0.85, 0.78, 0.66), 18, 2.5, 0.22, -4.0, 0.7)
	if _bang == null:
		_bang = Label3D.new()
		_bang.text = "!"
		_bang.font_size = 160
		_bang.pixel_size = 0.006
		_bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bang.no_depth_test = true
		_bang.modulate = Color("e8352c")
		_bang.outline_size = 24
		_bang.outline_modulate = Color(1, 0.96, 0.86)
		_bang.position = Vector3(0, 1.75, 0)
		_cub.add_child(_bang)
	_bang.visible = true
	_bang.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_bang, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	tw.tween_callback(func() -> void: _bang.visible = false)
	if _lane == null:
		_lane = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.0, 8.0)
		qm.orientation = PlaneMesh.FACE_Y
		_lane.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.95, 0.25, 0.2, 0.28)
		_lane.material_override = m
		_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_lane)
	var start := _cub.global_position
	var ln := 8.0 * _cub_free(_charge_dir * 8.0)
	(_lane.mesh as QuadMesh).size = Vector2(0.9, maxf(ln, 0.6))
	_lane.global_transform = Transform3D(Basis(Vector3.UP, atan2(-_charge_dir.x, -_charge_dir.z)), start + _charge_dir * (ln * 0.5) + Vector3(0, 0.03, 0))
	_lane.visible = true


func _ensure_stars() -> void:
	if _dizzy_stars:
		_dizzy_stars.visible = true
		return
	_dizzy_stars = Node3D.new()
	_dizzy_stars.position = Vector3(0, 1.25, 0)
	_cub.add_child(_dizzy_stars)
	for k in 4:
		var a := TAU * float(k) / 4.0
		var st := HubArchitecture.mi(_dizzy_stars, SphereMesh.new(), HubKit.emissive(Color(1.0, 0.85, 0.3), 2.0, "dizzy_star"), "Star")
		(st.mesh as SphereMesh).radius = 0.07
		(st.mesh as SphereMesh).height = 0.14
		st.position = Vector3(cos(a) * 0.35, 0, sin(a) * 0.35)


# ------------------------------------------------------------------ H-C Bramwell's Tea Run (R2.4)

const TEA_RINGS := [[Vector3(-1.79, 2.9, 6.06), 0.9], [Vector3(-3.24, 4.3, -1.19), 0.9], [Vector3(-2.6, 0.7, -10.6), 0.6], [Vector3(3.6, 4.5, -8.25), 0.9],
	[Vector3(0, 5.5, -13.2), 0.9], [Vector3(-13.46, 5.5, -3.86), 0.9], [Vector3(-13.3, 5.5, 2.83), 0.9], [Vector3(2.0, 1.2, 5.6), 0.9]]
## R3.7: two targets. Warm (27.0 s) wins the tea cosy, Piping Hot (19.5 s) the gold pom-pom. The countdown shows Warm.
const TEA_LIMIT := 27.0
const TEA_HOT := 19.5
var _tea_rings: Array[Node3D] = []
var _tea_next := -1
var _tea_t := 0.0
var _tea_running := false


func chase_active() -> bool:
	return _cub != null and _cub_state in ["waking", "run", "aim", "windup", "charge", "skid", "dizzy"]


func tea_available() -> bool:
	var g := _game()
	var n := int(g.call("truffle_count")) if g and g.has_method("truffle_count") else 0
	return (n >= 3 or _unlock_all() or bool(get_node_or_null("/root/Dev").call("has_arg", "hub-tea"))) and not _cub_state in ["run", "aim", "windup", "charge", "skid", "dizzy"]


## r1 fun + QA: every talk with Bramwell after 3 truffles used to teleport Mak and start the trial. The Tea Run now
## starts only from its own teacup stand (TT_tea_start) with an explicit interact, never while a dialog is open.
const TEA_START := Vector3(-0.6, 0, 12.4)
var _tea_stand: Node3D
var _tea_prompt := false


func _tea_run_setup() -> void:
	_tea_stand = Node3D.new()
	_tea_stand.name = "TT_tea_start"
	_tea_stand.position = TEA_START + Vector3(-1.1, 0, 0.5)
	add_child(_tea_stand)
	var b := HubKit.Buf.new()
	HubKit.turned(b, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.26, 0.0), Vector2(0.26, 0.05), Vector2(0.07, 0.12), Vector2(0.05, 0.85),
		Vector2(0.3, 0.88), Vector2(0.3, 0.93), Vector2(0.0, 0.95)]), 18)
	HubArchitecture.mi(_tea_stand, b.commit(), HubArchitecture.flat_toon(Color("6a3b22"), 0.5, 0.25), "Stand")
	var cup := HubKit.Buf.new()
	HubKit.turned(cup, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.11, 0.05), Vector2(0.12, 0.12), Vector2(0.11, 0.13), Vector2(0.0, 0.1)]), 16, Vector3(0, 0.95, 0))
	HubKit.lathe(cup, HubKit.round_rect_profile(0.0, 0.18, 0.95, 0.97, 0.0, 0.0, 0.01, 0.01), 0.0, 360.0, 15.0, true, false)
	HubArchitecture.mi(_tea_stand, cup.commit(), HubArchitecture.flat_toon(Color("f4ead6"), 0.5, 0.4), "Teacup")
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.85, 0.5)
	gl.light_energy = 0.0
	gl.omni_range = 2.0
	gl.position = Vector3(0, 1.3, 0)
	gl.name = "Glow"
	_tea_stand.add_child(gl)
	var body := HubArchitecture.static_body(_tea_stand, "Collision")
	HubKit.add_box_collision(body, null, Vector3(0.5, 0.95, 0.5), Transform3D(Basis(), Vector3(0, 0.475, 0)))
	_tea_stand.visible = tea_available()


func _tea_stand_process() -> void:
	if _tea_stand == null or _player == null:
		return
	var avail := tea_available()
	_tea_stand.visible = avail or _tea_running
	var gl := _tea_stand.get_node_or_null("Glow") as OmniLight3D
	if gl:
		gl.light_energy = (0.8 + 0.4 * sin(_t * 3.0)) if avail and not _tea_running else 0.0
	var near := avail and not _tea_running and _player.global_position.distance_to(_tea_stand.global_position) < 1.6
	var ui := get_node_or_null("/root/UI")
	if near != _tea_prompt:
		_tea_prompt = near
		if ui and ui.has_method("show_prompt"):
			if near:
				var g := _game()
				var best := float(g.call("best_time", "hub_tea")) if g and g.has_method("best_time") else INF
				ui.call("show_prompt", "interact", "Bramwell's Tea Run" + ("  (best %.1f s)" % best if best < 999.0 else ""))
			else:
				ui.call("hide_prompt")
	if near and Input.is_action_just_pressed("interact") and not (ui and ui.has_method("is_dialog_open") and bool(ui.call("is_dialog_open"))):
		if ui and ui.has_method("hide_prompt"):
			ui.call("hide_prompt")
		_tea_prompt = false
		_start_tea_run()


func _start_tea_run() -> void:
	if _player == null:
		return
	_tea_running = true
	print("[Hub] TT_tea_run start")
	if _player.has_method("respawn"):
		_player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(11.3)), TEA_START))
	_set_tea_suspensions(true)
	var ring_ps := HubAssets.scene("res://scenes/objects/TrialRing.tscn")
	for i in TEA_RINGS.size():
		var r := ring_ps.instantiate() as Node3D
		r.name = "TR%d" % (i + 1)
		r.set("radius", float(TEA_RINGS[i][1]))
		r.set("spin", false)
		r.set("active", i == 0)
		add_child(r)
		var here: Vector3 = TEA_RINGS[i][0]
		var nxt: Vector3 = TEA_RINGS[mini(i + 1, TEA_RINGS.size() - 1)][0] if i < TEA_RINGS.size() - 1 else here + (here - (TEA_RINGS[i - 1][0] as Vector3))
		var dir := nxt - here
		dir.y = 0.0
		r.global_position = here
		if dir.length() > 0.1:
			r.look_at(here + dir, Vector3.UP)
		r.connect("passed", _on_tea_ring.bind(i))
		_tea_rings.append(r)
	_tea_next = 0
	_tea_t = -3.0
	var ui := get_node_or_null("/root/UI")
	if ui:
		ui.call("toast", "Bramwell's Tea Run: 3... 2... 1...")


func _on_tea_ring(_ring: Node, i: int) -> void:
	if not _tea_running or _tea_t < 0.0:
		return
	if i != _tea_next:
		return
	_sfx("ring_pass", _tea_rings[i].global_position)
	_tea_next += 1
	if _tea_next < _tea_rings.size():
		_tea_rings[_tea_next].call("set_active", true)
	else:
		_end_tea_run(true)


func _end_tea_run(won: bool) -> void:
	_tea_running = false
	var ui := get_node_or_null("/root/UI")
	var t := _tea_t
	if ui:
		ui.call("timer_stop")
		ui.call("timer_hide")
	for r in _tea_rings:
		r.queue_free()
	_tea_rings.clear()
	_set_tea_suspensions(false)
	var finished := won
	won = won and t <= TEA_LIMIT
	print("[Hub] TT_tea_run %s in %.2f s" % ["WON" if won else "lost", t])
	var g := _game()
	var record := false
	if finished and g and g.has_method("record_time"):
		record = bool(g.call("record_time", "hub_tea", t))
	var rec_line := " A new best, %.1f s." % t if record else ""
	if won and t <= TEA_HOT:
		_unlock("hat_teacosy")
		_unlock("hat_teacosy_gold")
		_say(["Scalding, sir. %.1f seconds. Grandfather's record, beaten. The pom-pom is yours.%s" % [t, rec_line]], "Bramwell")
	elif won:
		_unlock("hat_teacosy")
		_say(["Still warm, sir: %.1f seconds. The tea cosy is yours, on the hat stand.%s" % [t, rec_line], "Under %.1f and it would be piping hot." % TEA_HOT], "Bramwell")
	elif finished:
		_say(["%.1f s too cool, sir. Shall we try again?%s" % [t - TEA_LIMIT, rec_line]], "Bramwell")
	else:
		_say(["Lukewarm, sir. Shall we try again?"], "Bramwell")


## R2.4: during the run every book trigger, the Wolf's Door trigger and the bellows updraft are suspended.
func _set_tea_suspensions(on: bool) -> void:
	var portals: Dictionary = level.get("portals") if level else {}
	for wid in portals.keys():
		if wid == "W1" and _phase == 2 and _cub_state != "gone" and not on:
			continue  # the impostor still holds Book 1's bookmark
		_set_portal_zone(portals[wid] as Node, not on)
	var door: Node = level.get("wolf_door") if level else null
	if door:
		for zn in ["_near_zone", "_enter_zone"]:
			var z := door.get(zn) as Area3D
			if z:
				z.set_deferred("monitoring", not on)
	var up := get_node_or_null("WZ_book1_updraft")
	if up and up.has_method("set_enabled"):
		up.call("set_enabled", not on)


func _set_portal_zone(portal: Node, on: bool) -> void:
	if portal == null:
		return
	var z := portal.get("_zone") as Area3D
	if z:
		z.set_deferred("monitoring", on)
	else:
		portal.set("route_on_enter", on)


func _tea_process(delta: float) -> void:
	_tea_stand_process()
	if not _tea_running:
		return
	var before := _tea_t
	_tea_t += delta
	if before < 0.0 and _tea_t >= 0.0:
		var ui := get_node_or_null("/root/UI")
		if ui:
			ui.call("timer_start", "Tea Run", TEA_LIMIT)
		_sfx("chime")
	if _tea_t > TEA_LIMIT + 13.0:  # finish late and Bramwell tells you by how much
		_end_tea_run(false)


## While the impostor holds Book 1's bookmark the page trigger is suspended (R3.2 chase rules).
## r1 QA: route_on_enter=false still played the full dive effect, so landing on Book 1 mid-chase looked like a
## dive that did nothing. Now the page trigger itself is off and a hub page area bounces Mak back up with a card.
var _book1_bounce: Area3D


func _set_book1_armed(on: bool) -> void:
	var portals: Dictionary = level.get("portals") if level else {}
	var b1: Node3D = portals.get("W1") as Node3D
	if b1:
		_set_portal_zone(b1, on)
		b1.set("route_on_enter", true)
		if not on and _book1_bounce == null:
			_book1_bounce = Area3D.new()
			_book1_bounce.name = "Book1ChaseBounce"
			_book1_bounce.collision_layer = 1 << 7
			_book1_bounce.collision_mask = 1 << 1
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(3.0, 1.2, 2.0) * float(b1.get("scale_factor") if b1.get("scale_factor") != null else 1.0)
			cs.shape = bx
			cs.position = Vector3(0, 3.3, -0.1) * float(b1.get("scale_factor") if b1.get("scale_factor") != null else 1.0)
			_book1_bounce.add_child(cs)
			b1.add_child(_book1_bounce)
			_book1_bounce.body_entered.connect(func(body: Node) -> void:
				if not body.is_in_group("player"):
					return
				if body.has_method("add_impulse"):
					body.set("vy", 0.0)
					body.call("add_impulse", Vector3(0, 6.5, 0))
				_sfx("bounce", (body as Node3D).global_position)
				var u := get_node_or_null("/root/UI")
				if u and u.has_method("toast"):
					u.call("toast", "No bookmark, no way in! Catch that sheep."))
		elif on and _book1_bounce:
			_book1_bounce.queue_free()
			_book1_bounce = null
	if level and level.has_method("_update_bramwell"):
		level.call_deferred("_update_bramwell")
	if not on:
		var ui := get_node_or_null("/root/UI")
		if ui:
			ui.call("toast", "The sheep stole Book One's bookmark!")
	else:
		_sfx("chime")


# ------------------------------------------------------------------ H-E / H-F shortcuts

func _shortcuts() -> void:
	var w2_1 := _has("W2-1") or _unlock_all()
	var w1_4 := _has("W1-4") or _unlock_all()
	# Balustrade gates: closed sections with collision until the shortcut grows.
	for spec in [["BGATE_beanstalk", 124.0, 132.0, w2_1], ["BGATE_updraft", 231.0, 239.0, w1_4]]:
		var gate := Node3D.new()
		gate.name = spec[0]
		add_child(gate)
		var pts: Array[Vector3] = []
		var a0: float = spec[1]
		var a1: float = spec[2]
		for i in 4:
			pts.append(HubKit.polar(12.65, a0 + (a1 - a0) * float(i) / 3.0, 4.5))
		var body := HubArchitecture.static_body(gate, "Collision")
		HubArchitecture.rail(gate, body, pts, 1.0, "wood", true)
		HubArchitecture._balusters_commit(gate)
		if bool(spec[3]):
			gate.rotation_degrees.y = 0.0
			body.process_mode = Node.PROCESS_MODE_DISABLED
			gate.visible = false
	if w2_1:
		var vine := HubLadder.new()
		vine.name = "V1_beanstalk_vine"
		vine.vine_look = true
		vine.foot = Vector3(8.9, 0, 7.0)
		vine.top = Vector3(8.9, 4.4, 7.0)
		vine.exit_point = Vector3(9.46, 4.5, 7.39)
		vine.exit_yaw_deg = -128.0
		add_child(vine)
		var leaf := HubArchitecture.static_body(self, "A29_leaf")
		var lb := HubKit.Buf.new()
		HubKit.rounded_box(lb, Vector3(1.4, 0.2, 1.6), 0.09, Transform3D(Basis(Vector3.UP, deg_to_rad(-128.0)), Vector3(9.46, 4.4, 7.39)))
		HubArchitecture.mi(leaf, lb.commit(), HubArchitecture.flat_toon(Color("8fcf4a"), 0.4, 0.3), "Leaf")
		HubKit.add_box_collision(leaf, null, Vector3(1.4, 0.2, 1.6), Transform3D(Basis(Vector3.UP, deg_to_rad(-128.0)), Vector3(9.46, 4.4, 7.39)))
	if w1_4:
		# Visible streamers: a WindZone with negligible force; the real lift is hub_updraft.gd.
		var wz := WindZone.new()
		wz.name = "WZ_book1_updraft_fx"
		wz.size = Vector3(2.0, 2.0, 6.0)
		wz.direction = Vector3(0, 0, -1)
		wz.strength = 0.01
		wz.position = Vector3(-9.34, 3.8, 6.54)
		wz.rotation_degrees.x = 90.0
		add_child(wz)
		var up := Area3D.new()
		up.name = "WZ_book1_updraft"
		up.set_script(load("res://scripts/worlds/hub_updraft.gd"))
		add_child(up)


func _unlock_all() -> bool:
	var dev := get_node_or_null("/root/Dev")
	return dev != null and bool(dev.call("has_arg", "unlock-all"))


# ------------------------------------------------------------------ sniff chain

func _sniff_chain() -> void:
	if _st_nook == null:
		_st_nook = _sniff_node("ST_nook", Vector3(0, 0.1, -11.8))
		_st_ladder = _sniff_node("ST_HUB1_ladder", Vector3(12.5, 4.6, 4.55))
	_st_nook.set("active", not _nook_done)
	# After the nook: point at the ladder while below the cornice (the jar itself is a sniff target once revealed).
	_st_ladder.set("active", false)  # R3.5: HUB-1 is found, not followed


func _sniff_node(n: String, at: Vector3) -> Node3D:
	var ps := HubAssets.scene("res://scenes/objects/SniffTarget.tscn")
	var s: Node3D
	if ps:
		s = ps.instantiate() as Node3D
	else:
		s = Node3D.new()
	s.name = n
	# An empty Visual slot: the target is the floorboard or ladder that is already there.
	var v := Node3D.new()
	v.name = "Visual"
	v.add_child(Node3D.new())
	s.add_child(v)
	s.position = at
	add_child(s)
	return s


## Fix r2 (feel major), hub-owned cornice assist: the player keeps the steering basis it captured when the stick left
## neutral, so on the curved cornice (r 15) a held "up" drifted into the wall over a few metres and stalled Mak
## (3.0 -> 0 m/s). While Mak stands on a cornice walk (not the gap, whose side view keeps its own basis) the basis is
## set to the local tangent every tick, so "up" follows the curve exactly; the tangent camera (yaw_offset 72) is within
## 18 degrees of it. Runs before the player (priority -20). Requested from the player owner: a public steering
## override so this does not need the private _steer_* fields.
func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var p := _player.global_position
	if p.y < 8.1 or p.y > 9.3:
		return
	var r := Vector2(p.x, p.z).length()
	if r < 13.9 or r > 16.3:
		return
	var th := fposmod(rad_to_deg(atan2(p.x, -p.z)), 360.0)
	if not ((th > 99.0 and th < 118.0) or (th > 152.0 and th < 169.0)):
		return
	if not bool(_player.get("grounded")) or _player.get("_steer_yaw") == null:
		return
	var inp: Variant = _player.get("inp")
	var stick := Vector2.ZERO
	if inp != null and (inp as Object).get("stick") != null:
		stick = (inp as Object).get("stick")
	_player.set("_steer_locked", true)
	_player.set("_steer_yaw", wrapf(-deg_to_rad(th + 90.0), -PI, PI))
	_player.set("_steer_release", 0.0)
	if stick.length() > 0.01:
		_player.set("_steer_dir", stick.normalized())
