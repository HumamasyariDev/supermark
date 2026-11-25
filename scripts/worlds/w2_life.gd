extends Node3D
## W2 Beanstalk Skyway: motion and ambient life (owned by the W2 world builder).
## Runs the Beanpod Lift, the sleeping Giant and his snore cycle, the pocket-watch hand, bouncy-leaf
## squash, the bean flower petals, banners, drifting cloud layers, local lights and ambient FX.

const M := preload("res://scripts/worlds/w2_mesh.gd")
const GIANT_PATHS := [
	"res://assets/characters/sleeping_giant/sleeping_giant_v2.glb",
	"res://assets/characters/sleeping_giant/sleeping_giant.glb",
	"res://assets/characters/giant/giant.glb",
	"res://assets/props/w2/sleeping_giant/sleeping_giant.glb",
	"res://assets/props/w2/giant/giant.glb",
]
const COW_PATHS := [
	"res://assets/characters/daisy_cow/daisy_cow_v2.glb",
	"res://assets/characters/daisy_cow/daisy_cow.glb",
	"res://assets/characters/cow/cow.glb",
	"res://assets/props/w2/daisy_cow/daisy_cow.glb",
]

var world: Node3D
var data: Dictionary
var b
var play
var t := 0.0
var player: Node3D

# Lift
var lift_unlocked := false
var lift_state := "top_wait"
var lift_timer := 0.0
const LIFT_BOTTOM := 0.3
const LIFT_TOP := 24.0
const LIFT_SPEED := 3.0

# Giant
var giant: Node3D
var giant_head: Node3D
var giant_body: Node3D
var giant_cap: Node3D
var zzz: Node3D
var pompom: Node3D
var beard_mesh: MeshInstance3D
var talk_label: Label3D
var _snore_cycles := 0
var _talk_timer := 0.0
const HEAD_POS := Vector3(-10.9, 57.0, -34.0)
const GIANT_ORIGIN := Vector3(-13.0, 55.6, -34.0)
const GIANT_SCALE := 0.8
var head_pos := HEAD_POS
var giant_skel: Skeleton3D
const BEARD_POS := Vector3(-9.6, 55.9, -32.4)
const POMPOM_POS := Vector3(-12.6, 59.6, -36.2)
const CP6 := Vector3(3.2, 54.45, -34.0)
var _last_phase := ""
# Round 1 state
var wolf_beaten := false
var goose_freed := false
var e16: Node
var bell: AnimatableBody3D
var bell_pivot := Vector3(-13.0, 66.5, -16.0)
var bell_angle := 0.0
var flower_forced := false
var sprouted := false
var hat_said := false
var droops: Array = []      # [body, base_pos, yaw_basis, timer, sag, standing_off]
var movers: Array = []      # [body, base, dir, amp, period, phase]
var lift2_unlocked := false
var lift2_state := "top_wait"
var lift2_timer := 0.0
# Watch
var minute_hand: AnimatableBody3D
var hand_pivot := Vector3.ZERO
# Flower
var petals: Array[Node3D] = []
var flower_open := 0.0
var bell_rung := false
# Misc
var banners: Array[Node3D] = []
var layers: Array[Node3D] = []
var bouncy_visuals := {}
var cloud_bell: Node3D
var far_islet: Node3D
var birds: Array[Node3D] = []


func setup(w: Node3D, d: Dictionary, builder, gameplay) -> void:
	world = w
	data = d
	b = builder
	play = gameplay
	_giant()
	_watch()
	_flower()
	_cloud_bell()
	_lights()
	_ambient_fx()
	_birds()
	_allotment_trigger()
	_r1_setup()
	_r2_setup()
	# Fix round 1: camera hints CH0-CH7 and the leaf fade (w2_camera.gd), placement self-check, fix-round systems.
	var camn: Node = (load("res://scripts/worlds/w2_camera.gd") as GDScript).new()
	camn.name = "W2Camera"
	add_child(camn)
	camn.call("setup", world, b)
	_fix1_setup()
	get_tree().create_timer(0.6, false).timeout.connect(_check_placement)
	_perf_pass.call_deferred()
	# Round 3 (P2): the seed-parachute descent after W2-8.
	var descent: Node = (load("res://scripts/worlds/w2_descent.gd") as GDScript).new()
	descent.name = "W2Descent"
	add_child(descent)
	descent.call("setup", world, data)
	var bn := world.get_node_or_null("Level/Castle/Banners")
	if bn:
		for c in bn.get_children():
			banners.append(c)
	var cp := world.get_node_or_null("Level/CloudPuffs")
	if cp:
		for c in cp.get_children():
			if String(c.name).begins_with("Clouds_layer") or String(c.name).begins_with("Clouds_sea"):
				layers.append(c)
	far_islet = b.visuals.get("FAR_ISLET")
	for id in b.plat.keys():
		if String(b.plat[id]["kind"]) == "bouncy_leaf" and b.visuals.has(id):
			bouncy_visuals[b.bodies[id]] = b.visuals[id]
	if play and play.nodes.has("GooseCage"):
		var cage: Node = play.nodes["GooseCage"]
		if cage.has_signal("opened"):
			cage.connect("opened", _on_goose_freed)
		for sid in ["Switch_S1", "Switch_S2", "Switch_S3"]:
			var swn := _pn(sid)
			if swn and swn.has_signal("pressed"):
				swn.connect("pressed", _on_goose_switch)
	if play and play.snore:
		play.snore.connect("phase_changed", _on_snore_phase)
	if play and play.nodes.has("CloudHopper"):
		var tt: Node = play.nodes["CloudHopper"]
		var fin := tt.get_node_or_null("FinishGate")
		if fin:
			for gv in fin.find_children("GateVisual", "", true, false):
				(gv as Node3D).visible = false
		if tt.has_signal("started"):
			tt.connect("started", func() -> void: print("[W2] Cloud Hopper started; player at ", player.global_position if player else Vector3.ZERO))
		if tt.has_signal("succeeded"):
			tt.connect("succeeded", func(_x: float) -> void: _ring_bell())
	var game := get_node_or_null("/root/Game")
	if game and game.has_signal("truffle_collected"):
		game.connect("truffle_collected", func(id: String) -> void: print("[W2] TRUFFLE COLLECTED %s at %s" % [id, player.global_position if player else Vector3.ZERO]))
	if world.has_signal("player_spawned"):
		world.connect("player_spawned", _on_player_spawned)


func _on_player_spawned(p: Node3D) -> void:
	player = p
	if p.has_signal("landed"):
		p.connect("landed", _on_player_landed)
	if p.has_signal("ground_pounded"):
		p.connect("ground_pounded", _on_ground_pounded)
	if p.has_signal("jumped"):
		p.connect("jumped", _on_player_jumped)
	_grace_t = 5.0  # finishing pass: E04 still reached Mak 4.3 s after a CP2 respawn (feel r1c)
	_last_ppos = p.global_position
	_intro.call_deferred()


# ------------------------------------------------------------------ the sleeping Giant

func _giant() -> void:
	var holder := Node3D.new()
	holder.name = "SleepingGiant"
	world.add_child(holder)
	giant = holder
	# Collision for the head dome and the pom-pom lives in w2_build.gd (_r1_structures).
	var real: Node3D = null
	for p in GIANT_PATHS:
		if ResourceLoader.exists(p):
			var ps := load(p) as PackedScene
			if ps:
				real = ps.instantiate() as Node3D
				break
	if real:
		real.name = "GiantModel"
		# glTF faces +Z; the Giant sits west of the table facing east (+X), forearms folded on the table top.
		real.rotation.y = PI * 0.5
		real.scale = Vector3.ONE * GIANT_SCALE
		real.position = GIANT_ORIGIN
		holder.add_child(real)
		giant_body = real
		giant_head = real
		head_pos = GIANT_ORIGIN + Vector3(0.72, 3.0, 0.0)
		for sk in real.find_children("*", "Skeleton3D", true, false):
			giant_skel = sk as Skeleton3D
			break
		# Seated lower body under the bust (the model is a waist-up bust).
		var lb = M.new()
		lb.rbox(Transform3D(Basis(), Vector3(-14.4, 52.8, -34.0)), Vector3(3.4, 5.6, 5.0), 0.9, Color("d4a62a"), 3, Color("e0b63a"))
		lb.rbox(Transform3D(Basis(), Vector3(-14.4, 50.6, -34.0)), Vector3(3.8, 1.2, 5.6), 0.5, Color("6b4a2a"), 3)
		_mesh(holder, lb.commit(b.vc_mat(0.4)), "SeatedBody")
	else:
		_procedural_giant(holder)
	_giant_props(holder)


func _procedural_giant(holder: Node3D) -> void:
	# Procedural stand-in, used only if the sleeping-giant mesh is missing.
	giant_body = Node3D.new()
	giant_body.name = "Body"
	giant_body.position = Vector3(-15.2, 50.0, -34.0)
	holder.add_child(giant_body)
	var m = M.new()
	var skin := Color("f2c4a0")
	var vest := Color("4a6fb0")
	var shirt := Color("f3ead8")
	m.sphere(Transform3D(Basis(Vector3.BACK, -0.35).scaled(Vector3(2.4, 3.4, 3.0)), Vector3(0.4, 4.4, 0)), vest, 22, 14, vest.darkened(0.3))
	for k in 4:
		m.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.22), Vector3(2.55 - k * 0.32, 5.6 - k * 0.75, 0)), Color("f2b632"), 8, 5)
	m.sphere(Transform3D(Basis().scaled(Vector3(1.6, 1.0, 2.6)), Vector3(1.0, 6.8, 0)), shirt, 16, 10)
	for side: float in [-1.0, 1.0]:
		m.sphere(Transform3D(Basis(Vector3.UP, side * 0.2).scaled(Vector3(2.6, 0.75, 0.85)), Vector3(4.2, 6.2, side * 1.9)), shirt, 18, 10)
		m.sphere(Transform3D(Basis().scaled(Vector3(0.75, 0.6, 0.7)), Vector3(5.8, 6.1, side * 1.2)), skin, 14, 8)
	_mesh(giant_body, m.commit(b.vc_mat(0.45)), "Torso")
	giant_head = Node3D.new()
	giant_head.name = "Head"
	giant_head.position = HEAD_POS
	holder.add_child(giant_head)
	var h = M.new()
	h.sphere(Transform3D(Basis().scaled(Vector3(1.55, 1.4, 1.6)), Vector3.ZERO), skin, 22, 14)
	h.sphere(Transform3D(Basis().scaled(Vector3(0.5, 0.45, 0.48)), Vector3(1.5, -0.1, 0)), Color("e0605a"), 14, 8)
	for side: float in [-1.0, 1.0]:
		h.sphere(Transform3D(Basis().scaled(Vector3(0.08, 0.06, 0.32)), Vector3(1.38, 0.38, side * 0.55)), Color("5a3520"), 8, 5)
		h.sphere(Transform3D(Basis(Vector3.RIGHT, side * 0.25).scaled(Vector3(0.22, 0.16, 0.45)), Vector3(1.3, 0.72, side * 0.58)), Color("d06a2a"), 10, 6)
		h.sphere(Transform3D(Basis().scaled(Vector3(0.35, 0.55, 0.2)), Vector3(0.0, 0.0, side * 1.58)), skin.darkened(0.08), 10, 6)
	h.sphere(Transform3D(Basis().scaled(Vector3(1.2, 1.0, 1.5)), Vector3(0.85, -0.85, 0)), Color("d8742e"), 18, 10, Color("a8501e"))
	h.sphere(Transform3D(Basis().scaled(Vector3(0.18, 0.3, 0.42)), Vector3(1.55, -0.62, 0)), Color("5a1f22"), 10, 6)
	_mesh(giant_head, h.commit(b.vc_mat(0.5)), "Face")
	var c = M.new()
	var crown := HEAD_POS + Vector3(-0.3, 1.0, 0.0)
	var pom0: Vector3 = POMPOM_POS + Vector3(0, -0.45, 0)
	var line := M.catmull([crown, crown + Vector3(-0.5, 1.0, -0.6), pom0 + Vector3(0.8, 0.6, 0.9), pom0 + Vector3(0.2, 0.1, 0.3)], 0.2)
	var rr := PackedFloat32Array()
	for i in line.size():
		rr.append(lerpf(1.3, 0.25, float(i) / float(line.size() - 1)))
	c.tube(line, rr, Color("d9304a"), 16, true, true, Color("f7f1e3"), 3)
	giant_cap = Node3D.new()
	giant_cap.name = "Nightcap"
	holder.add_child(giant_cap)
	_mesh(giant_cap, c.commit(b.vc_mat(0.45)), "Cap")


