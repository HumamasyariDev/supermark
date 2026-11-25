extends Node3D
## W2-4 "The Harpnapper": Captain Caw (E17), a Crow Bandit who has stuffed the Golden Harp in his loot sack.
## He hops between perches over the swinging Leaf Bouncer pads: TAUNT -> PERCH1 (over LB2) -> PERCH2 (over LB4)
## -> TREE (blossom tree on the islet). Mak jump-kicks him at the top of a bounce (hits 1 and 2), then Ham Slams
## the islet beside the trunk to shake him down dizzy and punches the sack open (hit 3). Body contact never
## hurts Mak: Caw just flaps up out of reach. Uses the real crow_bandit.glb model.

signal hit_taken(count: int)
signal defeated

const CROW_GLB := "res://assets/enemies/crow_bandit/crow_bandit.glb"
const SACK_POS := Vector3(0.2, -0.95, 0.15)

var perches := {
	"TAUNT": Vector3(-20.0, 44.8, -10.0),
	"PERCH1": Vector3(-29.5, 49.6, -16.5),
	"PERCH2": Vector3(-38.0, 50.6, -26.0),
	"TREE": Vector3(-41.6, 50.2, -39.0),
}
var stage := "TAUNT"
var hits := 0
var dizzy := 0.0
var is_defeated := false
var _target := Vector3.ZERO
var _flap := 0.0
var _t := 0.0
var _cool := 0.0
var _taunted := false
var visual: Node3D
var hurt: Area3D
var wind: Node   # optional w2_wind crosswind (drift during gusts)
## Round 3: at PERCH1/PERCH2 Caw follows the swinging pad below him (LB2, LB4) with a short lag.
var track := {}  # perch name -> Node3D pad


func _ready() -> void:
	add_to_group("w2_caw")
	position = perches[stage]
	_target = position
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	if ResourceLoader.exists(CROW_GLB) and load(CROW_GLB) is PackedScene:
		var g := (load(CROW_GLB) as PackedScene).instantiate() as Node3D
		g.rotation.y = PI  # glTF faces +Z; Caw faces -Z like every body
		# Fix r2 (visual critic): bigger than the crow enemies (1.6x) and a gold captain's mask and neckerchief
		# (the model's red cloth is remapped to #E8B23A), so he never reads as a plain E03/E04.
		g.scale = Vector3.ONE * 1.6
		visual.add_child(g)
		_captain_colours(g)
	# Fix r1: no primitive hat (crow_bandit.glb already reads as a bandit). The loot sack hangs 0.8 m below him on a
	# rope: a lumpy burlap sack with the real Golden Harp model poking out of its mouth, glinting gold.
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	var sack_root := Node3D.new()
	sack_root.name = "Sack"
	sack_root.position = SACK_POS
	sack_root.set_meta("base_scale", 1.6)  # fix r2: about 1.15 m across, so the target reads at pad distance
	visual.add_child(sack_root)
	var m = M.new()
	m.tube(PackedVector3Array([Vector3(0, 0.95, 0), Vector3(0.02, 0.6, 0.01), Vector3(0, 0.38, 0)]), PackedFloat32Array([0.025, 0.025, 0.025]), Color("8a6a3a"), 6)
	m.sphere(Transform3D(Basis().scaled(Vector3(0.36, 0.32, 0.34)), Vector3(0, 0.0, 0)), Color("c9a46a"), 16, 10, Color("8f6a3c"))
	m.sphere(Transform3D(Basis().scaled(Vector3(0.2, 0.18, 0.2)), Vector3(0.16, -0.12, 0.12)), Color("bf9860"), 12, 8, Color("8f6a3c"))
	m.sphere(Transform3D(Basis().scaled(Vector3(0.18, 0.16, 0.18)), Vector3(-0.15, -0.08, -0.1)), Color("c49c64"), 12, 8, Color("8f6a3c"))
	m.torus(Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.14, 0.04, Color("6b4a2a"), 14, 6)
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.roughness = 0.9
	smat.rim_enabled = true
	smat.rim = 0.4
	var smi := MeshInstance3D.new()
	smi.mesh = m.commit(smat)
	sack_root.add_child(smi)
	var hp := "res://assets/props/w2/golden_harp/golden_harp.glb"
	if ResourceLoader.exists(hp) and load(hp) is PackedScene:
		var h := (load(hp) as PackedScene).instantiate() as Node3D
		h.name = "HarpPeek"
		h.scale = Vector3.ONE * 0.42
		h.position = Vector3(0.02, 0.18, 0.04)
		h.rotation = Vector3(0.25, 0.4, -0.2)
		sack_root.add_child(h)
	var glint := OmniLight3D.new()
	glint.light_color = Color("ffc93c")
	glint.light_energy = 1.8
	glint.omni_range = 2.6
	glint.position = Vector3(0, 0.35, 0)
	sack_root.add_child(glint)
	hurt = Area3D.new()
	hurt.name = "Hurtbox"
	hurt.collision_layer = 64
	hurt.collision_mask = 2
	hurt.monitorable = true
	hurt.monitoring = true
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.45  # fix r2: at least 1.4 (fun critic)
	cs.shape = sp
	cs.position = SACK_POS  # the loot sack hangs below him: it is the target
	hurt.add_child(cs)
	add_child(hurt)
	hurt.body_entered.connect(_on_body)
	_kick = Label3D.new()
	_kick.name = "KickPrompt"
	_kick.text = "KICK!"
	_kick.font_size = 96
	_kick.outline_size = 24
	_kick.modulate = Color("ffd23c")
	_kick.outline_modulate = Color("5a2a10")
	_kick.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_kick.no_depth_test = true
	_kick.pixel_size = 0.006
	_kick.position = SACK_POS + Vector3(0, -1.3, 0)
	_kick.visible = false
	add_child(_kick)


