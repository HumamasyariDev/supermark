class_name WolfBoss
extends AnimatableBody3D
const GoldenHatLib := preload("res://scripts/objects/golden_hat.gd")
## Sir Reginald Huffington III: the three-phase rooftop fight (Docs/levels/BOSS.md + BOSS_amendments R1-R3).
## Real rigged Tripo P2 wolf (WolfRig + WolfRecipes, no authored clips), two hits per phase.
##  P1 HUFF: inhale (chest balloons), straight gust, sweep, two flank huffs at the gaps, tea debris; hide in the
##     lavender lee of a chimney. He hops down and pants: stomp or Ham Slam the head under the gold ring.
##     After hit 1 the cycle is denser and ends with a reverse sweep and the Chimney Sweep (soot from the hearths).
##  P2 PUFF: paws the roof (red dashed line), bull-charges. Into a chimney or stump: stuck head-first, Ham Slam the
##     tail under the gold ring (the chimney becomes a stump). Into a gap: teeter, any attack into his back.
##     Elsewhere on the parapet: dizzy. After hit 1: faster, and every second wind-up is a feint.
##  P3 HURRICANE: he spins at the centre inside a ring of flying tea things; spin wind, the Teapot Typhoon and crows.
##     Ham Slam the gold-plugged vent to fly to 8.45 m, drift in and slam his head. Hit 2: the Backfire Updraft.
##  Defeat: he swells, floats and wedges into a chimney; bounce on the belly and Ham Slam it: POP. The Great
##     Truffle BOSS-1 and the Golden Top Hat fly out; collecting the truffle unlocks the Golden Top Hat (Mak wears
##     the plain top hat from the start, so the reward is its gold variant: scripts/objects/golden_hat.gd).
## Falls keep his hits (R3.4); losing every slice resets the phase.

signal phase_changed(p: int)
signal hit_landed(p: int, hits_in_phase: int)
signal boss_popped
signal boss_defeated

const HITS := 2
const STAND := Vector3(0, 1.0, -13.4)
const APEX := Vector3(0, 3.0, -12.8)
const GOLD := Color(1.0, 0.79, 0.24)
const HAZARD := Color(1.0, 0.35, 0.24)
const CREAM := Color(1.0, 0.95, 0.84)
const PANT_SPOTS := [Vector3(0, 0, -9.0), Vector3(-4.5, 0, -8.2), Vector3(4.5, 0, -8.2)]
const TRUFFLE_AT := Vector3(0, 0.0, 0)
const STORM_TARGET := Vector3(-260, 40, -220)

var arena: WolfRooftop
var rig: WolfRig
var bar: BossHealthBar
var phase := 1
var hits := 0
var total := 0
var state := ""
var st := 0.0
var facing := Vector3(0, 0, 1)
var anim := "sip"
var anim_p: Dictionary = {}
var defeated := false
var body_cs: CollisionShape3D
var head_wp: BossWeakpoint
var tail_wp: BossWeakpoint
var back_wp: BossWeakpoint
var chest_wp: BossWeakpoint
var _guarded := false
var _guard_next := false
var _rasp: Curve3D
var wind: Area3D
var _rng := RandomNumberGenerator.new()
var _bark_label: Label3D
var _bark_cd := 0.0
var _bark_hide := 0.0
var _warned: Dictionary = {}
var _gold_ring: MeshInstance3D
var _tail_ring: MeshInstance3D
var _rest_y := 0.0
var _head_fx: Node3D
var _step_t := 0.0
var _hit_cd := 0.0
var _contact_cd := 0.0
var stats := {"hits": [], "falls": 0, "slices_lost": 0, "events": []}
var fight_time := 0.0
var fighting := false
var _clock := 0.0
# Fix round 1 (critic panels r1): retries, fairness, barks.
var _hp_last := 6
var _fall_reset := false
var _phase_done := false
var _retry := false
var _falls_seen := 0
var _bark_queued: Dictionary = {}
var _bark_shown := 0.0
var _crow_cd := 0.0
var last_steal_t := -10.0
var _blow_t := 0.0
var _blowoff_cd := 0.0
var _launch_air := false
var _launch_land_t := 0.0
var _pant_decal: MeshInstance3D
var _ring_safe := 0.0

# P1
var cycle := 0
var steps: Array = []
var step_i := 0
var step_t := 0.0
var gust: Dictionary = {}
var debris: Array = []
var _debris_due: Array = []
var pant_spot := Vector3(0, 0, -9)
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_dur := 1.0
var _hop_h := 1.2
var _flank_first := 1
var _gust_fx: Node3D
var _arrow: Node3D
var _shadow: MeshInstance3D
var _sheltered_t := 0.0
var _sweep_active := false
var _sweep_areas: Array[Area3D] = []
var _tail_swat_t := -1.0

# P2
var charge_dir := Vector3.FORWARD
var charge_speed := 14.0
var charge_len := 30.0
var charge_from := Vector3.ZERO
var windups := 0
var _feint := false
var _feinted := false
var _line: Node3D
var stuck_chimney: BossChimney
var _dust_t := 0.0
var _teeter_lip := Vector3.ZERO
var _dizzy_acorns := false

# P3
var ring: Node3D
var ring_pieces: Array[Area3D] = []
var ring_on := true
var ring_speed := 90.0
var typhoon: BossTyphoon
var typhoon_theta := 200.0
var typhoon_speed := 14.0
var active_vent: BossVent
var vent_t := 0.0
var vent_dur := 5.0
var _next_vent: BossVent
var _vent_visit := false
var _visits := 0
var _dud_cd := 0.0
var _duds := 0
var _launch_pending := 0.0
var _plug_slam := false
var crows: Array = []
var spectators: Array = []
var hit2_armed := false
var updraft := ""
var updraft_t := 0.0
var _apex_done := false
var _slowmo_t := 0.0
var _last_slam_pos := Vector3.INF

# Defeat
var cork: BossChimney
var cork_u := Vector3.ZERO
var belly := Vector3.ZERO
var _belly_cd := 0.0
var _boing := 0.0
var popped := false
var _hat: Node3D
var _truffle: Node3D


class BossWindZone extends Area3D:
	var boss: Node

	func get_wind(pos: Vector3) -> Vector3:
		if boss == null or not is_instance_valid(boss):
			return Vector3.ZERO
		return boss.call("wind_at", pos)


func _ready() -> void:
	_rng.seed = 64
	collision_layer = 4
	collision_mask = 0
	sync_to_physics = false
	add_to_group("boss")
	body_cs = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.95
	cap.height = 3.0
	body_cs.shape = cap
	body_cs.position = Vector3(0, 1.5, 0)
	add_child(body_cs)
	rig = WolfRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.set_layers(3)
	# Teacup for the sip, in the left paw.
	var cup := Node3D.new()
	# Real teacup model (the W2 giant teacup prop at hand size) instead of a cylinder and torus stand-in (r1 m10).
	var cup_path := "res://assets/props/w2/giant_teacup/giant_teacup.glb"
	if ResourceLoader.exists(cup_path):
		var cup_m := (load(cup_path) as PackedScene).instantiate() as Node3D
		cup.add_child(cup_m)
		EnemyKit.fit_height(cup_m, 0.15)
		if not Dev.has_arg("pbr"):
			FxToon.apply(cup_m, {"rim": 0.45, "outline_width": 1.0})
	else:
		EnemyKit.cylinder(cup, 0.11, 0.08, 0.13, Color(0.97, 0.95, 0.92), Vector3(0, 0.05, 0))
		EnemyKit.ring(cup, 0.03, 0.05, Color(0.85, 0.68, 0.3), Vector3(0.12, 0.05, 0), Vector3(90, 0, 0))
	rig.attach("hand_l", cup, Transform3D(Basis(), Vector3(0, -0.12, 0.1)))
	# Same storybook toon look as Mak and the minions (r1 m11); transparent surfaces (monocle) keep their material.
	if not Dev.has_arg("pbr"):
		FxToon.apply(rig, {"rim": 0.45, "outline_width": 1.3})
	cup.name = "Teacup"
	head_wp = BossWeakpoint.make(self, "head", 1.15, 1.0)
	add_child(head_wp)
	tail_wp = BossWeakpoint.make(self, "tail", 0.85, 1.2)
	add_child(tail_wp)
	back_wp = BossWeakpoint.make(self, "back", 1.1, 2.6)
	add_child(back_wp)
	chest_wp = BossWeakpoint.make(self, "chest", 1.25, 2.4)
	add_child(chest_wp)
	wind = BossWindZone.new()
	wind.name = "WindZone"
	(wind as BossWindZone).boss = self
	wind.collision_layer = 128
	wind.collision_mask = 0
	wind.monitoring = false
	wind.add_to_group("wind_zone")
	var wcs := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(44, 30, 44)
	wcs.shape = wb
	wcs.position = Vector3(0, 10, 0)
	wind.add_child(wcs)
	arena.add_child.call_deferred(wind)
	_bark_label = Label3D.new()
	_bark_label.fixed_size = true
	_bark_label.pixel_size = 0.0011
	_bark_label.font_size = 40
	_bark_label.outline_size = 12
	_bark_label.modulate = Color("3b2416")
	_bark_label.outline_modulate = Color("f3e6c4")
	_bark_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark_label.no_depth_test = true
	_bark_label.render_priority = 10
	_bark_label.width = 900.0
	_bark_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ResourceLoader.exists("res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"):
		_bark_label.font = load("res://assets/fonts/cherryswash/CherrySwash-Bold.ttf") as Font
	_bark_label.visible = false
	add_child(_bark_label)
	_gold_ring = _make_ring(0.95, 0.12)
	_tail_ring = _make_ring(0.55, 0.09)
	_shadow = MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 1.4
	sm.bottom_radius = 1.4
	sm.height = 0.02
	_shadow.mesh = sm
	var shm := StandardMaterial3D.new()
	shm.albedo_color = Color(0.08, 0.03, 0.1, 0.0)
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = shm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	# Gold landing ring at the pant spot (r1 fun: "add a gold decal at the pant shadow"): shown from the hop-down
	# so the player knows where the head will be before it lands.
	_pant_decal = _make_ring(1.45, 0.1)
	_pant_decal.scale = Vector3(1, 0.15, 1)
	bar = BossHealthBar.new()
	bar.name = "BossBar"
	add_child(bar)
	var g := _game()
	if g != null:
		if g.has_signal("cake_empty"):
			g.connect("cake_empty", _on_cake_empty)
		if g.has_signal("player_respawned"):
			g.connect("player_respawned", _on_respawned)
		if g.has_signal("damaged"):
			g.connect("damaged", func(_n: int) -> void: stats["slices_lost"] = int(stats["slices_lost"]) + 1)
		if g.has_signal("health_changed"):
			_hp_last = int(g.get("health"))
			g.connect("health_changed", _on_health_changed)
		if g.has_signal("truffle_collected"):
			g.connect("truffle_collected", _on_truffle)


