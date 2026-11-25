class_name GummyBrute
extends EnemyBase
## Gummy Brute: a big wobbly gummy bear. Crouches (landing ring telegraph), bounces high and
## body-slams, sending out a shockwave ring you jump over. Its back and head are a trampoline
## (stomps just bounce Mak sky-high); punch it while it is squashed and winded after a slam.
## Defeat: jiggles flat and melts.

const JELLY := Color(0.95, 0.24, 0.36, 0.84)
const JELLY_LIGHT := Color(1.0, 0.55, 0.6, 0.84)
const JELLY_DARK := Color(0.55, 0.06, 0.15)

@export var jump_time: float = 0.95
@export var wave_radius: float = 5.0
## "" or "stalker" (W3 brute_clearing maze stalker: hops toward Mak every 5 s without line of sight, clears hedges,
## melts after 3 hits and reforms at home 10 s later, a lesson rather than a soft-lock).
@export var variant: String = ""

var _jump_from: Vector3
var _jump_to: Vector3
var _marker: MeshInstance3D
var _grumble_t: float = 2.0
var _jelly_mat: StandardMaterial3D
var _mesh_jelly: Array[StandardMaterial3D] = []
var _step_phase: float = 0.0
var _puddle: MeshInstance3D
var _land_hold: float = 0.0
var _hop_t: float = 5.0
var _jump_h: float = 3.2
var _hints_done: bool = false
var _saved_mats: Array = []
var _grumble_jiggle: float = 2.0
var _puddle_eyes: Array[Node3D] = []
## Jelly core + ink outline passes (FxToon skips translucent surfaces, so the gummy had no outline, r1 M5).
static var _core_shader: Shader
const RISE := 0.4
const HANG := 0.12
const FALL := 0.3
## Shared translucent jelly look for every Gummy Brute (per-instance copies only while melting).
static var _jelly_cache: Dictionary = {}


## Plain defaults in _init so builder values survive (r1 blocker).
func _init() -> void:
	enemy_id = "gummy_brute"
	# Heavy jelly: barely leaves the ground, a slow wobble.
	notice_hop = 0.06
	notice_stretch = 0.07
	notice_len = 0.6
	display_name = "Gummy Brute"
	max_hp = 2
	body_radius = 0.6
	body_height = 1.5
	head_height = 1.55
	move_speed = 1.2
	turn_speed = 4.0
	notice_radius = 9.0
	lose_radius = 16.0
	stomp_bounce = 16.0
	squash_stiffness = 130.0
	squash_damping = 4.5
	acorns_on_defeat = 3
	block_text = "BOING!"
	windup_len = 0.9


func _setup() -> void:
	pass


func _on_mesh_ready(inst: Node) -> void:
	# Translucent raspberry jelly: soft alpha, glossy, rim and back light so light glows through it.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si) as StandardMaterial3D
			if src == null:
				continue
			var j: StandardMaterial3D = _jelly_cache.get(src.get_instance_id())
			if j == null:
				j = src.duplicate() as StandardMaterial3D
				# Raspberry, not washed salmon: near-opaque jelly over an opaque dark core, so the ground no longer
				# shows through the torso and the inner shells stop doubling every outline (r1 M5, r1 animation minor).
				j.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				# Alpha from 0.93 (read as plastic) to 0.62 over a darker opaque core 9 cm inside: the thick middle reads deep
				# raspberry, the thin rims glow lighter (gummy depth)
				# while the ground still never shows through the torso. --gummy-alpha=<a> for A/B captures.
				j.albedo_color = Color(1, 1, 1, clampf(float(Dev.arg("gummy-alpha", "0.62")), 0.3, 1.0))
				j.roughness = 0.12
				j.metallic_specular = 0.75
				j.rim_enabled = true
				# A pale, strong rim: light bleeding through the thin jelly edges is what sells "gummy" at 64 px.
				j.rim = 1.0
				j.rim_tint = 0.3
				j.backlight_enabled = true
				j.backlight = Color(0.9, 0.05, 0.2)
				j.clearcoat_enabled = true
				j.clearcoat = 0.35
				j.clearcoat_roughness = 0.1
				j.emission_enabled = true
				j.emission = Color(0.45, 0.04, 0.1)
				j.emission_energy_multiplier = 0.3
				j.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				var core := ShaderMaterial.new()
				core.shader = _core()
				core.render_priority = -1
				if not Dev.has_arg("pbr"):
					var o := ShaderMaterial.new()
					o.shader = FxToon.OUTLINE
					o.set_shader_parameter("outline_width", 1.3)
					o.set_shader_parameter("outline_color", Color("#5A0A1E"))
					core.next_pass = o
				j.next_pass = core
				_jelly_cache[src.get_instance_id()] = j
			m.set_surface_override_material(si, j)


