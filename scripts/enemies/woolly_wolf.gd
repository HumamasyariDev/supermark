class_name WoollyWolf
extends EnemyBase
## Woolly Wolf: a wolf cub badly disguised as a sheep. Grazes and "baa"-s; when it spots Mak it
## rips off the costume, paws the ground and charges in a committed line, then skids helplessly.
## Counter: sidestep the charge, then stomp or punch during the skid. Defeat: spins away in its underwear.

const FUR := Color(0.47, 0.52, 0.64)
const FUR_LIGHT := Color(0.78, 0.8, 0.86)
const WOOL := Color(0.98, 0.97, 0.92)
const SHORTS := Color(0.86, 0.16, 0.2)

@export var charge_speed: float = 9.5
@export var charge_time: float = 1.25

var disguised: bool = true
var costume: Array[Node3D] = []
var charge_dir: Vector3 = Vector3.FORWARD
var _baa_t: float = 2.0
var _wander_target: Vector3 = Vector3.ZERO
var _dust_t: float = 0.0
var _strip: Node3D
var _stars: Node3D
var _step_phase: float = 0.0
var _glance_t: float = 3.0
var _reveal_t: float = -10.0
var _prowl_side: float = 1.0
var _snarl_t: float = 1.5
static var _wool_cache: Dictionary = {}
var _gallop: float = 0.0
var _grr_done: bool = true
const FLEECE_TEX := "res://scenes/enemies/tex/woolly_wolf_fleece_white.webp"


## Plain defaults live in _init (runs at instantiate), so values a world builder sets before add_child survive
## (r1 blocker: _setup in _ready used to overwrite notice_radius, move_speed, acorns... in all three worlds).
func _init() -> void:
	enemy_id = "woolly_wolf"
	# Springy cub: a high, quick startle hop.
	notice_hop = 0.32
	notice_stretch = 0.16
	notice_len = 0.36
	display_name = "Woolly Wolf"
	body_radius = 0.38
	body_height = 1.05
	head_height = 1.15
	move_speed = 1.0
	notice_radius = 7.5
	lose_radius = 15.0
	acorns_on_defeat = 2
	windup_len = 0.85
	outline_width = 1.0


func _setup() -> void:
	_wander_target = home
	_baa_t = _rng.randf_range(0.5, 2.5)
	_glance_t = _rng.randf_range(2.0, 4.0)


func _on_mesh_ready(inst: Node) -> void:
	# Disguise colour: only the fleece texels are repainted to the W1 sheep's white (#F7F5FF) in a recoloured copy of
	# the albedo texture (tools: Docs/progress/enemies_v2 fleece recolour); the slate face, ears and inner-ear pink keep
	# their colours. The old whole-mesh lilac multiply turned the face purple (r1 visual M).
	if mesh_path == "" or mesh_path.ends_with("woolly_wolf.glb"):
		var tex: Texture2D = load(FLEECE_TEX) as Texture2D if ResourceLoader.exists(FLEECE_TEX) else null
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for si in m.mesh.get_surface_count():
				var src := m.get_active_material(si) as StandardMaterial3D
				if src != null and tex != null:
					var c: StandardMaterial3D = _wool_cache.get(src.get_instance_id())
					if c == null:
						c = src.duplicate() as StandardMaterial3D
						c.albedo_texture = tex
						c.albedo_color = Color(1, 1, 1)
						_wool_cache[src.get_instance_id()] = c
					m.set_surface_override_material(si, c)