func _giant_props(holder: Node3D) -> void:
	# The beard spills onto the table on the south side: that springy tuft is the BEARD bounce pad.
	var bd = M.new()
	var bp: Vector3 = BEARD_POS
	bd.sphere(Transform3D(Basis().scaled(Vector3(1.0, 0.32, 1.0)), bp + Vector3(0, -0.12, 0)), Color("e07a32"), 18, 9, Color("a8501e"))
	for k in 7:
		var a := TAU * float(k) / 7.0
		bd.sphere(Transform3D(Basis().scaled(Vector3(0.32, 0.2, 0.32)), bp + Vector3(cos(a) * 0.6, 0.04, sin(a) * 0.6)), Color("f0903a"), 10, 6)
	bd.tube(M.catmull([head_pos + Vector3(0.6, -1.4, 0.8), bp + Vector3(-0.4, 0.1, -0.6)], 0.3), PackedFloat32Array([0.55, 0.5, 0.45, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4]), Color("d8742e"), 12, true, true)
	beard_mesh = _mesh(holder, bd.commit(b.vc_mat(0.45)), "BeardPad")
	# The pom-pom perch (W2-3 truffle) beside his ear.
	var pom: Vector3 = POMPOM_POS + Vector3(0, -0.45, 0)
	pompom = Node3D.new()
	pompom.name = "PomPom"
	pompom.position = pom
	holder.add_child(pompom)
	var pmm = M.new()
	pmm.sphere(Transform3D(Basis().scaled(Vector3(1.15, 0.5, 1.15)), Vector3.ZERO), Color("fff8f0"), 18, 10, Color("e8dccc"))
	for k in 9:
		var a := TAU * float(k) / 9.0
		pmm.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.38), Vector3(cos(a) * 0.8, 0.12, sin(a) * 0.8)), Color("fffaf2"), 10, 6)
	_mesh(pompom, pmm.commit(b.vc_mat(0.5)), "Puff")
	# Snore Zs.
	zzz = Node3D.new()
	zzz.name = "Zzz"
	zzz.position = head_pos + Vector3(1.5, 1.5, 0)
	holder.add_child(zzz)
	for k in 3:
		var l := Label3D.new()
		l.text = "Z"
		l.font_size = 160 - k * 30
		l.outline_size = 18
		l.modulate = Color("f7f5ff")
		l.outline_modulate = Color("6e4a9e")
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(k * 0.7, k * 0.8, 0)
		zzz.add_child(l)
	# Sleep-talk bubble.
	talk_label = Label3D.new()
	talk_label.name = "SleepTalk"
	talk_label.font_size = 64
	talk_label.outline_size = 14
	talk_label.modulate = Color("3b2416")
	talk_label.outline_modulate = Color("f3e6c4")
	talk_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	talk_label.position = head_pos + Vector3(0.5, 2.8, 0.0)
	talk_label.visible = false
	holder.add_child(talk_label)


func _box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


func _mesh(parent: Node3D, mesh: Mesh, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _on_snore_phase(phase: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if phase == "inhale":
		_snore_cycles += 1
		var near_head := player != null and player.global_position.distance_to(head_pos) < 4.0
		if talk_label and (near_head or _snore_cycles % 4 == 0):
			var lines := ["Fee... fi... fo... hum... more toast...", "Mother, the goose is sulking again..."]
			var gm := get_node_or_null("/root/Game")
			if gm and gm.has_method("is_unlocked") and bool(gm.call("is_unlocked", "w2_reginald_seen")):
				lines[0] = "...kept all the gold... hum..."
			talk_label.text = "Nngh... smells like... bacon?" if near_head else String(lines[(_snore_cycles / 4) % 2])
			talk_label.visible = true
			_talk_timer = 3.0
	if phase == "blast":
		if audio:
			audio.play_sfx("giant_snore", Vector3(-10.5, 57, -34))
		_burst_crumbs()
	elif phase == "inhale" and audio:
		audio.play_sfx("giant_inhale", Vector3(-10.5, 57, -34))


func _burst_crumbs() -> void:
	if ResourceLoader.exists("res://scenes/fx/CrumbBurst.tscn"):
		var fx := (load("res://scenes/fx/CrumbBurst.tscn") as PackedScene).instantiate() as Node3D
		world.add_child(fx)
		fx.global_position = Vector3(-8.5, 56.4, -34.0)
		if fx.has_method("play"):
			fx.call("play")


# ------------------------------------------------------------------ watch

func _watch() -> void:
	var watch: Node3D = b.visuals.get("WATCH")
	if watch == null:
		return
	var hand := watch.find_child("MinuteHand", true, false) as Node3D
	var wp: Vector3 = watch.global_position if watch.is_inside_tree() else watch.position
	minute_hand = AnimatableBody3D.new()
	minute_hand.name = "WatchHand"
	minute_hand.sync_to_physics = true
	minute_hand.collision_layer = 1
	minute_hand.position = wp + Vector3(0, 0.38, 0)
	hand_pivot = minute_hand.position
	world.add_child(minute_hand)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.25, 0.3, 1.4)
	cs.shape = bs
	cs.position = Vector3(0, 0.15, -0.7)
	minute_hand.add_child(cs)
	if hand:
		var xf := hand.transform
		hand.get_parent().remove_child(hand)
		minute_hand.add_child(hand)
		hand.transform = Transform3D(xf.basis.scaled(Vector3.ONE * 0.9), Vector3(0, -0.38, 0) + Vector3(0, xf.origin.y * 0.9, 0))
	# Shove area: a sweep pushes Mak along the hand's motion.
	var area := Area3D.new()
	area.collision_layer = 128
	area.collision_mask = 2
	var acs := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(0.6, 1.0, 1.5)
	acs.shape = ash
	acs.position = Vector3(0, 0.5, -0.75)
	area.add_child(acs)
	minute_hand.add_child(area)
	area.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("player") and body.has_method("add_impulse"):
			var tangent := minute_hand.global_basis.x
			body.call("add_impulse", tangent * 4.0 + Vector3(0, 2.0, 0)))


# ------------------------------------------------------------------ flower and bell

func _flower() -> void:
	var fl: Node3D = b.visuals.get("FLOWER")
	if fl == null:
		return
	for c in fl.get_children():
		if String(c.name).begins_with("Petal"):
			petals.append(c)
	_set_petals(0.0)


func _set_petals(open: float) -> void:
	for p in petals:
		p.rotation.z = lerpf(1.15, 0.12, open)


func _cloud_bell() -> void:
	cloud_bell = Node3D.new()
	cloud_bell.name = "CloudBell"
	cloud_bell.position = Vector3(-17.6, 44.6, -6.0) + Vector3(0, 0, -1.6)
	world.add_child(cloud_bell)
	var m = M.new()
	var arm := M.catmull([Vector3(0, 0, 0), Vector3(0.2, 1.6, 0), Vector3(0.0, 2.6, 0.6), Vector3(-0.2, 2.8, 1.4), Vector3(0, 2.5, 1.6)], 0.2)
	var rr := PackedFloat32Array()
	for i in arm.size():
		rr.append(lerpf(0.22, 0.1, float(i) / float(arm.size() - 1)))
	m.tube(arm, rr, Color("fff8f0"), 10, true, true)
	_mesh(cloud_bell, m.commit(b.vc_mat(0.5)), "Bracket")
	var bell := Node3D.new()
	bell.name = "Bell"
	bell.position = Vector3(0, 2.45, 1.6)
	cloud_bell.add_child(bell)
	var bm = M.new()
	bm.cylinder(Transform3D(Basis(), Vector3(0, -0.45, 0)), 0.25, 0.62, 0.8, Color("f2b632"), 18, true)
	bm.torus(Transform3D(Basis(), Vector3(0, -0.85, 0)), 0.62, 0.08, Color("e8a020"), 18, 6)
	bm.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.14), Vector3(0, -0.95, 0)), Color("c98a20"), 8, 5)
	var gm := ShaderMaterial.new()
	gm.shader = load("res://assets/shaders/toon.gdshader")
	gm.set_shader_parameter("use_vertex_color", true)
	gm.set_shader_parameter("spec_strength", 1.2)
	gm.set_shader_parameter("emission_color", Color("f2b632"))
	gm.set_shader_parameter("emission_energy", 0.25)
	_mesh(bell, bm.commit(gm), "BellMesh")


func _ring_bell() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_sfx("bell", cloud_bell.global_position if cloud_bell else Vector3.INF)
	if cloud_bell:
		var bell := cloud_bell.get_node_or_null("Bell") as Node3D
		if bell:
			var tw := create_tween()
			for k in 6:
				tw.tween_property(bell, "rotation:z", 0.5 * (1.0 - k / 6.0) * (1 if k % 2 == 0 else -1), 0.18)
			tw.tween_property(bell, "rotation:z", 0.0, 0.2)


