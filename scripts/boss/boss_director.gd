class_name BossDirector
extends Node
## Camera and pacing for the boss fight (BOSS.md section 9, amendments R1.9, R2.4, R3.10):
## - BossFraming: steers the player's own MakCamera (yaw onto the wolf-to-Mak line, distance and pitch
##   per phase) whenever the player is not orbiting by hand, so movement stays camera-relative.
## - Cinematics on a separate Camera3D (Cine_Entry, Cine_Intro, Cine_P2, Cine_P3, Cine_Updraft,
##   Cine_Defeat, Cine_Outro), skippable, with the player's input held neutral.
## - Hit punctuation: hitstop, FOV punch, shake.

signal cine_finished(id: String)

var arena: WolfRooftop
var cine_cam: Camera3D
var in_cine := false
var cine_id := ""
var framing := true
## Phase framing: distance, height.
var frame_dist := 10.0
var frame_height := 4.0
var air_pitch := false
var hold_cam_id := ""
var _hold_from := Vector3.ZERO
var _hold_look := Vector3.ZERO
var _hold_fov := 55.0
var _skip := false
var _cine_tw: Tween
var zone: BossCamZone
## Fix round 1: live (tracking) holds, cinematic HUD/letterbox, impact flash, P1 tell framing, updraft view.
var updraft_view := false
var _hold_live := false
var _frozen_yaw := NAN
var _overlay: CanvasLayer
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _flash_rect: ColorRect
var _bars_tw: Tween
var _hud_hidden := false
var _bossbar_was := false
var _tell_mode := false


## Camera-hint zone covering the arena (MakCameraRig reads these values while Mak overlaps it; manual orbiting wins).
class BossCamZone extends Area3D:
	var camera_yaw_deg: float = NAN
	var camera_pitch_deg: float = NAN
	var camera_distance: float = 10.0
	var camera_blend: float = 2.2
	var camera_priority: int = 5


func _ready() -> void:
	zone = BossCamZone.new()
	zone.name = "BossFramingZone"
	zone.collision_layer = 128
	zone.collision_mask = 0
	zone.monitoring = false
	zone.add_to_group("camera_zone")
	var zcs := CollisionShape3D.new()
	var zc := CylinderShape3D.new()
	zc.radius = 21.0
	zc.height = 40.0
	zcs.shape = zc
	zcs.position = Vector3(0, 10, 0)
	zone.add_child(zcs)
	arena.add_child.call_deferred(zone)
	cine_cam = Camera3D.new()
	cine_cam.name = "CineCam"
	cine_cam.fov = 50.0
	# The cine camera is moved from _process, not by physics: no physics interpolation (r1 QA minor: the CineCam
	# interpolation warning and the one-frame pop at the updraft).
	cine_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena.add_child.call_deferred(cine_cam)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()


## Letterbox bars (2.39:1) for cinematics and a full-screen flash for impact frames. Layer 18 sits under the
## Tale strip (19) and the boss bar (20), so the narration stays readable in the lower bar.
func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "BossCineOverlay"
	_overlay.layer = 18
	add_child(_overlay)
	_bar_top = ColorRect.new()
	_bar_top.color = Color(0.03, 0.02, 0.04)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_top.anchor_right = 1.0
	_bar_top.anchor_bottom = 0.0
	_bar_top.offset_bottom = 0.0
	_overlay.add_child(_bar_top)
	_bar_bot = ColorRect.new()
	_bar_bot.color = Color(0.03, 0.02, 0.04)
	_bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bot.anchor_top = 1.0
	_bar_bot.anchor_right = 1.0
	_bar_bot.anchor_bottom = 1.0
	_bar_bot.offset_top = 0.0
	_overlay.add_child(_bar_bot)
	_flash_rect = ColorRect.new()
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_overlay.add_child(_flash_rect)


func _set_letterbox(on: bool) -> void:
	if _bar_top == null or not is_inside_tree():
		return
	var h := get_viewport().get_visible_rect().size.y * 0.128 if on else 0.0
	if _bars_tw != null and _bars_tw.is_valid():
		_bars_tw.kill()
	_bars_tw = create_tween().set_parallel(true)
	_bars_tw.tween_property(_bar_top, "offset_bottom", h, 0.25).set_trans(Tween.TRANS_SINE)
	_bars_tw.tween_property(_bar_bot, "offset_top", -h, 0.25).set_trans(Tween.TRANS_SINE)


