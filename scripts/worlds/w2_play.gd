extends RefCounted
## W2 Beanstalk Skyway: gameplay nodes (owned by the W2 world builder).
## Places checkpoints, truffles and their missions, switches and the goose cage, lost pages, acorns,
## climbable vines, vanishing puff clouds, enemies, wind hazards, the Beanpod Lift and dev markers,
## all from w2_level.json, using the shared object and enemy scenes.

const OBJ := "res://scenes/objects/"
const ENEMY := "res://scenes/enemies/"
const WindZoneScript := preload("res://scripts/worlds/w2_wind.gd")
const GRAVITY := 28.0

var world: Node3D
var data: Dictionary
var b  # w2_build.gd instance
var holder: Node3D
var nodes := {}
var poppers: Array[Node] = []
var pod_spawner: Node
var snore: Area3D
var nose_pull: Area3D
var sniffle: Area3D
var crosswind: Area3D
var lift: AnimatableBody3D
var lift2: AnimatableBody3D
var puffs: Array[Node] = []
var truffles := {}


func build(w: Node3D, d: Dictionary, builder) -> void:
	world = w
	data = d
	b = builder
	holder = Node3D.new()
	holder.name = "Gameplay"
	world.add_child(holder)
	_checkpoints()
	_truffles()
	_goose_mission()
	_pages()
	_pod_patrol()
	_cloud_hopper()
	_acorns()
	_hundred()
	_climbables()
	_puffs()
	_enemies()
	_hazards()
	_lift()
	_npcs()
	_dev_markers()
	_harpnapper()
	_hive_bud()
	_reginald()


static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func inst(scene: String, props: Dictionary, pos: Vector3, rot_y_deg := 0.0, parent: Node = null, n := "") -> Node3D:
	var path := scene if scene.begins_with("res://") else OBJ + scene + ".tscn"
	if not ResourceLoader.exists(path):
		push_warning("[W2] missing scene " + path)
		return null
	var node := (load(path) as PackedScene).instantiate() as Node3D
	for k in props.keys():
		node.set(k, props[k])
	if n != "":
		node.name = n
	node.position = pos
	node.rotation.y = deg_to_rad(rot_y_deg)
	(parent if parent else holder).add_child(node)
	# Enemy _ready()/_setup() may reset tuning values: apply them again after the node is in the tree
	# (critic round 1 blocker: E01's 5.5 m notice radius became 12 m and Mak was shot at the gate).
	for k in TUNE_KEYS:
		if props.has(k):
			node.set(k, props[k])
	return node


const TUNE_KEYS := ["notice_radius", "lose_radius", "reload_time", "patrol_wait", "ai_enabled", "aggressive"]


## Returns the existing child `n` of a scene instance (object scenes ship default children) or a new one.
func child_of(parent: Node, n: String, make: Callable) -> Node:
	var c := parent.get_node_or_null(n)
	if c == null:
		c = make.call()
		c.name = n
		parent.add_child(c)
	return c


func marker_at(parent: Node, pos_local: Vector3) -> void:
	var m := child_of(parent, "TruffleMarker", func() -> Node: return Marker3D.new()) as Node3D
	m.position = pos_local


## Round 3 models first (v2 files per the meshes READMEs), the v1 file as the fallback.
func _glb_v(path: String, fallback: String) -> PackedScene:
	var s := _glb_scene(path)
	return s if s else _glb_scene(fallback)


func _glb_scene(path: String) -> PackedScene:
	return load(path) as PackedScene if ResourceLoader.exists(path) else null


# ------------------------------------------------------------------ checkpoints and truffles

func _checkpoints() -> void:
	var cps := Node3D.new()
	cps.name = "Checkpoints"
	holder.add_child(cps)
	for c in data.get("checkpoints", []):
		var p := v3(c["pos"])
		if String(c["id"]) == "CP6":
			p = Vector3(2.4, 54.4, -35.4)  # chair seat corner (the chair moved 0.6 m toward the table)
		if String(c["id"]) == "CP0":
			p = Vector3(-5.0, b.island_h(-5.0, 30.8), 30.8)  # finishing pass: was (-3.6, 32.2), which still filled the opening frame's left third
		if String(c["id"]) == "CP3":
			p = Vector3(13.0, 24.0, 0.5)  # fix r1: at least 4 m from every pod mound (PM07 was 0.7 m away)
		# Fix r1: every respawn yaw points at the next goal, never at the void.
		var mission := _mission()
		var face := 0.0
		match String(c["id"]):
			"CP0": face = 0.0
			"CP1": face = 90.0
			"CP2": face = 90.0
			"CP3": face = -90.0
			"CP4": face = 72.0 if mission == "W2-4" else -90.0
			"CP5": face = -53.0
			"CP6": face = 90.0
			"CP7": face = 90.0
			"CP2b": face = -14.0
		var cprops := {"world_id": "W2"}
		if String(c["id"]) == "CP6":
			cprops["respawn_offset"] = Vector3(-1.2, 0, 0)  # fix r2: lands on the footstool seat (world +z), no fallback
		inst("Checkpoint", cprops, p, face, cps, String(c["id"]))


func _mission() -> String:
	var game := world.get_node_or_null("/root/Game")
	return String(game.get("current_mission")) if game else ""


func _truffles() -> void:
	var titles := {}
	for t in data.get("truffles", []):
		titles[String(t["id"])] = String(t["title"])
	for id: String in ["W2-1", "W2-3", "W2-8"]:
		var t: Dictionary = {}
		for x in data["truffles"]:
			if String(x["id"]) == id:
				t = x
		var node := inst("Truffle", {"truffle_id": id, "mission_title": titles.get(id, "")}, v3(t["pos"]), 0.0, holder, "Truffle_" + id)
		truffles[id] = node


# ------------------------------------------------------------------ W2-2 Free the Golden Goose