func _build_placeholder(root: Node3D) -> void:
	var body := EnemyKit.pivot(root, "body", Vector3(0, 0.42, 0))
	EnemyKit.capsule(body, 0.3, 0.72, FUR, Vector3(0, 0.12, 0), Vector3(-8, 0, 0))
	EnemyKit.ball(body, 0.24, FUR_LIGHT, Vector3(0, 0.08, -0.12), Vector3(1, 1.2, 0.8))
	# Red polka-dot shorts (the defeat gag reveals them in full).
	EnemyKit.cylinder(body, 0.31, 0.33, 0.2, SHORTS, Vector3(0, -0.12, 0))
	for i in 6:
		var a := TAU * float(i) / 6.0
		EnemyKit.ball(body, 0.035, Color(1, 1, 1), Vector3(cos(a) * 0.325, -0.1 + 0.04 * float(i % 2), sin(a) * 0.325))
	for side in [-1.0, 1.0]:
		var leg := EnemyKit.pivot(root, "leg_l" if side < 0 else "leg_r", Vector3(0.14 * side, 0.3, 0))
		EnemyKit.capsule(leg, 0.1, 0.34, FUR, Vector3(0, -0.13, 0))
		EnemyKit.ball(leg, 0.12, Color(0.3, 0.3, 0.38), Vector3(0, -0.27, -0.05), Vector3(1, 0.7, 1.3))
		var arm := EnemyKit.pivot(body, "arm_l" if side < 0 else "arm_r", Vector3(0.3 * side, 0.3, -0.04))
		EnemyKit.capsule(arm, 0.08, 0.36, FUR, Vector3(0.03 * side, -0.15, 0), Vector3(0, 0, 10 * side))
		EnemyKit.ball(arm, 0.1, FUR_LIGHT, Vector3(0.06 * side, -0.32, 0))
	var head := EnemyKit.pivot(body, "head", Vector3(0, 0.58, -0.04))
	head.set_meta("skin", FUR)
	EnemyKit.ball(head, 0.3, FUR, Vector3.ZERO, Vector3(1.05, 0.95, 1.0))
	EnemyKit.capsule(head, 0.13, 0.36, FUR_LIGHT, Vector3(0, -0.07, -0.28), Vector3(90, 0, 0), Vector3(1.15, 1, 0.85))
	EnemyKit.ball(head, 0.07, Color(0.08, 0.06, 0.08), Vector3(0, -0.02, -0.46))
	for side in [-1.0, 1.0]:
		EnemyKit.cone(head, 0.1, 0.26, FUR, Vector3(0.17 * side, 0.27, 0.02), Vector3(-10, 0, -18 * side))
		EnemyKit.cone(head, 0.055, 0.16, Color(0.95, 0.65, 0.7), Vector3(0.17 * side, 0.26, -0.02), Vector3(-10, 0, -18 * side))
	EnemyKit.face(head, Vector3(0, 0.08, -0.24), 0.11, 0.085, Color(0.98, 0.78, 0.15), "determined")
	EnemyKit.mouth(head, Vector3(0, -0.16, -0.33), 0.2, "toothy")
	var tail := EnemyKit.pivot(root, "tail", Vector3(0, 0.45, 0.3))
	EnemyKit.capsule(tail, 0.1, 0.42, FUR, Vector3(0, 0.12, 0.12), Vector3(-50, 0, 0))
	EnemyKit.ball(tail, 0.1, FUR_LIGHT, Vector3(0, 0.27, 0.27))
	# The terrible sheep costume.
	var wool_spots := [Vector3(0, 0.25, 0.08), Vector3(-0.2, 0.15, 0.0), Vector3(0.2, 0.15, 0.0), Vector3(0, 0.12, 0.2),
		Vector3(-0.15, 0.32, -0.08), Vector3(0.15, 0.32, -0.08), Vector3(0, 0.0, 0.18)]
	for p in wool_spots:
		costume.append(EnemyKit.ball(body, 0.2, WOOL, p, Vector3(1.1, 0.9, 1.1)))
	var cap := EnemyKit.ball(head, 0.24, WOOL, Vector3(0, 0.2, 0.04), Vector3(1.3, 0.7, 1.2))
	costume.append(cap)
	for side in [-1.0, 1.0]:
		costume.append(EnemyKit.ball(head, 0.09, Color(0.96, 0.85, 0.8), Vector3(0.3 * side, 0.12, 0.02), Vector3(1.6, 0.6, 0.9)))
	var bell := EnemyKit.ball(body, 0.07, Color(1.0, 0.78, 0.2), Vector3(0, 0.38, -0.3))
	(bell as MeshInstance3D).material_override = EnemyKit.mat(Color(1.0, 0.78, 0.2), 0.25, 0.3, 0.8)
	costume.append(bell)


func _initial_state() -> String:
	return "idle"


