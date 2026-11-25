class_name MakAnimator
extends Node
## Procedural animation driver for Mr. Mak (night 01, hero pass 2; hero v2 chibi overhaul 2026-10-18 evening).
## Every rendered frame it builds a pose for the abstract rig (JOINTS) from the player's state and
## motion, then writes it through an adapter (MakRigAdapters.Skel for the rigged Tripo P2 model,
## MakRigAdapters.Proxy for the emergency proxy pig).
## Rotations are character-space Euler angles in degrees (X right, Y up, -Z forward). Positive X on a
## hanging limb swings it forward; positive X on the torso leans it back; positive Y turns left.
## Gameplay never waits for animation: the pose follows the state machine, never the other way, so
## anticipation is staged inside the first frames of an action and in landings.
##
## Principles applied per clip: anticipation (wind-ups, crouches), follow-through and overlapping action
## (spring-driven ears, tail, backpack and hat), arcs (strike swooshes, flip curves), slow in / slow out
## (eased curves), squash and stretch (spring about the feet), secondary motion (breathing, blinks, idle
## variations), clean contacts (IK feet with stride matched to ground speed) and smooth blending (per-state
## blend rates). Mak's arms are 0.17 m long on a 1.1 m body, so strikes read through the whole body:
## lunges, twists, hops and swooshes.
##
## Hero v2 overhaul (owner: "too mature, not cute, animations are so so"): the new hero is a chibi piglet whose head is
## about 45 % of his height, so every clip is retuned to read cute and lively: a head bobble spring (the big head lags and
## nods on every bounce, step and landing), bigger and softer squash and stretch with overshoot, a waddle in the walk, a
## bouncy run with a big head bob and pumping arms, a wobblier hat, bone eyelid blinks (eyelid_l/r), and new idle beats
## (happy hop, hat tip, head tilt) next to the look-around, yawn and sniff.

const JOINTS := ["root", "hips", "spine", "head", "ear_l", "ear_r", "arm_l", "forearm_l", "arm_r",
	"forearm_r", "thigh_l", "shin_l", "thigh_r", "shin_r", "tail", "backpack", "head_top",
	"ear_l_2", "ear_r_2", "tail_2", "tail_3"]
const DEG := PI / 180.0
const L1 := 0.13          ## proxy thigh length (m)
const L2 := 0.16          ## proxy shin + hoof length (m)
const HIP_H := 0.29       ## proxy hip joint height at rest (m)
const BODY_CENTER := Vector3(0.0, 0.52, 0.0)
const HANG_ROOT_Y := 0.2      ## visual root lift while hanging (chin at the lip)
const HANG_ROOT_Z := -0.17    ## lean in toward the wall so the hooves reach over the lip
const IDLE_VARIATIONS := ["look", "hop", "hattip", "yawn", "tilt", "sniffair"]
const IDLE_VAR_TIME := {"look": 2.6, "yawn": 2.4, "beanie": 2.0, "sniffair": 2.1, "hop": 1.3, "hattip": 2.2, "tilt": 1.8}
## Hero v2 eyelids (ATTACH.md): the lid bone turns about its local +X; 0 open, 115 degrees closed, about 60 sleepy.
const LID_CLOSED_DEG := 115.0

var player: MakPlayer = null
var proxy: Node3D = null
var skeleton: Skeleton3D = null
var adapter: RefCounted = null

var _rot := {}
var _trot := {}
var _root_pos := Vector3.ZERO
var _troot_pos := Vector3.ZERO
var _body_pitch := 0.0
var _tbody_pitch := 0.0
var _spine_scale := 1.0
var _tspine_scale := 1.0
var _k := 16.0
## Gait lock (clean contacts): while walking or running, the IK legs, hips and root height follow their gait
## targets exactly instead of through the low-pass blend. The blend lagged the 3-6 Hz stride (amplitude 0.53 at a
## full run), so the planted foot swept less ground than the body covered and slid. Fades in and out over 0.12 s.
const GAIT_LOCK_JOINTS := ["thigh_l", "shin_l", "thigh_r", "shin_r", "hips"]
var _gait_lock := 0.0
var _gait_lock_target := 0.0
var _gait_lock_on := true   ## --no-gait-lock turns it off for A/B foot-slip measurements
var _spin := Vector3.ZERO

var t := 0.0
var _st := 0.0
var _state := ""
var _combo_seen := 0
var gait := 0.0
var _prev_ph := [0.0, 0.5]
var _sq := 0.0
var _sq_v := 0.0
var _pop := 1.0
var _pop_v := 0.0
var _ear := [Vector2.ZERO, Vector2.ZERO]
var _ear_v := [Vector2.ZERO, Vector2.ZERO]
var _ear_target := Vector2.ZERO
var _tail := Vector2.ZERO
var _tail_v := Vector2.ZERO
var _tail_wag_speed := 3.0
var _tail_wag_amp := 12.0
var _pack := Vector2.ZERO           ## backpack spring (pitch, roll), rad
var _pack_v := Vector2.ZERO
var _hat := Vector2.ZERO            ## hat spring (pitch, roll), rad
var _hat_v := Vector2.ZERO
var _hat_sq := 0.0
var _hat_sq_v := 0.0
var _hat_tug := 0.0                 ## m, pulled down by the idle beanie adjust
var _prev_vel := Vector3.ZERO
var _accel := Vector3.ZERO
var _prev_yaw := 0.0
var _yaw_rate := 0.0
var _prev_root_y := 0.0
var _look := 0.0
var _look_target := 0.0
var _look_timer := 2.0
var _flick_timer := 1.5
var _blink_timer := 2.5
var _blink := 0.0
var _turn_blink_cd := 0.0          ## finish pass: s until a quick turn may trigger another blink
var _prev_cam_turn := 0.0
var _eye_open := 1.0
var _eye_cur := 1.0
var _lid_tilt := 0.0
var _lid_tilt_cur := 0.0
var _brow_raise := 0.0
var _idle_time := 0.0
var _idle_var := ""
var _idle_var_t := 0.0
var _idle_next := 3.0
var _idle_order: Array = []
var _rng := RandomNumberGenerator.new()
var _lids: Array[ShaderMaterial] = []
var _lid_nodes: Array[Node3D] = []
## Leg geometry used by the IK; measured from the skeleton when a rigged model is used.
var l1 := L1
var l2 := L2
var hip_h := HIP_H
var ls := 1.0             ## leg scale relative to the proxy (scales lifts and crouch depths)
var model_root: Node3D = null
var _tophat: Node3D = null
var _swooshed := ""
## Fix r1 additions: state entry data, push-off and landing overlays, world-grounded feet, strike smears.
const JUMP_KINDS := {"jump": true, "double_jump": true, "triple_jump": true, "backflip": true, "side_flip": true,
	"long_jump": true, "rollout": true, "bounce": true}
## States whose IK legs stand on the ground: after the root lean, pitch and dips are applied, any hoof below the floor
## is lifted back onto it (the IK was solved in hip space before the root transform, so strikes sank 4.5 cm).
const GROUND_FEET_STATES := {"idle": true, "walk": true, "sniff": true, "skid": true, "crouch": true, "crouch_slide": true,
	"punch": true, "slam_land": true, "slide_getup": true, "celebrate": true}
const LAND_OVERLAY_STATES := {"idle": true, "walk": true, "crouch": true, "skid": true, "sniff": true}
var _prev_state_name := ""
var _entry_vy := 0.0
var _land_snap := 0.0
var _land_t := 99.0
var _land_amt := 0.0
var _ik_req := {}
var _foot_fix := {"l": 0.0, "r": 0.0}
var _foot_bones := [-1, -1]
var _sole_h := 0.0
var _smear := {}
## Second ear segments and the three-segment tail (chained springs: each lags its parent).
var _ear2 := [Vector2.ZERO, Vector2.ZERO]
var _ear2_v := [Vector2.ZERO, Vector2.ZERO]
var _tail2 := Vector2.ZERO
var _tail2_v := Vector2.ZERO
var _tail3 := Vector2.ZERO
var _tail3_v := Vector2.ZERO
## Fix r2 (hero fix stage round 1b): world-locked run contacts, brake and settle, slam impact squash, idle arm variety.
const EXHALE_FROM := {"punch": true, "slam_land": true, "slide_getup": true, "backflip": true, "triple_jump": true,
	"side_flip": true, "hurt_land": true, "ledge_climb": true, "skid": true, "rollout": true}
const LOCK_GAIN := 0.72          ## measured ratio of real ankle travel to hip-space IK travel on the Tripo rig
var _lock_gain := LOCK_GAIN      ## finish pass: --lock-gain=<x> overrides it for A/B foot-slip measurements
var _foot_lock_on := true      ## --no-foot-lock turns the world-locked contacts off for A/B foot-slip measurements
var _run_boost_on := true      ## --no-run-boost restores the run before the owner's 2026-10-19 amplitude fix (A/B captures)
var _lock_on := [false, false]
var _lock_pt := [Vector3.ZERO, Vector3.ZERO]
var _lock_f := [0.0, 0.0]
var _brake_t := -1.0             ## s into the current brake (-1 when not braking)
var _brake_lead := 0             ## leading hoof of the brake plant (0 left, 1 right)
var _settle_t := 99.0            ## s since a brake ended in a stop (forward-and-back weight settle)
var _slam_land_t := 99.0
var _idle_arm := 0               ## idle arm set: 0 clasp, 1 hooves on hips, 2 strap adjust, 3 loose hang
var _idle_arm_t := 0.0
var _idle_arm_w := 0.0
## Hero v2 state.
var hero_v2 := false
var v2_parts := {}                  ## set by MakPlayer: "pack", "top_hat", "beanie" nodes under their BoneAttachment3D
var _hat_id := "top_hat"
var _lid_bones := [-1, -1]
var _lid_rest := [Quaternion.IDENTITY, Quaternion.IDENTITY]
var _hb := 0.0                      ## head bobble spring (rad, + = chin up): the big head lags behind every bounce
var _hb_v := 0.0
var _hat_lift := 0.0                ## m, hat raised off the head (hat tip)
var _hat_tip := 0.0                 ## rad, hat tipped forward (hat tip)
var _arm_stretch_r := 0.0           ## extra stretch of the right arm (hat tip reach), applied as a smear
var _arm_stretch_l := 0.0
## Hero v2 fix r1 (critic round 1: animation director, appeal and feel lenses).
## ARM_ABD: every pose gets this much extra arm abduction so at least one hoof clears the torso and head silhouette.
const ARM_ABD := 12.0
const LAND_SQ_MIN := -0.2          ## normal landings never squash below 0.80
const SLAM_SQ_MIN := -0.3          ## the Ham Slam impact stops at 0.70
var _tsq_hold := 0.0                ## sustained squash target (crouch), blended into _sq_hold
var _sq_hold := 0.0
var _cam_turn := 0.0                ## rad, idle turn of the whole body toward the camera (feel F4)
var _cam_turn_target := 0.0
var _cam_side := 1.0
var _idle_look_add := 0.0
var _cam_turn_on := true            ## --no-cam-turn turns it off (fixed-angle look-dev captures)
var _cel_yaw := 0.0                 ## rad, celebrate turn to the camera, captured on entry
var _thigh_stretch_r := 0.0
var _hang_kick := 0.0
var _ceil_k := 0.0                  ## 0..1, a ceiling within 0.8 m above the hat halves the head and hat stretch (feel F5)
var _fold := [0.0, 0.0]
var _probe_t := 0.0


func setup(p: Node, proxy_node: Node3D, skel: Skeleton3D) -> void:
	# Keep animating while the tree is paused, but only for the celebration (see _process).
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = p as MakPlayer
	proxy = proxy_node
	skeleton = skel
	if skel != null:
		adapter = MakRigAdapters.Skel.new(skel, player.visual, JOINTS)
		_measure_legs(skel)
		hero_v2 = skel.find_bone("eyelid_l") >= 0 and skel.find_bone("eyelid_r") >= 0
		if hero_v2:
			# Hero v2 has rigged eyelids: blink by turning the lid bones (no shader lids).
			for i in 2:
				var bi := skel.find_bone("eyelid_l" if i == 0 else "eyelid_r")
				_lid_bones[i] = bi
				_lid_rest[i] = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
		else:
			_lids = MakRigFix.add_eyelids(skel, MakRigFix.sample_lid_skin(player.visual))
			var sock := skel.get_node_or_null("EyelidSocket")
			if sock != null:
				for c in sock.get_children():
					_lid_nodes.append(c as Node3D)
	elif proxy_node != null:
		adapter = MakRigAdapters.Proxy.new(proxy_node)
	if player != null and player.visual != null:
		# The skeleton and its attachments must keep updating during the TRUFFLE GET pause.
		player.visual.process_mode = Node.PROCESS_MODE_ALWAYS
	for j in JOINTS:
		_rot[j] = Vector3.ZERO
		_trot[j] = Vector3.ZERO
	_rng.seed = 6464
	var dev := get_tree().root.get_node_or_null("Dev") if is_inside_tree() else null
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "no-gait-lock")):
		_gait_lock_on = false
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "no-foot-lock")):
		_foot_lock_on = false
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "no-cam-turn")):
		_cam_turn_on = false
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "no-run-boost")):
		_run_boost_on = false
	if dev != null and dev.has_method("arg") and str(dev.call("arg", "lock-gain", "")) != "":
		_lock_gain = clampf(float(str(dev.call("arg", "lock-gain", ""))), 0.2, 2.0)
	if player != null:
		_prev_yaw = player.facing_yaw
		player.landed.connect(_on_landed)
		player.jumped.connect(_on_jumped)
		player.ground_pounded.connect(_on_slam)
		player.teleported.connect(_on_teleported)
		player.attacked.connect(_on_attacked)


func _measure_legs(skel: Skeleton3D) -> void:
	var tr := player.visual.global_transform.affine_inverse() * skel.global_transform
	var th := skel.find_bone("thigh_r")
	var sh := skel.find_bone("shin_r")
	var ft := skel.find_bone("foot_r")
	if th < 0 or sh < 0:
		return
	var p_th := tr * skel.get_bone_global_rest(th).origin
	var p_sh := tr * skel.get_bone_global_rest(sh).origin
	var sole := 0.0
	var l2m := p_sh.y - sole
	if ft >= 0:
		var p_ft := tr * skel.get_bone_global_rest(ft).origin
		l2m = (p_ft - p_sh).length() + maxf(p_ft.y - sole, 0.0)
	var l1m := (p_sh - p_th).length()
	if l1m < 0.02 or l2m < 0.02:
		return
	l1 = l1m
	l2 = l2m
	hip_h = p_th.y
	_foot_bones = [skel.find_bone("foot_l"), skel.find_bone("foot_r")]
	if ft >= 0:
		_sole_h = (tr * skel.get_bone_global_rest(ft).origin).y
	ls = clampf((l1 + l2) / (L1 + L2), 0.3, 2.0)
	print("[MakAnimator] rigged legs: thigh %.3f m, shin+foot %.3f m, hip %.3f m, leg scale %.2f" % [l1, l2, hip_h, ls])


func set_hat(id: String) -> void:
	_hat_id = id
	if proxy != null and proxy.has_method("set_hat") and skeleton == null:
		proxy.call("set_hat", id)
		return
	if hero_v2:
		# Hero v2 kit: the top hat and the beanie both sit on the head_top socket; show one. Hats without a v2 model
		# (bowler, tea cosy, deerstalker) fall back to the top hat, Mak's default.
		var beanie_on := id == "beanie" and v2_parts.has("beanie")
		if v2_parts.has("beanie"):
			(v2_parts["beanie"] as Node3D).visible = beanie_on
		if v2_parts.has("top_hat"):
			(v2_parts["top_hat"] as Node3D).visible = not beanie_on
		_hat_sq_v -= 2.5
		return
	if skeleton != null:
		# mak_v2.glb carries its beanie under the head_top socket; the top hat attaches there too
		# (offsets from res://assets/characters/mak/attach.json, model space).
		var beanie := _find_named(model_root if model_root != null else skeleton, "beanie")
		if id == "top_hat":
			if _tophat == null:
				var path := "res://assets/characters/mak/mak_tophat.glb"
				if ResourceLoader.exists(path) and skeleton.find_bone("head_top") >= 0:
					var att := BoneAttachment3D.new()
					att.name = "TopHatSocket"
					att.bone_name = "head_top"
					skeleton.add_child(att)
					var h := (load(path) as PackedScene).instantiate() as Node3D
					att.add_child(h)
					# Fix r2 (visual polish p3): a little bigger and seated 1 cm lower so the brim meets the ear roots.
					h.position = Vector3(0.0, -0.1025, -0.01)
					h.rotation_degrees = Vector3(-5.0, 0.0, 10.0)
					h.scale = Vector3.ONE * 1.2
					_tophat = att
					# Match the body's look (toon unless the player runs with --pbr).
					var body_toon := _find_named(model_root if model_root != null else skeleton, "body")
					var bm := body_toon as MeshInstance3D
					if bm != null and bm.get_surface_override_material(0) is ShaderMaterial:
						var fx := load("res://scripts/fx/fx_toon.gd")
						if fx != null:
							# Fix r2 (visual major M2): the default lavender shade and 0.45 rim turned the black silk purple
							# under W2's sky. Neutral shade, a faint rim and one hard glossy band; the crown stays near black.
							fx.call("apply", h, {"rim": 0.18, "spec": 0.5, "outline_width": 1.6,
								"shadow_tint": Color(0.62, 0.62, 0.64)})
							_tune_hat(h)
			if _tophat != null:
				_tophat.visible = true
				if beanie != null:
					beanie.visible = false
		else:
			if beanie != null:
				beanie.visible = true
			if _tophat != null:
				_tophat.visible = false
		# A little hat-settling bounce whenever it changes.
		_hat_sq_v -= 2.5


func _tune_hat(h: Node) -> void:
	var stack: Array[Node] = [h]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si) as ShaderMaterial
			if m == null:
				continue
			var d := m.duplicate() as ShaderMaterial
			d.set_shader_parameter("spec_size", 0.12)
			d.set_shader_parameter("rim_color", Color(0.85, 0.86, 0.9))
			var a: Variant = d.get_shader_parameter("albedo")
			var base: Color = a if a is Color else Color.WHITE
			# Neutral, darker crown: pull the albedo multiplier toward grey so the purple cast in the texture goes.
			d.set_shader_parameter("albedo", Color(base.r * 0.78, base.g * 0.76, base.b * 0.74, base.a))
			mi.set_surface_override_material(si, d)


func _find_named(n: Node, key: String) -> Node3D:
	if n == null:
		return null
	for c in n.get_children():
		if c is Node3D and str(c.name).to_lower().contains(key) and c != _tophat:
			return c as Node3D
		var r := _find_named(c, key)
		if r != null:
			return r
	return null