func _goose_mission() -> void:
	var sw_paths: Array[NodePath] = []
	for s in data.get("switches", []):
		var n := "Switch_" + String(s["id"])
		var sw := inst("SlamSwitch", {"radius": 0.9}, v3(s["pos"]), 0.0, holder, n)
		nodes[n] = sw
		sw_paths.append(NodePath("../" + n))
	var plinth := Vector3(13, 50.8, -35)
	var cage_scene := _glb_scene("res://assets/props/w2/goose_cage/goose_cage.glb")
	# Round 1: the caged "goose" is a Woolly Wolf in a goose costume; the real goose hides under the tea cosy.
	var props := {"reward_truffle_id": "", "switches": sw_paths, "radius": 1.45, "height": 3.4}
	if cage_scene:
		props["visual_scene"] = cage_scene
		props["visual_scale"] = 1.4
	var cage_path := OBJ + "Cage.tscn"
	var cage := (load(cage_path) as PackedScene).instantiate() as Node3D
	for k in props.keys():
		cage.set(k, props[k])
	cage.name = "GooseCage"
	cage.position = plinth
	marker_at(cage, Vector3(0, 0, 2.6))
	var contents := child_of(cage, "Contents", func() -> Node: return Node3D.new()) as Node3D
	var goose_scene := _glb_scene("res://assets/characters/golden_goose/golden_goose.glb")
	if goose_scene:
		var g := goose_scene.instantiate() as Node3D
		g.name = "Goose"
		g.scale = Vector3.ONE * 1.55
		g.rotation.y = 0.0  # glTF faces +Z: toward the gate side of the courtyard (south)
		g.position = Vector3(0, 0.3, 0)
		contents.add_child(g)
		nodes["Goose"] = g
	holder.add_child(cage)
	nodes["GooseCage"] = cage
	# The "goose" stays visible while caged (Contents is only process-disabled by the cage).
	contents.visible = true
	# Tea cosy on the hearth with the real Golden Goose asleep under it, and the W2-2 reward spawner.
	var tc: Dictionary = b.plat.get("TEA_COSY", {})
	var tpos := v3(tc["pos"]) if not tc.is_empty() else Vector3(-14, 50, -40.5)
	tpos = Vector3(tpos.x, 50.0, -39.3)  # in front of the hearth box (z -42..-40.4)
	var cosy := Area3D.new()
	cosy.set_script(preload("res://scripts/worlds/w2_target.gd"))
	cosy.name = "TeaCosy"
	cosy.position = tpos
	cosy.set("radius", 0.95)
	cosy.set("height", 1.3)
	holder.add_child(cosy)
	nodes["TeaCosy"] = cosy
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	var cm = M.new()
	cm.sphere(Transform3D(Basis().scaled(Vector3(0.95, 1.15, 0.8)), Vector3(0, 0.05, 0)), Color("f4a6b8"), 20, 12, Color("d27a92"), -0.05)
	for k in 6:
		var a := TAU * float(k) / 6.0
		cm.sphere(Transform3D(Basis().scaled(Vector3(0.16, 0.16, 0.06)), Vector3(cos(a) * 0.9, 0.55, sin(a) * 0.75)), Color("e8414b"), 8, 5)
	cm.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.2), Vector3(0, 1.2, 0)), Color("fff3f6"), 10, 6)
	var cmi := MeshInstance3D.new()
	cmi.name = "CosyMesh"
	cmi.mesh = cm.commit(b.vc_mat(0.4))
	cosy.add_child(cmi)
	var cbody := StaticBody3D.new()
	cbody.collision_layer = 1
	var ccs := CollisionShape3D.new()
	var ccy := CylinderShape3D.new()
	ccy.radius = 0.85
	ccy.height = 1.2
	ccs.shape = ccy
	ccs.position = Vector3(0, 0.6, 0)
	cbody.add_child(ccs)
	cosy.add_child(cbody)
	if goose_scene:
		var rg := goose_scene.instantiate() as Node3D
		rg.name = "RealGoose"
		rg.scale = Vector3.ONE * 1.25
		rg.visible = false
		rg.position = tpos + Vector3(0.0, 0.0, 0.2)
		holder.add_child(rg)
		nodes["RealGoose"] = rg
	var gs := TruffleSpawner.new()
	gs.name = "GooseReward"
	gs.set("reward_truffle_id", "W2-2")
	var gm := Marker3D.new()
	gm.name = "TruffleMarker"
	gm.position = Vector3(-13.0, 50.0, -39.6) if tc.is_empty() else Vector3(-12.6, 50.0, -38.4)
	gs.add_child(gm)
	holder.add_child(gs)
	nodes["GooseReward"] = gs


# ------------------------------------------------------------------ W2-5 Lost Pages

func _pages() -> void:
	var ps := inst("LostPageSet", {"world_id": "W2", "reward_truffle_id": "W2-5", "required": 5}, Vector3.ZERO, 0.0, holder, "LostPageSet")
	if ps:
		marker_at(ps, Vector3(9, 1.0, 22))
	for p in data.get("pages", []):
		inst("LostPage", {"world_id": "W2", "page_index": int(p["index"])}, v3(p["pos"]), 0.0, holder, "Page%d" % (int(p["index"]) + 1))


# ------------------------------------------------------------------ W2-6 Pea Pod Patrol

func _pod_patrol() -> void:
	pod_spawner = TruffleSpawner.new()
	pod_spawner.name = "PodPatrolReward"
	pod_spawner.set("reward_truffle_id", "W2-6")
	var m := Marker3D.new()
	m.name = "TruffleMarker"
	m.position = Vector3(24, 24, 0.5)
	pod_spawner.add_child(m)
	holder.add_child(pod_spawner)


func _on_popper_defeated(_e: Node) -> void:
	# Fix r1: SPARE/STRIKE bonus for pods bowled over in one belly slide (counted by w2_life).
	var life := world.get_node_or_null("W2Life")
	if life and life.has_method("on_pod_bowled"):
		life.call("on_pod_bowled", _e)
	var left := 0
	for p in poppers:
		if is_instance_valid(p) and not bool(p.get("is_defeated")):
			left += 1
	var ui := world.get_node_or_null("/root/UI")
	if left > 0:
		if ui and ui.has_method("toast"):
			ui.toast("Pea pods left: %d" % left)
		if left == poppers.size() - 3:
			# Round 1 escalation: the scarecrow calls in the bees.
			if ui and ui.has_method("toast"):
				ui.toast("Scarecrow: \"Reinforcements!\"")
			for bid in ["E11", "E12"]:
				var bee: Node = nodes.get(bid)
				if bee and is_instance_valid(bee):
					bee.set("notice_radius", 9.0)
	elif pod_spawner and pod_spawner.has_method("give_reward"):
		pod_spawner.call("give_reward")


# ------------------------------------------------------------------ W2-7 Cloud Hopper

## Fix r2: the Cloud Hopper limit (was a 46 s guess, about 100% slack). The route is 60 m of horizontal travel in
## 12 hops (about 1.0 s of air each plus run-ups and the PUFF07 rest), so a clean run takes about 17-20 s;
## 30 s follows the fun critic's estimate (median plus about 25%) until a real-input run times it.
## The last five seconds tick (w2_fix2.gd).
const TRIAL_LIMIT := 30.0