func _make_ring(r: float, w: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - w
	tm.outer_radius = r + w
	tm.rings = 32
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = EnemyKit.glow_mat(GOLD, 3.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi


func _game() -> Node:
	return get_node_or_null("/root/Game")


func player() -> Node3D:
	return arena.player if arena != null else null


func ppos() -> Vector3:
	var p := player()
	return p.global_position if p != null else Vector3(0, 0, 14)


func _dev_has(a: String) -> bool:
	var dev := get_node_or_null("/root/Dev")
	return dev != null and bool(dev.call("has_arg", a))


func _dev_arg(a: String, d: String) -> String:
	var dev := get_node_or_null("/root/Dev")
	return String(dev.call("arg", a, d)) if dev != null else d


func log_event(what: String) -> void:
	var e := {"t": snappedf(_clock, 0.01), "phase": phase, "hits": hits, "e": what}
	(stats["events"] as Array).append(e)
	print("[Boss] t=%.2f P%d h%d %s" % [_clock, phase, hits, what])


# ------------------------------------------------------------------ fight flow

## Juice bus (Docs/JUICE.md): emit the gameplay fact. The boss skips only the fallback channels the table owns.
func juice(ev: String, pos: Vector3 = Vector3.INF, params: Dictionary = {}) -> void:
	if not params.has("node"):
		params["node"] = self
	EnemyKit.juice(self, ev, pos, params)


func juice_has(ev: String, channel: String) -> bool:
	var j := get_node_or_null("/root/Juice")
	return j != null and j.has_method("handles") and bool(j.call("handles", ev, channel))


## A node that follows the head bone, so attached Juice loops (sweat, dizzy stars) sit on the head.
func head_fx() -> Node3D:
	if _head_fx == null or not is_instance_valid(_head_fx):
		_head_fx = Node3D.new()
		_head_fx.name = "HeadFx"
		add_child(_head_fx)
	_head_fx.global_position = rig.bone_world("head")
	return _head_fx


func begin_fight() -> void:
	var start := clampi(int(_dev_arg("boss-phase", "1")), 1, 3)
	phase = start
	total = (start - 1) * HITS
	global_position = STAND
	facing = Vector3(0, 0, 1)
	_face_now()
	bar.show_bar("Sir Reginald Huffington III", HITS * 3)
	if arena.player != null and not arena.player.is_connected("ground_pounded", _on_ground_pounded):
		arena.player.connect("ground_pounded", _on_ground_pounded)
	bar.set_remaining(HITS * 3 - total)
	_spawn_spectators()
	_prewarm()
	var seen := false
	var g := _game()
	if g != null and g.has_method("is_unlocked"):
		seen = bool(g.call("is_unlocked", "boss_intro_seen"))
	if start == 1 and not seen and not _dev_has("no-cine"):
		_intro_cines()
	else:
		# Finish pass: the title shows once (the sky page at build); a revisit goes straight to the chapter headline.
		_enter_phase(start)


func _intro_cines() -> void:
	set_state("intro")
	var d := arena.director
	# Finish pass: the old opening camera stood 2.4 m from Mak at knee height (a huge white shape cut by the left
	# edge) and its first 2 s played behind the Router page turn. Now: hold the opening frame until the page has
	# turned, then crane from over Mak's shoulder (Mak in the lower left third, the wolf centred on his terrace).
	var a0 := Vector3(2.4, 2.0, 21.0)
	var l0 := Vector3(-0.3, 1.6, -12.0)
	d.cine("Cine_Entry", a0, l0, a0, l0, 46.0, 46.0, 60.0)
	var router := get_node_or_null("/root/Router")
	if router != null and bool(router.get("busy")):
		await router.transition_finished
		await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	juice("boss_intro", global_position + Vector3(0, 2.0, 0))
	# The one title of the fight is this sky-page headline (no HUD banner, no title in the narration).
	arena.page_headline("THE WOLF'S\nOWN TALE", "Prologue")
	d.cine("Cine_Entry", a0, l0, Vector3(0.8, 3.4, 22.5), Vector3(0, 0.8, -10), 46.0, 56.0, 4.5)
	await d.cine_finished
	EnemyKit.voice(self, "voice_wolf_delicious")
	bark("intro", "Ah. The piglet. Do mind the draught.", "", true)
	arena.hud.say("Being the true and entirely accurate account of how the Wolf won.")
	# Look at the head (about 4.0 m on the terrace), not the chest, with headroom (r1 animation / spectacle: the
	# opening line was delivered with his eyes out of the top of the frame).
	d.cine("Cine_Intro", Vector3(3.5, 2.7, -9.6), Vector3(0, 3.3, -13.4), Vector3(0.7, 3.1, -9.0), Vector3(0, 3.55, -13.4), 46.0, 42.0, 4.0)
	await d.cine_finished
	var g := _game()
	if g != null and g.has_method("unlock"):
		g.call("unlock", "boss_intro_seen")
	_enter_phase(1)


func _enter_phase(p: int) -> void:
	var retry := _retry
	_retry = false
	_phase_done = false
	phase = p
	hits = 0
	fighting = true
	if retry:
		# Retry after a phase reset (r1 fun minor): no headline, narration or long opener; straight back in.
		arena.director.set_phase(p)
		arena.director.air_pitch = p == 3
		arena.set_phase_look(p, 0.6)
		log_event("phase_retry")
		match p:
			1:
				global_position = STAND
				_face_dir(Vector3(0, 0, 1))
				cycle = 0
				set_state("p1_open")
				st = 1.9
			2:
				windups = 0
				charge_speed = 14.0
				set_state("p2_open")
				st = 1.1
			3:
				global_position = Vector3.ZERO
				_start_p3()
				set_state("p3_open")
				st = 0.9
		return
	arena.director.set_phase(p)
	arena.director.air_pitch = p == 3
	arena.set_phase_look(p)
	bar.set_phase_title(["", "I. The Huff", "II. The Puff", "III. The Hurricane"][p])
	phase_changed.emit(p)
	if p >= 2:
		juice("boss_phase", global_position + Vector3(0, 2.0, 0), {"phase": p})
	log_event("phase_start")
	var g := _game()
	if g != null and g.has_method("set_checkpoint"):
		g.call("set_checkpoint", "BOSS", arena.checkpoint_xform())
	match p:
		1:
			arena.set_lee_visible(true)
			arena.page_headline("PIG BLOWN\nAWAY", "Chapter I")
			arena.hud.say("Chapter One. The wolf huffed, and the little pig was blown clean off the roof.")
			global_position = STAND
			_face_dir(Vector3(0, 0, 1))
			cycle = 0
			set_state("p1_open")
		2:
			arena.set_lee_visible(false)
			arena.page_headline("NOTHING STOPS\nTHE WOLF", "Chapter II")
			arena.hud.say("Chapter Two. The wolf charged like a gentleman bull, and nothing could stop him.")
			windups = 0
			charge_speed = 14.0
			set_state("p2_open")
		3:
			arena.set_lee_visible(false)
			arena.page_headline("NO PIG\nGETS NEAR", "Chapter III")
			arena.hud.say("Chapter Three. The wolf became a hurricane, and the little pig could not get near him.")
			global_position = Vector3(0, 0, 0)
			_start_p3()
			set_state("p3_open")


func set_state(s: String) -> void:
	state = s
	st = 0.0


# ------------------------------------------------------------------ physics

func _physics_process(delta: float) -> void:
	st += delta
	_clock += delta
	if fighting and not defeated:
		fight_time += delta
	_bark_cd = maxf(0.0, _bark_cd - delta)
	_hit_cd = maxf(0.0, _hit_cd - delta)
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_crow_cd = maxf(0.0, _crow_cd - delta)
	_blowoff_cd = maxf(0.0, _blowoff_cd - delta)
	_ring_safe = maxf(0.0, _ring_safe - delta)
	_bark_shown += delta
	if not _bark_queued.is_empty() and _bark_shown >= 1.2:
		var q := _bark_queued
		_bark_queued = {}
		_show_bark(String(q["id"]), String(q["text"]), String(q["voice"]))
	if _bark_hide > 0.0:
		_bark_hide -= delta
		if _bark_hide <= 0.0:
			_bark_label.visible = false
	anim_p = {}
	match state:
		"intro":
			anim = "sneer" if st < 2.0 else "sip"
		"p1_open":
			anim = "sip"
			_face_toward(ppos(), delta, 2.0)
			if st > 2.5:
				_start_cycle()
		"p1":
			_p1_tick(delta)
		"p1_hurt":
			_p1_hurt_tick(delta)
		"raspberry":
			_raspberry_tick(delta)
		"p1_trans":
			_p1_trans_tick(delta)
		"p2_open", "paw", "charge", "feint", "stuck", "pull_free", "dizzy", "teeter", "dangle", "reposition", "p2_hurt", "p2_trans", "soot_tumble":
			_p2_tick(delta)
		"p3_open", "p3", "p3_dizzy", "p3_tell", "p3_cough", "p3_trans":
			_p3_tick(delta)
		"swell", "drift", "wedged", "popped":
			_defeat_tick(delta)
		"respawn_wait":
			anim = "sip" if phase == 1 else ("sneer" if phase == 2 else "spin")
			if st > 1.5:
				_enter_phase(phase)
	_update_debris(delta)
	_update_markers(delta)
	# After _update_markers, so the P3 slam ring is not switched off again in the same frame (r1 fun major).
	_head_marker()
	_launch_watch(delta)
	_contact_damage()
	_shelter_bark(delta)
	_gust_blowoff(delta)
	_parapet_perch(delta)
	_animate(delta)


var _anim_over := ""
var _anim_over_t := 0.0
var _anim_over_age := 0.0


## Plays a short one-off recipe over the state's own (the cane-guard deflect).
func play_over(a: String, seconds: float) -> void:
	_anim_over = a
	_anim_over_t = seconds
	_anim_over_age = 0.0


func _animate(delta: float) -> void:
	rig.begin()
	if _anim_over_t > 0.0:
		_anim_over_t -= delta
		_anim_over_age += delta
		WolfRecipes.apply(rig, _anim_over, _anim_over_age, {})
		rig.update(delta)
		if _bark_label.visible:
			_bark_label.global_position = global_position + Vector3(0, 4.2 * rig.body.scale.y, 0)
		return
	WolfRecipes.apply(rig, anim, st if not anim_p.has("t") else float(anim_p["t"]), anim_p)
	rig.update(delta)
	if _head_fx != null and is_instance_valid(_head_fx):
		_head_fx.global_position = rig.bone_world("head")
	if _bark_label.visible:
		_bark_label.global_position = global_position + Vector3(0, 4.2 * rig.body.scale.y, 0)


func _face_dir(d: Vector3) -> void:
	d.y = 0.0
	if d.length() < 0.01:
		return
	facing = d.normalized()
	_face_now()


func _face_now() -> void:
	rotation.y = atan2(-facing.x, -facing.z)


func _face_toward(p: Vector3, delta: float, rate: float = 4.0) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return
	var cur := atan2(facing.x, facing.z)
	var want := atan2(d.x, d.z)
	var a := lerp_angle(cur, want, 1.0 - exp(-rate * delta))
	facing = Vector3(sin(a), 0, cos(a))
	_face_now()


## Left vector of the wolf (his left, for head turns).
func _left() -> Vector3:
	return Vector3(facing.z, 0, -facing.x)


func _contact_damage() -> void:
	var p := player()
	if p == null or _contact_cd > 0.0:
		return
	var harmful := state == "charge" or (state == "feint" and st > 0.3)
	if not harmful:
		return
	var d := p.global_position - global_position
	if Vector2(d.x, d.z).length() < 1.5 and d.y < 2.8:
		_contact_cd = 0.8
		if p.has_method("take_damage"):
			# Tossed aside off the charge line, not along it (r1 fun probe B: straight-ahead knockback put an idle Mak
			# on the parapet coping, where every later charge stopped short of him).
			var side := Vector3(-charge_dir.z, 0.0, charge_dir.x)
			if side.dot(Vector3(d.x, 0, d.z)) < 0.0:
				side = -side
			p.call("take_damage", 1, p.global_position - side * 1.5)
			p.call("add_impulse", side * 4.0)
		_on_hurt_player("charge")


func _on_hurt_player(why: String) -> void:
	EnemyKit.voice(self, "voice_wolf_laugh")
	match why:
		"debris":
			bark("bark_debris", "One lump or two?")
		"thump":
			bark("bark_thump", "Personal space!")
		_:
			bark("bark_laugh", "Ha-HA!")
	var g := _game()
	if g != null and int(g.get("health")) == 1:
		bark("bark_low", "Shall I put the kettle on? You look peaky.")


const GLOAT_BARKS := ["bark_laugh", "bark_feint", "bark_light", "bark_respawn", "bark_hiding", "bark_crow", "bark_debris", "bark_thump", "bark_low", "intro", "bark_blown"]


func bark(id: String, text: String, voice: String = "", force: bool = false) -> void:
	if not force and _bark_cd > 0.0:
		return
	# A forced line no longer replaces one that has been readable for under 1.2 s (r1 animation major): it waits in a
	# one-slot queue (a newer queued line drops the older one).
	if _bark_label.visible and _bark_shown < 1.2:
		_bark_queued = {"id": id, "text": text, "voice": voice}
		_bark_cd = 4.0
		return
	_show_bark(id, text, voice)


func _show_bark(id: String, text: String, voice: String) -> void:
	_bark_cd = 4.0
	_bark_shown = 0.0
	_bark_label.text = text
	_bark_label.visible = true
	_bark_label.scale = Vector3.ONE * 0.3
	create_tween().tween_property(_bark_label, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bark_hide = 2.4
	if voice != "":
		EnemyKit.voice(self, voice)
	elif id.begins_with("bark_"):
		# Text-only barks still get a vocal: a chuckle for the gloating lines, a growl for the rest.
		var laugh := id in ["bark_laugh", "bark_feint", "bark_light", "bark_respawn", "bark_hiding", "bark_crow"]
		EnemyKit.sfx(self, "wolf_laugh" if laugh else "boss_growl", global_position + Vector3(0, 2.6, 0), randf_range(0.95, 1.08), -7.0)
	# Only the gloating lines get a laugh from the gallery, and from one crow (not every crow on every bark).
	if id in GLOAT_BARKS:
		var perched: Array = []
		for c in spectators:
			if is_instance_valid(c) and (c as BossCrow).mode == "perch":
				perched.append(c)
		if not perched.is_empty():
			var cr := perched[_rng.randi() % perched.size()] as BossCrow
			get_tree().create_timer(0.3 + randf() * 0.3).timeout.connect(cr.cackle)
	log_event("bark " + id)


func warn_once(id: String, text: String, voice: String = "") -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	bark(id, text, voice, true)


# ------------------------------------------------------------------ wind

func wind_at(pos: Vector3) -> Vector3:
	var w := Vector3.ZERO
	if defeated:
		return w
	if phase == 1 and state == "p1" and not gust.is_empty():
		w += _gust_wind(pos)
	if phase == 1 and state == "p1" and _cur_step_kind() == "inhale":
		var to := APEX - pos
		to.y = 0
		if to.length() < 26.0:
			w += to.normalized() * 2.0
	if phase == 3 and not defeated:
		w += _spin_wind(pos)
		w += _typhoon_wind(pos)
		if updraft == "column":
			var r := Vector2(pos.x, pos.z)
			if r.length() < 3.5 and pos.y > 5.0:
				w += Vector3(-pos.x, 0, -pos.z).normalized() * 3.0
	return w


func _gust_axis() -> Vector3:
	if gust.has("b0"):
		var k := clampf(float(gust["t"]) / float(gust["dur"]), 0.0, 1.0)
		return WolfRooftop.bearing_dir(lerpf(float(gust["b0"]), float(gust["b1"]), k))
	return WolfRooftop.bearing_dir(float(gust["b"]))


func _gust_wind(pos: Vector3) -> Vector3:
	var to := pos - APEX
	to.y = 0.0
	var dist := to.length()
	if dist < 0.5 or dist > float(gust["len"]):
		return Vector3.ZERO
	var dir := to / dist
	if rad_to_deg(dir.angle_to(_gust_axis())) > float(gust["half"]):
		return Vector3.ZERO
	if sheltered(pos):
		return Vector3.ZERO
	return dir * float(gust["spd"])


## Shelter rule: a ray from the gust apex to Mak's chest blocked by a chimney (group "chimney") or the terrace.
func sheltered(pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(APEX + Vector3(0, 0, 0.4), pos + Vector3(0, 0.9, 0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var col: Object = hit.get("collider")
	return col is Node and ((col as Node).is_in_group("chimney") or (col as Node).name == "Terrace")


func _spin_wind(pos: Vector3) -> Vector3:
	if pos.y >= 4.0 or state == "p3_dizzy" or not ring_on or _launch_air:
		return Vector3.ZERO
	var r := Vector2(pos.x, pos.z).length()
	if r < 2.5 or r > 10.0:
		return Vector3.ZERO
	if active_vent != null and Vector2(pos.x - active_vent.global_position.x, pos.z - active_vent.global_position.z).length() < 2.2:
		return Vector3.ZERO
	var k := 1.0 - (r - 2.5) / 7.5
	return Vector3(pos.x, 0, pos.z).normalized() * 8.0 * k


func _typhoon_wind(pos: Vector3) -> Vector3:
	if typhoon == null or pos.y > 5.0 or _launch_air:
		return Vector3.ZERO
	var d := pos - typhoon.global_position
	d.y = 0.0
	var r := d.length()
	if r < 1.0 or r > 2.6:
		return Vector3.ZERO
	var out := d / r
	var tan := Vector3(-out.z, 0, out.x)
	return tan * 6.0 + out * 3.0


# ------------------------------------------------------------------ P1 HUFF

func _start_cycle() -> void:
	cycle += 1
	_guarded = _guard_next
	_guard_next = false
	steps = []
	var after := hits >= 1
	_flank_first = 1 if _rng.randf() < 0.5 else -1
	var b1 := 116.0 if _flank_first > 0 else 244.0
	var b2 := 244.0 if _flank_first > 0 else 116.0
	# r1 fun: the first cycle is now about 6.5 s (inhale, straight gust, flank pair, hop) instead of 9.4 s; the
	# sweep only joins after hit 1, so the phase gets harder instead of easier.
	steps.append({"k": "inhale", "d": 1.0 if after else 1.2})
	steps.append({"k": "gust", "d": 1.4, "b": 180.0, "half": 30.0, "len": 34.0, "spd": 10.0, "n": 5 if after else 4})
	steps.append({"k": "pause", "d": 0.5})
	if after:
		steps.append({"k": "gust", "d": 1.6, "b0": 215.0, "b1": 145.0, "half": 22.0, "len": 34.0, "spd": 10.0, "n": 6})
	steps.append({"k": "turn", "d": 0.5, "b": b1})
	steps.append({"k": "gust", "d": 1.2, "b": b1, "half": 18.0, "len": 24.0, "spd": 11.0, "n": 4 if after else 3, "flank": true})
	steps.append({"k": "turn", "d": 0.4 if after else 0.5, "b": b2})
	steps.append({"k": "gust", "d": 1.2, "b": b2, "half": 18.0, "len": 24.0, "spd": 11.0, "n": 4 if after else 3, "flank": true, "sweep_tell": after})
	if after:
		steps.append({"k": "gust", "d": 1.6, "b0": 145.0, "b1": 215.0, "half": 22.0, "len": 34.0, "spd": 10.0, "n": 6, "sweep": true})
	steps.append({"k": "hop_down", "d": 1.0})
	steps.append({"k": "pant", "d": 4.5})
	steps.append({"k": "hop_back", "d": 1.2})
	step_i = -1
	set_state("p1")
	_next_step()


func _cur_step_kind() -> String:
	if step_i < 0 or step_i >= steps.size():
		return ""
	return String((steps[step_i] as Dictionary)["k"])


func _next_step() -> void:
	step_i += 1
	step_t = 0.0
	gust = {}
	if _gust_fx != null and is_instance_valid(_gust_fx):
		if _gust_fx.has_method("set_active"):
			_gust_fx.call("set_active", false)
		var old := _gust_fx
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(old):
				old.queue_free())
		_gust_fx = null
	chest_wp.set_open(false)
	if step_i >= steps.size():
		_start_cycle()
		return
	var s: Dictionary = steps[step_i]
	var k := String(s["k"])
	match k:
		"inhale":
			juice("boss_inhale", rig.bone_world("head") + facing * 0.5, {"direction": facing})
			if not juice_has("boss_inhale", "sfx"):
				EnemyKit.sfx(self, "boss_inhale", global_position)
			EnemyKit.voice(self, "voice_wolf_inhale")
			log_event("inhale" + (" (cane guard)" if _guarded else ""))
			# Pop the Bellows window: the ballooning chest is a target for any attack (R2.2.2).
			chest_wp.global_position = Vector3(0, 1.9, -13.0)
			chest_wp.set_open(true)
		"gust":
			gust = {"t": 0.0, "dur": float(s["d"]), "half": float(s["half"]), "len": float(s["len"]), "spd": float(s["spd"])}
			if s.has("b0"):
				gust["b0"] = float(s["b0"])
				gust["b1"] = float(s["b1"])
			else:
				gust["b"] = float(s["b"])
			var n := int(s["n"])
			_debris_due = []
			for i in n:
				_debris_due.append(float(s["d"]) * (0.1 + 0.8 * float(i) / maxf(1.0, float(n - 1))))
			juice("boss_huff", rig.bone_world("head") + facing * 0.8, {"direction": _gust_axis()})
			if not juice_has("boss_huff", "sfx"):
				EnemyKit.sfx(self, "boss_huff_blast", global_position)
				EnemyKit.sfx(self, "gust_whoosh", global_position)
			if cycle == 1 and step_i == 1:
				EnemyKit.voice(self, "voice_wolf_huffpuff")
			rig.kick(-0.25)
			if not juice_has("boss_huff", "shake"):
				arena.director.shake(0.18)
			for c in spectators:
				if is_instance_valid(c):
					(c as BossCrow).flap_up()
			_spawn_gust_fx(s)
			if bool(s.get("sweep", false)):
				_start_chimney_sweep()
			log_event("gust %s" % ("sweep" if s.has("b0") else str(s["b"])))
		"turn":
			_show_flank_arrow(float(s["b"]))
		"hop_down":
			_choose_pant_spot()
			_hop(global_position, pant_spot, 1.0, 1.4)
			_shadow.global_position = pant_spot + Vector3(0, 0.03, 0)
			(_shadow.material_override as StandardMaterial3D).albedo_color.a = 0.55
			_pant_decal.global_position = pant_spot + Vector3(0, 0.05, 0)
			_pant_decal.visible = true
		"pant":
			juice("boss_winded", rig.bone_world("head"), {"node": head_fx()})
			if not juice_has("boss_winded", "sfx"):
				EnemyKit.voice(self, "voice_wolf_panting")
			head_wp.set_open(true)
			warn_once("bark_pant_warn", "Nobody... hff... bounce on my head.")
			log_event("pant at %s" % str(pant_spot))
		"hop_back":
			juice("boss_recover", global_position, {"node": null})
			head_wp.set_open(false)
			_pant_decal.visible = false
			_hop(global_position, STAND, 1.2, 1.6)


func _p1_tick(delta: float) -> void:
	if step_i < 0 or step_i >= steps.size():
		return
	var s: Dictionary = steps[step_i]
	var k := String(s["k"])
	step_t += delta
	var dur := float(s["d"])
	match k:
		"inhale":
			anim = "inhale"
			anim_p = {"k": clampf(step_t / dur, 0.0, 1.0), "guard": _guarded}
			_face_toward(ppos(), delta, 3.0)
		"gust":
			anim = "huff"
			gust["t"] = step_t
			var ax := _gust_axis()
			var yaw := clampf(ax.signed_angle_to(facing, Vector3.UP) * -1.0, -0.8, 0.8)
			anim_p = {"dur": dur, "t": step_t, "yaw": yaw}
			if _gust_fx != null and is_instance_valid(_gust_fx):
				_gust_fx.look_at(_gust_fx.global_position + ax, Vector3.UP)
			while not _debris_due.is_empty() and step_t >= float(_debris_due[0]):
				_debris_due.pop_front()
				_spawn_debris(ax, float(s["half"]))
			if bool(s.get("sweep_tell", false)) and step_t >= 0.2 and step_t - delta < 0.2:
				_chimney_sweep_tell()
			_tail_swat_check(delta)
		"pause":
			anim = "sip"
			_tail_swat_check(delta)
		"turn":
			anim = "head_turn"
			var dir := WolfRooftop.bearing_dir(float(s["b"]))
			var yaw := dir.signed_angle_to(facing, Vector3.UP) * -1.0
			anim_p = {"yaw": clampf(yaw, -1.0, 1.0)}
			_tail_swat_check(delta)
		"hop_down", "hop_back":
			anim = "hop"
			var kk := clampf(step_t / _hop_dur, 0.0, 1.0)
			anim_p = {"k": kk}
			_hop_step(kk)
			if k == "hop_back":
				_face_toward(global_position + Vector3(0, 0, 1), delta, 6.0)
			if kk >= 1.0 and step_t - delta < _hop_dur:
				_land(k == "hop_down")
		"pant":
			anim = "pant"
			_face_toward(ppos(), delta, 1.5)
	if step_t >= dur:
		_next_step()


func _hop(from: Vector3, to: Vector3, dur: float, h: float) -> void:
	_hop_from = from
	_hop_to = to
	_hop_dur = dur
	_hop_h = h
	var d := to - from
	d.y = 0
	if d.length() > 0.2:
		_face_dir(d if to.y < from.y or to.z > from.z else -d)


func _hop_step(k: float) -> void:
	var e := k
	var pos := _hop_from.lerp(_hop_to, e)
	pos.y += sin(PI * k) * _hop_h + (_hop_to.y - _hop_from.y) * 0.0
	global_position = pos


func _land(thump: bool) -> void:
	rig.kick(0.55)
	juice("boss_stomp", global_position + Vector3(0, 0.05, 0))
	if not juice_has("boss_stomp", "sfx"):
		EnemyKit.sfx(self, "boss_stomp", global_position)
	if not juice_has("boss_stomp", "shake"):
		arena.director.shake(0.28)
	EnemyKit.burst(arena, global_position + Vector3(0, 0.2, 0), "dust", [Color(0.75, 0.68, 0.7), Color(0.6, 0.55, 0.6)], 22, 5.0)
	if ResourceLoader.exists("res://scenes/fx/LandingRing.tscn"):
		FxEffect.spawn(arena, "res://scenes/fx/LandingRing.tscn", global_position + Vector3(0, 0.05, 0))
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = 0.0
	if thump:
		var p := player()
		if p != null:
			var d := p.global_position - global_position
			if Vector2(d.x, d.z).length() < 1.6 and d.y < 1.2:
				p.call("take_damage", 1, global_position)
				_on_hurt_player("thump")


func _choose_pant_spot() -> void:
	var mp := ppos()
	if hits == 0:
		pant_spot = PANT_SPOTS[0]
		return
	var best := Vector3.INF
	var best_d := -1.0
	for s in PANT_SPOTS:
		var d := (s as Vector3).distance_to(Vector3(mp.x, 0, mp.z))
		if d <= 16.0 and d > best_d:
			best_d = d
			best = s
	if best == Vector3.INF:
		var nd := 1e9
		for s in PANT_SPOTS:
			var d2 := (s as Vector3).distance_to(Vector3(mp.x, 0, mp.z))
			if d2 < nd:
				nd = d2
				best = s
		var ext := clampf((nd - 16.0) * 0.1, 0.0, 1.0)
		for i in steps.size():
			if String((steps[i] as Dictionary)["k"]) == "pant":
				steps[i]["d"] = float(steps[i]["d"]) + ext
	pant_spot = best


func _spawn_gust_fx(s: Dictionary) -> void:
	if not ResourceLoader.exists("res://scenes/fx/GustSwirl.tscn"):
		return
	var fx := (load("res://scenes/fx/GustSwirl.tscn") as PackedScene).instantiate() as Node3D
	fx.set("length", float(s["len"]) * 0.8)
	fx.set("radius", tan(deg_to_rad(float(s["half"]))) * float(s["len"]) * 0.35)
	fx.set("strength", 1.4)
	arena.add_child(fx)
	fx.global_position = APEX
	fx.look_at(APEX + _gust_axis(), Vector3.UP)
	if fx.has_method("set_active"):
		fx.call("set_active", true)
	_gust_fx = fx


func _show_flank_arrow(b: float) -> void:
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.queue_free()
	var dir := WolfRooftop.bearing_dir(b)
	var from := Vector3(0, 0.05, -10.6)
	_arrow = EnemyKit.ground_strip(arena, from, dir, 15.0, 1.6, Color(HAZARD.r, HAZARD.g, HAZARD.b, 0.55))
	var a := _arrow
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(a):
			EnemyKit.fade_free(a, 0.3))
	EnemyKit.sfx(self, "enemy_windup", global_position)


func _tail_swat_check(delta: float) -> void:
	# Mak on the terrace behind the wolf: the tail bristles 0.5 s, then swats him south.
	var p := player()
	if p == null:
		return
	var mp := p.global_position
	var on_terrace := Vector2(mp.x, mp.z + 15.0).length() < 4.4 and mp.z < -12.4 and mp.y > 0.8
	if _tail_swat_t < 0.0:
		if on_terrace:
			_tail_swat_t = 0.0
			bark("bark_tail", "Ahem! Members only.", "", true)
	else:
		_tail_swat_t += delta
		if _tail_swat_t >= 0.5:
			_tail_swat_t = -1.0
			if on_terrace:
				p.call("take_damage", 1, mp + Vector3(0, 0, -2))
				p.call("add_impulse", Vector3(0, 7, 8))
				EnemyKit.sfx(self, "punch", mp)


# Tea debris: saucers, sugar cubes, teaspoons and pages, 0.45-0.6 m, 12 m/s, falling to 0.8 m over 6 m.
func _spawn_debris(axis: Vector3, half: float) -> void:
	var a := deg_to_rad(_rng.randf_range(-half, half) * 0.8)
	var dir := axis.rotated(Vector3.UP, a)
	var piece := Area3D.new()
	piece.collision_layer = 16
	piece.collision_mask = 0
	piece.add_to_group("hazard")
	piece.set_meta("damage", 1)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.38
	cs.shape = sp
	piece.add_child(cs)
	var vis := Node3D.new()
	piece.add_child(vis)
	var kind := _rng.randi() % 4
	var white := Color(0.97, 0.95, 0.92)
	var cup_m := EnemyKit.teacup(0.42) if kind == 0 else null
	match kind:
		0:
			if cup_m != null:
				vis.add_child(cup_m)
			else:
				EnemyKit.cylinder(vis, 0.3, 0.24, 0.05, white, Vector3.ZERO)
				EnemyKit.ring(vis, 0.26, 0.3, GOLD, Vector3(0, 0.03, 0))
		1:
			var b := EnemyKit.box(vis, Vector3(0.36, 0.36, 0.36), white, Vector3.ZERO)
			b.material_override = EnemyKit.mat(Color(1, 0.99, 0.96), 0.9, 0.3)
		2:
			EnemyKit.capsule(vis, 0.05, 0.55, Color(0.82, 0.84, 0.9), Vector3.ZERO, Vector3(0, 0, 90))
			EnemyKit.ball(vis, 0.1, Color(0.82, 0.84, 0.9), Vector3(0.3, 0, 0), Vector3(1.3, 0.4, 1))
		3:
			var pg := EnemyKit.box(vis, Vector3(0.5, 0.02, 0.36), Color(0.93, 0.9, 0.8), Vector3.ZERO)
			EnemyKit.box(vis, Vector3(0.4, 0.025, 0.04), Color(0.3, 0.25, 0.2), Vector3(0, 0, -0.08))
			pg.rotation_degrees.x = 20.0
	vis.scale = Vector3.ONE * _rng.randf_range(1.0, 1.25)
	var shadow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.01
	shadow.mesh = cm
	shadow.material_override = EnemyKit.unshaded(Color(0.1, 0.05, 0.12, 0.45))
	(shadow.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.top_level = true
	piece.add_child(shadow)
	arena.add_child(piece)
	piece.global_position = APEX + dir * 0.8
	piece.area_entered.connect(func(_a: Area3D) -> void: pass)
	debris.append({"n": piece, "v": dir * 12.0, "d": 0.0, "spin": Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9), _rng.randf_range(-9, 9)), "vis": vis, "sh": shadow})


func _update_debris(delta: float) -> void:
	var keep: Array = []
	var p := player()
	for d in debris:
		var n := d["n"] as Area3D
		if not is_instance_valid(n):
			continue
		var v: Vector3 = d["v"]
		var pos := n.global_position + v * delta
		var dist := float(d["d"]) + v.length() * delta
		d["d"] = dist
		pos.y = lerpf(3.0, 0.9, clampf(dist / 6.0, 0.0, 1.0)) + sin(dist * 1.3) * 0.15
		n.global_position = pos
		(d["vis"] as Node3D).rotation += (d["spin"] as Vector3) * delta
		(d["sh"] as Node3D).global_position = Vector3(pos.x, 0.02, pos.z)
		var dead := dist > 32.0 or Vector2(pos.x, pos.z).length() > 18.5
		for c in arena.chimneys.values():
			var ch := c as BossChimney
			if ch.footprint_has(pos, 1.6 if pos.y < 1.2 else 1.15) and pos.y < ch.top_y():
				dead = true
		if p != null and p.global_position.distance_to(pos - Vector3(0, 0.6, 0)) < 0.9:
			if not bool(d.get("hit", false)):
				d["hit"] = true
				_on_hurt_player("debris")
		if dead:
			EnemyKit.burst(arena, pos, "crumbs", [Color(0.97, 0.95, 0.92), GOLD], 8, 3.0)
			n.queue_free()
		else:
			keep.append(d)
	debris = keep


func _start_chimney_sweep() -> void:
	# Blast boxes along each lee bearing, 1.1-3.0 m from each chimney centre (R3.3).
	_sweep_active = true
	for id in WolfRooftop.CHIMNEYS.keys():
		var ch := arena.chimneys[id] as BossChimney
		if ch.smashed:
			continue
		var b := float(WolfRooftop.LEE[id])
		var dir := WolfRooftop.bearing_dir(b)
		var a := Area3D.new()
		a.collision_layer = 16
		a.collision_mask = 0
		a.add_to_group("hazard")
		a.set_meta("damage", 1)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.2, 2.8, 1.9)
		cs.shape = bs
		a.add_child(cs)
		arena.add_child(a)
		a.global_position = (WolfRooftop.CHIMNEYS[id] as Vector3) + dir * 2.05 + Vector3(0, 1.4, 0)
		a.rotation.y = atan2(dir.x, dir.z)
		_sweep_areas.append(a)
		EnemyKit.burst(arena, a.global_position, "dust", [Color(0.1, 0.09, 0.09), Color(0.2, 0.18, 0.18)], 26, 5.0)
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		for a2 in _sweep_areas:
			if is_instance_valid(a2):
				a2.queue_free()
		_sweep_areas.clear()
		_sweep_active = false
		arena.set_near_bands(0.0))
	log_event("chimney_sweep")


func _chimney_sweep_tell() -> void:
	for c in arena.chimneys.values():
		(c as BossChimney).belch(2.6)
	arena.set_near_bands(0.55)
	bark("bark_smoke", "Chimney sweep! Mind your whiskers.", "", true)


func _shelter_bark(delta: float) -> void:
	if phase != 1 or state != "p1":
		_sheltered_t = 0.0
		return
	if not gust.is_empty() and sheltered(ppos()):
		_sheltered_t += delta
		if _sheltered_t > 6.0:
			_sheltered_t = -30.0
			bark("bark_hiding", "I can see your ears, Piglet.")


## r1 fun blocker: P1 could not hurt a player who stood still, because the parapet behind the spawn caught Mak and
## the straight gust only pinned him there. Now an unsheltered Mak pressed against the parapet by a gust for 0.45 s
## is lifted over the wall and blown clean off the roof (a fall: one slice, back to the bookmark). The rule
## "hide in the lee or be blown away" is taught by the first gust.
var _perch_t := 0.0


func _gust_blowoff(delta: float) -> void:
	if phase != 1 or state != "p1" or gust.is_empty() or _blowoff_cd > 0.0 or defeated:
		_blow_t = 0.0
		return
	var p := player()
	if p == null:
		return
	var pos := p.global_position
	var r := Vector2(pos.x, pos.z).length()
	var w := _gust_wind(pos)
	if w.length() < 0.5 or r < 16.7 or pos.y > 1.6:
		_blow_t = maxf(0.0, _blow_t - delta * 2.0)
		return
	_blow_t += delta
	if _blow_t < 0.45:
		return
	_blow_t = 0.0
	_blowoff_cd = 3.0
	var out := Vector3(pos.x, 0.0, pos.z).normalized()
	p.set("ext_vel", Vector3.ZERO)
	if p.get("forward_speed") != null:
		p.set("forward_speed", 0.0)
	p.call("bounce", 10.0)
	# The outward shove comes a moment later, once he is above the coping, so the wall does not stop him.
	get_tree().create_timer(0.13, false, true).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.call("add_impulse", out * 8.0))
	EnemyKit.burst(arena, pos + Vector3(0, 0.8, 0), "dust", [Color(1, 1, 1, 0.8), Color(0.85, 0.8, 0.9)], 20, 6.0)
	EnemyKit.sfx(self, "gust_whoosh", pos)
	arena.director.shake(0.25)
	bark("bark_blown", "Whoosh! I did say mind the draught.", "", true)
	arena.hud.say("And the little pig, who did not hide, was blown clean off the roof.")
	log_event("blown off the roof at r %.1f" % r)


