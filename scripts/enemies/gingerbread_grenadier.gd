class_name GingerbreadGrenadier
extends EnemyBase
## Gingerbread Grenadier: a marching cookie soldier in a squad, with a candy-cane lance that
## blocks punches from the front. Marches a patrol path ("Hup! Hup!"), halts on sight, lowers
## the lance and lunges. Turns slowly, so you can get behind it or stomp from above.
## Defeat: crumbles into crumbs ("Oh crumbs!").

const DOUGH := Color(0.74, 0.45, 0.22)
const DOUGH_DARK := Color(0.58, 0.33, 0.15)
const ICING := Color(1.0, 0.98, 0.94)
const CANDY_RED := Color(0.9, 0.15, 0.2)
const HAT := Color(0.12, 0.08, 0.1)

@export var formation_index: int = 0
## Sergeant Snap (mission W3-2): bigger, two hits, leads the squad's calls.
@export var sergeant: bool = false
## "" (lance grenadier) or "lobber" (W3 tier A: no lance, no block, lobs a gobstopper every 2.5 s with a ring decal).
@export var variant: String = ""

var squad: Array = []
var _hup_t: float = 1.0
var _tip: MeshInstance3D
var _lance: Node3D
var _lance_mat: Array[MeshInstance3D] = []
var _step_phase: float = 0.0
var _alert_delay: float = -1.0
var _wobble: float = 0.0
## Sergeant signature: lance sweep (ring telegraph, 360 degree spin you jump over).
var _sweep_cd: float = 3.0
var _ring: MeshInstance3D
var _sweep_hit: bool = false
var _lob_t: float = 1.5
var _hints_done: bool = false
## Fix round 2: the lance is aimed in body space every frame (the A-pose arm twisted it into the turf when the wind-up
## rotated the shoulder, r1 animation), with its grip on the hand bone.
var _sk: Skeleton3D
var _hand_bone: int = -1
var _lance_sc: float = 0.62
var _lance_dir: Vector3 = Vector3(0, 1, 0.22)
var _lance_dir_want: Vector3 = Vector3(0, 1, 0.22)
var _lance_slide: float = 0.0
var _lance_slide_want: float = 0.0
var _lance_rate: float = 12.0
var _tick_t: float = 2.5
var _tick_kind: int = 0
var _tick_age: float = 9.0
const LANCE_PATH := "res://assets/characters/sergeant_snap/snap_lance.glb"
const SNAP_PATH := "res://assets/characters/sergeant_snap/sergeant_snap.glb"
const DRUM_PATH := "res://assets/characters/sergeant_snap/snap_drum.glb"
## Round-4 asset delivery: Snap v3 (shoulder ball joints, AO, clean flanks) and the matte-gold _v2 props. The v3 rest
## pose has the arms raised 50 degrees, so every arm pose is lowered by ARM_DROP_V3 (README: "lower by about 50").
const SNAP_V3_PATH := "res://assets/characters/sergeant_snap/sergeant_snap_v3.glb"
const LANCE_V2_PATH := "res://assets/characters/sergeant_snap/snap_lance_v2.glb"
const DRUM_V2_PATH := "res://assets/characters/sergeant_snap/snap_drum_v2.glb"
const ARM_DROP_V3 := 0.87
var _arm_drop: float = 0.0


## Plain defaults in _init so builder values survive (r1 blocker).
func _init() -> void:
	enemy_id = "gingerbread_grenadier"
	# Soldier: a short, stiff snap to attention.
	notice_hop = 0.1
	notice_stretch = 0.05
	notice_len = 0.26
	display_name = "Gingerbread Grenadier"
	body_radius = 0.34
	body_height = 1.1
	head_height = 1.3
	move_speed = 1.6
	turn_speed = 3.2
	notice_radius = 8.0
	lose_radius = 14.0
	patrol_wait = 0.6
	acorns_on_defeat = 1
	windup_len = 0.7
	# Brown on brown on W3's gingerbread: a thicker dark-chocolate ink line separates the cookie (r1 m9).
	# Fix r2: still camouflaged on the W3 caramel ramp (dE 18.7-21), so the line is near-black chocolate and wider and
	# the rim brighter, which separates the cookie's silhouette from same-hue ground.
	outline_width = 2.4
	outline_color = Color("#1E1009")
	toon_rim = 0.7


func _setup() -> void:
	_hup_t = 0.5 + 0.3 * float(formation_index)
	# Belt and braces: a builder that hands us Snap's mesh gets the sergeant (W3 never set the flag, r1 M1).
	if mesh_path.contains("sergeant_snap"):
		sergeant = true
	if sergeant:
		if display_name == "Gingerbread Grenadier":
			display_name = "Sergeant Snap"
		max_hp = maxi(max_hp, 2)
		body_radius = 0.42
		body_height = 1.4
		head_height = 1.7
		acorns_on_defeat = maxi(acorns_on_defeat, 4)
		if mesh_path == "" or mesh_path == SNAP_PATH:
			# W3 hands us the v1 path; the newest delivery replaces it (same bones, sockets and size).
			if ResourceLoader.exists(SNAP_V3_PATH):
				mesh_path = SNAP_V3_PATH
			elif mesh_path == "" and ResourceLoader.exists(SNAP_PATH):
				mesh_path = SNAP_PATH
		if mesh_path.ends_with("_v2.glb") or mesh_path.ends_with("_v3.glb"):
			_arm_drop = ARM_DROP_V3