func _cloud_hopper() -> void:
	var tt: Node3D = (load(OBJ + "TimeTrial.tscn") as PackedScene).instantiate() as Node3D if ResourceLoader.exists(OBJ + "TimeTrial.tscn") else null
	if tt == null:
		return
	tt.name = "CloudHopper"
	tt.set("time_limit", TRIAL_LIMIT)  # fix r2: see TRIAL_LIMIT
	tt.set("trial_label", "Cloud Hopper")
	tt.set("reward_truffle_id", "W2-7")
	tt.set("ordered", true)  # fix r1: the course reads as a route
	var start := child_of(tt, "StartGate", func() -> Node: return Node3D.new()) as Node3D
	start.position = Vector3(-14.6, 24.4, -11.4)
	start.rotation.y = deg_to_rad(90.0)
	var fin := child_of(tt, "FinishGate", func() -> Node: return Node3D.new()) as Node3D
	fin.position = Vector3(-17.6, 44.6, -6.0)
	var rings := child_of(tt, "Rings", func() -> Node: return Node3D.new()) as Node3D
	for c in rings.get_children():
		rings.remove_child(c)
		c.free()
	var i := 0
	for r in data.get("cloud_hopper_rings", []):
		i += 1
		var ring := (load(OBJ + "TrialRing.tscn") as PackedScene).instantiate() as Node3D
		ring.name = "R%d" % i
		ring.set("radius", float(r.get("radius", 1.5)))
		ring.position = v3(r["pos"])
		ring.rotation.y = deg_to_rad(float(r.get("facing_rot_y", r.get("rot_y", 0.0))))
		rings.add_child(ring)
		# Fix r1: a chunky glowing gold hoop (collectible gold #FFC93C) so the rings read at distance.
		var M := preload("res://scripts/worlds/w2_mesh.gd")
		var gm = M.new()
		gm.torus(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), float(r.get("radius", 1.5)) + 0.05, 0.17, Color("ffc93c"), 40, 10)
		var gmat := StandardMaterial3D.new()
		gmat.vertex_color_use_as_albedo = true
		gmat.metallic = 0.6
		gmat.roughness = 0.3
		gmat.emission_enabled = true
		gmat.emission = Color("ffb820")
		gmat.emission_energy_multiplier = 0.9
		var gmi := MeshInstance3D.new()
		gmi.name = "GoldHoop"
		gmi.mesh = gm.commit(gmat)
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(gmi)
	marker_at(tt, Vector3(-17.6, 44.6, -6.0))
	holder.add_child(tt)
	nodes["CloudHopper"] = tt


# ------------------------------------------------------------------ acorns

func _acorns() -> void:
	var ac := Node3D.new()
	ac.name = "Acorns"
	holder.add_child(ac)
	for g in data.get("acorn_groups", []):
		var shape := String(g["shape"])
		var pos := v3(g["pos"])
		var id := String(g["id"])
		if id == "A01":
			pos.z = 26.5  # fix (smoke test): the line overlapped the gate spawn, so Mak began with 3 acorns
		if id == "A34" and g.has("arc_from_az"):
			var n := int(g["count"])
			for k in n:
				var az := deg_to_rad(lerpf(float(g["arc_from_az"]), float(g["arc_to_az"]), float(k) / float(maxi(n - 1, 1))))
				inst("Acorn", {}, pos + Vector3(cos(az), 0, sin(az)) * float(g["radius"]) - Vector3(0, 0.45, 0), 0.0, ac, "%s_%d" % [id, k + 1])
			continue
		match shape:
			"LINE", "RING", "ARC":
				var props := {"count": int(g["count"])}
				props["shape"] = {"LINE": 0, "RING": 1, "ARC": 2}[shape]
				if g.has("length"):
					props["length"] = float(g["length"])
				if g.has("radius"):
					props["radius"] = float(g["radius"])
				if g.has("arc_degrees"):
					props["arc_degrees"] = float(g["arc_degrees"])
				var grp := inst("AcornGroup", props, pos + Vector3(0, 0.05, 0), float(g.get("rot_y", 0.0)), ac, id)
				if grp and pos.y < 2.0:
					# Garden groups: lift each acorn onto the rolling lawn.
					for c in grp.get_children():
						if c is Node3D:
							var gp := (c as Node3D).global_position
							var gy: float = b.island_h(gp.x, gp.z) + 0.05
							if gp.y < gy:
								(c as Node3D).global_position = Vector3(gp.x, gy, gp.z)
			"POINTS":
				var k := 0
				for q in g.get("points", []):
					k += 1
					inst("Acorn", {}, v3(q) - Vector3(0, 0.45, 0), 0.0, ac, "%s_%d" % [id, k])
			"CRATE":
				inst("BreakableCrate", {"acorns": int(g["count"]), "size": 1.1}, pos, 15.0, ac, id)
	_crumb_trail(ac)


## Fix r1: a three-crumb acorn trail from the loaf's lee toward the nostrils invites the sneeze-cannon gag.
func _crumb_trail(ac: Node3D) -> void:
	var k := 0
	for q: Vector3 in [Vector3(-6.3, 56.75, -32.3), Vector3(-7.2, 56.75, -32.8), Vector3(-7.9, 56.75, -33.4)]:  # fix r2: +0.7 (ObjSvc lift)
		k += 1
		inst("Acorn", {}, q, 0.0, ac, "SneezeCrumb_%d" % k)


func _hundred() -> void:
	var h := inst("AcornHundred", {"reward_truffle_id": "W2-100", "required": 100}, Vector3.ZERO, 0.0, holder, "AcornHundred")
	if h:
		marker_at(h, Vector3(-5.5, 24.0, -13.5))


# ------------------------------------------------------------------ vines, broom and puff clouds

func _climbables() -> void:
	for id: String in ["V0", "V1", "V2", "V3", "V5", "BROOM"]:
		var p: Dictionary = b.plat.get(id, {})
		if p.is_empty():
			continue
		var a := v3(p["pos"])
		var top := v3(p["top"])
		var h := a.distance_to(top)
		var c := inst("Climbable", {"height": h, "pole_radius": 0.25, "grab_radius": 0.7, "look": 0}, a, 0.0, holder, "Climb_" + id)
		if c == null:
			continue
		if id == "BROOM":
			var y := (top - a).normalized()
			var x := y.cross(Vector3.FORWARD).normalized()
			c.basis = Basis(x, y, x.cross(y))
			var vis := c.get_node_or_null("Visual") as Node3D
			if vis:
				vis.visible = false
		nodes["Climb_" + id] = c
		if id == "V5":
			# The magic sprout vine appears only after the bean mound is slammed.
			c.visible = false
			c.set_deferred("monitorable", false)
			c.process_mode = Node.PROCESS_MODE_DISABLED