func _build_placeholder(root: Node3D) -> void:
	_jelly_mat = StandardMaterial3D.new()
	_jelly_mat.albedo_color = JELLY
	_jelly_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_jelly_mat.roughness = 0.12
	_jelly_mat.rim_enabled = true
	_jelly_mat.rim = 0.7
	_jelly_mat.rim_tint = 0.2
	_jelly_mat.emission_enabled = true
	_jelly_mat.emission = Color(0.6, 0.05, 0.12)
	_jelly_mat.emission_energy_multiplier = 0.35
	var light := _jelly_mat.duplicate() as StandardMaterial3D
	light.albedo_color = JELLY_LIGHT
	var body := EnemyKit.pivot(root, "body", Vector3(0, 0.62, 0))
	_j(EnemyKit.ball(body, 0.55, JELLY, Vector3.ZERO, Vector3(1.0, 1.05, 0.88)))
	EnemyKit.ball(body, 0.36, JELLY_LIGHT, Vector3(0, -0.05, -0.2), Vector3(1, 1.1, 0.6)).material_override = light
	var head := EnemyKit.pivot(body, "head", Vector3(0, 0.62, -0.02))
	head.set_meta("skin", JELLY)
	_j(EnemyKit.ball(head, 0.38, JELLY, Vector3.ZERO, Vector3(1.05, 0.95, 0.95)))
	EnemyKit.ball(head, 0.16, JELLY_LIGHT, Vector3(0, -0.1, -0.3), Vector3(1.2, 0.85, 0.8)).material_override = light
	EnemyKit.ball(head, 0.06, JELLY_DARK, Vector3(0, -0.04, -0.43), Vector3(1.3, 0.9, 0.8))
	for side in [-1.0, 1.0]:
		_j(EnemyKit.ball(head, 0.13, JELLY, Vector3(0.28 * side, 0.3, 0.02), Vector3(1, 1, 0.7)))
	EnemyKit.face(head, Vector3(0, 0.1, -0.3), 0.13, 0.085, Color(0.25, 0.05, 0.08), "angry")
	EnemyKit.mouth(head, Vector3(0, -0.2, -0.33), 0.16, "grumpy", JELLY_DARK)
	for side in [-1.0, 1.0]:
		var arm := EnemyKit.pivot(body, "arm_l" if side < 0 else "arm_r", Vector3(0.5 * side, 0.22, -0.05))
		_j(EnemyKit.capsule(arm, 0.16, 0.5, JELLY, Vector3(0.1 * side, -0.16, 0), Vector3(0, 0, 30 * side)))
		var leg := EnemyKit.pivot(root, "leg_l" if side < 0 else "leg_r", Vector3(0.28 * side, 0.22, 0))
		_j(EnemyKit.ball(leg, 0.22, JELLY, Vector3(0, -0.05, -0.04), Vector3(1, 0.9, 1.25)))
	# A sugar-crystal sparkle on top hints at the trampoline back.
	for i in 6:
		var a := TAU * float(i) / 6.0
		var c := EnemyKit.box(body, Vector3(0.05, 0.05, 0.05), Color(1, 1, 1), Vector3(cos(a) * 0.3, 0.4, sin(a) * 0.3 + 0.1), Vector3(45, 45, 0))
		c.material_override = EnemyKit.glow_mat(Color(1, 0.95, 0.95), 1.2)