## r1 fun major (probe B): after the first charge Mak could stand on the parapet coping behind the spawn, where every
## later charge stopped short and did nothing. In P2 and P3 the coping is no place to stand: after 1 s a spectator
## crow shoos him back onto the roof (a hop inward, no damage), and a charge that stops at the parapet next to him
## shoulder-checks him (see _charge_collide).
func _parapet_perch(delta: float) -> void:
	var p := player()
	if p == null or defeated or phase < 2:
		_perch_t = 0.0
		return
	var pos := p.global_position
	var r := Vector2(pos.x, pos.z).length()
	var on_top := r > 17.7 and r < 19.0 and pos.y > 0.6 and pos.y < 1.5 and bool(p.get("grounded"))
	if not on_top:
		_perch_t = 0.0
		return
	_perch_t += delta
	if _perch_t < 1.0:
		return
	_perch_t = -1.0
	var inward := Vector3(-pos.x, 0.0, -pos.z).normalized()
	p.call("bounce", 7.0)
	p.call("add_impulse", inward * 6.0)
	EnemyKit.burst(arena, pos + Vector3(0, 0.9, 0), "dust", [Color(0.2, 0.18, 0.22), Color(0.4, 0.38, 0.42)], 10, 3.0)
	EnemyKit.sfx(self, "crow_swoop", pos)
	for c in spectators:
		if is_instance_valid(c) and (c as BossCrow).mode == "perch":
			(c as BossCrow).cackle()
			break
	bark("bark_perch", "Off the masonry, Piglet! That is load-bearing.", "", true)
	log_event("shooed off the parapet")