func _puffs() -> void:
	for id in b.plat.keys():
		var p: Dictionary = b.plat[id]
		if String(p["kind"]) != "puff" and String(p["kind"]) != "puff_flat":
			continue
		var pos := v3(p["pos"])
		var r := float(p.get("r", 1.4))
		var vc := inst("VanishingCloud", {"size": Vector3(r * 2.0, 0.9, r * 2.0), "vanish_delay": float(p.get("vanish", {}).get("after_touch_s", 0.25)), "respawn_time": float(p.get("vanish", {}).get("respawn_s", 4.0)), "drift_amplitude": 0.12}, pos, 0.0, holder, String(id))
		if vc:
			if String(p["kind"]) == "puff":
				vc.add_to_group("bouncy")
				var apex := float(p.get("bounce_apex", 3.4))
				vc.set_meta("bounce_velocity", float(p.get("bounce_velocity_g28", sqrt(2.0 * GRAVITY * apex))))
			puffs.append(vc)


# ------------------------------------------------------------------ enemies

func _enemies() -> void:
	var en := Node3D.new()
	en.name = "Enemies"
	holder.add_child(en)
	for e in data.get("enemies", []):
		var id := String(e["id"])
		var typ := String(e["type"])
		if id == "E17":
			continue  # Captain Caw is built by _harpnapper (w2_caw.gd)
		if id == "E16":
			continue  # the goose-costume wolf appears when the cage opens (w2_life.gd)
		var pos := v3(e["pos"])
		var props := {}
		var patrol: Array[Vector3] = []
		var rot := 180.0 if typ == "PeapodPopper" and pos.z > 10.0 else 0.0
		match id:
			# Fix r1: the garden pods guard the path from beside the vegetable beds (facing west across it), well away
			# from the gate and the descent landing; E02 moved 1.5 m inward off the island rim.
			"E01":
				pos = Vector3(7.0, 0.0, 22.5)
				rot = 90.0
			"E02":
				pos = Vector3(10.0, 0.0, 26.5)
				rot = 110.0
			# Fix r1: the crow perches west of the stalk over L13, not 3.4 m from the CP1 sun leaf.
			# Fix r2: E04 hovers over the middle of the Cloud Landing, so every swoop and knock-back ends on the solid
			# C1 deck (it was 1.7 m from M01 with a knock-back over the void).
			"E04":
				pos = Vector3(-8.0, 25.8, -12.5)
		if pos.y < 2.0 and typ != "BumbleBruiser" and typ != "CrowBandit":
			pos.y = b.island_h(pos.x, pos.z) + 0.05  # snap garden walkers onto the rolling lawn
		match typ:
			"PeapodPopper":
				# Garden pods (E01, E02) only notice Mak within 5.5 m and give up at 8 m, so the gate is never under fire.
				props = {"reload_time": 2.6 if id != "E02" else 3.0, "notice_radius": 5.5 if id in ["E01", "E02"] else 10.0}
				if id in ["E01", "E02"]:
					props["lose_radius"] = 8.0
				elif e.get("group", "") != "":
					props["notice_radius"] = 7.5
					props["lose_radius"] = 10.0
					# Fix r2: three pods now share lane R1, so each fires less often (3 pods at 2.6 s was a pea storm).
					props["reload_time"] = 3.4
			"CrowBandit":
				props = {"notice_radius": 6.0 if id == "E04" else 8.0, "lose_radius": 10.0 if id == "E04" else 16.0}
			"BumbleBruiser":
				pos.y -= 1.4
				match id:
					"E10":
						for k in 8:
							var a := TAU * float(k) / 8.0
							patrol.append(Vector3(-1.2 + cos(a) * 8.0, 34.5 - 1.4, -6.0 + sin(a) * 8.0) - pos)
					"E11":
						for k in 8:
							var a := TAU * float(k) / 8.0
							patrol.append(Vector3(18 + cos(a) * 5.0, 26.5 - 1.4, 5 + sin(a) * 5.0) - pos)
					"E12":
						patrol.append(Vector3.ZERO)
						patrol.append(Vector3(14, 0, 14))
					"E13":
						# Round 3: guards the Upper Runner (never the checkpoint deck), aggro only on U02/U03.
						patrol.append(Vector3.ZERO)
						patrol.append(Vector3(2.5, 51.5 - 1.4, -13.2) - pos)
				props = {"notice_radius": 0.0 if id in ["E11", "E12", "E13"] else 7.0, "patrol_wait": 0.2}
		if patrol.size() > 0:
			props["patrol_points"] = patrol
		var node := inst(ENEMY + typ + ".tscn", props, pos, rot, en, id)
		if node == null:
			continue
		nodes[id] = node
		# Fix r1: forget defeated enemies so no typed lookup ever receives a freed instance.
		node.tree_exiting.connect(func() -> void:
			if nodes.get(id) == node:
				nodes.erase(id))
		if e.get("group", "") != "":
			node.add_to_group(String(e["group"]))
			poppers.append(node)
			if node.has_signal("defeated"):
				node.connect("defeated", _on_popper_defeated)


# ------------------------------------------------------------------ hazards