func kick(kind: String) -> void:
	if kind == "jump":
		# Push-off: squash on the press frame, springing into the launch stretch over the next frames
		# (the pose side of the push-off is staged in _overlays).
		_sq = minf(_sq, -0.12)
		_sq_v = 3.4
		_land_t = 99.0
		_pack_v.x -= 4.0
		_hat_v.x -= 3.0


# ------------------------------------------------------------------ signal reactions

func _on_landed(impact: float) -> void:
	_land_t = 0.0
	_land_amt = clampf(impact / 13.0, 0.25, 1.0)
	var s := clampf(impact * 0.024, 0.06, 0.36)
	_sq = minf(_sq, -s)
	_sq_v = 0.0
	for i in 2:
		var ev: Vector2 = _ear_v[i]
		_ear_v[i] = ev + Vector2(-impact * 1.0, impact * 0.55)
	_tail_v += Vector2(impact * 0.8, 0.0)
	_pack_v.x += impact * 0.6
	_hat_v.x += impact * 0.35
	_hat_sq_v -= impact * 0.15
	# Hero v2: the big head nods into the landing (cute, rubbery). Fix r1 (animation blocker): the landing pancaked Mak, crushed
	# the hat into the head and dropped the head below the shoulders, so the squash is capped at 0.80 and the nod is softer;
	# the bounce comes from the spring's overshoot (about 1.05) and the ear flick and hat lift in _overlays.
	_hb_v -= impact * 0.22
	_sq = maxf(minf(_sq, -clampf(impact * 0.02, 0.06, 0.2)), LAND_SQ_MIN)
	# The legs snap to their stand targets on the landing frame (the slow idle blend left the air pose's reaching hooves
	# under the floor for a frame).
	_gait_lock = 1.0


func _on_jumped(kind: String) -> void:
	for i in 2:
		var ev: Vector2 = _ear_v[i]
		_ear_v[i] = ev + Vector2(6.0, -2.5)
	_pack_v.x -= 3.0
	_hb_v -= 3.5
	_hat_sq_v += 2.0
	if kind == "wall_kick":
		_sq = 0.2
		_sq_v = 1.0


func _on_slam(_pos: Vector3) -> void:
	_sq = SLAM_SQ_MIN
	_hb_v -= 5.0
	_sq_v = 0.0
	_hat_sq_v -= 3.0
	_gait_lock = 1.0
	_pack_v.x += 9.0
	for i in 2:
		var ev: Vector2 = _ear_v[i]
		_ear_v[i] = ev + Vector2(-14.0, 9.0)


func _on_attacked(kind: String) -> void:
	if player == null or player.visual == null:
		return
	# Strike swooshes (arcs) parented to the Visual node (forward = -Z).
	var v := player.visual
	match kind:
		"punch":
			var right := player.combo_step != 2
			if right:
				MakSwoosh.spawn(v, {"a0": -110.0, "a1": 25.0, "r": 0.6, "h": 0.5, "w": 0.28, "life": 0.24})
			else:
				MakSwoosh.spawn(v, {"a0": 110.0, "a1": -25.0, "r": 0.6, "h": 0.54, "w": 0.28, "life": 0.24})
		"kick":
			MakSwoosh.spawn(v, {"a0": 40.0, "a1": 400.0, "r": 0.72, "h": 0.26, "w": 0.3, "life": 0.4})
		"jump_kick":
			MakSwoosh.spawn(v, {"a0": 160.0, "a1": 60.0, "r": 0.58, "h": 0.35, "w": 0.24, "life": 0.26, "axis": "x"})
		"dive":
			MakSwoosh.spawn(v, {"a0": 150.0, "a1": 80.0, "r": 0.66, "h": 0.3, "w": 0.22, "life": 0.24, "axis": "x"})


func _on_teleported() -> void:
	_root_pos = Vector3.ZERO
	_body_pitch = 0.0
	_spin = Vector3.ZERO
	# Respawn pop-in: grow from small with an overshoot.
	_pop = 0.25
	_pop_v = 0.0
	if player != null:
		_prev_yaw = player.facing_yaw
		_prev_vel = Vector3.ZERO


## World position of the striking hoof for hit feedback (fix r1), or Vector3.INF without a skeleton.
func strike_point(kind: String) -> Vector3:
	if skeleton == null:
		return Vector3.INF
	var bone := "hand_r"
	if kind == "kick" or kind == "jump_kick" or kind == "slide":
		bone = "foot_r"
	elif kind == "punch" and player != null and player.combo_step == 2:
		bone = "hand_l"
	var bi := skeleton.find_bone(bone)
	if bi < 0:
		return Vector3.INF
	return skeleton.global_transform * skeleton.get_bone_global_pose(bi).origin


## PoseLab hooks.
func debug_idle_variation(id: String) -> void:
	_idle_time = 5.0
	_idle_var = id
	_idle_var_t = 0.0


func debug_idle_arm(id: int) -> void:
	_idle_arm = id
	_idle_arm_t = 99.0
	_idle_time = 1.5


func debug_blink() -> void:
	_blink = 0.05


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if player == null or adapter == null:
		return
	if get_tree().paused and player.state != "celebrate":
		return
	var dt := clampf(delta, 0.0001, 0.05)
	t += dt
	var s := player.state
	if s != _state or (s == "punch" and player.combo_step != _combo_seen):
		_prev_state_name = _state
		_state = s
		_st = 0.0
		_combo_seen = player.combo_step
		_entry_vy = player.vy
		_land_snap = 0.0
		if s == "celebrate":
			# Fix r1: the celebration turns to the camera within 6 frames (it opened with 10-15 frames of his back).
			var cy0 := _camera_rel_yaw()
			_cel_yaw = cy0 if absf(cy0) < 4.0 else 0.0
		if _prev_state_name == "skid" and (s == "idle" or s == "walk"):
			_settle_t = 0.0
			for i in 2:
				var ev0: Vector2 = _ear_v[i]
				_ear_v[i] = ev0 + Vector2(8.0, -2.0)
			_hat_v.x -= 4.0
		if s == "ledge_hang":
			for i in 2:
				var ev1: Vector2 = _ear_v[i]
				_ear_v[i] = ev1 + Vector2(-6.0, 9.0)
	else:
		_st += dt
	var vel := player.velocity
	var hs := Vector2(vel.x, vel.z).length()
	var yr := angle_difference(_prev_yaw, player.facing_yaw) / dt
	_prev_yaw = player.facing_yaw
	_yaw_rate = lerpf(_yaw_rate, clampf(yr, -12.0, 12.0), 1.0 - exp(-10.0 * dt))
	_accel = _accel.lerp((vel - _prev_vel) / dt, 1.0 - exp(-12.0 * dt))
	_prev_vel = vel
	# Brake and settle timers (fix r2): the controller's hard brake (stick released at speed) gets a planted stop.
	var braking_now := player.braking and s == "walk" and hs > 0.3
	if braking_now:
		if _brake_t < 0.0:
			_brake_t = 0.0
			# The hoof that is further forward right now leads the plant.
			_brake_lead = 0 if fmod(gait, 1.0) < 0.5 else 1
			for i in 2:
				var ev: Vector2 = _ear_v[i]
				_ear_v[i] = ev + Vector2(9.0, -3.0)
			_pack_v.x += 6.0
			_hat_v.x += 4.0
		else:
			_brake_t += dt
	elif _brake_t >= 0.0:
		if s == "idle" or (s == "walk" and hs < 0.6):
			_settle_t = 0.0
		_brake_t = -1.0
	_settle_t += dt
	_slam_land_t += dt
	_reset_targets()
	_pose(s, dt, hs)
	_overlays(s, dt)
	_blend(dt)
	_apply(dt)
	_ground_feet(s, dt)


func _reset_targets() -> void:
	for j in JOINTS:
		_trot[j] = Vector3.ZERO
	_troot_pos = Vector3.ZERO
	_tbody_pitch = 0.0
	_tspine_scale = 1.0
	_spin = Vector3.ZERO
	_k = 16.0
	_gait_lock_target = 0.0
	_ear_target = Vector2.ZERO
	_eye_open = 1.0
	_lid_tilt = 0.0
	_brow_raise = 0.0
	_tail_wag_speed = 3.0
	_tail_wag_amp = 12.0
	_hat_tug = 0.0
	_hat_lift = 0.0
	_hat_tip = 0.0
	_arm_stretch_r = 0.0
	_arm_stretch_l = 0.0
	_thigh_stretch_r = 0.0
	_tsq_hold = 0.0
	_cam_turn_target = 0.0
	_ik_req.clear()


func _r(j: String, x: float, y: float = 0.0, z: float = 0.0) -> void:
	_trot[j] = Vector3(x, y, z) * DEG


func _arms(lx: float, lz: float, rx: float, rz: float, lf: float = 15.0, rf: float = 15.0) -> void:
	# Hero v2 fix r1 (animation major): the stubby arms vanished inside the torso and head silhouette in most poses, so
	# every arm target gets a global abduction offset.
	var abd := ARM_ABD if hero_v2 else 0.0
	_r("arm_l", lx, 0.0, -(lz + abd))
	_r("arm_r", rx, 0.0, rz + abd)
	_r("forearm_l", lf)
	_r("forearm_r", rf)


func _leg_raw(side: String, thigh: float, shin: float, splay: float = 0.0) -> void:
	_r("thigh_" + side, thigh, 0.0, splay * (-1.0 if side == "l" else 1.0))
	_r("shin_" + side, shin)
	_ik_req.erase(side)


## Two-bone leg IK in the sagittal plane: foot target f metres forward of the hip, d metres below it.
## The ground pass (_ground_feet) shortens d by _foot_fix when the root transform would push the hoof into the floor.
func _leg_ik(side: String, f: float, d: float, splay: float = 0.0) -> void:
	_ik_req[side] = Vector3(f, d, splay)
	var sol := _ik_solve(f, d - float(_foot_fix[side]))
	_trot["thigh_" + side] = Vector3(sol.x, 0.0, splay * DEG * (-1.0 if side == "l" else 1.0))
	_trot["shin_" + side] = Vector3(sol.y, 0.0, 0.0)


func _ik_solve(f: float, d: float) -> Vector2:
	var dd := sqrt(f * f + d * d)
	dd = clampf(dd, 0.04 * ls, l1 + l2 - 0.002)
	var a := atan2(f, d)
	var b := acos(clampf((l1 * l1 + dd * dd - l2 * l2) / (2.0 * l1 * dd), -1.0, 1.0))
	var k := acos(clampf((l1 * l1 + l2 * l2 - dd * dd) / (2.0 * l1 * l2), -1.0, 1.0))
	return Vector2(a + b, -(PI - k))


func _stand_legs(root_y: float, fl: float = 0.0, fr: float = 0.0, splay: float = 2.0) -> void:
	_leg_ik("l", fl * ls, hip_h + root_y - 0.004 * ls, splay)
	_leg_ik("r", fr * ls, hip_h + root_y - 0.004 * ls, splay)


func _ease_out(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)