## Plug launch flight: no spin or typhoon wind while he flies (so every vent flies the same arc), and 0.6 s of
## ring safety after the landing (r1 fun: "0.6 s of no ring damage after a launch landing").
func _launch_watch(delta: float) -> void:
	if not _launch_air:
		return
	var p := player()
	if p == null or phase != 3:
		_launch_air = false
		return
	_launch_land_t += delta
	if _launch_land_t > 0.15 and bool(p.get("grounded")):
		_launch_air = false
		if p.get("invulnerable") != null:
			p.set("invulnerable", maxf(float(p.get("invulnerable")), 0.6))


## Before the tea ring re-forms, Mak standing inside it is shrugged out past it with a hop and 1.2 s of
## invulnerability (r1 fun major: the re-forming ring trapped him, 3 slices in 3.2 s).
func _clear_ring_zone() -> void:
	var p := player()
	if p == null:
		return
	var pos := p.global_position
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > 4.6 or pos.y > 5.5:
		return
	var out := Vector3(pos.x, 0.0, pos.z)
	if out.length() < 0.2:
		out = Vector3(0, 0, 1)
	out = out.normalized()
	var need := 4.9 - flat.length()
	p.set("ext_vel", Vector3.ZERO)
	if p.get("forward_speed") != null:
		p.set("forward_speed", 0.0)
	p.call("bounce", 9.0)
	p.call("add_impulse", out * clampf(need * 1.6, 3.0, 8.0))
	if p.get("invulnerable") != null:
		p.set("invulnerable", maxf(float(p.get("invulnerable")), 1.2))
	rig.kick(-0.3)
	EnemyKit.burst(arena, global_position + Vector3(0, 1.2, 0), "dust", [Color(1, 0.97, 0.9, 0.8)], 18, 5.0)
	EnemyKit.sfx(self, "gust_whoosh", global_position)
	log_event("ring shrug: Mak pushed out")


func _on_health_changed(v: int) -> void:
	var g := _game()
	var mx := int(g.get("max_health")) if g != null and g.get("max_health") != null else 6
	# A fall at one slice refills the cake in game_state.player_fell_out without cake_empty. In the boss fight that
	# is a defeat (R3.4: the phase resets), not a free heal (r1 fun major). Flagged here, handled on the respawn.
	if v >= mx and _hp_last == 1 and fighting and not defeated:
		_fall_reset = true
	_hp_last = v


## Compile the boss's effect and P3 materials during the intro instead of at each phase start (r1 QA: 285-361 ms
## first-use hitches). Everything plays once out of sight, under the roof slab in front of the camera.
func _prewarm() -> void:
	await get_tree().create_timer(0.15).timeout
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var at := Vector3(0, -2.5, 0)
	if cam != null:
		var f := -cam.global_basis.z
		f.y = 0.0
		at = cam.global_position + f.normalized() * 8.0
		at.y = -2.5
	for kind in ["dust", "rubble", "stars", "confetti", "crumbs"]:
		EnemyKit.burst(arena, at, kind, [Color(1, 1, 1), GOLD], 3, 0.2)
	EnemyKit.poof(arena, at, 0.3, Color(0.15, 0.13, 0.13))
	EnemyKit.poof(arena, at, 0.3)
	if ResourceLoader.exists("res://scenes/fx/LandingRing.tscn"):
		FxEffect.spawn(arena, "res://scenes/fx/LandingRing.tscn", at)
	if ResourceLoader.exists("res://scenes/fx/HitStars.tscn"):
		FxEffect.spawn(arena, "res://scenes/fx/HitStars.tscn", at)
	var shock := _shockwave(at, GOLD, 0.5)
	shock.scale = Vector3.ONE * 0.2
	if phase != 3:
		if ring == null:
			_build_ring()
		# Finish pass: the full-size typhoon is 14 m tall and stood 8 m in front of the opening camera (a translucent
		# funnel over the whole intro frame). Both draw shrunk to 12 %, under the roof tiles: still drawn once for
		# the shader compile, hidden by the depth test.
		ring.visible = true
		ring.scale = Vector3.ONE * 0.12
		ring.global_position = at + Vector3(0, -0.4, 0)
		if typhoon == null:
			typhoon = BossTyphoon.new()
			typhoon.name = "TeapotTyphoon"
			arena.add_child(typhoon)
		typhoon.scale = Vector3.ONE * 0.12
		typhoon.global_position = at + Vector3(0, -0.3, 0)
		typhoon.visible = true
		await get_tree().create_timer(0.3).timeout
		if phase != 3 and is_inside_tree():
			ring.visible = false
			# Finish blocker (boss QA r1): the hidden ring pieces stayed monitorable hazards at the roof centre. Switch
			# them off and park the ring far below the roof until P3 calls _set_ring(true).
			for a in ring_pieces:
				a.set_deferred("monitorable", false)
			ring.global_position = Vector3(0, -40.0, 0)
			ring.scale = Vector3.ONE
			typhoon.visible = false
			typhoon.global_position = Vector3(0, -40.0, 0)
			typhoon.scale = Vector3.ONE
	log_event("prewarm done")


## Expanding gold torus shockwave (final hit, POP).
func _shockwave(at: Vector3, color: Color, seconds: float = 0.45, to_scale: float = 6.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 6
	mi.mesh = tm
	var m := EnemyKit.glow_mat(color, 4.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3(0.4, 0.4, 0.4)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(to_scale, to_scale * 0.35, to_scale), seconds).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, seconds).set_delay(seconds * 0.35)
	tw.chain().tween_callback(mi.queue_free)
	return mi


func _pop_bellows() -> void:
	chest_wp.set_open(false)
	_guard_next = true
	gust = {}
	_debris_due = []
	for d in debris:
		var n := d["n"] as Node3D
		if is_instance_valid(n):
			EnemyKit.burst(arena, n.global_position, "crumbs", [Color(0.97, 0.95, 0.92)], 6, 2.0)
			n.queue_free()
	debris = []
	_rasp = Curve3D.new()
	for pt in [Vector3(0, 3.1, -13.0), Vector3(8, 5, -6), Vector3(6, 6, 6), Vector3(-6, 5, 6), Vector3(-8, 4, -4), Vector3(0, 0.6, -7.5)]:
		_rasp.add_point(pt)
	# Smooth handles for a looping raspberry flight.
	for i in _rasp.point_count:
		var prev := _rasp.get_point_position(maxi(0, i - 1))
		var nxt := _rasp.get_point_position(mini(_rasp.point_count - 1, i + 1))
		var tan := (nxt - prev) * 0.25
		_rasp.set_point_in(i, -tan)
		_rasp.set_point_out(i, tan)
	set_state("raspberry")
	rig.flash(Color(1, 1, 1))
	arena.director.punctuate(false)
	EnemyKit.sfx(self, "bellows_break", global_position)
	EnemyKit.sfx(self, "cloud_puff", global_position)
	EnemyKit.popup(arena, global_position + Vector3(0, 3.6, 0), "PFFFRRT!", Color(1, 0.86, 0.3), 140, 1.4)
	bark("bark_pop", "PFFFRRT. Ahem. Pardon me.", "", true)
	arena.hud.say("The wolf let out a most ungentlemanly noise.")
	arena.page_headline("(PFFFRRT)", "", false)
	log_event("POP THE BELLOWS")


func _raspberry_tick(delta: float) -> void:
	var k := clampf(st / 2.0, 0.0, 1.0)
	anim = "float_away"
	anim_p = {"t": 0.0}
	var pos := _rasp.sample_baked(k * _rasp.get_baked_length())
	var ahead := _rasp.sample_baked(minf(1.0, k + 0.02) * _rasp.get_baked_length())
	global_position = pos - Vector3(0, 0.6, 0)
	if ahead.distance_to(pos) > 0.01:
		_face_dir(ahead - pos)
	rig.rotation.z += delta * TAU * 2.0
	if fmod(st, 0.12) < delta:
		EnemyKit.burst(arena, global_position + Vector3(0, 1.5, 0) - facing * 0.8, "dust", [Color(1, 1, 1, 0.7)], 3, 1.0)
	if k >= 1.0:
		rig.rotation.z = 0.0
		global_position = Vector3(0, 0, -7.5)
		rig.kick(0.7)
		arena.director.shake(0.4)
		EnemyKit.sfx(self, "boss_stomp", global_position)
		EnemyKit.burst(arena, global_position + Vector3(0, 0.3, 0), "dust", [Color(0.75, 0.68, 0.7)], 26, 5.0)
		steps = [{"k": "pant", "d": 3.5 if hits >= 1 else 4.5}, {"k": "hop_back", "d": 1.2}]
		step_i = -1
		set_state("p1")
		_next_step()


func _p1_hurt_tick(delta: float) -> void:
	anim = "hurt"
	anim_p = {"where": "head"}
	var k := clampf(st / 2.0, 0.0, 1.0)
	global_position = _hop_from + Vector3(0, sin(PI * clampf(st / 0.9, 0.0, 1.0)) * 1.6, 0)
	if st > 2.0:
		if hits >= HITS:
			_p1_transition()
		else:
			steps = [{"k": "hop_back", "d": 1.2}]
			step_i = -1
			set_state("p1")
			_next_step()
	_face_toward(ppos(), delta, 2.0)


func _p1_transition() -> void:
	set_state("p1_trans")
	# No debris may land after the phase is won (r1 QA: a game over in p1_trans reset Phase 1).
	gust = {}
	_debris_due = []
	for d in debris:
		var n := d["n"] as Node3D
		if is_instance_valid(n):
			EnemyKit.burst(arena, n.global_position, "crumbs", [Color(0.97, 0.95, 0.92)], 6, 2.0)
			n.queue_free()
	debris = []
	_hop(global_position, STAND, 1.2, 1.6)
	log_event("p1_transition")


func _p1_trans_tick(delta: float) -> void:
	if st < 1.2:
		anim = "hop"
		anim_p = {"k": st / 1.2}
		_hop_step(clampf(st / 1.2, 0.0, 1.0))
		_face_toward(global_position + Vector3(0, 0, 1), delta, 6.0)
		return
	anim = "sneer"
	if st - delta < 1.2:
		_land(false)
		# He flings the teacup; the trolley tips and spills 6 acorns.
		if arena.trolley != null:
			var tw := create_tween()
			tw.tween_property(arena.trolley, "rotation_degrees:z", 70.0, 0.4).set_trans(Tween.TRANS_BACK)
		for i in 6:
			EnemyKit.drop_acorns(arena, Vector3(1.2 + 0.5 * float(i), 1.2, -10.4), 1)
		EnemyKit.voice(self, "voice_wolf_huffpuff")
		bark("p2", "Then I shall PUFF!", "", true)
		arena.page_stamp("VOID")
		arena.hud.say("The wolf, quite winded, declared the chapter void on a technicality.")
		if not _dev_has("no-cine"):
			arena.director.cine("Cine_P2", Vector3(-5, 1.2, -8), Vector3(0, 2.4, -13.4), Vector3(0, 2.5, -9.5), Vector3(0, 2.6, -13.4), 50.0, 46.0, 2.5)
	if st > 3.8:
		global_position = Vector3(0, 0, -9.0)
		_enter_phase(2)


# ------------------------------------------------------------------ P2 PUFF