func _hazards() -> void:
	# H2 snore blast across the Giant's table, with lee boxes behind the table things (H3).
	snore = Area3D.new()
	snore.set_script(WindZoneScript)
	snore.name = "SnoreWind"
	snore.set("size", Vector3(10, 3.6, 8))
	snore.set("direction", Vector3(1, 0, 0))
	snore.set("mode", "snore")
	snore.position = Vector3(-4.0, 57.4, -34.0)
	var lee: Array[AABB] = []
	for box in [[Vector3(0.3, 57.0, -32.0), Vector3(2.0, 2.4, 3.0)], [Vector3(-2.0, 57.4, -35.6), Vector3(2.6, 3.0, 2.6)], [Vector3(-4.9, 57.4, -32.6), Vector3(2.0, 3.0, 4.4)], [Vector3(-7.3, 56.8, -30.9), Vector3(1.8, 2.0, 1.4)]]:
		lee.append(AABB(box[0] - box[1] * 0.5, box[1]))
	snore.set("lee", lee)
	holder.add_child(snore)
	snore.set("cycle", [["inhale", 2.0, -2.5], ["hold", 0.5, 0.0], ["blast", 1.6, 11.0], ["rest", 1.2, 0.0]])
	var lee_in: Array[AABB] = [AABB(Vector3(-8.2, 57.4, -32.6) - Vector3(0.5, 1.5, 2.2), Vector3(1.0, 3.0, 4.4)), AABB(Vector3(-10.1, 56.8, -30.9) - Vector3(0.3, 1.0, 0.6), Vector3(0.6, 2.0, 1.2))]
	snore.set("lee_inhale", lee_in)
	# H2b nose pull: extra westward pull during the inhale only (stacks with H2's -2.5 to -4.5 m/s).
	nose_pull = Area3D.new()
	nose_pull.set_script(WindZoneScript)
	nose_pull.name = "NosePull"
	nose_pull.set("size", Vector3(4, 3.6, 8))
	nose_pull.set("direction", Vector3(1, 0, 0))
	nose_pull.set("mode", "snore")
	nose_pull.set("cycle", [["inhale", 2.0, -2.0], ["hold", 0.5, 0.0], ["blast", 1.6, 0.0], ["rest", 1.2, 0.0]])
	nose_pull.set("lee_inhale", lee_in)
	nose_pull.set("show_streaks", false)
	nose_pull.position = Vector3(-8.5, 57.4, -34.0)
	holder.add_child(nose_pull)
	# H2c sniffle trigger at the nostrils (inhale only; handled by w2_life.gd).
	sniffle = Area3D.new()
	sniffle.name = "SniffleTrigger"
	sniffle.collision_layer = 128
	sniffle.collision_mask = 2
	sniffle.position = Vector3(-8.7, 56.6, -34.0)
	var scs := CollisionShape3D.new()
	var sbx := BoxShape3D.new()
	sbx.size = Vector3(1.0, 1.2, 1.8)
	scs.shape = sbx
	sniffle.add_child(scs)
	holder.add_child(sniffle)
	# H4 crosswind over the Leaf Bouncer.
	crosswind = Area3D.new()
	crosswind.set_script(WindZoneScript)
	crosswind.name = "Crosswind"
	crosswind.set("size", Vector3(22, 8, 26))
	# Fix r1: blow across the pad chain (perpendicular, toward the north-east) at half strength, so it nudges
	# the bounce instead of pushing Mak backwards off the route.
	crosswind.set("direction", Vector3(0.7, 0, -0.7))
	crosswind.set("mode", "gust")
	# Fix r2 (feel critic): the crosswind tops out at 1.6 m/s, so a Leaf Bouncer bounce drifts under 1 m.
	crosswind.set("base_wind", 0.9)
	crosswind.set("gust_wind", 0.7)
	crosswind.position = Vector3(-32.0, 46.0, -22.0)
	holder.add_child(crosswind)


# ------------------------------------------------------------------ Beanpod Lift

func _lift() -> void:
	lift = _make_pod("BeanpodLift", Vector3(9.5, 24.0, -2.5))
	if b.plat.has("LIFT2"):
		var l2: Dictionary = b.plat["LIFT2"]
		lift2 = _make_pod("BeanpodLift2", v3(l2["path"][1]))
		_lift_vine(Vector3(-10.5 - 1.5, 22.0, -12.6 - 1.1), 26)
	_lift_vine(Vector3(11.0, -1.0, -3.6), 30)


func _make_pod(n: String, at: Vector3) -> AnimatableBody3D:
	var lift := AnimatableBody3D.new()
	lift.name = n
	lift.sync_to_physics = true
	lift.collision_layer = 1
	lift.collision_mask = 0
	lift.position = at
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 0.5, 2.6)
	cs.shape = bs
	cs.position = Vector3(0, -0.25, 0)
	lift.add_child(cs)
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	var m = M.new()
	m.sphere(Transform3D(Basis().scaled(Vector3(1.55, 0.7, 1.45)), Vector3(0, -0.45, 0)), Color("8fcf4a"), 22, 12, Color("2e6b2b"))
	m.torus(Transform3D(Basis(), Vector3(0, 0.02, 0)), 1.45, 0.16, Color("6bbf4a"), 24, 8)
	m.disc(Transform3D(Basis(), Vector3(0, 0.0, 0)), 1.35, 1.25, Color("cfe89a"), 22)
	for k in 3:
		var x := (float(k) - 1.0) * 0.8
		m.sphere(Transform3D(Basis().scaled(Vector3(0.32, 0.26, 0.32)), Vector3(x, 0.12, 0.85)), Color("b6ea62"), 12, 6)
	# Vine loop on top that "holds" the pod to its vine.
	m.torus(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.4, 0)), 0.9, 0.09, Color("3e9a45"), 18, 6)
	for sx: float in [-1.0, 1.0]:
		m.tube(PackedVector3Array([Vector3(sx * 1.2, 0.0, 0), Vector3(sx * 0.9, 1.0, 0), Vector3(sx * 0.5, 1.4, 0)]), PackedFloat32Array([0.08, 0.08, 0.08]), Color("3e9a45"), 6)
	var mi := MeshInstance3D.new()
	mi.name = "PodVisual"
	mi.mesh = m.commit(b.vc_mat(0.45, 0.5))
	lift.add_child(mi)
	holder.add_child(lift)
	return lift


## The vine a pod rides on (visual column beside the lift path).
func _lift_vine(base: Vector3, n: int) -> void:
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	var v = M.new()
	var pts := PackedVector3Array()
	var rr := PackedFloat32Array()
	for k in n:
		var y := float(k) * 0.9
		pts.append(base + Vector3(sin(y * 0.6) * 0.25, y, cos(y * 0.5) * 0.25))
		rr.append(0.22)
	v.tube(pts, rr, Color("3e9a45"), 8, false, true, Color("6bbf4a"), 1)
	var vm := MeshInstance3D.new()
	vm.name = "LiftVine"
	vm.mesh = v.commit(b.vc_mat(0.35))
	holder.add_child(vm)


# ------------------------------------------------------------------ NPCs and signs