func _ai(delta: float) -> void:
	match state:
		"idle":
			_graze(delta)
			if sees_player():
				notice_player("!", "wolf_cub_baa" if disguised else "wolf_cub_growl")
		"notice":
			velocity.x = 0.0
			velocity.z = 0.0
			if player != null:
				face_toward(player_pos(), delta, 10.0)
			if disguised:
				var u := clampf((state_time - 0.12) / 0.26, 0.0, 1.0)
				scale_mult = Vector3.ONE * (1.0 + u * 0.16) + Vector3(sin(state_time * 70.0), 0, cos(state_time * 63.0)) * 0.04 * u
			if disguised and state_time > 0.38:
				scale_mult = Vector3.ONE
				_rip_costume()
			_grr_beat()
			# After a reveal the cub needs its ta-da and its embarrassed look before it charges.
			if state_time > 0.9 and _anim_t - _reveal_t > 0.85:
				# Attack token: a refused wolf drops into its prowl and asks again (no unison charges).
				set_state("windup" if request_attack() else "prowl")
		"prowl":
			if dist_to_player() > lose_radius:
				# Lost him: a "where did he go?" beat, then a cocky trot home (r1 animation: it froze facing away).
				set_state("search")
				return
			face_toward(player_pos(), delta)
			# Predator prowl: circle sideways around Mak at 3-5 m instead of standing still (r1 animation).
			var to_p := flat_dir_to(player_pos())
			var side := Vector3(-to_p.z, 0, to_p.x) * _prowl_side
			var fd := flat_dist_to_player()
			var want := side * 1.0 + to_p * (0.8 if fd > 5.0 else (-0.6 if fd < 3.0 else 0.0))
			if drop_ahead(want, 1.0):
				_prowl_side = -_prowl_side
				want = -want
			steer(want, 1.5, delta, 6.0)
			if fmod(state_time + 0.7, 2.6) < delta:
				_prowl_side = -_prowl_side
			_snarl_t -= delta
			if _snarl_t <= 0.0:
				_snarl_t = 1.5
				EnemyKit.sfx(self, "wolf_cub_growl", global_position, 1.15, -8.0)
			if state_time > 0.8 and fd < 8.0 and request_attack():
				set_state("windup")
		"windup":
			steer(Vector3.ZERO, 0.0, delta, 30.0)
			if state_time < 0.45:
				face_toward(player_pos(), delta, 12.0)
				charge_dir = forward()
			elif _strip == null:
				charge_dir = forward()
				# The lane covers the whole charge (9.5 m/s x 1.25 s + body), not 9.1 m of an 11.9 m run (r1 fun).
				_strip = EnemyKit.ground_strip(get_parent(), global_position + charge_dir * 0.6, charge_dir, charge_speed * charge_time + 0.9, 0.9)
				EnemyKit.sfx(self, "wolf_cub_growl", global_position)
				if _anim_t - _reveal_t > 1.0:
					say("GRRR!", Color(1, 0.55, 0.3), 70)
			_dust_t -= delta
			if _dust_t <= 0.0:
				_dust_t = 0.22
				EnemyKit.burst(get_parent(), global_position + forward() * -0.3, "dust", [Color(0.85, 0.78, 0.62, 0.5)], 4, 1.6)
			if state_time > 0.85:
				set_state("attack")
		"attack":
			velocity.x = charge_dir.x * charge_speed
			velocity.z = charge_dir.z * charge_speed
			face_dir_instant(charge_dir)
			if get_slide_collision_count() > 0 and is_on_wall():
				_bonk()
			elif state_time > charge_time:
				set_state("skid")
			elif drop_ahead(charge_dir, 1.9, 1.5):
				# Edge ahead: brake early and teeter at the lip instead of running off the map (r1 fun).
				set_state("skid")
				set_meta("teeter", true)
		"skid":
			var v := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, charge_speed / (0.5 if has_meta("teeter") else 0.9) * delta)
			velocity.x = v.x
			velocity.z = v.z
			_dust_t -= delta
			if _dust_t <= 0.0 and v.length() > 1.0:
				_dust_t = 0.07
				EnemyKit.burst(get_parent(), global_position + charge_dir * 0.3, "dust", [Color(0.9, 0.84, 0.7, 0.5)], 3, 2.2)
			if state_time > 1.0:
				if has_meta("teeter"):
					remove_meta("teeter")
				set_state("recover")
		"dizzy":
			steer(Vector3.ZERO, 0.0, delta, 30.0)
			if state_time > 1.8:
				set_state("recover")
		"recover":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			if state_time > 0.6:
				set_state("prowl")
		"search":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			if state_time > 0.9 and not has_meta("hmph"):
				set_meta("hmph", true)
				say("Hmph!", Color(1, 0.8, 0.7), 60)
				EnemyKit.sfx(self, "wolf_cub_growl", global_position, 1.35, -10.0)
			if sees_player() and dist_to_player() < lose_radius * 0.7:
				remove_meta("hmph")
				set_state("prowl")
			elif state_time > 2.2:
				remove_meta("hmph")
				set_state("home")
		"home":
			var dh := home - global_position
			dh.y = 0
			if dh.length() < 0.5:
				set_state("idle")
			else:
				steer(dh, 2.2, delta, 8.0)
				face_toward(home, delta, 6.0)
			if sees_player() and dist_to_player() < notice_radius:
				notice_player("!", "wolf_cub_growl")


func _on_ledge() -> void:
	if state == "attack":
		set_meta("teeter", true)
		set_state("skid")


func _graze(delta: float) -> void:
	_baa_t -= delta
	if _baa_t <= 0.0:
		_baa_t = _rng.randf_range(2.5, 4.5)
		if disguised:
			say("Baa~", Color(1, 1, 1), 64)
			EnemyKit.sfx(self, "wolf_cub_baa", global_position)
		else:
			# Unmasked and back home: no more baa-ing, just a sulky look-out.
			_baa_t += 2.0
			EnemyKit.sfx(self, "wolf_cub_growl", global_position, 1.3, -14.0)
	var d := _wander_target - global_position
	d.y = 0
	if d.length() < 0.3:
		if state_time > 0.0 and _rng.randf() < 0.01:
			var a := _rng.randf() * TAU
			_wander_target = home + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.5, 2.0)
		steer(Vector3.ZERO, 0.0, delta)
	else:
		steer(d, move_speed, delta, 6.0)
		face_toward(_wander_target, delta, 3.0)