func _p2_tick(delta: float) -> void:
	match state:
		"p2_open":
			anim = "sneer"
			if global_position.y > 0.05 or Vector2(global_position.x, global_position.z + 9.0).length() > 0.3:
				_hop(global_position, Vector3(0, 0, -9.0), 0.8, 1.0)
				global_position = Vector3(0, 0, -9.0)
			_face_toward(ppos(), delta, 3.0)
			if st > 1.5:
				_start_paw()
		"paw":
			anim = "paw"
			var tell := 1.2 if hits == 0 else 0.9
			if st < tell * 0.55:
				_face_toward(ppos(), delta, 8.0)
			elif _line == null:
				_lock_charge(ppos())
			_dust_t -= delta
			if _dust_t <= 0.0:
				_dust_t = 0.25
				EnemyKit.burst(arena, global_position - facing * 0.4 + Vector3(0, 0.1, 0), "dust", [Color(0.8, 0.7, 0.7)], 5, 2.0)
				EnemyKit.burst(arena, global_position + facing * 0.9 + Vector3(0, 2.4, 0), "dust", [Color(1, 1, 1, 0.8)], 4, 1.5)
			if st > tell:
				if _line == null:
					_lock_charge(ppos())
				_start_charge()
		"charge":
			anim = "charge"
			var step := charge_speed * delta
			global_position += charge_dir * step
			_step_t -= delta
			if _step_t <= 0.0:
				_step_t = 0.125
				juice("boss_footstep", global_position + Vector3(0, 0.05, 0), {"speed": charge_speed})
			_dust_t -= delta
			if _dust_t <= 0.0:
				_dust_t = 0.06
				EnemyKit.burst(arena, global_position + Vector3(0, 0.1, 0), "dust", [Color(0.8, 0.7, 0.7)], 4, 2.5)
			if _feint and not _feinted and global_position.distance_to(charge_from) >= charge_len * 0.4:
				_feinted = true
				set_state("feint")
				bark("bark_feint", "Ha! Made you flinch.")
				_clear_line()
				return
			_charge_collide()
		"feint":
			anim = "feint"
			if st < 0.3:
				global_position += charge_dir * charge_speed * (0.3 - st) * delta * 2.0
			elif st < 1.0:
				_face_toward(ppos(), delta, 10.0)
				if _line == null and st > 0.3:
					_lock_charge(ppos())
			else:
				_start_charge()
		"stuck":
			anim = "stuck"
			var dur := 4.0 if hits == 0 else 3.2
			tail_wp.global_position = global_position - facing * 1.2 + Vector3(0, 0.4, 0)
			if st > dur:
				tail_wp.set_open(false)
				set_state("pull_free")
				juice("boss_recover", global_position, {"node": null})
				EnemyKit.burst(arena, global_position + facing * 1.0 + Vector3(0, 1.5, 0), "rubble", [Color(0.64, 0.27, 0.18)], 10, 4.0)
		"pull_free":
			anim = "pull_free"
			if st < 0.5:
				global_position -= facing * 2.0 * delta
			if st > 1.0:
				_start_reposition()
		"p2_hurt":
			anim = "hurt"
			anim_p = {"where": "tail"}
			if st < 0.6:
				global_position -= facing * 3.0 * delta
				global_position.y = sin(PI * st / 0.6) * 1.2
			else:
				global_position.y = 0.0
			if st > 1.6:
				if hits >= HITS:
					_p2_transition()
				else:
					_start_reposition()
		"dizzy":
			anim = "dizzy"
			if st > 1.8:
				_start_reposition()
		"soot_tumble":
			# Blasted backwards out of the bricks: a 6 m arc with a 540-degree tumble, then a soot-faced sit.
			var k := clampf(st / 0.6, 0.0, 1.0)
			if k < 1.0:
				anim = "tumble"
				global_position = _hop_from - facing * 6.0 * k + Vector3(0, sin(PI * k) * 1.5, 0)
				rig.rotation.x = -k * TAU * 1.5
			else:
				anim = "dizzy"
				rig.rotation.x = 0.0
				global_position.y = 0.0
			if st > 1.6:
				if hits >= HITS:
					_p2_transition()
				else:
					_start_reposition()
		"teeter":
			anim = "teeter"
			back_wp.global_position = global_position - facing * 0.4
			if st > 2.5:
				back_wp.set_open(false)
				set_state("pull_free")
		"dangle":
			anim = "dangle"
			global_position = _teeter_lip + Vector3(0, -1.6 + clampf((st - 1.4) / 0.6, 0.0, 1.0) * 1.6, 0)
			if st > 2.0:
				global_position = _teeter_lip - facing * 0.6
				if hits >= HITS:
					_p2_transition()
				else:
					_start_reposition()
		"reposition":
			anim = "trot"
			var to := _repo_target
			var d := to - global_position
			d.y = 0.0
			anim_p = {"speed": 6.0, "phase": st * 9.0}
			if d.length() > 0.2:
				var sp := maxf(d.length() / maxf(0.1, 1.5 - st), 4.0)
				global_position += d.normalized() * minf(sp * delta, d.length())
				_face_toward(global_position + d, delta, 10.0)
			if st > 1.5:
				_start_paw()
		"p2_trans":
			anim = "hop"
			var k := clampf(st / 1.2, 0.0, 1.0)
			anim_p = {"k": k}
			_hop_step(k)
			if k >= 1.0 and st - delta < 1.2:
				_land(false)
				bark("p3", "Hurricane it is!", "voice_wolf_laugh", true)
			if st > 1.6:
				_enter_phase(3)


var _repo_target := Vector3.ZERO


func _start_paw() -> void:
	windups += 1
	_feint = hits >= 1 and windups % 2 == 0
	_feinted = false
	charge_speed = 14.0 if hits == 0 else 16.0
	_clear_line()
	set_state("paw")
	EnemyKit.sfx(self, "enemy_windup", global_position)


func _lock_charge(target: Vector3) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.5:
		d = facing
	charge_dir = d.normalized()
	_face_dir(charge_dir)
	# Length to the parapet along the line.
	var p0 := Vector2(global_position.x, global_position.z)
	var dv := Vector2(charge_dir.x, charge_dir.z)
	var b := p0.dot(dv)
	var c := p0.length_squared() - 17.2 * 17.2
	charge_len = -b + sqrt(maxf(0.0, b * b - c))
	_clear_line()
	_line = EnemyKit.ground_strip(arena, global_position + charge_dir * 1.0 + Vector3(0, 0.04, 0), charge_dir, maxf(2.0, charge_len - 1.0), 1.7, Color(HAZARD.r, HAZARD.g, HAZARD.b, 0.5))
	EnemyKit.sfx(self, "boss_growl" if juice_has("boss_charge_start", "sfx") else "boss_charge", global_position)


func _clear_line() -> void:
	if _line != null and is_instance_valid(_line):
		EnemyKit.fade_free(_line, 0.15)
	_line = null


func _start_charge() -> void:
	set_state("charge")
	charge_from = global_position
	_step_t = 0.0
	EnemyKit.voice(self, "voice_wolf_getback")
	juice("boss_charge_start", global_position + Vector3(0, 0.1, 0), {"direction": charge_dir})
	if not juice_has("boss_charge_start", "shake"):
		arena.director.shake(0.12)
	log_event("charge dir=%s" % str(charge_dir.snapped(Vector3.ONE * 0.01)))


func _charge_collide() -> void:
	var front := global_position + charge_dir * 0.9
	for c in arena.chimneys.values():
		var ch := c as BossChimney
		if ch.footprint_has(front, ch.charge_half(), 0.35):
			_get_stuck(ch)
			return
	var r := Vector2(global_position.x, global_position.z).length()
	if r >= 16.6 or st > 3.2:
		var th := WolfRooftop.theta_of(global_position)
		_clear_line()
		if r >= 15.5 and ((th >= 64.0 and th <= 88.0) or (th >= 272.0 and th <= 296.0)):
			var east := th < 180.0
			_teeter_lip = Vector3(16.88 if east else -16.88, 0, -4.21)
			global_position = _teeter_lip - Vector3(_teeter_lip.x, 0, _teeter_lip.z).normalized() * 0.4
			_face_dir(Vector3(_teeter_lip.x, 0, _teeter_lip.z))
			set_state("teeter")
			back_wp.set_open(true)
			back_wp.global_position = global_position - facing * 0.4
			bark("bark_teeter", "Steady... steady...", "", true)
			EnemyKit.sfx(self, "skid", global_position)
			log_event("teeter")
		else:
			EnemyKit.burst(arena, global_position + charge_dir * 1.2 + Vector3(0, 0.6, 0), "rubble", [Color(0.64, 0.27, 0.18), Color(0.85, 0.73, 0.54)], 22, 6.0)
			juice("boss_chimney_smash", global_position + charge_dir * 1.2 + Vector3(0, 0.6, 0))
			if not juice_has("boss_chimney_smash", "sfx"):
				EnemyKit.sfx(self, "chimney_crash", global_position)
			if not juice_has("boss_chimney_smash", "shake"):
				arena.director.shake(0.35)
			rig.kick(0.4)
			_dizzy_acorns = false
			set_state("dizzy")
			bark("bark_parapet", "Blast this parapet!")
			log_event("dizzy (parapet)")
			# Shoulder-check (r1 fun major, probe B): a Mak standing by the stop point, on the roof or on the coping,
			# is hit and thrown back inward, so the parapet is no safe spot.
			var p := player()
			if p != null:
				var d := p.global_position - (global_position + charge_dir * 0.9)
				if Vector2(d.x, d.z).length() < 2.6 and d.y < 2.4:
					# Knockback points away from the source: a source just outside him throws him inward.
					var inward := Vector3(-p.global_position.x, 0.0, -p.global_position.z).normalized()
					p.call("take_damage", 1, p.global_position - inward * 1.5)
					_on_hurt_player("charge")
					log_event("parapet shoulder-check")


func _get_stuck(ch: BossChimney) -> void:
	stuck_chimney = ch
	_clear_line()
	set_state("stuck")
	ch.crack(charge_dir)
	rig.kick(0.5)
	juice("boss_chimney_smash", global_position + charge_dir * 1.0 + Vector3(0, 1.2, 0))
	juice("boss_stuck", global_position)
	if not juice_has("boss_chimney_smash", "shake"):
		arena.director.shake(0.45)
	if not juice_has("boss_chimney_smash", "sfx"):
		EnemyKit.sfx(self, "chimney_crash", global_position)
		EnemyKit.sfx(self, "boss_stomp", global_position)
	tail_wp.set_open(true)
	tail_wp.global_position = global_position - facing * 1.2 + Vector3(0, 0.4, 0)
	bark("bark_stuck", "This is a load-bearing face.")
	warn_once("bark_tail_warn", "Whatever you do, leave the TAIL alone.")
	log_event("stuck in %s (%s)" % [ch.label, "stump" if ch.smashed else "intact"])


func _start_reposition() -> void:
	var mp := ppos()
	var away := Vector3(-mp.x, 0, -mp.z)
	if away.length() < 0.5:
		away = Vector3(0, 0, -1)
	_repo_target = away.normalized() * 6.0
	set_state("reposition")


func _p2_transition() -> void:
	set_state("p2_trans")
	for i in 6:
		EnemyKit.drop_acorns(arena, Vector3(1.2 + 0.5 * float(i), 1.2, -10.4), 1)
	_hop(global_position, Vector3(0, 0, 0), 1.2, 3.0)
	arena.page_headline("RECOUNT?", "", true)
	arena.hud.say("The wolf demanded a recount.")
	if not _dev_has("no-cine"):
		arena.director.cine("Cine_P3", Vector3(0, 9, 12), Vector3(0, 2.5, 0), Vector3(0, 4.5, 8.0), Vector3(0, 2.2, 0), 55.0, 50.0, 2.5)
	log_event("p2_transition")


# ------------------------------------------------------------------ P3 HURRICANE

func _start_p3() -> void:
	ring_speed = 90.0
	typhoon_speed = 14.0
	vent_dur = 5.0
	hit2_armed = false
	updraft = ""
	_visits = 0
	_duds = 0
	if ring == null:
		_build_ring()
	ring.global_position = Vector3.ZERO
	ring.visible = true
	# r1 QA major: after a P3 game over the collapsed pieces stayed on the floor as live hazards. Kill any running
	# collapse tween and fly every piece back home.
	_set_ring(true)
	if typhoon == null:
		typhoon = BossTyphoon.new()
		typhoon.name = "TeapotTyphoon"
		arena.add_child(typhoon)
	typhoon_theta = 200.0
	typhoon.global_position = WolfRooftop.polar(typhoon_theta, 7.5)
	typhoon.visible = true
	typhoon.set_alpha(1.0)
	typhoon.core.set_deferred("monitorable", true)
	juice("boss_tornado_spawn", typhoon.global_position + Vector3(0, 1.0, 0), {"node": typhoon})
	# EN_crow_1 takes off from theta 340; EN_crow_2 waits on its perch until hit 1.
	for c in spectators:
		if is_instance_valid(c) and (c as BossCrow).get_meta("slot", -1) == 340:
			(c as BossCrow).take_off()
			crows.append(c)
	if arena.player != null and not arena.player.is_connected("ground_pounded", _on_ground_pounded):
		arena.player.connect("ground_pounded", _on_ground_pounded)
	active_vent = null
	vent_t = 0.0


func _build_ring() -> void:
	ring = Node3D.new()
	ring.name = "TeaTempest"
	arena.add_child(ring)
	ring.global_position = Vector3.ZERO
	var white := Color(0.97, 0.95, 0.92)
	var pot_ps: PackedScene = load("res://assets/props/boss/teapot/teapot.glb") if ResourceLoader.exists("res://assets/props/boss/teapot/teapot.glb") else null
	for i in 14:
		var tier := i % 2
		var a := TAU * float(i) / 14.0
		var r := 2.4 if tier == 0 else 3.3
		var y := 1.2 + float(i % 4) * 1.15
		var piece := Area3D.new()
		piece.monitorable = false
		piece.monitoring = false
		piece.collision_layer = 16
		piece.collision_mask = 0
		piece.add_to_group("hazard")
		piece.set_meta("damage", 1)
		piece.set_meta("knockback_up", 5.0)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.55
		cs.shape = sp
		piece.add_child(cs)
		var vis := Node3D.new()
		piece.add_child(vis)
		match i % 5:
			0:
				if pot_ps != null:
					var pot := pot_ps.instantiate() as Node3D
					pot.position = Vector3(0, -0.25, 0)
					vis.add_child(pot)
				else:
					EnemyKit.ball(vis, 0.35, Color(0.8, 0.8, 0.85), Vector3.ZERO)
			1:
				EnemyKit.cylinder(vis, 0.3, 0.22, 0.32, white, Vector3.ZERO)
				EnemyKit.ring(vis, 0.07, 0.12, white, Vector3(0.32, 0, 0), Vector3(90, 0, 0))
			2:
				EnemyKit.cylinder(vis, 0.45, 0.38, 0.06, white, Vector3.ZERO)
				EnemyKit.ring(vis, 0.38, 0.45, GOLD, Vector3(0, 0.04, 0))
			3:
				var br := EnemyKit.box(vis, Vector3(0.6, 0.3, 0.3), Color(0.64, 0.27, 0.18), Vector3.ZERO)
				br.material_override = EnemyKit.mat(Color(0.64, 0.27, 0.18), 0.9, 0.2)
			4:
				EnemyKit.box(vis, Vector3(0.42, 0.42, 0.42), Color(1, 0.99, 0.96), Vector3.ZERO)
		ring.add_child(piece)
		piece.position = Vector3(cos(a) * r, y, sin(a) * r)
		piece.set_meta("home", piece.position)
		ring_pieces.append(piece)
	# Spray of steam particles around the ring.
	var sp2 := CPUParticles3D.new()
	sp2.amount = 50
	sp2.lifetime = 1.0
	sp2.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sp2.emission_ring_axis = Vector3.UP
	sp2.emission_ring_height = 4.0
	sp2.emission_ring_radius = 3.0
	sp2.emission_ring_inner_radius = 2.2
	sp2.direction = Vector3(1, 0.2, 0)
	sp2.spread = 40.0
	sp2.initial_velocity_min = 3.0
	sp2.initial_velocity_max = 5.0
	sp2.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.97, 0.9, 0.5))
	g.set_color(1, Color(1, 0.95, 0.9, 0.0))
	sp2.color_ramp = g
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sp2.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp2.material_override = mm
	sp2.position = Vector3(0, 2.5, 0)
	ring.add_child(sp2)