func _npcs() -> void:
	var pip := _glb_v("res://assets/characters/pip_v2/pip_v3.glb", "res://assets/characters/pip/pip.glb")
	if pip and ResourceLoader.exists(OBJ + "NPCTalker.tscn"):
		inst("NPCTalker", {"visual_scene": pip, "visual_scale": 1.0, "speaker": "Cousin Pip", "lines": PackedStringArray([
			"Mr. Mak! You came up the book too? Look at that beanstalk!",
			"The wolf's rewritten the tale so the Giant keeps all the gold. He's even locked up a golden goose!",
			"Hop up the leaves round the stalk. The teal ones are bouncy. Ooh, and mind the pea pods in the veg patch!",
			"Somebody's locked poor Jack in a birdcage by the cottage. Give it a good thump!",
		])}, Vector3(5.6, island_y(5.6, 20.6), 20.6), 120.0, holder, "Pip")
	_jack_and_daisy()
	if ResourceLoader.exists(OBJ + "SignPost.tscn"):
		inst("SignPost", {"board_text": "Stalk"}, Vector3(-3.3, island_y(-3.3, 26.8), 26.8), 30.0, holder, "SignGate")
		inst("SignPost", {"board_text": "Giant's Allotment"}, Vector3(-1.5, 24.0, -10.5), -80.0, holder, "SignAllotment")
		inst("SignPost", {"board_text": "Cloud Hopper"}, Vector3(-10.5, 24.0, -12.8), 90.0, holder, "SignHopper")
		inst("SignPost", {"board_text": "Garden drop"}, Vector3(12.0, 50.0, -17.6), 180.0, holder, "SignLeap")


func island_y(x: float, z: float) -> float:
	return b.island_h(x, z)


# ------------------------------------------------------------------ dev markers

func _dev_markers() -> void:
	var spawns := world.get_node_or_null("Spawns")
	if spawns == null:
		return
	var marks := {
		"dev_W2-1": [Vector3(-7.2, 24.05, -13.6), 43.0],
		"dev_W2-2": [Vector3(13.0, 50.05, -29.0), 0.0],
		"dev_W2-3": [Vector3(3.2, 54.45, -34.0), 90.0],
		"dev_W2-4": [Vector3(-12.5, 44.05, -9.0), 120.0],
		"dev_W2-5": [Vector3(9.0, b.island_h(9.0, 25.5) + 0.05, 25.5), 0.0],
		"dev_W2-6": [Vector3(15.0, 24.05, -3.0), -90.0],
		"dev_W2-7": [Vector3(-12.6, 24.05, -11.6), 90.0],
		"dev_W2-8": [Vector3(-18.0, 58.05, -17.6), 0.0],
		"dev_W2-100": [Vector3(-4.0, 24.05, -12.0), 90.0],
		"dev_castle": [Vector3(10.5, 50.05, -19.0), 0.0],
		"dev_kitchen": [Vector3(0.0, 50.05, -27.0), 90.0],
		"dev_allot": [Vector3(14.5, 24.05, -3.0), -90.0],
		"dev_sunleaf": [Vector3(5.44, 20.45, -6.22), 90.0],
		"dev_slot": [Vector3(-18.0, 58.05, -17.9), 0.0],
		"dev_bell": [Vector3(-8.4, 62.85, -16.6), 90.0],
		"dev_leafbouncer": [Vector3(-19.2, 44.05, -10.2), 125.0],
	}
	# Fix r1: W2-4 and W2-7 must not skip the W2-1 climb. Until W2-1 is owned they start at the garden gate.
	var game := world.get_node_or_null("/root/Game")
	var w21: bool = game != null and game.has_method("has_truffle") and bool(game.call("has_truffle", "W2-1"))
	if not w21:
		var dflt := spawns.get_node_or_null("Default") as Node3D
		for sid in ["W2-4", "W2-7"]:
			var sm := spawns.get_node_or_null(sid) as Node3D
			if sm and dflt:
				sm.transform = dflt.transform
	for k in marks.keys():
		var m := Marker3D.new()
		m.name = k
		m.position = marks[k][0]
		m.rotation.y = deg_to_rad(float(marks[k][1]))
		spawns.add_child(m)


# ------------------------------------------------------------------ round 2: The Harpnapper (W2-4)

var caw: Node3D
var harp: Node3D


func _harpnapper() -> void:
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	# Blossom tree on the islet (Caw's last perch): trunk collision, crown visual only.
	var bt: Dictionary = b.plat.get("BLOSSOM_TREE", {})
	var tp := v3(bt["pos"]) if not bt.is_empty() else Vector3(-41.6, 46.0, -39.0)
	var tm = M.new()
	tm.tube(M.catmull([tp, tp + Vector3(0.3, 1.6, 0.1), tp + Vector3(-0.1, 3.4, 0)], 0.3), PackedFloat32Array([0.4, 0.36, 0.32, 0.3, 0.28, 0.26, 0.24, 0.22, 0.2, 0.2, 0.2, 0.2, 0.2]), Color("7a4a2a"), 10, false, true)
	for k in 7:
		var a := TAU * float(k) / 7.0
		var cp := tp + Vector3(0, 4.2, 0) + (Vector3(cos(a) * 1.1, sin(a * 2.0) * 0.3, sin(a) * 1.1) if k > 0 else Vector3.ZERO)
		tm.sphere(Transform3D(Basis().scaled(Vector3.ONE * (1.3 if k == 0 else 0.9)), cp), Color("ffb3d1").lerp(Color("ffe0ec"), float(k % 3) * 0.3), 14, 8, Color("e88ab0"))
	var tmi := MeshInstance3D.new()
	tmi.name = "BlossomTree"
	tmi.mesh = tm.commit(b.vc_mat(0.45))
	holder.add_child(tmi)
	var tb := StaticBody3D.new()
	tb.collision_layer = 1
	var tcs := CollisionShape3D.new()
	var tcy := CylinderShape3D.new()
	tcy.radius = 0.4
	tcy.height = 3.0
	tcs.shape = tcy
	tcs.position = tp + Vector3(0, 1.5, 0)
	tb.add_child(tcs)
	holder.add_child(tb)
	# Reward spawner and the harp (visible on the islet once freed).
	var hs := TruffleSpawner.new()
	hs.name = "HarpReward"
	hs.set("reward_truffle_id", "W2-4")
	var hm := Marker3D.new()
	hm.name = "TruffleMarker"
	hm.position = Vector3(-40.5, 46.0, -38.0)
	hs.add_child(hm)
	holder.add_child(hs)
	nodes["HarpReward"] = hs
	var hp := "res://assets/props/w2/golden_harp/golden_harp.glb"
	if ResourceLoader.exists(hp) and load(hp) is PackedScene:
		harp = (load(hp) as PackedScene).instantiate() as Node3D
		harp.name = "GoldenHarp"
		harp.position = Vector3(-39.6, 46.0, -37.0)
		harp.rotation.y = 2.4
		harp.scale = Vector3.ONE * 1.2
		harp.visible = false
		holder.add_child(harp)
	var game := world.get_node_or_null("/root/Game")
	var owned: bool = game != null and bool(game.call("has_truffle", "W2-4"))
	if owned:
		if harp:
			harp.visible = true
		return
	caw = Node3D.new()
	caw.set_script(preload("res://scripts/worlds/w2_caw.gd"))
	caw.name = "E17_CaptainCaw"
	caw.set("wind", crosswind)
	caw.set("track", {"PERCH1": b.bodies.get("LB2"), "PERCH2": b.bodies.get("LB4")})
	holder.add_child(caw)
	nodes["E17"] = caw
	caw.connect("defeated", func() -> void:
		if harp:
			harp.visible = true
		hs.call("give_reward"))