## Opaque dark-raspberry core: the same surface pulled 7 cm inward along its normals.
static func _core() -> Shader:
	if _core_shader == null:
		_core_shader = Shader.new()
		_core_shader.code = """shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_toon, specular_disabled;
uniform vec4 core_color : source_color = vec4(0.36, 0.02, 0.09, 1.0);
void vertex() {
	VERTEX -= normalize(NORMAL) * 0.09;
}
void fragment() {
	ALBEDO = core_color.rgb;
	ROUGHNESS = 0.6;
}
"""
	return _core_shader


func _j(mi: MeshInstance3D) -> MeshInstance3D:
	mi.material_override = _jelly_mat
	return mi


func _initial_state() -> String:
	return "idle"


func _ai(delta: float) -> void:
	if not _hints_done:
		_hints_done = true
		# W3 does not pass `variant` yet (requested); its data marks brute_clearing as the maze stalker.
		if variant == "" and String(name) == "brute_clearing":
			variant = "stalker"
		if variant == "stalker":
			max_hp = maxi(max_hp, 3)
			hp = max_hp
			wave_radius = 1.5
	if variant == "stalker" and (state == "idle" or state == "stalk"):
		_hop_t -= delta
		if player != null and dist_to_player() < 26.0 and _hop_t <= 0.0 and request_attack():
			_hop_t = 5.0
			set_state("windup")
			return
	match state:
		"idle":
			_grumble_t -= delta
			if _grumble_t < 0.0:
				_grumble_t = _rng.randf_range(3.0, 5.0)
				say("Hrrmph.", Color(1, 0.7, 0.75), 56)
				EnemyKit.sfx(self, "gummy_wobble", global_position)
			var d := home - global_position
			d.y = 0
			steer(d if d.length() > 0.5 else Vector3.ZERO, move_speed, delta, 4.0)
			if sees_player():
				notice_player("!", "gummy_wobble")
				say("HRRAAH!", Color(1, 0.5, 0.55), 80)
		"notice":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			face_toward(player_pos(), delta, 8.0)
			if state_time > 0.6:
				set_state("windup" if request_attack() else "stalk")
		"stalk":
			if player == null or dist_to_player() > lose_radius:
				set_state("idle")
				return
			face_toward(player_pos(), delta)
			var dir := flat_dir_to(player_pos())
			steer(dir if not drop_ahead(dir, 1.2) else Vector3.ZERO, move_speed, delta, 6.0)
			if state_time > 1.0 and flat_dist_to_player() < 7.5 and request_attack():
				set_state("windup")
		"windup":
			steer(Vector3.ZERO, 0.0, delta, 20.0)
			face_toward(player_pos(), delta, 8.0)
			if player != null and state_time < 0.6:
				var tgt := _safe_landing(player_pos())
				_jump_to = tgt
				if _marker == null:
					_marker = EnemyKit.ground_disc(get_parent(), _jump_to, 1.3)
				else:
					_marker.global_position = _jump_to + Vector3(0, 0.04, 0)
			squash = lerpf(squash, 0.35 * clampf(state_time / windup_len, 0.0, 1.0), 0.25)
			squash_vel = 0.0
			if state_time > windup_len:
				_jump_from = global_position
				set_state("attack")
		"attack":
			# Heavy arc: a fast ease-out rise (0.4 s), a short hang at the apex (0.12 s), an ease-in fall (0.3 s);
			# the old symmetric parabola fell as slowly as it rose (r1 animation).
			var tt := state_time
			var h := 6.5 if variant == "stalker" else 3.2
			var y := 0.0
			var u := 0.0
			if tt < RISE:
				var a := tt / RISE
				y = h * (1.0 - (1.0 - a) * (1.0 - a))
				u = a * 0.45
			elif tt < RISE + HANG:
				y = h
				u = 0.45 + (tt - RISE) / HANG * 0.1
			else:
				var b := clampf((tt - RISE - HANG) / FALL, 0.0, 1.0)
				y = h * (1.0 - b * b)
				u = 0.55 + b * 0.45
			var p := _jump_from.lerp(_jump_to, u)
			p.y = lerpf(_jump_from.y, _jump_to.y, u) + y
			velocity = (p - global_position) / maxf(delta, 0.001)
			if tt >= RISE + HANG + FALL:
				velocity = Vector3.ZERO
				_slam()
		"recover":
			steer(Vector3.ZERO, 0.0, delta, 30.0)
			if state_time > 1.9:
				set_state("stalk")