func _set_ring(on: bool, collapse: bool = false) -> void:
	ring_on = on
	for a in ring_pieces:
		a.set_deferred("monitorable", on)
		var home: Vector3 = a.get_meta("home")
		if not on and not collapse:
			continue
		var old: Variant = a.get_meta("tw") if a.has_meta("tw") else null
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		var tw := a.create_tween()
		a.set_meta("tw", tw)
		if collapse and not on:
			tw.tween_property(a, "position", Vector3(home.x * 1.4, 0.3, home.z * 1.4), 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		elif on:
			tw.tween_property(a, "position", home, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _p3_tick(delta: float) -> void:
	global_position = global_position.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))
	if ring != null and ring.visible:
		ring.rotation.y += deg_to_rad(ring_speed) * delta * (1.0 if ring_on else 0.15)
	if typhoon != null and typhoon.visible:
		var cam := get_viewport().get_camera_3d()
		if state == "p3_tell" and cam != null:
			# Updraft: park the typhoon on the far side from the camera so it never covers the target (r1 spectacle).
			var far := fposmod(WolfRooftop.theta_of(cam.global_position) + 180.0, 360.0)
			typhoon_theta = rad_to_deg(lerp_angle(deg_to_rad(typhoon_theta), deg_to_rad(far), 1.0 - exp(-3.0 * delta)))
		else:
			typhoon_theta = fposmod(typhoon_theta + typhoon_speed * delta, 360.0)
		typhoon.global_position = WolfRooftop.polar(typhoon_theta, 7.5)
		if cam != null and not defeated:
			# Thin the steam when the camera is close, so a frame is never a milky wash of tornado cards.
			var cd := Vector2(cam.global_position.x - typhoon.global_position.x, cam.global_position.z - typhoon.global_position.z).length()
			var want := clampf(remap(cd, 4.0, 8.0, 0.3, 1.0), 0.3, 1.0)
			# Finish pass: also thin it while it crosses the camera-to-Mak line (a P3 frame was a brown wash over Mak).
			if arena.player != null:
				var a2 := Vector2(cam.global_position.x, cam.global_position.z)
				var b2 := Vector2(arena.player.global_position.x, arena.player.global_position.z)
				var c2 := Vector2(typhoon.global_position.x, typhoon.global_position.z)
				var ab := b2 - a2
				var k := clampf((c2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				if k > 0.0 and k < 1.0 and (a2 + ab * k).distance_to(c2) < 3.2:
					want = minf(want, 0.22)
			typhoon.set_alpha(lerpf(typhoon.alpha, want, 1.0 - exp(-8.0 * delta)))
	_dud_cd = maxf(0.0, _dud_cd - delta)
	match state:
		"p3_open":
			anim = "spin"
			rig.rotation.y += delta * 9.4
			if st > 1.5:
				set_state("p3")
				_open_vent(_pick_vent())
		"p3":
			anim = "spin"
			rig.rotation.y += delta * 9.4
			_vent_tick(delta)
		"p3_dizzy":
			anim = "dizzy"
			rig.rotation.y = lerp_angle(rig.rotation.y, 0.0, 1.0 - exp(-6.0 * delta))
			if st > 3.0:
				_clear_ring_zone()
				_set_ring(true)
				set_state("p3")
				if hits == 1 and not _warned.has("p3_after1"):
					_warned["p3_after1"] = true
					var v2 := arena.vents["V2"] as BossVent
					var v4 := arena.vents["V4"] as BossVent
					var pick := v2 if v2.global_position.distance_to(typhoon.global_position) > v4.global_position.distance_to(typhoon.global_position) else v4
					get_tree().create_timer(0.5).timeout.connect(func() -> void: _open_vent(pick))
				else:
					_open_vent(_pick_vent())
		"p3_tell":
			anim = "look_up"
			rig.rotation.y = lerp_angle(rig.rotation.y, 0.0, 1.0 - exp(-8.0 * delta))
			_updraft_tick(delta)
		"p3_cough":
			anim = "cough"
			if st > 2.0:
				_clear_ring_zone()
				_set_ring(true)
				updraft = ""
				set_state("p3")
				_open_vent(_pick_vent())
	if _launch_pending > 0.0:
		_launch_pending -= delta
		if _launch_pending <= 0.0:
			_do_plug_launch()


func _pick_vent() -> BossVent:
	var ids := ["V1", "V2", "V3", "V4"]
	var arr: Array = []
	for id in ids:
		var v := arena.vents[id] as BossVent
		if v == active_vent:
			continue
		arr.append(v)
	if _visits == 0 and active_vent == null:
		return arena.vents["V3"] as BossVent
	arr.sort_custom(func(a: BossVent, b: BossVent) -> bool:
		return a.global_position.distance_to(typhoon.global_position) > b.global_position.distance_to(typhoon.global_position))
	return arr[_rng.randi() % mini(2, arr.size())]


func _open_vent(v: BossVent) -> void:
	if active_vent != null:
		active_vent.set_active(false)
	if _next_vent != null:
		_next_vent.set_flicker(false)
	active_vent = v
	v.set_active(true)
	vent_t = 0.0
	_vent_visit = false
	_next_vent = null
	log_event("vent " + v.vid)


func _vent_tick(delta: float) -> void:
	if active_vent == null:
		return
	vent_t += delta
	# r1 fun: P3 is the last chapter, so it is the brisk one (was 5.0 / 3.5 s per vent).
	var dur := 4.2 if hits == 0 else 3.2
	if vent_t > dur - 1.0 and _next_vent == null:
		_next_vent = _pick_vent()
		_next_vent.set_flicker(true)
	var p := player()
	if p != null:
		var d := p.global_position - active_vent.global_position
		var flat := Vector2(d.x, d.z).length()
		if flat < 2.0 and not _vent_visit and absf(d.y) < 1.5:
			_vent_visit = true
			_visits += 1
			_maybe_crow_dive(active_vent.global_position)
		var grounded: bool = bool(p.get("grounded")) if p.get("grounded") != null else false
		if flat < 1.1 and grounded and d.y < 0.5 and _dud_cd <= 0.0 and not _plug_slam and _launch_pending <= 0.0:
			if not (p.has_method("is_ground_pounding") and bool(p.call("is_ground_pounding"))) and String(p.call("get_state_name")) != "slam_land":
				_dud_cd = 1.0
				_duds += 1
				active_vent.dud_puff()
				# The puff catches him: straight up over the plug, so the slam lands back on it.
				var fs: Variant = p.get("forward_speed")
				if fs != null:
					p.set("forward_speed", float(fs) * 0.15)
				p.set("ext_vel", Vector3.ZERO)
				p.call("bounce", 12.96)
				warn_once("bark_vent_warn", "Careful! Those plugs are frightfully delicate. Nobody SLAM them.")
				if _duds >= 2:
					arena.hud.say("(The plug did look awfully slammable.)")
	if vent_t > dur and _launch_pending <= 0.0 and updraft == "":
		_open_vent(_next_vent if _next_vent != null else _pick_vent())


func _on_ground_pounded(pos: Vector3) -> void:
	_last_slam_pos = pos
	if phase == 4 or state == "wedged":
		return
	# Down the Chimney (R2.3 / R3.7): a Ham Slam on the crown of the intact chimney that holds him.
	if phase == 2 and state == "stuck" and stuck_chimney != null and not stuck_chimney.smashed 			and pos.y > 4.0 and stuck_chimney.footprint_has(pos, 1.3):
		_register_hit("down the chimney")
		return
	if phase != 3 or active_vent == null or (state != "p3" and state != "p3_cough"):
		return
	var d := pos - active_vent.global_position
	if Vector2(d.x, d.z).length() < 1.25 and pos.y < 0.8:
		_plug_slam = true
		_launch_pending = 0.001


func _do_plug_launch() -> void:
	_plug_slam = false
	var p := player()
	if p == null or active_vent == null:
		return
	active_vent.pop_plug()
	p.set("ext_vel", Vector3.ZERO)
	if p.get("forward_speed") != null:
		p.set("forward_speed", 0.0)
	if p.get("side_speed") != null:
		p.set("side_speed", 0.0)
	p.call("bounce", 21.8)
	# The geyser leans in toward the wolf. r1 fun major: the fixed 3.2 m/s lean plus the spin and typhoon winds
	# landed a neutral stick on the head from V1 but 1.87 m off from V3. Now the flight is wind-free (_launch_air)
	# and the lean is scaled to the real distance, so every vent flies the same arc: it crests about 2 m short and
	# comes down over the head ring 1.37 s later. Only a SLAM scores; a passive landing just bounces off.
	var inward := Vector3(-p.global_position.x, 0.0, -p.global_position.z)
	var dist := inward.length()
	if dist > 0.1:
		var flight := 21.8 / 28.125 + sqrt(2.0 * 4.95 / 28.125)
		var lean := (dist + 0.3 * flight * flight) / flight
		p.call("add_impulse", inward / dist * lean)
	_launch_air = true
	_launch_land_t = 0.0
	arena.director.shake(0.3)
	bark("bark_plug", "No, no, not the vents!", "", true)
	log_event("plug launch from " + active_vent.vid)
	if hit2_armed:
		set_state("p3_tell")
		updraft = "tell"
		updraft_t = 0.0
		_apex_done = false
		# Was never reset, so every updraft after a miss skipped its apex beat (slow motion, centring).
		_slowmo_t = 0.0
		_set_ring(false)
		bark("bark_updraft", "Get DOWN from there!", "voice_wolf_getback", true)


func _updraft_tick(delta: float) -> void:
	updraft_t += delta
	var p := player()
	if p == null:
		return
	if updraft == "tell" and updraft_t >= 0.6:
		updraft = "column"
	if updraft == "column":
		var pp := p.global_position
		var airborne: bool = not bool(p.get("grounded"))
		if airborne and Vector2(pp.x, pp.z).length() < 3.5 and pp.y > 5.0 and pp.y < 16.0 and not _apex_done:
			_apex_done = true
			var v := maxf(6.0, sqrt(2.0 * 28.125 * maxf(0.0, 14.0 - pp.y)))
			# The column catches him and centres him over the head: the plug lean is cancelled (it carried him past
			# the axis once the launch became wind-free) and replaced by a drift that reaches the axis near the apex.
			p.set("ext_vel", Vector3.ZERO)
			p.call("bounce", v)
			p.call("add_impulse", Vector3(-pp.x, 0.0, -pp.z) / 0.9)
			updraft = "rise"
			EnemyKit.sfx(self, "gust_whoosh", pp)
			log_event("updraft bounce %.1f from y %.1f" % [v, pp.y])
	if updraft == "rise":
		var vy: float = float(p.get("vy")) if p.get("vy") != null else 0.0
		if vy <= 0.5 and _slowmo_t <= 0.0:
			_slowmo_t = 0.8
			p.set("ext_vel", Vector3.ZERO)
			arena.director.slowmo(0.8, 0.5)
			# r1 fun / spectacle majors: no fixed Cine_Updraft at the one precision moment (it remapped the steering
			# mid-air, put the camera inside the tornado and shrank Mak to 20 px). The gameplay camera stays (the
			# framing goes high and looks down at the head, see BossDirector air_pitch) with a wide FOV punch.
			arena.director.fov_punch(9.0)
			arena.director.updraft_view = true
			arena.lightning(true)
			updraft = "apex"
			log_event("updraft apex y %.2f" % p.global_position.y)
	if updraft == "apex" or updraft == "rise":
		if bool(p.get("grounded")):
			# Landed without the head: the miss and cough.
			arena.director.release_hold()
			updraft = "miss"
			set_state("p3_cough")
			log_event("updraft miss")
	if updraft_t > 6.0 and updraft != "miss":
		arena.director.release_hold()
		updraft = ""
		_clear_ring_zone()
		_set_ring(true)
		set_state("p3")
		_open_vent(_pick_vent())


func _head_marker() -> void:
	# Gold ring under Mak whenever he is above the head (P3).
	# r1 fun major: shown from the launch on (whenever Mak flies off a plug or rides the updraft), so it can be
	# steered by; it swells and brightens when he is right above the head.
	var p := player()
	if p == null or phase != 3 or defeated:
		return
	if not (state == "p3" or state == "p3_tell" or state == "p3_cough"):
		return
	var d := p.global_position - global_position
	var flat := Vector2(d.x, d.z).length()
	var airborne := not bool(p.get("grounded"))
	var flying := airborne and (_launch_air or updraft != "") and p.global_position.y > 1.5
	if flying or (flat < 1.6 and p.global_position.y > 3.6):
		var t := Time.get_ticks_msec() / 1000.0
		var over := flat < 1.4
		_gold_ring.visible = true
		_gold_ring.global_position = global_position + Vector3(0, 3.5, 0)
		var s := (1.4 / 0.95) * ((1.12 + 0.08 * sin(t * TAU * 4.0)) if over else (0.95 + 0.05 * sin(t * TAU * 2.0)))
		_gold_ring.scale = Vector3.ONE * s


func _maybe_crow_dive(at: Vector3) -> void:
	var alive: Array = []
	for c in crows:
		if is_instance_valid(c) and (c as BossCrow).mode != "dead":
			alive.append(c)
	crows = alive
	if hits == 0 and _visits <= 1:
		return
	# r1 fun minor: one crow per dive with a 4 s global cooldown (pairs on one spot stole acorns twice).
	if _crow_cd > 0.0:
		return
	var divers := 1
	var n := 0
	for c in crows:
		var cr := c as BossCrow
		if cr.mode == "orbit" and n < divers:
			cr.dive_at(at + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3)))
			n += 1
			_crow_cd = 4.0
			log_event("crow dive")


func _spawn_spectators() -> void:
	var slots := [20, 110, 160, 200, 250, 340]
	for th in slots:
		var c := BossCrow.new()
		c.boss = self
		c.perch = WolfRooftop.polar(float(th), 18.35, 0.86)
		var inward := -WolfRooftop.polar(float(th), 1.0)
		c.perch_yaw = atan2(-inward.x, -inward.z)
		c.nigel = th == 160
		c.set_meta("slot", th)
		c.name = "Crow_%d" % th
		arena.add_child(c)
		spectators.append(c)
		c.defeated_crow.connect(_on_crow_defeated)


func _on_crow_defeated(c: BossCrow) -> void:
	log_event("crow defeated")
	crows.erase(c)
	spectators.erase(c)
	# A spectator takes off 6 s later to replace it.
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if phase != 3 or defeated:
			return
		for s in spectators:
			if is_instance_valid(s) and (s as BossCrow).mode == "perch":
				(s as BossCrow).take_off()
				crows.append(s)
				return)


# ------------------------------------------------------------------ hits

func weak_hit(tag: String, kind: String, from_position: Vector3) -> bool:
	if defeated or _hit_cd > 0.0:
		return false
	match tag:
		"chest":
			if phase == 1 and state == "p1" and _cur_step_kind() == "inhale":
				var pl := player()
				if _guarded:
					if pl != null:
						var away := pl.global_position - global_position
						away.y = 0.0
						pl.call("add_impulse", away.normalized() * 6.0 + Vector3(0, 4, 0))
					rig.flash(Color(0.8, 0.85, 1.0))
					play_over("cane_guard", 0.6)
					EnemyKit.sfx(self, "enemy_block", global_position)
					EnemyKit.burst(arena, from_position + Vector3(0, 0.8, 0), "stars", [Color(0.85, 0.9, 1.0)], 10, 4.0)
					bark("bark_guard", "Not twice, Piglet.", "", true)
					log_event("cane guard deflect")
					return false
				_pop_bellows()
				return true
			return false
		"head":
			if phase == 1 and state == "p1" and _cur_step_kind() == "pant" and (kind == "stomp" or kind == "slam"):
				return _register_hit("pant " + kind)
			if phase == 3 and (state == "p3" or state == "p3_tell" or state == "p3_cough") and (kind == "stomp" or kind == "slam") and from_position.y > 2.9:
				if state == "p3_cough":
					return false
				if kind == "stomp":
					# r1 fun major: a passive landing no longer scores in P3; the rule reads "launch, drift in, SLAM".
					# He bounces off the spinning head (the player bounces on a true return) and can slam on the way down.
					_hit_cd = 0.3
					rig.kick(-0.2)
					EnemyKit.sfx(self, "gumdrop_bounce", from_position)
					bark("bark_light", "Hah! Too light! You'd need to SLAM, and you won't.", "", true)
					log_event("p3 head stomp (no hit)")
					return true
				return _register_hit("head " + kind)
		"tail":
			if phase == 2 and state == "stuck":
				if kind == "slam":
					return _register_hit("tail slam")
				if kind == "stomp":
					bark("bark_light", "Hah! Too light!")
					return true
		"back":
			if phase == 2 and state == "teeter":
				var p := player()
				if p != null:
					p.call("add_impulse", Vector3(-global_position.x, 0, -global_position.z).normalized() * 4.0)
				return _register_hit("teeter " + kind)
	return false