func _on_goose_freed() -> void:
	_goose_wolf_reveal()
	return
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_sfx("goose_honk", Vector3(13, 52, -35))
	var g: Node3D = _pn("Goose")
	if g:
		var tw := create_tween()
		tw.tween_property(g, "position:y", g.position.y + 1.2, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(g, "position:y", g.position.y, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if ResourceLoader.exists("res://scenes/fx/FeatherBurst.tscn"):
		var fx := (load("res://scenes/fx/FeatherBurst.tscn") as PackedScene).instantiate() as Node3D
		world.add_child(fx)
		fx.global_position = Vector3(13, 52, -35)


# ------------------------------------------------------------------ lights and ambient FX

func _lights() -> void:
	for l in data.get("lighting", {}).get("local_lights", []):
		if not l.has("color") or not l.has("range"):
			continue
		var o := OmniLight3D.new()
		o.name = "Light_" + String(l["id"])
		o.position = Vector3(float(l["pos"][0]), float(l["pos"][1]), float(l["pos"][2]))
		o.light_color = Color(String(l["color"]))
		o.light_energy = float(l["energy"])
		o.omni_range = float(l["range"])
		o.shadow_enabled = false
		world.add_child(o)


func _fx(scene: String, pos: Vector3, parent: Node3D = null) -> Node3D:
	var path := "res://scenes/fx/%s.tscn" % scene
	if not ResourceLoader.exists(path):
		return null
	var fx := (load(path) as PackedScene).instantiate() as Node3D
	fx.position = pos
	(parent if parent else world).add_child(fx)
	if fx.has_method("set_active"):
		fx.call("set_active", true)
	return fx


func _ambient_fx() -> void:
	_fx("ChimneySmoke", Vector3(-14.1, 8.6, 18.9))
	for p: Vector3 in [Vector3(-6, 0.8, 26), Vector3(10, 0.8, 10), Vector3(-15, 0.8, 8), Vector3(12, 2.0, 30)]:
		_fx("Butterflies", p)
	for p: Vector3 in [Vector3(1, 14, -1), Vector3(-1, 30, -5), Vector3(-3, 46, -12)]:
		_fx("FallingLeaves", p)
	for p: Vector3 in [Vector3(7.2, 35.5, -6), Vector3(18, 32, 5), Vector3(-18, 70, -24), Vector3(13, 52, -35)]:
		_fx("Sparkle", p)


func _birds() -> void:
	# Ambient swallow loops round the stalk. Fix r2 (fun and visual critics): the masked crow_bandit.glb stand-ins
	# read as flying enemies, so the loops stay off until a real swallow GLB exists (requested: AMB-SW).
	var glb_path := "res://assets/characters/swallow/swallow.glb"
	if not ResourceLoader.exists(glb_path):
		return
	var ps := load(glb_path) as PackedScene
	if ps == null:
		return
	for k in 6:  # fix r1: six larger birds so the flaps read in wide shots
		var bird := Node3D.new()
		bird.name = "Swallow%d" % k
		world.add_child(bird)
		var g := ps.instantiate() as Node3D
		g.name = "Model"
		g.rotation.y = PI  # glTF faces +Z; the bird flies along -Z
		g.scale = Vector3.ONE * 0.7
		bird.add_child(g)
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sk := g.find_children("*", "Skeleton3D", true, false)
		if not sk.is_empty():
			var skel := sk[0] as Skeleton3D
			var wings := []
			for bn: String in ["arm_l", "arm_r", "forearm_l", "forearm_r"]:
				var bi := skel.find_bone(bn)
				if bi >= 0:
					wings.append([bi, skel.get_bone_rest(bi).basis.get_rotation_quaternion(), 1.0 if bn.ends_with("_l") else -1.0, 1.0 if bn.begins_with("arm") else 0.6])
			bird.set_meta("skel", skel)
			bird.set_meta("wings", wings)
		birds.append(bird)


func _allotment_trigger() -> void:
	var a := Area3D.new()
	a.name = "AllotmentTrigger"
	a.collision_layer = 128
	a.collision_mask = 2
	a.position = Vector3(23, 25, -4)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 11.5
	cy.height = 3.0
	cs.shape = cy
	a.add_child(cs)
	world.add_child(a)
	a.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("player") and not lift_unlocked:
			lift_unlocked = true
			var ui := get_node_or_null("/root/UI")
			if ui and ui.has_method("toast"):
				ui.toast("The Beanpod Lift is running!")
			_scarecrow_bark("HALT! Who goes there? \n...Reinforcements!"))


## Fix r2 (visual critic: the scarecrow gag was lost at gameplay distance): a speech bubble over his head.
func _scarecrow_bark(text: String) -> void:
	var sc: Node3D = b.visuals.get("SCARECROW")
	if sc == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.outline_size = 18
	l.modulate = Color("fff6e0")
	l.outline_modulate = Color("4a2c1a")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.01
	l.position = sc.global_position + Vector3(0, 6.2, 0)
	world.add_child(l)
	_sfx("wolf_growl", sc.global_position)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.15).from(Vector3.ONE * 0.2)
	tw.tween_property(l, "scale", Vector3.ONE, 0.1)
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ per frame