func _build_visual() -> void:
	super._build_visual()
	# Measured heights: Snap 1.8 m (W3 amendment), grunts 1.3 m with the busby (README spec). The grunt mesh is
	# 1.12 m, shorter than Mak (r1 M6). The enemy owns Visual's scale; EnemyBase undoes an outside rescale.
	var target := 1.8 if sergeant else 1.3
	var sc := 1.3 if sergeant else 1.0
	if mesh_root != null:
		var h := _mesh_height(mesh_root)
		sc = clampf(target / h, 0.8, 1.4) if h > 0.2 else 1.0
	visual.scale = Vector3.ONE * sc
	_visual_scale_want = sc
	# Hit boxes follow the measured visual (hat top = head_height).
	head_height = target * 0.94 if mesh_root != null else head_height
	body_height = target * (0.78 if sergeant else 0.85)
	_resize_collision()


func _mesh_height(root: Node3D) -> float:
	var lo := INF
	var hi := -INF
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or _on_socket(m, root):
			continue
		var xf := inv * m.global_transform if m.is_inside_tree() else m.transform
		var bb := xf * m.get_aabb()
		lo = minf(lo, bb.position.y)
		hi = maxf(hi, bb.end.y)
	return hi - lo if hi > lo else 0.0


## True for props on bone sockets (lance, drum): they must not count toward the body height.
func _on_socket(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if p is BoneAttachment3D:
			return true
		p = p.get_parent()
	return false


func _on_mesh_ready(inst: Node) -> void:
	# Candy-cane lance (topup-chars prop) in the right hand: a BoneAttachment3D on hand_r.
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty() or not ResourceLoader.exists(LANCE_PATH) or variant == "lobber":
		return
	var sk := sks[0] as Skeleton3D
	var hand := sk.find_bone("hand_r")
	if hand < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "LanceSocket"
	att.bone_name = "hand_r"
	sk.add_child(att)
	if sergeant and ResourceLoader.exists(DRUM_PATH) and sk.find_bone("hips") >= 0:
		# Parade snare on the left hip (asset README look-dev: model-space offset (0.30, -0.05, 0.25) from the
		# hips, skin up, tipped 15 degrees toward the front), so the sergeant reads as the drum-major.
		var hip_att := BoneAttachment3D.new()
		hip_att.name = "DrumSocket"
		hip_att.bone_name = "hips"
		sk.add_child(hip_att)
		var drum := (load(DRUM_V2_PATH if ResourceLoader.exists(DRUM_V2_PATH) else DRUM_PATH) as PackedScene).instantiate() as Node3D
		hip_att.add_child(drum)
		var hips_rest := sk.get_bone_global_rest(sk.find_bone("hips"))
		var want_drum := Basis(Vector3(1, 0, 0), deg_to_rad(15.0))
		drum.transform = Transform3D(hips_rest.basis.orthonormalized().inverse() * want_drum,
			hips_rest.basis.orthonormalized().inverse() * Vector3(0.30, -0.05, 0.25))
	# The lance rides on the rig and is aimed in body space each frame (_after_pose), gripped at hand_r. Its origin is
	# the grip with the shaft along +Y: the gold spike leads and the candy-cane crook is the pommel behind the hand.
	_lance = (load(LANCE_V2_PATH if ResourceLoader.exists(LANCE_V2_PATH) else LANCE_PATH) as PackedScene).instantiate() as Node3D
	_lance.name = "Lance"
	rig.add_child(_lance)
	_sk = sk
	_hand_bone = hand
	_lance_sc = 1.0 if sergeant else 0.62
	for mi in _lance.find_children("*", "MeshInstance3D", true, false):
		_lance_mat.append(mi as MeshInstance3D)


func _build_placeholder(root: Node3D) -> void:
	var body := EnemyKit.pivot(root, "body", Vector3(0, 0.5, 0))
	EnemyKit.capsule(body, 0.3, 0.7, DOUGH, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1.05, 1, 0.6))
	# Icing belt, buttons and cuffs.
	EnemyKit.ring(body, 0.27, 0.31, ICING, Vector3(0, -0.05, 0), Vector3.ZERO).scale = Vector3(1.05, 1, 0.62)
	EnemyKit.ball(body, 0.06, CANDY_RED, Vector3(0, 0.25, -0.18))
	EnemyKit.ball(body, 0.06, Color(0.3, 0.75, 0.4), Vector3(0, 0.08, -0.19))
	EnemyKit.box(body, Vector3(0.5, 0.04, 0.05), ICING, Vector3(0, 0.38, -0.12), Vector3(0, 0, 0))
	var head := EnemyKit.pivot(body, "head", Vector3(0, 0.6, 0))
	head.set_meta("skin", DOUGH)
	EnemyKit.ball(head, 0.27, DOUGH, Vector3.ZERO, Vector3(1.0, 0.95, 0.65))
	EnemyKit.face(head, Vector3(0, 0.03, -0.15), 0.1, 0.07, Color(0.15, 0.08, 0.05), "determined")
	EnemyKit.mouth(head, Vector3(0, -0.12, -0.17), 0.15, "smirk", ICING)
	EnemyKit.ball(head, 0.04, Color(1.0, 0.55, 0.55), Vector3(-0.17, -0.06, -0.12))
	EnemyKit.ball(head, 0.04, Color(1.0, 0.55, 0.55), Vector3(0.17, -0.06, -0.12))
	# Tall guardsman hat with a plume and chin strap.
	EnemyKit.cylinder(head, 0.2, 0.23, 0.42, HAT, Vector3(0, 0.36, 0.02))
	EnemyKit.ball(head, 0.2, HAT, Vector3(0, 0.56, 0.02), Vector3(1, 0.5, 1))
	EnemyKit.ball(head, 0.07, CANDY_RED, Vector3(0.18, 0.42, 0.0), Vector3(0.6, 1.6, 0.6))
	EnemyKit.ring(head, 0.21, 0.235, Color(0.95, 0.75, 0.25), Vector3(0, 0.0, 0.0), Vector3(90, 90, 0)).scale = Vector3(1, 1, 0.8)
	for side in [-1.0, 1.0]:
		var arm := EnemyKit.pivot(body, "arm_l" if side < 0 else "arm_r", Vector3(0.33 * side, 0.36, 0))
		EnemyKit.capsule(arm, 0.1, 0.42, DOUGH, Vector3(0.04 * side, -0.16, 0), Vector3(0, 0, 12 * side), Vector3(1, 1, 0.65))
		EnemyKit.ring(arm, 0.08, 0.1, ICING, Vector3(0.07 * side, -0.3, 0), Vector3(0, 0, 12 * side))
		var leg := EnemyKit.pivot(root, "leg_l" if side < 0 else "leg_r", Vector3(0.15 * side, 0.36, 0))
		EnemyKit.capsule(leg, 0.12, 0.42, DOUGH, Vector3(0, -0.16, 0), Vector3.ZERO, Vector3(1, 1, 0.65))
		EnemyKit.ring(leg, 0.09, 0.12, ICING, Vector3(0, -0.24, 0), Vector3.ZERO)
	# Candy-cane lance in the right hand, pointing forward.
	var arm_r: Node3D = body.get_node("arm_r")
	var lance := EnemyKit.pivot(arm_r, "lance", Vector3(0.1, -0.34, 0))
	EnemyKit.cylinder(lance, 0.04, 0.04, 1.3, ICING, Vector3(0, 0, -0.35), Vector3(90, 0, 0))
	for i in 7:
		EnemyKit.ring(lance, 0.035, 0.05, CANDY_RED, Vector3(0, 0, 0.2 - 0.17 * float(i)), Vector3(90, 0, 25))
	_tip = EnemyKit.cone(lance, 0.07, 0.2, ICING, Vector3(0, 0, -1.08), Vector3(-90, 0, 0))
	EnemyKit.ring(lance, 0.05, 0.09, CANDY_RED, Vector3(0, 0, 0.32), Vector3(0, 0, 0))