## Landing spot toward p, at most 6 m away, on floor within 1 m of the brute's own height. Steps back toward the
## brute until it finds one, so it never slams in mid-air past an edge (r1 fun).
func _safe_landing(p: Vector3) -> Vector3:
	var off := p - global_position
	off.y = 0
	if variant == "stalker":
		# Maze hop: straight onto Mak's cell, over the hedges, wherever the floor is.
		if off.length() > 9.0:
			off = off.normalized() * 9.0
		var t := global_position + off
		var sy := floor_y_at(Vector3(t.x, p.y, t.z), 1.5, 6.0)
		if not is_nan(sy):
			return Vector3(t.x, sy, t.z)
	if off.length() > 6.0:
		off = off.normalized() * 6.0
	for k in 5:
		var s := 1.0 - float(k) * 0.22
		var c := global_position + off * s
		var fy := floor_y_at(Vector3(c.x, global_position.y, c.z), 1.2, 2.2)
		if not is_nan(fy) and absf(fy - global_position.y) < 1.0:
			return Vector3(c.x, fy, c.z)
	return global_position


func _physics_process(delta: float) -> void:
	# The jump arc is driven kinematically; gravity would fight it.
	uses_gravity = state != "attack"
	super._physics_process(delta)


func _slam() -> void:
	set_state("recover")
	# Landing squash holds for 2 frames before the wobble: symmetric and volume-preserving (sy 0.6, sx 1.29), palms
	# slapping the ground in front (r1 animation: a 0.3 x 1.8 frame with an arm sticking out read as falling over).
	squash = 0.4
	squash_vel = 0.0
	_land_hold = 0.034
	moment_sfx("enemy_slam", "gummy_slam")
	if not owns("enemy_slam"):
		EnemyKit.fx(get_parent(), "SlamShockwave", global_position + Vector3(0, 0.05, 0), 0.9, Color(1.0, 0.7, 0.75))
	EnemyKit.fx(get_parent(), "DustPuff", global_position, 1.4)
	juice("enemy_slam", {"scale": 1.2, "tint": Color(1.0, 0.7, 0.75)}, global_position + Vector3(0, 0.05, 0))
	stunned(true)
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.2, 0), "dust", [Color(1, 0.85, 0.85)], 14, 4.0)
	var wave := GummyShockwave.new()
	wave.max_radius = wave_radius
	get_parent().add_child(wave)
	wave.global_position = global_position
	say("Oof...", Color(1, 0.8, 0.85), 64)


func _on_enter_state(s: String) -> void:
	if prev_state == "recover" and s != "recover" and s != "defeat":
		stunned(false)
	# Finish pass (encounter r1 major): the landing disc stays through the jump and goes at the landing, so the
	# player can read where the gummy will come down while it is in the air.
	if s != "windup" and s != "attack" and _marker != null:
		EnemyKit.fade_free(_marker)
		_marker = null
	if s == "attack":
		moment_sfx("enemy_attack", "gummy_jump")
		EnemyKit.fx(get_parent(), "DustPuff", global_position, 0.9)
		kick_squash(-0.7)


func _resolve_hit(kind: String, _from_position: Vector3) -> String:
	if kind == "stomp" or kind == "slam":
		say("Boing!", Color(1, 0.75, 0.85), 80)
		EnemyKit.sfx(self, "gummy_boing", global_position)
		return "bounce"
	if state == "recover" or state == "hurt":
		return "damage"
	return "block"


func _contact_active() -> bool:
	# Only the landing of the telegraphed jump hurts (the disc marks it); stalking is solid but harmless (r1 fun).
	return state == "attack" and state_time > RISE + HANG + FALL * 0.4


func _contact_yields_to_attack() -> bool:
	return state == "recover"


func _on_hurt_player(p: Node3D) -> void:
	# The slam is a heavy hit: a longer knockback arc and a heavier beat than a pea (r1 fun minor).
	if p != null and p.has_method("add_impulse"):
		var away := p.global_position - global_position
		away.y = 0
		away = away.normalized() if away.length() > 0.01 else -forward()
		p.call("add_impulse", away * 5.0 + Vector3.UP * 5.5)
	juice("enemy_slam", {"scale": 0.8}, p.global_position + Vector3(0, 0.1, 0) if p != null else Vector3.INF)