func _rip_costume() -> void:
	disguised = false
	_reveal_t = _anim_t
	_swap_to_cub_mesh()
	EnemyKit.sfx(self, "costume_rip", global_position)
	# The reveal must stay visible: a short white pop on the new mesh, cream fleece tufts torn off the body surface
	# that hang in the air, a small low puff behind the feet, then a "ta-da" pose and an embarrassed look before
	# the "GRR!" (r1 animation: blue spheres and a hard one-frame swap).
	flash(Color(1, 1, 1), 0.07, 0.8)
	var puff_at := global_position + Vector3(0, 0.15, 0) - forward() * 0.35
	if EnemyKit.fx(get_parent(), "Poof", puff_at, 0.45) == null:
		EnemyKit.poof(get_parent(), puff_at, 0.45, Color(0.98, 0.97, 0.92))
	_grr_done = false
	var parent_node := get_parent()
	var fleece := [Color("#F4EFE2"), Color("#FBF8F0")]
	var right := global_transform.basis.x
	# Fluttering fleece tufts from the VFX track's wool_burst preset (sprite tufts that flip and drift, not spheres),
	# one at the hood and one at the body; the CPU sphere tufts remain only as a fallback.
	# Fewer and brighter than the first pass (26 beige tufts hid the cub's face for 0.6 s, impl3 reel): the tint lifts the
	# lit sprites back to fleece white.
	var wool_tint := Color(1.3, 1.3, 1.24)
	var a := EnemyKit.preset(parent_node, "wool_burst", global_position + Vector3(0, 1.0, 0) - forward() * 0.15, 0.7, wool_tint)
	var b := EnemyKit.preset(parent_node, "wool_burst", global_position + Vector3(0, 0.45, 0) - forward() * 0.1, 0.45, wool_tint)
	if a == null or b == null:
		for spot in [Vector3(0, 0.95, 0), Vector3(0, 0.6, 0.0), right * 0.3 + Vector3(0, 0.6, 0), -right * 0.3 + Vector3(0, 0.6, 0), Vector3(0, 0.35, 0) + forward() * 0.2]:
			EnemyKit.burst(parent_node, global_position + spot, "wool", fleece, 6, 3.4)
	if mesh_root != null and mesh_root.visible:
		# Generated mesh: the placeholder costume stays hidden; real wool tufts come from the bursts.
		for c in costume:
			if is_instance_valid(c):
				c.queue_free()
		costume.clear()
		return
	for c in costume:
		if not is_instance_valid(c):
			continue
		var gp := c.global_transform
		c.get_parent().remove_child(c)
		parent_node.add_child(c)
		c.global_transform = gp
		c.material_overlay = null
		var fly := (c.global_position - global_position)
		fly.y = 0
		fly = fly.normalized() * _rng.randf_range(1.0, 2.0) + Vector3.UP * _rng.randf_range(0.6, 1.4)
		var land := c.global_position + Vector3(fly.x, 0, fly.z) * 1.2
		land.y = global_position.y + 0.1
		var tw := c.create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "global_position:y", c.global_position.y + fly.y, 0.25).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "global_position:x", land.x, 0.6)
		tw.tween_property(c, "global_position:z", land.z, 0.6)
		tw.tween_property(c, "rotation", Vector3(_rng.randf() * 6, _rng.randf() * 6, 0), 0.6)
		tw.chain().tween_property(c, "global_position:y", land.y, 0.35).set_ease(Tween.EASE_IN)
		tw.chain().tween_interval(2.5)
		tw.chain().tween_property(c, "scale", Vector3.ONE * 0.01, 0.4)
		tw.chain().tween_callback(c.queue_free)
	costume.clear()


## With generated meshes, woolly_wolf.glb is the sheep disguise and woolly_wolf_cub.glb the cub
## underneath. Without the cub mesh the procedural placeholder (red shorts) takes over.
func _swap_to_cub_mesh() -> void:
	if mesh_root == null:
		return
	var cub := "res://assets/enemies/woolly_wolf_cub/woolly_wolf_cub.glb"
	for c in mesh_root.get_children():
		mesh_root.remove_child(c)
		c.queue_free()
	if ResourceLoader.exists(cub):
		var inst := (load(cub) as PackedScene).instantiate()
		mesh_root.add_child(inst)
		apply_toon(inst)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = _flash
		_collect_parts(mesh_root)
	else:
		mesh_root.visible = false
		placeholder.visible = true
		_collect_parts(placeholder)
	pose_cur.clear()


func _bonk() -> void:
	set_state("dizzy")
	velocity = -charge_dir * 3.0 + Vector3.UP * 3.0
	kick_squash(0.7)
	moment_sfx("enemy_stunned", "enemy_bonk")
	say("BONK!", Color(1, 0.9, 0.4), 90)
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 1.0, 0), "stars", [Color(1, 0.95, 0.4)], 10, 3.0)


func _on_enter_state(s: String) -> void:
	if s == "attack" and _strip != null:
		# The lane stays under the charge and shrinks away over its length.
		EnemyKit.fade_free(_strip, charge_time)
		_strip = null
	elif s != "windup" and _strip != null:
		EnemyKit.fade_free(_strip)
		_strip = null
	if s == "attack":
		moment_sfx("enemy_attack", "wolf_charge")
		kick_squash(-0.3)
	if s == "skid":
		EnemyKit.sfx(self, "enemy_skid", global_position)
		say("Whoa-oa!", Color(1, 1, 1), 60)
	if s != "dizzy" and prev_state == "dizzy":
		stunned(false)
	if s != "dizzy" and _stars != null:
		_stars.queue_free()
		_stars = null
	if s == "dizzy":
		stunned(true)
		if not owns("enemy_stunned"):
			_stars = _make_stars()


func _resolve_hit(kind: String, from_position: Vector3) -> String:
	# Finish pass (encounter r1 major: a running dive one-shot the wolf before it ever acted). A dive into a wolf
	# that has not attacked yet knocks him dizzy instead; the follow-up stomp or punch finishes him.
	if kind == "dive" and (state == "idle" or state == "prowl" or state == "home" or state == "search" or state == "notice" or state == "windup" or state == "skid"):
		if disguised:
			_rip_costume()
		_bonk()
		return "ignore"
	if state == "attack" and kind != "stomp" and kind != "slam":
		var to_from := flat_dir_to(from_position)
		if to_from.dot(charge_dir) > 0.2:
			# Teach "sidestep the charge" instead of silently eating the punch (r1 fun).
			_block_text_once = "Too fast!"
			return "block"
	return "damage"


func _contact_yields_to_attack() -> bool:
	return state != "attack"


func _vaultable() -> bool:
	return state == "attack"


## "GRR!" lands after the ta-da (0.07 s), the squash and a 0.25 s embarrassed look.
func _grr_beat() -> void:
	if _grr_done or _anim_t - _reveal_t < 0.42:
		return
	_grr_done = true
	say("GRR!", Color(1, 0.5, 0.3), 90)
	EnemyKit.sfx(self, "wolf_cub_growl", global_position, 1.1, -2.0)
	kick_squash(-0.5)