func _initial_state() -> String:
	return "patrol"


func alert_squad() -> void:
	# A ripple of notices down the line (formation order, 0.25 s apart) instead of one unison take (r1 fun).
	for g in squad:
		if is_instance_valid(g) and g != self and (g as EnemyBase).state == "patrol":
			var gg := g as GingerbreadGrenadier
			gg._alert_delay = 0.25 * float(maxi(1, gg.formation_index))


func is_leader() -> bool:
	if sergeant:
		return true
	for g in squad:
		if is_instance_valid(g) and (g as GingerbreadGrenadier).sergeant and not (g as EnemyBase).is_defeated:
			return false
	var lowest := formation_index
	for g in squad:
		if is_instance_valid(g) and not (g as EnemyBase).is_defeated:
			lowest = mini(lowest, (g as GingerbreadGrenadier).formation_index)
	return formation_index == lowest


func _alive_squad() -> Array:
	var out: Array = []
	for g in squad:
		if is_instance_valid(g) and not (g as EnemyBase).is_defeated:
			out.append(g)
	if out.is_empty():
		out.append(self)
	return out


func _ai(delta: float) -> void:
	_sweep_cd = maxf(0.0, _sweep_cd - delta)
	if not _hints_done:
		_hints_done = true
		# W3 does not pass `variant` yet (requested); its data marks tier A grenadiers as LOBBERs by id.
		if variant == "" and String(name).begins_with("grenadier_tierA"):
			_become_lobber()
	if variant == "lobber" and state != "patrol" and state != "return":
		_lobber_ai(delta)
		return
	match state:
		"patrol":
			patrol_step(delta)
			if formation_index == 0:
				_hup_t -= delta
				if _hup_t < 0.0:
					_hup_t = 2.4
					say("Left! Right! Left!" if sergeant else "Hup! Hup!", Color(1, 0.95, 0.85), 52)
					EnemyKit.sfx(self, "gingerbread_march", global_position)
			if _alert_delay >= 0.0:
				_alert_delay -= delta
				if _alert_delay < 0.0:
					notice_player("!", "")
					if is_leader():
						say("Squad, CHARGE!" if sergeant else "Halt!", Color(1, 0.9, 0.8), 70)
					else:
						say(["Aye!", "Sir!", "Hup!"][formation_index % 3], Color(1, 0.9, 0.8), 48)
				return
			if sees_player():
				notice_player("!", "gingerbread_halt")
				if is_leader():
					say("Squad, CHARGE!" if sergeant else "Halt!", Color(1, 0.9, 0.8), 70)
				else:
					say("Intruder!", Color(1, 0.9, 0.8), 56)
				alert_squad()
		"notice":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			face_toward(player_pos(), delta)
			if state_time > 0.6:
				set_state("advance")
		"advance":
			if player == null or dist_to_player() > lose_radius:
				set_state("return")
				return
			face_toward(player_pos(), delta)
			# Line-abreast slots facing Mak (-1.4 / 0 / +1.4 m), wider spacing (1.6 m, weight 4): the squad no longer
			# folds into one body with fanned lances (r1 animation and fun).
			var members := _alive_squad()
			var idx := maxi(0, members.find(self))
			var n := members.size()
			var centre := Vector3.ZERO
			for g in members:
				centre += (g as Node3D).global_position
			centre /= float(n)
			var to_p := player_pos() - centre
			to_p.y = 0
			to_p = to_p.normalized() if to_p.length() > 0.01 else forward()
			var perp := Vector3(-to_p.z, 0, to_p.x)
			var slot := player_pos() - to_p * 2.3 + perp * ((float(idx) - float(n - 1) * 0.5) * 1.4)
			var want := slot - global_position
			want.y = 0
			var spacing := Vector3.ZERO
			for g in members:
				if g != self:
					var d := global_position - (g as Node3D).global_position
					d.y = 0
					if d.length() < 1.6 and d.length() > 0.01:
						spacing += d.normalized() * (1.6 - d.length())
			var fd := flat_dist_to_player()
			var move := want.normalized() * clampf(want.length(), 0.0, 1.0) + spacing * 4.0
			steer(move, 1.8 if want.length() > 0.6 else 1.0, delta)
			# Staggered lunges in formation order, through the shared attack tokens (no unison thrusts).
			var can_go := state_time > 0.5 + float(idx) * 0.2
			if can_go and sergeant and _sweep_cd <= 0.0 and fd < 3.2 and request_attack():
				set_state("sweep")
			elif can_go and fd < 2.7 and forward().dot(flat_dir_to(player_pos())) > 0.8 and request_attack():
				set_state("windup")
		"windup":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			face_toward(player_pos(), delta, 2.0)
			if state_time > windup_len:
				set_state("attack")
		"attack":
			var f := forward()
			var spd := 6.5 if state_time < 0.3 else 0.0
			# Abort the lunge into a squadmate or off a ledge.
			for g in squad:
				if is_instance_valid(g) and g != self and not (g as EnemyBase).is_defeated:
					var d := (g as Node3D).global_position - global_position
					d.y = 0
					if d.length() < 0.9 and d.normalized().dot(f) > 0.5:
						spd = 0.0
			if spd > 0.0 and drop_ahead(f, 1.0):
				spd = 0.0
			velocity.x = f.x * spd
			velocity.z = f.z * spd
			if state_time > 0.45:
				set_state("recover")
		"sweep":
			_sweep_ai(delta)
		"tripped":
			steer(Vector3.ZERO, 0.0, delta, 30.0)
			if state_time > 2.5:
				set_state("recover")
		"recover":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			if state_time > (1.1 if prev_state == "sweep" else 0.8):
				set_state("advance")
		"return":
			var d := home - global_position
			d.y = 0
			if d.length() < 0.3:
				set_state("patrol")
			else:
				steer(d, move_speed, delta)
				face_toward(home, delta)
			if sees_player():
				set_state("advance")