func _defeat_juice_params(kind: String) -> Dictionary:
	# The splat waits for the melt (r1 animation: the body was a puddle in 0.4 s and the debris flew at once).
	return {"kind": kind, "no_vfx": true}


func _after_hurt_state() -> String:
	# Finish pass (encounter r1 major): the counter-jump goes through the attack tokens and the on-screen gate
	# like every other attack (the hurt-to-windup shortcut made the one off-screen hit).
	if hp <= 0:
		return "recover"
	return "windup" if request_attack() else "stalk"


func _animate(delta: float) -> void:
	if _land_hold > 0.0:
		_land_hold -= delta
		# Finish pass (r1 animation major): hold the landing squash _slam sets (0.4, sy 0.6); 0.7 forced sy 0.32.
		squash = 0.4
		squash_vel = 0.0
	var hv := walk_cycle(delta, 1.0)
	var t := _anim_t
	# LEGS pass: a heavy, short-legged gait from the shared distance-driven stride (knees fold on the swing, a deep
	# bob and a side-to-side waddle in step); the legs used to swing through the 14/s pose ease as stiff posts.
	var prev_gait := gait_phase
	var walking := state != "attack" and state != "windup"
	bob = gait_update(delta, walking, 0.9, 0.1, 0.7)
	lean = 0.06 * gait_w
	tilt = sin(gait_phase) * 0.09 * gait_w
	spin = 0.0
	# Heavy waddle: every footfall jiggles the jelly and thumps.
	if hv > 0.3 and is_on_floor() and gait_footfall(prev_gait):
		squash_vel += 1.1
		EnemyKit.sfx(self, "enemy_step", global_position, 0.6, -2.0)
	# Exaggerated fists (ART_V2: the gummy's one big feature): forearms and fists scaled 1.35x so they break the outline.
	pose_scale("forearm_l", Vector3.ONE * 1.35)
	pose_scale("forearm_r", Vector3.ONE * 1.35)
	if state != "attack" and state != "windup":
		# A jelly that jiggles: a continuous 2.5 Hz wobble on the body scale (+-4 %) with the head lagging behind the
		# belly, plus a belly jiggle every couple of seconds (r1 animation: the idle barely moved).
		var w := sin(t * TAU * 2.5 + _breath_phase)
		scale_mult = Vector3(1.0 + 0.04 * w, 1.0 - 0.04 * w, 1.0 + 0.04 * w)
		pose_cycle("head", Vector3(sin(t * TAU * 2.5 + _breath_phase - 1.1) * 0.07, 0, sin(t * TAU * 1.25 - 0.6) * 0.05))
		pose_cycle("spine_2", Vector3(sin(t * TAU * 2.5 + _breath_phase - 0.5) * 0.05, 0, 0))
		_grumble_jiggle -= delta
		if _grumble_jiggle <= 0.0:
			_grumble_jiggle = _rng.randf_range(1.6, 2.8)
			kick_squash(0.28)
	else:
		scale_mult = scale_mult.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
	match state:
		"idle":
			# Grumpy idle: fists held out from the belly so they read at 64 px, a huff side to side.
			squash_vel += sin(t * 3.0) * 0.08
			pose("arm_l", Vector3(0.35, 0, 0.25 + sin(t * 2.0) * 0.08))
			pose("arm_r", Vector3(0.35, 0, -0.25 - sin(t * 2.0) * 0.08))
			pose("forearm_l", Vector3(0.5, 0, 0))
			pose("forearm_r", Vector3(0.5, 0, 0))
			pose("head", Vector3(0.05, sin(t * 0.9) * 0.3, 0))
			pose("ear_l", Vector3(0, 0, sin(t * 4.0) * 0.1))
			pose("ear_r", Vector3(0, 0, -sin(t * 4.0) * 0.1))
		"notice":
			# "Hm?!": fists come up beside the head and the shoulders hunch (a straight forward reach read as a zombie
			# grab from the side, impl3 sheet).
			# Rig convention (verified on the impl3 side sheets): +X swings a hanging arm forward and up.
			pose_snap("arm_l", Vector3(1.25, 0, 0.35), 30.0)
			pose_snap("arm_r", Vector3(1.25, 0, -0.35), 30.0)
			pose("forearm_l", Vector3(1.0, 0, 0))
			pose("forearm_r", Vector3(1.0, 0, 0))
			pose("head", Vector3(0.12, 0, 0))
			lean = -0.1
		"windup":
			# The crouch ramps in 0.45 s with the arms swinging up and the shoulders bunching, then the whole jelly
			# quivers faster and faster, eyes on the landing disc, until it springs (r1 animation: a 1 s static hold).
			var u := clampf(state_time / 0.45, 0.0, 1.0)
			var e := 1.0 - (1.0 - u) * (1.0 - u)
			var q := clampf((state_time - 0.45) / maxf(windup_len - 0.45, 0.1), 0.0, 1.0)
			var qf := 18.0 + 50.0 * q
			lean = 0.1 * e
			bob = -0.1 * e
			pose("arm_l", Vector3(0.3 + 2.3 * e, 0, 0.2))
			pose("arm_r", Vector3(0.3 + 2.3 * e, 0, -0.2))
			pose("forearm_l", Vector3(0.7 * e, 0, 0))
			pose("forearm_r", Vector3(0.7 * e, 0, 0))
			pose("head", Vector3(-0.1 * e, 0, 0))
			pose("leg_l", Vector3(0.35 * e, 0, -0.2 * e))
			pose("leg_r", Vector3(0.35 * e, 0, 0.2 * e))
			pose_cycle("spine_2", Vector3(sin(t * qf) * 0.05 * (0.3 + q), 0, sin(t * qf * 0.8) * 0.05 * (0.3 + q)))
			pose_cycle("head", Vector3(0, sin(t * qf * 0.6) * 0.06 * q, 0))
			var qs := sin(t * qf) * 0.035 * (0.4 + q)
			# Anticipation squash: the jelly settles 13 % lower and bulges out as it loads the spring (the crouch only
			# moved the arms from the front camera, impl3 sheet).
			scale_mult = Vector3(1.0 + qs + 0.07 * e, 1.0 - qs - 0.13 * e, 1.0 + qs + 0.07 * e)
		"attack":
			pose("arm_l", Vector3(-2.9, 0, 0.2))
			pose("arm_r", Vector3(-2.9, 0, -0.2))
			pose("leg_l", Vector3(0.7, 0, 0))
			pose("leg_r", Vector3(0.7, 0, 0))
			pose("head", Vector3(0.2, 0, 0))
		"recover":
			# Winded after the slam: palms on the ground in front, slumped, panting, a dazed head roll. The punch window.
			lean = 0.25
			bob = -0.05
			pose("head", Vector3(-0.3, 0, sin(t * 3.0) * 0.15))
			pose("arm_l", Vector3(0.8, 0, 0.75))
			pose("arm_r", Vector3(0.8, 0, -0.75))
			squash_vel += sin(t * 10.0) * 0.12
		_:
			pose("arm_l", Vector3(0.0, 0, 0.15))
			pose("arm_r", Vector3(0.0, 0, -0.15))
			pose("head", Vector3(0.05, 0, 0))
			pose_cycle("head", Vector3(0, 0, sin(gait_phase) * 0.06 * gait_w))
	if walking:
		pose("leg_l", Vector3.ZERO)
		pose("leg_r", Vector3.ZERO)
	gait_legs(1.1, 0.5 if state != "idle" and state != "notice" and state != "recover" else 0.0)
	if state != "windup" and state != "idle" and state != "notice":
		pose("forearm_l", Vector3(0.3, 0, 0))
		pose("forearm_r", Vector3(0.3, 0, 0))
	# Secondary jelly wobble: the upper body lags the squash spring.
	pose("spine_2", Vector3(squash_vel * 0.02, 0, sin(t * 7.0) * squash * 0.3))