func _contact_active() -> bool:
	# Only the telegraphed charge hurts (last 0.25 s of the pawing wind-up, then the run); prowl and notice are solid
	# but harmless (DESIGN_V2: no damage without a telegraph, r1 fun).
	return not disguised and (state == "attack" or windup_hot())


func _after_hurt_state() -> String:
	if disguised:
		_rip_costume()
	return "recover"


func _make_stars() -> Node3D:
	var st := Node3D.new()
	add_child(st)
	st.position = Vector3(0, head_height + 0.2, 0)
	for i in 4:
		var a := TAU * float(i) / 4.0
		var b := EnemyKit.ball(st, 0.06, Color(1, 0.92, 0.3), Vector3(cos(a) * 0.32, 0, sin(a) * 0.32))
		b.material_override = EnemyKit.glow_mat(Color(1, 0.9, 0.3), 1.3)
	return st


func _animate(delta: float) -> void:
	var hv := walk_cycle(delta, 1.2)
	var t := _anim_t
	# LEGS pass: legs, knees, arm counter-swing and the stride bob come from the shared distance-driven gait.
	var prev_gait := gait_phase
	var walk_on := true
	bob = 0.0
	lean = 0.0
	tilt = 0.0
	spin = 0.0
	if state != "notice":
		scale_mult = scale_mult.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
	var head := Vector3.ZERO
	var jaw := 0.0
	var ears := 0.0
	var tail_speed := 6.0
	var tail_amp := 0.5
	var tail_base := 0.2
	var arm_l := Vector3.ZERO
	var arm_r := Vector3.ZERO
	var leg_l := Vector3.ZERO
	var leg_r := Vector3.ZERO
	var bound := false
	if _stars != null:
		_stars.rotation.y += delta * 6.0
	var body_p := Vector3.ZERO
	lunge = 0.0
	match state:
		"idle" when not disguised:
			# Unmasked and back home: a sulky look-out, sitting low, tail wagging, head scanning.
			bob = -0.05
			head = Vector3(0.05, sin(t * 0.6) * 0.5, 0)
			tail_amp = 0.45
			tail_speed = 5.0
			jaw = 0.05
			arm_l = Vector3(0.2, 0, 0.1)
			arm_r = Vector3(0.2, 0, -0.1)
		"idle":
			# Grazing in disguise, head only slightly down so the sly grin reads from the -17 degree camera (r1 m8),
			# with a sneaky glance at Mak every 3-4 s.
			head = Vector3(-0.14 + sin(t * 9.0) * 0.04, sin(t * 0.8) * 0.2, 0)
			lean = 0.06
			jaw = maxf(0.0, sin(t * 9.0)) * 0.2
			bob += sin(t * 2.0) * 0.01
			tail_amp = 0.35
			_glance_t -= delta
			if _glance_t < 0.75:
				var g := sin(clampf((0.75 - _glance_t) / 0.75, 0.0, 1.0) * PI)
				head = head.lerp(Vector3(0.26, 0.35 * signf(sin(t * 0.3) + 0.01), 0), clampf(g * 1.6, 0.0, 1.0))
				jaw = 0.05
			if _glance_t <= 0.0:
				_glance_t = _rng.randf_range(3.0, 4.0)
		"notice":
			# Spotted you: head snaps to Mak with a small overshoot (not up at the sky), ears up, arms flare.
			head = Vector3(minf(head_pitch_to_player(0.05), 0.12), 0, 0)
			lean = -0.12
			jaw = 0.4
			ears = 0.5
			arm_l = Vector3(-0.6, 0, -0.35)
			arm_r = Vector3(-0.6, 0, 0.35)
			var rv := _anim_t - _reveal_t
			if not disguised and rv < 0.85:
				walk_on = false
				if rv < 0.07:
					# Ta-da! Arms flung out, a tall stretch.
					arm_l = Vector3(0.2, 0, -1.2)
					arm_r = Vector3(0.2, 0, 1.2)
					pose_snap("arm_l", arm_l + Vector3(0, 0, 0.55), 60.0)
					pose_snap("arm_r", arm_r + Vector3(0, 0, -0.55), 60.0)
					scale_mult = Vector3(0.9, 1.2, 0.9)
					head = Vector3(0.15, 0, 0)
					jaw = 0.5
				elif rv < 0.16:
					arm_l = Vector3(0.2, 0, -1.0)
					arm_r = Vector3(0.2, 0, 1.0)
					scale_mult = Vector3(1.08, 0.85, 1.08)
					head = Vector3(0.1, 0, 0)
				elif rv < 0.42:
					# Caught out: an embarrassed look away, ears down, paws together, tail tucked.
					scale_mult = scale_mult.lerp(Vector3.ONE, 1.0 - exp(-14.0 * delta))
					head = Vector3(-0.25, 0.55, 0.15)
					jaw = 0.0
					ears = 0.9
					arm_l = Vector3(0.55, 0, -0.15)
					arm_r = Vector3(0.55, 0, 0.15)
					tail_base = -0.7
					tail_amp = 0.08
					bob = -0.03
				else:
					# GRR!: snaps back to Mak, hunched, teeth bared.
					scale_mult = scale_mult.lerp(Vector3.ONE, 1.0 - exp(-14.0 * delta))
					lean = 0.3
					body_p = Vector3(-0.25, 0, 0)
					head = Vector3(clampf(head_pitch_to_player(0.0) + 0.45, -0.3, 0.3), 0, 0)
					jaw = 0.55 + sin(t * 30.0) * 0.06
					ears = -0.8
					arm_l = Vector3(0.6, 0, -0.5)
					arm_r = Vector3(0.6, 0, 0.5)
					tail_base = 0.3
					tail_amp = 0.2
					tail_speed = 22.0
		"windup":
			# Pawing the ground like a bull: chest dropped low over the front paws, spine pitched forward, the back
			# leg scraping, nose level with Mak (never up at the sky), ears pinned, snarl, tail stiff and twitching.
			# Lean and spine pitch are compensated on the head so the eyes stay on Mak (r1 animation major).
			var u := clampf(state_time / 0.3, 0.0, 1.0)
			lean = 0.4 * u
			# A small drop only: the rig translates as one piece, so -0.18 sank the feet 18 cm into the turf (impl3 side
			# sheet); the crouch now comes from the pitch and the leg bends.
			bob = -0.05 * u
			lunge = -0.06 * u
			body_p = Vector3(-0.35 * u, 0, 0)
			var aim := head_pitch_to_player(0.0)
			head = Vector3(clampf(aim + (lean + 0.35 * u) * 0.85, -0.45, 0.35), 0, 0)
			pose_cycle("head", Vector3(0, 0, sin(t * 18.0) * 0.05))
			jaw = 0.4 + sin(t * 20.0) * 0.08
			ears = -0.9
			tail_base = 0.15
			tail_speed = 24.0
			tail_amp = 0.18
			leg_r = Vector3(-0.45, 0, 0)
			walk_on = false
			pose_cycle("leg_r", Vector3(sin(t * 20.0) * 0.55, 0, 0))
			leg_l = Vector3(0.35, 0, 0)
			# Front paws planted wide and forward, claws in the turf.
			arm_l = Vector3(0.75, 0, -0.3)
			arm_r = Vector3(0.75, 0, 0.3)
		"attack":
			# Bounding charge: chest down, head low and forward, ears pinned, tail straight back; arms and legs work in
			# pairs from a speed-locked phase with a short flight phase (was an upright skate on the wall clock, r1).
			bound = true
			lean = 0.55
			head = Vector3(-0.2, 0, 0)
			jaw = 0.5
			ears = -1.0
			tail_base = -0.9
			tail_amp = 0.12
			tail_speed = 18.0
			scale_mult = Vector3(1.0, 0.97, 1.1)
		"skid":
			# Heels dug in, body thrown back, but the face stays forward with wide eyes and both arms windmilling
			# (head 0.35 on top of the lean pointed the face at the sky, impl3 reel).
			lean = -0.5
			tilt = sin(t * 25.0) * 0.08
			head = Vector3(-0.12, 0, 0)
			pose_cycle("arm_l", Vector3(sin(t * 14.0) * 0.6, 0, 0))
			pose_cycle("arm_r", Vector3(-sin(t * 14.0) * 0.6, 0, 0))
			jaw = 0.55
			ears = 0.7
			arm_l = Vector3(-1.8, 0, 0.4)
			arm_r = Vector3(-1.8, 0, -0.4)
			leg_l = Vector3(-0.7, 0, 0)
			leg_r = Vector3(-0.5, 0, 0)
			walk_on = false
			if has_meta("teeter"):
				# Teetering at the lip: arms windmill.
				pose_cycle("arm_l", Vector3(sin(t * 16.0) * 0.9, 0, 0))
				pose_cycle("arm_r", Vector3(-sin(t * 16.0) * 0.9, 0, 0))
				tilt = sin(t * 9.0) * 0.12
		"dizzy":
			tilt = sin(t * 6.0) * 0.18
			head = Vector3(sin(t * 4.0) * 0.2, sin(t * 3.0) * 0.3, sin(t * 5.0) * 0.2)
			jaw = 0.3
			ears = sin(t * 7.0) * 0.6
			arm_l = Vector3(0.2, 0, -0.5 - sin(t * 5.0) * 0.25)
			arm_r = Vector3(0.2, 0, 0.5 + sin(t * 5.0) * 0.25)
			tail_amp = 0.1
		"recover":
			# Shakes it off.
			bob = sin(t * 14.0) * 0.02
			head = Vector3(-0.15, 0, 0)
			pose_cycle("head", Vector3(0, sin(t * 22.0) * 0.35 * clampf(1.0 - state_time / 0.6, 0.0, 1.0), 0))
		"prowl":
			# Low predator crouch, head forward with eyes on Mak, tail low and twitching; a paw scrape and a
			# lip-curl snarl every 1.5 s (was a neutral stand for up to 5 s, r1).
			lean = 0.3
			bob = -0.03
			head = Vector3(head_pitch_to_player(0.25), 0, 0)
			ears = -0.5
			jaw = 0.12
			tail_base = -0.35
			tail_amp = 0.18
			tail_speed = 11.0
			arm_l = Vector3(-0.35, 0, 0.1)
			arm_r = Vector3(-0.35, 0, -0.1)
			var sc := 1.5 - _snarl_t
			if sc < 0.45:
				var e := sin(sc / 0.45 * PI)
				jaw = 0.12 + e * 0.35
				pose_cycle("leg_r", Vector3(-sin(sc * 30.0) * 0.5 * e, 0, 0))
		"search":
			# "Where did he go?": head scans left and right twice, a shrug, a sniff at the ground, "Hmph!".
			var s := state_time
			if s < 1.2:
				head = Vector3(0.1, sin(s / 1.2 * TAU * 2.0) * 0.8, 0)
				ears = 0.6
				jaw = 0.1
			elif s < 1.6:
				var e := sin((s - 1.2) / 0.4 * PI)
				arm_l = Vector3(0.3, 0, -0.9 * e)
				arm_r = Vector3(0.3, 0, 0.9 * e)
				bob = 0.04 * e
				head = Vector3(0.1, 0, 0.25 * e)
				jaw = 0.2
			else:
				# Nose to the ground, sniff sniff.
				lean = 0.35
				body_p = Vector3(-0.3, 0, 0)
				head = Vector3(-0.4, sin(t * 3.0) * 0.2, 0)
				pose_cycle("head", Vector3(sin(t * 24.0) * 0.06, 0, 0))
				ears = 0.2
			tail_amp = 0.15
		"home":
			# Cocky trot home: chin up, tail wagging high.
			head = Vector3(0.2, 0, 0)
			tail_base = 0.5
			tail_amp = 0.7
			tail_speed = 10.0
			jaw = 0.15
		"hurt":
			lean = -0.3
			head = Vector3(0.4, 0, 0)
			jaw = 0.5
			ears = 0.8
	var gait_bob := gait_update(delta, walk_on and not bound, 1.0, 0.07, 0.85)
	if bound:
		# Two-beat gallop (hind legs push off together, a flight phase, front paws reach and land). The body stretches on
		# the push-off, squashes on landing and rocks its pitch with the stride; ears pinned, tail streaming. LEGS pass:
		# the cadence follows the ground speed (1.8-3.2 Hz; a fixed 5.8 Hz lock once aliased at 10 fps, r1) and the
		# hocks and wrists fold on the recovery swing (the legs were straight planks).
		_gallop += delta * TAU * clampf(gait_speed / 3.3, 1.8, 3.2)
		var c := sin(_gallop)
		var c2 := sin(_gallop - 0.9)
		var air := maxf(0.0, sin(_gallop + 0.4))
		bob = air * 0.07
		lean = 0.5 + c * 0.12
		var st := 1.0 + air * 0.12 - maxf(0.0, -sin(_gallop + 0.4)) * 0.1
		scale_mult = Vector3(1.0 / sqrt(st), st * 0.97, 1.08 / sqrt(st))
		pose("arm_l", Vector3(0.45, 0, 0.3 + 0.55))
		pose("arm_r", Vector3(0.45, 0, -0.3 - 0.55))
		pose("leg_l", Vector3(-0.1, 0, 0))
		pose("leg_r", Vector3(-0.1, 0, 0))
		pose_cycle("arm_l", Vector3(c2 * 0.9, 0, 0))
		pose_cycle("arm_r", Vector3(sin(_gallop - 1.15) * 0.9, 0, 0))
		pose_cycle("leg_l", Vector3(-c * 0.9, 0, 0))
		pose_cycle("leg_r", Vector3(-sin(_gallop - 0.25) * 0.9, 0, 0))
		pose_cycle("shin_l", Vector3(-maxf(0.0, -cos(_gallop)) * 1.0, 0, 0))
		pose_cycle("shin_r", Vector3(-maxf(0.0, -cos(_gallop - 0.25)) * 1.0, 0, 0))
		pose_cycle("forearm_l", Vector3(maxf(0.0, cos(_gallop - 0.9)) * 0.8, 0, 0))
		pose_cycle("forearm_r", Vector3(maxf(0.0, cos(_gallop - 1.15)) * 0.8, 0, 0))
		pose_cycle("body", Vector3(c * 0.12, 0, 0))
	else:
		pose("leg_l", leg_l)
		pose("leg_r", leg_r)
		# The rigs rest in an A-pose: relax the arms toward the body unless a state poses them wide.
		pose("arm_l", arm_l + Vector3(0, 0, 0.55))
		pose("arm_r", arm_r + Vector3(0, 0, -0.55))
		bob += gait_bob
		gait_legs(1.0, 0.85)
	pose("body", body_p)
	pose("head", head)
	pose("jaw", Vector3(jaw, 0, 0))
	pose("ear_l", Vector3(-ears * 0.6, 0, ears * 0.4))
	pose("ear_r", Vector3(-ears * 0.6, 0, -ears * 0.4))
	pose("tail", Vector3(tail_base, 0, 0))
	pose_cycle("tail", Vector3(0, sin(t * tail_speed) * tail_amp, 0))
	pose_cycle("tail_2", Vector3(0, sin(t * tail_speed - 0.8) * tail_amp * 0.8, 0))
	# Footfalls while running and charging.
	if hv > 1.0 and is_on_floor():
		var ph2 := fmod(_gallop, PI) if bound else (0.0 if gait_footfall(prev_gait) else PI)
		if ph2 < _step_phase:
			EnemyKit.sfx(self, "enemy_step", global_position, 1.0, -2.0 if state == "attack" else -6.0)
			if state == "attack":
				EnemyKit.fx(get_parent(), "DustPuff", global_position - forward() * 0.4, 0.3)
		_step_phase = ph2