## Sergeant Snap's signature beat (W3 data, phase 2): plume shake, "Hup-hup!" and a red-orange disc for 1.0 s, then a
## full spin with the lance held at chest height (0.6-1.4 m): a jump is caught, but a dive or belly slide under it
## reaches his boots and trips him face-first for 2.5 s (stompable). He catches his breath for 1.2 s after a spin.
func _sweep_ai(delta: float) -> void:
	steer(Vector3.ZERO, 0.0, delta, 30.0)
	const TELL := 1.0
	const SPIN := 0.6
	const REACH := 2.6
	if state_time < TELL:
		face_toward(player_pos(), delta, 3.0)
		if _ring == null:
			_ring = EnemyKit.ground_disc(get_parent(), global_position, REACH, Color(1, 0.35, 0.15, 0.32))
			flash(Color(1.0, 0.5, 0.1), TELL, 0.95, true)
			say("Hup-hup!", Color(1, 0.85, 0.7), 70)
			moment_sfx("enemy_windup", "lance_ready")
			juice("enemy_windup", {}, global_position + Vector3(0, head_height + 0.1, 0))
			_sweep_hit = false
		return
	if state_time < TELL + SPIN:
		if not has_meta("sweep_go"):
			set_meta("sweep_go", true)
			moment_sfx("enemy_attack", "lance_thrust")
			juice("enemy_attack", {"direction": forward()}, global_position + Vector3(0, head_height * 0.5, 0))
			EnemyKit.ground_ring(get_parent(), global_position, REACH, Color(1, 0.8, 0.5, 0.8), SPIN)
		rotation.y += TAU / SPIN * delta
		if not _sweep_hit and player != null:
			var d := player.global_position - global_position
			var flat := Vector2(d.x, d.z).length()
			var st := String(player.call("get_state_name")) if player.has_method("get_state_name") else ""
			var low := st == "dive" or st == "belly_slide" or st == "slope_slide"
			if low and flat < 1.1 and d.y < 0.5:
				# Under the lance and into his boots: he trips.
				_sweep_hit = true
				remove_meta("sweep_go")
				_sweep_cd = 5.0
				set_state("tripped")
				return
			# The lance disc sits 0.6-1.4 m up: it catches anyone whose body overlaps that band (standing or jumping).
			if not low and flat < REACH + 0.2 and d.y < 1.4 * visual.scale.y and d.y + 1.25 > 0.6:
				_sweep_hit = true
				heavy_hit(player, global_position)
		return
	remove_meta("sweep_go")
	_sweep_cd = 5.0
	set_state("recover")


func _on_enter_state(s: String) -> void:
	if s == "windup":
		moment_sfx("enemy_windup", "lance_ready")
		if _tip != null:
			_tip.material_override = EnemyKit.glow_mat(Color(1, 0.5, 0.4), 2.5)
		for mi in _lance_mat:
			if is_instance_valid(mi):
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(1.0, 0.55, 0.3, 0.55)
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mi.material_overlay = m
	else:
		if _tip != null:
			_tip.material_override = EnemyKit.mat(ICING)
		for mi in _lance_mat:
			if is_instance_valid(mi):
				mi.material_overlay = null
	if s == "attack":
		# One voice per squad: only the leader shouts the line; the others grunt a short, different word.
		if is_leader():
			say("Have at thee!", Color(1, 0.85, 0.75), 52)
		elif _rng.randf() < 0.5:
			say(["Hup!", "Hah!", "Aye!"][formation_index % 3], Color(1, 0.9, 0.8), 44)
		moment_sfx("enemy_attack", "lance_thrust")
	if s == "recover" and prev_state == "attack":
		_wobble = 1.0
	if s != "sweep" and _ring != null:
		EnemyKit.fade_free(_ring)
		_ring = null
	if s == "tripped":
		say("Oof! My busby!", Color(1, 0.9, 0.8), 64)
		kick_squash(0.6)
		EnemyKit.fx(get_parent(), "DustPuff", global_position + forward() * 0.8, 0.8)
		stunned(true)
	elif prev_state == "tripped":
		stunned(false)


