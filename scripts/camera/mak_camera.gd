class_name MakCameraRig
extends Node3D
## Third-person camera rig for Mr. Mak (original design, not a reference camera).
## Mouse orbit (captured during gameplay), right-stick orbit, gentle auto-follow behind the run
## direction, pitch limits, sphere-cast collision against layer 1 only, smoothing, look-ahead,
## ground-level vertical framing (no bob on every jump, catches up on long falls), recenter on
## "cam_center", FOV kick on dives and long jumps, short shake on Ham Slam.
## Follows the player's interpolated transform in _process (physics interpolation is on).
## Group "game_camera": add_shake(strength, duration) for the Juice autoload and gameplay.
## Camera-hint zones: any Area3D in group "camera_zone" overlapping Mak (put it on layer 8, trigger) can set
## preferred values as properties or metas: camera_yaw_deg, camera_pitch_deg, camera_distance (m),
## camera_blend (1/s, default 2.5) and camera_priority (int). Unset values keep the free camera's.
## Player input still wins: manual orbiting suspends the zone's yaw/pitch for 1.5 s.
## Camera finish pass (2026-10-19, owner playtest):
## - Floor slide: pitching up (camera below Mak) slides the camera along the floor toward him and keeps it there; the
##   floor no longer counts as a "tight space" (that raised the pivot 2.2 m and pulled the camera back out), the boom
##   tilts up to look at Mak from the ground, the pitch does not drift back while he stands still, and the camera keeps
##   floor_clearance above the ground on slopes and steps.
## - One owner during interactions: while a dialog or menu owns the input the rig holds its view (no auto pitch, tight
##   lift, recenter, zone or prop changes); if the view of Mak is blocked when the dialog opens it eases once to the
##   nearest clear side.
## - No pops from props: a blocked arm only snaps in for wide obstructions (walls, floor); props and NPCs pull the arm in
##   smoothly and hold it for PROP_HOLD s, so a thin object at the edge of the arm no longer flips it every frame. NPCs
##   and signs (group "talker") are soft blockers only. Losing sight of Mak caps the tight-space lift below that height.
## - Mouse recapture: the first motion events after the mouse is captured again (dialogs, menus, focus) are dropped.
## Settings (Game autoload): mouse_sensitivity, gamepad_sensitivity, invert_x, invert_y, live on settings_changed.
## The mouse is released whenever the tree is paused, the window is unfocused or any visible
## node in the group "ui_modal" exists.

@export var target_path: NodePath = ^".."
@export var distance := 5.0                 ## m, default orbit distance (fix r1: 5.4 read Mak small)
@export var min_distance := 1.1             ## m, closest the camera gets when blocked
@export var pivot_height := 0.95            ## m above the framed ground level
@export var tight_distance := 2.5           ## m: below this arm length the camera frames for tight spaces
@export var tight_pitch_deg := -24.0        ## pitch pulled toward in tight spaces (fix r2: -35 read as a top-down close-up)
@export var tight_lift := 2.2               ## m: in tight spaces the pivot rises up to this much (looking across a shaft)
@export var sideways_follow_rate := 0.8     ## 1/s flat auto-follow (fix r2: no |sin| boost while strafing)
@export var default_pitch_deg := -17.0
@export var min_pitch_deg := -70.0
@export var max_pitch_deg := 42.0          ## finish pass: 30 stopped the camera at the floor; 42 looks up from the ground
@export var floor_clearance := 0.24         ## m: camera centre above the ground below it (floor slide on slopes and steps)
@export var mouse_sensitivity := 0.0025     ## rad per pixel
@export var stick_yaw_speed_deg := 160.0
@export var stick_pitch_speed_deg := 95.0
@export var auto_follow := true
@export var auto_follow_delay := 0.9        ## s without manual input before auto-follow
@export var auto_follow_rate := 1.6         ## 1/s at full speed when moving sideways
@export var look_ahead_time := 0.16         ## s of velocity
@export var look_ahead_max := 1.4           ## m
@export var collision_radius := 0.22        ## m
@export var base_fov := 62.0
@export var follow_rate := 14.0             ## 1/s horizontal follow
@export var vertical_rate := 5.0            ## 1/s vertical framing
@export var fall_catchup := 0.6             ## m below the ground reference before following down
@export var rise_allowance := 1.3           ## m above the ground reference before following up

var yaw := 0.0
var pitch := 0.0
var player: MakPlayer = null
var cam: Camera3D = null
var _pivot := Vector3.ZERO
var _ground_ref := 0.0
var _frame_y := 0.0
var _cur_dist := 5.4
var _manual_timer := 99.0
var _recenter := 0.0
var _fov_kick := 0.0

var _look := Vector3.ZERO
var _mouse_delta := Vector2.ZERO
var _test_run := false
var _t := 0.0
var _shake_amp := 0.0
var _shake_time := 0.0
var _shake_dur := 0.3
var _mouse_mult := 1.0
var _pad_mult := 1.0
var _inv_x := 1.0
var _inv_y := 1.0
var _zone_dist := -1.0
var _cur_target_dist := 5.0
var zone: Node = null
var _prev_zone: Node = null
var _fall_tilt := 0.0
var _fast_fall_t := 0.0
var _head_bias := 0.0
var _lift := 0.0
var _tight_d0 := 99.0
var _frame_v := 0.0
var _flip_bias := 0.0
var _floor_k := 0.0
## Hero v2 fix r1 (feel F1-F3).
const THIN_SIDE := 0.25                     ## m: side offset of the two parallel arm casts that tell a thin prop from a wall
const ARM_PROP_CLEAR := 1.6                 ## m: an ignored thin prop must be at least this far in front of the camera
const FLIP_STATES := {"triple_jump": true, "side_flip": true, "backflip": true, "wall_kick": true, "double_jump": true}