func _on_player_landed(_impact: float) -> void:
	if player == null:
		return
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 0.3, 0), player.global_position + Vector3(0, -0.8, 0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider")
	if not hat_said and Vector2(player.global_position.x - 24.0, player.global_position.z + 4.0).length() < 1.5 and player.global_position.y > 28.0:
		hat_said = true
		_toast("Scarecrow: \"...I'm only straw, you know.\"")
	if col and bouncy_visuals.has(col):
		var v: Node3D = bouncy_visuals[col]
		var tw := create_tween()
		tw.tween_property(v, "scale", Vector3(1.15, 0.6, 1.15), 0.07)
		tw.tween_property(v, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		var audio := get_node_or_null("/root/Audio")
		if audio:
			audio.play_sfx("leaf_boing", v.global_position)


func _physics_process(delta: float) -> void:
	t += delta
	_lift_step(delta)
	_r1_physics(delta)
	_r2_physics(delta)
	_fix1_physics(delta)
	_pods_step(delta)
	if minute_hand:
		minute_hand.rotation.y = -t * deg_to_rad(60.0)


func _lift_step(delta: float) -> void:
	if play == null or play.lift == null:
		return
	var l: AnimatableBody3D = play.lift
	lift_timer += delta
	var y := l.position.y
	match lift_state:
		"top_wait":
			if lift_unlocked and lift_timer > 2.0:
				lift_state = "down"
		"down":
			y = maxf(LIFT_BOTTOM, y - LIFT_SPEED * delta)
			if y <= LIFT_BOTTOM:
				lift_state = "bottom_wait"
				lift_timer = 0.0
		"bottom_wait":
			if lift_timer > 2.0:
				lift_state = "up"
		"up":
			y = minf(LIFT_TOP, y + LIFT_SPEED * delta)
			if y >= LIFT_TOP:
				lift_state = "top_wait"
				lift_timer = 0.0
	l.position = Vector3(9.5, y, -2.5)


func _process(delta: float) -> void:
	# Giant breathing and snore animation.
	if play and play.snore and giant_head:
		var ph: String = play.snore.phase
		var pr: float = play.snore.call("phase_progress")
		var breath := 0.0
		match ph:
			"inhale": breath = pr
			"hold": breath = 1.0
			"blast": breath = 1.0 - pr
			_: breath = 0.0
		if giant_body:
			giant_body.scale = Vector3(1.0 + breath * 0.04, 1.0 + breath * 0.05, 1.0 + breath * 0.04)
		if giant_head != giant_body:
			giant_head.position.y = HEAD_POS.y + breath * 0.15
		elif giant_skel:
			_pose_bone("jaw", Quaternion(Vector3.RIGHT, deg_to_rad(16.0) * (pr if ph == "blast" else (1.0 - pr if ph == "rest" else 0.0))))
			_pose_bone("head", Quaternion(Vector3.RIGHT, -0.06 * breath))
			_pose_bone_scale("nostrils", 1.0 + 0.35 * breath)
			_pose_bone_scale("chest", 1.0 + 0.04 * breath)
			_pose_bone("cap_tip", Quaternion(Vector3.FORWARD, sin(t * 2.0) * 0.08 + breath * 0.15))
		if pompom:
			pompom.scale = Vector3(1.0 + breath * 0.06, 1.0 - breath * 0.05, 1.0 + breath * 0.06)
		if giant_cap:
			giant_cap.rotation.z = breath * 0.25 + sin(t * 2.0) * 0.03
		if zzz:
			zzz.visible = ph == "blast" or ph == "rest"
			zzz.position.x = head_pos.x + 1.5 + (pr * 3.0 if ph == "blast" else 3.0)
			zzz.position.y = head_pos.y + 1.5 + (pr * 1.2 if ph == "blast" else 1.2)
		if talk_label and talk_label.visible:
			_talk_timer -= delta
			if _talk_timer <= 0.0:
				talk_label.visible = false
	# Bean flower opens when Mak gets near the belfry top.
	if player and petals.size() > 0:
		var near := flower_forced or (player.global_position.y > 67.5 and Vector2(player.global_position.x + 18.0, player.global_position.z + 24.0).length() < 6.0)
		flower_open = move_toward(flower_open, 1.0 if near else 0.0, delta * 1.2)
		_set_petals(ease(flower_open, -2.0))
		if near and not bell_rung and player.global_position.y > 67.5:
			bell_rung = true
			var audio := get_node_or_null("/root/Audio")
			if audio:
				audio.play_sfx("bell", Vector3(-18, 64, -24))
	elif petals.size() > 0:
		_set_petals(0.0)
	# Banners flap.
	for i in banners.size():
		var bn: Node3D = banners[i]
		var cloth := bn.get_node_or_null("Cloth") as Node3D
		if cloth:
			cloth.rotation.x = sin(t * 2.6 + i) * 0.08
			cloth.rotation.z = sin(t * 1.9 + i * 0.7) * 0.05
	# Cloud layers and the cloud sea drift slowly east and back.
	for i in layers.size():
		var ly: Node3D = layers[i]
		# Fix r2 (visual critic: 1.2% of pixels moved per second): faster, wider drift, about 0.3-0.7 m/s.
		var amp := 7.0 if String(ly.name).contains("sea") else 5.0
		ly.position.x = sin(t * 0.11 + i * 0.9) * amp
		ly.position.z = cos(t * 0.08 + i * 1.3) * amp * 0.45
		ly.position.y = sin(t * 0.5 + i * 2.1) * 0.25
	if far_islet:
		far_islet.position.y = 6.0 + sin(t * 0.4) * 0.6
	# Swallows circle the stalk in two loops.
	for k in birds.size():
		var bird: Node3D = birds[k]
		var low := k < 3
		var r := 10.0 + float(k % 3) * 1.1
		var sp := 0.45 + float(k % 3) * 0.06
		var a := t * sp * (1.0 if low else -1.0) + float(k) * 1.57
		var cy := (14.0 if low else 34.0) + sin(t * 0.7 + k) * 2.0
		var c: Vector3 = b.stalk_center(cy)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		var fwd := Vector3(-sin(a), 0, cos(a)) * (1.0 if low else -1.0)
		# Bank into the turn, bob, and flap in bursts between glides.
		var bank := Basis(fwd, 0.35 * (1.0 if low else -1.0))
		bird.global_transform = Transform3D(bank * Basis.looking_at(fwd, Vector3.UP), p + Vector3(0, sin(t * 3.0 + k) * 0.15, 0))
		if bird.has_meta("skel"):
			var skel := bird.get_meta("skel") as Skeleton3D
			var burst := 1.0 if fmod(t + float(k) * 0.7, 3.0) < 1.6 else 0.15
			var flap := sin(t * 13.0 + k) * 0.55 * burst
			for wg: Array in bird.get_meta("wings"):
				var q := Quaternion(Vector3(0, 0, 1), flap * float(wg[2]) * float(wg[3]))
				skel.set_bone_pose_rotation(int(wg[0]), (wg[1] as Quaternion) * q)
	# Cloud bell sways gently.
	if cloud_bell:
		var bell := cloud_bell.get_node_or_null("Bell") as Node3D
		if bell and not bell.has_meta("ringing"):
			bell.rotation.x = sin(t * 1.3) * 0.05


# ------------------------------------------------------------------ round 1: moving leaves, bell, bean, goose gag

var bean_sniff: Node3D
var _sneezing := false


func _r1_setup() -> void:
	for id in b.bodies.keys():
		var body: Node3D = b.bodies[id]
		var kind := String(body.get_meta("kind", ""))
		var p: Dictionary = b.plat[id]
		# Rest positions always come from the level data, never from body.position (critic round 1 blocker).
		var base := _jpos(p)
		match kind:
			"droop_leaf":
				var yb := Basis()
				if p.has("stem_to"):
					var d := Vector3(float(p["stem_to"][0]), 0, float(p["stem_to"][2])) - Vector3(base.x, 0, base.z)
					yb = Basis.looking_at(d.normalized(), Vector3.UP)
				body.global_position = base
				droops.append([body, base, yb, 0.0, 0.0, 99.0])
			"moving_leaf":
				var a := Vector3(float(p["path"][0][0]), float(p["path"][0][1]), float(p["path"][0][2]))
				var c := Vector3(float(p["path"][1][0]), float(p["path"][1][1]), float(p["path"][1][2]))
				movers.append([body, (a + c) * 0.5, (c - a).normalized(), a.distance_to(c) * 0.5, 3.2, 0.0])
			"bouncy_leaf_swing":
				var ids := ["LB1", "LB2", "LB3", "LB4", "LB5"]
				var i := ids.find(String(id))
				var prev: Vector3 = _jpos(b.plat[ids[maxi(i - 1, 0)]])
				var nxt: Vector3 = _jpos(b.plat[ids[mini(i + 1, 4)]])
				var chain := nxt - prev
				chain.y = 0.0
				var perp := Vector3(-chain.z, 0, chain.x).normalized()
				var sw: Dictionary = p.get("swing", {})
				body.global_position = base
				movers.append([body, base, perp, float(sw.get("amplitude_m", 1.2)) * 0.5, float(sw.get("period_s", 3.6)), deg_to_rad(float(sw.get("phase_deg", 0.0)))])
	# BL3 (magic sprout leaf) stays hidden until the bean mound is slammed.
	var bl3: Node3D = b.bodies.get("BL3")
	if bl3:
		bl3.visible = false
		for cs in bl3.find_children("*", "CollisionShape3D", true, false):
			(cs as CollisionShape3D).disabled = true
	# Magic bean mound: a sniff target with a little soil hump.
	var mound := Vector3(-16.4, b.island_h(-16.4, 11.4), 11.4)
	var mm = M.new()
	mm.sphere(Transform3D(Basis().scaled(Vector3(0.8, 0.28, 0.8)), mound), Color("8a6444"), 14, 7, Color("6b4a30"))
	mm.sphere(Transform3D(Basis().scaled(Vector3(0.16, 0.12, 0.12)), mound + Vector3(0.1, 0.25, 0)), Color("b07cff"), 8, 5)
	_mesh(world, mm.commit(b.vc_mat(0.4)), "BeanMound")
	if ResourceLoader.exists("res://scenes/objects/SniffTarget.tscn"):
		var st := (load("res://scenes/objects/SniffTarget.tscn") as PackedScene).instantiate() as Node3D
		st.name = "BeanSniff"
		st.position = mound
		world.add_child(st)
		bean_sniff = st
	_bell()
	# Lift 2 starts once CP4 is touched.
	var cp4 := world.get_node_or_null("Gameplay/Checkpoints/CP4")
	if cp4 and cp4.has_signal("activated"):
		cp4.connect("activated", func(_c: Node) -> void:
			if not lift2_unlocked:
				lift2_unlocked = true
				_toast("Beanpod Lift 2 is running!"))
	var cosy: Node = _pn("TeaCosy")
	if cosy and cosy.has_signal("hit"):
		cosy.connect("hit", _on_cosy_hit)


## Safe lookup into the gameplay node table: null for missing or freed nodes (a freed instance assigned to a typed
## variable raised a script error every physics frame after E13 or E10 was defeated, critic round 1).
func _pn(key: String) -> Node:
	if play == null:
		return null
	var v: Variant = play.nodes.get(key)
	if v == null or not is_instance_valid(v):
		return null
	return v as Node


static func _jpos(p: Dictionary) -> Vector3:
	var a: Array = p.get("pos", [0, 0, 0])
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Load-time check: every platform body must sit within 0.5 m of its level-data position (movers within their swing).
func _check_placement() -> void:
	var bad := 0
	for id in b.bodies.keys():
		var body: Node3D = b.bodies[id]
		if not is_instance_valid(body) or not b.plat.has(id):
			continue
		var p: Dictionary = b.plat[id]
		if not p.has("pos"):
			continue
		var tol := 0.5
		var kind := String(p.get("kind", ""))
		if not kind in ["leaf", "droop_leaf", "moving_leaf", "bouncy_leaf", "bouncy_leaf_swing"]:
			continue  # cloud and structure bodies sit at the origin with world-space shapes by design
		if kind == "moving_leaf" or kind == "bouncy_leaf_swing":
			tol = 4.0
		if body.global_position.distance_to(_jpos(p)) > tol:
			bad += 1
			push_warning("[W2] MISPLACED %s at %s (data %s)" % [id, body.global_position, _jpos(p)])
	print("[W2] placement check: %d misplaced of %d bodies" % [bad, b.bodies.size()])


func _park_e13(on: bool) -> void:
	var e13: Node3D = _pn("E13")
	if e13 == null or not is_instance_valid(e13):
		return
	e13.set("ai_enabled", not on)
	if on:
		var tw := create_tween()
		tw.tween_property(e13, "global_position", Vector3(-16.0, 48.5 - 1.4, -8.0), 0.8)


func _toast(text: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.toast(text)


func _sfx(key: String, at := Vector3.INF) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_sfx(key, at)


func _bell() -> void:
	var p: Dictionary = b.plat.get("BELL", {})
	if p.is_empty():
		return
	bell_pivot = Vector3(float(p["pivot"][0]), float(p["pivot"][1]), float(p["pivot"][2]))
	bell = AnimatableBody3D.new()
	bell.name = "GiantBell"
	bell.sync_to_physics = true
	bell.collision_layer = 1
	bell.collision_mask = 0
	bell.position = bell_pivot
	world.add_child(bell)
	# Walkable crown plate 3.0 m below the pivot; the bell body below it is steep (not walkable).
	var plate := CollisionShape3D.new()
	var pb := BoxShape3D.new()
	# Fix r1: a 2.6 m plate whose collar runs 0.9 m down flush, so a running hop from T3 lands on the plate instead
	# of the convex flank (nothing sticks out within 1.2 m below the plate edge).
	pb.size = Vector3(2.6, 0.9, 2.6)
	plate.shape = pb
	plate.position = Vector3(0, -3.45, 0)
	bell.add_child(plate)
	var pts := PackedVector3Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(Vector3(cos(a) * 1.0, -3.9, sin(a) * 1.0))
		pts.append(Vector3(cos(a) * 2.0, -5.6, sin(a) * 2.0))
	var cv := ConvexPolygonShape3D.new()
	cv.points = pts
	var bodycs := CollisionShape3D.new()
	bodycs.shape = cv
	bell.add_child(bodycs)
	var m = M.new()
	var bronze := Color("c98a3a")
	m.tube(PackedVector3Array([Vector3(0, 0.2, 0), Vector3(0, -1.5, 0), Vector3(0, -2.95, 0)]), PackedFloat32Array([0.12, 0.12, 0.12]), Color("4a4550"), 8, true, true)
	for k in 6:
		m.torus(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * float(k % 2)), Vector3(0, -0.3 - k * 0.45, 0)), 0.18, 0.05, Color("5a5560"), 10, 5)
	# Fix r2 (visual critic: the slab crown read as an anvil): a round, bevelled crown with a hanging loop.
	m.puck(Transform3D(Basis(), Vector3(0, -3.3, 0)), 1.5, 0.6, 0.22, Color("a86a32"), 36, Color("e0aa60"))
	m.torus(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -2.75, 0)), 0.32, 0.09, bronze.lightened(0.1), 18, 6)
	m.cylinder(Transform3D(Basis(), Vector3(0, -3.75, 0)), 1.25, 1.0, 0.4, Color("7a4e2c"), 24, false)
	# Bell profile (shoulder, waist, flared lip) in stacked slices so it reads as a bell, not a lampshade.
	var prof := [[-3.5, 0.95], [-3.75, 1.08], [-4.1, 1.12], [-4.5, 1.2], [-4.9, 1.38], [-5.2, 1.62], [-5.42, 1.86], [-5.55, 1.98]]
	for i in prof.size() - 1:
		var y0: float = prof[i][0]
		var y1: float = prof[i + 1][0]
		m.cylinder(Transform3D(Basis(), Vector3(0, (y0 + y1) * 0.5, 0)), float(prof[i][1]), float(prof[i + 1][1]), y0 - y1, bronze.lightened(0.04 * float(i % 2)), 36, false)
	m.torus(Transform3D(Basis(), Vector3(0, -4.0, 0)), 1.12, 0.07, bronze.lightened(0.25), 36, 6)
	m.torus(Transform3D(Basis(), Vector3(0, -5.55, 0)), 1.95, 0.16, bronze.lightened(0.15), 28, 8)
	m.sphere(Transform3D(Basis().scaled(Vector3(0.9, 0.35, 0.9)), Vector3(0, -3.5, 0)), bronze.darkened(0.1), 18, 8)
	m.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.35), Vector3(0, -5.3, 0)), Color("8a5a2a"), 10, 6)
	var bm := ShaderMaterial.new()
	bm.shader = load("res://assets/shaders/toon.gdshader")
	bm.set_shader_parameter("use_vertex_color", true)
	bm.set_shader_parameter("spec_strength", 1.1)
	bm.set_shader_parameter("rim_strength", 0.6)
	_mesh(bell, m.commit(bm), "BellMesh")


func _on_ground_pounded(pos: Vector3) -> void:
	# Bell crown: BONG opens the bean flower.
	# Fix r1: any slam that lands on the bell body (or starts within 2.5 m of the plate) rings it.
	if bell and (_player_floor() == bell or pos.distance_to(bell.global_transform * Vector3(0, -3.0, 0)) < 2.5 or _slam_from_bell):
		_sfx("bell", pos)
		_toast("BONG!")
		if not flower_forced:
			flower_forced = true
			_toast("The bean flower bursts open!")
			_bong_two_shot()
		else:
			_giant_jolt(0.6)
		_fx("SlamShockwave", pos)
	# Blossom tree on the islet: shake Captain Caw down.
	if play and play.caw and is_instance_valid(play.caw) and pos.y > 45.0 and Vector2(pos.x + 41.6, pos.z + 39.0).length() < 2.2:
		play.caw.call("shake_down")
		_fx("FallingLeaves", Vector3(-41.6, 50, -39))
	# Allotment lanes: a slam beside a pea pod stuns its whole row (fix r1, amendments r2 s2).
	if play and pos.y > 23.0 and pos.y < 26.0 and pos.x > 13.0:
		_pod_lane_slam(pos)
	# Magic bean mound: sprout V5 and BL3.
	if not sprouted and Vector2(pos.x + 16.4, pos.z - 11.4).length() < 1.9 and pos.y < 2.0:
		_sprout()