# ------------------------------------------------------------------ round 2: Bluebell bud (P4)

var bud: StaticBody3D
var bud_open := false
var _bud_held: Array[Node3D] = []


func _hive_bud() -> void:
	var hp: Dictionary = b.plat.get("HIVE", {})
	if String(hp.get("kind", "")) != "bud_then_cup":
		return
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	var c := v3(hp["pos"])
	bud = StaticBody3D.new()
	bud.name = "BluebellBud"
	bud.collision_layer = 1
	var pts := PackedVector3Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(c + Vector3(cos(a) * 1.8, -0.05, sin(a) * 1.8))
		pts.append(c + Vector3(cos(a) * 1.0, 1.4, sin(a) * 1.0))
	pts.append(c + Vector3(0, 2.2, 0))
	var cp := ConvexPolygonShape3D.new()
	cp.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = cp
	bud.add_child(cs)
	var m = M.new()
	for k in 5:
		var a := TAU * float(k) / 5.0
		var b2 := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -0.25)
		m.sphere(Transform3D(b2.scaled(Vector3(0.9, 1.25, 0.55)), c + Vector3(cos(a) * 0.75, 0.95, sin(a) * 0.75)), Color("6f8ff0"), 14, 8, Color("4a62c8"))
	m.sphere(Transform3D(Basis().scaled(Vector3(0.35, 0.5, 0.35)), c + Vector3(0, 2.0, 0)), Color("8aa4ff"), 10, 6)
	var mi := MeshInstance3D.new()
	mi.name = "BudMesh"
	mi.mesh = m.commit(b.vc_mat(0.55))
	bud.add_child(mi)
	holder.add_child(bud)
	# Fix r2 (QA critic): the page and the A19 ring wait outside the tree until the bud opens, so ObjSvc's unbury can
	# never lift them out of the closed bud onto its top (W2-5 page 4 was collectible without the bee puzzle).
	for nm in ["Page4", "Acorns/A19"]:
		var n := holder.get_node_or_null(nm) as Node3D
		if n:
			var gp := n.global_position
			n.get_parent().remove_child(n)
			n.position = gp
			_bud_held.append(n)
	holder.tree_exiting.connect(func() -> void:
		for n in _bud_held:
			if is_instance_valid(n) and not n.is_inside_tree():
				n.free()
		_bud_held.clear())
	# Fix r1: only the bee's charge opens the bud (the bee-bait puzzle). A hit just teases the hint; the punch
	# fallback stays only for when the bee is gone, so the page can never be locked away.
	var tgt := Area3D.new()
	tgt.set_script(preload("res://scripts/worlds/w2_target.gd"))
	tgt.set("radius", 1.9)
	tgt.set("height", 2.4)
	tgt.position = c
	tgt.name = "BudTarget"
	bud.add_child(tgt)
	tgt.connect("hit", func(kind: String) -> void:
		if not kind in ["punch", "kick", "jump_kick", "dive", "slam"]:
			return
		var bee: Variant = nodes.get("E10")
		if bee == null or not is_instance_valid(bee) or bool((bee as Node).get("is_defeated")):
			open_bud("punch")
			return
		var ui := world.get_node_or_null("/root/UI")
		if ui and ui.has_method("toast"):
			ui.toast("Boing. The bud is shut tight. (That bee looks cross. Stand between it and the bud...)"))


func open_bud(why: String) -> void:
	if bud_open or bud == null:
		return
	bud_open = true
	var ui := world.get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.toast("BOING! The bluebell bursts open!" if why == "bee" else "Pop! The bluebell opens.")
	var path := "res://scenes/fx/Confetti.tscn"
	if ResourceLoader.exists(path):
		var fx := (load(path) as PackedScene).instantiate() as Node3D
		holder.add_child(fx)
		fx.global_position = bud.get_node("BudTarget").global_position + Vector3(0, 1, 0)
	var tw := bud.create_tween()
	tw.tween_property(bud.get_node("BudMesh"), "scale", Vector3(1.6, 0.1, 1.6), 0.35).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(bud.queue_free)
	tw.tween_callback(func() -> void:
		for n in _bud_held:
			if is_instance_valid(n):
				holder.add_child(n)
		_bud_held.clear())


# ------------------------------------------------------------------ round 2: Sir Reginald's cameo

var reginald: Node3D


func _reginald() -> void:
	var path := "res://assets/characters/wolf_boss/wolf_boss.glb"
	if not ResourceLoader.exists(path):
		return
	var game := world.get_node_or_null("/root/Game")
	if game and game.has_method("is_unlocked") and bool(game.call("is_unlocked", "w2_reginald_seen")):
		return
	reginald = Node3D.new()
	reginald.name = "ReginaldCameo"
	# Fix r1: on the partition-wall top, where both the courtyard and the kitchen cameras face him.
	reginald.position = Vector3(7.0, 58.5, -31.0)
	reginald.rotation.y = -PI * 0.5  # faces west, toward the sleeping Giant
	var ps := load(path) as PackedScene
	if ps == null:
		reginald.free()
		reginald = null
		return
	var g := ps.instantiate() as Node3D
	g.rotation.y = PI
	g.scale = Vector3.ONE * 0.62
	reginald.add_child(g)
	var book := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.9, 0.12)
	book.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("b3263a")
	book.material_override = mat
	book.position = Vector3(0, 1.35, -0.55)
	book.rotation.x = -0.5
	reginald.add_child(book)
	holder.add_child(reginald)