func _defeat_gag(_kind: String, _from_position: Vector3) -> float:
	say_side("Blorp...", Color(1, 0.7, 0.8), 80)
	moment_sfx("enemy_defeat", "gummy_melt")
	# Per-instance copies so only this bear melts.
	_mesh_jelly.clear()
	_saved_mats.clear()
	if mesh_root != null:
		for mi in mesh_root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for si in m.mesh.get_surface_count():
				var cur := m.get_active_material(si) as StandardMaterial3D
				if cur != null:
					_saved_mats.append([m, si, cur])
					var c := cur.duplicate() as StandardMaterial3D
					m.set_surface_override_material(si, c)
					_mesh_jelly.append(c)
	set_meta("melt_stage", 0)
	return 2.45


## Melt (2.45 s): the knees go and the body sags (0-0.35 s), the head droops and one arm waves a weak goodbye
## (to 0.95 s), it slumps into a spreading puddle with jelly droplets (to 1.35 s), and the puddle keeps two eyes that
## look up at Mak, blink once and then the poof takes it (r1 animation: body to puddle in 0.4 s with no face).
func _defeat_process(delta: float) -> void:
	var st := state_time
	var t := _anim_t
	var stage: int = get_meta("melt_stage", 0)
	scale_mult = Vector3.ONE
	if st < 0.35:
		var u := st / 0.35
		bob = -0.12 * u
		lean = 0.1 * u
		rig.scale = rig.scale.lerp(Vector3(1.08, 0.88, 1.08), 1.0 - exp(-10.0 * delta))
		pose("leg_l", Vector3(0.6 * u, 0, -0.4 * u))
		pose("leg_r", Vector3(0.6 * u, 0, 0.4 * u))
		pose("arm_l", Vector3(0.4, 0, 0.9))
		pose("arm_r", Vector3(0.4, 0, -0.9))
		pose("head", Vector3(-0.2 * u, 0, 0.1 * u))
		return
	if st < 0.95:
		var u := (st - 0.35) / 0.6
		bob = -0.12 - 0.1 * u
		rig.scale = rig.scale.lerp(Vector3(1.25, 0.7 - 0.1 * u, 1.25), 1.0 - exp(-6.0 * delta))
		pose("head", Vector3(-0.5, 0, 0.35))
		pose("arm_l", Vector3(0.3, 0, 1.1))
		# One arm raised in a weak little wave.
		pose("arm_r", Vector3(0.4, 0, 0.2))
		pose_cycle("arm_r", Vector3(0, 0, sin(t * 9.0) * 0.35))
		pose_cycle("forearm_r", Vector3(sin(t * 9.0 - 0.6) * 0.3, 0, 0))
		for jm in _mesh_jelly:
			jm.albedo_color.a = lerpf(jm.albedo_color.a, 0.75, 1.0 - exp(-3.0 * delta))
		return
	if st < 1.35:
		if stage < 1:
			set_meta("melt_stage", 1)
			_spawn_puddle()
			EnemyKit.sfx(self, "gummy_melt", global_position, 0.85, -3.0)
			EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.7, 0), "jelly", [Color(0.95, 0.24, 0.36), Color(1, 0.55, 0.6)], 22, 3.2)
		var u := (st - 0.95) / 0.4
		bob = lerpf(bob, 0.0, 1.0 - exp(-8.0 * delta))
		var jig := sin(t * 26.0) * 0.06 * (1.0 - u)
		rig.scale = rig.scale.lerp(Vector3(1.8 + jig, 0.05, 1.8 - jig), 1.0 - exp(-7.0 * delta))
		pose("arm_l", Vector3(0, 0, 1.4))
		pose("arm_r", Vector3(0, 0, -1.4))
		for jm in _mesh_jelly:
			jm.albedo_color.a = lerpf(jm.albedo_color.a, 0.25, 1.0 - exp(-4.0 * delta))
		return
	# Puddle hold: the eyes rise out of the jelly, look up, blink once.
	rig.scale = rig.scale.lerp(Vector3(1.8, 0.03, 1.8), 1.0 - exp(-6.0 * delta))
	if stage < 2:
		set_meta("melt_stage", 2)
		_spawn_puddle_eyes()
	var blink := 1.0
	if st > 1.95 and st < 2.07:
		blink = 0.1
	for e in _puddle_eyes:
		if is_instance_valid(e):
			var rs: Vector3 = e.get_meta("rest_scale", Vector3.ONE)
			var grow := clampf((st - 1.35) / 0.2, 0.0, 1.0)
			e.scale = Vector3(rs.x * grow, rs.y * grow * blink, rs.z * grow)