func _ease_in(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c


func _ease_io(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _seg(u: float, a: float, b: float) -> float:
	return clampf((u - a) / maxf(b - a, 0.0001), 0.0, 1.0)


func _bell(u: float, a: float, b: float) -> float:
	## 0 outside [a, b], 1 in the middle, eased.
	return sin(_seg(u, a, b) * PI)


# ------------------------------------------------------------------ poses

func _pose(s: String, dt: float, hs: float) -> void:
	if s != "idle":
		_idle_time = 0.0
		_idle_var = ""
	match s:
		"idle":
			_pose_idle(dt)
		"walk":
			_pose_walk(dt, hs, false)
		"sniff":
			_pose_walk(dt, hs, true)
		"skid":
			_pose_skid()
		"crouch":
			_pose_crouch(dt, hs)
		"crouch_slide":
			_pose_crouch_slide()
		"punch":
			_pose_punch()
		"slam_land":
			_pose_slam_land()
		"belly_slide":
			_pose_belly_slide(hs)
		"slide_getup":
			_pose_getup()
		"slope_slide":
			_pose_butt_slide()
		"celebrate":
			_pose_celebrate()
		"hurt_land", "dead":
			_pose_lying(s)
		"ledge_hang":
			_pose_ledge_hang()
		"ledge_climb":
			_pose_ledge_climb()
		"pole_climb":
			_pose_pole()
		"jump":
			_pose_jump(false)
		"bounce":
			_pose_bounce()
		"double_jump":
			_pose_jump(true)
		"wall_kick":
			_pose_wall_kick()
		"triple_jump":
			_pose_flip(Vector3(-1.0, 0.0, 0.0), 0.62, true)
		"backflip":
			_pose_flip(Vector3(1.0, 0.0, 0.0), 0.7, false)
		"side_flip":
			_pose_flip(Vector3(0.0, 0.0, 1.0), 0.62, false)
		"rollout":
			_pose_flip(Vector3(-1.0, 0.0, 0.0), 0.42, true)
		"long_jump":
			_pose_long_jump()
		"dive":
			_pose_dive()
		"jump_kick":
			_pose_jump_kick()
		"wall_slide":
			_pose_wall_slide()
		"ham_slam":
			_pose_ham_slam()
		"hurt_air":
			_pose_hurt_air()
		"bonk":
			_pose_bonk()
		"fallout":
			_pose_fallout()
		_:
			_pose_fall()


func _pose_idle(dt: float) -> void:
	_idle_time += dt
	_idle_look_add = 0.0
	var breath := sin(t * 2.3)
	_tspine_scale = 1.0 + (0.026 if hero_v2 else 0.018) * breath
	# Slow weight shift from foot to foot.
	var shift := sin(t * 0.85)
	_troot_pos = Vector3(0.012 * shift, -0.006 - 0.003 * breath, 0.0)
	_trot["root"] = Vector3(0.0, 0.0, -0.025 * shift)
	_r("spine", -2.0 + 1.4 * breath, 0.0, 2.0 * shift)
	_r("head", 3.0 + 2.6 * breath, 3.0 * sin(t * 0.53), -2.5 * shift + 2.0 * sin(t * 0.71))
	_idle_arms(dt, breath)
	_stand_legs(_troot_pos.y, 0.012, -0.012, 3.0)
	# Fix r2: after an action (strikes, slam, flips, a brake) the first 0.8 s of idle is an exhale and a little
	# shake-out instead of a static hold.
	if _st < 0.8 and EXHALE_FROM.has(_prev_state_name):
		var ex := _bell(_st, 0.05, 0.8)
		var sp0: Vector3 = _trot["spine"]
		sp0.x += -6.0 * DEG * ex
		_trot["spine"] = sp0
		var hd0: Vector3 = _trot["head"]
		hd0.x += -5.0 * DEG * ex
		hd0.z += 7.0 * DEG * sin(_st * 16.0) * _bell(_st, 0.35, 0.8)
		_trot["head"] = hd0
		_troot_pos.y -= 0.012 * ls * ex
		_tspine_scale -= 0.03 * ex
		_eye_open = 1.0 - 0.5 * _bell(_st, 0.1, 0.45)
	_flick_timer -= dt
	if _flick_timer <= 0.0:
		_flick_timer = _rng.randf_range(1.6, 4.2)
		var i := _rng.randi_range(0, 1)
		var ev: Vector2 = _ear_v[i]
		_ear_v[i] = ev + Vector2(_rng.randf_range(-9.0, 9.0), _rng.randf_range(7.0, 11.0))
	_tail_wag_speed = 2.2
	_tail_wag_amp = 14.0
	_k = 9.0
	# Idle variations: a gentle look around first, then a cycle of little character beats.
	if _idle_var == "":
		_idle_next -= dt
		if _idle_time > 2.2 and _idle_next <= 0.0:
			if _idle_order.is_empty():
				_idle_order = IDLE_VARIATIONS.duplicate()
				_idle_order.shuffle()
			_idle_var = str(_idle_order.pop_back())
			_idle_var_t = 0.0
	# Fix r1 (feel F4): the gameplay camera sits behind Mak, so the cute face and the idle beats played to the back of his
	# head (91 % of idle frames). After 0.6 s of idle the whole body turns up to 90 degrees toward the camera (eased, see
	# _apply) and the head adds up to 45 degrees, so the face and the beats read at three-quarters.
	var cy := _camera_rel_yaw()
	if hero_v2 and _cam_turn_on and absf(cy) < 4.0 and _idle_time > 0.6 and not (_st < 0.8 and EXHALE_FROM.has(_prev_state_name)):
		if absf(cy) > 2.9:
			cy = absf(cy) * _cam_side          # straight behind: keep turning the same way (no flip-flop)
		else:
			_cam_side = signf(cy) if cy != 0.0 else _cam_side
		var body_turn := clampf(cy, -90.0 * DEG, 90.0 * DEG)
		_cam_turn_target = body_turn
		var look := clampf(cy - body_turn, -45.0 * DEG, 45.0 * DEG) * _ease_io(clampf((_idle_time - 0.9) / 0.5, 0.0, 1.0))
		if _idle_var == "" or _idle_var == "hattip" or _idle_var == "hop":
			_idle_look_add = look       # added after the idle beats (they set the head themselves)
			if _idle_var == "":
				var hd_l2: Vector3 = _trot["head"]
				hd_l2.x += 3.0 * DEG
				_trot["head"] = hd_l2
				_brow_raise = 0.35
	elif _idle_var == "" and _idle_time > 4.0 and absf(cy) < 2.6:
		var look2 := clampf(cy, -35.0 * DEG, 35.0 * DEG) * _ease_io(clampf((_idle_time - 4.0) / 0.6, 0.0, 1.0))
		_r("head", 6.0 + 2.0 * breath, look2 / DEG, -2.5 * shift)
		_r("spine", -2.0 + 1.4 * breath, look2 / DEG * 0.25, 2.0 * shift)
		_brow_raise = 0.35
	if _idle_var != "":
		_idle_var_t += dt
		var dur: float = IDLE_VAR_TIME.get(_idle_var, 2.0)
		var u := _idle_var_t / dur
		if u >= 1.0:
			_idle_var = ""
			_idle_next = _rng.randf_range(1.2, 2.4)
		else:
			match _idle_var:
				"look":
					_idle_look(u)
				"yawn":
					_idle_yawn(u)
				"beanie":
					_idle_beanie(u)
				"sniffair":
					_idle_sniff_air(u)
				"hop":
					_idle_hop(u)
				"hattip":
					if _hat_id == "beanie" or not hero_v2:
						_idle_beanie(u)
					else:
						_idle_hat_tip(u)
				"tilt":
					_idle_tilt(u)
	if absf(_idle_look_add) > 0.0001:
		var hd_la: Vector3 = _trot["head"]
		hd_la.y += _idle_look_add
		_trot["head"] = hd_la


## Fix r2 (arm range): idle arm sets so the hooves do not sit clasped on the belly. Mak cycles every 4-7 s between
## arms hanging loose with a little drag, hooves on the hips, a backpack strap adjust and the gentleman's hooves behind
## his back. Transitions ride the idle blend (k 9, about 0.3 s).
func _idle_arms(dt: float, breath: float) -> void:
	_idle_arm_t -= dt
	if _idle_arm_t <= 0.0:
		_idle_arm_t = _rng.randf_range(4.0, 7.0)
		_idle_arm = (_idle_arm + 1 + _rng.randi_range(0, 2)) % 4 if _idle_time > 1.0 else 0
	var drag := clampf(_accel.y * -0.4, -6.0, 6.0)
	match _idle_arm:
		1:
			_arms(-14.0 + breath, 46.0, -14.0 + breath, 46.0, 104.0, 104.0)
		2:
			var tug := maxf(0.0, sin(t * 5.0)) * 8.0
			_arms(4.0 + 2.0 * breath, 24.0, 118.0 + tug, 8.0, 18.0, 128.0 - tug)
			var sh: Vector3 = _trot["spine"]
			sh.z += -3.0 * DEG
			_trot["spine"] = sh
		3:
			_arms(-34.0 + breath, 16.0, -34.0 + breath, 16.0, 46.0, 46.0)
			var sp: Vector3 = _trot["spine"]
			sp.x += 4.0 * DEG
			_trot["spine"] = sp
		_:
			_arms(3.0 + 2.5 * breath + drag, 26.0 + 2.0 * breath, 3.0 + 2.5 * breath + drag, 26.0 + 2.0 * breath, 12.0, 12.0)


func _camera_rel_yaw() -> float:
	## Yaw (rad) from Mak's facing to the active camera, positive to his left.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or player == null:
		return 99.0
	var to := cam.global_position - player.global_position
	to.y = 0.0
	if to.length() < 0.2:
		return 99.0
	return angle_difference(player.facing_yaw, atan2(-to.x, -to.z))


func _idle_look(u: float) -> void:
	# Look left, hold, sweep right, hold, back: the head leads, the spine follows a beat later.
	var yaw := 0.0
	if u < 0.15:
		yaw = 42.0 * _ease_io(u / 0.15)
	elif u < 0.4:
		yaw = 42.0
	elif u < 0.58:
		yaw = lerpf(42.0, -40.0, _ease_io((u - 0.4) / 0.18))
	elif u < 0.82:
		yaw = -40.0
	else:
		yaw = lerpf(-40.0, 0.0, _ease_io((u - 0.82) / 0.18))
	_r("head", 4.0 + 6.0 * _bell(u, 0.15, 0.4), yaw, -yaw * 0.12)
	_r("spine", -2.0, yaw * 0.22)
	_brow_raise = 0.5
	_ear_target = Vector2(-0.25 - 0.4 * clampf((absf(yaw) - 25.0) / 15.0, 0.0, 1.0), 0.0)
	_k = 10.0


func _idle_yawn(u: float) -> void:
	# Inhale (anticipation), big stretch with the eyes shut, a shake and settle.
	var up := _ease_io(_seg(u, 0.0, 0.3)) * (1.0 - _ease_io(_seg(u, 0.72, 0.95)))
	_r("spine", lerpf(-2.0, 14.0, up), 0.0)
	_r("head", lerpf(3.0, 28.0, up), 0.0, 6.0 * sin(u * 9.0) * up)
	_arms(lerpf(6.0, 70.0, up), lerpf(12.0, 72.0, up), lerpf(6.0, 70.0, up), lerpf(12.0, 72.0, up),
		lerpf(18.0, 40.0, up), lerpf(18.0, 40.0, up))
	_tspine_scale = 1.0 + 0.06 * up
	_troot_pos.y += 0.008 * up
	_stand_legs(_troot_pos.y, 0.012, -0.012, 3.0)
	_eye_open = lerpf(1.0, 0.0, _ease_io(_seg(u, 0.18, 0.32))) if u < 0.75 else _ease_io(_seg(u, 0.75, 0.9))
	_ear_target = Vector2(-0.6 * up, 0.5 * up)
	if u > 0.78 and u < 0.92:
		# Shake it off.
		_r("head", 3.0, 18.0 * sin(t * 30.0), 0.0)
	_k = 7.0


func _idle_beanie(u: float) -> void:
	# Reach up to the beanie, give it a tug and a wiggle, then a satisfied little nod.
	var reach := _ease_io(_seg(u, 0.0, 0.25)) * (1.0 - _ease_io(_seg(u, 0.72, 0.95)))
	var tug := _bell(u, 0.3, 0.6)
	_arms(6.0, 12.0, lerpf(6.0, 150.0, reach), lerpf(12.0, 35.0, reach), 18.0, lerpf(18.0, 105.0, reach))
	# Fix r1: the head tilts down and toward the raised hoof so hoof and beanie meet (it read as a cheek scratch).
	_r("head", lerpf(3.0, -22.0, reach) + 6.0 * tug, -8.0 * reach, lerpf(0.0, -24.0, reach))
	_r("spine", -2.0, 0.0, -9.0 * reach)
	_hat_tug = -0.022 * tug
	_r("head_top", 0.0, 10.0 * sin(u * 30.0) * tug, -6.0 * reach)
	if u > 0.78:
		_r("head", 3.0 + 10.0 * _bell(u, 0.8, 0.95), 0.0)
	_eye_open = 1.0 - 0.6 * tug
	_k = 10.0


func _idle_sniff_air(u: float) -> void:
	# Snout up, three quick sniffs, a pleased wiggle.
	var up := _ease_io(_seg(u, 0.0, 0.2)) * (1.0 - _ease_io(_seg(u, 0.8, 1.0)))
	var sniffs := 0.0
	if u > 0.22 and u < 0.7:
		sniffs = maxf(0.0, sin((u - 0.22) * 40.0))
	_r("head", lerpf(3.0, 24.0, up) + 5.0 * sniffs, 6.0 * sin(u * 6.0) * up)
	_r("spine", lerpf(-2.0, 6.0, up))
	_troot_pos.y += 0.012 * up
	_stand_legs(_troot_pos.y, 0.012, -0.012, 3.0)
	_eye_open = lerpf(1.0, 0.45, up)
	_ear_target = Vector2(0.45 * up, -0.2 * up)
	_tail_wag_speed = lerpf(2.2, 16.0, _bell(u, 0.6, 1.0))
	_tail_wag_amp = lerpf(14.0, 28.0, _bell(u, 0.6, 1.0))
	if sniffs > 0.95 and player != null and fmod(t, 0.2) < 0.02:
		player.on_anim_event("sniff_air")
	_k = 11.0


## Hero v2 idle beat: a happy little hop in place. Squat (anticipation), spring up with a stretch and the hooves
## flapping, tuck the legs, land in a squash, and the head bobble and ears carry the follow-through.
func _idle_hop(u: float) -> void:
	var squat := _bell(u, 0.0, 0.3) * (1.0 - _seg(u, 0.18, 0.3))
	var air := _bell(u, 0.22, 0.62)
	var land := _bell(u, 0.58, 0.85)
	var h := 0.1 * air
	# Fix r1: a deeper, readable wind-up squat (8 frames of anticipation) before the hop.
	_troot_pos.y += h - 0.07 * ls * squat - 0.03 * ls * land
	_tsq_hold = -0.12 * squat
	if u > 0.2 and u < 0.24:
		_sq = maxf(_sq, 0.14)
		_sq_v = maxf(_sq_v, 1.5)
	if u > 0.6 and u < 0.64:
		_sq = minf(_sq, -0.16)
		_hb_v -= 2.0
	if air > 0.15:
		_leg_raw("l", 40.0 * air, -70.0 * air, 6.0)
		_leg_raw("r", 30.0 * air, -60.0 * air, 6.0)
	else:
		_stand_legs(_troot_pos.y, 0.012, -0.012, 3.0)
	var flap := sin(u * 30.0) * 18.0 * air
	_arms(20.0 + 60.0 * air - 30.0 * squat, 40.0 + 30.0 * air + flap, 20.0 + 60.0 * air - 30.0 * squat, 40.0 + 30.0 * air - flap, 20.0, 20.0)
	_r("spine", -8.0 * squat + 6.0 * air, 0.0)
	_r("head", 10.0 * air - 6.0 * squat, 0.0, 6.0 * sin(u * 9.0) * air)
	_eye_open = lerpf(1.0, 0.35, air)        # happy squint at the top
	_ear_target = Vector2(-0.5 * air + 0.4 * land, 0.4 * air)
	_tail_wag_speed = 16.0
	_tail_wag_amp = 26.0
	_k = 18.0


## Hero v2 idle beat: the gentleman's hat tip. The right hoof rises (stretched, the short arm cannot reach the crown
## otherwise), the top hat lifts off the head and tips forward while Mak bows with his eyes closed, then it settles
## back with a little wobble. With the beanie the beanie tug plays instead.
func _idle_hat_tip(u: float) -> void:
	var reach := _ease_io(_seg(u, 0.0, 0.22)) * (1.0 - _ease_io(_seg(u, 0.74, 0.95)))
	var tip := _ease_io(_seg(u, 0.22, 0.4)) * (1.0 - _ease_io(_seg(u, 0.62, 0.8)))
	var bow := _bell(u, 0.25, 0.78)
	# The hoof rises up and out to the side so it shows beside the head at the brim (it hid behind the face when raised
	# straight forward).
	_arms(-24.0 * bow, 18.0, lerpf(6.0, 125.0, reach), lerpf(14.0, 72.0, reach), 30.0, lerpf(15.0, 70.0, reach))
	_arm_stretch_r = 0.45 * reach
	_hat_lift = 0.075 * tip
	_hat_tip = 0.5 * tip
	_r("head", 3.0 - 16.0 * bow, 0.0, -6.0 * bow)
	_r("spine", -2.0 - 12.0 * bow, 0.0, 0.0)
	_troot_pos.y -= 0.012 * ls * bow
	_stand_legs(_troot_pos.y, 0.03 * bow, -0.05 * bow, 3.0)
	_eye_open = 1.0 - 0.75 * _bell(u, 0.3, 0.72)
	_ear_target = Vector2(0.35 * bow, -0.15 * bow)
	if u > 0.78 and u < 0.8:
		_hat_sq_v -= 3.0
	_k = 11.0


## Hero v2 idle beat: a curious head tilt, one ear perks, a double blink.
func _idle_tilt(u: float) -> void:
	var a := _ease_io(_seg(u, 0.0, 0.2)) * (1.0 - _ease_io(_seg(u, 0.75, 1.0)))
	var side := 1.0 if fmod(floorf(t / 7.0), 2.0) < 1.0 else -1.0
	_r("head", 6.0 * a, 10.0 * side * a, 20.0 * side * a)
	_r("spine", -2.0, 0.0, 4.0 * side * a)
	_ear_target = Vector2(0.2 * a, 0.3 * a)
	var ei := 0 if side > 0.0 else 1
	if u > 0.25 and u < 0.27:
		var ev: Vector2 = _ear_v[ei]
		_ear_v[ei] = ev + Vector2(-6.0, 8.0)
	if (u > 0.4 and u < 0.44) or (u > 0.52 and u < 0.56):
		_eye_open = 0.0
	_k = 10.0


func _pose_walk(dt: float, hs: float, sniff: bool) -> void:
	if not sniff and _brake_t >= 0.0:
		_pose_brake(dt, hs)
		return
	if not sniff and player.pushing_wall:
		_pose_push()
		return
	var run := clampf((hs - 1.5) / 6.0, 0.0, 1.0)
	## Hero v2 fix r1: weight of the rebuilt run keys (contact, push, flight) against the walk.
	var wr := smoothstep(0.3, 0.75, run) if hero_v2 else 0.0
	# Owner fix 2026-10-19 (run amplitude): "when he runs fast the legs should swing wider, the body should lean forward a
	# little, and the arms should swing too". `boost` grows from a jog (3.3 m/s, 0) to the top run speed (7.5 m/s, 1) and
	# widens the stride, lifts the swing knee higher, kicks the heel further back, leans the whole body forward about the
	# feet and pumps the arms harder. The walk (below 3.3 m/s), the idle and the sniff walk are unchanged.
	var boost := smoothstep(0.3, 1.0, run) if hero_v2 and not sniff and _run_boost_on else 0.0
	var legl := l1 + l2 - 0.004
	# Lower the hips with speed: it lengthens the reach and gives a grounded, scurrying run.
	# Hero v2 fix r1: the walk also sits 2.5 cm lower so its 3 cm bob can peak on the passing pose without the stance leg
	# running out of length.
	var drop := legl * lerpf(0.11, 0.24, run) + (0.02 * ls if sniff else 0.0) + (0.025 * (1.0 - wr) if hero_v2 and not sniff else 0.0)
	# Owner fix: the run sits up to 5 % of the leg lower so the hoof can plant further forward (longer reach, still on the
	# IK's reachable circle so contacts stay on the ground; 9 % was tried and cut the planted frames by two thirds).
	drop += legl * 0.05 * boost
	var d_mean := hip_h - drop
	var reach := lerpf(0.9, 0.96, boost) * sqrt(maxf(legl * legl - d_mean * d_mean, 0.0))
	# Fix r1 (animation blocker): the cadence is capped so every step spans at least about 7 frames at 60 fps (walk
	# 2.6 Hz, run 4.4 Hz) and the stride comes from the speed. Above the cap the stance is shortened and the rest of the
	# cycle is a flight phase (a bouncy cartoon trot instead of a buzz).
	# Fix r2: the minimum duty is 0.2 (contacts of 3 frames at a full run, were 2), and from 2.5 m/s up each planted hoof
	# is world-locked: its touchdown point is stored and the IK is solved back onto it every frame from the measured
	# ankle (closed loop), released at toe-off. The sweep allowed behind the hip is longer (heel push-off).
	var sweep_eff := lerpf(0.8, 0.66, run) if _gait_lock_on else 1.0
	var sweep := 2.0 * reach * sweep_eff
	var walk_duty := 0.58
	var natural := hs * walk_duty / maxf(sweep, 0.01)       # cycles/s of a walk with no flight phase
	# Hero v2: the stubby legs scurry a little faster (5 Hz cap at a full run, 6 frames per step) so the run reads
	# as a bouncy chibi dash instead of long floaty hops.
	# Fix r1: 4.5 Hz at a full run (was 5) and a 0.2 minimum duty, so each step has a readable contact and a longer flight.
	var cap := lerpf(2.8, 4.5, run) if hero_v2 else lerpf(2.6, 4.4, run)
	var cadence := minf(natural, cap)
	var duty := walk_duty
	if natural > cap:
		duty = clampf(sweep * 1.35 * cap / maxf(hs, 0.01), 0.2, walk_duty)
	if hs > 0.05:
		gait = fmod(gait + cadence * dt, 1.0)
	# Bob: lowest just after contact (weight on the leg), highest mid-flight. Two contacts per cycle.
	var hp := fmod(gait * 2.0, 1.0)
	var sd := minf(2.0 * duty, 1.0)
	var flight_amt := clampf((1.0 - sd) * 1.6, 0.0, 1.0)
	var comp := 0.0
	var air := 0.0
	if hp < sd:
		comp = sin(hp / sd * PI)
	else:
		air = sin((hp - sd) / maxf(1.0 - sd, 0.01) * PI)
	# Hero v2: a bouncier gait (walk 2 cm, run 3.5 cm of contact bob plus a higher flight arc).
	var bob_amp := lerpf(0.02, 0.035, run)
	if hero_v2:
		bob_amp = lerpf(0.03, 0.035, run)     # fix r1: a 3 cm walk bob that peaks on the passing pose
	# Fix r2: 6-8 cm of vertical bob at a full run (was 5 cm), lowest at contact.
	var bob := (0.5 - 0.5 * cos(gait * TAU * 2.0)) * bob_amp * (1.0 - flight_amt) \
		+ (air * lerpf(0.095, 0.11, wr) - comp * lerpf(0.035, 0.05, wr)) * ls * flight_amt
	var root_y := bob - drop
	_troot_pos = Vector3(0.0, root_y, 0.0)
	_tspine_scale = 1.0 + (0.04 * air - 0.035 * comp) * flight_amt
	if wr > 0.0:
		# Fix r1 (animation blocker: the run read as gliding): four keys per step. Contact is the lowest point with a
		# 0.92 squash, push stretches to 1.08 with the back leg at full length, flight tucks the knees up with both hooves
		# off the ground, then back to contact.
		var cd := minf(hp, 1.0 - hp)
		var contact_w := exp(-pow(cd / 0.08, 2.0))
		var push_w := exp(-pow((hp - 0.85 * sd) / 0.08, 2.0))
		var keyed := 1.0 - 0.08 * contact_w + 0.08 * push_w
		_tspine_scale = lerpf(_tspine_scale, keyed, wr)
	var lock_w := 0.0
	if _gait_lock_on and _foot_lock_on and skeleton != null and int(_foot_bones[0]) >= 0 and not sniff:
		# Hero v2: the stubby legs cover so little ground per step that the open-loop walk slid (probe: 0.5 m/s at a
		# 1.4 m/s walk), so every planted hoof is world-locked from a slow walk up.
		lock_w = clampf((hs - 0.3) / 0.5, 0.0, 1.0) if hero_v2 else clampf((hs - 2.5) / 1.5, 0.0, 1.0)
	var fwd := MakPlayer.dir_from_yaw(player.facing_yaw)
	var fls := [0.0, 0.0]
	for i in 2:
		var side := "l" if i == 0 else "r"
		var ph := fmod(gait + 0.5 * i, 1.0)
		var f := 0.0
		var lift := 0.0
		if ph < duty:
			var u0 := ph / duty
			f = lerpf(reach, -reach * 1.25, u0)
			if lock_w > 0.0:
				var foot := _foot_world(i)
				if not bool(_lock_on[i]):
					_lock_on[i] = true
					_lock_pt[i] = foot
					_lock_f[i] = f
				else:
					var err := ((_lock_pt[i] as Vector3) - foot).dot(fwd)
					_lock_f[i] = clampf(float(_lock_f[i]) + err / _lock_gain, -reach * 1.45, reach * 1.1)
				f = lerpf(f, float(_lock_f[i]), lock_w)
		else:
			_lock_on[i] = false
			var u := (ph - duty) / (1.0 - duty)
			# Swing: heel kick back and up after toe-off, then the knee drives forward and up to reach.
			var heel := sin(clampf(u / 0.45, 0.0, 1.0) * PI)
			f = lerpf(-reach * 1.25, reach, 0.5 - 0.5 * cos(u * PI)) - (0.6 + 0.35 * boost) * reach * flight_amt * heel
			# Owner fix: at speed the knee drives forward past the plant point mid-swing, then the hoof reaches back down to it.
			f += 0.3 * reach * boost * sin(clampf((u - 0.3) / 0.7, 0.0, 1.0) * PI)
			# Hero v2 fix r1: the walk hoof lifts about 5 cm with the knee raised (it shuffled), the run tucks higher.
			var lift_amp := lerpf(0.075, 0.2, run) + 0.07 * boost if hero_v2 else lerpf(0.05, 0.155, run)
			lift = sin(u * PI) * lift_amp * ls + air * 0.035 * ls * flight_amt + heel * (0.05 * run + 0.03 * boost) * ls
		if ph < float(_prev_ph[i]) and hs > 0.4 and player.grounded:
			player.on_footstep(i)
			# Contact accents: the ears, pack and hat take a small hit on each footfall.
			var ev: Vector2 = _ear_v[i]
			_ear_v[i] = ev + Vector2(-2.5 * run, 2.0 * run)
			_pack_v.x += 2.2 * run
			_hat_v.x += (0.35 if hero_v2 else 1.6) * run   # hat fit pass: a small bob, not a tip, on hero v2
			_hb_v -= 0.8 + 1.8 * run       # the big head nods on every footfall
		_prev_ph[i] = ph
		fls[i] = f
		_leg_ik(side, f, hip_h + root_y - lift, 3.0)
	# Hero v2: the stubby arms pump hard at a run (elbows bent about 100 degrees) and swing loosely at a walk.
	var amp := lerpf(30.0, 82.0, run)
	var fl: float = fls[0]
	var fr: float = fls[1]
	var swing_l := clampf(fr / maxf(reach, 0.01), -1.3, 1.3)
	var swing_r := clampf(fl / maxf(reach, 0.01), -1.3, 1.3)
	if hero_v2:
		# Fix r1 (walk blocker, arms in profile): the arms swing from the gait phase with a 2-frame lag behind the legs,
		# 40 degrees each way at a walk; at a run the pumps are big (70 degrees), the elbows only half bent and the arm
		# stretched so the hooves leave the torso silhouette in front and behind.
		var lag := cadence * 2.0 / 60.0
		var sw_l := cos(TAU * (gait + 0.5 - lag))
		var sw_r := cos(TAU * (gait - lag))
		# Owner fix: the pumps grow with speed (up to 94 degrees each way at the top speed) and open a little wider so the
		# far hoof shows behind the body.
		var a_amp := lerpf(40.0, 72.0, wr) + 22.0 * boost
		var a_base := lerpf(6.0, 22.0, wr)
		var fore := lerpf(22.0, 58.0, wr)
		var a_abd := lerpf(16.0, 30.0, wr) + 6.0 * boost
		_arms(a_base + sw_l * a_amp, a_abd, a_base + sw_r * a_amp, a_abd,
			fore + 12.0 * maxf(sw_l, 0.0) * wr, fore + 12.0 * maxf(sw_r, 0.0) * wr)
		_arm_stretch_l = 0.22 * wr + 0.1 * boost
		_arm_stretch_r = 0.22 * wr + 0.1 * boost
	else:
		_arms(10.0 + swing_l * amp, lerpf(18.0, 30.0, run), 10.0 + swing_r * amp, lerpf(18.0, 30.0, run),
			lerpf(24.0, 100.0, run), lerpf(24.0, 100.0, run))
	# Lean into the run from the hips (fix r2: 22-28 degrees at a full run, was 14.5 measured), twist the shoulders
	# against the hips, and counter-tilt the head so the eyes stay level.
	var fwd_acc := _accel.dot(fwd)
	# Hero v2: a chibi runs head-first but fairly upright (a deep lean buried the big face); the head bob carries it.
	# Fix r1: the run leans 12-15 degrees forward at the head (the torso was upright) and the head bob leads the body.
	var lean := -lerpf(3.0, 14.0 + 4.0 * wr, run) - clampf(fwd_acc * 0.9, -8.0, 10.0)
	var root_lean := -6.0 * run - 4.0 * wr
	# Owner fix: the whole body tips forward about the feet with speed (up to 7 more degrees at the top speed); the head
	# only takes back a quarter of it, so the run reads head-first.
	var speed_lean := -7.0 * boost
	var twist := sin(gait * TAU) * lerpf(5.0, 13.0, run)
	# Finish pass (turn responsiveness): the head leads into a turn (up to 24 degrees) and the chest follows at a third,
	# so a curve or a sharp stick change reads a few frames before the body has come round.
	var turn_lead := clampf(_yaw_rate * 6.0, -24.0, 24.0) if hero_v2 else 0.0
	_r("spine", lean, twist + turn_lead * 0.35, 0.0)
	_r("head", -(lean + root_lean) * lerpf(0.8, 0.5, wr) - speed_lean * 0.25 + lerpf(3.0, 7.0, run) * sin(gait * TAU * 2.0 - 0.9 - 0.6 * wr), -twist * 0.7 + turn_lead,
		lerpf(4.0, 2.0, run) * sin(gait * TAU) + turn_lead * 0.25)
	var hip_yaw := -twist * 0.6
	# Slow walks get a side-to-side hip roll and a head nod at each contact (fix r2: the 0.7 m/s walk read stiff).
	# Hero v2 waddle: a wider side-to-side hip roll at a walk, the head tilting with it (above).
	var hip_roll := sin(gait * TAU) * lerpf(8.0, 6.0, run)
	_r("hips", 0.0, hip_yaw, hip_roll)
	if _gait_lock_on:
		# The hips' sway and twist must not drag the planted foot sideways: the thighs counter-rotate it.
		for side in ["l", "r"]:
			_trot["thigh_" + side] += Vector3(0.0, -hip_yaw, -hip_roll) * DEG
	_trot["root"] = Vector3((root_lean + speed_lean) * DEG, 0.0, clampf(_yaw_rate * hs * 0.045, -0.42, 0.42))
	if run < 0.3:
		var walk_w := 1.0 - run / 0.3
		var hd: Vector3 = _trot["head"]
		hd.x += (-5.0 if hero_v2 else -3.0) * DEG * walk_w * maxf(0.0, cos(gait * TAU * 2.0))
		_trot["head"] = hd
		var spn: Vector3 = _trot["spine"]
		spn.z += 4.0 * DEG * walk_w * sin(gait * TAU)
		_trot["spine"] = spn
		_ear_target = Vector2(0.15 * walk_w * sin(gait * TAU * 2.0), 0.1 * walk_w)
	else:
		_ear_target = Vector2(run * 0.7 + 0.15 * air * flight_amt, 0.0)
	_tail_wag_speed = lerpf(4.0, 14.0, run)
	_tail_wag_amp = lerpf(10.0, 26.0, run)
	_k = 22.0
	_gait_lock_target = 1.0 if hs > 0.05 and _gait_lock_on else 0.0
	if run > 0.6:
		_lid_tilt = 0.2
		_eye_open = 0.85
	if sniff:
		_r("spine", -22.0, twist * 0.5)
		_r("head", -24.0 + 7.0 * maxf(0.0, sin(t * 19.0)), 14.0 * sin(t * 1.7))
		_ear_target = Vector2(0.4, -0.15)
		_tail_wag_speed = 17.0
		_tail_wag_amp = 24.0
		_eye_open = 0.5
		_arms(22.0 + swing_l * 10.0, 14.0, 22.0 + swing_r * 10.0, 14.0, 45.0, 45.0)
		if hs < 0.1:
			_stand_legs(root_y, 0.02, -0.02)


## Metres from the feet down to the world (layer 1), 99 when nothing is under Mak within 6 m.
func _ground_distance() -> float:
	if player == null or not player.is_inside_tree():
		return 99.0
	var o := player.global_position
	var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.05, o + Vector3.DOWN * 6.0, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 99.0
	return maxf(o.y - (hit["position"] as Vector3).y, 0.0)


func _foot_world(i: int) -> Vector3:
	var bi := int(_foot_bones[i])
	if skeleton == null or bi < 0:
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(bi).origin


## Fix r2 (feel minor M4): pushing against a wall. Lean in from the feet, hooves flat on the wall and scrabbling at
## 3 Hz, the legs treading in place, a strained squint.
func _pose_push() -> void:
	var ph := t * 3.0 * TAU
	_troot_pos = Vector3(0.0, -0.02 * ls, -0.03)
	_trot["root"] = Vector3(-16.0 * DEG, 0.0, 0.0)
	_r("spine", -8.0, 4.0 * sin(ph * 0.5))
	_r("head", 14.0, 0.0, 3.0 * sin(ph))
	_arms(96.0 + 8.0 * sin(ph), 22.0, 96.0 - 8.0 * sin(ph), 22.0, 30.0 + 10.0 * sin(ph), 30.0 - 10.0 * sin(ph))
	var dd := hip_h - 0.02 * ls
	_leg_ik("l", -0.05 * ls, dd - 0.02 * ls * maxf(0.0, sin(ph)), 4.0)
	_leg_ik("r", -0.03 * ls, dd - 0.02 * ls * maxf(0.0, -sin(ph)), 4.0)
	_brow_raise = -0.6
	_lid_tilt = 0.45
	_eye_open = 0.7
	_ear_target = Vector2(-0.3, 0.2)
	_tail_wag_speed = 9.0
	_k = 20.0
	_gait_lock_target = 0.0


## Fix r2 (animation major): the hard brake from a run. The leading hoof plants ahead, the body leans back 15-20 degrees
## with the arms thrown forward for balance, and the ears, pack and hat whip forward (impulses in _process); the other
## hoof skids under the hips. The settle after the stop is an overlay (_overlays).
func _pose_brake(_dt: float, hs: float) -> void:
	var e := _ease_out(clampf(_brake_t / 0.07, 0.0, 1.0))
	var lead := "l" if _brake_lead == 0 else "r"
	var back := "r" if _brake_lead == 0 else "l"
	var ry := -0.05 * ls * e
	# Fix r1 (animation blocker): the brake read as falling backwards (head to the sky, a stiff held pose). The body leans
	# back at most 13 degrees, the head stays level and looks ahead with a surprised face, both hooves brace forward and
	# the body shudders at 7 Hz while it skids; the whip forward at the stop is the settle overlay.
	var shud := sin(_brake_t * TAU * 7.0) * e
	_troot_pos = Vector3(0.0, ry + 0.006 * ls * shud, 0.0)
	var lean := lerpf(3.0, 13.0, e) * clampf(hs / 3.0, 0.4, 1.0)
	_trot["root"] = Vector3((lean + 1.5 * shud) * DEG, 0.0, 1.5 * DEG * sin(_brake_t * TAU * 5.0) * e)
	_r("spine", 2.0 * e, 0.0, 0.0)
	_r("head", -(lean + 2.0 * e) + 2.0 * shud, 0.0, 3.0 * sin(t * 20.0) * e)
	var legl := l1 + l2 - 0.004
	var dd := hip_h + ry
	var reach := 0.9 * sqrt(maxf(legl * legl - dd * dd, 0.0))
	_leg_ik(lead, reach * 1.05, dd, 5.0)
	_leg_ik(back, reach * 0.55, dd + 0.004 * ls, 5.0)
	var w := sin(t * 18.0) * 6.0
	_arms(lerpf(10.0, 62.0, e) + w, 40.0, lerpf(10.0, 56.0, e) - w, 40.0, 20.0, 20.0)
	_arm_stretch_l = 0.15 * e
	_arm_stretch_r = 0.15 * e
	_ear_target = Vector2(1.0 * e, 0.0)
	_brow_raise = 0.8
	_eye_open = 1.1
	_tail_wag_speed = 18.0
	_k = 30.0
	_gait_lock_target = 0.0
	if _brake_t < 0.02:
		_sq = minf(_sq, -0.06)


func _pose_skid() -> void:
	# Heels dug in, body thrown back against the momentum, arms windmilling.
	# Fix r1 (animation blocker): the skid stared at the sky in one held pose for 72 frames. Now: lean back 12 degrees, the
	# head level and looking ahead with wide eyes, both hooves braced forward, a 7 Hz shudder through the body and the head,
	# and the arms thrown forward and out for balance (outside the silhouette).
	var e := _ease_out(clampf(_st / 0.08, 0.0, 1.0))
	var shud := sin(_st * TAU * 7.0) * e
	_troot_pos = Vector3(0.0, -0.05 * ls + 0.006 * ls * shud, 0.0)
	var lean := 12.0 * e if hero_v2 else 18.0
	_trot["root"] = Vector3((lean + 1.5 * shud) * DEG, 0.0, 2.0 * DEG * sin(_st * TAU * 4.5) * e)
	_leg_ik("l", 0.12 * ls, hip_h - 0.06 * ls, 6.0)
	_leg_ik("r", (0.08 if hero_v2 else 0.04) * ls, hip_h - 0.07 * ls, 6.0)
	if hero_v2:
		_r("spine", 2.0)
		_r("head", -(lean + 2.0) + 2.5 * shud, 0.0, 5.0 * sin(t * 18.0))
		var w2 := sin(t * 22.0)
		_arms(55.0 + 25.0 * w2, 48.0, 55.0 - 25.0 * w2, 48.0, 20.0, 20.0)
		_arm_stretch_l = 0.15
		_arm_stretch_r = 0.15
		_ear_target = Vector2(0.9, 0.15 * shud)
		_brow_raise = 1.0
		_eye_open = 1.15
		_k = 22.0
		return
	_r("spine", 12.0, 0.0)
	_r("head", 2.0, 0.0, 6.0 * sin(t * 18.0))
	var w := sin(t * 24.0)
	_arms(-30.0 + 40.0 * w, 65.0, -30.0 - 40.0 * w, 65.0, 30.0, 30.0)
	_ear_target = Vector2(0.9, 0.0)
	_brow_raise = 0.9
	_eye_open = 1.15
	_k = 22.0


func _pose_crouch(dt: float, hs: float) -> void:
	# Squash down through the hips and chest rather than folding the very short thighs.
	# Crouch reads from the gameplay camera: a deeper hip drop and a squashed torso (was 7 cm / 0.9).
	var ry := -0.1 * ls
	if hero_v2:
		# Fix r1 (animation major): crouch and crawl were too close to standing. The hips drop to the knees' limit, the
		# whole body holds a 0.85 squash (a sustained squash, not the spring) and the ears lie flat: the head drops about
		# 30 % of his height.
		ry = -0.16 * ls
		_tsq_hold = -0.15
	_troot_pos = Vector3(0.0, ry, 0.0)
	_tspine_scale = 0.84
	if hs > 0.1:
		# Crawl: nose down, arms paddling, quick little steps. The stride matches the ground speed (clean
		# contacts, same sweep factor as the walk), with the cadence capped at 7.5 Hz so it never buzzes.
		var amp := 0.085
		var duty := 0.55
		var stride := maxf(2.0 * amp * ls * 0.8 / duty, hs / 7.5) if _gait_lock_on else 0.3
		gait = fmod(gait + hs * dt / stride, 1.0)
		_gait_lock_target = 1.0 if _gait_lock_on else 0.0
		for i in 2:
			var side := "l" if i == 0 else "r"
			var ph := fmod(gait + 0.5 * i, 1.0)
			var f := 0.0
			var lift := 0.0
			if ph < duty:
				f = lerpf(amp, -amp, ph / duty) * ls
			else:
				var u := (ph - duty) / (1.0 - duty)
				f = lerpf(-amp, amp, 0.5 - 0.5 * cos(u * PI)) * ls
				lift = sin(u * PI) * 0.035 * ls
			_leg_ik(side, f, hip_h + ry - lift, 8.0)
			if ph < float(_prev_ph[i]) and player.grounded:
				player.on_footstep(i)
			_prev_ph[i] = ph
		var pad := sin(gait * TAU)
		_tbody_pitch = (-40.0 if hero_v2 else -26.0) * DEG
		_arms(75.0 + 35.0 * pad, 16.0, 75.0 - 35.0 * pad, 16.0, 30.0, 30.0)
		_r("head", 34.0 if hero_v2 else 26.0, 6.0 * pad)
		_r("spine", -6.0, 5.0 * pad)
		if hero_v2:
			# A slow belly-down wiggle: the hips roll and yaw with the paddle.
			_r("hips", 0.0, 7.0 * pad, 9.0 * pad)
			_trot["root"] = Vector3(0.0, 0.0, 4.0 * DEG * pad)
	else:
		_leg_ik("l", 0.03 * ls, hip_h + ry, 12.0)
		_leg_ik("r", -0.02 * ls, hip_h + ry, 12.0)
		# Hunkered: chest over the knees, head tucked but eyes up, a slow nervous breath.
		var br := sin(t * 3.2)
		_tbody_pitch = -9.0 * DEG
		_r("spine", -18.0 + 1.5 * br)
		_r("head", 14.0 - 1.0 * br)
		_arms(36.0, 22.0, 36.0, 22.0, 62.0, 62.0)
	_ear_target = Vector2(-0.95, 0.75) if hero_v2 else Vector2(-0.3, 0.35)
	_brow_raise = 0.2
	_k = 16.0


func _pose_crouch_slide() -> void:
	var ry := -0.08 * ls
	_troot_pos = Vector3(0.0, ry, 0.0)
	_tspine_scale = 0.92
	_leg_ik("l", 0.08 * ls, hip_h + ry, 8.0)
	_leg_ik("r", 0.03 * ls, hip_h + ry, 8.0)
	_r("spine", 10.0)
	_r("head", 2.0)
	_arms(-30.0, 40.0, -30.0, 40.0, 20.0, 20.0)
	_ear_target = Vector2(0.6, 0.0)
	_brow_raise = 0.5
	_k = 18.0


func _pose_punch() -> void:
	## Whole-body strikes: wind back (anticipation), snap through (arc + swoosh), hold, recover.
	var step := player.combo_step
	_lid_tilt = 0.45
	_eye_open = 0.8
	_brow_raise = -0.8
	_k = 34.0
	if step == 3:
		_pose_spin_kick()
		return
	var dur := player.p.punch_time
	var u := clampf(_st / dur, 0.0, 1.0)
	var wind := _ease_io(_seg(u, 0.0, 0.17))
	var snap := _ease_out(_seg(u, 0.17, 0.42))
	var rec := _ease_io(_seg(u, 0.62, 1.0))
	if hero_v2:
		_pose_jab_v2(u, dur)
		return
	var e := (snap - rec) if snap > 0.0 else -0.4 * wind
	var ep := maxf(e, 0.0)
	var dir := 1.0 if step == 1 else -1.0      # 1: right hoof, 2: left hoof
	# Lunge forward and dip, roll the punching shoulder forward (a modest twist keeps the hoof in view).
	_troot_pos = Vector3(-0.03 * dir * ep, -0.035 * ls * ep - 0.02 * ls * wind, -0.26 * ep + 0.05 * wind * (1.0 - snap))
	_trot["root"] = Vector3(-18.0 * DEG * ep + 7.0 * DEG * wind * (1.0 - snap), dir * 8.0 * DEG * ep, dir * 5.0 * DEG * ep)
	_r("spine", -12.0 * ep + 6.0 * wind * (1.0 - snap), dir * (24.0 * ep - 22.0 * wind * (1.0 - snap)), -dir * 6.0 * ep)
	_r("head", -4.0 * ep, -dir * 16.0 * ep, dir * 6.0 * ep)
	_r("hips", 0.0, dir * 8.0 * ep)
	var strike_x := lerpf(-40.0, 92.0, clampf(e + 0.35, 0.0, 1.35) / 1.35)
	var strike_f := lerpf(115.0, 0.0, clampf(e, 0.0, 1.0))
	var strike_z := lerpf(14.0, 30.0, ep)
	if step == 1:
		_arms(lerpf(30.0, -30.0, ep), 26.0, strike_x, strike_z, lerpf(60.0, 105.0, ep), strike_f)
	else:
		_arms(strike_x, strike_z, lerpf(30.0, -30.0, ep), 26.0, strike_f, lerpf(60.0, 105.0, ep))
	# Front foot steps into the punch, back foot pushes.
	var front := "l" if step == 1 else "r"
	var back := "r" if step == 1 else "l"
	_leg_ik(front, (0.03 + 0.06 * ep) * ls, hip_h + _troot_pos.y, 6.0)
	_leg_ik(back, (-0.02 - 0.06 * ep) * ls, hip_h + _troot_pos.y, 6.0)
	_ear_target = Vector2(-0.5 * ep, 0.0)
	if snap > 0.0 and snap < 0.4:
		_sq = minf(_sq, -0.05)


## Hero v2 fix r1 (animation major: the jab arm barely left the body silhouette). Timing on the 0.24 s jab (14 frames):
## frames 0-4 anticipation (shoulder pulls back, head ducks, weight drops), frames 4-6 snap to full extension (the arm
## smears to about 1.9x so the hoof lands well in front of the snout), frames 6-9 hold with a 0.95 body squash, frames 9-14
## recover. The torso twists the punching shoulder forward and the head turns away from the arm so it reads from the side.
func _pose_jab_v2(u: float, _dur: float) -> void:
	var step := player.combo_step
	var dir := 1.0 if step == 1 else -1.0      # 1: right hoof, 2: left hoof
	var wind := _ease_io(_seg(u, 0.0, 0.28))
	var snap := _ease_out(_seg(u, 0.28, 0.4))
	var rec := _ease_io(_seg(u, 0.62, 1.0))
	var ext := snap * (1.0 - rec)
	var ant := wind * (1.0 - snap)
	var hold := _bell(u, 0.36, 0.66)
	_troot_pos = Vector3(-0.02 * dir * ext, -0.02 * ls * ant - 0.03 * ls * ext, 0.05 * ant - 0.2 * ext)
	_trot["root"] = Vector3(-14.0 * DEG * ext + 6.0 * DEG * ant, dir * (10.0 * ext - 8.0 * ant) * DEG, dir * 4.0 * DEG * ext)
	_r("spine", -10.0 * ext + 5.0 * ant, dir * (30.0 * ext - 26.0 * ant), -dir * 5.0 * ext)
	_r("head", -9.0 * ant + 6.0 * ext, -dir * 22.0 * ext + dir * 8.0 * ant, dir * 5.0 * ext)
	_r("hips", 0.0, dir * 9.0 * ext)
	var strike_x := lerpf(-45.0 * wind, 96.0, ext)
	var strike_f := lerpf(lerpf(20.0, 120.0, wind), 0.0, ext)
	var guard_x := lerpf(30.0, -35.0, ext)
	if step == 1:
		_arms(guard_x, 34.0, strike_x, lerpf(18.0, 8.0, ext), lerpf(60.0, 100.0, ext), strike_f)
		_arm_stretch_r = 1.0 * snap * (1.0 - _seg(u, 0.45, 0.62) * 0.25) * (1.0 - rec)
	else:
		_arms(strike_x, lerpf(18.0, 8.0, ext), guard_x, 34.0, strike_f, lerpf(60.0, 100.0, ext))
		_arm_stretch_l = 1.0 * snap * (1.0 - _seg(u, 0.45, 0.62) * 0.25) * (1.0 - rec)
	_tsq_hold = -0.05 * hold
	var front := "l" if step == 1 else "r"
	var back := "r" if step == 1 else "l"
	_leg_ik(front, (0.03 + 0.08 * ext) * ls, hip_h + _troot_pos.y, 6.0)
	_leg_ik(back, (-0.02 - 0.08 * ext) * ls, hip_h + _troot_pos.y, 6.0)
	_ear_target = Vector2(-0.6 * ext + 0.3 * ant, 0.0)
	_eye_open = 0.75 if ext > 0.2 else 0.9
	if snap > 0.0 and snap < 0.5:
		_sq = minf(_sq, -0.04)


func _pose_spin_kick() -> void:
	var dur := player.p.kick_time
	var u := clampf(_st / dur, 0.0, 1.0)
	var wind := _ease_io(_seg(u, 0.0, 0.14))
	var spin := _ease_io(_seg(u, 0.12, 0.72))
	var ext := _bell(u, 0.12, 0.8)
	# Coil the other way first, then one full turn with a hop and the leg flung out.
	_spin = Vector3(0.0, 0.45 * wind * (1.0 - spin) - TAU * spin, 0.0)
	_troot_pos = Vector3(0.0, 0.09 * ls * _bell(u, 0.12, 0.75) - 0.03 * ls * wind * (1.0 - spin), 0.0)
	_r("thigh_r", 30.0 * ext, 0.0, 85.0 * ext)
	_r("shin_r", -10.0 * (1.0 - ext))
	_leg_ik("l", 0.0, hip_h + _troot_pos.y * 0.3 - 0.02 * ls, 5.0)
	_arms(30.0, 80.0 * ext + 20.0, 30.0, 80.0 * ext + 20.0, 25.0, 25.0)
	_r("spine", 8.0 * ext, 0.0, -14.0 * ext)
	_r("head", 6.0, 0.0, 8.0 * ext)
	_ear_target = Vector2(-0.2, 0.9 * ext)
	_tail_wag_amp = 30.0
	if hero_v2:
		# Fix r1 (animation major: the spin kick read as a turn with no visible leg): the kicking leg flies out straight and
		# level, smeared to about 1.7x so it clears the round body, the torso leans away to counter it and the arms fling wide.
		var kx := _ease_out(_seg(u, 0.1, 0.3)) * (1.0 - _ease_io(_seg(u, 0.72, 0.95)))
		_r("thigh_r", 20.0 * kx, 0.0, 88.0 * kx)
		_r("shin_r", -6.0 * (1.0 - kx))
		_thigh_stretch_r = 0.7 * kx
		_r("spine", 6.0 * kx, 0.0, -24.0 * kx)
		_r("head", 4.0, 0.0, 14.0 * kx)
		_arms(40.0, 95.0 * kx + 20.0, 40.0, 95.0 * kx + 20.0, 15.0, 15.0)
		_arm_stretch_l = 0.15 * kx
		_arm_stretch_r = 0.15 * kx
		_tsq_hold = -0.04 * kx


func _pose_slam_land() -> void:
	# Impact squash (driven by the spring on ground_pounded), held for three frames so it reads through the dust,
	# splayed legs, then a little rebound hop.
	var u := clampf(_st / 0.32, 0.0, 1.0)
	if _st < 0.085:
		# Fix r2: hold a 0.75x squash for 3 frames (the spring alone recovered within 2 frames, under the dust).
		# Hero v2: a bigger pancake held 5 frames, then the rubbery rebound.
		_sq = minf(_sq, -0.32)
		_sq_v = minf(_sq_v, 0.0)
	var hop := 0.08 * _bell(u, 0.25, 0.75) * ls
	# Fix r1: the squash alone (capped at 0.70) carries the impact; the extra hip dip and forward fold are halved so the
	# head stays above the shoulders (it dropped to about half its height).
	var ry := -(0.04 if hero_v2 else 0.08) * ls * (1.0 - _ease_io(_seg(u, 0.3, 0.9))) + hop
	_troot_pos = Vector3(0.0, ry, 0.0)
	_leg_ik("l", 0.03 * ls, hip_h + ry, 16.0)
	_leg_ik("r", -0.01 * ls, hip_h + ry, 16.0)
	_arms(30.0, lerpf(85.0, 30.0, u), 30.0, lerpf(85.0, 30.0, u), 20.0, 20.0)
	_r("spine", (-6.0 if hero_v2 else -12.0) * (1.0 - u))
	_r("head", (-2.0 if hero_v2 else -8.0) + 14.0 * _bell(u, 0.3, 0.9))
	_ear_target = Vector2(-0.6, 0.8)
	_brow_raise = -1.0
	_lid_tilt = 0.5
	_eye_open = 0.6
	_k = 26.0


func _pose_belly_slide(hs: float) -> void:
	# Fix r2: flat on the belly (was nose-up by about 9 degrees), chin up, a 2-frame squash on the first contact.
	_tbody_pitch = -95.0 * DEG
	_troot_pos = Vector3(0.0, -0.28, 0.0)
	if _st < 0.035:
		_sq = minf(_sq, -0.14)
	var sp := clampf(hs / 6.0, 0.0, 1.0)
	var wob := sin(t * 9.0) * sp
	_arms(150.0 + 6.0 * wob, 30.0, 150.0 - 6.0 * wob, 30.0, 10.0, 10.0)
	var kicks := 1.0 - sp
	_leg_raw("l", -14.0, -12.0 - 35.0 * maxf(0.0, sin(t * 13.0)) * kicks, 8.0)
	_leg_raw("r", -14.0, -12.0 - 35.0 * maxf(0.0, -sin(t * 13.0)) * kicks, 8.0)
	_r("spine", -6.0, 4.0 * wob)
	_r("head", 80.0, 6.0 * wob)
	_ear_target = Vector2(1.1, 0.0)
	_tail_wag_speed = 12.0
	_eye_open = 0.9
	_brow_raise = 0.4
	_k = 30.0 if _st < 0.25 else 14.0


func _pose_getup() -> void:
	var u := clampf(_st / maxf(player.p.slide_getup_time, 0.05), 0.0, 1.0)
	var up := _ease_io(u)
	_tbody_pitch = lerpf(-60.0, 0.0, up) * DEG
	_troot_pos = Vector3(0.0, lerpf(-0.2, 0.0, up), 0.0)
	_arms(lerpf(80.0, 10.0, up), 30.0, lerpf(80.0, 10.0, up), 30.0, 30.0, 30.0)
	_stand_legs(_troot_pos.y * 0.3, 0.02, -0.02, 6.0)
	_r("head", lerpf(40.0, 0.0, up), 0.0, 10.0 * sin(u * 12.0) * (1.0 - u))
	_k = 14.0


func _pose_butt_slide() -> void:
	_troot_pos = Vector3(0.0, -0.13, 0.0)
	_tbody_pitch = 14.0 * DEG
	_leg_raw("l", 88.0, -12.0, 8.0)
	_leg_raw("r", 84.0, -16.0, 8.0)
	var w := sin(t * 11.0)
	_arms(-35.0 + 20.0 * w, 55.0, -35.0 - 20.0 * w, 55.0, 25.0, 25.0)
	_r("spine", 14.0)
	_r("head", -4.0, 10.0 * sin(t * 3.0))
	if hero_v2:
		# Fix r1 (animation major: the slide stared at the sky): the spine sits up and the head tips forward so the face
		# looks down the slope, with squeezed eyes and a wobble.
		_r("spine", 4.0)
		_r("head", -24.0, 10.0 * sin(t * 3.0), 7.0 * sin(t * 8.5))
		_eye_open = 0.45
		_lid_tilt = 0.3
	_ear_target = Vector2(0.8, 0.0)
	_brow_raise = 1.0
	if not hero_v2:
		_eye_open = 1.15
	_k = 14.0


func _pose_celebrate() -> void:
	# Hop with a full twirl, then a fist pump with a happy squint; works while the tree is paused.
	var spin := _ease_io(_seg(_st, 0.05, 0.55))
	var hop1 := _bell(_st, 0.0, 0.6)
	var later := maxf(_st - 0.6, 0.0)
	var hop2 := 0.45 * absf(sin(later * 7.0)) if _st > 0.6 else 0.0
	var hop := 0.12 * ls * hop1 + 0.06 * ls * hop2
	_spin = Vector3(0.0, TAU * spin, 0.0)
	if hero_v2:
		# Fix r1: turn to the camera within 6 frames (with a small overshoot), then a quick happy twirl in place that is
		# over in 0.2 s, so the face is on screen for nearly the whole celebration.
		var turn := _ease_out(clampf(_st / 0.1, 0.0, 1.0)) + 0.08 * sin(clampf((_st - 0.1) / 0.15, 0.0, 1.0) * PI)
		var twirl := _ease_io(_seg(_st, 0.3, 0.5))
		_spin = Vector3(0.0, _cel_yaw * turn + TAU * twirl, 0.0)
	_troot_pos = Vector3(0.0, hop, 0.0)
	_stand_legs(0.0, 0.02, -0.02, 4.0)
	if hop > 0.02 * ls:
		_leg_raw("l", 35.0, -60.0, 6.0)
		_leg_raw("r", 12.0, -35.0, 6.0)
	# Fix r2 (arm range): the arms read only when they leave the belly silhouette, so the victory beats are big and the
	# raised arms stretch (bone scale in _overlays). During the spin the hooves fly out wide; on the up-beat of the second
	# hop both hooves punch overhead in a V and hold 6 frames, then single right-hoof pumps on the beat with the left hoof
	# on the hip, and a drop with a little bounce at the end.
	if _st < 0.6:
		_arms(lerpf(60.0, 120.0, spin), lerpf(70.0, 95.0, hop1), lerpf(60.0, 120.0, spin), lerpf(70.0, 95.0, hop1), 20.0, 20.0)
	elif later < 0.42:
		var up := _ease_out(clampf(later / 0.1, 0.0, 1.0))
		_arms(lerpf(60.0, 150.0, up), lerpf(60.0, 40.0, up), lerpf(60.0, 150.0, up), lerpf(60.0, 40.0, up), 8.0, 8.0)
		_r("hips", 0.0, 0.0, 0.0)
	else:
		var l2t := later - 0.42
		var beat := fmod(l2t, 0.5) / 0.5
		var pump := _ease_out(_seg(beat, 0.0, 0.22)) * (1.0 - _ease_io(_seg(beat, 0.55, 1.0)))
		if hero_v2 and _hat_id != "beanie":
			# Hero v2: the left hoof pumps on the beat while the right hoof tips the top hat (it lifts and tips, a wink).
			var tipu := _ease_out(clampf(l2t / 0.18, 0.0, 1.0))
			# Fix r1: the pumping hoof goes up and out (48 degrees) so it never covers the face in 3/4.
			_arms(lerpf(70.0, 145.0, pump), lerpf(40.0, 48.0, pump), 125.0 * tipu, lerpf(30.0, 72.0, tipu), lerpf(80.0, 10.0, pump), 70.0)
			_arm_stretch_r = 0.45 * tipu
			_hat_lift = 0.07 * tipu
			_hat_tip = 0.45 * tipu + 0.08 * sin(l2t * 12.6) * tipu
		else:
			_arms(-14.0, 44.0, lerpf(70.0, 150.0, pump), lerpf(40.0, 22.0, pump), 100.0, lerpf(80.0, 10.0, pump))
		_r("hips", 0.0, 8.0 * sin(l2t * 6.3), 5.0 * sin(l2t * 12.6))
	_r("spine", 8.0, 0.0, 6.0 * sin(later * 5.5))
	_r("head", 18.0, -8.0, 8.0 * sin(later * 5.5))
	_eye_open = 0.35
	_brow_raise = 1.0
	_ear_target = Vector2(0.3, -0.6)
	_tail_wag_speed = 20.0
	_tail_wag_amp = 32.0
	_k = 18.0


func _pose_lying(s: String) -> void:
	var dur := player.hurt_land_duration if s == "hurt_land" else 99.0
	var u := _st / dur
	var up := _ease_io(_seg(u, 0.55, 1.0))
	var bounce := 0.06 * _bell(u, 0.0, 0.35)
	_tbody_pitch = lerpf(78.0, 0.0, up) * DEG
	_troot_pos = Vector3(0.0, lerpf(-0.24, 0.0, up) + bounce, 0.0)
	_arms(lerpf(100.0, 20.0, up), 80.0, lerpf(100.0, 20.0, up), 80.0, 20.0, 20.0)
	_leg_raw("l", lerpf(65.0, 10.0, up), -40.0, 10.0)
	_leg_raw("r", lerpf(50.0, 5.0, up), -30.0, 10.0)
	var dizzy := 18.0 * sin(t * 4.0) if s == "dead" else 10.0 * sin(t * 7.0) * (1.0 - up)
	_r("head", -10.0, dizzy, 0.0)
	if hero_v2:
		# Fix r1 (animation major: head pitch reached -75 degrees in hurt_land, the face vanished): he lands on his rump
		# leaning back 45 degrees, the head tips forward to face out with dizzy, squeezed eyes and a wobble.
		_tbody_pitch = lerpf(45.0, 0.0, up) * DEG
		_troot_pos.y = lerpf(-0.16, 0.0, up) + bounce
		_r("head", lerpf(-38.0, 0.0, up), dizzy, 9.0 * sin(t * 6.0) * (1.0 - up))
		_r("spine", lerpf(-8.0, 0.0, up))
	_eye_open = 0.15 if up < 0.5 else 0.7
	if hero_v2 and up < 0.5:
		_eye_open = 0.3 + 0.15 * sin(t * 9.0)
	_brow_raise = 0.9
	_ear_target = Vector2(-0.4, 0.9)
	_k = 10.0 if up > 0.0 else 16.0


func _pose_ledge_hang() -> void:
	## Fix r1: solved from the hands. The controller holds the feet 1.0 m under the lip; the visual root rises only
	## until the chin is at lip height, the body leans in so the hooves rest on top of the lip with the arms near
	## vertical, and the legs hang straight with a pendulum sway at the hips.
	var swing := sin(_st * 6.5) * exp(-_st * 2.8)
	var breath := sin(t * 2.6)
	var sway := sin(t * 1.7) * 5.0
	_troot_pos = Vector3(0.0, HANG_ROOT_Y + 0.008 * breath, HANG_ROOT_Z)
	_tbody_pitch = (-10.0 + 8.0 * swing) * DEG
	_arms(166.0, 6.0, 166.0, 6.0, 26.0, 26.0)
	_leg_raw("l", -2.0 - 12.0 * swing + sway, -6.0 - 4.0 * sin(t * 2.6 + 0.5), 3.0)
	_leg_raw("r", 2.0 - 10.0 * swing - sway, -4.0 + 4.0 * sin(t * 2.6 + 0.5), 3.0)
	_r("spine", 6.0)
	_r("head", 22.0 + 3.0 * breath)
	if hero_v2:
		# Fix r1 (animation blocker: both arms pointed straight up behind the huge head, nothing seemed to hold him). The
		# arms spread in a wide V (40 degrees out) and stretch so both hooves sit on the lip either side of the head, the
		# chin lifts, and the grab gets a 2-cycle leg kick (the ear flick is an impulse on entry).
		_arms(128.0, 50.0 - ARM_ABD, 128.0, 50.0 - ARM_ABD, 8.0, 8.0)
		_arm_stretch_l = 0.4
		_arm_stretch_r = 0.4
		var kick := sin(_st * TAU * 3.0) * (1.0 - _seg(_st, 0.45, 0.67))
		_leg_raw("l", 10.0 + 28.0 * kick + sway, -30.0 - 25.0 * maxf(kick, 0.0), 4.0)
		_leg_raw("r", 10.0 - 28.0 * kick - sway, -30.0 - 25.0 * maxf(-kick, 0.0), 4.0)
		_r("head", 30.0 + 3.0 * breath, 0.0, 4.0 * sin(t * 1.3))
	_ear_target = Vector2(0.4, 0.0)
	_brow_raise = 0.6
	_k = 18.0


func _pose_ledge_climb() -> void:
	var u := clampf(_st / maxf(player._climb_time, 0.05), 0.0, 1.0)
	var up_part := 1.0 - pow(1.0 - clampf(u / 0.62, 0.0, 1.0), 2.0)
	var knee := _bell(u, 0.15, 0.85)
	# The controller lifts the body 1.0 m; the visual offset fades so the net rise looks like a pull-up.
	_troot_pos = Vector3(0.0, lerpf(HANG_ROOT_Y, 0.0, up_part), lerpf(HANG_ROOT_Z, 0.0, _ease_io(u)))
	_tbody_pitch = -28.0 * knee * DEG
	_arms(lerpf(166.0, 20.0, _ease_io(u / 0.7)), 12.0, lerpf(166.0, 20.0, _ease_io(u / 0.7)), 12.0,
		60.0 * knee, 60.0 * knee)
	_leg_raw("r", 95.0 * knee, -110.0 * knee, 4.0)
	_leg_raw("l", 25.0 * knee, -45.0 * knee, 4.0)
	_r("spine", -12.0 * knee)
	_r("head", 12.0 - 10.0 * knee)
	_brow_raise = -0.4
	_lid_tilt = 0.3
	_k = 28.0


func _pose_pole() -> void:
	## Fix r1: grip the vine. The head turns so the cheek rests on the vine (the snout clears it), the belly sits on
	## the vine, the hooves hug its sides and alternate up and down as he climbs, the legs wrap around it.
	var c := player.pole_climb_travel / 0.5 * TAU
	var s := sin(c)
	var br := sin(t * 2.4)
	# Fix r1 (minor): the body hitches up 3 cm with each hoof grab (twice per climb cycle).
	var hitch := absf(sin(c)) * 0.03 if hero_v2 else 0.0
	_troot_pos = Vector3(0.0, 0.01 * br + hitch, -0.05)
	_arms(132.0 + 16.0 * s, -14.0 - (ARM_ABD if hero_v2 else 0.0), 132.0 - 16.0 * s, -14.0 - (ARM_ABD if hero_v2 else 0.0), 70.0 - 14.0 * s, 70.0 + 14.0 * s)
	_leg_raw("l", 70.0 - 16.0 * s, -96.0 + 10.0 * s, 26.0)
	_leg_raw("r", 70.0 + 16.0 * s, -96.0 - 10.0 * s, 26.0)
	_r("spine", -8.0 + 1.5 * br, 4.0 * s)
	_r("head", 8.0, 38.0, 10.0)
	_ear_target = Vector2(0.2, 0.2)
	_k = 18.0


func _pose_jump(big: bool) -> void:
	var vy := player.vy
	var rise := smoothstep(-2.5, 3.5, vy)
	var fall := 1.0 - rise
	var land_ready := smoothstep(-3.0, -9.0, vy)
	if big:
		# Double jump: a flourish. Hero v2: a full pirouette on the way up (slow in, slow out) with a quick tuck at
		# takeoff, then the star spread.
		var tuck := _bell(_st, 0.0, 0.32)
		_spin = Vector3(0.0, TAU * _ease_io(_seg(_st, 0.02, 0.5)), 0.0)
		if _st < 0.05:
			_sq = maxf(_sq, 0.14)
		var scissor := sin(clampf(_st / 0.45, 0.0, 1.0) * TAU) * (1.0 - _seg(_st, 0.3, 0.5))
		_tbody_pitch = -22.0 * tuck * DEG
		_arms(lerpf(70.0, 160.0, rise), lerpf(55.0, 78.0, rise), lerpf(70.0, 160.0, rise), lerpf(55.0, 78.0, rise), 6.0, 6.0)
		if hero_v2:
			# Fix r1 (feel F6): a bigger arm flail through the pirouette's first 0.35 s (the arms windmill half a cycle apart).
			var fl := (1.0 - _seg(_st, 0.2, 0.35))
			var wv := _st * 22.0
			var al: Vector3 = _trot["arm_l"]
			var ar: Vector3 = _trot["arm_r"]
			al.x += 45.0 * DEG * sin(wv) * fl
			ar.x += 45.0 * DEG * sin(wv + PI) * fl
			_trot["arm_l"] = al
			_trot["arm_r"] = ar
			_arm_stretch_l = 0.2 * fl
			_arm_stretch_r = 0.2 * fl
		_leg_raw("l", lerpf(30.0, 40.0 + 30.0 * tuck + 30.0 * scissor, rise), lerpf(-50.0, -60.0 - 40.0 * tuck, rise), lerpf(10.0, 26.0, rise))
		_leg_raw("r", lerpf(10.0, -20.0 + 50.0 * tuck - 30.0 * scissor, rise), lerpf(-30.0, -30.0 - 60.0 * tuck, rise), lerpf(10.0, 26.0, rise))
		_r("spine", 6.0 * rise)
		_r("head", 14.0 * rise - 6.0 * fall)
		_eye_open = 1.0
		_brow_raise = 0.6
	else:
		# Rise: one knee up, one leg trailing, the opposite arm reaching (arcs follow the takeoff).
		_arms(lerpf(60.0, -30.0, rise), lerpf(60.0, 32.0, rise), lerpf(60.0, 150.0, rise), lerpf(60.0, 25.0, rise),
			lerpf(25.0, 35.0, rise), lerpf(25.0, 10.0, rise))
		_leg_raw("l", lerpf(30.0, 60.0, rise), lerpf(-50.0, -90.0, rise), 5.0)
		_leg_raw("r", lerpf(12.0, -14.0, rise), lerpf(-35.0, -22.0, rise), 5.0)
		_r("spine", -5.0 * rise + 2.0 * fall)
		_r("head", 10.0 * rise - 8.0 * fall)
	if fall > 0.5:
		var w := sin(t * 10.0) * fall
		_r("arm_l", 70.0 + 18.0 * w, 0.0, -62.0)
		_r("arm_r", 70.0 - 18.0 * w, 0.0, 62.0)
	if land_ready > 0.0:
		# Reach for the ground just before landing (clean contact, anticipation of the landing squash).
		_leg_raw("l", lerpf(30.0, 18.0, land_ready), lerpf(-50.0, -20.0, land_ready), 6.0)
		_leg_raw("r", lerpf(12.0, 6.0, land_ready), lerpf(-35.0, -14.0, land_ready), 6.0)
	_ear_target = Vector2(lerpf(-0.9, 0.7, rise), 0.25 * fall)
	if rise > 0.5 and not big:
		_sq = maxf(_sq, 0.1 * rise)
	if hero_v2:
		_air_secondary(vy, land_ready)
	_k = 16.0


## Hero v2 fix r1 (animation major: the air poses were frozen, depending only on vy): near the apex the arms float and the
## legs kick (one cycle per 0.4 s), the ears flap on the way down and the tail curls.
func _air_secondary(vy: float, land_ready: float) -> void:
	var apex := 1.0 - smoothstep(1.5, 5.0, absf(vy))
	var free := 1.0 - land_ready
	var ph := _st * TAU / 0.4
	for side in ["l", "r"]:
		var sg := 1.0 if side == "l" else -1.0
		var ar: Vector3 = _trot["arm_" + side]
		ar.x += 16.0 * DEG * sin(ph + (0.0 if side == "l" else 1.2)) * apex * free
		ar.z += sg * -10.0 * DEG * (0.5 + 0.5 * sin(ph * 0.5)) * apex * free
		_trot["arm_" + side] = ar
		var th: Vector3 = _trot["thigh_" + side]
		th.x += 18.0 * DEG * sin(ph + (0.0 if side == "l" else PI)) * apex * free
		_trot["thigh_" + side] = th
		var sh: Vector3 = _trot["shin_" + side]
		sh.x += -16.0 * DEG * maxf(0.0, sin(ph + (0.0 if side == "l" else PI))) * apex * free
		_trot["shin_" + side] = sh
	var down := smoothstep(0.5, -4.0, vy) * free
	_ear_target += Vector2(0.0, 0.35 * sin(_st * 14.0) * down)
	_tail_wag_speed = lerpf(_tail_wag_speed, 9.0, apex)
	_tail_wag_amp = lerpf(_tail_wag_amp, 24.0, maxf(apex, down))
	var hd: Vector3 = _trot["head"]
	hd.z += 5.0 * DEG * sin(ph * 0.5) * apex * free
	_trot["head"] = hd


func _pose_fall() -> void:
	var w := sin(t * 9.0)
	var land_ready := smoothstep(-3.0, -9.0, player.vy)
	_arms(70.0 + 15.0 * w, 62.0, 70.0 - 15.0 * w, 62.0, 25.0, 25.0)
	_leg_raw("l", lerpf(32.0 + 8.0 * w, 18.0, land_ready), lerpf(-55.0, -20.0, land_ready), 6.0)
	_leg_raw("r", lerpf(12.0 - 8.0 * w, 6.0, land_ready), lerpf(-38.0, -14.0, land_ready), 6.0)
	_r("spine", 2.0)
	_r("head", -8.0)
	_ear_target = Vector2(-0.6, 0.5)
	_brow_raise = 0.3
	if hero_v2:
		_air_secondary(player.vy, land_ready)
	_k = 10.0


func _pose_bounce() -> void:
	## Stomp / bounce pad (fix r1): on contact the legs are straight with the hooves pointed down and the body
	## squashed, then he tucks and springs open into a star.
	if _st < 0.02:
		_sq = minf(_sq, -0.2)
		_sq_v = maxf(_sq_v, 2.5)
	var push := 1.0 - _ease_out(_seg(_st, 0.0, 0.1))
	var tuck := _bell(_st, 0.06, 0.4)
	var star := _ease_io(_seg(_st, 0.3, 0.55))
	_leg_raw("l", lerpf(lerpf(-4.0, 85.0, tuck), 30.0, star), lerpf(lerpf(-2.0, -120.0, tuck), -30.0, star), lerpf(4.0, 22.0, star))
	_leg_raw("r", lerpf(lerpf(4.0, 80.0, tuck), 20.0, star), lerpf(lerpf(-2.0, -115.0, tuck), -24.0, star), lerpf(4.0, 22.0, star))
	_arms(lerpf(lerpf(30.0, 60.0, tuck), 150.0, star), lerpf(lerpf(70.0, 20.0, tuck), 70.0, star),
		lerpf(lerpf(30.0, 60.0, tuck), 150.0, star), lerpf(lerpf(70.0, 20.0, tuck), 70.0, star), lerpf(20.0, 100.0, tuck), lerpf(20.0, 100.0, tuck))
	_r("spine", -18.0 * tuck + 6.0 * star)
	_r("head", -10.0 * push + 12.0 * star)
	_spin = Vector3(-0.5 * tuck, 0.0, 0.0)
	_ear_target = Vector2(-0.8 * push + 0.6 * star, 0.4)
	_eye_open = lerpf(0.5, 1.1, star)
	_brow_raise = lerpf(-0.6, 1.0, star)
	_k = 30.0
	if player.vy < -2.0:
		_pose_fall()


func _pose_flip(axis: Vector3, dur: float, forward: bool) -> void:
	## Somersaults: launch stretch, tuck into a slow-in / fast-middle / slow-out turn, open up to land.
	## Fix r1: the turn spans about 70 % of the airtime predicted from the launch speed (it used to finish in the
	## rise and leave a 0.7 s static star), overshoots about 10 degrees and settles, then the descent keeps moving:
	## a slow arm windmill, a leg bicycle and the land-ready reach.
	var g := maxf(player.p.gravity, 1.0)
	var air := 2.0 * maxf(_entry_vy, 0.0) / g
	if air > 0.2:
		dur = maxf(dur, air * 0.68)
	var u := _st / dur
	var over := 0.17
	if u < 1.0:
		var turn := _ease_io(_seg(u, 0.06, 0.9))
		var tuck := _bell(u, 0.02, 1.0)
		var a := turn * TAU + over * _ease_io(_seg(u, 0.82, 1.0))
		_spin = axis * a
		_leg_raw("l", lerpf(10.0, 95.0, tuck), lerpf(-20.0, -135.0, tuck), 10.0)
		_leg_raw("r", lerpf(5.0, 90.0, tuck), lerpf(-15.0, -128.0, tuck), 10.0)
		_arms(lerpf(150.0, 70.0, tuck), lerpf(40.0, 10.0, tuck), lerpf(150.0, 70.0, tuck), lerpf(40.0, 10.0, tuck),
			lerpf(10.0, 110.0, tuck), lerpf(10.0, 110.0, tuck))
		_r("spine", -26.0 * tuck)
		_r("head", -16.0 * tuck)
		_tspine_scale = 1.0 - 0.06 * tuck
		_ear_target = Vector2(0.8 if forward else -0.8, 0.0)
		_eye_open = lerpf(1.0, 0.25, tuck)
		if hero_v2:
			# Fix r1 (minor): the hat is pulled down onto the head through the top of the flip (it looked detached in 3/4).
			_hat_tug = -0.014 * _bell(u, 0.2, 0.8)
		_k = 30.0
		if u < 0.08:
			_sq = maxf(_sq, 0.12)
	else:
		var su := _st - dur
		_spin = axis * over * exp(-su * 9.0) * cos(su * 15.0)
		var land_ready := smoothstep(-3.0, -10.0, player.vy)
		var w := su * 1.5 * TAU
		var open := _ease_out(clampf(su / 0.18, 0.0, 1.0))
		var free := 1.0 - land_ready
		# Windmill (arms half a cycle apart) easing into the land-ready reach.
		var al := lerpf(100.0 + 55.0 * sin(w), 62.0, land_ready)
		var ar := lerpf(100.0 + 55.0 * sin(w + PI), 62.0, land_ready)
		_arms(al, lerpf(72.0, 80.0, open), ar, lerpf(72.0, 80.0, open), 15.0, 15.0)
		var b := su * 2.2 * TAU
		var tl := lerpf(18.0, 30.0 + 26.0 * sin(b) * free, open)
		var tr := lerpf(4.0, 22.0 + 26.0 * sin(b + PI) * free, open)
		var sl := lerpf(-30.0, -48.0 - 28.0 * maxf(0.0, cos(b)) * free, open)
		var sr := lerpf(-18.0, -40.0 - 28.0 * maxf(0.0, cos(b + PI)) * free, open)
		_leg_raw("l", lerpf(tl, 18.0, land_ready), lerpf(sl, -20.0, land_ready), 9.0)
		_leg_raw("r", lerpf(tr, 6.0, land_ready), lerpf(sr, -14.0, land_ready), 9.0)
		_r("spine", 4.0 + 4.0 * sin(w * 0.5), 6.0 * sin(w))
		_r("head", 6.0 - 6.0 * land_ready, -4.0 * sin(w))
		_ear_target = Vector2(-0.4, 0.6)
		_brow_raise = 0.7
		_k = 14.0


func _pose_long_jump() -> void:
	## Fix r1: no frozen 1 s pose. The arms paddle from forward to back over the airtime, the legs flutter-kick
	## and swing forward to land, the body levels out as it falls.
	var g := maxf(player.p.long_jump_gravity, 1.0)
	var air := maxf(2.0 * maxf(_entry_vy, 0.0) / g, 0.4)
	var pr := clampf(_st / air, 0.0, 1.0)
	var stretch := _bell(_st, 0.0, 0.5)
	var land_ready := smoothstep(-3.0, -8.0, player.vy)
	_tbody_pitch = (-62.0 + 22.0 * pr + 10.0 * land_ready) * DEG
	var paddle := sin(_st * 8.0) * 12.0 * (1.0 - land_ready)
	var ax := lerpf(165.0, 40.0, _ease_io(pr)) + paddle
	_arms(ax, 18.0 + 10.0 * pr, ax - 2.0 * paddle, 18.0 + 10.0 * pr, lerpf(0.0, 30.0, pr), lerpf(0.0, 30.0, pr))
	var fl := sin(_st * 15.0) * 16.0 * (1.0 - land_ready)
	_leg_raw("l", lerpf(-30.0 + fl, 34.0, land_ready), lerpf(-30.0, -40.0, land_ready), 6.0)
	_leg_raw("r", lerpf(-18.0 - fl, 26.0, land_ready), lerpf(-18.0, -30.0, land_ready), 6.0)
	_r("spine", -6.0 + 8.0 * pr)
	_r("head", lerpf(46.0, 24.0, pr))
	_ear_target = Vector2(1.2, 0.15 * sin(_st * 11.0))
	_brow_raise = -0.4
	_lid_tilt = 0.35
	_eye_open = 0.85
	_tspine_scale = 1.0 + 0.08 * stretch
	_k = 14.0


func _pose_dive() -> void:
	_tbody_pitch = -80.0 * DEG
	var fl := sin(_st * 16.0) * 10.0
	_arms(165.0 + 0.4 * fl, 16.0, 165.0 - 0.4 * fl, 16.0, 0.0, 0.0)
	_leg_raw("l", -16.0 + fl, -14.0, 7.0)
	_leg_raw("r", -10.0 - fl, -10.0, 7.0)
	_r("spine", -6.0)
	_r("head", 64.0)
	_ear_target = Vector2(1.3, 0.0)
	_brow_raise = -0.7
	_lid_tilt = 0.4
	_eye_open = 0.8
	_tspine_scale = 1.07
	# Fix r1: the body pitch snaps to the dive line instead of lagging at 45-55 degrees.
	_k = 30.0


func _pose_jump_kick() -> void:
	var u := clampf(_st / maxf(player.p.jump_kick_time, 0.05), 0.0, 1.0)
	var chamber := _ease_io(_seg(u, 0.0, 0.12))
	var ext := _ease_out(_seg(u, 0.1, 0.3)) * (1.0 - _ease_io(_seg(u, 0.7, 1.0)))
	_tbody_pitch = 22.0 * ext * DEG
	_r("thigh_r", lerpf(70.0 * chamber, 105.0, ext), 0.0, 6.0)
	_r("shin_r", lerpf(-100.0 * chamber, -2.0, ext))
	_leg_raw("l", -20.0, -80.0, 6.0)
	_r("spine", 12.0 * ext, -15.0 * ext)
	_r("head", -10.0 * ext)
	_arms(-40.0 * ext + 30.0, 60.0, -40.0 * ext + 30.0, 60.0, 20.0, 20.0)
	_brow_raise = -0.8
	_lid_tilt = 0.45
	_eye_open = 0.8
	_k = 30.0


func _pose_wall_slide() -> void:
	# Back to the wall? No: belly to the wall, hooves braced, sliding down with a worried look.
	var w := sin(t * 20.0) * 0.5
	_tbody_pitch = -6.0 * DEG
	_troot_pos = Vector3(0.0, 0.0, -0.05)
	_arms(118.0 + 6.0 * w, 32.0, 108.0 - 6.0 * w, 28.0, 25.0, 25.0)
	_leg_raw("l", 60.0, -60.0, 8.0)
	_leg_raw("r", 18.0, -45.0, 8.0)
	_r("spine", 6.0)
	_r("head", 16.0, 0.0, 4.0 * w)
	_ear_target = Vector2(-0.5, 0.4)
	_brow_raise = 0.8
	if hero_v2:
		# Fix r1 (animation major: the wall slide looked like idle). Belly to the wall: the right hoof and the right foot
		# press flat on the wall, the left arm flails out to the side, the head turns away from the wall with a squint,
		# and a 14 Hz friction judder runs through the body.
		var jud := sin(t * TAU * 14.0)
		_troot_pos = Vector3(0.004 * jud, 0.003 * jud, -0.06)
		_tbody_pitch = -10.0 * DEG
		_arms(55.0 + 10.0 * sin(t * 9.0), 70.0, 112.0 + 2.0 * jud, 8.0, 20.0, 12.0)
		_arm_stretch_r = 0.3
		_leg_raw("r", 78.0, -18.0, 6.0)
		_leg_raw("l", 12.0 + 8.0 * sin(t * 7.0), -42.0, 10.0)
		_r("spine", 4.0, -10.0)
		_r("head", 10.0, 52.0, 12.0 + 2.0 * jud)
		_eye_open = 0.45
		_lid_tilt = 0.55
		_brow_raise = -0.3
		_ear_target = Vector2(-0.7, 0.5)
		_tail_wag_speed = 16.0


func _pose_wall_kick() -> void:
	# Push off: legs extend back toward the wall, body launches, arms swing forward and up.
	var u := _st
	var push := 1.0 - _ease_io(_seg(u, 0.0, 0.3))
	var vy := player.vy
	if u < 0.3:
		_leg_raw("l", lerpf(-10.0, -45.0, push), -10.0, 6.0)
		_leg_raw("r", lerpf(-5.0, -35.0, push), -16.0, 6.0)
		_arms(lerpf(120.0, 150.0, push), 35.0, lerpf(120.0, 150.0, push), 35.0, 10.0, 10.0)
		_tbody_pitch = -20.0 * push * DEG
		_r("head", 10.0)
		_tspine_scale = 1.0 + 0.06 * push
		_ear_target = Vector2(-1.0, 0.0)
		_lid_tilt = 0.3
		_k = 26.0
	elif vy > -2.0:
		_pose_jump(true)
	else:
		_pose_fall()


func _pose_ham_slam() -> void:
	## Ham Slam: tuck, one forward somersault while hovering, open into the butt-first drop.
	var spin_t := player.p.slam_spin_time
	var u := _st / spin_t
	if u < 1.0:
		var tuck := _ease_io(_seg(u, 0.0, 0.16))
		var turn := _ease_io(_seg(u, 0.12, 0.86))
		var open := _ease_io(_seg(u, 0.84, 1.0))
		_spin = Vector3(-TAU * turn, 0.0, 0.0)
		_leg_raw("l", lerpf(lerpf(20.0, 100.0, tuck), 100.0, open), lerpf(lerpf(-30.0, -140.0, tuck), -110.0, open), 12.0)
		_leg_raw("r", lerpf(lerpf(15.0, 96.0, tuck), 96.0, open), lerpf(lerpf(-25.0, -134.0, tuck), -104.0, open), 12.0)
		_arms(lerpf(lerpf(60.0, 55.0, tuck), 168.0, open), lerpf(40.0, 24.0, open), lerpf(lerpf(60.0, 55.0, tuck), 168.0, open),
			lerpf(40.0, 24.0, open), lerpf(110.0, 10.0, open), lerpf(110.0, 10.0, open))
		_r("spine", lerpf(-28.0 * tuck, 10.0, open))
		_r("head", lerpf(-18.0 * tuck, -22.0, open))
		_tbody_pitch = 25.0 * DEG * open
		_tspine_scale = 1.0 - 0.08 * tuck * (1.0 - open)
		_eye_open = lerpf(1.0, 0.2, tuck * (1.0 - open))
		_ear_target = Vector2(0.6, 0.0)
		_k = 34.0
		if u < 0.06:
			_sq = minf(_sq, -0.08)
	else:
		# Fix r1 drop pose: rump leads (body pitched back 25 degrees), thighs tucked to the belly with the shins folded,
		# arms straight up, chin tucked with the eyes on the landing spot, a stretch that grows with fall speed and
		# the ears streaming up.
		# Fix r2: the rump-first pose is held for the whole drop (pitched back 34 degrees, thighs pulled to the belly,
		# hooves up), and the last 3 frames before contact stretch 1.15x vertically into the impact squash.
		var fall := clampf(-player.vy / 18.0, 0.0, 1.0)
		var jit := sin(t * 40.0) * 2.0 * fall
		_tbody_pitch = 34.0 * DEG
		_leg_raw("l", 118.0 + jit, -96.0, 16.0)
		_leg_raw("r", 112.0 - jit, -90.0, 16.0)
		_arms(160.0 + jit, 30.0, 160.0 - jit, 30.0, 6.0, 6.0)
		_r("spine", 14.0)
		_r("head", -30.0)
		_tspine_scale = 1.0 + 0.1 * fall
		var gd := _ground_distance()
		if player.vy < -1.0 and gd < -player.vy * 0.055:
			_tspine_scale = 1.15
			_sq = maxf(_sq, 0.15)
		_ear_target = Vector2(-0.6, -1.0)
		_brow_raise = -1.0
		_lid_tilt = 0.55
		_eye_open = 0.7
		_sq = maxf(_sq, 0.12 * fall)
		_k = 34.0


func _pose_hurt_air() -> void:
	var u := _st
	_spin = Vector3(0.0, TAU * _ease_out(u / 0.55), 0.0)
	_tbody_pitch = 24.0 * DEG
	var w := sin(t * 16.0)
	_arms(150.0 + 22.0 * w, 70.0, 150.0 - 22.0 * w, 70.0, 30.0, 30.0)
	_leg_raw("l", 50.0 + 15.0 * w, -60.0, 12.0)
	_leg_raw("r", 30.0 - 15.0 * w, -40.0, 12.0)
	_r("spine", 22.0)
	_r("head", 18.0, 0.0, 10.0 * w)
	_eye_open = 0.0
	_brow_raise = 1.0
	_ear_target = Vector2(-1.0, 1.0)
	_k = 22.0


func _pose_bonk() -> void:
	# Splat against the wall, then tip over backwards with stars in the eyes.
	var u := _st
	var splat := 1.0 - _ease_out(_seg(u, 0.0, 0.18))
	_tbody_pitch = lerpf(-8.0, 40.0, _ease_io(_seg(u, 0.1, 0.5))) * DEG
	_troot_pos = Vector3(0.0, 0.0, 0.1 * splat)
	_arms(lerpf(150.0, 120.0, splat), 75.0, lerpf(150.0, 120.0, splat), 75.0, 20.0, 20.0)
	_leg_raw("l", 40.0, -50.0, 12.0)
	_leg_raw("r", 25.0, -35.0, 12.0)
	_r("head", 14.0, 0.0, 12.0 * sin(t * 18.0) * (1.0 - splat))
	if u < 0.05:
		_sq = minf(_sq, -0.2)
	_eye_open = 0.0 if u < 0.3 else 0.5
	_brow_raise = 1.0
	_ear_target = Vector2(1.0, 0.8)
	_k = 24.0


func _pose_fallout() -> void:
	var w := sin(t * 16.0)
	_arms(160.0 + 25.0 * w, 45.0, 160.0 - 25.0 * w, 45.0, 20.0, 20.0)
	_leg_raw("l", 30.0 + 30.0 * sin(t * 14.0), -50.0, 8.0)
	_leg_raw("r", 30.0 - 30.0 * sin(t * 14.0), -50.0, 8.0)
	_r("head", 22.0, 0.0, 8.0 * w)
	_eye_open = 1.2
	_brow_raise = 1.0
	_ear_target = Vector2(-0.8, -1.0)
	_k = 16.0


# ------------------------------------------------------------------ overlays (fix r1)

func _overlays(s: String, dt: float) -> void:
	var f := _st * 60.0
	# Push-off: every jump starts on the press frame, so the anticipation is staged inside its first frames.
	# Frame 0: hips down, knees bent, arms down and back (the squash comes from kick()). Frames 1-5: the legs
	# extend past straight and the arms swing up through their arc into the jump pose.
	if JUMP_KINDS.has(s) and f < 6.0:
		var crouch := 1.0 - _ease_out(clampf(f / 2.2, 0.0, 1.0))
		var ext := _bell(f, 0.6, 6.0) * (1.0 - crouch)
		# Fix r2: the backflip loads deeper (hips 10 cm down, arms swung back) so the flip reads as earned.
		var depth := 0.15 if s == "backflip" else 0.045
		_troot_pos.y += -depth * ls * crouch
		for side in ["l", "r"]:
			var th: Vector3 = _trot["thigh_" + side]
			var sh: Vector3 = _trot["shin_" + side]
			th.x = lerpf(lerpf(th.x, -6.0 * DEG, ext), 48.0 * DEG, crouch)
			sh.x = lerpf(lerpf(sh.x, -4.0 * DEG, ext), -86.0 * DEG, crouch)
			_trot["thigh_" + side] = th
			_trot["shin_" + side] = sh
		for side in ["l", "r"]:
			var ar: Vector3 = _trot["arm_" + side]
			ar.x = lerpf(ar.x, -38.0 * DEG, crouch)
			_trot["arm_" + side] = ar
		var sp: Vector3 = _trot["spine"]
		sp.x += -10.0 * DEG * crouch
		_trot["spine"] = sp
		_tspine_scale *= 1.0 + 0.06 * ext
		_k = maxf(_k, 46.0)
	# Landing: the pose carries the beat (hips down, arms thrown down and back, the head dips two frames late),
	# holds the bottom for two frames, then recovers. The ground pass bends the knees to keep the hooves planted.
	_land_t += dt
	if LAND_OVERLAY_STATES.has(s) and _land_t < 0.3:
		var lf := _land_t * 60.0
		var dip := _land_curve(lf) * _land_amt
		var late := _land_curve(lf - 2.0) * _land_amt
		if hero_v2:
			# Fix r1 (animation blocker: landings crashed): a lighter dip that keeps the head above the shoulders, then a
			# bounce on the way out: the ears flick up and the hat lifts 1.5 cm around frames 6-14 (the squash spring's
			# overshoot to about 1.05 carries the body). Hard landings add a stagger with a head wobble (feel F6).
			dip *= 0.6
			late *= 0.5
			var reb := _bell(lf, 5.0, 15.0)
			_ear_target += Vector2(0.0, -0.5 * reb * _land_amt)
			_hat_lift += 0.015 * reb * _land_amt
			if _land_amt > 0.65:
				var stg := exp(-maxf(lf - 3.0, 0.0) / 9.0) * _seg(lf, 2.0, 4.0)
				var hd5: Vector3 = _trot["head"]
				hd5.z += 9.0 * DEG * sin(lf * 0.75) * stg
				_trot["head"] = hd5
				_trot["root"] = (_trot["root"] as Vector3) + Vector3(0.0, 0.0, 4.0 * DEG * sin(lf * 0.5) * stg)
		_troot_pos.y -= 0.065 * ls * dip
		_tbody_pitch += -9.0 * DEG * dip
		for side in ["l", "r"]:
			var ar: Vector3 = _trot["arm_" + side]
			ar.x = lerpf(ar.x, -42.0 * DEG, dip)
			ar.z += (28.0 * DEG * dip) * (-1.0 if side == "l" else 1.0)
			_trot["arm_" + side] = ar
		var sp2: Vector3 = _trot["spine"]
		sp2.x += -10.0 * DEG * dip
		_trot["spine"] = sp2
		var hd: Vector3 = _trot["head"]
		hd.x += -14.0 * DEG * late
		_trot["head"] = hd
		_ear_target += Vector2(-0.5 * late, 0.5 * late)
		_k = maxf(_k, 40.0)
	# Fix r2 (feel major M1): the mantle hop-up. While the visual eases up onto the top (0.2 s), the knees tuck, the hooves
	# push down on the lip and the body pitches forward, then he stands.
	if player != null and player.mantle_time >= 0.0 and player.mantle_time < 0.3:
		var mu := _bell(player.mantle_time, 0.0, 0.3)
		_tbody_pitch += -20.0 * DEG * mu
		for side in ["l", "r"]:
			var thm: Vector3 = _trot["thigh_" + side]
			thm.x += (70.0 if side == "r" else 35.0) * DEG * mu
			_trot["thigh_" + side] = thm
			var shm: Vector3 = _trot["shin_" + side]
			shm.x += -80.0 * DEG * mu
			_trot["shin_" + side] = shm
			var arm: Vector3 = _trot["arm_" + side]
			arm.x = lerpf(arm.x, 40.0 * DEG, mu)
			_trot["arm_" + side] = arm
		_k = maxf(_k, 30.0)
	# Fix r2: after a brake to a stop the weight rocks forward past rest and back over about 8 frames.
	if _settle_t < 0.5 and (s == "idle" or s == "walk"):
		_tbody_pitch += -6.0 * DEG * sin(_settle_t * 13.0) * exp(-_settle_t * 6.0)
		if hero_v2:
			# Fix r1: at the stop the head whips forward past rest and settles within about 10 frames.
			var hd6: Vector3 = _trot["head"]
			hd6.x += -14.0 * DEG * sin(_settle_t * 19.0) * exp(-_settle_t * 9.0)
			_trot["head"] = hd6
			_k = maxf(_k, 30.0)
		var ar2: Vector3 = _trot["arm_l"]
		ar2.x += 20.0 * DEG * exp(-_settle_t * 7.0)
		_trot["arm_l"] = ar2
		var ar3: Vector3 = _trot["arm_r"]
		ar3.x += 20.0 * DEG * exp(-_settle_t * 7.0)
		_trot["arm_r"] = ar3
	if s == "side_flip" and player != null and absf(player.visual_yaw_offset) > 0.01:
		var off := player.visual_yaw_offset
		var hd2: Vector3 = _trot["head"]
		hd2.y += -off * 0.45
		_trot["head"] = hd2
		var sp3: Vector3 = _trot["spine"]
		sp3.y += -off * 0.25
		_trot["spine"] = sp3
	# Strike smears: the striking limb stretches on the snap frames (applied as a uniform bone scale in _apply).
	_smear.clear()
	if _arm_stretch_r > 0.001:
		_smear["arm_r"] = 1.0 + _arm_stretch_r
	if _arm_stretch_l > 0.001:
		_smear["arm_l"] = 1.0 + _arm_stretch_l
	if _thigh_stretch_r > 0.001:
		_smear["thigh_r"] = 1.0 + _thigh_stretch_r
	if s == "punch":
		var step := player.combo_step
		if step == 3:
			var u3 := _st / maxf(player.p.kick_time, 0.05)
			if not hero_v2:
				_smear["thigh_r"] = 1.0 + 0.25 * _bell(u3, 0.15, 0.55)
		elif hero_v2:
			pass      # _pose_jab_v2 sets the arm smear (_arm_stretch_l/r)
		else:
			var u := _st / maxf(player.p.punch_time, 0.05)
			_smear["arm_r" if step == 1 else "arm_l"] = 1.0 + 0.32 * _bell(u, 0.16, 0.5)
	elif s == "jump_kick":
		var uk := _st / maxf(player.p.jump_kick_time, 0.05)
		_smear["thigh_r"] = 1.0 + 0.25 * _bell(uk, 0.08, 0.45)
	elif s == "celebrate":
		# Raised arms stretch so the hooves clear the head (the 0.17 m arms cannot reach above the beanie otherwise).
		for side in ["l", "r"]:
			var ax: float = (_rot["arm_" + side] as Vector3).x / DEG
			var st := clampf((ax - 90.0) / 60.0, 0.0, 1.0)
			if st > 0.0:
				_smear["arm_" + side] = 1.0 + 0.4 * st


func _land_curve(lf: float) -> float:
	if lf < 0.0:
		return 0.0
	if lf < 2.0:
		return _ease_out(lf / 2.0)
	if lf < 4.0:
		return 1.0
	return 1.0 - _ease_io((lf - 4.0) / 11.0)


func _ground_feet(s: String, dt: float) -> void:
	## World-grounded feet (fix r1): after the full root transform is on the skeleton, measure each IK hoof and lift
	## any that ended up below the floor by shortening that leg (same frame), keeping the correction for the next frames.
	if skeleton == null or int(_foot_bones[0]) < 0 or player == null:
		return
	var active := GROUND_FEET_STATES.has(s) and player.grounded
	var to_vis := player.visual.global_transform.affine_inverse() * skeleton.global_transform
	for i in 2:
		var side := "l" if i == 0 else "r"
		var old_fix: float = _foot_fix[side]
		if not active or not _ik_req.has(side):
			_foot_fix[side] = move_toward(old_fix, 0.0, dt * 0.8)
			continue
		var fy := (to_vis * skeleton.get_bone_global_pose(int(_foot_bones[i])).origin).y
		var err := _sole_h - fy - 0.006
		var nf := old_fix
		if err > 0.0:
			nf = clampf(old_fix + err, 0.0, 0.18)
		else:
			nf = maxf(old_fix + err * 0.5, 0.0)
		if absf(nf - old_fix) > 0.0015:
			var req: Vector3 = _ik_req[side]
			var a := _ik_solve(req.x, req.y - old_fix)
			var b := _ik_solve(req.x, req.y - nf)
			var th: Vector3 = _rot["thigh_" + side]
			var sh: Vector3 = _rot["shin_" + side]
			th.x += b.x - a.x
			sh.x += b.y - a.y
			_rot["thigh_" + side] = th
			_rot["shin_" + side] = sh
			adapter.call("set_joint", "thigh_" + side, _joint_basis("thigh_" + side, th), Vector3.ZERO)
			adapter.call("set_joint", "shin_" + side, Basis.from_euler(sh), Vector3.ZERO)
		_foot_fix[side] = nf


func _joint_basis(j: String, r: Vector3) -> Basis:
	var b := Basis.from_euler(r)
	if _smear.has(j):
		b = b * Basis.from_scale(Vector3.ONE * float(_smear[j]))
	return b


# ------------------------------------------------------------------ blend and apply

func _blend(dt: float) -> void:
	var a := 1.0 - exp(-_k * dt)
	_gait_lock = move_toward(_gait_lock, _gait_lock_target, dt / 0.12)
	var al := maxf(a, _gait_lock)
	for j in JOINTS:
		var cur: Vector3 = _rot[j]
		var tgt: Vector3 = _trot[j]
		_rot[j] = cur.lerp(tgt, al if GAIT_LOCK_JOINTS.has(j) else a)
	_root_pos = _root_pos.lerp(_troot_pos, al)
	_body_pitch = lerpf(_body_pitch, _tbody_pitch, a)
	# Fix r1: the run's contact squash and push stretch are per-step keys, so they follow the gait lock too.
	_spine_scale = lerpf(_spine_scale, _tspine_scale, al if hero_v2 else a)


## Fix r1 (feel F5): the hat and ears reach well outside the capsule and clipped into fences, parapets and overhangs. Three
## short rays (every other frame, layer 1): up from the hat top for a ceiling, and left and right at ear height for walls.
## Returns the fold amount per ear; the ceiling factor is stored in _ceil_k. The collision capsule is left alone.
func _space_probe(dt: float) -> Array:
	if not hero_v2 or player == null or not player.is_inside_tree():
		return [0.0, 0.0]
	_probe_t -= dt
	if _probe_t <= 0.0:
		_probe_t = 1.0 / 30.0
		var ss := player.get_world_3d().direct_space_state
		var o := player.global_position
		var ex: Array[RID] = [player.get_rid()]
		var top := o + Vector3.UP * 1.3
		var hit := ss.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.UP * 0.8, 1, ex))
		var ck := 0.0
		if not hit.is_empty():
			ck = clampf(1.0 - ((hit["position"] as Vector3).y - top.y) / 0.8, 0.0, 1.0)
		_ceil_k = ck
		var right := MakPlayer.dir_from_yaw(player.facing_yaw + _cam_turn).cross(Vector3.UP).normalized()
		var eh := o + Vector3.UP * 1.0
		for i in 2:
			var dir := -right if i == 0 else right      # ear_l is Mak's left (model +X, the visual faces -Z)
			var h2 := ss.intersect_ray(PhysicsRayQueryParameters3D.create(eh, eh + dir * 0.6, 1, ex))
			var f := 0.0
			if not h2.is_empty():
				f = clampf(1.0 - ((h2["position"] as Vector3) - eh).length() / 0.6, 0.0, 1.0) * 1.6
			_fold[i] = clampf(f, 0.0, 1.0)
	return _fold