func _register_hit(what: String) -> bool:
	_hit_cd = 0.8
	hits += 1
	total += 1
	if hits >= HITS:
		# The phase is won: a game over from here on (transition, reel) never undoes it (r1 QA majors).
		_phase_done = true
		var pl := player()
		if pl != null and pl.get("invulnerable") != null:
			pl.set("invulnerable", maxf(float(pl.get("invulnerable")), 3.0))
	(stats["hits"] as Array).append({"t": snappedf(fight_time, 0.01), "phase": phase, "what": what})
	log_event("HIT " + what)
	hit_landed.emit(phase, hits)
	bar.set_remaining(HITS * 3 - total)
	rig.flash(Color(1, 1, 1))
	rig.kick(0.7)
	var kind := "tail" if what.begins_with("tail") else ("slam" if what.ends_with("slam") else "stomp")
	var hit_at := rig.bone_world("tail_2") if kind == "tail" else rig.bone_world("head")
	juice("boss_hit", hit_at, {"kind": kind, "impact": 12.0})
	juice("boss_recover", global_position, {"node": null})
	if not juice_has("boss_hit", "sfx"):
		EnemyKit.sfx(self, "enemy_hit", global_position)
		EnemyKit.sfx(self, "boss_stomp", global_position)
	else:
		EnemyKit.sfx(self, "boss_stomp", global_position, 1.0, -6.0)
	if not juice_has("boss_hit", "vfx") and ResourceLoader.exists("res://scenes/fx/HitStars.tscn"):
		FxEffect.spawn(arena, "res://scenes/fx/HitStars.tscn", rig.bone_world("head"))
	EnemyKit.burst(arena, rig.bone_world("head"), "stars", [GOLD, Color(1, 1, 1)], 22, 6.0)
	for c in spectators:
		if is_instance_valid(c):
			(c as BossCrow).cackle()
	var final := phase == 3 and hits >= HITS
	arena.director.punctuate(final, "boss_hit")
	match phase:
		1:
			EnemyKit.voice(self, "voice_wolf_curses" if hits == 2 else "voice_wolf_laugh")
			head_wp.set_open(false)
			arena.page_headline("BOUNCED\nBACK" if hits == 1 else "PIG BOUNCED\nBACK", "", true)
			if hits == 1:
				arena.hud.say("Chapter One. The wolf huffed, and the little pig bounced on the wolf's head. Rather rudely.")
			_hop_from = Vector3(global_position.x, 0, global_position.z)
			set_state("p1_hurt")
			bark("hit", "OWOOOO!", "", true)
		2:
			EnemyKit.voice(self, "voice_wolf_tail")
			tail_wp.set_open(false)
			back_wp.set_open(false)
			if what.begins_with("down"):
				stuck_chimney.belch(1.2)
				EnemyKit.poof(arena, global_position + facing * 1.2 + Vector3(0, 1.6, 0), 2.2, Color(0.12, 0.1, 0.1))
				EnemyKit.burst(arena, global_position + facing * 1.0 + Vector3(0, 1.6, 0), "dust", [Color(0.08, 0.07, 0.07), Color(0.2, 0.18, 0.18)], 40, 7.0)
				EnemyKit.drop_acorns(arena, stuck_chimney.global_position - facing * 1.2 + Vector3(0, 1.4, 0), 3)
				arena.page_headline("THE PIG
STOPS THE WOLF", "", true)
				arena.hud.say("The pig came down the chimney instead. That is not how the story goes.")
				bark("bark_down", "That is NOT how it goes!", "", true)
				_hop_from = global_position
				set_state("soot_tumble")
			elif what.begins_with("tail"):
				if stuck_chimney != null:
					stuck_chimney.smash()
				arena.page_headline("A CHIMNEY\nSTOPS THE WOLF", "", true)
				arena.hud.say("Chapter Two. The wolf charged like a gentleman bull, and a chimney stopped him. Face first.")
				_smoking_tail()
				set_state("p2_hurt")
			else:
				arena.page_headline("THE EDGE\nSTOPS THE WOLF", "", true)
				arena.hud.say("Chapter Two. The wolf charged like a gentleman bull, and the edge of the roof very nearly did.")
				bark("bark_dangle", "I meant to do that.", "", true)
				set_state("dangle")
		3:
			if final:
				_begin_defeat()
			else:
				EnemyKit.voice(self, "voice_wolf_curses")
				arena.page_headline("PIG FROM\nABOVE", "", true)
				arena.hud.say("Chapter Three. The wolf became a hurricane, and the little pig came down on him like a dropped piano.")
				_set_ring(false, true)
				if active_vent != null:
					active_vent.set_active(false)
				if _next_vent != null:
					_next_vent.set_flicker(false)
				active_vent = null
				_next_vent = null
				ring_speed = 120.0
				typhoon_speed = 18.0
				hit2_armed = true
				for c in spectators:
					if is_instance_valid(c) and (c as BossCrow).get_meta("slot", -1) == 20 and (c as BossCrow).mode == "perch":
						(c as BossCrow).take_off()
						crows.append(c)
				set_state("p3_dizzy")
	return true


func _smoking_tail() -> void:
	var sm := CPUParticles3D.new()
	sm.amount = 16
	sm.lifetime = 1.2
	sm.direction = Vector3.UP
	sm.initial_velocity_min = 0.8
	sm.initial_velocity_max = 1.4
	sm.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 0.28, 0.3, 0.6))
	g.set_color(1, Color(0.4, 0.38, 0.4, 0.0))
	sm.color_ramp = g
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	sm.mesh = s
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material_override = m
	rig.attach("tail_4", sm)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(sm):
			sm.emitting = false)


func _update_markers(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.9 + 0.1 * sin(t * TAU * 2.0)
	var pant := phase == 1 and state == "p1" and _cur_step_kind() == "pant"
	# Only P1 owns the ring here; P3 (_head_marker) and the wedged belly (_defeat_tick) drive it themselves. The old
	# unconditional write switched the P3 slam ring off every frame (r1 fun major).
	if phase == 1 and not defeated:
		_gold_ring.visible = pant
	elif phase == 3 and not defeated:
		_gold_ring.visible = false
	if _pant_decal.visible and not (phase == 1 and state == "p1" and _cur_step_kind() in ["hop_down", "pant"]):
		_pant_decal.visible = false
	if _pant_decal.visible:
		_pant_decal.scale = Vector3(1.0, 0.15, 1.0) * (0.92 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.0))
	if pant:
		_gold_ring.global_position = global_position + Vector3(0, 1.85, 0) + facing * 0.35
		_gold_ring.scale = Vector3.ONE * pulse
		head_wp.global_position = global_position + Vector3(0, 0.9, 0) + facing * 0.35
	if phase == 3:
		head_wp.global_position = global_position + Vector3(0, 2.6, 0)
		head_wp.set_open(state == "p3" or state == "p3_tell")
		(head_wp.shape_node.shape as CylinderShape3D).radius = 1.4
		(head_wp.shape_node.shape as CylinderShape3D).height = 0.8
		head_wp.shape_node.position = Vector3(0, 0.4, 0)
	_tail_ring.visible = state == "stuck"
	if _tail_ring.visible:
		_tail_ring.global_position = global_position - facing * 1.2 + Vector3(0, 1.0, 0)
		_tail_ring.scale = Vector3.ONE * pulse
	# Body collision follows the pose.
	var cap := body_cs.shape as CapsuleShape3D
	var h := 3.0
	if anim == "pant":
		h = 2.0
	elif state == "stuck":
		h = 2.2
	elif state == "dangle" or state == "drift" or state == "wedged" or state == "popped" or state == "swell":
		h = 2.0
	if absf(cap.height - h) > 0.01:
		cap.height = h
		body_cs.position = Vector3(0, h * 0.5, 0)
	body_cs.disabled = state == "dangle" or state == "drift" or state == "wedged" or state == "popped" or state == "swell" or anim == "pant"


# ------------------------------------------------------------------ defeat

func _begin_defeat() -> void:
	defeated = true
	set_state("swell")
	log_event("final hit: swell")
	head_wp.set_open(false)
	updraft = ""
	_launch_air = false
	arena.director.updraft_view = false
	# Impact frame on the final hit (r1 spectacle major): a white flash, a gold shockwave on the head and a small
	# upward camera snap, on top of the Juice boss_hit (big) and the director's punctuation.
	arena.director.flash(Color(1, 1, 1), 0.07)
	_shockwave(rig.bone_world("head"), GOLD, 0.5, 7.0)
	_shockwave(rig.bone_world("head") + Vector3(0, -0.4, 0), Color(1, 1, 1), 0.35, 4.0)
	arena.director.shake(0.6, 0.35)
	_gold_ring.visible = false
	arena.page_headline("SKY FALLS\nON WOLF", "", true)
	arena.hud.say("The wolf huffed the pig up to the clouds, and the pig came down like the whole sky.")
	EnemyKit.voice(self, "voice_wolf_curses")
	# Every P3 hazard shuts down.
	_set_ring(false, true)
	if active_vent != null:
		active_vent.set_active(false)
	if _next_vent != null:
		_next_vent.set_flicker(false)
	active_vent = null
	if typhoon != null:
		juice("boss_tornado_end", typhoon.global_position, {"node": typhoon})
		var tw := create_tween()
		tw.tween_method(typhoon.set_alpha, 1.0, 0.0, 1.2)
		tw.tween_callback(func() -> void:
			typhoon.visible = false
			typhoon.core.set_deferred("monitorable", false))
	for c in crows:
		if is_instance_valid(c):
			var cr := c as BossCrow
			cr.mode = "perch"
	# The storm look stays until the POP (r1 spectacle: clearing it at the swell made the climax flat yellow before
	# the last hit); set_phase_look(4) now runs in _pop().
	# Cork chimney: C4 if intact, else the intact one nearest bearing 310.
	cork = null
	var c4 := arena.chimneys["C4"] as BossChimney
	if not c4.smashed:
		cork = c4
	else:
		var best := 1e9
		for id in arena.chimneys.keys():
			var ch := arena.chimneys[id] as BossChimney
			if ch.smashed:
				continue
			var th := WolfRooftop.theta_of(ch.global_position)
			var dd := absf(angle_difference(deg_to_rad(th), deg_to_rad(310.0)))
			if dd < best:
				best = dd
				cork = ch
	if cork == null:
		cork = c4
		cork.restore()
	cork_u = (Vector3.ZERO - cork.global_position)
	cork_u.y = 0
	cork_u = cork_u.normalized()
	belly = cork.global_position + cork_u * 1.9 + Vector3(0, 3.6, 0)
	# Held Cine_Swell from the first frame of the defeat (r1 spectacle blocker: the swell and drift played off the top
	# of the gameplay frame). A side view of the centre-to-cork line, low, tracking the wolf through the drift.
	var side := Vector3(-cork_u.z, 0, cork_u.x)
	var mid := cork.global_position * 0.5
	var cand_a := mid + side * 11.0
	var cand_b := mid - side * 11.0
	_swell_cam = (cand_a if cand_a.z >= cand_b.z else cand_b) + Vector3(0, 2.2, 0)
	arena.director.framing = false
	arena.director.hold("Cine_Swell", _swell_cam, _swell_look(), 55.0, 0.35)


var _swell_cam := Vector3.ZERO
var _exit_cam := Vector3.ZERO
var _exit_to := Vector3.ZERO


func _swell_look() -> Vector3:
	var top := cork.global_position + Vector3(0, 4.4, 0)
	return (global_position + Vector3(0, 2.4, 0)).lerp(top, 0.4)