var _clangs := 0


func _resolve_hit(kind: String, from_position: Vector3) -> String:
	if kind == "stomp" or kind == "slam" or variant == "lobber":
		return "damage"
	# Finish pass (encounter r1 major): no lance block while he recovers, is tripped or is already hurt.
	if state == "recover" or state == "tripped" or state == "hurt" or state == "dizzy" or state == "stunned":
		return "damage"
	if forward().dot(flat_dir_to(from_position)) > 0.35:
		# Every third clang in a row says how to beat him (naive punches made a 42-clang loop with no hint).
		_clangs += 1
		if _clangs % 3 == 0:
			_block_text_once = "Stomp him, or go round!"
		return "block"
	_clangs = 0
	return "damage"


func _become_lobber() -> void:
	variant = "lobber"
	if _lance != null and is_instance_valid(_lance):
		_lance.queue_free()
		_lance = null
		_lance_mat.clear()


## LOBBER: keeps 5-9 m from Mak, and every 2.5 s winds up (0.5 s, arm back, rim glow) and lobs a red gobstopper on a
## 1.0 s arc; a red ring marks the landing spot for the whole flight. No lance, so punches and stomps land freely.
func _lobber_ai(delta: float) -> void:
	if player == null or dist_to_player() > lose_radius:
		set_state("return")
		return
	face_toward(player_pos(), delta, 5.0)
	var fd := flat_dist_to_player()
	match state:
		"windup":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			if state_time > 0.5:
				_lob()
				set_state("recover")
		"recover":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			if state_time > 0.6:
				set_state("advance")
		"hurt":
			pass
		_:
			var to_p := flat_dir_to(player_pos())
			var want := Vector3.ZERO
			if fd > 9.0:
				want = to_p
			elif fd < 5.0:
				want = -to_p
			if drop_ahead(want, 1.0):
				want = Vector3.ZERO
			steer(want, move_speed, delta)
			if state != "advance":
				set_state("advance")
			_lob_t -= delta
			if _lob_t <= 0.0 and fd < 12.0 and sees_player(12.0) and request_attack("volley"):
				_lob_t = 2.5
				set_state("windup")


func _lob() -> void:
	if player == null:
		return
	var from := global_position + Vector3(0, head_height * 0.85, 0) + forward() * 0.3
	var target := player_pos()
	var fy := floor_y_at(target, 1.0, 8.0)
	if not is_nan(fy):
		target.y = fy
	var pea := PeaProjectile.new()
	get_parent().add_child(pea)
	pea.global_position = from
	pea.vel = PeaProjectile.flight_velocity(from, target, 1.0)
	pea.marker = EnemyKit.ground_disc(get_parent(), target, 0.6, Color(0.95, 0.15, 0.15, 0.5))
	for c in pea.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = EnemyKit.mat(Color(0.9, 0.12, 0.2), 0.15, 0.5)
	juice("enemy_projectile_fire", {"kind": "gobstopper", "direction": (target - from).normalized()}, from)
	moment_sfx("enemy_projectile_fire", "pea_pop", 0.7)
	kick_squash(-0.3)
	say(["Catch!", "Sweets!", "Have one!"][_rng.randi() % 3], Color(1, 0.85, 0.75), 48)


func _contact_active() -> bool:
	# Marching flanks are solid but harmless; only the lowered-lance lunge hurts (r1 fun).
	return state == "attack" or windup_hot()


## Grip on the hand bone, shaft along the body-space direction the state asks for (eased; thrusts snap).
func _after_pose(delta: float) -> void:
	if _lance == null or not is_instance_valid(_lance) or _sk == null or _hand_bone < 0 or is_defeated:
		return
	var k := 1.0 - exp(-_lance_rate * delta)
	_lance_dir = _lance_dir.lerp(_lance_dir_want.normalized(), k).normalized()
	_lance_slide = lerpf(_lance_slide, _lance_slide_want, k)
	var hand_world := _sk.global_transform * _sk.get_bone_global_pose(_hand_bone).origin
	var hand_rig := rig.global_transform.affine_inverse() * hand_world
	# The lance rides the rig, which pitches with `lean`: a level aim tilted 13 degrees up in the wind-up and dipped into
	# the turf on the thrust (impl3 side sheet). Near-horizontal aims are pre-tilted by the lean so they stay level.
	var y := _lance_dir
	if absf(y.y) < 0.6:
		y = (y + Vector3(0, lean * 0.95 * sqrt(maxf(0.0, 1.0 - y.y * y.y)), 0)).normalized()
	var xr := Vector3(1, 0, 0)
	if absf(y.dot(xr)) > 0.95:
		xr = Vector3(0, 0, 1)
	var x := (xr - y * y.dot(xr)).normalized()
	var z := x.cross(y).normalized()
	_lance.transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * _lance_sc), hand_rig + y * _lance_slide)


## Snap v3 rests with raised arms: lower every arm pose by the same amount so the grunt poses carry over.
func pose(part: String, euler: Vector3) -> void:
	super.pose(part, _drop_arm(part, euler))


func pose_snap(part: String, euler: Vector3, rate: float = 45.0) -> void:
	super.pose_snap(part, _drop_arm(part, euler), rate)