func _sprout() -> void:
	sprouted = true
	_sfx("leaf_boing", Vector3(-16.4, 1, 11.4))
	_toast("A magic bean sprouts!")
	_fx("Confetti", Vector3(-16.4, 1.0, 11.4))
	if bean_sniff:
		bean_sniff.set("active", false)
	var v5: Node3D = _pn("Climb_V5")
	if v5:
		v5.process_mode = Node.PROCESS_MODE_INHERIT
		v5.visible = true
		v5.set("monitorable", true)
		v5.scale = Vector3(1, 0.05, 1)
		var tw := create_tween()
		tw.tween_property(v5, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bl3: Node3D = b.bodies.get("BL3")
	if bl3:
		bl3.visible = true
		for cs in bl3.find_children("*", "CollisionShape3D", true, false):
			(cs as CollisionShape3D).set_deferred("disabled", false)
		var v: Node3D = b.visuals.get("BL3")
		if v:
			v.scale = Vector3.ONE * 0.05
			var tw2 := create_tween()
			tw2.tween_interval(0.8)
			tw2.tween_property(v, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_cosy_hit(_kind: String) -> void:
	if goose_freed:
		return
	if not wolf_beaten:
		_sfx("goose_honk", Vector3(-14, 51, -39.3))
		_toast("(a sleepy honk from under the tea cosy...)")
		return
	goose_freed = true
	var cosy: Node3D = _pn("TeaCosy")
	if cosy:
		var tw := create_tween()
		tw.tween_property(cosy, "position:y", cosy.position.y + 2.5, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cosy, "scale", Vector3.ONE * 0.01, 0.3)
		tw.tween_callback(func() -> void: cosy.queue_free())
	var g: Node3D = _pn("RealGoose")
	if g:
		g.visible = true
	_sfx("goose_honk", Vector3(-14, 51, -39.3))
	_dialog(["Hnk? Oh! A gentleman! One moment...", "There. Do mind the Giant."], "Golden Goose")
	var tw3 := create_tween()
	tw3.tween_interval(1.6)
	tw3.tween_callback(func() -> void:
		var gs: Node = _pn("GooseReward")
		if gs and gs.has_method("give_reward"):
			gs.call("give_reward"))


func _dialog(lines: Array, speaker: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		for l in lines:
			ui.toast("%s: %s" % [speaker, l])


func _goose_wolf_reveal() -> void:
	# Fix r1: the Goose Gag finale (amendments r3 s2): the costume falls apart, the portcullis drops and the
	# "goose" waddle-flees round the plinth until a dive and a jump kick send it out through the gate.
	_sfx("goose_honk", Vector3(13, 52, -35))
	_dialog(["...baa?"], "The \"goose\"")
	var g: Node3D = _pn("Goose")
	if g:
		var tw := create_tween()
		tw.tween_property(g, "position:y", g.position.y + 0.6, 0.25)
		tw.tween_property(g, "scale", Vector3.ONE * 0.01, 0.2)
	await get_tree().create_timer(0.6, false).timeout
	if g:
		g.visible = false
	_fx("FeatherBurst", Vector3(13, 52, -35))
	var gw := Node3D.new()
	gw.set_script(load("res://scripts/worlds/w2_goose_wolf.gd"))
	gw.name = "E16_GooseWolf"
	world.add_child(gw)
	e16 = gw
	gw.connect("finished", func() -> void:
		wolf_beaten = true
		var game := get_node_or_null("/root/Game")
		if game and game.has_method("unlock"):
			game.call("unlock", "w2_goose_wolf")
		_toast("The real goose must be somewhere... sniff around the kitchen!"))
	var e14: Node = _pn("E14")
	if e14:
		e14.set("ai_enabled", false)


## Costume stages advanced by the switch count: ear, then tail, each with its line (stage 3 opens the cage).
func _on_goose_switch(_sw: Node) -> void:
	_goose_stage += 1
	var g: Node3D = _pn("Goose")
	if g == null:
		return
	match _goose_stage:
		1:
			_toast("The \"goose\": \"HONK.\" (...was that a wolf ear?)")
		2:
			_toast("The \"goose\": \"Hhhonk?\" (a bushy grey tail flops out)")
	if _goose_stage <= 2:
		var GW: GDScript = load("res://scripts/worlds/w2_goose_wolf.gd")
		GW.call("add_wolf_bits", g, _goose_stage)
		_sfx("goose_honk", g.global_position)


var _goose_stage := 0


func _r1_physics(delta: float) -> void:
	# Droopy leaves: sag 0.9 m and tilt 12 degrees 0.6 s after Mak lands; recover 3 s after he leaves.
	var on_body: Object = _player_floor()
	for d in droops:
		var body: AnimatableBody3D = d[0]
		var base: Vector3 = d[1]
		var yb: Basis = d[2]
		if on_body == body:
			d[3] = float(d[3]) + delta
			d[5] = 0.0
		else:
			d[3] = 0.0
			d[5] = float(d[5]) + delta
		var sag: float = d[4]
		if float(d[3]) > 0.6:
			sag = minf(1.0, sag + delta / 0.8)
		elif float(d[5]) > 3.0:
			sag = maxf(0.0, sag - delta / 1.0)
		if float(d[3]) > 0.3 and float(d[3]) - delta <= 0.3:
			_sfx("leaf_creak", base)
		d[4] = sag
		var e := ease(sag, -1.6)
		body.global_transform = Transform3D(Basis(yb.x, deg_to_rad(12.0) * e), base + Vector3(0, -0.9 * e, 0))
	for mv in movers:
		var body2: AnimatableBody3D = mv[0]
		var off: float = sin(TAU * t / float(mv[4]) + float(mv[5])) * float(mv[3])
		body2.global_position = (mv[1] as Vector3) + (mv[2] as Vector3) * off
	# The Giant's bell swings east-west under the hook.
	if bell:
		# Fix r1: ease into a short dwell at each extreme so boarding and slamming have a readable window.
		var sw := sin(TAU * t / 4.0)
		bell_angle = deg_to_rad(25.0) * signf(sw) * pow(absf(sw), 0.55)
		bell.global_transform = Transform3D(Basis(Vector3.BACK, bell_angle), bell_pivot)
	# Sniffle trigger at the nostrils during the inhale.
	if player and play and play.sniffle and play.snore and String(play.snore.phase) == "inhale":
		var sp: Vector3 = play.sniffle.global_position
		var pp := player.global_position + Vector3(0, 0.6, 0)
		if absf(pp.x - sp.x) < 0.7 and absf(pp.y - sp.y) < 0.8 and absf(pp.z - sp.z) < 1.0:
			_sneeze()
	if play and play.lift2:
		_lift2_step(delta)
	# Round 3: E13 only charges while Mak stands on U02 or U03.
	var e13: Node = _pn("E13")
	if e13 and is_instance_valid(e13):
		var fb := _player_floor()
		var on_runner: bool = fb != null and (fb == b.bodies.get("U02") or fb == b.bodies.get("U03"))
		e13.set("notice_radius", 9.0 if on_runner else 0.0)
	_candle_step()


func _sneeze() -> void:
	if _sneezing:
		return
	_sneezing = true
	_sfx("giant_sneeze", HEAD_POS)
	_toast("ACHOO!")
	_fx("CrumbBurst", player.global_position)
	await get_tree().create_timer(0.35, false).timeout
	# Round 3 (P4): the sneeze cannon. Mak tumbles on a scripted 2.0 s arc (peak about 63.5 over x -2) and
	# lands on the footstool at CP6; the A41 acorns lie along the arc and are collected by it.
	if player and is_instance_valid(player):
		var from := player.global_position
		var mid_y := (from.y + CP6.y) * 0.5
		var h := maxf(63.5 - mid_y, 2.0)
		player.set_physics_process(false)
		var e := 0.0
		while e < 2.0 and is_instance_valid(player):
			await get_tree().physics_frame
			e += get_physics_process_delta_time()
			var u := clampf(e / 2.0, 0.0, 1.0)
			var p := from.lerp(CP6, u)
			p.y = lerpf(from.y, CP6.y, u) + h * 4.0 * u * (1.0 - u)
			player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)) * Basis(Vector3.RIGHT, -u * TAU * 2.0), p)
		if is_instance_valid(player):
			player.set_physics_process(true)
			if player.has_method("respawn"):
				player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), CP6))
			else:
				player.global_position = CP6
			_toast("...bless me...")
	_sneezing = false


func _player_floor() -> Object:
	if player == null or not (player is CharacterBody3D):
		return null
	var cb := player as CharacterBody3D
	if not cb.is_on_floor():
		return null
	for i in cb.get_slide_collision_count():
		var col := cb.get_slide_collision(i)
		if col.get_normal().y > 0.6:
			return col.get_collider()
	return null


func _lift2_step(delta: float) -> void:
	var l: AnimatableBody3D = play.lift2
	lift2_timer += delta
	var y := l.position.y
	match lift2_state:
		"top_wait":
			if lift2_unlocked and lift2_timer > 2.0:
				lift2_state = "down"
		"down":
			y = maxf(24.0, y - LIFT_SPEED * delta)
			if y <= 24.0:
				lift2_state = "bottom_wait"
				lift2_timer = 0.0
		"bottom_wait":
			if lift2_timer > 2.0:
				lift2_state = "up"
		"up":
			y = minf(44.0, y + LIFT_SPEED * delta)
			if y >= 44.0:
				lift2_state = "top_wait"
				lift2_timer = 0.0
	l.position = Vector3(l.position.x, y, l.position.z)


# ------------------------------------------------------------------ opening hero shot

## First 10 seconds: when the visit starts at the garden gate, a storybook camera rises from the garden
## up the beanstalk through both cloud layers to the castle and belfry flower, then hands back to the
## gameplay camera behind Mak. Skipped for captures, replays, tests and mission spawns above the garden.
func _intro() -> void:
	var dev := get_node_or_null("/root/Dev")
	if dev:
		for a in ["capture", "replay", "w2-selftest", "w2-fps", "w2-nointro", "spawn"]:
			if dev.has_arg(a):
				return
	if String(world.get("spawn_name")) != "Default" or player == null or player.global_position.y > 2.0:
		return
	await get_tree().process_frame
	var game_cam := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "IntroCam"
	cam.far = 1500.0
	world.add_child(cam)
	# Round 3 crane: hold on StoryCam_F_v3 (the castle on its cloud), crane down to StoryCam_A_v2, then
	# blend into the gameplay camera behind Mak.
	var a2 := world.get_node_or_null("StoryCams/StoryCam_A_v2") as Camera3D
	var f3 := world.get_node_or_null("StoryCams/StoryCam_F_v3") as Camera3D
	var start := a2.global_transform if a2 else Transform3D(Basis(), Vector3(6, 1, 44)).looking_at(Vector3(-1, 20, -6), Vector3.UP)
	var crane := f3.global_transform if f3 else start
	var fov_a: float = a2.fov if a2 else 62.0
	var fov_f: float = f3.fov if f3 else fov_a
	cam.fov = fov_f
	cam.global_transform = crane
	cam.make_current()
	var e := 0.0
	while e < 6.5:
		e += get_process_delta_time()
		if e > 1.0 and e <= 4.0:
			var k := smoothstep(0.0, 1.0, (e - 1.0) / 3.0)
			cam.global_transform = crane.interpolate_with(start, k)
			cam.fov = lerpf(fov_f, fov_a, k)
		elif e > 5.0 and game_cam and is_instance_valid(game_cam):
			var k2 := smoothstep(0.0, 1.0, (e - 5.0) / 1.5)
			cam.global_transform = start.interpolate_with(game_cam.global_transform, k2)
			cam.fov = lerpf(fov_a, game_cam.fov, k2)
		await get_tree().process_frame
	if game_cam and is_instance_valid(game_cam):
		game_cam.make_current()
	cam.queue_free()


# ------------------------------------------------------------------ round 2: beacon, colour script, cameo, bud

var beacon: Node3D
var beacon_mat: StandardMaterial3D
var beacon_light: OmniLight3D
var colour_keys: Array = []
var _smooth_y := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _sky_timer := 0.0
var _sky_y := -999.0
var blob: Decal
var _reg_state := 0
var _reg_t := 0.0