func _defeat_tick(delta: float) -> void:
	var p := player()
	match state:
		"swell":
			anim = "swell"
			anim_p = {"k": clampf(st / 1.2, 0.0, 1.0)}
			global_position = global_position.lerp(Vector3(0, 0.3, 0), 1.0 - exp(-3.0 * delta))
			arena.director.hold_track(_swell_cam, _swell_look())
			if st > 1.4:
				set_state("drift")
				_hop_from = global_position
				log_event("drift to " + cork.label)
		"drift":
			anim = "swell"
			anim_p = {"k": 1.0}
			var k := clampf(st / 2.0, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var to := cork.global_position + cork_u * 0.6 + Vector3(0, 3.0, 0)
			global_position = _hop_from.lerp(to, e) + Vector3(0, sin(PI * k) * 3.0, 0)
			_face_toward(global_position + cork_u, delta, 4.0)
			arena.director.hold_track(_swell_cam, _swell_look())
			if k >= 1.0:
				set_state("wedged")
				rig.kick(0.6)
				EnemyKit.sfx(self, "boss_stomp", global_position)
				EnemyKit.burst(arena, cork.global_position + Vector3(0, 4.6, 0), "dust", [Color(0.12, 0.1, 0.1)], 30, 4.0)
				cork.belch(1.5)
				arena.hud.say("The wolf, stuck fast, was entirely at the mercy of...")
				arena.director.framing = false
				_cork_camera()
				log_event("wedged")
		"wedged":
			anim = "wedged"
			_boing = maxf(0.0, _boing - delta * 4.0)
			anim_p = {"boing": _boing}
			_face_dir(cork_u)
			_gold_ring.visible = true
			_gold_ring.global_position = belly + Vector3(0, 2.4, 0)
			_gold_ring.scale = Vector3.ONE * (1.6 + 0.15 * sin(st * TAU * 2.0))
			_belly_cd = maxf(0.0, _belly_cd - delta)
			if st > 6.0 and not _warned.has("cork_hint"):
				_warned["cork_hint"] = true
				arena.hud.say("(a Ham Slam, perhaps?)")
				bark("bark_belly_idle", "Don't you DARE.", "", true)
			if p != null and _belly_cd <= 0.0:
				_belly_rules(p)
			if st > 15.0 and not popped:
				# Fallback: Mak is placed above the belly and the slam is made for him.
				log_event("cork fallback")
				p.call("respawn", Transform3D(Basis(), belly + Vector3(0, 2.0, 0)))
				_pop()
		"popped":
			# r1 spectacle major: a 3.8 s exit the camera follows (was 2.5 s and a speck), a slower spin so the pose
			# reads, a sputtering puff trail and a twinkle star where he vanishes.
			anim = "float_away"
			var k := clampf(st / 3.8, 0.0, 1.0)
			global_position = _hop_from.lerp(_exit_to, k * k)
			rig.rotation += Vector3(delta * 1.6, delta * 2.6, delta * 1.0)
			rig.scale = Vector3.ONE * lerpf(1.0, 0.55, k)
			_trail_t -= delta
			if _trail_t <= 0.0 and visible:
				_trail_t = 0.09
				EnemyKit.burst(arena, rig.bone_world("tail_2"), "dust", [Color(1, 0.98, 0.94, 0.85), Color(0.9, 0.86, 0.8, 0.7)], 3, 1.2)
				if fmod(st, 0.45) < delta:
					EnemyKit.sfx(self, "cloud_puff", global_position, randf_range(1.2, 1.5), -10.0)
			if _bark_label.visible:
				_bark_label.global_position = global_position + Vector3(0, 3.0, 0)
			if visible:
				var push := clampf(st / 3.8, 0.0, 1.0)
				var cam_pos := _exit_cam + (_exit_cam - global_position).normalized() * push * 3.0 + Vector3(0, push * 1.2, 0)
				arena.director.hold_track(cam_pos, global_position + Vector3(0, 1.5, 0))
			if st > 3.8 and visible:
				visible = false
				_twinkle(global_position + Vector3(0, 1.5, 0))
				bar.hide_bar()
				boss_defeated.emit()
			if st > 4.6 and arena.director.hold_cam_id == "Cine_Exit":
				arena.director.release_hold()
				arena.director.framing = true


func _cork_camera() -> void:
	# r1 spectacle blocker: frame the head AND the belly (look above the belly so the head sits in the upper third),
	# from a little further out and lower; the HUD and boss bar are hidden during holds.
	var u_side := Vector3(-cork_u.z, 0, cork_u.x)
	var pos := cork.global_position + cork_u * 9.0 + u_side * 2.5 + Vector3(0, 3.6, 0)
	arena.director.hold("Cine_Defeat_Soft", pos, belly + Vector3(0, 1.3, 0), 55.0, 0.8)


var _trail_t := 0.0


## A cartoon twinkle where the wolf vanishes over the horizon.
func _twinkle(at: Vector3) -> void:
	var star := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	star.mesh = qm
	var m := EnemyKit.glow_mat(Color(1.0, 0.95, 0.7), 6.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	star.material_override = m
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(star)
	star.global_position = at
	star.scale = Vector3.ONE * 0.2
	var tw := star.create_tween()
	tw.tween_property(star, "scale", Vector3.ONE * 4.5, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(star, "rotation:z", PI * 0.5, 0.5)
	tw.tween_property(star, "scale", Vector3.ONE * 0.05, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(star.queue_free)
	EnemyKit.burst(arena, at, "stars", [Color(1, 0.95, 0.7), Color(1, 1, 1)], 14, 5.0)
	EnemyKit.sfx(self, "truffle_sparkle", at, 1.0, -4.0)


func _belly_rules(p: Node3D) -> void:
	var feet := p.global_position
	var chest := feet + Vector3(0, 0.6, 0)
	var slam := p.has_method("is_ground_pounding") and bool(p.call("is_ground_pounding"))
	if slam and feet.y >= belly.y - 0.3 and feet.distance_to(belly) < 2.1:
		_pop()
		return
	if chest.distance_to(belly) < 2.0:
		_belly_cd = 0.35
		if chest.y >= belly.y - 0.3:
			var fs: Variant = p.get("forward_speed")
			if fs != null:
				p.set("forward_speed", float(fs) * 0.25)
			p.call("bounce", 18.0)
			_boing = 1.0
			rig.kick(-0.3)
			EnemyKit.sfx(self, "gumdrop_bounce", belly)
			bark("bark_belly", "Unhand my waistcoat!")
			log_event("belly boing")
		elif feet.y < 0.6 and chest.y < belly.y - 0.9:
			p.call("add_impulse", cork_u * 6.0 + Vector3(0, -3, 0))
			EnemyKit.sfx(self, "leaf_bounce", belly)


func _pop() -> void:
	if popped:
		return
	popped = true
	log_event("POP")
	_gold_ring.visible = false
	juice("boss_defeat", belly, {"node": self})
	arena.director.punctuate(true, "boss_defeat")
	EnemyKit.sfx(self, "bellows_break", global_position)
	EnemyKit.sfx(self, "cloud_puff", global_position)
	EnemyKit.voice(self, "voice_wolf_notlast")
	# The exit camera: near the cork, on the open side, pushing out as he sputters off (Cine_Exit, tracked).
	var u_side := Vector3(-cork_u.z, 0, cork_u.x)
	_exit_cam = cork.global_position + cork_u * 6.5 + u_side * 2.2 + Vector3(0, 2.6, 0)
	_exit_to = global_position + (STORM_TARGET - global_position).normalized() * 55.0
	# r1 spectacle blocker: the POP was a wall of opaque 2.9 m soot balls in front of the camera. Now a 2-frame white
	# flash, a gold and a cream shockwave ring, a small half-transparent soot puff BEHIND the belly (away from the
	# camera), gold and burgundy confetti and six brass waistcoat buttons pinging off with sparkles.
	arena.director.flash(Color(1, 1, 1), 0.07)
	_shockwave(belly, GOLD, 0.55, 8.0)
	_shockwave(belly + Vector3(0, 0.3, 0), CREAM, 0.4, 5.0)
	var away := belly - _exit_cam
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -cork_u
	EnemyKit.poof(arena, belly + away * 0.9, 1.1, Color(0.22, 0.2, 0.2, 0.5))
	EnemyKit.burst(arena, belly, "confetti", [GOLD, Color("7a1f2e"), Color("d4a62a")], 60, 9.0)
	EnemyKit.burst(arena, belly, "stars", [GOLD, Color(1, 1, 1)], 24, 7.0)
	# Buttons ping off.
	for i in 6:
		var b := EnemyKit.ball(arena, 0.13, GOLD, belly + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), 0), Vector3(1, 0.45, 1))
		b.material_override = EnemyKit.glow_mat(GOLD, 1.6)
		var to := belly + Vector3(randf_range(-6, 6), -belly.y + 0.08, randf_range(-6, 6))
		var tw := b.create_tween()
		tw.set_parallel(true)
		tw.tween_property(b, "global_position", to, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "rotation", Vector3(randf_range(6, 14), randf_range(6, 14), 0), 0.9)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(b):
				EnemyKit.burst(arena, b.global_position + Vector3(0, 0.1, 0), "stars", [GOLD], 4, 1.5))
		tw.chain().tween_interval(2.0)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(b):
				EnemyKit.fade_free(b, 0.3))
	var p := player()
	if p != null:
		p.call("bounce", 12.0)
	bark("defeat", "Curses, Piglet!", "voice_wolf_curses", true)
	arena.page_headline("WOLF,
CORKED", "The End?", true)
	arena.hud.say("And the wolf lived... somewhere else.")
	_hop_from = global_position
	set_state("popped")
	boss_popped.emit()
	_spawn_prizes()
	cork.belch(2.0)
	# The storm clears now, at the payoff (it cleared at the swell before).
	arena.set_phase_look(4)
	if not _dev_has("no-cine"):
		arena.director.hold("Cine_Exit", _exit_cam, belly, 52.0, 0.25)
	else:
		arena.director.release_hold()
		arena.director.framing = true


func _spawn_prizes() -> void:
	# The Great Truffle arcs out of the waistcoat to the centre on a golden beam; the folded hat beside it.
	# A gold stand-in flies the arc; the collectable truffle appears where it lands.
	var flyer := Node3D.new()
	var fb := EnemyKit.ball(flyer, 0.45, GOLD, Vector3.ZERO, Vector3(1, 0.85, 1))
	fb.material_override = EnemyKit.glow_mat(GOLD, 2.0)
	arena.add_child(flyer)
	flyer.global_position = belly
	var tw := flyer.create_tween()
	tw.tween_method(func(k: float) -> void:
		var pos := belly.lerp(TRUFFLE_AT + Vector3(0, 1.2, 0), k)
		pos.y += sin(PI * k) * 5.0
		flyer.global_position = pos
		flyer.rotation.y = k * TAU * 3.0, 0.0, 1.0, 1.6)
	tw.tween_callback(func() -> void:
		flyer.queue_free()
		var t: Node3D
		if ResourceLoader.exists("res://scenes/objects/Truffle.tscn"):
			t = (load("res://scenes/objects/Truffle.tscn") as PackedScene).instantiate() as Node3D
			t.set("truffle_id", "BOSS-1")
			t.set("mission_title", "The Great Truffle")
			t.set("spawn_revealed", true)
		else:
			t = Node3D.new()
			EnemyKit.ball(t, 0.5, GOLD, Vector3(0, 1.0, 0))
		t.name = "GreatTruffle"
		arena.add_child(t)
		t.scale = Vector3.ONE * 1.6
		t.global_position = TRUFFLE_AT
		_truffle = t
		EnemyKit.burst(arena, TRUFFLE_AT + Vector3(0, 1.2, 0), "stars", [GOLD, Color(1, 1, 0.8)], 30, 7.0)
		if ResourceLoader.exists("res://scenes/fx/TruffleBurst.tscn"):
			FxEffect.spawn(arena, "res://scenes/fx/TruffleBurst.tscn", TRUFFLE_AT + Vector3(0, 1.2, 0)))
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 0.8
	cm.height = 30.0
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := EnemyKit.glow_mat(Color(1.0, 0.85, 0.4, 0.22), 1.6)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(beam)
	beam.global_position = TRUFFLE_AT + Vector3(0, 15.0, 0)
	beam.name = "GoldenBeam"
	EnemyKit.sfx(self, "truffle_get", belly)
	var hp := "res://assets/characters/mak/mak_tophat.glb"
	if ResourceLoader.exists(hp):
		_hat = Node3D.new()
		_hat.name = "FoldedTopHat"
		var h := (load(hp) as PackedScene).instantiate() as Node3D
		h.rotation_degrees.y = 180.0
		_hat.add_child(h)
		GoldenHatLib.gild(h, true)
		GoldenHatLib.sparkle(_hat, true, 0.5, Vector3(0, 0.3, 0))
		arena.add_child(_hat)
		_hat.global_position = belly
		_hat.scale = Vector3(1.6, 0.4, 1.6)
		var htw := _hat.create_tween()
		htw.tween_method(func(k: float) -> void:
			var to := Vector3(0.8, 0.0, 0.3)
			var pos := belly.lerp(to, k)
			pos.y += sin(PI * k) * 4.0
			_hat.global_position = pos
			_hat.rotation.y = k * TAU * 2.0, 0.0, 1.0, 1.4)
		htw.tween_property(_hat, "scale", Vector3(1.6, 1.6, 1.6), 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_truffle(id: String) -> void:
	if id != "BOSS-1":
		return
	log_event("truffle BOSS-1 collected")
	var g := _game()
	if g != null and g.has_method("unlock"):
		g.call("unlock", GoldenHatLib.ID)
	var beam := arena.get_node_or_null("GoldenBeam") as Node3D
	if beam != null:
		EnemyKit.fade_free(beam, 0.5)
	# The world pauses for TRUFFLE GET!; the outro runs after it.
	await get_tree().create_timer(arena.celebration_seconds + 0.2, true).timeout
	while get_tree().paused:
		await get_tree().process_frame
	_outro()


func _outro() -> void:
	var p := player()
	log_event("outro: golden top hat")
	if _hat != null and is_instance_valid(_hat):
		var tw := _hat.create_tween()
		tw.tween_property(_hat, "scale", Vector3.ZERO, 0.25)
	if p != null and p.has_method("set_hat"):
		p.call("set_hat", GoldenHatLib.ID)
		EnemyKit.sfx(self, "hat_on", p.global_position + Vector3(0, 1.2, 0))
	# r1 QA major: persist the reward, so Mak walks into the hub in the hat he just earned (DESIGN_V2: "Mak gains
	# the top hat"). Game.set_hat validates against available_hats() and saves atomically.
	var g := _game()
	if g != null and g.has_method("set_hat"):
		if g.has_method("is_unlocked") and not bool(g.call("is_unlocked", GoldenHatLib.ID)) and g.has_method("unlock"):
			g.call("unlock", GoldenHatLib.ID)
		g.call("set_hat", GoldenHatLib.ID)
	EnemyKit.voice(self, "voice_mak_tophat")
	var a := get_node_or_null("/root/Audio")
	if a != null and a.has_method("play_jingle"):
		a.call("play_jingle", "music_victory")
	arena.page_headline("THE END\n(PROPERLY)", "The Wolf's Own Tale")
	arena.hud.say("THE END (properly). The Golden Top Hat is yours!")
	var mp := p.global_position if p != null else Vector3.ZERO
	if p != null and p.get("facing_yaw") != null:
		# r1 spectacle major: the outro offset assumed Mak faced +Z, so it often showed the back of his head. Turn him
		# to face the camera (south, the golden beam behind him) before the shot.
		p.set("facing_yaw", PI)
		if p.has_method("reset_physics_interpolation"):
			p.call("reset_physics_interpolation")
	var ledger :="TIME %d:%02d   SLICES LOST %d" % [int(fight_time) / 60, int(fight_time) % 60, int(stats["slices_lost"])]
	arena.hud.say("THE END (properly).   GOLDEN TOP HAT WON   " + ledger, 6.0)
	arena.director.cine("Cine_Outro", mp + Vector3(1.2, 1.1, 2.8), mp + Vector3(0, 1.0, 0), mp + Vector3(1.0, 1.0, 2.4), mp + Vector3(0, 1.05, 0), 35.0, 32.0, 3.5)
	if p != null and p.has_method("celebrate"):
		p.call("celebrate", 3.0)
	await arena.director.cine_finished
	boss_defeated.emit()
	var dev := get_node_or_null("/root/Dev")
	if dev != null and bool(dev.call("has_arg", "boss-stay")):
		return
	var r := get_node_or_null("/root/Router")
	if r != null and r.has_method("go_to_hub"):
		r.call("go_to_hub", "From_BOSS")


# ------------------------------------------------------------------ retries

func _on_respawned() -> void:
	stats["falls"] = int(stats["falls"]) + 1
	if defeated:
		return
	if _fall_reset:
		# A fall on the last slice counts as an empty cake (r1 fun major): the phase resets, the cake is full.
		_fall_reset = false
		log_event("fell out on the last slice: treated as cake empty")
		_on_cake_empty()
	_falls_seen += 1
	if _falls_seen == 1:
		# The page gag plays on the first fall only (r1 fun minor: retry friction).
		arena.page_headline("THE END", "", false)
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			arena.page_headline("...OR NOT", "", true))
	bark("bark_respawn", "Back for seconds?", "voice_wolf_blownaway")
	log_event("player respawned (hits %s)" % ("reset" if _retry else "kept"))


func _on_cake_empty() -> void:
	# A real defeat resets the phase (R3.4): hits 0, chimneys restored in P2.
	if defeated:
		return
	if _phase_done or hits >= HITS or state in ["p1_trans", "p2_trans", "p3_trans"]:
		# r1 QA majors: the final hit of a phase already landed (p1_trans, p2_hurt, dangle, soot tumble). The phase
		# stays won; the transition runs on and the next phase starts as usual.
		log_event("cake empty after the phase was won: no reset")
		return
	log_event("cake empty: phase reset")
	_retry = true
	total -= hits
	hits = 0
	bar.set_remaining(HITS * 3 - total)
	head_wp.set_open(false)
	tail_wp.set_open(false)
	back_wp.set_open(false)
	gust = {}
	_clear_line()
	if phase == 2:
		for c in arena.chimneys.values():
			(c as BossChimney).restore()
	if phase == 3:
		hit2_armed = false
		updraft = ""
		_launch_air = false
		_launch_pending = 0.0
		_plug_slam = false
		ring_speed = 90.0
		typhoon_speed = 14.0
		arena.director.release_hold()
		arena.director.updraft_view = false
	if phase == 1:
		global_position = STAND
	set_state("respawn_wait")