## The pop-up pirouette must read: no table debris at the hit (the wool_burst and the poof covered the spin, fix r2);
## a side spark now, a light ring of fleece tufts at the pop, and the leave-poof at the end.
func _defeat_juice_params(kind: String) -> Dictionary:
	return {"kind": kind, "no_vfx": true}


func _defeat_gag(kind: String, from_position: Vector3) -> float:
	if disguised:
		_rip_costume()
	if EnemyKit.preset(get_parent(), "wool_burst", global_position + Vector3(0, 0.45, 0), 0.4, Color(1.3, 1.3, 1.24)) == null:
		EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.45, 0), "wool", [Color("#F4EFE2"), Color("#FBF8F0")], 8, 2.6)
	say_side("Yipe!", Color(1, 0.75, 0.75), 90)
	moment_sfx("enemy_defeat", "wolf_cub_yelp")
	if prev_state == "dizzy":
		stunned(false)
	if _stars != null:
		_stars.queue_free()
		_stars = null
	var away := global_position - from_position
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else -forward()
	set_meta("flee_dir", away)
	set_meta("ground_y", global_position.y)
	velocity = Vector3.ZERO
	kick_squash(0.5)
	return 1.95


func _defeat_process(delta: float) -> void:
	# Anticipation 0.1 s, pop up and pirouette in the heart underpants (to 0.8 s), land and hold an embarrassed
	# pose facing Mak for 0.4 s, then zip off. The poof only comes at the end, small (r1: the rip was hidden).
	var t := _anim_t
	var gy: float = get_meta("ground_y", global_position.y)
	if state_time < 0.1:
		pose_snap("arm_l", Vector3(0, 0, 0.9))
		pose_snap("arm_r", Vector3(0, 0, -0.9))
		pose("jaw", Vector3(0.6, 0, 0))
		return
	if state_time < 0.8:
		if not has_meta("popped"):
			set_meta("popped", true)
			velocity = Vector3.UP * 5.2
		velocity.y -= GRAVITY * 0.7 * delta
		global_position += velocity * delta
		global_position.y = maxf(global_position.y, gy)
		spin += delta * 16.0
		tilt = 0.2
		pose("arm_l", Vector3(0, 0, -1.3))
		pose("arm_r", Vector3(0, 0, 1.3))
		pose_cycle("arm_l", Vector3(0, 0, sin(t * 30.0) * 0.3))
		pose_cycle("arm_r", Vector3(0, 0, -sin(t * 30.0) * 0.3))
		pose("leg_l", Vector3(0.6, 0, 0.3))
		pose("leg_r", Vector3(-0.6, 0, -0.3))
		pose_cycle("leg_l", Vector3(sin(t * 26.0) * 0.5, 0, 0))
		pose_cycle("leg_r", Vector3(-sin(t * 26.0) * 0.5, 0, 0))
		pose("jaw", Vector3(0.6, 0, 0))
		pose("ear_l", Vector3(0.5, 0, 0.6))
		pose("ear_r", Vector3(0.5, 0, -0.6))
		pose("tail", Vector3(0.4, 0, 0))
		pose_cycle("tail", Vector3(0, sin(t * 40.0) * 0.8, 0))
		return
	if state_time < 1.25:
		# Hold: landed, spin settles toward Mak, hands cover the shorts, ears flat, a sheepish grin.
		if not has_meta("held"):
			set_meta("held", true)
			global_position.y = gy
			kick_squash(0.45)
			EnemyKit.sfx(self, "enemy_land", global_position, 1.2, -6.0)
		spin = lerp_angle(spin, 0.0, 1.0 - exp(-14.0 * delta))
		tilt = lerpf(tilt, 0.0, 1.0 - exp(-10.0 * delta))
		pose_snap("arm_l", Vector3(-0.5, 0, 0.1), 30.0)
		pose_snap("arm_r", Vector3(-0.5, 0, -0.1), 30.0)
		pose("leg_l", Vector3(0, 0, -0.15))
		pose("leg_r", Vector3(0, 0, 0.15))
		pose("head", Vector3(-0.2, 0.15, 0.12))
		pose("jaw", Vector3(0.15, 0, 0))
		pose("ear_l", Vector3(0.9, 0, 0.3))
		pose("ear_r", Vector3(0.9, 0, -0.3))
		pose("tail", Vector3(-0.6, 0, 0))
		return
	if not has_meta("fled"):
		set_meta("fled", true)
		var away: Vector3 = get_meta("flee_dir", -forward())
		velocity = away * 6.0 + Vector3.UP * 5.5
		EnemyKit.sfx(self, "wolf_charge", global_position, 1.3, -4.0)
	velocity.y -= GRAVITY * 0.6 * delta
	global_position += velocity * delta
	spin += delta * 26.0
	tilt = 0.25
	pose("arm_l", Vector3(0, 0, -1.3))
	pose("arm_r", Vector3(0, 0, 1.3))
	pose_cycle("leg_l", Vector3(sin(t * 26.0) * 0.6, 0, 0))
	pose_cycle("leg_r", Vector3(-sin(t * 26.0) * 0.6, 0, 0))
	pose("jaw", Vector3(0.6, 0, 0))


func _defeat_burst() -> void:
	if owns("enemy_flee"):
		return
	EnemyKit.fx(get_parent(), "Confetti", global_position + Vector3(0, 0.6, 0), 0.9)
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.6, 0), "confetti", [SHORTS, Color(1, 1, 1), FUR_LIGHT], 30, 5.0)