func _spring2(pos: Vector2, vel: Vector2, target: Vector2, k: float, c: float, dt: float) -> Array:
	var acc := (target - pos) * k - vel * c
	vel += acc * dt
	pos += vel * dt
	return [pos, vel]


func _apply(dt: float) -> void:
	# Squash and stretch spring (about the feet).
	var acc := -230.0 * _sq - 11.0 * _sq_v
	_sq_v += acc * dt
	var sq_min := SLAM_SQ_MIN if (_state == "slam_land" or _state == "ham_slam") else (LAND_SQ_MIN if hero_v2 else -0.5)
	_sq = clampf(_sq + _sq_v * dt, sq_min, 0.5)
	_sq_hold = lerpf(_sq_hold, _tsq_hold, 1.0 - exp(-12.0 * dt))
	var sy := 1.0 + _sq + _sq_hold
	if _ceil_k > 0.0 and sy > 1.0:
		sy = 1.0 + (sy - 1.0) * (1.0 - 0.5 * _ceil_k)
	_cam_turn = lerpf(_cam_turn, _cam_turn_target, 1.0 - exp(-(4.0 if absf(_cam_turn_target) > 0.01 else 14.0) * dt))
	var sxz := 1.0 / sqrt(maxf(sy, 0.3))
	# Respawn pop-in spring (uniform scale with overshoot).
	_pop_v += ((1.0 - _pop) * 180.0 - _pop_v * 11.0) * dt
	_pop = clampf(_pop + _pop_v * dt, 0.05, 1.4)
	# Ears and tail: damped springs for secondary motion.
	var fwd := MakPlayer.dir_from_yaw(player.facing_yaw)
	var fwd_acc := _accel.dot(fwd)
	var fold := _space_probe(dt)
	for i in 2:
		var target := _ear_target + Vector2(clampf(fwd_acc * 0.012, -0.5, 0.5), clampf(-_accel.y * 0.004, -0.4, 0.4))
		if float(fold[i]) > 0.0:
			# Fix r1 (feel F5): an ear next to a wall folds back and down instead of poking through it.
			target = target.lerp(Vector2(-1.0, 0.9), float(fold[i]))
		var r := _spring2(_ear[i], _ear_v[i], target, 150.0, 9.0, dt)
		_ear[i] = (r[0] as Vector2).clamp(Vector2(-1.1, -0.8), Vector2(1.1, 1.0))
		_ear_v[i] = r[1]
	# Chained second segments (fix r1): each targets 0.8x its parent's spring angle through a softer spring, so the
	# tips lag a few frames and whip instead of swinging as rigid paddles.
	for i in 2:
		var r2 := _spring2(_ear2[i], _ear2_v[i], (_ear[i] as Vector2) * 0.8, 90.0, 6.0, dt)
		_ear2[i] = (r2[0] as Vector2).clamp(Vector2(-1.0, -0.8), Vector2(1.0, 0.9))
		_ear2_v[i] = r2[1]
	var wag := sin(t * _tail_wag_speed) * _tail_wag_amp * DEG
	var rt := _spring2(_tail, _tail_v, Vector2(wag, 0.0), 120.0, 7.0, dt)
	_tail = rt[0]
	_tail_v = rt[1]
	var rt2 := _spring2(_tail2, _tail2_v, _tail * 0.9, 85.0, 5.0, dt)
	_tail2 = rt2[0]
	_tail2_v = rt2[1]
	var rt3 := _spring2(_tail3, _tail3_v, _tail2 * 0.9, 70.0, 4.2, dt)
	_tail3 = rt3[0]
	_tail3_v = rt3[1]
	# Backpack and hat: lag behind the body (follow-through), settle with a wobble.
	var root_vy := (_root_pos.y - _prev_root_y) / dt
	_prev_root_y = _root_pos.y
	var pack_lim := 0.2 if hero_v2 else 0.35       # fix r1: the pack slid down to the rump in brakes and skids
	if hero_v2 and (_state == "skid" or _brake_t >= 0.0):
		pack_lim = 0.08
	var pack_target := Vector2(clampf((fwd_acc * (0.006 if hero_v2 else 0.01)) - _accel.y * 0.004 + root_vy * 0.08, -pack_lim, pack_lim),
		clampf(-_yaw_rate * 0.04, -0.25, 0.25))
	# Heavier backpack (fix r1): lower stiffness and damping, so it swings later and longer than the ears and hat.
	var rp := _spring2(_pack, _pack_v, pack_target, 70.0, 4.4, dt)
	_pack = (rp[0] as Vector2).clamp(Vector2(-0.3 if hero_v2 else -0.45, -0.3), Vector2(0.3 if hero_v2 else 0.45, 0.3))
	if hero_v2 and (_state == "skid" or _brake_t >= 0.0 or _settle_t < 0.3):
		_pack.x = clampf(_pack.x, -0.1, 0.1)
		_pack_v.x *= 0.5
	_pack_v = rp[1]
	var hat_target := Vector2(clampf(fwd_acc * 0.008 - _accel.y * 0.0025 - _hb * 0.6, -0.22, 0.22), clampf(-_yaw_rate * 0.025, -0.14, 0.14))
	# Hero v2: a softer, wobblier hat (the tall top hat should visibly jiggle and lag; overlapping action).
	# Hat fit pass (owner 2026-10-19): on hero v2 the spring pitched the hat up to 14.4 degrees off the head in the run
	# (fwd_acc, the head-bob term and a footfall kick all summed into the +-0.25 rad clamp), so the brim lifted off the
	# crown and the beanie showed its inside. The hat now follows the head with a small bob: about a quarter of the
	# drive, a stiffer, better-damped spring and a +-3 degree pitch / +-2.3 degree roll limit.
	if hero_v2:
		hat_target = (hat_target * 0.25).clamp(Vector2(-0.045, -0.035), Vector2(0.045, 0.035))
	var rh := _spring2(_hat, _hat_v, hat_target, 320.0 if hero_v2 else 300.0, 26.0 if hero_v2 else 12.0, dt)
	if hero_v2:
		_hat = (rh[0] as Vector2).clamp(Vector2(-0.052, -0.04), Vector2(0.052, 0.04))
	else:
		_hat = (rh[0] as Vector2).clamp(Vector2(-0.25, -0.2), Vector2(0.25, 0.2))
	_hat_v = rh[1]
	_hat_sq_v += (-_hat_sq * 300.0 - _hat_sq_v * 12.0) * dt
	_hat_sq = clampf(_hat_sq + _hat_sq_v * dt, -0.25, 0.25)
	# Head bobble (hero v2): the big head is a soft spring on the neck. Vertical acceleration of the body and of the
	# visual root (bob, squash, hops) makes it lag and nod, then settle with one or two little overshoots.
	var bob_acc := clampf(_accel.y * 0.0035 + root_vy * 0.05, -0.3, 0.3)
	_hb_v += ((-bob_acc - _hb) * 190.0 - _hb_v * 10.0) * dt
	_hb = clampf(_hb + _hb_v * dt, -0.32, 0.32)
	# Visual offsets handed over by the controller (eased back to zero here).
	# The side flip's reversal is a 5-6 frame twist led by the head and shoulders (see _overlays), not a snap.
	player.visual_yaw_offset *= exp(-(7.5 if _state == "side_flip" else 11.0) * dt)
	if absf(player.visual_yaw_offset) < 0.002:
		player.visual_yaw_offset = 0.0
	player.visual_step_offset = move_toward(player.visual_step_offset, 0.0, 2.6 * dt) * exp(-10.0 * dt)
	# Root: lean about the feet, body pitch and flips about the body centre, squash about the feet.
	# Ledge grab catch: the body snapped onto the hang; the visual starts where it was and eases in over ~0.1 s.
	var grab_local := Vector3.ZERO
	if player.visual_grab_offset.length_squared() > 1e-8:
		grab_local = player.visual.global_transform.basis.inverse() * player.visual_grab_offset
		player.visual_grab_offset *= exp(-player.visual_grab_rate * dt)
		if player.visual_grab_offset.length() < 0.002:
			player.visual_grab_offset = Vector3.ZERO
	var lean: Vector3 = _rot["root"]
	var xf := Transform3D(Basis(Vector3.UP, player.visual_yaw_offset + _cam_turn) * Basis.from_euler(lean),
		_root_pos + Vector3(0.0, player.visual_step_offset, 0.0) + grab_local)
	var body := Basis(Vector3.RIGHT, _body_pitch) * Basis.from_euler(_spin)
	xf = xf * Transform3D(Basis.IDENTITY, BODY_CENTER) * Transform3D(body, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -BODY_CENTER)
	xf = xf * Transform3D(Basis.from_scale(Vector3(sxz, sy, sxz) * _pop), Vector3.ZERO)
	adapter.call("set_root", xf)
	for j in JOINTS:
		if j == "root":
			continue
		var r: Vector3 = _rot[j]
		var off := Vector3.ZERO
		if j == "ear_l":
			var e: Vector2 = _ear[0]
			r += Vector3(e.x, 0.0, e.y)
		elif j == "ear_r":
			var e2: Vector2 = _ear[1]
			r += Vector3(e2.x, 0.0, -e2.y)
		elif j == "tail":
			r += Vector3(_tail.y, _tail.x, 0.0)
		elif j == "ear_l_2":
			# Lag term (zero at rest) plus a little curl in the parent's direction.
			var e3: Vector2 = (_ear2[0] as Vector2) - (_ear[0] as Vector2) * 0.8 + (_ear[0] as Vector2) * 0.22
			r += Vector3(e3.x, 0.0, e3.y) * 1.3
		elif j == "ear_r_2":
			var e4: Vector2 = (_ear2[1] as Vector2) - (_ear[1] as Vector2) * 0.8 + (_ear[1] as Vector2) * 0.22
			r += Vector3(e4.x, 0.0, -e4.y) * 1.3
		elif j == "tail_2":
			r += Vector3(_tail2.y, _tail2.x, 0.0) * 0.7
		elif j == "tail_3":
			r += Vector3(_tail3.y, _tail3.x, 0.0) * 0.7
		elif j == "backpack":
			r += Vector3(_pack.x, 0.0, _pack.y)
		elif j == "head_top":
			r += Vector3(_hat.x - _hat_tip, 0.0, _hat.y)
			off = Vector3(0.0, _hat_tug + _hat_lift, -_hat_lift * 0.4)
		elif j == "head":
			r += Vector3(_hb, 0.0, 0.0)
		var b := _joint_basis(j, r)
		if j == "spine":
			b = b * Basis.from_scale(Vector3(1.0, _spine_scale, 1.0))
		elif j == "head_top" and absf(_hat_sq) > 0.001:
			b = b * Basis.from_scale(Vector3(1.0 - _hat_sq * 0.5, 1.0 + _hat_sq, 1.0 - _hat_sq * 0.5))
		adapter.call("set_joint", j, b, off)
	_apply_face(dt)
	# Invulnerability blink.
	if player.visual != null:
		player.visual.visible = not (player.hurt_blink > 0.0 and player.state != "hurt_air" and fmod(t, 0.14) < 0.05)