## HUD off in cinematics and holds (r1 spectacle major: the cake, counters and boss plate covered the wolf).
func _set_hud(on: bool) -> void:
	if on == (not _hud_hidden):
		return
	_hud_hidden = not on
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("set_hud_visible"):
		ui.call("set_hud_visible", on)
	var boss := arena.boss if arena != null else null
	if boss != null and is_instance_valid(boss) and boss.bar != null:
		if not on:
			_bossbar_was = boss.bar.visible
			boss.bar.visible = false
		elif _bossbar_was and not boss.defeated:
			boss.bar.visible = true


## Full-screen flash for impact frames (a frame or two of white, then a quick fade).
func flash(color: Color = Color(1, 1, 1), seconds: float = 0.07) -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = Color(color.r, color.g, color.b, 0.85)
	var tw := create_tween()
	tw.tween_interval(seconds * 0.5)
	tw.tween_property(_flash_rect, "color:a", 0.0, seconds + 0.12)


## r1 QA major: if the arena is freed during the updraft slow motion, give the time scale back.
func _exit_tree() -> void:
	if _slowmo_left > 0.0:
		_slowmo_left = 0.0
		_set_scale(1.0)
	if _hud_hidden:
		var ui := get_node_or_null("/root/UI")
		if ui != null and ui.has_method("set_hud_visible"):
			ui.call("set_hud_visible", true)


func player() -> Node3D:
	return arena.player if arena != null else null


func mak_cam() -> Node3D:
	var p := player()
	if p == null:
		return null
	return p.get_node_or_null("MakCamera") as Node3D


func set_phase(p: int) -> void:
	match p:
		1:
			frame_dist = 10.0
			frame_height = 4.0
		2:
			frame_dist = 12.0
			frame_height = 6.0
		_:
			frame_dist = 12.0
			frame_height = 6.5


func lock_input(on: bool) -> void:
	var p := player()
	if p == null:
		return
	var bot := arena.bot
	if bot != null:
		bot.set("paused", on)
		return
	var inp: Variant = p.get("inp")
	if inp == null:
		return
	if on:
		inp.set("replay_active", true)
		inp.set("steer_world", true)
		inp.set("_r_stick", Vector2.ZERO)
		inp.set("_held", {})
	else:
		inp.set("replay_active", false)