func _r2_setup() -> void:
	# Goal beacon: a golden pollen column rising from the bean-flower bud, readable from every band.
	beacon = Node3D.new()
	beacon.name = "GoalBeacon"
	beacon.position = Vector3(-18.0, 70.0, -24.0)
	world.add_child(beacon)
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 1.0
	cm.height = 30.0
	cm.cap_top = false
	cm.cap_bottom = false
	col.mesh = cm
	col.position = Vector3(0, 15.0, 0)
	beacon_mat = StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon_mat.albedo_color = Color(1.0, 0.74, 0.2, 0.3)
	col.material_override = beacon_mat
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(col)
	_fx("Sparkle", Vector3(0, 2.0, 0), beacon)
	beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color("ffe79a")
	beacon_light.light_energy = 2.5
	beacon_light.omni_range = 10.0
	beacon.add_child(beacon_light)
	var game := get_node_or_null("/root/Game")
	if game and bool(game.call("has_truffle", "W2-8")):
		beacon.visible = false
	if game and game.has_signal("truffle_collected"):
		game.connect("truffle_collected", func(id: String) -> void:
			if id == "W2-8" and beacon:
				beacon.visible = false)
	# Colour script keys (sun, fog, sky and ambient by Mak's height).
	colour_keys = data.get("lighting", {}).get("colour_script", {}).get("keys", [])
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky and _env.sky.sky_material is ShaderMaterial:
			_sky_mat = (_env.sky.sky_material as ShaderMaterial).duplicate() as ShaderMaterial
			_env.sky = _env.sky.duplicate() as Sky
			_env.sky.sky_material = _sky_mat
	_sun = world.get_node_or_null("Sun") as DirectionalLight3D
	# Hero contact shadow: a soft blob under Mak on every surface (fades with height).
	blob = Decal.new()
	blob.name = "MakBlobShadow"
	blob.size = Vector3(0.9, 8.0, 0.9)
	blob.texture_albedo = _blob_tex()
	blob.modulate = Color(0.37, 0.31, 0.53, 0.45)
	blob.cull_mask = 1
	world.add_child(blob)


func _blob_tex() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - smoothstep(0.35, 1.0, d), 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _key_at(y: float) -> Dictionary:
	if colour_keys.is_empty():
		return {}
	var lo: Dictionary = colour_keys[0]
	var hi: Dictionary = colour_keys[colour_keys.size() - 1]
	for i in colour_keys.size() - 1:
		var a: Dictionary = colour_keys[i]
		var c: Dictionary = colour_keys[i + 1]
		if y >= float(a["y"]) and y <= float(c["y"]):
			lo = a
			hi = c
			break
	if y <= float(lo["y"]):
		hi = lo
	elif y >= float(hi["y"]):
		lo = hi
	var k := 0.0 if float(hi["y"]) == float(lo["y"]) else clampf((y - float(lo["y"])) / (float(hi["y"]) - float(lo["y"])), 0.0, 1.0)
	var out := {}
	for key in ["sun_color", "fog_color", "sky_top", "sky_horizon", "ambient_tint"]:
		out[key] = Color(String(lo[key])).lerp(Color(String(hi[key])), k)
	for key in ["sun_energy", "sun_pitch_deg", "fog_density", "ambient_energy"]:
		out[key] = lerpf(float(lo[key]), float(hi[key]), k)
	return out


func _r2_physics(delta: float) -> void:
	if player == null:
		return
	var py := player.global_position.y
	# Colour script.
	_smooth_y = lerpf(_smooth_y, py, 1.0 - exp(-delta / 1.5))
	var k := _key_at(_smooth_y)
	if not k.is_empty():
		if _sun:
			# Grade fix r1: stronger warm key light, long soft shadows (pitch kept within -30..-20).
			_sun.light_color = (k["sun_color"] as Color).lerp(Color("ffc98a"), 0.35)
			_sun.light_energy = float(k["sun_energy"]) * 1.35
			_sun.rotation_degrees.x = clampf(float(k["sun_pitch_deg"]), -30.0, -20.0)
		if _env:
			_env.fog_light_color = k["fog_color"]
			_env.ambient_light_color = (k["ambient_tint"] as Color).lerp(Color("f2e8da"), 0.6)
			_env.ambient_light_energy = float(k["ambient_energy"]) * 0.7  # grade fix r2: shadows read on the decks
		# Sky changes re-render the radiance map, so update the sky only in coarse steps.
		_sky_timer -= delta
		if _sky_mat and _sky_timer <= 0.0 and absf(_smooth_y - _sky_y) > 3.0:
			_sky_timer = 1.5
			_sky_y = _smooth_y
			# Grade fix r2: periwinkle top and a lilac horizon, nearer the key art than the plan's violet and peach.
			_sky_mat.set_shader_parameter("top_color", (k["sky_top"] as Color).lerp(Color("8f8fd8"), 0.55))
			_sky_mat.set_shader_parameter("horizon_color", (k["sky_horizon"] as Color).lerp(Color("e8c8e8"), 0.6))
	# Beacon fades out within 25 m of Mak.
	if beacon and beacon.visible:
		var d := player.global_position.distance_to(beacon.global_position)
		beacon_mat.albedo_color.a = 0.3 * smoothstep(12.0, 25.0, d)
	# Blob shadow follows Mak, fading with height above the ground below.
	if blob:
		var space := world.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 0.2, 0), player.global_position + Vector3(0, -8.0, 0), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			blob.visible = false
		else:
			var gp: Vector3 = hit["position"]
			var h := player.global_position.y - gp.y
			blob.visible = h < 6.0
			blob.global_position = gp + Vector3(0, 0.5, 0)
			blob.modulate.a = 0.62 * (1.0 - clampf(h / 6.0, 0.0, 1.0))  # fix r1: reads on the light decks
			var sz := 0.8 * (1.0 - clampf(h / 6.0, 0.0, 1.0) * 0.4)
			blob.size = Vector3(sz, 4.0, sz)
	# Bluebell bud: the bumble's charge bursts it open.
	if play and play.bud and not play.bud_open:
		_bee_bait(delta)
	# Sir Reginald's cameo on the chair back (first entry into the courtyard or kitchen).
	if play and play.reginald and is_instance_valid(play.reginald):
		var p := player.global_position
		var inside := (p.x > 8 and p.x < 20 and p.y > 49 and p.y < 60 and p.z > -42 and p.z < -26) or (p.x > -16 and p.x < 6 and p.y > 49 and p.y < 62 and p.z > -42 and p.z < -26)
		match _reg_state:
			0:
				if inside:
					_reg_state = 1
					_reg_t = 0.0
					_toast("Sir Reginald: \"Fee... fi... fo... and the Giant kept ALL the gold. The end.\"")
			1:
				_reg_t += delta
				if _reg_t > 8.0 or p.distance_to(play.reginald.global_position) < 10.0:
					_reg_state = 2
					_reg_t = 0.0
					_toast("Sir Reginald: \"Shh! Piglet! He's only just gone off!\"")
			2:
				_reg_t += delta
				if _reg_t > 2.5:
					_reg_state = 3
					_toast("Sir Reginald: \"Hmph. Do try not to wake him. I shan't read it twice.\"")
					_fx("PageFlutter", play.reginald.global_position + Vector3(0, 1, 0))
					_fx("Confetti", play.reginald.global_position + Vector3(0, 1, 0))
					play.reginald.queue_free()
					var game := get_node_or_null("/root/Game")
					if game and game.has_method("unlock"):
						game.call("unlock", "w2_reginald_seen")


func _pose_bone(bone_name: String, q: Quaternion) -> void:
	var i := giant_skel.find_bone(bone_name)
	if i >= 0:
		giant_skel.set_bone_pose_rotation(i, giant_skel.get_bone_rest(i).basis.get_rotation_quaternion() * q)


func _pose_bone_scale(bone_name: String, k: float) -> void:
	var i := giant_skel.find_bone(bone_name)
	if i >= 0:
		giant_skel.set_bone_pose_scale(i, Vector3.ONE * k)


# ------------------------------------------------------------------ round 3: candle, BONG two-shot

var candle_flame: MeshInstance3D
var candle_light: OmniLight3D
var _bong_busy := false


func _r3_candle_setup() -> void:
	if not b.visuals.has("CANDLE_TOP"):
		return
	var top: Vector3 = b.visuals["CANDLE_TOP"]
	# Fix r1: a camera-facing additive teardrop flame that glows (was a flat yellow ellipse).
	candle_flame = MeshInstance3D.new()
	candle_flame.name = "CandleFlame"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.7, 1.3)
	qm.center_offset = Vector3(0, 0.5, 0)
	candle_flame.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.no_depth_test = false
	fm.albedo_texture = _flame_tex()
	fm.albedo_color = Color(2.4, 1.6, 0.8)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	candle_flame.material_override = fm
	candle_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	candle_flame.position = top + Vector3(0, 0.05, 0)
	candle_flame.set_meta("base", candle_flame.position)
	world.add_child(candle_flame)
	candle_light = OmniLight3D.new()
	candle_light.light_color = Color("ffc86b")
	candle_light.light_energy = 2.0
	candle_light.omni_range = 9.0
	candle_light.position = top + Vector3(0, 0.6, 0)
	world.add_child(candle_light)
	var hz := Area3D.new()
	hz.name = "CandleFlameHazard"
	hz.add_to_group("hazard")
	hz.set_meta("damage", 1)
	hz.set_meta("knockback_up", 6.0)
	hz.collision_layer = 16
	hz.collision_mask = 0
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.35
	cs.shape = ss
	hz.add_child(cs)
	hz.position = top + Vector3(0, 0.4, 0)
	world.add_child(hz)


func _flame_tex() -> Texture2D:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v := 1.0 - (float(y) + 0.5) / float(h)  # 0 bottom .. 1 top
			# Teardrop: round bottom (centre at v 0.28), tapering to a point at the top.
			var half := 0.0
			if v < 0.28:
				half = sqrt(maxf(0.0, 1.0 - pow((0.28 - v) / 0.28, 2.0))) * 0.62
			else:
				half = 0.62 * pow(maxf(0.0, 1.0 - (v - 0.28) / 0.72), 1.4)
			var d := absf(u) / maxf(half, 0.001)
			var a := clampf(1.0 - smoothstep(0.55, 1.0, d), 0.0, 1.0) if half > 0.0 else 0.0
			var core := clampf(1.0 - d * 1.4, 0.0, 1.0) * clampf(1.0 - v * 1.3, 0.0, 1.0)
			var c := Color(1.0, 0.55 + 0.4 * core, 0.18 + 0.7 * core, a * (0.95 - v * 0.25))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _candle_step() -> void:
	if candle_flame == null:
		if b.visuals.has("CANDLE_TOP") and not has_meta("candle_done"):
			set_meta("candle_done", true)
			_r3_candle_setup()
		return
	# The flame is a second breath telegraph: leans west on the inhale, flat east in the blast.
	var ph: String = String(play.snore.phase) if play and play.snore else "rest"
	var target := 0.0
	match ph:
		"inhale": target = 0.45
		"blast": target = -1.2
		_: target = 0.0
	# The billboard cannot roll, so the lean is a sideways shift plus a squash.
	var lean: float = lerpf(float(candle_flame.get_meta("lean", 0.0)), target, 0.15)
	candle_flame.set_meta("lean", lean)
	candle_flame.position = (candle_flame.get_meta("base") as Vector3) + Vector3(-lean * 0.22, 0, 0)
	candle_flame.scale = Vector3(1.0 + absf(lean) * 0.25, (1.0 - absf(lean) * 0.25) * (1.0 + sin(t * 17.0) * 0.08 + sin(t * 9.0) * 0.05), 1.0)
	if candle_light:
		candle_light.light_energy = 2.0 + sin(t * 13.0) * 0.25 + sin(t * 7.3) * 0.15