const LEDGE_HOLD_STATES := {"ledge_hang": true, "ledge_climb": true, "pole_climb": true, "wall_slide": true}
const PROP_HOLD := 0.45                     ## s a soft (prop/NPC) block keeps the arm in after the last blocked frame
var _arm_hard := false
var _arm_ground_y := INF
var _prop_hold := 0.0
var _prop_d := 99.0
var _lift_cap := 99.0
var _lift_cap_at := Vector3.ZERO
var _hold := false
var _hold_yaw := NAN
var _soft_t := 0.0
var _capture_skip := 0
var _was_captured := false
## Camera probe (dev only, tests): --cam-trace=<abs jsonl> writes one line per rendered frame (viewport camera, rig
## state, frame time); --cam-mouse="t0,t1,dx,dy/..." feeds dx,dy mouse pixels per frame between t0 and t1 s (rig time)
## through the real mouse path; --cam-interact=<t> presses "interact" for two physics frames at t s.
var _ptrace: FileAccess = null
var _pmouse: Array = []
var _pinteract: Array = []
var _pinteract_f := 0
var _pframe := 0
var _pt := 0.0


func _ready() -> void:
	top_level = true
	add_to_group("game_camera")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam = get_node_or_null("Camera3D") as Camera3D
	player = get_node_or_null(target_path) as MakPlayer
	var dev := get_tree().root.get_node_or_null("Dev")
	if dev != null and dev.has_method("is_test_run"):
		_test_run = bool(dev.call("is_test_run"))
	# Showcase captures: --cam-distance=<m> and --cam-pitch=<deg> frame Mak closer than gameplay.
	if dev != null and dev.has_method("arg"):
		var cd := str(dev.call("arg", "cam-distance", ""))
		if cd != "":
			distance = float(cd)
			min_distance = minf(min_distance, distance * 0.5)
		var cp := str(dev.call("arg", "cam-pitch", ""))
		if cp != "":
			default_pitch_deg = float(cp)
		_probe_setup(dev)
	if player != null:
		player.jumped.connect(_on_jumped)
		player.attacked.connect(_on_attacked)
		player.teleported.connect(snap_behind)
	var g := get_tree().root.get_node_or_null("Game")
	if g != null and g.has_signal("settings_changed"):
		g.connect("settings_changed", _read_settings)
	_read_settings()
	pitch = deg_to_rad(default_pitch_deg)
	call_deferred("snap_behind")