func _drop_arm(part: String, euler: Vector3) -> Vector3:
	if _arm_drop <= 0.0:
		return euler
	if part == "arm_l":
		return euler + Vector3(0, 0, _arm_drop)
	if part == "arm_r":
		return euler - Vector3(0, 0, _arm_drop)
	return euler


func _lance_aim(dir: Vector3, slide: float = 0.0, rate: float = 12.0) -> void:
	_lance_dir_want = dir
	_lance_slide_want = slide
	_lance_rate = rate


func _defeat_juice_params(kind: String) -> Dictionary:
	# The crumbs must wait for the wobble (r1 animation): no table debris now; the spark and crumbs come from the gag.
	return {"kind": kind, "no_vfx": true}


func _contact_yields_to_attack() -> bool:
	var p := player_pos()
	return p == Vector3.INF or forward().dot(flat_dir_to(p)) < 0.35


func _animate(delta: float) -> void:
	var hv := walk_cycle(delta, 1.4)
	var t := _anim_t
	var march := state != "windup" and state != "attack" and state != "sweep" and state != "tripped"
	# LEGS pass: the march comes from the shared distance-driven stride (a crisp knee lift, a bob per footfall, the
	# free arm swinging against the legs); it used a fixed-length stride whose swing shrank with speed (skating feet).
	var prev_gait := gait_phase
	bob = gait_update(delta, march, 1.0, 0.06, 0.75)
	var m := gait_w
	var step := sin(gait_phase)
	lean = 0.0
	lunge = 0.0
	tilt = step * 0.05 * m
	spin = 0.0
	_wobble = move_toward(_wobble, 0.0, delta * 1.6)
	_tick_age += delta
	# Stiff toy-soldier march. The rig rests in an A-pose, so arms are lowered first (Z) and then swing (X); an X turn
	# on the raised arm only twisted it (r1 animation: the lance dipped into the turf). The lance is aimed separately.
	pose("leg_l", Vector3.ZERO)
	pose("leg_r", Vector3.ZERO)
	pose("shin_l", Vector3.ZERO)
	pose("shin_r", Vector3.ZERO)
	pose("arm_l", Vector3(0, 0, 0.8))
	pose("arm_r", Vector3(0.25, 0, -0.75))
	pose("forearm_l", Vector3.ZERO)
	pose("forearm_r", Vector3(0.6, 0, 0))
	# Head tipped up 9 degrees at rest so the face shows under the busby from the gameplay camera (r1 visual).
	var head := Vector3(0.16, 0, 0)
	gait_legs(1.15)
	pose_cycle("arm_l", Vector3(-step * gait_amp * 0.9 * m, 0, 0))
	match state:
		"patrol", "return":
			# Slope arms: the lance leans back on the shoulder.
			_lance_aim(Vector3(0, 1, 0.22), 0.0, 10.0)
			pose_cycle("head", Vector3(0, sin(t * 0.8) * 0.12, step * 0.05 * m))
			if m < 0.2:
				_idle_ticks(delta, t)
		"notice":
			# "Halt!": heels click, chin up, lance presented upright.
			head = Vector3(0.26, 0, 0)
			pose_snap("head", head, 30.0)
			pose("arm_l", Vector3(0, 0, 1.0))
			pose("leg_l", Vector3(0, 0, -0.06))
			pose("leg_r", Vector3(0, 0, 0.06))
			_lance_aim(Vector3(0, 1, -0.05), 0.12, 30.0)
		"advance":
			# At the ready: lance lowered toward Mak, chin up so the face reads.
			lean = 0.06
			pose("arm_r", Vector3(0.45, 0, -0.7))
			pose("forearm_r", Vector3(0.4, 0, 0))
			head = Vector3(0.18, 0, 0)
			_lance_aim(Vector3(0, 0.45, -1.0), 0.0, 10.0)
		"windup":
			# Cock back: weight on the rear foot, body leaning back about 13 degrees, the lance level at Mak and drawn
			# back past the hip, the spike glowing; a tremble builds as it is about to go.
			var u := clampf(state_time / windup_len, 0.0, 1.0)
			var e := 1.0 - (1.0 - u) * (1.0 - u)
			lean = -0.23 * e
			lunge = -0.08 * e
			bob = -0.03 * e
			pose("arm_r", Vector3(-0.75 * e, 0, -0.75))
			pose("forearm_r", Vector3(0.35, 0, 0))
			pose("arm_l", Vector3(0.35 * e, 0, 0.55))
			head = Vector3(0.1 + 0.15 * e, 0, 0)
			pose("leg_l", Vector3(0.3 * e, 0, 0))
			pose("leg_r", Vector3(-0.35 * e, 0, 0))
			pose("shin_r", Vector3(-0.25 * e, 0, 0))
			tilt = sin(t * 40.0) * 0.02 * u
			_lance_aim(Vector3(0, 0.1, -1.0), -0.32 * e, 16.0)
		"attack":
			# Thrust: the root lunges 0.28 m on the first frames with the front foot planted, the lance shoots forward
			# along its line with a one-frame overshoot stretch, then holds (was a rigid plank tilt, r1 animation).
			var a := clampf(state_time / 0.08, 0.0, 1.0)
			lean = 0.18
			lunge = 0.28 * a
			bob = -0.06 * a
			pose_snap("arm_r", Vector3(1.0, 0, -0.6), 50.0)
			pose_snap("forearm_r", Vector3(0.1, 0, 0), 50.0)
			pose_snap("arm_l", Vector3(-0.6, 0, 0.7), 40.0)
			pose_snap("leg_l", Vector3(0.85, 0, 0), 45.0)
			pose_snap("shin_l", Vector3(-0.35, 0, 0), 45.0)
			pose_snap("leg_r", Vector3(-0.7, 0, 0), 45.0)
			head = Vector3(0.12, 0, 0)
			_lance_aim(Vector3(0, 0.02, -1.0), 0.4, 50.0)
			if state_time < 0.05:
				scale_mult = Vector3(0.92, 0.95, 1.18)
			else:
				scale_mult = scale_mult.lerp(Vector3.ONE, 1.0 - exp(-18.0 * delta))
		"sweep":
			var tell := state_time < 1.0
			if tell:
				# Lance raised high behind the head, plume up, rear foot planted.
				lean = -0.12
				pose("arm_r", Vector3(-0.2, 0, 0.3))
				pose("forearm_r", Vector3(0.6, 0, 0))
				pose("arm_l", Vector3(0.3, 0, 0.5))
				pose("leg_l", Vector3(-0.3, 0, 0.15))
				pose("leg_r", Vector3(0.3, 0, -0.15))
				pose_cycle("head", Vector3(0, 0, sin(t * 30.0) * 0.03 * state_time))
				_lance_aim(Vector3(0.35, 1.0, 0.55), 0.1, 10.0)
			else:
				lean = 0.15
				pose_snap("arm_r", Vector3(0.8, 0, -0.2), 45.0)
				pose_snap("forearm_r", Vector3(0.1, 0, 0), 45.0)
				pose("arm_l", Vector3(0, 0, 1.0))
				_lance_aim(Vector3(0.8, 0.05, -0.6), 0.25, 40.0)
		"tripped":
			# Face-first on the ground, boots in the air, busby askew, lance flat beside him.
			lean = minf(1.45, state_time * 9.0)
			bob = -0.35 * minf(1.0, state_time * 6.0)
			pose("arm_l", Vector3(-0.9, 0, 0.3))
			pose("arm_r", Vector3(-0.9, 0, -0.3))
			pose("leg_l", Vector3(0.5, 0, 0))
			pose("leg_r", Vector3(0.3, 0, 0))
			pose_cycle("leg_l", Vector3(sin(t * 9.0) * 0.25, 0, 0))
			pose_cycle("leg_r", Vector3(-sin(t * 9.0) * 0.25, 0, 0))
			head = Vector3(0.3, 0.2, 0.25)
			_lance_aim(Vector3(0.5, -0.05, -0.85), 0.0, 8.0)
		"recover":
			pose("arm_r", Vector3(0.3, 0, -0.7))
			head = Vector3(0.2, 0, 0)
			pose_cycle("head", Vector3(0, sin(t * 7.0) * 0.15, 0))
			tilt = sin(t * 8.0) * 0.05
			# Lance held up and out to the side (it crossed the face from the front camera, impl3 sheet).
			_lance_aim(Vector3(0.3, 1.0, -0.35), 0.0, 8.0)
			if prev_state == "sweep" or prev_state == "tripped":
				# Dizzy from the spin: the punish window.
				tilt = sin(t * 6.0) * 0.14
				pose_cycle("head", Vector3(sin(t * 4.0) * 0.15, sin(t * 3.0) * 0.3, 0))
				_lance_aim(Vector3(0.3, 0.6, 0.6), 0.0, 6.0)
		"hurt":
			head = Vector3(0.35, 0, 0)
			_lance_aim(Vector3(0.2, 0.9, 0.5), 0.0, 20.0)
		_:
			pose_cycle("head", Vector3(0, sin(t * 0.8) * 0.1, 0))
			_lance_aim(Vector3(0, 1, 0.1), 0.0, 10.0)
	pose("head", head)
	if state != "attack":
		scale_mult = scale_mult.lerp(Vector3.ONE, 1.0 - exp(-14.0 * delta))
	# Lance spring after a thrust: the shaft wobbles and settles.
	if _wobble > 0.0:
		pose_cycle("forearm_r", Vector3(sin(t * 34.0) * 0.25 * _wobble, 0, 0))
		_lance_dir_want += Vector3(sin(t * 34.0) * 0.12 * _wobble, sin(t * 30.0) * 0.1 * _wobble, 0)
	# Biscuit footfalls in step (the squad leader keeps the time with "Hup!").
	if hv > 0.6 and is_on_floor() and gait_footfall(prev_gait):
		EnemyKit.sfx(self, "enemy_step", global_position, 1.1, -5.0)