func _giant_jolt(up: float) -> void:
	if giant_body == null:
		return
	var base_y := GIANT_ORIGIN.y if giant_body == giant_head else giant_body.position.y
	var tw := create_tween()
	tw.tween_property(giant_body, "position:y", base_y + up, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(giant_body, "position:y", base_y, 0.6).set_trans(Tween.TRANS_QUAD)


func _bong_two_shot() -> void:
	# First slam per visit: a 3.2 s cutaway on StoryCam_E_v3 showing the bell and the Giant together.
	if _bong_busy:
		return
	_bong_busy = true
	var e3 := world.get_node_or_null("StoryCams/StoryCam_E_v3") as Camera3D
	var game_cam := get_viewport().get_camera_3d()
	if e3:
		e3.make_current()
	_fx("SlamShockwave", bell.global_transform * Vector3(0, -3.0, 0) if bell else Vector3(-13, 63.5, -16))
	await get_tree().create_timer(0.5, false).timeout
	_giant_jolt(1.8)
	await get_tree().create_timer(0.4, false).timeout
	_toast("The Giant: \"FEE! FI! FO!\"")
	_sfx("giant_snore", head_pos)
	_fx("FallingLeaves", head_pos + Vector3(0, 4, 0))
	await get_tree().create_timer(1.1, false).timeout
	_toast("The Giant: \"...bacon?\"")
	await get_tree().create_timer(1.2, false).timeout
	if game_cam and is_instance_valid(game_cam):
		game_cam.make_current()
	_bong_busy = false

# ------------------------------------------------------------------ dev self-test (logic chain of each mission)

## --w2-selftest=<truffle id>: drives the mission's logic (switches, pages, poppers, rings, acorns) without
## movement, then places Mak on the reward. Proves the reward chain and the truffle id; route reachability
## is covered separately by replays.
func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_arg("w2-selftest"):
		_selftest_many.call_deferred(String(dev.arg("w2-selftest", "")))


## Finishing pass (WORLDS, 2026-10-19): "all" or a comma list runs every reward chain in ONE launch.
func _selftest_many(arg: String) -> void:
	var ids := PackedStringArray(["W2-1", "W2-3", "W2-5", "W2-6", "W2-7", "W2-4", "W2-2", "W2-100", "W2-8"]) if arg == "all" else arg.split(",")
	var ok := 0
	for id in ids:
		await _selftest(id)
		var game := get_node_or_null("/root/Game")
		if game and bool(game.call("has_truffle", id)):
			ok += 1
	print("[W2 selftest] SUMMARY %d/%d reward chains collected" % [ok, ids.size()])
	await _wait(1.0)
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, false).timeout


func _tp(pos: Vector3) -> void:
	if player == null:
		return
	if player.has_method("respawn"):
		player.call("respawn", Transform3D(Basis(), pos))
	else:
		player.global_position = pos
		player.reset_physics_interpolation()


func _selftest(id: String) -> void:
	await _wait(1.5)
	print("[W2 selftest] start ", id)
	match id:
		"W2-2":
			for n in ["Switch_S1", "Switch_S2", "Switch_S3"]:
				var sw: Node = _pn(n)
				if sw:
					sw.call("press")
					print("[W2 selftest] pressed ", n)
				await _wait(0.4)
			await _wait(1.5)
			print("[W2 selftest] goose-costume wolf spawned=", e16 != null, " stage=", _goose_stage)
			_tp(Vector3(12.5, 50.1, -29.5))
			await _wait(1.0)
			if e16 and is_instance_valid(e16):
				var p0: Vector3 = (e16 as Node3D).global_position
				await _wait(1.0)
				print("[W2 selftest] wolf moved %.2f m in 1 s, state=%s, portcullis y=%.2f" % [p0.distance_to((e16 as Node3D).global_position), e16.get("state"), float(e16.get("_port_y"))])
				print("[W2 selftest] punch on a running wolf lands=", e16.call("hit_by_player", "punch", Vector3.ZERO))
				await _wait(0.9)
				print("[W2 selftest] dive lands=", e16.call("hit_by_player", "dive", Vector3.ZERO))
				await _wait(1.0)
				print("[W2 selftest] jump kick lands=", e16.call("hit_by_player", "jump_kick", Vector3.ZERO))
			await _wait(3.0)
			print("[W2 selftest] wolf_beaten=", wolf_beaten)
			_on_cosy_hit("punch")
			await _wait(3.0)
			var gm: Node3D = play.nodes["GooseReward"].get_node("TruffleMarker")
			_tp(gm.global_position + Vector3(0, 0.1, 0))
		"W2-5":
			if play.has_method("open_bud"):
				play.call("open_bud", "bee")  # P4 waits inside the bluebell bud until E10's charge opens it
				await _wait(1.0)
			for pg in get_tree().get_nodes_in_group("lost_page"):
				pg.call("collect")
				await _wait(0.3)
			await _wait(2.0)
			_tp(Vector3(9, 1.1, 22))
		"W2-6":
			for e in play.poppers:
				for k in 3:
					if is_instance_valid(e) and not bool(e.get("is_defeated")):
						e.call("hit_by_player", "stomp", (e as Node3D).global_position + Vector3(0, 2, 0))
						await _wait(0.6)
			await _wait(3.0)
			_tp(Vector3(24, 24.1, 0.5))
		"W2-7":
			var tt: Node3D = _pn("CloudHopper")
			_tp(tt.get_node("StartGate").global_position + Vector3(0, 0.2, 0))
			await _wait(0.6)
			print("[W2 selftest] trial running=", tt.get("running"))
			for r in tt.get_node("Rings").get_children():
				_tp((r as Node3D).global_position + Vector3(0, -0.6, 0))
				await _wait(0.25)
			print("[W2 selftest] rings passed=", tt.call("rings_passed"))
			_tp(Vector3(-17.6, 44.7, -6.0))
			await _wait(2.0)
			_tp(Vector3(-17.6, 44.7, -6.0))
		"W2-4":
			var caw: Node3D = play.caw
			_tp(Vector3(-19.0, 44.1, -8.5))
			await _wait(1.5)
			for k in 2:
				caw.call("hit_by_player", "jump_kick", caw.global_position)
				await _wait(2.5)
			_on_ground_pounded(Vector3(-41.0, 46.05, -38.0))
			await _wait(1.0)
			caw.call("hit_by_player", "punch", caw.global_position)
			await _wait(3.0)
			_tp(Vector3(-40.5, 46.1, -38.0))
		"sneeze":
			_tp(Vector3(-8.7, 56.6, -34.0))
			await _wait(0.5)
			var acorns0: int = int(get_node("/root/Game").get("acorns")) if get_node_or_null("/root/Game") else -1
			_sneeze()
			await _wait(3.2)
			print("[W2 selftest] sneeze landed at %s (CP6 %s), acorns %d -> %s" % [player.global_position, CP6, acorns0, get_node("/root/Game").get("acorns") if get_node_or_null("/root/Game") else "?"])
		"W2-100":
			var n := 0
			var acorns: Array[Node] = []
			for a in world.find_children("*", "Area3D", true, false):
				if a.get_script() and String((a.get_script() as Script).resource_path).ends_with("acorn.gd"):
					acorns.append(a)
			print("[W2 selftest] acorns in world: ", acorns.size())
			for a in acorns:
				if is_instance_valid(a) and a.has_method("collect") and a.get_script() and String((a.get_script() as Script).resource_path).ends_with("acorn.gd"):
					a.call("collect")
					n += 1
					await _wait(0.02)
			print("[W2 selftest] acorns collected: ", n)
			await _wait(2.5)
			_tp(Vector3(-5.5, 24.1, -13.5))
		"W2-8":
			_tp(bell.global_transform * Vector3(0, -2.6, 0))
			await _wait(0.3)
			_on_ground_pounded(bell.global_transform * Vector3(0, -3.0, 0))
			await _wait(5.0)
			print("[W2 selftest] flower_forced=", flower_forced)
			var t8: Node3D = play.truffles.get(id)
			if t8:
				_tp(t8.global_position + Vector3(0, 0.1, 0))
		_:
			var t: Node3D = play.truffles.get(id)
			if t:
				_tp(t.global_position + Vector3(0, 0.1, 0))
	await _wait(5.0)
	var game := get_node_or_null("/root/Game")
	print("[W2 selftest] result %s has_truffle=%s" % [id, game.call("has_truffle", id) if game else "?"])


# ------------------------------------------------------------------ fix round 1: fairness systems

var _grace_t := 0.0
var _graced: Array = []
var _last_ppos := Vector3.ZERO
var _slam_from_bell := false
var _was_slamming := false
const LB_BOX := AABB(Vector3(-46, 40, -44), Vector3(28, 14, 36))


## Catch zones (no heart lost, Mak is set back at the start of the section he fell from) and the catch cloud
## under the Giant's bell.
func _fix1_setup() -> void:
	var leaf_start := Vector3(-17.0, 44.05, -9.2)
	# Fix r2: grown to x -47..-17 and z -44..-10 so a short jump for LB1 off the UC rim is caught here too.
	_catch_zone("CatchLeafBouncer", AABB(Vector3(-47, 37.5, -44), Vector3(30, 3, 34)), leaf_start, _yaw_to(leaf_start, Vector3(-24.5, 0, -12.5)), "A cloud catches you. Again!")
	var hop_start := Vector3(-13.6, 24.05, -11.4)
	_catch_zone("CatchCloudHopper", AABB(Vector3(-40, 15, -24), Vector3(32, 4.5, 26)), hop_start, 90.0, "Whoops! Back to the start of the hop.")
	_catch_zone("CatchBell", AABB(Vector3(-18.5, 51, -17), Vector3(9.3, 7, 6)), Vector3(-6.0, 50.05, -19.5), 90.0, "Caught by a cloud! Up the vine again.")
	# The catch cloud reads under the bell's swing arc.
	var m = M.new()
	var c := Vector3(-12.0, 55.0, -14.5)
	for k in 7:
		var a := TAU * float(k) / 7.0
		var r := 0.0 if k == 0 else 1.6
		m.sphere(Transform3D(Basis().scaled(Vector3(1.4, 0.7, 1.2) * (1.15 if k == 0 else 0.85)), c + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.8)), Color("f4ecf6"), 14, 8, Color("a596d6"))
	_mesh(world, m.commit(b.cloud_mat() if b.has_method("cloud_mat") else b.vc_mat(0.5)), "BellCatchCloud")


func _yaw_to(a: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(-(to.x - a.x), -(to.z - a.z)))