func snap_behind() -> void:
	if player == null:
		return
	yaw = player.facing_yaw
	pitch = deg_to_rad(default_pitch_deg)
	var p := player.global_position
	_ground_ref = p.y
	_frame_y = p.y
	_look = Vector3.ZERO
	_pivot = Vector3(p.x, p.y + pivot_height, p.z)
	_cur_dist = distance
	_cur_target_dist = distance
	_update_camera(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Finish pass: the first events after a (re)capture carry the cursor warp to the window centre (a one-frame yaw
		# jump after every dialog); drop them, and cap any single event.
		if _capture_skip > 0:
			return
		_mouse_delta += (event as InputEventMouseMotion).relative.limit_length(240.0)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _gameplay_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _gameplay_active() -> bool:
	if _test_run or DisplayServer.get_name() == "headless":
		return false
	if get_tree().paused:
		return false
	var ui := get_tree().root.get_node_or_null("UI")
	if ui != null and ui.has_method("is_input_blocked") and bool(ui.call("is_input_blocked")):
		return false
	if not get_window().has_focus():
		return false
	for n in get_tree().get_nodes_in_group("ui_modal"):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return false
		if n is CanvasLayer and (n as CanvasLayer).visible:
			return false
	return cam != null and cam.current


func _update_mouse_mode() -> void:
	if _test_run or DisplayServer.get_name() == "headless":
		return
	var want := _gameplay_active()
	if OS.has_feature("web"):
		# Pointer lock requires a click. Retrying every frame after Esc/focus loss
		# floods the browser with rejected requests and prevents leaving the game.
		if not want and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if want and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not want and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_jumped(kind: String) -> void:
	if kind == "long_jump":
		_fov_kick = maxf(_fov_kick, 7.0)


func _on_attacked(kind: String) -> void:
	if kind == "dive":
		_fov_kick = maxf(_fov_kick, 6.0)


## Screen shake on the Juice scale (Docs/JUICE.md): strength 0..1 (0.05 a double jump, 0.38 a Ham Slam, 0.9 the
## boss defeat), decaying to zero over duration seconds; 1.0 is about 0.4 m of camera offset. Overlapping shakes
## keep the strongest.
func add_shake(strength: float, duration: float = 0.3) -> void:
	var remaining := _shake_amp * (_shake_time / maxf(_shake_dur, 0.001))
	if strength >= remaining:
		_shake_amp = clampf(strength, 0.0, 1.5)
		_shake_dur = maxf(duration, 0.05)
		_shake_time = _shake_dur


func _read_settings() -> void:
	var g := get_tree().root.get_node_or_null("Game") if is_inside_tree() else null
	if g == null or not g.has_method("get_setting"):
		return
	_mouse_mult = float(g.call("get_setting", "mouse_sensitivity", 1.0))
	_pad_mult = float(g.call("get_setting", "gamepad_sensitivity", 1.0))
	_inv_x = -1.0 if bool(g.call("get_setting", "invert_x", false)) else 1.0
	_inv_y = -1.0 if bool(g.call("get_setting", "invert_y", false)) else 1.0


func _zone_value(z: Node, key: String) -> Variant:
	var v: Variant = z.get(key)
	if v == null and z.has_meta(key):
		v = z.get_meta(key)
	return v


func _find_zone() -> Node:
	if player == null or player.sensor == null:
		return null
	var best: Node = null
	var best_p := -1000000
	for a in player.sensor.get_overlapping_areas():
		if a.is_in_group("camera_zone"):
			var pr: Variant = _zone_value(a, "camera_priority")
			var pi := int(pr) if pr != null else 0
			if pi > best_p:
				best_p = pi
				best = a
	return best


func _process(delta: float) -> void:
	if player == null or cam == null:
		return
	_update_mouse_mode()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and not _was_captured:
		_capture_skip = 3
		_mouse_delta = Vector2.ZERO
	elif _capture_skip > 0:
		_capture_skip -= 1
	_was_captured = captured
	_pt += delta
	if not _pmouse.is_empty():
		for seg in _pmouse:
			if _pt >= float(seg[0]) and _pt < float(seg[1]):
				_probe_mouse += Vector2(float(seg[2]), float(seg[3])) * delta
	_update_camera(minf(delta, 0.05))
	if _ptrace != null:
		_probe_write(delta)


var _probe_mouse := Vector2.ZERO


func _probe_setup(dev: Node) -> void:
	var tp := str(dev.call("arg", "cam-trace", ""))
	if tp != "":
		DirAccess.make_dir_recursive_absolute(tp.get_base_dir())
		_ptrace = FileAccess.open(tp, FileAccess.WRITE)
	var ms := str(dev.call("arg", "cam-mouse", ""))
	for part in ms.split("/", false):
		var v := part.split(",")
		if v.size() == 4:
			_pmouse.append([float(v[0]), float(v[1]), float(v[2]), float(v[3])])
	for it in str(dev.call("arg", "cam-interact", "")).split(",", false):
		_pinteract.append(float(it))


func _physics_process(_delta: float) -> void:
	if _pinteract.is_empty() and _pinteract_f == 0:
		return
	if not _pinteract.is_empty() and _pt >= float(_pinteract[0]) and _pinteract_f == 0:
		_pinteract.pop_front()
		_pinteract_f = 2
		Input.action_press("interact")
	elif _pinteract_f > 0:
		_pinteract_f -= 1
		if _pinteract_f == 0:
			Input.action_release("interact")


func _probe_write(delta: float) -> void:
	_pframe += 1
	var vc := get_viewport().get_camera_3d()
	var ct := vc.global_transform if vc != null else cam.global_transform
	var fwd := -ct.basis.z
	var pp := player.get_global_transform_interpolated().origin
	var ui := get_tree().root.get_node_or_null("UI")
	var blocked := ui != null and ui.has_method("is_input_blocked") and bool(ui.call("is_input_blocked"))
	var row := {"f": _pframe, "t": snappedf(_pt, 0.0001), "dt": snappedf(delta, 0.00001),
		"cam": [snappedf(ct.origin.x, 0.0001), snappedf(ct.origin.y, 0.0001), snappedf(ct.origin.z, 0.0001)],
		"fwd": [snappedf(fwd.x, 0.00001), snappedf(fwd.y, 0.00001), snappedf(fwd.z, 0.00001)],
		"vcam": str(vc.name) if vc != null else "", "rig_cur": vc == cam,
		"pitch": snappedf(rad_to_deg(pitch), 0.01), "yaw": snappedf(rad_to_deg(yaw), 0.01),
		"boom": snappedf(_cur_dist, 0.0001), "lift": snappedf(_lift, 0.0001), "tight_d0": snappedf(_tight_d0, 0.001),
		"head": snappedf(_head_bias, 0.0001), "floor": snappedf(_floor_k, 0.001),
		"pl": [snappedf(pp.x, 0.0001), snappedf(pp.y, 0.0001), snappedf(pp.z, 0.0001)],
		"st": player.state, "ui": blocked}
	_ptrace.store_line(JSON.stringify(row))
	if _pframe % 60 == 0:
		_ptrace.flush()


func _exit_tree() -> void:
	if _ptrace != null:
		_ptrace.flush()
		_ptrace = null


func _update_camera(dt: float) -> void:
	_t += dt
	var ppos := player.get_global_transform_interpolated().origin
	# Fix r2 (feel minor M5): follow what the player sees. A vault, mantle or ledge grab moves the body up to 0.8 m in one
	# tick while the visual eases over; the camera now targets the eased visual position, so it no longer lurches.
	ppos += player.visual_grab_offset
	var manual := false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_mouse_delta = Vector2.ZERO
	_mouse_delta += _probe_mouse
	_probe_mouse = Vector2.ZERO
	if _mouse_delta != Vector2.ZERO:
		yaw -= _mouse_delta.x * mouse_sensitivity * _mouse_mult * _inv_x
		pitch -= _mouse_delta.y * mouse_sensitivity * _mouse_mult * _inv_y
		_mouse_delta = Vector2.ZERO
		manual = true
	var cam_in := player.inp.cam
	if not player.inp.replay_active and InputMap.has_action("cam_left") and not player._ui_blocks_input():
		cam_in = Input.get_vector("cam_left", "cam_right", "cam_down", "cam_up", 0.15) * _pad_mult
		cam_in = Vector2(cam_in.x * _inv_x, cam_in.y * _inv_y)
	if cam_in.length() > 0.01:
		yaw -= cam_in.x * deg_to_rad(stick_yaw_speed_deg) * dt
		pitch += cam_in.y * deg_to_rad(stick_pitch_speed_deg) * dt
		manual = true
	_manual_timer = 0.0 if manual else _manual_timer + dt
	var center := player.inp.cam_center_pressed
	if not player.inp.replay_active and InputMap.has_action("cam_center") and Input.is_action_just_pressed("cam_center"):
		center = true
	if center:
		_recenter = 0.35
	var st := player.state
	var hv := player.get_horizontal_velocity()
	var sp := hv.length()
	var was_hold := _hold
	_hold = player._ui_blocks_input()
	if _hold and not was_hold:
		_hold_yaw = _clear_view_yaw(ppos)
	elif not _hold:
		_hold_yaw = NAN
	if _hold:
		# Finish pass (one owner): a dialog or menu owns the input, so the rig holds the view. Only a blocked view of Mak
		# at the dialog's start eases once to the nearest clear side (picked in _clear_view_yaw).
		_recenter = 0.0
		_manual_timer = 0.0
		if not is_nan(_hold_yaw):
			yaw = lerp_angle(yaw, _hold_yaw, 1.0 - exp(-3.0 * dt))
	elif _recenter > 0.0:
		_recenter -= dt
		yaw = lerp_angle(yaw, player.facing_yaw, 1.0 - exp(-14.0 * dt))
		pitch = lerpf(pitch, deg_to_rad(default_pitch_deg), 1.0 - exp(-14.0 * dt))
	elif auto_follow and _manual_timer > auto_follow_delay and sp > 1.0 \
			and st != "ledge_hang" and st != "pole_climb" and st != "wall_slide" and st != "wall_kick" and st != "fallout":
		var move_yaw := atan2(-hv.x, -hv.z)
		var diff := angle_difference(yaw, move_yaw)
		if absf(diff) < deg_to_rad(125.0):
			# Fix r2 (feel minor M3): a flat, slower follow. The |sin| boost swung the camera 83 degrees in 3.2 s exactly when
			# the player ran sideways, so "right" ended up pointing into the screen.
			var rate := sideways_follow_rate * clampf(sp / 7.5, 0.0, 1.0)
			yaw += diff * (1.0 - exp(-rate * dt))
	# Camera-hint zones (chimneys, corridors): ease toward the zone's preferred view.
	zone = _find_zone()
	if zone != _prev_zone:
		# Fix r1: entering a zone applies its view at once instead of waiting out the 1.5 s manual hold.
		if zone != null:
			_manual_timer = maxf(_manual_timer, 1.51)
		_prev_zone = zone
	_zone_dist = -1.0
	var zone_pitch := false
	# Finish pass: tightness comes from the level arm only (see _tight_d0), so pitching into the floor is not "tight".
	var tight := clampf((tight_distance - _tight_d0) / 1.2, 0.0, 1.0) if _lift < 0.3 and not _hold else 0.0
	if zone != null:
		var blend: Variant = _zone_value(zone, "camera_blend")
		var zr := float(blend) if blend != null else 2.5
		if tight > 0.0:
			zr = maxf(zr, 6.0)
		var za := 1.0 - exp(-zr * dt)
		if _manual_timer > 1.5 and _recenter <= 0.0:
			var zy: Variant = _zone_value(zone, "camera_yaw_deg")
			if zy != null and not is_nan(float(zy)):
				yaw = lerp_angle(yaw, deg_to_rad(float(zy)), za)
			var zp: Variant = _zone_value(zone, "camera_pitch_deg")
			if zp != null and not is_nan(float(zp)):
				pitch = lerpf(pitch, deg_to_rad(float(zp)), za)
				zone_pitch = true
		var zd: Variant = _zone_value(zone, "camera_distance")
		if zd != null and not is_nan(float(zd)) and float(zd) > 0.0:
			_zone_dist = float(zd)
	# Finish pass (floor slide): the pitch only drifts back while Mak moves, so a low look-up view stays put while he stands.
	if _manual_timer > 2.5 and _recenter <= 0.0 and not zone_pitch and tight <= 0.0 and not _hold \
			and (sp > 1.0 or not player.grounded):
		var back := clampf((sp - 1.0) / 3.0, 0.0, 1.0) if player.grounded else 1.0
		pitch = lerpf(pitch, deg_to_rad(default_pitch_deg), 1.0 - exp(-0.8 * back * dt))
	# Fix r1, tight spaces: when the arm is compressed the camera looks down more steeply so Mak and his landing spot
	# stay in frame (the near-level pitch at 1.2 m lost him off the top of the frame on every jump).
	if tight > 0.0 and _manual_timer > 0.5 and not zone_pitch and _recenter <= 0.0:
		pitch = lerpf(pitch, deg_to_rad(tight_pitch_deg), 1.0 - exp(-3.5 * tight * dt))
	pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	yaw = wrapf(yaw, -PI, PI)
	# Vertical framing: follow the ground level, not every jump.
	var rate_v := vertical_rate
	if st == "fallout":
		pass
	elif player.grounded or st == "ledge_hang" or st == "ledge_climb" or st == "pole_climb" or st == "wall_slide" \
			or st == "wall_kick":
		_ground_ref = ppos.y
	else:
		if ppos.y < _ground_ref - fall_catchup:
			_ground_ref = ppos.y + fall_catchup
			rate_v = vertical_rate * 2.5
		elif ppos.y > _ground_ref + rise_allowance:
			_ground_ref = ppos.y - rise_allowance
			rate_v = vertical_rate * 2.5
	# Wall-kick climbs rise 3 m per kick: follow them tightly (and inside camera zones) so Mak stays in frame.
	if st == "wall_kick" or st == "wall_slide" or (zone != null and absf(player.vy) > 2.0):
		rate_v = maxf(rate_v, 11.0)
	if tight > 0.0 and not player.grounded and st != "fallout":
		# Tight spaces: follow Mak's height closely instead of the ground level.
		_ground_ref = lerpf(_ground_ref, ppos.y, tight)
		rate_v = maxf(rate_v, lerpf(vertical_rate, 11.0, tight))
	# Fix r2 (feel polish P2): a critically damped spring (zero velocity at the settle) instead of an exponential lerp, so
	# touchdowns carry no residual vertical kick.
	if dt > 0.0:
		var om := rate_v * 1.6
		_frame_v += (om * om * (_ground_ref - _frame_y) - 2.0 * om * _frame_v) * dt
		_frame_y += _frame_v * dt
	else:
		_frame_y = _ground_ref
		_frame_v = 0.0
	# Look-ahead in the direction of travel.
	var la := (hv * look_ahead_time).limit_length(look_ahead_max)
	if st == "fallout":
		la = Vector3.ZERO
	_look = _look.lerp(la, 1.0 - exp(-3.0 * dt)) if dt > 0.0 else la
	var want_fb := 0.8 if (FLIP_STATES.has(st) and not player.grounded and player.vy < 0.0) else 0.0
	_flip_bias = lerpf(_flip_bias, want_fb, 1.0 - exp(-(8.0 if want_fb > _flip_bias else 4.0) * dt)) if dt > 0.0 else want_fb
	var target := Vector3(ppos.x, _frame_y + pivot_height + _head_bias - _flip_bias, ppos.z) + _look
	if st == "fallout":
		target = _pivot
	if dt > 0.0:
		var hp := Vector3(_pivot.x, 0.0, _pivot.z).lerp(Vector3(target.x, 0.0, target.z), 1.0 - exp(-follow_rate * dt))
		_pivot = Vector3(hp.x, target.y, hp.z)
	else:
		_pivot = target
	# Look down a little more during real falls so the landing spot stays visible. Fix r1: the tilt is a smoothed
	# state (it dropped to 0 on the touchdown frame and jumped the camera 0.5-1.2 m), and ordinary or chained jumps
	# get none: only falls below the ground reference or more than 0.25 s faster than 14 m/s.
	var want_tilt := 0.0
	if not player.grounded and st != "fallout" and not LEDGE_HOLD_STATES.has(st):
		_fast_fall_t = _fast_fall_t + dt if player.vy < -14.0 else 0.0
		if ppos.y < _ground_ref - fall_catchup + 0.05 or _fast_fall_t > 0.25:
			want_tilt = clampf(-player.vy / 17.6, 0.0, 1.0) * deg_to_rad(12.0)
		# Fix r1 (feel F3): the landing spot fell below the frame during flips and wall kicks. In those states the tilt
		# starts as soon as the descent passes 1.5 m/s (up to 16 degrees), and the framing is biased 0.8 m down (see _flip_bias).
		if FLIP_STATES.has(st):
			if player.vy < -1.5:
				want_tilt = maxf(want_tilt, clampf((-player.vy - 1.0) / 8.0, 0.0, 1.0) * deg_to_rad(16.0))
			# High flips (a triple jump peaks about 5 m up): tilt with the height above the ground below Mak.
			var hq := PhysicsRayQueryParameters3D.create(ppos + Vector3.UP * 0.2, ppos + Vector3.DOWN * 8.0, 1, [player.get_rid()])
			var hh := get_world_3d().direct_space_state.intersect_ray(hq)
			var hgt := ppos.y - (hh["position"] as Vector3).y if not hh.is_empty() else 0.0
			want_tilt = maxf(want_tilt, clampf((hgt - 1.5) / 3.0, 0.0, 1.0) * deg_to_rad(22.0))
	else:
		_fast_fall_t = 0.0
	_fall_tilt = lerpf(_fall_tilt, want_tilt, 1.0 - exp(-(7.0 if FLIP_STATES.has(st) else 5.0) * dt)) if dt > 0.0 else want_tilt
	var b := Basis.from_euler(Vector3(pitch - _fall_tilt, yaw, 0.0))
	var tdist := _zone_dist if _zone_dist > 0.0 else distance
	_cur_target_dist = lerpf(_cur_target_dist, tdist, 1.0 - exp(-3.0 * dt)) if dt > 0.0 else tdist
	# Fix r2 (feel major M2): in a tight space raise the pivot and keep the arm long instead of pulling in to 1.2 m.
	# Tightness is measured from the unlifted pivot (no feedback loop); the lift is limited by the free space above.
	# Finish pass (floor slide): measure tightness along the arm at a level-or-higher pitch, so the floor under a low,
	# look-up camera never counts as a tight space (it raised the pivot 2.2 m and threw the camera back out to 5 m).
	var b_lvl := Basis.from_euler(Vector3(minf(pitch, 0.0) - _fall_tilt, yaw, 0.0))
	var d0 := _collide_arm(_pivot, _pivot + b_lvl.z * _cur_target_dist, b_lvl.x)
	_tight_d0 = d0
	# The lift cap set when the lifted camera lost sight of Mak holds until he leaves the tight spot (1.5 m or a free arm).
	if d0 >= tight_distance or Vector2(ppos.x - _lift_cap_at.x, ppos.z - _lift_cap_at.z).length() > 1.5:
		_lift_cap = tight_lift
	var lift_target := 0.0
	if _hold:
		lift_target = _lift
	elif d0 < tight_distance and st != "fallout" and tight_lift > 0.0:
		var up_free := _collide(_pivot, _pivot + Vector3.UP * (tight_lift + 0.4)) - 0.4
		lift_target = minf(clampf(up_free, 0.0, tight_lift) * clampf((tight_distance - d0) / 1.0, 0.0, 1.0), _lift_cap)
	# Fix r1 (feel F2): the hub tight-space lift put the camera above the balcony floor with Mak hidden under it. The lift is
	# only kept while the lifted camera can see Mak's chest; when the line of sight is lost the lift drops quickly.
	# Finish pass: losing sight caps the lift 0.4 m below the height where it happened instead of dropping it to zero and
	# letting it rise again the next frame (it pumped up and down beside the balcony telescope).
	if _lift > 0.05 and not _hold and not _los_clear(_pivot + Vector3.UP * _lift + b.z * minf(_cur_dist, _cur_target_dist), ppos + Vector3.UP * 0.6):
		_lift_cap = maxf(minf(_lift_cap, _lift) - 0.4, 0.0)
		_lift_cap_at = ppos
		lift_target = minf(lift_target, _lift_cap)
		_lift = lerpf(_lift, lift_target, 1.0 - exp(-10.0 * dt)) if dt > 0.0 else lift_target
	_lift = lerpf(_lift, lift_target, 1.0 - exp(-(5.0 if lift_target > _lift else 2.0) * dt)) if dt > 0.0 else lift_target
	var lp := _pivot + Vector3.UP * _lift
	var want := lp + b.z * _cur_target_dist
	var d := _collide_arm(lp, want, b.x)
	var hard := _arm_hard
	# Soft blockers (NPCs and signs): the plain centre cast with them included, never a snap.
	_refresh_soft(ppos, dt)
	if not _soft_nodes.is_empty():
		var ds := _soft_block(lp, want)
		if ds < d - 0.05:
			d = maxf(ds, min_distance)
			hard = false
	# Finish pass (no pops): props pull the arm in smoothly and hold it for PROP_HOLD s after the last blocked frame, so a
	# prop at the edge of the arm (the balcony telescope, a signpost) no longer flips it between 1.5 m and 5 m each frame.
	var full_len := maxf(_cur_target_dist, min_distance)
	if not hard and d < full_len - 0.05:
		_prop_hold = PROP_HOLD
		_prop_d = d if (_prop_d > 90.0 or d < _prop_d) else lerpf(_prop_d, d, 1.0 - exp(-2.0 * dt))
	elif _prop_hold > 0.0:
		_prop_hold -= dt
		if _prop_hold <= 0.0:
			_prop_d = 99.0
	var d_soft := minf(d, _prop_d) if _prop_hold > 0.0 else d
	# Finish pass (floor slide): a ground contact (walkable face below the pivot + 0.5 m: floor, slope, step) shortens the
	# arm over a few frames instead of in one. Grazing a slope moved the contact 2-3 m along the arm in a single frame;
	# the floor guard below keeps the easing camera above the ground meanwhile.
	var ground := hard and dt > 0.0 and d < _cur_dist - 0.05 and _arm_ground_y < INF
	if dt <= 0.0:
		_cur_dist = d
	elif ground:
		_cur_dist = lerpf(_cur_dist, d, 1.0 - exp(-14.0 * dt))
	elif hard and d < _cur_dist:
		_cur_dist = d
	elif d_soft < _cur_dist:
		_cur_dist = lerpf(_cur_dist, d_soft, 1.0 - exp(-9.0 * dt))
	else:
		_cur_dist = move_toward(_cur_dist, d_soft, 4.0 * dt)
	var cpos := lp + b.z * _cur_dist
	# Finish pass (floor slide): keep the camera floor_clearance above the ground under it (slopes rising behind Mak,
	# step edges) and aim it back at Mak's pivot, so a low camera slides along the ground and looks up at him.
	_floor_k = 0.0
	# The guard ray starts at the pivot height + 0.5 m (below ceilings), or 1 m over the ground the arm just met (a hill
	# rising behind Mak), whichever is higher.
	var g0 := lp.y + 0.5
	if _arm_ground_y < INF:
		g0 = maxf(g0, _arm_ground_y + 1.0)
	if cpos.y < g0:
		var gq := PhysicsRayQueryParameters3D.create(Vector3(cpos.x, g0, cpos.z), Vector3(cpos.x, cpos.y - floor_clearance - 0.4, cpos.z), 1, [player.get_rid()])
		var gh := get_world_3d().direct_space_state.intersect_ray(gq)
		if not gh.is_empty() and (gh["normal"] as Vector3).y > 0.55:
			var gy := (gh["position"] as Vector3).y + floor_clearance
			if gy > cpos.y:
				_floor_k = gy - cpos.y
				cpos.y = gy
				var aim0 := lp - cpos
				if aim0.length() > 0.3 and absf(aim0.normalized().dot(Vector3.UP)) < 0.97:
					b = Basis.looking_at(aim0.normalized(), Vector3.UP)
		# No dead zone at the floor: once the arm is pinned at min_distance, pitch input past the angle the camera can
		# actually reach is not stored (it would have to be unwound before the camera moved again).
		var reach := asin(clampf((lp.y - cpos.y) / maxf(lp.distance_to(cpos), 0.01), -1.0, 1.0))
		if _floor_k > 0.0 and _cur_dist <= min_distance + 0.05 and pitch > reach + deg_to_rad(4.0):
			pitch = reach + deg_to_rad(4.0)
	if _lift > 0.05:
		# Look back down at Mak from the lifted spot, blending with the free orbit basis.
		var aim := ppos + Vector3.UP * 0.6 - cpos
		if aim.length() > 0.3 and absf(aim.normalized().dot(Vector3.UP)) < 0.98:
			var la_b := Basis.looking_at(aim.normalized(), Vector3.UP)
			b = b.slerp(la_b, clampf(_lift / 0.8, 0.0, 1.0))
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - dt, 0.0)
		var k := _shake_time / _shake_dur
		var a := _shake_amp * 0.4 * k * k
		cpos += b.x * (sin(_t * 71.0) + 0.5 * sin(_t * 113.0)) * a * 0.67 + b.y * (sin(_t * 53.0 + 1.3) + 0.5 * sin(_t * 97.0)) * a * 0.67
	cam.global_transform = Transform3D(b, cpos)
	# Keep Mak's head inside the frame (top 12 %) in tight spaces by raising the framing a little.
	if dt > 0.0:
		var want_bias := 0.0
		if tight > 0.0 and not cam.is_position_behind(ppos + Vector3.UP * 1.25):
			var vp := cam.get_viewport().get_visible_rect().size
			var sy := cam.unproject_position(ppos + Vector3.UP * 1.25).y / maxf(vp.y, 1.0)
			if _hold:
				want_bias = _head_bias
			elif sy < 0.12:
				want_bias = _head_bias + (0.12 - sy) * 2.5
			else:
				want_bias = maxf(_head_bias - 0.5 * dt, 0.0)
		_head_bias = clampf(lerpf(_head_bias, want_bias, 1.0 - exp(-8.0 * dt)), 0.0, 1.5)
	_fov_kick = move_toward(_fov_kick, 0.0, 9.0 * dt)
	cam.fov = base_fov + _fov_kick


## Fix r1 (feel F1): thin props (signposts, flower stems, posts) pumped the arm in and out. The centre cast only counts when
## at least one of two parallel casts offset THIN_SIDE to each side is blocked too; a prop narrower than about 0.5 m that
## blocks only the centre is ignored.
func _collide_arm(from: Vector3, to: Vector3, side: Vector3) -> float:
	var full := maxf((to - from).length(), min_distance)
	var dc := _collide(from, to)
	_arm_hard = false
	_arm_ground_y = INF
	if dc >= full - 0.01:
		return dc
	# Finish pass: wide obstructions (walls, floors, ceilings: the arm 0.75 m to both sides is blocked too) snap the arm
	# in at once; anything narrower is a prop and the caller eases toward it (see PROP_HOLD).
	var offw := side.normalized() * 0.75
	_arm_hard = _collide(from + offw, to + offw) < full - 0.05 and _collide(from - offw, to - offw) < full - 0.05
	# Ground (a walkable face: floor, slope, step) is never a "thin prop": a slope grazing the end of the arm passed the
	# thin tests below and left the camera inside the hillside.
	var rq := PhysicsRayQueryParameters3D.create(from, to, 1, _soft_ex if not _soft_ex.is_empty() else [player.get_rid()])
	rq.hit_back_faces = false
	rq.hit_from_inside = false
	var rh := get_world_3d().direct_space_state.intersect_ray(rq)
	if not rh.is_empty():
		var nrm := rh["normal"] as Vector3
		# A front face that looks up and that the arm runs down into (a back face or an underside is a prop).
		if nrm.y > 0.55 and nrm.dot(to - from) < 0.0:
			_arm_ground_y = (rh["position"] as Vector3).y
	if _arm_ground_y < INF:
		_arm_hard = true
		return dc
	# Finish pass (W1 and hub tours): an ignored prop right in front of the lens filled a quarter of the frame (a hub pole,
	# the balcony rail). Props are only ignored when at least ARM_PROP_CLEAR of free arm lies between them and the camera;
	# nearer the camera the arm pulls in front of them (a short move). A camera spot inside geometry fails this test too.
	var db := _collide(to, from)
	if db < ARM_PROP_CLEAR:
		_arm_hard = true
		return dc
	var off := side.normalized() * THIN_SIDE
	var dl := _collide(from + off, to + off)
	var dr := _collide(from - off, to - off)
	if dl >= full - 0.05 and dr >= full - 0.05:
		return full
	# Finish pass (W1 tour, frames 715-745): a signpost whose boards are wider than the 0.5 m test still snapped the arm from
	# about 5 m to 1.2 m, leaving a full-screen board in front of the lens. A prop that is thin along the arm (under 0.8 m)
	# and narrower than about 1.5 m (a cast 0.75 m to one side is clear) is also ignored; the occlusion silhouette shows Mak
	# through it. Walls and buildings block both wide casts or are thick.
	if full - dc - db < 0.8:
		var off2 := side.normalized() * 0.75
		if _collide(from + off2, to + off2) >= full - 0.05 or _collide(from - off2, to - off2) >= full - 0.05:
			return full
		# Wide but low props (a signpost with two 1 m boards): the same arm raised 1.2 m passes over them.
		if _collide(from + Vector3.UP * 1.2, to + Vector3.UP * 1.2) >= full - 0.05:
			return full
	return dc


func _los_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Finish pass: NPCs and signs (group "talker") within 12 m. They are left out of the arm casts and only pull the arm
## in softly (see _update_camera).
func _refresh_soft(ppos: Vector3, dt: float) -> void:
	_soft_t -= dt
	if _soft_t > 0.0:
		return
	_soft_t = 0.25
	_soft_nodes.clear()
	_soft_ex.clear()
	_soft_ex.append(player.get_rid())
	for n in get_tree().get_nodes_in_group("talker"):
		if n is CollisionObject3D and (n as Node3D).global_position.distance_to(ppos) < 12.0:
			_soft_ex.append((n as CollisionObject3D).get_rid())
			_soft_nodes.append(n)


var _soft_ex: Array[RID] = []
var _soft_nodes: Array[Node] = []


## Distance along the arm to the first nearby NPC (talker with npc_radius), each taken as an upright cylinder (its footprint radius, 1.7 m
## tall) widened by the camera sphere; 99 when none is in the way. Only talkers count here (a plain cast would also
## catch the thin props _collide_arm deliberately ignores).
func _soft_block(from: Vector3, to: Vector3) -> float:
	var best := 99.0
	var a := Vector2(from.x, from.z)
	var dv := Vector2(to.x - from.x, to.z - from.z)
	var dd := dv.length_squared()
	if dd < 0.0001:
		return best
	for n in _soft_nodes:
		# Characters only: signs and the telescope's "Look" post are thin props the arm passes (as _collide_arm did).
		if not is_instance_valid(n) or not n.has_method("npc_radius"):
			continue
		var c3 := (n as Node3D).global_position
		var r := float(n.call("npc_radius")) + collision_radius
		var f := a - Vector2(c3.x, c3.z)
		var bq := 2.0 * f.dot(dv)
		var cq := f.length_squared() - r * r
		var disc := bq * bq - 4.0 * dd * cq
		if disc < 0.0:
			continue
		var s := (-bq - sqrt(disc)) / (2.0 * dd)
		if s < 0.0 or s > 1.0:
			continue
		var y := from.y + (to.y - from.y) * s
		if y < c3.y - collision_radius or y > c3.y + 1.7 + collision_radius:
			continue
		best = minf(best, s * (to - from).length())
	return best


## Finish pass: when a dialog opens and the arm to Mak is short (an object between the camera and Mak), pick the
## nearest yaw within 100 degrees whose level arm is at least 2.6 m long; NAN keeps the current view.
func _clear_view_yaw(ppos: Vector3) -> float:
	if _cur_dist >= 2.6 and _los_clear(cam.global_position, ppos + Vector3.UP * 0.6):
		return NAN
	var best := NAN
	for k in [20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 80.0, -80.0, 100.0, -100.0]:
		var y := yaw + deg_to_rad(float(k))
		var bb := Basis.from_euler(Vector3(minf(pitch, 0.0), y, 0.0))
		var dd := _collide(_pivot, _pivot + bb.z * maxf(_cur_target_dist, 3.0))
		if dd >= 2.6 and _los_clear(_pivot + bb.z * dd, ppos + Vector3.UP * 0.6):
			best = y
			break
	return best


func _collide(from: Vector3, to: Vector3, include_soft: Array[RID] = []) -> float:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = collision_radius
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = 1
	if include_soft.is_empty() and not _soft_ex.is_empty():
		q.exclude = _soft_ex
	else:
		var ex: Array[RID] = [player.get_rid()]
		q.exclude = ex
	var r := get_world_3d().direct_space_state.cast_motion(q)
	var frac := 1.0
	if r.size() > 0:
		frac = r[0]
	return maxf((to - from).length() * frac, min_distance)