## Toy-soldier ticks at rest, desynced per squad member: a lance shoulder-tap every 2.5 s, a heel click with a little
## hop, eyes-front head snaps and a slight sway on the spot (r1 animation: the idle was nearly frozen).
func _idle_ticks(delta: float, t: float) -> void:
	tilt += sin(t * 1.3 + float(formation_index) * 1.7) * 0.025
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 2.5 + 0.35 * float(formation_index % 3) + _rng.randf_range(-0.2, 0.2)
		_tick_kind = (_tick_kind + 1 + (formation_index % 2)) % 3
		_tick_age = 0.0
		if _tick_kind == 1:
			EnemyKit.sfx(self, "enemy_step", global_position, 1.5, -10.0)
	if _tick_age > 0.45:
		return
	var e := sin(clampf(_tick_age / 0.45, 0.0, 1.0) * PI)
	match _tick_kind:
		0:
			# Lance shoulder-tap: lift, tap, re-plant.
			_lance_aim(Vector3(0, 1, -0.05), 0.1 * e, 30.0)
			pose_cycle("forearm_r", Vector3(0.35 * e, 0, 0))
		1:
			# Heel click: feet snap together, a 4 cm hop.
			bob += 0.04 * e
			pose_cycle("leg_l", Vector3(0, 0, -0.12 * e))
			pose_cycle("leg_r", Vector3(0, 0, 0.12 * e))
		2:
			# Eyes front! Head snaps left then right.
			pose_cycle("head", Vector3(0, sin(_tick_age / 0.45 * TAU) * 0.35, 0))