func _catch_zone(n: String, box: AABB, to: Vector3, yaw_deg: float, line: String) -> void:
	var a := Area3D.new()
	a.name = n
	a.collision_layer = 128
	a.collision_mask = 2
	a.position = box.get_center()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	cs.shape = bs
	a.add_child(cs)
	world.add_child(a)
	a.body_entered.connect(func(body: Node) -> void:
		if not body.is_in_group("player") or _sneezing:
			return
		var pb := body as Node3D
		_fx("CloudPuff", pb.global_position)
		_sfx("cloud_poof", pb.global_position)
		# Fix r2 (fun critic: catches removed all stakes): a running catch counter, and every third catch in a row
		# on the same section costs a heart (never the last one).
		var now := Time.get_ticks_msec()
		var cnt := int(a.get_meta("catches", 0))
		if now - int(a.get_meta("last_catch", 0)) > 45000:
			cnt = 0
		cnt += 1
		a.set_meta("catches", cnt)
		a.set_meta("last_catch", now)
		var said := line
		if cnt >= 2:
			said = "%s (catch no. %d)" % [line, cnt]
		var game := get_node_or_null("/root/Game")
		if cnt % 3 == 0 and game and int(game.get("health")) > 1 and game.has_method("damage"):
			game.call("damage", 1)
			said = "The cloud is getting tired of catching you... (-1 heart)"
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), to)
		if body.has_method("respawn"):
			body.call_deferred("respawn", xf)
		else:
			pb.set_deferred("global_transform", xf)
		_toast(said)
		_fx.call_deferred("CloudPuff", to + Vector3(0, 0.5, 0)))


func _on_player_jumped(kind: String) -> void:
	# Fix r1: a Leaf Bouncer pad re-aims Mak at the stick direction on every bounce (the controller locks facing in
	# the air, so the chain's 50 degree turn was otherwise unsteerable).
	if kind != "bounce" or player == null or not LB_BOX.has_point(player.global_position):
		return
	var dir: Variant = player.get("intended_dir")
	if dir is Vector3 and (dir as Vector3).length() > 0.3:
		var fy: Variant = player.get("intended_yaw")
		if fy != null:
			player.set("facing_yaw", float(fy))
			player.set("side_speed", 0.0)
			player.set("forward_speed", maxf(float(player.get("forward_speed")), 4.2))


func _fix1_physics(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var pp := player.global_position
	# A teleport (spawn, respawn, catch zone) starts a short grace: enemies near Mak hold fire for 3 s.
	if pp.distance_to(_last_ppos) > 6.0:
		_grace_t = 5.0  # finishing pass: E04 still reached Mak 4.3 s after a CP2 respawn (feel r1c)
	_last_ppos = pp
	if _grace_t > 0.0:
		_grace_t -= delta
		if play:
			for id in play.nodes.keys():
				if not String(id).begins_with("E") or id in ["E10", "E13", "E16", "E17"]:
					continue
				var e := _pn(id) as Node3D
				if e == null or _graced.has(e):
					continue
				if e.global_position.distance_to(pp) < 12.0 and e.get("ai_enabled") != null and bool(e.get("ai_enabled")):
					e.set("ai_enabled", false)
					_graced.append(e)
		if _grace_t <= 0.0:
			for e in _graced:
				if is_instance_valid(e):
					e.set("ai_enabled", true)
			_graced.clear()
	# Slam bookkeeping for the bell: a slam that starts within 2.5 m above the plate always rings it.
	var st := String(player.call("get_state_name")) if player.has_method("get_state_name") else ""
	var slamming := st == "ham_slam"
	if slamming and not _was_slamming and bell:
		_slam_from_bell = pp.distance_to(bell.global_transform * Vector3(0, -3.0, 0)) < 2.5 + 1.5
	elif not slamming and st != "slam_land":
		_slam_from_bell = false
	_was_slamming = slamming


# ------------------------------------------------------------------ fix round 1: W2-5 bee-bait puzzle (amendments r2 s5)

const BUD_C := Vector3(7.2, 36.1, -6.0)
var _bee_state := 0
var _bee_t := 0.0
var _bee_from := Vector3.ZERO
var _bee_to := Vector3.ZERO


## When Mak stands between the cross bumble E10 and the shut bluebell, the bee flies to his far side, glints and
## buzzes for 0.8 s, then charges 9 m along the line. Mak hops aside (or ducks; it flies high) and the bee
## ploughs into the bud: BOING, the cup opens and the bee is left dizzy.
func _bee_bait(delta: float) -> void:
	var bee := _pn("E10") as Node3D
	if bee == null or bool(bee.get("is_defeated")):
		_bee_state = 0
		return
	var pp := player.global_position
	_bee_t += delta
	match _bee_state:
		0:
			var flat_b := Vector2(pp.x - BUD_C.x, pp.z - BUD_C.z)
			if _bee_t > 1.0 and bee.global_position.distance_to(pp) < 7.5 and flat_b.length() < 6.0 and absf(pp.y - BUD_C.y) < 4.0:
				var away := Vector3(flat_b.x, 0, flat_b.y)
				away = away.normalized() if away.length() > 0.3 else Vector3(-1, 0, 0)
				_bee_from = bee.global_position
				_bee_to = Vector3(pp.x, BUD_C.y, pp.z) + away * 4.5
				_bee_state = 1
				_bee_t = 0.0
				bee.set("ai_enabled", false)
				_toast("Bzzz?! The bumble is lining up a charge...")
		1:
			bee.global_position = _bee_from.lerp(_bee_to, ease(clampf(_bee_t / 0.8, 0.0, 1.0), -2.0))
			_face(bee, BUD_C)
			if _bee_t >= 0.8:
				_bee_state = 2
				_bee_t = 0.0
				_sfx("bee_buzz", bee.global_position)
				_fx("Sparkle", bee.global_position + Vector3(0, 1.6, 0))
		2:
			# Hold, buzzing and wobbling: the tell.
			bee.global_position = _bee_to + Vector3(sin(_bee_t * 40.0) * 0.06, 0, 0)
			_face(bee, BUD_C)
			if _bee_t >= 0.8:
				_bee_state = 3
				_bee_t = 0.0
				_bee_from = _bee_to
				_sfx("whoosh", bee.global_position)
		3:
			var dir := (BUD_C - _bee_from)
			dir.y = 0.0
			dir = dir.normalized()
			var p := _bee_from + dir * minf(_bee_t * 11.0, 9.0)
			p.y = BUD_C.y
			bee.global_position = p
			if p.distance_to(BUD_C) < 2.3:
				play.open_bud("bee")
				_sfx("leaf_boing", BUD_C)
				_toast("BOING! The bumble bounces off the bluebell, seeing stars.")
				_fx("DizzyStars", bee.global_position + Vector3(0, 1.8, 0))
				if bee.has_method("set_state"):
					bee.call("set_state", "dizzy")
				_bee_state = 4
				_bee_t = 0.0
			elif _bee_t * 11.0 >= 9.0:
				_bee_state = 4
				_bee_t = 0.0
		4:
			if _bee_t > 2.5:
				bee.set("ai_enabled", true)
				if bee.has_method("set_state"):
					bee.call("set_state", "patrol")
				_bee_state = 0
				_bee_t = 0.0


func _face(n: Node3D, at: Vector3) -> void:
	var d := at - n.global_position
	if Vector2(d.x, d.z).length() > 0.1:
		n.rotation.y = atan2(-d.x, -d.z)


# ------------------------------------------------------------------ fix round 1: W2-6 lane stun and SPARE/STRIKE

const LANES_Z := [-13.5, -8.5, -3.5, 1.5, 6.5]
var _slide_count := 0
var _slide_id := 0
var _stunned_pods := {}   # pod -> seconds left


func _pod_lane_slam(pos: Vector3) -> void:
	var near: Node3D = null
	for pod in play.poppers:
		if is_instance_valid(pod) and not bool(pod.get("is_defeated")) and Vector2(pod.global_position.x - pos.x, pod.global_position.z - pos.z).length() < 2.3:
			near = pod
	if near == null:
		return
	var lane_z := near.global_position.z
	var n := 0
	for pod in play.poppers:
		if is_instance_valid(pod) and not bool(pod.get("is_defeated")) and absf(pod.global_position.z - lane_z) < 1.2:
			n += 1
			_stunned_pods[pod] = 4.0  # fix r2: 4 s, room to back off and build dive speed for a STRIKE
			pod.set("ai_enabled", false)
			if pod.has_method("stunned"):
				pod.call("stunned", true)
			var v := pod.get_node_or_null("Visual") as Node3D
			var tw := create_tween()
			tw.tween_property(pod, "global_position:y", pod.global_position.y + 0.4, 0.15)
			tw.tween_property(pod, "global_position:y", pod.global_position.y, 0.25).set_trans(Tween.TRANS_BOUNCE)
			if v:
				v.rotation.z = deg_to_rad(80.0)
			_fx("DizzyStars", pod.global_position + Vector3(0, 1.0, 0))
	_fx("SlamShockwave", Vector3(pos.x, near.global_position.y, lane_z))
	_toast("The whole row keels over! %d pod%s stunned. Belly slide!" % [n, "" if n == 1 else "s"])


func _pods_step(delta: float) -> void:
	for pod in _stunned_pods.keys():
		if not is_instance_valid(pod):
			_stunned_pods.erase(pod)
			continue
		_stunned_pods[pod] = float(_stunned_pods[pod]) - delta
		if float(_stunned_pods[pod]) <= 0.0:
			_stunned_pods.erase(pod)
			if not bool(pod.get("is_defeated")):
				pod.set("ai_enabled", true)
				if pod.has_method("stunned"):
					pod.call("stunned", false)
				var v := pod.get_node_or_null("Visual") as Node3D
				if v:
					v.rotation.z = 0.0
	if player and player.has_method("get_state_name"):
		var st := String(player.call("get_state_name"))
		if not (st in ["belly_slide", "crouch_slide", "dive", "slide_getup"]):
			if _slide_count >= 2:
				_slide_bonus(_slide_count)
			_slide_count = 0


func on_pod_bowled(_pod: Node) -> void:
	if player == null or not player.has_method("get_state_name"):
		return
	var st := String(player.call("get_state_name"))
	if st in ["belly_slide", "crouch_slide", "dive"]:
		_slide_count += 1
		if _slide_count == 3:
			_slide_bonus(3)
			_slide_count = -99


func _slide_bonus(n: int) -> void:
	var game := get_node_or_null("/root/Game")
	if n >= 3:
		_toast("STRIKE!  +10 acorns")
		_toast("Scarecrow: \"Not the peas!\"")
		if game and game.has_method("add_acorns"):
			game.call("add_acorns", 10)
		_fx("Confetti", player.global_position + Vector3(0, 1, 0))
	elif n == 2:
		_toast("SPARE!  +4 acorns")
		if game and game.has_method("add_acorns"):
			game.call("add_acorns", 4)
		_fx("Sparkle", player.global_position + Vector3(0, 1, 0))


## Fix r1 (60 fps bar): small meshes (acorns, flowers, props under 2.5 m) stop drawing beyond 60 m and the
## smallest ones stop casting sun shadows; nothing on the player is touched.
func _perf_pass() -> void:
	var n_range := 0
	var n_shadow := 0
	for n in world.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi is MultiMeshInstance3D or gi.visibility_range_end > 0.0:
			continue
		var cur: Node = gi
		var skip := false
		while cur != null and cur != world:
			if cur.is_in_group("player") or cur.name == "StoryCams" or cur.name == "GoalBeacon":
				skip = true
				break
			cur = cur.get_parent()
		if skip:
			continue
		var bb := gi.get_aabb()
		var sz := (gi.global_transform.basis * bb.size).abs()
		var m := maxf(sz.x, maxf(sz.y, sz.z))
		if m <= 0.0 or m > 2.5:
			continue
		gi.visibility_range_end = 60.0 if m > 1.0 else 45.0
		gi.visibility_range_end_margin = 6.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		n_range += 1
		if m < 1.2 and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n_shadow += 1
	print("[W2] perf pass: %d small meshes range-culled, %d shadow casters removed" % [n_range, n_shadow])