var _kick: Label3D


## The crow model shares one texture; its red bandit cloth is remapped to captain's gold.
func _captain_colours(g: Node3D) -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
uniform bool has_nrm = false;
void fragment() {
	vec4 c = texture(tex, UV);
	float red = smoothstep(0.08, 0.25, c.r - max(c.g, c.b));
	vec3 gold = vec3(0.807, 0.445, 0.042) * (0.55 + 1.6 * c.r);
	ALBEDO = mix(c.rgb, gold, red);
	ROUGHNESS = mix(0.75, 0.35, red);
	METALLIC = 0.25 * red;
	if (has_nrm) { NORMAL_MAP = texture(nrm, UV).rgb; }
	RIM = 0.35;
	RIM_TINT = 0.5;
}
"""
	for n in g.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si) as BaseMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("tex", src.albedo_texture)
			if src.normal_enabled and src.normal_texture:
				m.set_shader_parameter("nrm", src.normal_texture)
				m.set_shader_parameter("has_nrm", true)
			mi.set_surface_override_material(si, m)


func hit_by_player(kind: String, _from: Vector3) -> bool:
	if is_defeated or _cool > 0.0:
		return false
	if stage == "TAUNT":
		# Fix r1: he is out of reach until the chase starts (a hit here used to skip PERCH1 entirely).
		_flap = 1.2
		_say("Captain Caw: \"Missed me! Catch me over the leaves, piglet!\"")
		approach_taunt()
		return false
	if stage == "TREE" and dizzy <= 0.0:
		# He sulks out of reach in the crown until the trunk is slammed.
		_say("Captain Caw: \"Nyah! Can't reach me up here!\"")
		return false
	_cool = 0.6
	hits += 1
	hit_taken.emit(hits)
	_burst("FeatherBurst")
	_sfx("crow_caw")
	match stage:
		"PERCH1":
			_drop_acorns(3)
			_say("Captain Caw: \"Ow! My good feathers!\"")
			_go("PERCH2")
		"PERCH2":
			_drop_acorns(3)
			_say("Captain Caw: \"Right, I'm sulking in the tree!\"")
			_go("TREE")
		"TREE":
			_defeat()
	return true


## Called by the world when Mak Ham Slams the islet next to the blossom-tree trunk.
func shake_down() -> void:
	if stage != "TREE" or is_defeated:
		return
	dizzy = 2.5
	_target = Vector3(-41.0, 46.1, -38.0)
	_say("Captain Caw: \"Whoa-oh-oh!\" (dizzy)")
	_sfx("crow_caw")


func approach_taunt() -> void:
	if _taunted:
		return
	_taunted = true
	_say("Captain Caw: \"Finders keepers, piglet!\"")
	_say("Golden Harp (in the sack): \"La-la-LAAA! I am being HARPNAPPED!\"")
	_go("PERCH1")


func _go(p: String) -> void:
	stage = p
	_target = perches[p]


func _defeat() -> void:
	is_defeated = true
	_burst("FeatherBurst")
	_burst("Confetti")
	_say("Golden Harp: \"At last, an audience!\"")
	defeated.emit()
	var tw := create_tween()
	tw.tween_property(self, "position", position + Vector3(6, 14, -10), 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "rotation:z", 12.0, 2.2)
	tw.tween_callback(queue_free)


func _on_body(body: Node) -> void:
	if is_defeated or not body.is_in_group("player"):
		return
	# Touched without attacking: flap up out of reach ("Missed me!").
	if body.has_method("is_attacking") and bool(body.call("is_attacking")):
		return
	if dizzy <= 0.0:
		_flap = 1.2
		_say("Captain Caw: \"Missed me!\"")


func _physics_process(delta: float) -> void:
	_t += delta
	_cool = maxf(0.0, _cool - delta)
	if is_defeated:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and not _taunted and player.global_position.distance_to(perches["TAUNT"]) < 8.0:
		approach_taunt()
	var goal := _target
	if dizzy > 0.0:
		dizzy -= delta
		if dizzy <= 0.0:
			_target = perches["TREE"]
			_say("Captain Caw: \"Back to my tree!\"")
	else:
		if track.has(stage) and is_instance_valid(track[stage]):
			var pad: Node3D = track[stage]
			var base: Vector3 = perches[stage]
			goal = Vector3(pad.global_position.x, base.y, pad.global_position.z)
		else:
			goal += Vector3(0, sin(_t * 2.4) * 0.2, 0)
			if wind and wind.has_method("current_phase") and String(wind.call("current_phase")) == "gust":
				goal += Vector3(0.7, 0, -0.7).normalized()
	if _flap > 0.0:
		_flap -= delta
		goal += Vector3(0, 1.5, 0)
	position = position.lerp(goal, 1.0 - exp(-(7.0 if track.has(stage) else 4.0) * delta))
	if player:
		var to := player.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-6.0 * delta))
	visual.rotation.z = sin(_t * 9.0) * 0.6 if dizzy > 0.0 else sin(_t * 3.0) * 0.08
	# The sack wriggles: the harp inside is singing.
	var sk := visual.get_node_or_null("Sack") as Node3D
	if sk:
		sk.rotation = Vector3(sin(_t * 5.3) * 0.18, 0.0, sin(_t * 4.1) * 0.22)
		var k := 1.0 + sin(_t * 7.0) * 0.05
		var bs := float(sk.get_meta("base_scale", 1.0))
		sk.scale = Vector3(k, 2.0 - k, k) * bs
	# First hit only: a KICK! prompt when Mak rises to the sack's height under it.
	if _kick:
		var show := false
		if hits == 0 and stage == "PERCH1" and player is CharacterBody3D:
			var pv := (player as CharacterBody3D).velocity
			var sp_ := global_position + SACK_POS
			var dxz := Vector2(player.global_position.x - sp_.x, player.global_position.z - sp_.z).length()
			show = dxz < 2.2 and absf(pv.y) < 4.5 and absf(player.global_position.y + 0.6 - sp_.y) < 1.6
		_kick.visible = show
		if show:
			_kick.scale = Vector3.ONE * (1.0 + 0.15 * sin(_t * 16.0))


func _drop_acorns(n: int) -> void:
	if ResourceLoader.exists("res://scenes/objects/Acorn.tscn"):
		for i in n:
			var a := (load("res://scenes/objects/Acorn.tscn") as PackedScene).instantiate() as Node3D
			get_parent().add_child(a)
			a.global_position = global_position + Vector3(randf_range(-0.6, 0.6), -0.4, randf_range(-0.6, 0.6))
			if a.has_method("pop_out"):
				a.call("pop_out", Vector3(randf_range(-2, 2), 4.0, randf_range(-2, 2)))


func _burst(scene: String) -> void:
	var path := "res://scenes/fx/%s.tscn" % scene
	if ResourceLoader.exists(path):
		var fx := (load(path) as PackedScene).instantiate() as Node3D
		get_parent().add_child(fx)
		fx.global_position = global_position + Vector3(0, 0.5, 0)


func _say(text: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.toast(text)


func _sfx(key: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_sfx(key, global_position)