func _defeat_gag(_kind: String, _from_position: Vector3) -> float:
	say_side("Oh crumbs!", Color(1, 0.9, 0.75), 80)
	moment_sfx("enemy_defeat", "gingerbread_crumble")
	set_meta("crumb_stage", 0)
	return 1.35


## Crumble (1.35 s): a 0.45 s stiff wobble (3 swings of 8 degrees, arms out), the knees give and chunks break off the
## hands and feet first, the busby head nods down, then the body collapses into a crumb heap. The lance falls flat
## on the ground, bounces once with a clatter and leaves with a sparkle and a small poof (r1 animation).
func _defeat_process(delta: float) -> void:
	var st := state_time
	var stage: int = get_meta("crumb_stage", 0)
	if stage == 0:
		set_meta("crumb_stage", 1)
		_drop_lance()
	if st < 0.45:
		var w := sin(st / 0.45 * TAU * 1.5) * 0.14 * (1.0 - st / 0.45 * 0.4)
		tilt = w
		lean = 0.0
		pose_snap("arm_l", Vector3(0, 0, -0.1), 30.0)
		pose_snap("arm_r", Vector3(0, 0, 0.1), 30.0)
		pose("head", Vector3(0.3, 0, -w))
		return
	if st < 0.8:
		var u := (st - 0.45) / 0.35
		if stage < 2:
			set_meta("crumb_stage", 2)
			EnemyKit.sfx(self, "gingerbread_crumble", global_position, 1.2, -4.0)
			for side: float in [-1.0, 1.0]:
				var hand: Vector3 = global_position + global_transform.basis.x * side * 0.5 * visual.scale.x + Vector3(0, 0.6 * visual.scale.y, 0)
				var foot: Vector3 = global_position + global_transform.basis.x * side * 0.18 + Vector3(0, 0.1, 0)
				EnemyKit.burst(get_parent(), hand, "crumbs", [DOUGH, DOUGH_DARK], 8, 2.2)
				EnemyKit.burst(get_parent(), foot, "crumbs", [DOUGH, ICING], 6, 1.8)
		# Knees buckle: he sinks, legs splay, arms droop, head nods.
		bob = -0.18 * u * visual.scale.y
		tilt = sin(_anim_t * 18.0) * 0.04
		pose("leg_l", Vector3(0.5 * u, 0, -0.35 * u))
		pose("leg_r", Vector3(0.5 * u, 0, 0.35 * u))
		pose("shin_l", Vector3(-0.8 * u, 0, 0))
		pose("shin_r", Vector3(-0.8 * u, 0, 0))
		pose("arm_l", Vector3(0, 0, 0.9))
		pose("arm_r", Vector3(0, 0, -0.9))
		pose("head", Vector3(-0.45 * u, 0, 0.2 * u))
		return
	# Collapse into a heap.
	if stage < 3:
		set_meta("crumb_stage", 3)
		EnemyKit.sfx(self, "gingerbread_crumble", global_position, 0.8)
		EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.45, 0), "crumbs", [DOUGH, DOUGH_DARK, DOUGH, DOUGH_DARK, ICING, CANDY_RED], 40, 3.6)
		EnemyKit.fx(get_parent(), "DustPuff", global_position, 0.6)
	rig.scale = rig.scale.lerp(Vector3(1.4, 0.06, 1.4), 1.0 - exp(-9.0 * delta))
	bob = lerpf(bob, 0.0, 1.0 - exp(-8.0 * delta))
	tilt = sin(_anim_t * 25.0) * 0.05


func _drop_lance() -> void:
	if _lance == null or not is_instance_valid(_lance):
		return
	var gt := _lance.global_transform
	var lp := _lance
	_lance = null
	lp.get_parent().remove_child(lp)
	get_parent().add_child(lp)
	lp.global_transform = gt
	# Fall flat (shaft horizontal along the ground), one small bounce with a clatter, rest, then a sparkle and a poof.
	var gy := global_position.y
	var fy := floor_y_at(gt.origin, 1.0, 4.0)
	if not is_nan(fy):
		gy = fy
	var along := gt.basis.y
	along.y = 0
	along = along.normalized() if along.length() > 0.05 else forward()
	var x := Vector3.UP.cross(along).normalized()
	var flat := Basis(x, along, x.cross(along).normalized()).scaled(gt.basis.get_scale())
	var rest := gt.origin
	rest.y = gy + 0.05
	var tw := lp.create_tween()
	tw.tween_property(lp, "global_transform", Transform3D(flat, rest), 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		EnemyKit.sfx(lp, "enemy_block", rest, 1.35, -8.0))
	tw.tween_property(lp, "global_position:y", rest.y + 0.12, 0.09).set_ease(Tween.EASE_OUT)
	tw.tween_property(lp, "global_position:y", rest.y, 0.1).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.3)
	tw.tween_callback(func() -> void:
		if lp.is_inside_tree():
			var mid := lp.global_position + lp.global_transform.basis.y * 0.35
			EnemyKit.burst(lp.get_parent(), mid, "stars", [Color(1, 0.95, 0.6), Color(1, 1, 1)], 10, 1.6)
			EnemyKit.poof(lp.get_parent(), mid, 0.4))
	tw.tween_property(lp, "scale", Vector3.ONE * 0.02, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_callback(lp.queue_free)


func _defeat_burst() -> void:
	# The heap pops with crumbs in the cookie palette only (dough, dark dough, icing, candy red).
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.25, 0), "crumbs", [DOUGH, DOUGH_DARK, DOUGH, DOUGH_DARK, ICING, CANDY_RED], 30, 4.0)