func _spawn_puddle() -> void:
	_puddle = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.05
	cm.radial_segments = 40
	_puddle.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.92, 0.2, 0.32, 0.85)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.08
	pm.rim_enabled = true
	pm.rim = 0.6
	pm.emission_enabled = true
	pm.emission = Color(0.45, 0.04, 0.1)
	pm.emission_energy_multiplier = 0.3
	_puddle.material_override = pm
	get_parent().add_child(_puddle)
	_puddle.global_position = global_position + Vector3(0, 0.02, 0)
	_puddle.scale = Vector3(0.45, 1, 0.45)
	var tw := _puddle.create_tween()
	tw.tween_property(_puddle, "scale", Vector3(1.35, 1, 1.2), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(1.0)
	tw.tween_property(pm, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(_puddle.queue_free)


func _spawn_puddle_eyes() -> void:
	_puddle_eyes.clear()
	if _puddle == null or not is_instance_valid(_puddle):
		return
	var holder := Node3D.new()
	holder.name = "PuddleEyes"
	get_parent().add_child(holder)
	holder.global_position = global_position + Vector3(0, 0.1, 0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var to_cam := cam.global_position - holder.global_position
		to_cam.y = 0
		if to_cam.length() > 0.01:
			holder.rotation.y = atan2(to_cam.x, to_cam.z)
	for left in [true, false]:
		var e := EnemyKit.eye(holder, Vector3(-0.17 if left else 0.17, 0.0, 0.25), 0.11, Color(0.25, 0.05, 0.08), "worried", left)
		e.rotation_degrees = Vector3(0, 180, 0)
		e.set_meta("rest_scale", e.scale)
		e.scale = Vector3.ZERO
		_puddle_eyes.append(e)
	get_tree().create_timer(1.3).timeout.connect(holder.queue_free)


func _finish_defeat() -> void:
	if variant != "stalker":
		super._finish_defeat()
		return
	if not is_inside_tree():
		return
	# Melted, not gone: the acorns pop out, then the jelly reforms at home 10 s later.
	moment_sfx("enemy_flee", "enemy_defeat_poof")
	_defeat_burst()
	EnemyKit.drop_acorns(get_parent(), global_position, acorns_on_defeat)
	defeated.emit(self)
	visible = false
	get_tree().create_timer(10.0).timeout.connect(_reform)


func _reform() -> void:
	if not is_inside_tree():
		return
	for e in _saved_mats:
		var mi := e[0] as MeshInstance3D
		if is_instance_valid(mi):
			mi.set_surface_override_material(int(e[1]), e[2] as Material)
	_saved_mats.clear()
	global_position = home
	reset_physics_interpolation()
	rig.scale = Vector3.ONE
	scale_mult = Vector3.ONE
	is_defeated = false
	_pancake_t = -1.0
	hp = max_hp
	collision_layer = 1 << 2
	collision_mask = 1
	hurtbox.set_deferred("monitorable", true)
	head_zone.set_deferred("monitoring", true)
	visible = true
	if is_instance_valid(_puddle):
		_puddle.queue_free()
	EnemyKit.poof(get_parent(), home + Vector3(0, 0.3, 0), 0.8, Color(1.0, 0.7, 0.75))
	squash = -0.5
	squash_vel = 0.0
	say("Hrrmph!", Color(1, 0.6, 0.7), 70)
	_hop_t = 5.0
	set_state("idle")


func _defeat_burst() -> void:
	if owns("enemy_flee"):
		return
	EnemyKit.fx(get_parent(), "Confetti", global_position + Vector3(0, 0.3, 0), 0.8, Color(1.0, 0.55, 0.65))
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.3, 0), "jelly", [Color(0.95, 0.24, 0.36), Color(1, 0.55, 0.6)], 30, 5.0)