func _process(delta: float) -> void:
	if _slowmo_left > 0.0:
		# Counted in real seconds (the delta is scaled by the slow motion itself).
		_slowmo_left -= delta / maxf(Engine.time_scale, 0.01)
		if _slowmo_left <= 0.0:
			_set_scale(1.0)
	if get_tree().paused:
		return
	if hold_cam_id != "" and _hold_live and not in_cine:
		# Live hold: ease toward the tracked position and look target (Cine_Swell, Cine_Exit).
		var k := 1.0 - exp(-5.0 * delta)
		cine_cam.global_position = cine_cam.global_position.lerp(_hold_from, k)
		if cine_cam.global_position.distance_to(_hold_look) > 0.05:
			var want := Transform3D.IDENTITY.looking_at(_hold_look - cine_cam.global_position, Vector3.UP).basis
			cine_cam.global_basis = Basis(cine_cam.global_basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), 1.0 - exp(-8.0 * delta)))
	if in_cine:
		if _skip_pressed():
			skip()
		return
	var mc := mak_cam()
	var p := player()
	var boss := arena.boss if arena != null else null
	if mc == null or p == null or boss == null or not is_instance_valid(boss):
		return
	if boss.defeated and not boss.visible:
		# He has floated off to the storm: no line to frame, hand the camera back to the player.
		zone.camera_yaw_deg = NAN
		zone.camera_pitch_deg = NAN
		return
	var mpos := p.global_position
	var wpos := boss.global_position
	var d := mpos - wpos
	d.y = 0.0
	if d.length() < 0.5:
		return
	zone.camera_yaw_deg = rad_to_deg(atan2(d.x, d.z))
	# Keep the camera near the roof: on the wolf-to-Mak line a 10-12 m boom flies far past the rim whenever Mak is out
	# by the edge (P1 lee spots, P3 vents) and the rim props filled the frame. Shorten the horizontal reach to the
	# r 20.5 circle (just past the parapet, still above it) and climb a little instead; never closer than 6.5 m.
	var a0 := atan2(frame_height, frame_dist)
	# P1 tell framing (r1 fun / animation / spectacle majors): while the wolf inhales, huffs and turns, the camera on
	# the wolf-to-Mak line put the hiding chimney right over him. Climb to about -32 degrees and swing to a bearing
	# with a clear sightline to his head (below); fade the stack if none is clear.
	_tell_mode = boss.phase == 1 and not boss.defeated and (boss.state == "p1" or boss.state == "p1_open") and not (boss._cur_step_kind() in ["pant", "hop_back"])
	if _tell_mode:
		# Finish pass: 32 degrees put the far wolf at the top edge, under the boss bar; 26 keeps him in view (the
		# stack that still hides him is faded below, tested from the live camera).
		a0 = deg_to_rad(26.0)
	var reach := frame_dist * cos(a0)
	var height := frame_dist * sin(a0)
	var m := Vector2(mpos.x, mpos.z)
	var u := Vector2(d.x, d.z).normalized()
	var mu := m.dot(u)
	var disc := mu * mu - (m.length_squared() - 20.5 * 20.5)
	if disc > 0.0:
		var t_max := -mu + sqrt(disc)
		if t_max < reach:
			var h := maxf(t_max, 6.5)
			height += (reach - h) * 0.25
			reach = h
	# Chimneys: with Mak tucked against a plinth (P1 lee, P2 bait, a stump after a tail slam) the boom ran into the
	# brickwork and the spring snapped the camera into the rubble mesh. Swing the boom sideways to the first clear
	# bearing (keeps the last one while it stays clear, so the camera does not flick between sides).
	var base_yaw := atan2(d.x, d.z)
	var head := wpos + Vector3(0, 3.0, 0)
	var best_off := NAN
	if _view_ok(m, mpos, base_yaw + _yaw_off, reach, height, head):
		best_off = _yaw_off
	else:
		for off in [0.0, 0.45, -0.45, 0.8, -0.8, 1.1, -1.1, 1.4, -1.4, 1.6, -1.6]:
			if _view_ok(m, mpos, base_yaw + off, reach, height, head):
				best_off = off
				break
	var fade_ch: Variant = null
	if is_nan(best_off):
		best_off = 0.0
		for off in [0.0, 0.6, -0.6, 1.1, -1.1, 1.6, -1.6]:
			if not _boom_blocked(m, base_yaw + off, reach, height):
				best_off = off
				break
		if _tell_mode:
			fade_ch = _sight_blocked(mpos, base_yaw + best_off, reach, height, head)
	if _tell_mode and fade_ch == null:
		# Finish pass: the boom model above can call a line clear while the real camera (still blending, or pushed
		# by its spring) has the hiding stack right over the wolf. Test from the live camera too and fade that stack.
		var live := get_viewport().get_camera_3d()
		if live != null:
			fade_ch = _sight_blocked_from(live.global_position, head)
	_fade_chimneys(fade_ch, delta)
	if _cam_log and boss.phase == 1 and Engine.get_process_frames() % 45 == 0:
		var cam3 := get_viewport().get_camera_3d()
		var seen := cam3 != null and cam3.is_position_in_frustum(head)
		print("[CAMLOG] t=%.1f st=%s step=%s tell=%s off=%.2f fade=%s wolf_in_frustum=%s blocked_now=%s" % [boss.fight_time, boss.state, str(boss._cur_step_kind()), str(_tell_mode), best_off,
			str(fade_ch.name) if fade_ch != null else "-", str(seen), str(_sight_blocked(mpos, base_yaw + best_off, reach, height, head) != null)])
	_yaw_off = best_off
	zone.camera_yaw_deg = rad_to_deg(base_yaw + _yaw_off)
	zone.camera_distance = sqrt(reach * reach + height * height)
	var want_pitch := -rad_to_deg(atan2(height, reach))
	if air_pitch and mpos.y > 3.5 and Vector2(d.x, d.z).length() < 4.0:
		want_pitch = -40.0
	# Updraft climax: keep the gameplay camera, high behind Mak looking down at the head; the yaw is frozen so the
	# camera-relative steering never remaps mid-air (r1 fun major).
	if updraft_view and (boss.phase != 3 or boss.defeated or not (boss.updraft in ["column", "rise", "apex", "tell"])):
		updraft_view = false
	if updraft_view:
		if is_nan(_frozen_yaw):
			_frozen_yaw = zone.camera_yaw_deg
		zone.camera_yaw_deg = _frozen_yaw
		zone.camera_distance = 7.8
		want_pitch = -50.0
	else:
		_frozen_yaw = NAN
	zone.camera_pitch_deg = want_pitch
	if not framing:
		zone.camera_yaw_deg = NAN
		zone.camera_pitch_deg = NAN