func _apply_face(dt: float) -> void:
	_blink_timer -= dt
	# Finish pass (idle life): a quick turn of the body (a sharp stick turn, or the idle turn to the camera) blinks, the
	# way animators hide a head turn; at most one turn blink per 1.2 s, never on top of a scheduled blink.
	_turn_blink_cd = maxf(_turn_blink_cd - dt, 0.0)
	var turn_rate := absf(_yaw_rate) + (absf(_cam_turn - _prev_cam_turn) / dt if dt > 0.0 else 0.0)
	_prev_cam_turn = _cam_turn
	if hero_v2 and turn_rate > 4.5 and _turn_blink_cd <= 0.0 and _blink <= 0.0 and _blink_timer > 0.5:
		_blink = 0.07
		_turn_blink_cd = 1.2
		_blink_timer = maxf(_blink_timer, 1.5)
	if _blink_timer <= 0.0:
		_blink_timer = _rng.randf_range(2.5, 5.0)
		_blink = 0.07
		# Occasionally a double blink.
		if _rng.randf() < 0.2:
			_blink_timer = 0.32
	_blink = maxf(_blink - dt, 0.0)
	var target := 0.0 if _blink > 0.0 else _eye_open
	_eye_cur = lerpf(_eye_cur, target, 1.0 - exp(-(75.0 if _blink > 0.0 else 34.0) * dt))
	_lid_tilt_cur = lerpf(_lid_tilt_cur, _lid_tilt, 1.0 - exp(-12.0 * dt))
	if hero_v2 and skeleton != null:
		# Bone lids: closed fraction plus a little determined lid; both eyes together (ATTACH.md blink timing).
		var c := clampf(1.0 - _eye_cur, 0.0, 1.0)
		var shown := maxf(c, _lid_tilt_cur * 0.3)
		for i in 2:
			var bi := int(_lid_bones[i])
			if bi >= 0:
				skeleton.set_bone_pose_rotation(bi, (_lid_rest[i] as Quaternion) * Quaternion(Vector3.RIGHT, deg_to_rad(LID_CLOSED_DEG * shown)))
		return
	if not _lids.is_empty():
		var close := clampf(1.0 - _eye_cur, 0.0, 1.0)
		# A determined look keeps a little lid even when open.
		var shown := maxf(close, _lid_tilt_cur * 0.25)
		for i in _lids.size():
			_lids[i].set_shader_parameter("close_amount", shown)
			_lids[i].set_shader_parameter("tilt", _lid_tilt_cur * 0.6)
			if i < _lid_nodes.size():
				_lid_nodes[i].visible = shown > 0.02
		return
	if proxy == null:
		return
	var open := _eye_cur
	var eyes: Variant = proxy.get("eye_nodes")
	if eyes is Array:
		for e in eyes:
			var n := e as Node3D
			if n != null:
				n.scale.y = lerpf(n.scale.y, maxf(open, 0.08), 1.0 - exp(-30.0 * dt))
	var brows: Variant = proxy.get("brow_nodes")
	if brows is Array:
		var i := 0
		for b in brows:
			var n := b as Node3D
			if n != null:
				var side := -1.0 if i == 0 else 1.0
				var ty := 0.252 + 0.02 * _brow_raise
				n.position.y = lerpf(n.position.y, ty, 1.0 - exp(-14.0 * dt))
				n.rotation_degrees.z = lerpf(n.rotation_degrees.z, (-12.0 - 14.0 * minf(_brow_raise, 0.0)) * side, 1.0 - exp(-14.0 * dt))
			i += 1