# ------------------------------------------------------------------ round 1: Jack (caged) and Daisy the cow

var jack_cage: Node3D
var jack_hits := 0
var jack_free: Node3D
const JACK_HINTS := {
	"W2-1": "Up the leaves, round and round. The droopy ones sag, so don't dawdle!",
	"W2-2": "Three red switches free the goose. That goose honks like a wolf, though. And if it runs like one... you'll want a running start.",
	"W2-3": "The Giant breathes in, then snores out. Hide behind the loaf, bounce off his beard... and whatever you do, don't tickle his nose!",
	"W2-4": "A crow in a hat nicked the Giant's harp. Kick him at the top of a bounce!",
	"W2-5": "Five pages blew all over the beanstalk. One's shut in a bluebell bud, and the bees hate that bud. Very cross bees. Very stupid bees.",
	"W2-6": "Those pea pods stand in neat little rows, like skittles. Shame if somebody knocked a whole row over!",
	"W2-7": "Six gold rings from the Cloud Landing up to the high cloudbank before the clock runs out. Bounce, jump-jump-JUMP through the high one, long jump, then dive!",
	"W2-8": "Ride the Giant's bell and give it a good Ham Slam. BONG!",
}


func _jack_and_daisy() -> void:
	var jack_scene := _glb_v("res://assets/characters/jack/jack_v2.glb", "res://assets/characters/jack/jack.glb")
	if jack_scene:
		var M := preload("res://scripts/worlds/w2_mesh.gd")
		jack_cage = Node3D.new()
		jack_cage.name = "JackCage"
		jack_cage.position = Vector3(-7.4, 0.5, 21.0)
		holder.add_child(jack_cage)
		var cm = M.new()
		for i in 10:
			var a := TAU * float(i) / 10.0
			cm.cylinder(Transform3D(Basis(), Vector3(cos(a) * 0.7, 0.8, sin(a) * 0.7)), 0.035, 0.035, 1.6, Color("3b3640"), 6)
		cm.torus(Transform3D(Basis(), Vector3(0, 0.02, 0)), 0.72, 0.06, Color("c9a04a"), 18, 5)
		cm.torus(Transform3D(Basis(), Vector3(0, 1.6, 0)), 0.72, 0.06, Color("c9a04a"), 18, 5)
		cm.sphere(Transform3D(Basis().scaled(Vector3(0.72, 0.35, 0.72)), Vector3(0, 1.6, 0)), Color("c9a04a"), 14, 6)
		cm.cylinder(Transform3D(Basis(), Vector3(0, 2.6, 0)), 0.03, 0.03, 1.6, Color("6b5a4a"), 5)
		cm.puck(Transform3D(Basis(), Vector3(0, 0.0, 0)), 0.75, 0.08, 0.03, Color("8a5a35"), 18)
		var cmi := MeshInstance3D.new()
		cmi.name = "Bars"
		cmi.mesh = cm.commit(b.vc_mat(0.4, 0.7))
		jack_cage.add_child(cmi)
		var jk := jack_scene.instantiate() as Node3D
		jk.name = "JackCaged"
		jk.scale = Vector3.ONE * 0.95
		jk.position = Vector3(0, 0.05, 0)
		jk.rotation.y = 0.6
		jack_cage.add_child(jk)
		var cb := StaticBody3D.new()
		cb.collision_layer = 1
		var ccs := CollisionShape3D.new()
		var ccy := CylinderShape3D.new()
		ccy.radius = 0.72
		ccy.height = 1.7
		ccs.shape = ccy
		ccs.position = Vector3(0, 0.85, 0)
		cb.add_child(ccs)
		jack_cage.add_child(cb)
		var tgt := Area3D.new()
		tgt.set_script(preload("res://scripts/worlds/w2_target.gd"))
		tgt.set("radius", 0.9)
		tgt.set("height", 1.8)
		tgt.name = "LockTarget"
		jack_cage.add_child(tgt)
		tgt.connect("hit", _on_jack_cage_hit)
		# Jack after release, at the garden gate: hint giver for the selected mission.
		var game := world.get_node_or_null("/root/Game")
		var mission: String = String(game.get("current_mission")) if game else ""
		var hint: String = JACK_HINTS.get(mission, "Ask me anything! Well, about beanstalks.")
		jack_free = inst("NPCTalker", {"visual_scene": jack_scene, "visual_scale": 1.0, "speaker": "Jack", "lines": PackedStringArray([
			"Thank you, sir! The wolf traded my beans for a single acorn! Rotten deal!",
			hint,
		])}, Vector3(2.4, island_y(2.4, 31.2), 31.2), -150.0, holder, "Jack")
		if jack_free:
			jack_free.visible = false
			jack_free.process_mode = Node.PROCESS_MODE_DISABLED
	var cow := _glb_v("res://assets/characters/daisy_cow/daisy_cow_v2.glb", "res://assets/characters/daisy_cow/daisy_cow.glb")
	if cow:
		var daisy := inst("NPCTalker", {"visual_scene": cow, "visual_scale": 1.0, "speaker": "Daisy", "talk_radius": 2.8, "lines": PackedStringArray([
			"I was NOT sold for beans, thank you very much.",
			"Moo. The Giant snores like a tuba.",
		])}, Vector3(-6.0, island_y(-6.0, 27.0), 27.0), 60.0, holder, "Daisy")
		nodes["Daisy"] = daisy


func _on_jack_cage_hit(_kind: String) -> void:
	if jack_cage == null:
		return
	jack_hits += 1
	var ui := world.get_node_or_null("/root/UI")
	if jack_hits == 1:
		if ui and ui.has_method("toast"):
			ui.toast("Jack: \"Oi! Again, harder!\"")
		var tw := jack_cage.create_tween()
		tw.tween_property(jack_cage, "rotation:z", 0.25, 0.08)
		tw.tween_property(jack_cage, "rotation:z", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC)
		return
	if ui and ui.has_method("toast"):
		ui.toast("Jack: \"Free! Thank you, sir! Find me by the gate!\"")
	var path := "res://scenes/fx/Confetti.tscn"
	if ResourceLoader.exists(path):
		var fx := (load(path) as PackedScene).instantiate() as Node3D
		holder.add_child(fx)
		fx.global_position = jack_cage.global_position + Vector3(0, 1, 0)
	jack_cage.queue_free()
	jack_cage = null
	if jack_free:
		jack_free.visible = true
		jack_free.process_mode = Node.PROCESS_MODE_INHERIT