var _yaw_off := 0.0
var _cam_log: bool = OS.get_cmdline_user_args().has("--ebu-cam-log")


## True when a boom from Mak along `yaw` (camera at reach / height) passes through a chimney below its top.
func _boom_blocked(m: Vector2, yaw: float, reach: float, height: float) -> bool:
	var dir := Vector2(sin(yaw), cos(yaw))
	for c in arena.chimneys.values():
		var ch := c as BossChimney
		var cp := Vector2(ch.global_position.x, ch.global_position.z)
		var s := (cp - m).dot(dir)
		if s < 0.3 or s > reach + 1.5:
			continue
		var lateral := (m + dir * s).distance_to(cp)
		var top := 3.0 if ch.smashed else 4.4
		var y_at := 1.2 + height * clampf(s / maxf(reach, 0.1), 0.0, 1.0)
		if lateral < (1.7 if ch.smashed else 1.95) and y_at < top + 0.3:
			return true
	return false


func _view_ok(m: Vector2, mpos: Vector3, yaw: float, reach: float, height: float, head: Vector3) -> bool:
	if _boom_blocked(m, yaw, reach, height):
		return false
	if _tell_mode and _sight_blocked(mpos, yaw, reach, height, head) != null:
		return false
	return true


## The chimney that blocks the line from the camera (boom along `yaw`) to the wolf's head, or null.
func _sight_blocked(mpos: Vector3, yaw: float, reach: float, height: float, head: Vector3) -> Variant:
	return _sight_blocked_from(mpos + Vector3(sin(yaw) * reach, 1.2 + height, cos(yaw) * reach), head)


func _sight_blocked_from(cam: Vector3, head: Vector3) -> Variant:
	for c in arena.chimneys.values():
		var ch := c as BossChimney
		# Finish pass: the real stack (plinth corners about 1.9 m out, pots to about 5.3 m) hid the wolf while this test,
		# sized to the bare stack, reported a clear sightline (P1 tells: wolf hidden behind the hiding chimney).
		var top := 3.4 if ch.smashed else 5.3
		var cp := Vector2(ch.global_position.x, ch.global_position.z)
		for i in 17:
			var q := cam.lerp(head, float(i) / 16.0)
			if q.y < top + 0.2 and Vector2(q.x, q.z).distance_to(cp) < 2.0:
				return ch
	return null


## Fade the one chimney that hides the wolf's tell to 35 % (the others back to solid).
func _fade_chimneys(which: Variant, delta: float) -> void:
	for c in arena.chimneys.values():
		var ch := c as BossChimney
		var f := float(ch.get_meta("cam_fade", 0.0))
		var nf := move_toward(f, 0.65 if ch == which else 0.0, delta * 3.0)
		if absf(nf - f) < 0.0001:
			continue
		ch.set_meta("cam_fade", nf)
		for g in ch.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).transparency = nf


func _skip_pressed() -> bool:
	if arena.bot != null:
		return false
	return InputMap.has_action("ui_cancel") and Input.is_action_just_pressed("ui_cancel")


func shake(amount: float = 0.3, seconds: float = 0.3) -> void:
	var mc := mak_cam()
	if mc != null and mc.has_method("add_shake"):
		mc.call("add_shake", amount, seconds)


func fov_punch(deg: float = -6.0) -> void:
	var mc := mak_cam()
	if mc != null and mc.get("_fov_kick") != null:
		mc.set("_fov_kick", deg)


## Hitstop goes through Juice when it exists (one owner of Engine.time_scale, so overlapping freezes and the
## updraft slow motion always restore); the local fallback only runs without the autoload.
func hitstop(seconds: float = 0.12, scale: float = 0.05) -> void:
	var j := get_node_or_null("/root/Juice")
	if j != null and j.has_method("hitstop"):
		j.call("hitstop", seconds * 1000.0)
		return
	Engine.time_scale = scale
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)


## Slow motion that Juice hitstops cannot strand: while it runs, the scale Juice restores to is updated too.
var _slowmo_left := 0.0


func slowmo(seconds: float, scale: float = 0.5) -> void:
	_slowmo_left = seconds
	_set_scale(scale)


func _set_scale(v: float) -> void:
	var j := get_node_or_null("/root/Juice")
	if j != null and j.has_method("is_hitstop_active") and bool(j.call("is_hitstop_active")):
		j.set("_saved_time_scale", v)
	else:
		Engine.time_scale = v


## Hit punctuation. With a Juice event name, the channels the Juice table owns (shake, hitstop) are skipped here;
## the FOV punch always plays (Juice has none).
func punctuate(big := false, juice_event := "") -> void:
	var j := get_node_or_null("/root/Juice")
	var owns := func(ch: String) -> bool:
		return juice_event != "" and j != null and j.has_method("handles") and bool(j.call("handles", juice_event, ch))
	if big or not owns.call("hitstop"):
		hitstop(0.3 if big else 0.12)
	fov_punch(-6.0)
	if not owns.call("shake"):
		shake(0.5 if big else 0.35)


## Plays a camera move from (a, look_a) to (b, look_b) over seconds. Await cine_finished or check in_cine.
func cine(id: String, a: Vector3, look_a: Vector3, b: Vector3, look_b: Vector3, fov_a: float, fov_b: float, seconds: float, lock := true) -> void:
	in_cine = true
	cine_id = id
	_skip = false
	_hold_live = false
	if lock:
		lock_input(true)
	_set_hud(false)
	_set_letterbox(true)
	cine_cam.make_current()
	var t0 := 0.0
	cine_cam.fov = fov_a
	_place(a, look_a)
	if _cine_tw != null and _cine_tw.is_valid():
		_cine_tw.kill()
	_cine_tw = create_tween()
	_cine_tw.tween_method(func(k: float) -> void:
		var e := k * k * (3.0 - 2.0 * k)
		_place(a.lerp(b, e), look_a.lerp(look_b, e))
		cine_cam.fov = lerpf(fov_a, fov_b, e), 0.0, 1.0, seconds)
	_cine_tw.tween_callback(func() -> void: end_cine(id, lock))
	t0 = seconds


func _place(pos: Vector3, look: Vector3) -> void:
	if pos.distance_to(look) < 0.01:
		return
	var t := Transform3D.IDENTITY.looking_at(look - pos, Vector3.UP)
	t.origin = pos
	# The cine camera may still be waiting for its deferred add_child when the intro starts in _ready.
	if cine_cam.is_inside_tree():
		cine_cam.global_transform = t
	else:
		cine_cam.transform = t


## A live camera that follows a callable each frame (Cine_Defeat_Soft, Cine_Updraft).
func hold(id: String, pos: Vector3, look: Vector3, fov: float, blend: float = 0.3) -> void:
	in_cine = false
	hold_cam_id = id
	_hold_from = pos
	_hold_look = look
	_hold_live = false
	_set_hud(false)
	_set_letterbox(false)
	var from_cam := get_viewport().get_camera_3d()
	var start_pos := from_cam.global_position if from_cam != null else pos
	var start_basis := from_cam.global_basis if from_cam != null else Basis()
	cine_cam.make_current()
	cine_cam.fov = fov
	cine_cam.global_position = start_pos
	cine_cam.global_basis = start_basis
	if _cine_tw != null and _cine_tw.is_valid():
		_cine_tw.kill()
	_cine_tw = create_tween()
	var q0 := start_basis.get_rotation_quaternion()
	var target := Transform3D.IDENTITY.looking_at(look - pos, Vector3.UP)
	var q1 := target.basis.get_rotation_quaternion()
	_cine_tw.tween_method(func(k: float) -> void:
		cine_cam.global_position = start_pos.lerp(pos, k)
		cine_cam.global_basis = Basis(q0.slerp(q1, k)), 0.0, 1.0, blend)
	_cine_tw.tween_callback(func() -> void: _hold_live = true)


## Move a live hold's camera target (eased in _process).
func hold_track(pos: Vector3, look: Vector3) -> void:
	_hold_from = pos
	_hold_look = look


func release_hold() -> void:
	hold_cam_id = ""
	_hold_live = false
	if not in_cine:
		_set_hud(true)
		_set_letterbox(false)
	var mc := mak_cam()
	if mc != null:
		var c := mc.get_node_or_null("Camera3D") as Camera3D
		if c != null:
			c.make_current()


func skip() -> void:
	if not in_cine:
		return
	if _cine_tw != null and _cine_tw.is_valid():
		_cine_tw.kill()
	end_cine(cine_id, true)


func end_cine(id: String, unlock: bool) -> void:
	if not in_cine:
		return
	in_cine = false
	release_hold()
	if unlock:
		lock_input(false)
	var mc := mak_cam()
	if mc != null and mc.has_method("snap_behind"):
		pass
	cine_finished.emit(id)
