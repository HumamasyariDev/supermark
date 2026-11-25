extends Node3D
## W1 Huff & Puff Hollow content builder. Places every landmark, platform, mission, enemy, collectible,
## hazard and decoration at runtime from res://assets/environment/w1/w1_level.json (a copy of
## data/levels/W1.json plus sampled splines), so the level plan stays the single source of numbers.
## Generated GLBs (res://assets/props/w1/...) are the visuals; walkable house shells use trimesh collision
## baked from the same mesh, so Mak stands exactly on what the camera shows. Gameplay-critical shapes
## (chimney shaft, scaffold, sail steps, decks) use builder boxes at the plan sizes.

const K := preload("res://scripts/worlds/w1_kit.gd")
const L := preload("res://scripts/worlds/w1_landmarks.gd")
const D := preload("res://scripts/worlds/w1_dress.gd")
const OBJ := "res://scenes/objects/%s.tscn"
const GUST := preload("res://scripts/worlds/w1_gust_zone.gd")
const LIFE := preload("res://scripts/worlds/w1_life.gd")
## Fix round 2: thin solids that must block Mak but not the camera spring arm (layer 1 only) go on layer 3 (bit 4):
## the player masks layers 1 and 3, the camera and enemies mask layer 1 only.
const SOLID_NO_CAM := 4

const SIEGE_IDS := ["WW1", "WW2", "WW3", "WW4"]

var lv: Dictionary = {}
var plat: Dictionary = {}
## World-space triangle soups of the walkable GLB shells (for surface height queries while building).
var shells: Dictionary = {}
var siege_left: int = 4
var siege_spawner: Node3D
var pip: Node3D
var sail_rotor: Node3D
var sail_visual: Node3D
var acorn_hundred: Node3D
## Fix round 2: the living layer (sheep, puff plates, WW3's haystack, the Hay Hoist, riddle signs, the sail-ride dive).
var life: Node3D
var _t := 0.0
var _lod_t := 0.0
var _lod_nodes: Array[Node3D] = []
var _lod_radius: Array[float] = []


func _ready() -> void:
	var web_trace_t := WebRuntime.trace_start()
	lv = W1Terrain.level()
	if lv.is_empty():
		push_error("[W1] level data missing")
		return
	for p in lv.get("platforms", []):
		plat[String(p["id"])] = p
	_amend()
	life = LIFE.new()
	life.name = "W1Life"
	add_child(life)
	life.setup(self)
	var t0 := Time.get_ticks_msec()
	_landmarks()
	_door_sign()
	_camera_hints()
	_platforms()
	_rope_bridge()
	_scaffold()
	_windmill_ride()
	_bellows()
	_missions()
	_enemies()
	_collectibles()
	_hazards()
	D.dress(self, lv)
	for sk in D.SKEPS:
		life.call("add_bees", Vector3(sk.x, gy(sk.x, sk.y), sk.y), 4)
	_tale_states()
	_cutcams()
	_perf_setup()
	_spawn_fixes()
	_sign_camera_colliders.call_deferred()
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_arg("w1-punchline"):
		get_tree().create_timer(1.0).timeout.connect(_punchline)
	if dev and dev.has_arg("w1-blowdown"):
		get_tree().create_timer(1.0).timeout.connect(_blow_down)
	if dev and dev.has_arg("w1-sticks"):
		get_tree().create_timer(1.0).timeout.connect(func() -> void: _stick_collapse(true))
	if dev and dev.has_arg("w1-probe"):
		_probe()
	print("[W1] level built in %d ms (%d nodes)" % [Time.get_ticks_msec() - t0, get_child_count()])
	WebRuntime.trace_end("builder_ready:worlds/w1_level", web_trace_t)


## Builder spawn fixes (gameplay-camera captures): W1-2 started under the Mill Stage posts, W1-6 tucked the camera
## into the chimney corner. Runs before WorldRoot resolves the spawn.
func _spawn_fixes() -> void:
	# Fix round 1 (QA r1): W1-3 spawned 5.6 m from WW5 (notice 8) and W1-6 4.5 m from CB5, so Mak took damage under
	# the mission banner. Both now start well outside those radii, facing the mission.
	var fixes := {"W1-2": [Vector3(48.0, 0, -35.2), -48.6], "W1-6": [Vector3(10.5, 0, -29.5), -25.0], "W1-3": [Vector3(-36.0, 0, -7.0), 6.0],
		"W1-8": [Vector3(41.0, 0, 17.0), -58.0]}
	for id in fixes:
		var m := get_parent().get_node_or_null("Spawns/" + String(id)) as Node3D
		if m:
			var p: Vector3 = fixes[id][0]
			p.y = gy(p.x, p.z) + 0.05
			m.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(fixes[id][1]))), p)


var _b3: Node3D
var _b3_zone: Node3D
var _b3_base := Basis()
var _b3_zone_rel := Transform3D()
var _b3_t := 0.0


## R1.7: B3 swivels +/- 35 degrees about its base (period 6 s); its gust sweeps the plateau apron.
func _physics_process(delta: float) -> void:
	if _b3 == null or not is_instance_valid(_b3) or bool(_b3.get("is_broken")):
		return
	_b3_t += delta
	# Fix round 1: +/- 18 degrees (was 35): now that the gusts blow at full strength (STEADY zones) the sweep no longer
	# covers the chimney's soot door and the Saddle Lane start (fun critic r1: B3 tripled the lane time).
	var r := Basis(Vector3.UP, deg_to_rad(18.0) * sin(TAU * _b3_t / 6.0))
	_b3.basis = r * _b3_base
	if _b3_zone and is_instance_valid(_b3_zone):
		_b3_zone.global_transform = Transform3D(r, _b3.global_position) * _b3_zone_rel


## Fix round 1: the two blow-downs persist with their truffles owned; the stick house falls after the W1-3 celebration.
func _tale_states() -> void:
	if i_owned("W1-1"):
		_straw_after(false)
	if i_owned("W1-3"):
		_stick_collapse(false)
		return
	var wr := get_parent()
	if wr and wr.has_signal("truffle_celebration_finished"):
		wr.connect("truffle_celebration_finished", func(id: String) -> void:
			if id == "W1-3":
				get_tree().create_timer(0.4).timeout.connect(func() -> void: _stick_collapse(true)))


## Fix round 1 (QA r1): enemies sleep for 3 s after the level starts (and until Mak first moves 1 m), so a mission
## start or a respawn under the banner never takes a hit.
var _grace := 3.0
var _grace_from := Vector3.INF


func _grace_step(delta: float) -> void:
	if _grace <= 0.0:
		return
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	if _grace_from == Vector3.INF:
		_grace_from = pl.global_position
	_grace -= delta
	if pl.global_position.distance_to(_grace_from) > 1.0 and _grace < 2.0:
		_grace = 0.0
	if _grace <= 0.0:
		_lod_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	_grace_step(delta)
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.25
		_lod()
	if sail_rotor and sail_visual and sail_rotor.has_method("get_rotor_angle"):
		sail_visual.rotation.z = float(sail_rotor.call("get_rotor_angle")) + PI * 0.25
	_cut_update(delta)


# ------------------------------------------------------------------ performance

## 60 fps at 1080p on the target GPU: the level is CPU-bound by node count, not by pixels (measured with --w1-fps and
## --w1-skip). Static subtrees skip physics interpolation (only physics-driven movers need it), the stream current
## zones never need a tick (steady wind, no particles), and enemies and acorns sleep beyond a radius from Mak.
func _perf_setup() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_ancestor_of(n):
			(n as Node).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
			_lod_nodes.append(n)
			_lod_radius.append(42.0)
	for n in find_children("*", "AnimatableBody3D", true, false):
		n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	for cls in ["RotatingPlatform", "FallingPlatform"]:
		for n in find_children("*", "Node3D", true, false):
			if n.get_script() != null and (n.get_script() as Script).get_global_name() == cls:
				n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var cur := get_node_or_null("StreamCurrent")
	if cur:
		for z in cur.get_children():
			z.process_mode = Node.PROCESS_MODE_DISABLED
	call_deferred("_collect_acorns_for_lod")


func _collect_acorns_for_lod() -> void:
	for n in get_tree().get_nodes_in_group("acorn"):
		if is_ancestor_of(n) and n is Node3D:
			_lod_nodes.append(n)
			_lod_radius.append(32.0)


func _lod() -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var pp := pl.global_position
	for i in range(_lod_nodes.size() - 1, -1, -1):
		var n := _lod_nodes[i]
		if not is_instance_valid(n):
			_lod_nodes.remove_at(i)
			_lod_radius.remove_at(i)
			continue
		var near := n.global_position.distance_squared_to(pp) < _lod_radius[i] * _lod_radius[i]
		if _grace > 0.0 and n.is_in_group("enemy"):
			near = false
		var want := Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
		if n.process_mode != want:
			n.process_mode = want


# ------------------------------------------------------------------ helpers

static func v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func gy(x: float, z: float) -> float:
	return W1Terrain.height(x, z)


func obj(scene: String, pos: Vector3, props: Dictionary = {}, yaw_deg: float = 0.0, parent: Node = null) -> Node3D:
	var ps := load(OBJ % scene) as PackedScene
	if ps == null:
		push_warning("[W1] missing object scene " + scene)
		return null
	var n := ps.instantiate() as Node3D
	for k in props:
		n.set(k, props[k])
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	(parent if parent != null else self).add_child(n)
	return n


func glb(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null


## Instances a GLB under a new node at `pos` (base centre), uniform `scl`, yaw in degrees. No 180 flip:
## W1 buildings face south (+Z) toward the spawn, which is the glTF front.
func place_glb(path: String, node_name: String, pos: Vector3, yaw_deg: float = 0.0, scl: float = 1.0, parent: Node3D = null) -> Node3D:
	var ps := glb(path)
	if ps == null:
		return null
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	(parent if parent != null else self).add_child(holder)
	var inst := ps.instantiate() as Node3D
	inst.scale = Vector3.ONE * scl
	holder.add_child(inst)
	return holder


## Static trimesh collision baked from every mesh under `visual` (world-space faces). Returns the faces.
func trimesh_from(visual: Node3D, body_name: String) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var xf := (mi as MeshInstance3D).global_transform
		for p in m.get_faces():
			faces.append(xf * p)
	if faces.is_empty():
		return faces
	var b := StaticBody3D.new()
	b.name = body_name
	b.collision_layer = 1
	b.collision_mask = 0
	add_child(b)
	var s := ConcavePolygonShape3D.new()
	s.backface_collision = false
	s.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = s
	b.add_child(cs)
	return faces


## Highest surface of a triangle soup above (x, z) (or -INF).
static func surface_y(faces: PackedVector3Array, x: float, z: float) -> float:
	var best := -INF
	var from := Vector3(x, 500.0, z)
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if minf(a.x, minf(b.x, c.x)) > x or maxf(a.x, maxf(b.x, c.x)) < x:
			continue
		if minf(a.z, minf(b.z, c.z)) > z or maxf(a.z, maxf(b.z, c.z)) < z:
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, a, b, c)
		if hit != null:
			best = maxf(best, (hit as Vector3).y)
	return best


func shell_y(shell: String, x: float, z: float, fallback: float) -> float:
	if not shells.has(shell):
		return fallback
	var y := surface_y(shells[shell], x, z)
	return y if y > -1e8 else fallback


# ------------------------------------------------------------------ builder amendments

## Builder changes to the plan's platform table, on top of Docs/levels/W1_amendments.md round 1 (recorded in
## Docs/DEVLOG.md). Measured on the shipping controller with the W1 bot (w1_bot.gd): a standing jump peaks at 1.71 m,
## the second jump only chains on landing, and ledges grab 0.75-1.55 m above the feet, so standing rises of 1.6-2.4 m
## (the plan's scaffold "doubles") cannot be climbed on small platforms. Climbs use rises of 1.1-1.3 m. The generated
## house roofs are steeper than the 40-degree slide angle, so roof access uses bale tiers, window boxes and a roof walk.
func _amend() -> void:
	# Stick Scaffold (R1.6 spirit): a 9-step spiral (radius 4 m around a lashed birch pole), single-jump rises;
	# steps 6 and 7 are crumbling sticks (they drop 1.2 s after landing and re-tie), step 5 rocks.
	for i in range(1, 10):
		plat.erase("scaffold_sc%d" % i)
	var c := Vector2(-38.0, -25.5)
	for k in 9:
		var a := deg_to_rad(75.0 - 31.9 * k)
		var top := Vector3(c.x + 4.0 * cos(a), 5.2 + 1.2 * k, c.y + 4.0 * sin(a))
		var id := "scaffold_sc%d" % (k + 1)
		var t := "static_sticks"
		if k == 4:
			t = "rocking_sticks"
		elif k == 5 or k == 6:
			t = "crumbling_sticks"
		plat[id] = {"id": id, "type": t, "top": [top.x, top.y, top.z], "size": [1.9, 0.3, 1.9] if k != 4 else [2.6, 0.3, 1.7], "yaw_deg": 0}
	# Fix round 1 (fun + feel critics r1: nine identical 1.2 m table hops; the pole climb and pole jump unused in W1):
	# R3.2 scaffold_pole replaces sc4-sc6. A lashed birch pole, greased (not climbable) below y 9, climbable 9-11;
	# J14 a standing jump from sc3 grabs it, climb, orbit to the side facing sc7 (the red pennant points there) and
	# pole-jump: from feet 9-10 the arc lands 4.0-4.8 m out, sc7 spans 2.65-4.55 m. A32 ring around the top.
	var p3 := v3(plat["scaffold_sc3"]["top"])
	var p7 := v3(plat["scaffold_sc7"]["top"])
	for k in [4, 5, 6]:
		plat.erase("scaffold_sc%d" % k)
	var mid := (p3 + p7) * 0.5
	plat["scaffold_pole"] = {"id": "scaffold_pole", "type": "scaffold_pole", "top": [mid.x, 11.0, mid.z], "size": [0.44, 2.0, 0.44], "yaw_deg": 0,
		"aim": [p7.x, p7.y, p7.z]}
	# Page Gate secret: five book steps with 1.2 m rises, then the arch top (7.5).
	var books := [Vector3(5.4, 1.6, 59.2), Vector3(6.2, 2.8, 57.4), Vector3(5.0, 4.0, 56.0), Vector3(3.4, 5.2, 56.6), Vector3(3.6, 6.4, 58.6)]
	for i in 5:
		plat.erase("book_step_%d" % (i + 1))
	for i in books.size():
		var b: Vector3 = books[i]
		plat["book_step_%d" % (i + 1)] = {"id": "book_step_%d" % (i + 1), "type": "static_book", "top": [b.x, b.y, b.z], "size": [1.8, 0.5, 1.4], "yaw_deg": 0}
	# Straw house: hay cart by the east wall and two bale tiers up to the gentle top of the thatch (CB1's perch).
	plat["straw_haybale_step"]["top"] = [-13.2, 1.5, 30.4]
	plat["straw_haycart"]["top"] = [-14.6, 2.6, 28.4]
	plat["straw_bale_tier_1"] = {"id": "straw_bale_tier_1", "type": "static_haybale", "top": [-14.8, 3.7, 27.2], "size": [1.6, 1.1, 1.2], "yaw_deg": 0}
	plat["straw_bale_tier_2"] = {"id": "straw_bale_tier_2", "type": "static_haybale", "top": [-15.1, 4.8, 26.0], "size": [1.6, 1.1, 1.2], "yaw_deg": 0}
	# Brick house front: rain butt, woodshed, a plank shelf, the balcony and a window box up to a sweep's plank on the
	# dormer and a railed roof walk along the ridge (A09 acorns, the view of the chimney truffle).
	plat["brick_water_butt"]["top"] = [1.2, 13.2, -29.4]
	plat["brick_woodshed_roof"]["top"] = [2.4, 14.4, -31.2]
	plat["brick_woodshed_roof"]["size"] = [3.6, 0.3, 2.6]
	plat["brick_plank_shelf"] = {"id": "brick_plank_shelf", "type": "static_wood", "top": [5.6, 15.7, -30.6], "size": [1.8, 0.25, 1.2], "yaw_deg": 0}
	plat["brick_balcony"]["top"] = [8.0, 17.0, -31.4]
	plat["brick_balcony"]["size"] = [2.4, 0.25, 1.3]
	plat["brick_window_box"] = {"id": "brick_window_box", "type": "static_wood", "top": [5.4, 18.35, -32.45], "size": [1.6, 0.3, 0.9], "yaw_deg": 0}
	plat.erase("brick_roof_south")
	plat["brick_dormer_plank"] = {"id": "brick_dormer_plank", "type": "roof_plank", "top": [5.5, 19.65, -33.9], "size": [1.4, 0.25, 1.3], "yaw_deg": 0}
	plat["brick_roof_walk"] = {"id": "brick_roof_walk", "type": "roof_plank", "top": [3.4, 20.85, -36.0], "size": [6.2, 0.25, 1.6], "yaw_deg": 0}
	for g in lv.get("acorn_groups", []):
		var gid := String(g["id"])
		if gid == "A09":
			g["start"] = [0.9, 21.55, -36.0]
			g["end"] = [6.0, 21.55, -36.0]
		elif gid == "A15":
			g["end"] = [11.3, 26.5, -36.0]
		elif gid == "A22":
			g["kind"] = "ring"
			g["center"] = [-6.0, 0.35, 10.4]
			g["radius"] = 0.5
		# Fix round 2 (QA r1: ObjSvc.unbury moved these at every load): source positions lifted clear of the geometry.
		elif gid == "A05":
			g["center"] = [2.0, 1.6, -3.0]
		elif gid == "A08":
			var pts: Array = g["points"]
			pts[1] = [-35.0, 7.6, -24.6]
		elif gid == "A11":
			g["center"] = [34.0, 8.6, 3.0]
		elif gid == "A27":
			g["start"] = [2.0, 3.8, -3.0]
	for pg in lv.get("pages", []):
		if String(pg["id"]) == "P1":
			pg["pos"] = [-17.0, 0.98, 1.5]
	# The plan's shelf spot is closed by the generated bridge's abutments: the A22 shelf sits under the arch instead.
	plat["page_shelf"]["top"] = [-6.0, -0.3, 10.4]
	plat["page_shelf"]["size"] = [1.2, 0.5, 1.2]
	# Treehouse hut roof at 19.3 (R1.5 P3 backflip target): built by w1_dress; the plan row is decorative here.
	plat.erase("treehouse_hut_roof")


# ------------------------------------------------------------------ landmarks

func _landmarks() -> void:
	# Straw house (cousin Pip's). Fix round 1 (visual critic r1: the generated GLB is the banned scalloped mushroom
	# dome and R2.10's two-mesh cottage was never generated): an interim procedural front-gable cottage, walls and roof
	# as separate nodes so the R1.4 blow-down folds the real roof off.
	_straw_cottage(Vector3(-20, 0.35, 26))
	# Stick house in the birch grove.
	var stick := place_glb("res://assets/props/w1/stick_house/stick_house.glb", "StickHouse", Vector3(-42, 4.0, -18))
	if stick:
		shells["stick"] = trimesh_from(stick, "StickHouseShell")
	else:
		var n2 := Node3D.new()
		n2.position = Vector3(-42, 4, -18)
		add_child(n2)
		L.stick_house(n2)
	# Brick house on the hilltop (GLB 9.7 x 10.4 x 7, its own small chimney on the west gable).
	var brick := place_glb("res://assets/props/w1/brick_house/brick_house.glb", "BrickHouse", Vector3(5, 12.0, -36))
	if brick:
		shells["brick"] = trimesh_from(brick, "BrickHouseShell")
	# Hollow chimney stack against the east gable (builder boxes: flat kick walls), procedural brick.
	var ch := Node3D.new()
	ch.name = "ChimneyStack"
	ch.position = Vector3(5, 12, -36)
	add_child(ch)
	_chimney(ch)
	# Windmill: GLB tower with trimesh (its gallery ring is walkable), plus the weathervane deck.
	var mill := place_glb("res://assets/props/w1/windmill_body/windmill_body.glb", "Windmill", Vector3(40, 12.0, -46))
	if mill:
		shells["mill"] = trimesh_from(mill, "WindmillShell")
	else:
		var n3 := Node3D.new()
		n3.position = Vector3(40, 12, -46)
		add_child(n3)
		L.windmill(n3)
	# Village well.
	var well := place_glb("res://assets/props/w1/wishing_well/wishing_well.glb", "VillageWell", Vector3(2, 0.4, -3), 0.0, 1.05)
	if well:
		trimesh_from(well, "VillageWellShell")
	# Stone footbridge on Page Lane over the stream (GLB length runs along Z).
	var bridge := place_glb("res://assets/props/w1/stone_bridge/stone_bridge.glb", "StoneBridge", Vector3(-6, -0.25, 10.0), 0.0, 1.12)
	if bridge:
		shells["bridge"] = trimesh_from(bridge, "StoneBridgeShell")
	else:
		L.arched_bridge(self)
	# Page Gate (procedural book stacks and ribbon arch; no GLB yet).
	var gate := Node3D.new()
	gate.name = "PageGate"
	gate.position = Vector3(0, 0.4, 57.5)
	add_child(gate)
	L.page_gate(gate)
	# Grand Birch with the treehouse, Hollow Tor, willow, grotto, camp, scarecrow (w1_dress).
	D.landmarks(self)


## Interim R2.10 cottage: walls 7 x 6 m of bulging straw-bundle courses on a stone plinth, a steep 40-degree
## gable roof (ridge north-south, so the triangle faces the spawn with the door in it) of two thick thatch slabs with
## overhanging eaves and a ridge roll. Box collision matches the visual. Requested: w1_straw_house_walls / _roof.
var straw_roof: Node3D


func _straw_cottage(at: Vector3) -> void:
	var house := Node3D.new()
	house.name = "StrawHouse"
	house.position = at
	add_child(house)
	var straw := K.tex_mat("straw_thatch", Color(1.08, 1.06, 1.25), 0.45)
	var straw_dk := K.tex_mat("straw_thatch", Color(0.9, 0.84, 0.95), 0.45)
	var thatch := K.tex_mat("straw_thatch", Color(1.0, 0.92, 1.0), 0.6)
	var wood := K.tex_mat("bark", Color(0.85, 0.66, 0.48), 0.5)
	var stone := K.tex_mat("cliff_rock", Color(1.05, 1.0, 0.95), 0.5)
	var hw := 3.5
	var hd := 3.0
	var wall_h := 3.45
	K.rbox(house, Vector3(hw * 2 + 0.5, 0.45, hd * 2 + 0.5), stone, Vector3(0, 0.12, 0), Vector3.ZERO, 0.15)
	K.rbox(house, Vector3(hw * 2 - 0.2, wall_h, hd * 2 - 0.2), straw_dk, Vector3(0, 0.3 + wall_h * 0.5, 0), Vector3.ZERO, 0.2)
	# Bundle courses, each a fat rounded loaf, staggered so the walls bulge.
	for k in 5:
		var y := 0.62 + k * 0.66
		var bulge := 0.16 + 0.08 * sin(float(k) * 1.3)
		# Fix round 2 (visual r1: ruler-straight walls): each course leans and drifts a little, so the walls bow.
		K.rbox(house, Vector3(hw * 2 + bulge, 0.6, hd * 2 + bulge), straw if k % 2 == 0 else straw_dk, Vector3(0.03 * (k % 2) + 0.05 * k, y, 0.04 * sin(k * 2.1)), Vector3(1.2 * sin(k * 1.7), 0.6 * (k % 2), -0.9 * k + 1.2), 0.28)
	for cx in [-hw, hw]:
		for cz in [-hd, hd]:
			K.cyl(house, 0.17, 0.2, wall_h + 0.4, wood, Vector3(cx, 0.3 + (wall_h + 0.4) * 0.5, cz), Vector3.ZERO, 8)
	for cz in [-hd, hd]:
		K.cyl(house, 0.12, 0.12, hw * 2 + 0.3, wood, Vector3(0, wall_h + 0.35, cz), Vector3(0, 0, 90), 8)
	# Front (south, +Z): round-topped door, two shuttered windows with flower boxes, a little sign.
	var door := K.tex_mat("wood_planks", Color(0.9, 0.62, 0.42), 0.6)
	K.rbox(house, Vector3(1.25, 1.75, 0.18), door, Vector3(0.0, 1.2, hd + 0.12), Vector3.ZERO, 0.05)
	K.cyl(house, 0.625, 0.625, 0.18, door, Vector3(0.0, 2.07, hd + 0.12), Vector3(90, 0, 0), 16)
	K.sphere(house, 0.07, K.mat(Color("c9a04a"), 0.3), Vector3(0.4, 1.25, hd + 0.24))
	var glass := K.mat(Color("2e4a6b"), 0.2)
	var shutter := K.mat(Color("c8302e"), 0.6)
	for wx in [-2.1, 2.1]:
		K.rbox(house, Vector3(0.95, 0.85, 0.12), glass, Vector3(wx, 2.0, hd + 0.13), Vector3.ZERO, 0.05)
		K.rbox(house, Vector3(1.1, 0.1, 0.16), wood, Vector3(wx, 2.47, hd + 0.16), Vector3.ZERO, 0.03)
		for sx in [-0.62, 0.62]:
			K.rbox(house, Vector3(0.3, 0.95, 0.08), shutter, Vector3(wx + sx, 2.0, hd + 0.2), Vector3.ZERO, 0.03)
		K.rbox(house, Vector3(1.0, 0.25, 0.3), wood, Vector3(wx, 1.45, hd + 0.25), Vector3.ZERO, 0.04)
		for fl in 4:
			K.sphere(house, 0.12, K.mat([Color("e8413b"), Color("e9c45a"), Color("f6ecd6"), Color("b46ad8")][fl % 4], 0.6), Vector3(wx - 0.36 + fl * 0.24, 1.66, hd + 0.27))
	for wz in [-1.3, 1.3]:
		for sx in [-1.0, 1.0]:
			K.rbox(house, Vector3(0.12, 0.8, 0.9), glass, Vector3(sx * (hw + 0.1), 2.0, wz), Vector3.ZERO, 0.05)
	var body := K.body(house, "StrawHouseShell")
	K.shape_box(body, Vector3(hw * 2 + 0.2, wall_h + 0.45, hd * 2 + 0.2), Vector3(0, (wall_h + 0.45) * 0.5, 0))
	# Roof: its own node, pivoted on the west eave (the R1.4 hinge line), so the blow-down can fold it off.
	var eave_y := wall_h + 0.4
	var pitch := deg_to_rad(40.0)
	var rise := hw * tan(pitch)
	straw_roof = Node3D.new()
	straw_roof.name = "StrawRoof"
	house.add_child(straw_roof)
	straw_roof.position = Vector3(-hw, eave_y, 0)
	var roof_v := Node3D.new()
	roof_v.name = "Visual"
	straw_roof.add_child(roof_v)
	roof_v.position = Vector3(hw, 0, 0)
	var over := 0.7
	var run := hw + over
	var slope_len := run / cos(pitch)
	var thick := 0.55
	var rb := K.body(straw_roof, "StrawRoofBody")
	rb.position = Vector3(hw, 0, 0)
	for side in [-1.0, 1.0]:
		var cx: float = side * run * 0.5 + side * thick * 0.5 * sin(pitch)
		var cy := rise - run * 0.5 * tan(pitch) + thick * 0.5 * cos(pitch)
		var rot := Vector3(0, 0, -side * 40.0)
		K.rbox(roof_v, Vector3(slope_len, thick, hd * 2 + 1.1), thatch, Vector3(cx, cy, 0), rot, 0.22)
		# Thatch courses: three fat rolls along each slope.
		for k in 3:
			var t := 0.25 + k * 0.28
			var px: float = side * run * t
			var py := rise - run * t * tan(pitch) + thick + 0.02
			K.rbox(roof_v, Vector3(0.5, 0.2, hd * 2 + 1.15), straw, Vector3(px, py, 0), rot, 0.09)
		K.shape_box(rb, Vector3(slope_len, thick, hd * 2 + 1.1), Vector3(cx, cy, 0), rot)
	# Ridge roll and gable triangles (south front with a round attic vent, north back).
	# Fix round 2 (visual r1): the ridge sags 0.2 m in the middle (three roll segments), a fat eave lip overhangs both
	# eaves, and a wobbly clay chimney with smoke sits on the east slope (all on the roof node, so it blows off too).
	var seg_len := (hd * 2 + 1.25) / 3.0
	for si in 3:
		var sz := -hd - 0.625 + seg_len * (si + 0.5)
		var sag := -0.2 if si == 1 else -0.06
		var tilt := 0.0 if si == 1 else (3.5 if si == 0 else -3.5)
		K.cyl(roof_v, 0.36, 0.36, seg_len + 0.12, straw, Vector3(0, rise + 0.38 + sag, sz), Vector3(90 + tilt, 0, 0), 14)
	for side in [-1.0, 1.0]:
		var ex: float = side * (run + 0.12)
		var ey := rise - (run + 0.12) * tan(pitch) + thick * 0.4
		K.cyl(roof_v, 0.26, 0.26, hd * 2 + 1.3, straw_dk, Vector3(ex, ey, 0), Vector3(90, 0, 0), 12)
	var clay := K.mat(Color("c0703f"), 0.8)
	var cx0 := 1.3
	var cy0 := rise - cx0 * tan(pitch) + thick * 0.6
	for ci in 3:
		K.cyl(roof_v, 0.26 - ci * 0.02, 0.3 - ci * 0.02, 0.5, clay, Vector3(cx0 + 0.03 * ci, cy0 + 0.25 + ci * 0.46, -1.7 + 0.04 * sin(ci * 2.0)), Vector3(4.0 * sin(ci * 1.9), 0, -5.0 + 3.0 * ci), 10)
	K.torus(roof_v, 0.2, 0.32, K.mat(Color("a85a30"), 0.8), Vector3(cx0 + 0.08, cy0 + 1.52, -1.7))
	D.fx(roof_v, "ChimneySmoke", Vector3(cx0 + 0.08, cy0 + 1.7, -1.7))
	var tri := _prism_mesh(hw * 2, rise, 0.25)
	for gz in [-hd, hd]:
		var gm := K.add(roof_v, tri, straw_dk, Vector3(0, 0, gz))
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	K.cyl(roof_v, 0.32, 0.32, 0.1, wood, Vector3(0, rise * 0.45, hd + 0.16), Vector3(90, 0, 0), 14)
	K.cyl(roof_v, 0.24, 0.24, 0.12, glass, Vector3(0, rise * 0.45, hd + 0.18), Vector3(90, 0, 0), 14)
	# A little straw tuft and a weathercock pole on the ridge, CB1's perch.
	K.cone(roof_v, 0.35, 0.7, straw, Vector3(0, rise + 0.9, -hd + 0.6), Vector3.ZERO, 8)


## A sail cloth panel w x h (local XY, centred), bellied `belly` m toward +Z in the middle.
static func _sail_cloth_mesh(w: float, h: float, belly: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 3
	var nv := 8
	var pt := func(i: int, j: int) -> Vector3:
		var u := float(i) / nu
		var v := float(j) / nv
		return Vector3((u - 0.5) * w, (v - 0.5) * h, belly * sin(PI * u) * sin(PI * v))
	for i in nu:
		for j in nv:
			var a: Vector3 = pt.call(i, j)
			var b: Vector3 = pt.call(i + 1, j)
			var c: Vector3 = pt.call(i + 1, j + 1)
			var d: Vector3 = pt.call(i, j + 1)
			for q: Vector3 in [a, b, c, a, c, d]:
				st.set_uv(Vector2(q.x / w + 0.5, q.y / h + 0.5))
				st.add_vertex(q)
	st.generate_normals()
	return st.commit()


## A triangular gable prism: base width w, height h, depth d (local origin at the base centre).
static func _prism_mesh(w: float, h: float, d: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-w * 0.5, 0, 0)
	var b := Vector3(w * 0.5, 0, 0)
	var c := Vector3(0, h, 0)
	var f := Vector3(0, 0, d * 0.5)
	var tris := [[a + f, b + f, c + f], [b - f, a - f, c - f], [a - f, a + f, c + f], [a - f, c + f, c - f], [b + f, b - f, c - f], [b + f, c - f, c + f]]
	for t in tris:
		var n: Vector3 = ((t[1] as Vector3) - (t[0] as Vector3)).cross((t[2] as Vector3) - (t[0] as Vector3)).normalized()
		for v in t:
			st.set_normal(n)
			st.set_uv(Vector2((v as Vector3).x / w + 0.5, (v as Vector3).y / maxf(h, 0.01)))
			st.add_vertex(v)
	return st.commit()


const CHIMNEY_H := 16.0  # builder amendment: crown at y 28 (plan 26), so no roof perch can backflip onto it


func _chimney(n: Node3D) -> void:
	# Local frame: origin (5, 12, -36). Outer x 9.5..13.1 -> local 4.5..8.1; z -37.6..-34.4 -> local -1.6..1.6.
	var hh := CHIMNEY_H
	var cb := K.body(n, "ChimneyWalls")
	cb.add_to_group("w1_chimney")
	var walls := [
		[Vector3(0.3, hh, 3.2), Vector3(4.65, hh * 0.5, 0)],
		[Vector3(3.6, hh, 0.3), Vector3(6.3, hh * 0.5, -1.45)],
		[Vector3(3.6, hh, 0.3), Vector3(6.3, hh * 0.5, 1.45)],
		[Vector3(0.3, hh, 0.8), Vector3(7.95, hh * 0.5, -1.2)],
		[Vector3(0.3, hh, 0.8), Vector3(7.95, hh * 0.5, 1.2)],
		[Vector3(0.3, hh - 1.9, 1.6), Vector3(7.95, 1.9 + (hh - 1.9) * 0.5, 0)],
	]
	var brick := K.tex_mat("brick", Color(0.98, 0.78, 0.7), 0.32)  # R2.11: chunkier, darker courses closer to the house mesh
	var v := Node3D.new()
	v.name = "ChimneyVisual"
	n.add_child(v)
	# Visual: the generated hollow shaft (meshes workstream, built to the W1-6 geometry) stretched to 16 m;
	# the builder boxes below stay the collision. Procedural walls are the fallback.
	var shaft := glb("res://assets/props/w1/brick_chimney_shaft/brick_chimney_shaft.glb")
	if shaft:
		var si := shaft.instantiate() as Node3D
		si.name = "ShaftMesh"
		si.position = Vector3(6.3, 0, 0)
		si.scale = Vector3(0.95, hh / 14.97, 0.92)
		v.add_child(si)
		_chimney_south.append(si)
	# R3.11: a lime-washed lower stack (y 12-17.5) in the house-wall cream so it reads as part of the cottage.
	var lime := K.tex_mat("plaster_wall", Color(0.93, 0.8, 0.64), 0.55, 0.9)
	var band := [
		[Vector3(0.12, 5.5, 3.5), Vector3(4.33, 2.75, 0)], [Vector3(3.9, 5.5, 0.12), Vector3(6.3, 2.75, -1.79)],
		[Vector3(3.9, 5.5, 0.12), Vector3(6.3, 2.75, 1.79)], [Vector3(0.12, 5.5, 1.1), Vector3(8.27, 2.75, -1.2)],
		[Vector3(0.12, 5.5, 1.1), Vector3(8.27, 2.75, 1.2)], [Vector3(0.12, 3.4, 1.4), Vector3(8.27, 3.8, 0)],
	]
	for bd in band:
		var bm := K.rbox(v, bd[0], lime, bd[1], Vector3.ZERO, 0.04)
		if (bd[1] as Vector3).z > 1.0:
			_chimney_south.append(bm)
	K.rbox(v, Vector3(4.1, 0.25, 3.7), K.mat(Color("b5483a"), 0.8), Vector3(6.3, 5.55, 0), Vector3.ZERO, 0.06)
	# Cutaway: the flue's west, north and east walls as open brick (shown only while the cutaway camera films the climb).
	_chimney_cut = Node3D.new()
	_chimney_cut.name = "ChimneyCutaway"
	_chimney_cut.visible = false
	v.add_child(_chimney_cut)
	var inner := K.tex_mat("brick", Color(0.78, 0.58, 0.5), 0.55)
	for wi in walls.size():
		var w: Array = walls[wi]
		K.shape_box(cb, w[0], w[1])
		if shaft == null:
			var wm := K.rbox(v, w[0], brick, w[1], Vector3.ZERO, 0.08)
			if wi == 2:
				_chimney_south.append(wm)
		if wi != 2:
			K.rbox(_chimney_cut, w[0], inner, w[1], Vector3.ZERO, 0.04)
	# A cut edge along the missing south wall so the cutaway reads as a sliced chimney, not a missing mesh.
	var cut_edge := K.mat(Color("8a3b2a"), 0.9)
	for ex in [4.65, 7.95]:
		K.rbox(_chimney_cut, Vector3(0.36, hh, 0.12), cut_edge, Vector3(ex, hh * 0.5, 1.45), Vector3.ZERO, 0.03)
	# Soot ledge (rest), top y 19.0 world -> local 7.0.
	# Builder fix 06:10: 0.6 m deep (was 0.9) so a centred wall-kick climb clears its underside by 0.35 m instead of 0.05 m
	# (the bot bonked on it at y 17.45 and stalled; a player drifting a few cm would too).
	K.shape_box(cb, Vector3(3.0, 0.4, 0.6), Vector3(6.3, 6.8, 1.0))
	K.rbox(v, Vector3(3.0, 0.4, 0.6), K.mat(Color("6d5a52")), Vector3(6.3, 6.8, 1.0), Vector3.ZERO, 0.08)
	# Soot door arch, crown band and pots, sooty floor.
	K.torus(v, 0.7, 0.95, K.mat(K.STONE_DARK), Vector3(8.12, 1.9, 0), Vector3(0, 0, 90))
	var soot := K.mat(Color("2b2220"), 0.95)
	K.rbox(v, Vector3(0.06, 1.8, 1.5), soot, Vector3(8.05, 0.9, 0), Vector3.ZERO, 0.02)
	var crown := K.mat(Color("d8c7a8"))
	for z in [-1.55, 1.55]:
		var cr := K.rbox(v, Vector3(4.0, 0.45, 0.5), crown, Vector3(6.3, hh - 0.15, z), Vector3.ZERO, 0.1)
		if z > 0.0:
			_chimney_south.append(cr)
	for x in [4.55, 8.05]:
		K.rbox(v, Vector3(0.5, 0.45, 3.6), crown, Vector3(x, hh - 0.15, 0), Vector3.ZERO, 0.1)
	var pot := K.mat(Color("c0703f"))
	# Fix round 1 (visual critic r1: still a ruler-straight factory smokestack): two stepped brick shoulders 0.3 m
	# proud, a fat corbelled crown and fat 0.7 m pots, ivy on the lime band and a soot cap. Visual only; the
	# collision and the W1-6 shaft are unchanged. South-facing pieces join the cutaway set.
	var shoulder := K.tex_mat("brick", Color(0.92, 0.7, 0.62), 0.32)
	for sy in [5.5, 9.0]:
		var parts := [[Vector3(0.3, 0.4, 3.8), Vector3(4.35, sy, 0)], [Vector3(0.3, 0.4, 3.8), Vector3(8.25, sy, 0)],
			[Vector3(4.2, 0.4, 0.3), Vector3(6.3, sy, -1.75)], [Vector3(4.2, 0.4, 0.3), Vector3(6.3, sy, 1.75)]]
		for sp in parts:
			var sm := K.rbox(v, sp[0], shoulder, sp[1], Vector3.ZERO, 0.08)
			if (sp[1] as Vector3).z > 1.0:
				_chimney_south.append(sm)
	var corbel := K.mat(Color("cdb894"))
	for cp in [[Vector3(0.45, 0.4, 4.3), Vector3(4.4, hh - 0.75, 0)], [Vector3(0.45, 0.4, 4.3), Vector3(8.2, hh - 0.75, 0)],
			[Vector3(4.3, 0.4, 0.45), Vector3(6.3, hh - 0.75, -1.85)], [Vector3(4.3, 0.4, 0.45), Vector3(6.3, hh - 0.75, 1.85)]]:
		var cm := K.rbox(v, cp[0], corbel, cp[1], Vector3.ZERO, 0.12)
		if (cp[1] as Vector3).z > 1.0:
			_chimney_south.append(cm)
	var soot_cap := K.mat(Color("4a3a34"), 0.95)
	for sc in [[Vector3(0.08, 1.6, 3.7), Vector3(4.42, hh - 1.7, 0)], [Vector3(0.08, 1.6, 3.7), Vector3(8.18, hh - 1.7, 0)], [Vector3(3.9, 1.6, 0.08), Vector3(6.3, hh - 1.7, -1.72)]]:
		K.rbox(v, sc[0], soot_cap, sc[1], Vector3.ZERO, 0.03)
	# Fix round 2 (visual r1: the R3.11 details were too small to register): fat bellied terracotta pots with a rolled lip
	# (one carries a brass pig weathervane), big ivy clumps on the south and east faces, a soot-darkened upper stack, and
	# alternate courses nudged 0.1 m so the stack reads hand-laid rather than ruler-straight. Visual only.
	for pp in [Vector3(4.75, hh + 0.05, -1.3), Vector3(7.85, hh + 0.05, 1.3)]:
		K.cyl(v, 0.36, 0.46, 0.5, pot, pp + Vector3(0, 0.25, 0), Vector3.ZERO, 14)
		K.sphere(v, 0.5, pot, pp + Vector3(0, 0.62, 0), Vector3(1.0, 0.7, 1.0))
		K.cyl(v, 0.34, 0.4, 0.42, pot, pp + Vector3(0, 0.98, 0), Vector3.ZERO, 14)
		K.torus(v, 0.3, 0.46, K.mat(Color("a85a30")), pp + Vector3(0, 1.2, 0))
	var vane := Node3D.new()
	vane.name = "PigWeathervane"
	v.add_child(vane)
	vane.position = Vector3(7.85, hh + 1.25, 1.3)
	var brass := K.mat(Color("c9a04a"), 0.3)
	K.cyl(vane, 0.025, 0.025, 1.0, brass, Vector3(0, 0.5, 0), Vector3.ZERO, 6)
	K.sphere(vane, 0.2, brass, Vector3(0, 1.1, 0), Vector3(1.5, 1.0, 1.0))
	K.cyl(vane, 0.07, 0.09, 0.12, brass, Vector3(0.32, 1.1, 0), Vector3(0, 0, 90), 8)
	K.cone(vane, 0.12, 0.25, brass, Vector3(-0.35, 1.18, 0), Vector3(0, 0, 70), 4)
	var vtw := vane.create_tween().set_loops()
	vtw.tween_property(vane, "rotation_degrees:y", 25.0, 3.2).set_trans(Tween.TRANS_SINE)
	vtw.tween_property(vane, "rotation_degrees:y", -20.0, 3.6).set_trans(Tween.TRANS_SINE)
	var ivy := K.mat(Color("4f9a37"), 0.85)
	var ivy2 := K.mat(Color("6fae3a"), 0.85)
	var ivy3 := K.mat(Color("86c04a"), 0.85)
	var irng := RandomNumberGenerator.new()
	irng.seed = 616
	for c in 5:
		var east := c < 3
		var base := Vector3(8.36, 0.9 + c * 1.5, -0.9 + c * 0.55) if east else Vector3(5.2 + (c - 3) * 2.0, 1.0 + (c - 3) * 2.2, 1.92)
		for k in 4:
			var off := Vector3(0, irng.randf_range(-0.5, 0.6), irng.randf_range(-0.45, 0.45)) if east else Vector3(irng.randf_range(-0.45, 0.45), irng.randf_range(-0.5, 0.6), 0)
			var scl := Vector3(0.3, 1.0, 1.25) if east else Vector3(1.25, 1.0, 0.3)
			var im := K.sphere(v, irng.randf_range(0.36, 0.5), [ivy, ivy2, ivy3][k % 3], base + off, scl)
			if not east:
				_chimney_south.append(im)
	var soot_band := K.tex_mat("brick", Color(0.62, 0.48, 0.44), 0.32)
	for sb in [[Vector3(0.04, 5.2, 3.3), Vector3(4.48, 11.6, 0)], [Vector3(0.04, 5.2, 3.3), Vector3(8.12, 11.6, 0)], [Vector3(3.6, 5.2, 0.04), Vector3(6.3, 11.6, -1.66)], [Vector3(3.6, 5.2, 0.04), Vector3(6.3, 11.6, 1.66)]]:
		var sm2 := K.rbox(v, sb[0], soot_band, sb[1], Vector3.ZERO, 0.01)
		if (sb[1] as Vector3).z > 1.0:
			_chimney_south.append(sm2)
	for ci in 6:
		var cy := 6.2 + ci * 1.6
		var dx := 0.1 if ci % 2 == 0 else -0.06
		for cp in [[Vector3(4.0, 0.18, 0.08), Vector3(6.3 + dx, cy, 1.69)], [Vector3(0.08, 0.18, 3.4), Vector3(8.16, cy, dx)]]:
			var course := K.rbox(v, cp[0], shoulder, cp[1], Vector3.ZERO, 0.02)
			if (cp[1] as Vector3).z > 1.0:
				_chimney_south.append(course)
	K.rbox(v, Vector3(2.9, 0.06, 2.5), soot, Vector3(6.3, 0.03, 0))
	# (The old camera_hint Area is replaced by the cutaway camera, _cutcams.)
	# R2.11: a cold flue lit by three lanterns and a cool crown spot; the smoke comes from the kitchen pot instead.
	for lp in [Vector3(6.3, 2.0, -0.9), Vector3(6.3, 7.6, 1.0), Vector3(6.3, 12.0, -0.9)]:
		var ol := OmniLight3D.new()
		ol.light_color = Color("ffb46b") if lp.y < 10.0 else Color("ffd9a0")
		ol.light_energy = 1.0
		ol.omni_range = 4.3
		ol.position = lp
		n.add_child(ol)
		K.rbox(n, Vector3(0.22, 0.32, 0.22), K.glow_mat(Color("ffcf7a"), 2.2), lp + Vector3(0, 0, -0.35 if lp.z < 0 else 0.35), Vector3.ZERO, 0.05)
	var spot := SpotLight3D.new()
	spot.light_color = Color("cde8f5")
	spot.light_energy = 1.5
	spot.spot_angle = 35.0
	spot.spot_range = 16.0
	spot.position = Vector3(6.3, hh + 0.4, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	n.add_child(spot)
	D.fx(self, "ChimneySmoke", Vector3(1.2, 21.6, -36.0))
	# R3.7: Bertram lights the stove when Mak's feet pass y 19.3 going up: a 30 s 2.5 m/s draught in the upper flue.
	var flue := obj("WindZone", Vector3(11.3, 22.5, -36.0), {"size": Vector3(3.0, 7.0, 2.6), "direction": Vector3(0, 1, 0), "strength": 2.5, "mode": WindZone.Mode.STEADY, "end_falloff": 0.0, "enabled": false, "streak_color": Color(1.0, 0.7, 0.35, 0.5)})
	if flue:
		flue.name = "W_flue"
		var trig := Area3D.new()
		trig.name = "FlueTrigger"
		trig.collision_layer = 128
		trig.collision_mask = 2
		add_child(trig)
		trig.global_position = Vector3(11.3, 19.6, -36.0)
		K.shape_box(trig, Vector3(3.0, 0.6, 2.6))
		trig.body_entered.connect(func(b: Node) -> void:
			if not b.is_in_group("player") or bool(flue.get("enabled")):
				return
			var bvel: Variant = b.get("velocity")
			if bvel is Vector3 and (bvel as Vector3).y <= 0.0:
				return
			flue.call("set_enabled", true)
			var ui := get_node_or_null("/root/UI")
			if ui and ui.has_method("toast"):
				ui.call("toast", "Bertram: \"Oh, are you STILL in there? I'll put the kettle on!\"")
			for k in 3:
				ObjSvc.burst(self, Vector3(11.3, 13.0 + k * 0.3, -36.0), Color(1.0, 0.55, 0.2), 16, 4.0, 0.12, 6.0, 1.2)
			get_tree().create_timer(30.0).timeout.connect(func() -> void: flue.call("set_enabled", false)))


## Fix round 1 (feel critic r1): the old camera_hint Areas carried metas the camera never read. These are real
## MakCameraRig camera_zone volumes (layer 8; values as metas: yaw/pitch/distance/blend/priority; unset keeps the
## free camera's value). Tight spaces where the spring arm would wedge (chimney flue, Hollow Log) use the cutaway
## camera below instead.
func _camera_hints() -> void:
	var zones := [
		# W1-2 sail ride: face-on to the wheel from the south so the approaching step and the crest jump read.
		# Fix round 2 (feel r1): pitch -12 (was -4) so the vane deck and the next step stay in frame.
		{"name": "CamZone_sail_ride", "pos": Vector3(40, 25.0, -41.6), "size": Vector3(20.0, 20.0, 9.0), "camera_yaw_deg": 0.0, "camera_pitch_deg": -12.0, "camera_distance": 12.0, "camera_blend": 4.0, "camera_priority": 3},
		# W1-7 pen, the whole fight (fix round 2, fun r1: the round-2 fight camera hid the game): high and wide, yaw locked
		# to the gate bearing (Mak walks in from the east), the bale ring is invisible to the spring arm (SOLID_NO_CAM).
		{"name": "CamZone_hay_yard", "pos": Vector3(-43.0, 3.0, -48.5), "size": Vector3(18.5, 9.0, 18.5), "camera_yaw_deg": 90.0, "camera_pitch_deg": -45.0, "camera_distance": 11.5, "camera_blend": 3.0, "camera_priority": 2},
		# P4 Kick Cleft (fix round 2, feel r1: the level camera could not fit and rested at 1.35 m): look down into the slot
		# from above the open mouth.
		{"name": "CamZone_kick_cleft", "pos": Vector3(-54.0, 6.0, -7.9), "size": Vector3(3.2, 12.5, 4.8), "camera_yaw_deg": 180.0, "camera_pitch_deg": -25.0, "camera_distance": 6.0, "camera_priority": 2},
		# W1-3 greased pole (fix round 2, feel r1): south-east of the pole looking north-west toward sc7, slightly up.
		{"name": "CamZone_scaffold_pole", "pos": Vector3(-37.1, 10.5, -26.5), "size": Vector3(2.5, 4.0, 2.5), "camera_yaw_deg": 45.0, "camera_pitch_deg": 8.0, "camera_distance": 6.0, "camera_priority": 2},
		# Crows' Nest backflip (fix round 2, feel r1, R2.5): camera south-east of the nest looking north-west, outside the canopy.
		{"name": "CamZone_hut_roof", "pos": Vector3(-47.5, 21.0, -30.0), "size": Vector3(5.0, 6.0, 6.0), "camera_yaw_deg": 45.0, "camera_pitch_deg": 10.0, "camera_distance": 6.0, "camera_priority": 2},
		# Upward hops with hidden landings (fix round 2, feel r1): look down over the straw bale tiers and the Tor row.
		{"name": "CamZone_bale_tiers", "pos": Vector3(-14.6, 4.8, 28.0), "size": Vector3(4.5, 5.0, 6.5), "camera_pitch_deg": -28.0, "camera_distance": 6.5, "camera_priority": 1},
		{"name": "CamZone_tor_row", "pos": Vector3(30.5, 4.8, 0.5), "size": Vector3(9.0, 6.0, 9.0), "camera_pitch_deg": -28.0, "camera_distance": 7.0, "camera_priority": 1},
		# Rope bridge: ride above the invisible rail walls.
		{"name": "CamZone_rope_bridge", "pos": Vector3(-25.75, 14.8, -31.5), "size": Vector3(34.0, 5.0, 3.2), "camera_pitch_deg": -28.0, "camera_distance": 6.5, "camera_priority": 1},
		# Brick roof route (window box, dormer plank, roof walk): keep the camera on the open south side.
		{"name": "CamZone_brick_roof", "pos": Vector3(4.5, 20.0, -34.2), "size": Vector3(9.5, 4.5, 6.0), "camera_yaw_deg": 0.0, "camera_pitch_deg": -24.0, "camera_distance": 6.0, "camera_priority": 2},
	]
	for h in zones:
		var a := Area3D.new()
		a.name = String(h["name"])
		a.add_to_group("camera_zone")
		a.collision_layer = 128
		a.collision_mask = 0
		a.monitoring = false
		a.monitorable = true
		for k in h:
			if k not in ["name", "pos", "size"]:
				a.set_meta(k, h[k])
		add_child(a)
		a.global_position = h["pos"]
		K.shape_box(a, h["size"])


# ------------------------------------------------------------------ cutaway camera (chimney flue, Hollow Log)

var _cut_cam: Camera3D
var _cut_prev: Camera3D
var _cut_vols: Array[Dictionary] = []
var _cut_active := -1
var _cut_y := 0.0
var _chimney_south: Array[Node3D] = []
var _chimney_cut: Node3D
var _fade_mat: ShaderMaterial
var _cut_from := Transform3D()
var _cut_from_fov := 60.0
var _cut_blend := 1.0
const CUT_BLEND_S := 0.35


## Fix round 1 (feel + fun critics r1: the W1-6 flue showed solid brick for 18-30 % of the climb and the P1 log hid Mak
## in 401 of 401 frames). While Mak is inside one of these volumes a fixed side camera takes over and the wall between
## it and Mak is cut away (chimney: the south shell swaps for an open brick box) or faded (log). Input stays
## camera-relative because the player reads the viewport camera.
func _cutcams() -> void:
	_cut_cam = Camera3D.new()
	_cut_cam.name = "CutawayCam"
	_cut_cam.fov = 60.0
	_cut_cam.far = 600.0
	add_child(_cut_cam)
	# Fix round 2 (feel r1: a flat unshaded brown film at alpha 0.28 could read as mud): the faded log keeps its bark
	# texture and shading, dithered down to a light ghost, so Mak reads cleanly through it.
	# Render fix 2026-10-19 (owner: the 22 % alpha-hash dither read as harsh coloured noise): the camera-facing shell is
	# cut away instead (assets/shaders/occluder_cutaway.gdshader), far wall and floor stay solid, no dither.
	var bark := K.tex_mat("bark", Color(0.9, 0.72, 0.52), 0.45)
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = load("res://assets/shaders/occluder_cutaway.gdshader") as Shader
	_fade_mat.set_shader_parameter("albedo", bark.albedo_color)
	_fade_mat.set_shader_parameter("albedo_texture", bark.albedo_texture)
	_fade_mat.set_shader_parameter("triplanar_scale", bark.uv1_scale.x)
	# Chimney: shaft x 9.8..12.8, z -37.3..-34.7, floor y 12, crown 28; plus the soot-door mouth on the east side.
	_cut_vols.append({"name": "chimney", "boxes": [AABB(Vector3(9.8, 11.8, -37.3), Vector3(3.2, 16.6, 2.6)), AABB(Vector3(13.0, 11.8, -36.9), Vector3(1.6, 2.6, 1.8))],
		"kind": "chimney"})
	var hlog := get_node_or_null("HollowLog") as Node3D
	if hlog:
		var ln := float(hlog.get_meta("length", 6.0))
		var lp := hlog.global_position
		var fades: Array = []
		for mi in hlog.get_children():
			if mi is MeshInstance3D and ((mi as MeshInstance3D).mesh is CylinderMesh or mi.has_meta("log_fade")):
				fades.append(mi)
		_cut_vols.append({"name": "log", "boxes": [AABB(Vector3(lp.x - ln * 0.5 - 0.3, lp.y - 0.3, lp.z - 0.8), Vector3(ln + 0.6, 1.5, 1.6))],
			"kind": "log", "fades": fades, "node": hlog, "x0": lp.x - ln * 0.5 - 0.6, "x1": lp.x + ln * 0.5 + 0.6, "z": lp.z, "y": lp.y})


func _cut_update(delta: float) -> void:
	if _cut_cam == null:
		return
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var pp := pl.get_global_transform_interpolated().origin
	var idx := -1
	for i in _cut_vols.size():
		for b: AABB in _cut_vols[i]["boxes"]:
			if b.grow(0.05).has_point(pp + Vector3(0, 0.3, 0)):
				idx = i
				break
		if idx >= 0:
			break
	var cur := get_viewport().get_camera_3d()
	if idx >= 0:
		if _cut_active < 0:
			# A story camera or the hay-yard overhead owns the view: leave it alone.
			if cur != null and cur != _cut_cam and not pl.is_ancestor_of(cur):
				return
			_cut_prev = cur
			_cut_y = pp.y
			# Fix round 2 (feel r1: a hard cut and a 90 degree turn of the held stick): blend in from the follow camera.
			_cut_from = cur.global_transform if cur != null else Transform3D()
			_cut_from_fov = cur.fov if cur != null else 60.0
			_cut_blend = 0.0 if cur != null else 1.0
		if idx != _cut_active:
			_cut_set(_cut_active, false)
			_cut_set(idx, true)
			_cut_active = idx
			_cut_y = pp.y
		var v: Dictionary = _cut_vols[idx]
		_cut_y = lerpf(_cut_y, pp.y, 1.0 - exp(-9.0 * delta))
		var cpos: Vector3
		var look: Vector3
		if v["kind"] == "chimney":
			cpos = Vector3(11.3, _cut_y + 1.3, -28.6)
			look = Vector3(11.3, _cut_y + 0.7, -36.0)
			_cut_cam.fov = 62.0
		else:
			var cx := clampf(pp.x, float(v["x0"]), float(v["x1"]))
			cpos = Vector3(cx, float(v["y"]) + 1.7, float(v["z"]) + 5.2)
			look = Vector3(cx, float(v["y"]) + 0.45, float(v["z"]))
			_cut_cam.fov = 58.0
		var want := Transform3D(Basis.looking_at(look - cpos, Vector3.UP), cpos)
		if _cut_blend < 1.0:
			_cut_blend = minf(_cut_blend + delta / CUT_BLEND_S, 1.0)
			var e := _cut_blend * _cut_blend * (3.0 - 2.0 * _cut_blend)
			want = _cut_from.interpolate_with(want, e)
			_cut_cam.fov = lerpf(_cut_from_fov, _cut_cam.fov, e)
		_cut_cam.global_transform = want
		if not _cut_cam.current:
			_cut_cam.current = true
	elif _cut_active >= 0:
		_cut_set(_cut_active, false)
		_cut_active = -1
		if _cut_cam.current:
			if is_instance_valid(_cut_prev):
				_cut_prev.current = true
			else:
				_cut_cam.current = false


func _cut_set(i: int, on: bool) -> void:
	if i < 0 or i >= _cut_vols.size():
		return
	var v: Dictionary = _cut_vols[i]
	if v["kind"] == "chimney":
		for n in _chimney_south:
			if is_instance_valid(n):
				n.visible = not on
		if _chimney_cut:
			_chimney_cut.visible = on
	else:
		# The bark ridges (meta log_fade) are added by w1_dress after this list was built, so collect the log's parts again here.
		var parts: Array = v["fades"]
		var node := v.get("node") as Node3D
		if is_instance_valid(node):
			parts = node.get_children().filter(func(c): return c is MeshInstance3D and ((c as MeshInstance3D).mesh is CylinderMesh or c.has_meta("log_fade")))
		for mi in parts:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).material_override = _fade_mat if on else null


func _door_sign() -> void:
	var lbl := Label3D.new()
	lbl.name = "SIGN_door"
	lbl.text = "Not by the hair of my\nchinny-chin-chin.\n- The Management"
	lbl.font_size = 30
	lbl.pixel_size = 0.004
	lbl.modulate = Color("f6ecd6")
	lbl.outline_size = 8
	lbl.outline_modulate = Color("3b2416")
	lbl.position = Vector3(4.2, 14.9, -32.45)
	add_child(lbl)


# ------------------------------------------------------------------ static platforms

func _platforms() -> void:
	var rock := K.tex_mat("cliff_rock", Color(1.08, 1.04, 0.98), 0.55)
	var moss := K.mat(Color("7fae45"), 0.85)
	var wood := K.tex_mat("wood_planks", Color(1.0, 0.86, 0.68), 0.6)
	var bark := K.tex_mat("bark", Color(0.95, 0.82, 0.66), 0.5)
	for id in plat:
		var p: Dictionary = plat[id]
		var t: String = p["type"]
		var top := v3(p["top"])
		var size := v3(p["size"])
		var yaw: float = float(p.get("yaw_deg", 0.0))
		match t:
			"static_rock":
				if size.y > 2.5 and not id.begins_with("tor_rock"):
					# Tall granite: the Stone Finger (P2) and the Kick Cleft walls (P4). Outer faces are no-ledge-grab.
					var bt := K.body(self, id, top, yaw)
					bt.set_meta("no_ledge_grab", true)
					bt.add_to_group("no_ledge_grab")
					K.shape_box(bt, size, Vector3(0, -size.y * 0.5, 0))
					K.rbox(bt, size, K.tex_mat("cliff_rock", Color(1.06, 1.02, 0.96), 0.3), Vector3(0, -size.y * 0.5, 0), Vector3.ZERO, 0.45)
					K.rbox(bt, Vector3(size.x * 0.8, 0.12, size.z * 0.8), moss, Vector3(0, 0.0, 0), Vector3.ZERO, 0.05)
					continue
				if id.begins_with("tor_rock"):
					# Pillars rise from the ground to the plan top (2.2 m wide: builder amendment, plan 1.6).
					size.x = 2.2
					var gh := gy(top.x, top.z)
					var h := maxf(top.y - gh + 0.4, 1.0)
					var b := K.body(self, id, Vector3(top.x, top.y, top.z), 0.0)
					K.shape_cyl(b, size.x * 0.5, h, Vector3(0, -h * 0.5, 0))
					K.cyl(b, size.x * 0.5, size.x * 0.62, h, rock, Vector3(0, -h * 0.5, 0), Vector3(0, float(id.hash() % 90), 0), 9)
					# Fix round 2 (feel r1: tor tops were meadow green on meadow green from the follow camera): a pale
					# stone rim and a darker side band frame each landing, with a small mossy-stone centre.
					K.cyl(b, size.x * 0.53, size.x * 0.53, 0.1, K.mat(Color("ddd3bf"), 0.7), Vector3(0, -0.03, 0), Vector3.ZERO, 12)
					K.cyl(b, size.x * 0.55, size.x * 0.56, 0.32, K.mat(Color("7a6f62"), 0.85), Vector3(0, -0.26, 0), Vector3.ZERO, 12)
					K.cyl(b, size.x * 0.34, size.x * 0.36, 0.06, K.mat(Color("6e9a46"), 0.85), Vector3(0, 0.02, 0), Vector3.ZERO, 10)
				else:
					var b2 := K.body(self, id, top, 0.0)
					var r := maxf(size.x, size.z) * 0.5
					if size.x == size.z:
						K.shape_cyl(b2, r, size.y, Vector3(0, -size.y * 0.5, 0))
						K.sphere(b2, r, rock, Vector3(0, -size.y * 0.42, 0), Vector3(1.0, size.y / (2.0 * r) * 1.15, 1.0))
					else:
						K.shape_box(b2, size, Vector3(0, -size.y * 0.5, 0))
						K.rbox(b2, size + Vector3(0.1, 0, 0.1), rock, Vector3(0, -size.y * 0.5, 0), Vector3.ZERO, 0.35)
					K.rbox(b2, Vector3(size.x * 0.7, 0.08, size.z * 0.6), moss, Vector3(0.1, 0.0, -0.05), Vector3.ZERO, 0.04)
			"static_log":
				var b3 := K.body(self, id, top, yaw)
				K.shape_box(b3, Vector3(0.9, 0.3, size.z), Vector3(0, -0.15, 0))
				K.shape_box(b3, Vector3(size.x, size.y, size.z), Vector3(0, -size.y * 0.5 - 0.05, 0))
				K.cyl(b3, 0.55, 0.55, size.z + 0.4, bark, Vector3(0, -0.5, 0), Vector3(90, 0, 0), 14)
				for e in [-1.0, 1.0]:
					K.cyl(b3, 0.5, 0.5, 0.06, K.mat(Color("d9b27a"), 0.8), Vector3(0, -0.5, e * (size.z * 0.5 + 0.22)), Vector3(90, 0, 0), 14)
				K.sphere(b3, 0.3, moss, Vector3(0.2, -0.05, 1.5), Vector3(1.2, 0.35, 1.6))
			"static_haybale":
				_hay_step(id, top, size)
			"static_cart":
				_cart(id, top, size, yaw)
			"static_crate":
				pass  # bellows step crates: placed by _bellows()
			"static_woodpile":
				var b4 := K.body(self, id, top, yaw)
				K.shape_box(b4, size, Vector3(0, -size.y * 0.5, 0))
				for row in 3:
					for i in 5 - row:
						K.cyl(b4, 0.2, 0.2, size.z, bark, Vector3(-0.8 + row * 0.2 + i * 0.4, -size.y + 0.2 + row * 0.38, 0), Vector3(90, 0, 0), 10)
			"static_wood":
				if id in ["mill_weathervane_deck", "mill_cap_gallery"]:
					continue  # handled with the windmill
				if id in ["treehouse_deck", "treehouse_hut_roof"]:
					continue  # w1_dress builds the treehouse
				var b5 := K.platform(self, id, top, size, yaw, wood, 0.06)
				D.posts_under(b5, size, top, gy(top.x, top.z))
			"static_barrel":
				var b6 := K.body(self, id, top, 0.0)
				K.shape_cyl(b6, size.x * 0.5, size.y, Vector3(0, -size.y * 0.5, 0))
				K.cyl(b6, size.x * 0.48, size.x * 0.44, size.y, K.tex_mat("wood_planks", Color(0.9, 0.7, 0.5), 0.9), Vector3(0, -size.y * 0.5, 0), Vector3.ZERO, 16)
				for hy in [0.2, 0.8]:
					K.torus(b6, size.x * 0.46, size.x * 0.52, K.mat(Color("3b3b44"), 0.4), Vector3(0, -size.y * hy, 0))
				K.cyl(b6, size.x * 0.44, size.x * 0.44, 0.04, K.mat(Color("4fb3d9"), 0.15), Vector3(0, -0.06, 0), Vector3.ZERO, 16)
			"static_roof":
				var b7 := K.platform(self, id, top, size, yaw, K.tex_mat("roof_shingles_slate", Color(0.95, 0.98, 1.05), 0.5), 0.08)
				D.posts_under(b7, size, top, gy(top.x, top.z))
			"ramp":
				if id == "log_ramp":
					_wedge(id, Vector3(-9.0, 0.05, 1.5), Vector3(-14.0, 0.75, 1.5), size.z)
				else:
					_ramp(id, top, size)
			"static_book":
				var b8 := K.body(self, id, top, yaw + float((id.hash() % 30) - 15))
				K.shape_box(b8, size, Vector3(0, -size.y * 0.5, 0))
				var cov: Array[Color] = [Color("7a1f2e"), Color("2e6f8c"), Color("3f8f3a"), Color("c9a04a")]
				K.rbox(b8, size, K.mat(cov[absi(id.hash()) % 4], 0.55), Vector3(0, -size.y * 0.5, 0), Vector3.ZERO, 0.1)
				K.rbox(b8, size - Vector3(0.12, 0.1, -0.04), K.mat(Color("f6ecd6"), 0.9), Vector3(0.08, -size.y * 0.5, 0), Vector3.ZERO, 0.04)
				# Each book stands on a column of books down to the ground.
				var gh2 := gy(top.x, top.z)
				var col_h := top.y - size.y - gh2
				if col_h > 0.1:
					K.shape_box(b8, Vector3(size.x * 0.9, col_h, size.z * 0.9), Vector3(0, -size.y - col_h * 0.5, 0))
					var yy := -size.y
					var k := 0
					while yy > -size.y - col_h + 0.05:
						var hh := minf(0.55, yy + size.y + col_h)
						K.rbox(b8, Vector3(size.x * 0.9, hh, size.z * 0.88), K.mat(cov[(absi(id.hash()) + k + 1) % 4], 0.6), Vector3(0.05 * (k % 2), yy - hh * 0.5, 0), Vector3(0, 7.0 * (k % 3 - 1), 0), 0.08)
						yy -= hh
						k += 1
			"climb_pole", "static_hat", "rotating_level_step", "rotating_level_step_sack":
				pass  # w1_dress (treehouse pole, scarecrow) and the sail ride
			"tunnel_log":
				D.hollow_log(self, top, size)
			"static_nest":
				D.crows_nest(self, top, size)
			"bouncy":
				if id == "thatch_flap":
					continue  # appears only after the straw roof blow-down (needs the separate roof mesh)
				_bouncer(id, top, size)
			"roof_plank":
				var b10 := K.platform(self, id, top, size, 0.0, K.tex_mat("wood_planks", Color(1.0, 0.82, 0.6), 0.6), 0.05)
				if id == "brick_roof_walk":
					# Rail on the north side and the east end (the chimney side), posts down to the slates.
					K.shape_box(b10, Vector3(size.x, 1.0, 0.1), Vector3(0, 0.5, -size.z * 0.5))
					K.shape_box(b10, Vector3(0.1, 1.0, size.z), Vector3(size.x * 0.5, 0.5, 0))
					var rm := K.mat(Color("8a5a3b"), 0.8)
					K.rbox(b10, Vector3(size.x, 0.1, 0.1), rm, Vector3(0, 0.95, -size.z * 0.5), Vector3.ZERO, 0.04)
					K.rbox(b10, Vector3(0.1, 0.1, size.z), rm, Vector3(size.x * 0.5, 0.95, 0), Vector3.ZERO, 0.04)
					for i in 7:
						K.cyl(b10, 0.04, 0.04, 1.0, rm, Vector3(-size.x * 0.5 + i * size.x / 6.0, 0.5, -size.z * 0.5), Vector3.ZERO, 6)
				for sx in [-1.0, 1.0]:
					K.cyl(b10, 0.06, 0.06, 1.2, K.mat(Color("6e4a2c")), Vector3(sx * (size.x * 0.5 - 0.2), -0.7, 0), Vector3.ZERO, 6)
			"crate_step":
				var b9 := K.body(self, id, top, 15.0)
				K.shape_box(b9, size, Vector3(0, -size.y * 0.5, 0))
				var cg := glb("res://assets/props/pickups/breakable_crate/breakable_crate.glb")
				if cg:
					var ci := cg.instantiate() as Node3D
					ci.scale = size
					ci.position = Vector3(0, -size.y, 0)
					b9.add_child(ci)
			_:
				pass


func _bouncer(id: String, top: Vector3, size: Vector3) -> void:
	var apex := 8.0 if id == "haycart_bounce" else (6.5 if id == "tor_haystack_bounce" else 5.0)
	var v := sqrt(2.0 * 28.0 * apex)
	var hay := glb("res://assets/props/w1/hay_bale/hay_bale.glb")
	if id == "haycart_bounce":
		# A sprung hay cart: the cart body is static, a springy bale on top bounces (apex 8 m).
		_cart(id + "_cart", top - Vector3(0, 0.3, 0), Vector3(size.x, 0.4, size.z), 0.0)
		var pad := obj("BouncePad", top - Vector3(0, 0.25, 0), {"look": BouncePad.Look.LEAF, "radius": 1.1, "bounce_velocity": v, "visual_scene": hay, "visual_scale": 1.2})
		if pad:
			pad.name = id
	else:
		var rr := 1.1 if id == "tor_haystack_bounce" else 0.75
		var base_y := gy(top.x, top.z) if id == "tor_haystack_bounce" else top.y - 0.75
		if id == "tor_haystack_bounce":
			var hb := K.body(self, id + "_stack", Vector3(top.x, base_y, top.z))
			K.shape_cyl(hb, 1.05, top.y - base_y - 0.75, Vector3(0, (top.y - base_y - 0.75) * 0.5, 0))
			K.sphere(hb, 1.15, K.tex_mat("straw_thatch", Color(1.1, 1.2, 1.7), 0.5), Vector3(0, (top.y - base_y) * 0.45, 0), Vector3(1.0, 0.85, 1.0))
			base_y = top.y - 0.75
		var pad2 := obj("BouncePad", Vector3(top.x, base_y, top.z), {"look": BouncePad.Look.DRUM, "radius": rr, "bounce_velocity": v, "visual_scene": hay, "visual_scale": 0.85 if rr < 1.0 else 1.25})
		if pad2:
			pad2.name = id


func _hay_step(id: String, top: Vector3, size: Vector3) -> void:
	var b := K.body(self, id, top, 12.0)
	K.shape_box(b, size, Vector3(0, -size.y * 0.5, 0))
	var g := glb("res://assets/props/w1/hay_bale/hay_bale.glb")
	if g:
		var inst := g.instantiate() as Node3D
		inst.scale = Vector3(size.x / 1.65, size.y / 1.22, size.z / 1.31)
		inst.position = Vector3(0, -size.y + 0.06, 0)
		b.add_child(inst)
	else:
		K.rbox(b, size, K.tex_mat("straw_thatch", Color(1.1, 1.0, 0.8), 0.6), Vector3(0, -size.y * 0.5, 0))


func _cart(id: String, top: Vector3, size: Vector3, yaw: float) -> void:
	var b := K.body(self, id, top, yaw)
	var gh := gy(top.x, top.z)
	var h := top.y - gh
	K.shape_box(b, Vector3(size.x, h, size.z), Vector3(0, -h * 0.5, 0))
	var wood := K.tex_mat("wood_planks", Color(0.95, 0.75, 0.55), 0.8)
	K.rbox(b, Vector3(size.x, 0.5, size.z), wood, Vector3(0, -h + 0.95, 0), Vector3.ZERO, 0.08)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			K.cyl(b, 0.5, 0.5, 0.14, wood, Vector3(sx * (size.x * 0.5 + 0.08), -h + 0.5, sz * size.z * 0.3), Vector3(0, 0, 90), 14)
			K.torus(b, 0.36, 0.5, K.mat(Color("5c3a21")), Vector3(sx * (size.x * 0.5 + 0.1), -h + 0.5, sz * size.z * 0.3), Vector3(0, 0, 90))
	var hay := K.tex_mat("straw_thatch", Color(1.15, 1.02, 0.78), 0.55)
	K.sphere(b, size.x * 0.62, hay, Vector3(0, -0.45, 0), Vector3(1.0, (h - 1.2) / (size.x * 1.24) + 0.25, size.z / size.x))
	K.rbox(b, Vector3(size.x * 0.95, 0.3, size.z * 0.9), hay, Vector3(0, -0.15, 0), Vector3.ZERO, 0.14)
	K.cyl(b, 0.06, 0.06, 2.4, wood, Vector3(0, -h + 0.7, size.z * 0.5 + 1.0), Vector3(-75, 0, 0), 8)


func _wedge(id: String, a: Vector3, c: Vector3, width: float) -> void:
	var b := K.body(self, id)
	var d := c - a
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 0.6, d.length())
	cs.shape = bs
	cs.transform = Transform3D(basis, (a + c) * 0.5 - basis.y * 0.3)
	b.add_child(cs)
	var mi := K.rbox(b, Vector3(width, 0.6, d.length()), K.tex_mat("dirt_path", Color(1.0, 0.92, 0.8), 0.4), Vector3.ZERO, Vector3.ZERO, 0.2)
	mi.transform = Transform3D(basis, (a + c) * 0.5 - basis.y * 0.3)


func _ramp(id: String, top: Vector3, size: Vector3) -> void:
	# Mill stair: from (52, 12, -39) up west to (43, 17, -39); stepped treads with a sloped collision.
	var a := Vector3(top.x + size.x * 0.5, 12.0, top.z)
	var c := Vector3(top.x - size.x * 0.5, 17.0, top.z)
	var b := K.body(self, id)
	var d := c - a
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.z, 0.4, d.length())
	cs.shape = bs
	cs.transform = Transform3D(basis, (a + c) * 0.5 - basis.y * 0.2)
	b.add_child(cs)
	var wood := K.tex_mat("wood_planks", Color(1.0, 0.85, 0.66), 0.7)
	var steps := 14
	for i in steps:
		var t := (i + 0.5) / steps
		var p := a.lerp(c, t)
		K.rbox(b, Vector3(d.length() / steps + 0.05, 0.16, size.z), wood, p + Vector3(0, -0.02, 0), Vector3.ZERO, 0.04)
	for i in 5:
		var t2 := i / 4.0
		var p2 := a.lerp(c, t2)
		var post_h := p2.y - gy(p2.x, p2.z) + 1.0
		for sz in [-1.0, 1.0]:
			K.cyl(b, 0.08, 0.1, post_h, K.mat(Color("6e4a2c")), Vector3(p2.x, p2.y + 1.0 - post_h * 0.5, p2.z + sz * size.z * 0.5))
	for sz in [-1.0, 1.0]:
		var rail := K.rbox(b, Vector3(0.1, 0.1, d.length()), K.mat(Color("8a5a3b")), Vector3.ZERO, Vector3.ZERO, 0.04)
		rail.transform = Transform3D(basis, (a + c) * 0.5 + Vector3(0, 0.95, sz * size.z * 0.5))
		var wall := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = Vector3(0.1, 1.1, d.length())
		wall.shape = ws
		wall.transform = Transform3D(basis, (a + c) * 0.5 + Vector3(0, 0.5, sz * size.z * 0.5))
		b.add_child(wall)


# ------------------------------------------------------------------ rope bridge

func _rope_bridge() -> void:
	var rb: Dictionary = lv["splines"]["rope_bridge"]
	var s := v3(rb["start"])
	var e := v3(rb["end"])
	var width: float = float(rb.get("width", 1.6))
	var sag: float = float(rb.get("sag", 1.2))
	var gap: Array = rb.get("gap_t", [0.45, 0.51])
	var root := Node3D.new()
	root.name = "RopeBridge"
	add_child(root)
	var b := K.body(root, "Planks")
	var plank := K.tex_mat("wood_planks", Color(1.0, 0.84, 0.64), 0.9)
	var rope := K.mat(Color("d8c08a"), 0.85)
	var n := 46
	var length := s.distance_to(e)
	var pl := length / n
	var prev := Vector3.ZERO
	var rail_pts: Array[Vector3] = []
	for i in n:
		var t := (i + 0.5) / n
		var p := Vector3(lerpf(s.x, e.x, t), lerpf(s.y, e.y, t) - sag * sin(PI * t), lerpf(s.z, e.z, t))
		rail_pts.append(p)
		if t > float(gap[0]) and t < float(gap[1]):
			continue
		var t2 := t + 0.5 / n
		var t1 := t - 0.5 / n
		var p1 := Vector3(lerpf(s.x, e.x, t1), lerpf(s.y, e.y, t1) - sag * sin(PI * t1), 0)
		var p2 := Vector3(lerpf(s.x, e.x, t2), lerpf(s.y, e.y, t2) - sag * sin(PI * t2), 0)
		var ang := rad_to_deg(atan2(p2.y - p1.y, p2.x - p1.x))
		var cs := K.shape_box(b, Vector3(pl + 0.02, 0.2, width), p - Vector3(0, 0.1, 0), Vector3(0, 0, ang))
		cs.name = "P%d" % i
		var w := 0.95 if i % 3 else 1.0
		K.rbox(b, Vector3(pl * 0.82, 0.12, width * w), plank, p - Vector3(0, 0.06, 0), Vector3(0, float((i * 37) % 7) - 3.0, ang), 0.03)
	# Rope rails (visual) and invisible rail walls on both sides, posts at the ends.
	for side in [-1.0, 1.0]:
		var wall := K.body(root, "Rail%d" % int(side))
		# Fix round 2 (feel r1: the orbit still dropped to 1.3 m on the bridge): the rail walls block Mak, not the camera.
		wall.collision_layer = SOLID_NO_CAM
		for i in range(0, n, 2):
			var p := rail_pts[i]
			var q := rail_pts[mini(i + 2, n - 1)]
			var mid := (p + q) * 0.5
			var ang2 := rad_to_deg(atan2(q.y - p.y, q.x - p.x))
			K.shape_box(wall, Vector3(p.distance_to(q) + 0.05, 1.3, 0.12), mid + Vector3(0, 0.55, side * (width * 0.5 + 0.08)), Vector3(0, 0, ang2))
			var rope_len := p.distance_to(q)
			K.cyl(root, 0.045, 0.045, rope_len + 0.05, rope, mid + Vector3(0, 0.95, side * (width * 0.5 + 0.08)), Vector3(0, 0, ang2 - 90.0), 6)
			K.cyl(root, 0.035, 0.035, 0.95, rope, p + Vector3(0, 0.45, side * (width * 0.5 + 0.08)), Vector3.ZERO, 5)
		for endp: Vector3 in [s, e]:
			var post_h := endp.y - gy(endp.x, endp.z) + 1.6
			if endp.x < -30.0:
				post_h = 2.0
			K.cyl(root, 0.14, 0.16, post_h, K.tex_mat("bark", Color(0.9, 0.75, 0.6), 0.6), endp + Vector3(0, 1.4 - post_h * 0.5, side * (width * 0.5 + 0.12)), Vector3.ZERO, 10)
	# A small landing platform on the Brick Hill end.
	K.platform(root, "BridgeLanding", Vector3(e.x + 1.3, e.y, e.z), Vector3(2.8, 0.4, 2.6), 0.0, plank, 0.06)
	_treehouse_gate(root, s, e, sag, rope)


## Fix round 1 (QA r1 blocker): the rope bridge from Hill Lane reached the treehouse deck and W1-3 without a single
## scaffold step. Until W1-3 is owned, Hazel's lashed stick gate closes the treehouse end (3.2 m: no jump clears it),
## with 3.2 m rail walls for the last 4 m and short wings so nobody hops round it. It falls apart when W1-3 is won.
func _treehouse_gate(root: Node3D, s: Vector3, e: Vector3, sag: float, rope: Material) -> void:
	var game := get_node_or_null("/root/Game")
	if game and bool(game.call("has_truffle", "W1-3")):
		return
	var tg := 0.05
	var gp := Vector3(lerpf(s.x, e.x, tg), lerpf(s.y, e.y, tg) - sag * sin(PI * tg), s.z)
	var gate := K.body(root, "TreehouseGate", gp)
	K.shape_box(gate, Vector3(0.3, 3.2, 1.9), Vector3(0, 1.6, 0))
	for side in [-1.0, 1.0]:
		K.shape_box(gate, Vector3(0.3, 3.2, 1.3), Vector3(0, 1.6, side * 1.6))
		var rail_len := 4.0
		K.shape_box(gate, Vector3(rail_len, 3.4, 0.12), Vector3(rail_len * 0.5 - (gp.x - s.x) - 0.2, 1.4, side * 0.88))
	var v := Node3D.new()
	v.name = "Visual"
	gate.add_child(v)
	var stick := K.tex_mat("bark", Color(0.92, 0.72, 0.52), 0.7)
	for k in 7:
		var z := -0.85 + k * (1.7 / 6.0)
		var h := 2.6 + 0.35 * float((k * 5) % 3)
		K.cyl(v, 0.06, 0.08, h, stick, Vector3(0, h * 0.5, z), Vector3(float((k * 7) % 5) - 2.0, 0, 0), 6)
		K.cone(v, 0.07, 0.18, stick, Vector3(0, h + 0.09, z), Vector3.ZERO, 6)
	for y in [0.7, 1.9]:
		K.cyl(v, 0.05, 0.05, 2.1, stick, Vector3(0.08, y, 0), Vector3(90, 0, 4.0 if y < 1.0 else -6.0), 6)
		for z in [-0.6, 0.0, 0.6]:
			K.torus(v, 0.05, 0.1, rope, Vector3(0.08, y, z), Vector3(0, 0, 90))
	var lbl := Label3D.new()
	lbl.text = "HAZEL'S DECK
Scaffold only.
Yes, YOU."
	lbl.font_size = 34
	lbl.pixel_size = 0.005
	lbl.modulate = Color("3b2416")
	lbl.outline_size = 0
	lbl.position = Vector3(0.22, 1.35, 0)
	lbl.rotation_degrees.y = 90.0
	v.add_child(lbl)
	K.rbox(v, Vector3(0.04, 0.6, 1.0), K.tex_mat("wood_planks", Color(1.0, 0.9, 0.72), 0.8), Vector3(0.18, 1.35, 0), Vector3.ZERO, 0.02)
	if game and game.has_signal("truffle_collected"):
		var open_gate := func(id: String) -> void:
			if id != "W1-3" or not is_instance_valid(gate):
				return
			for c in gate.get_children():
				if c is CollisionShape3D:
					(c as CollisionShape3D).set_deferred("disabled", true)
			var tw := v.create_tween()
			tw.tween_property(v, "rotation_degrees:z", -88.0, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.tween_interval(1.5)
			tw.tween_property(v, "scale", Vector3(1, 0.01, 1), 0.4)
			tw.tween_callback(gate.queue_free)
		game.connect("truffle_collected", open_gate)
		if OS.has_feature("web"):
			# This lambda captures the two gate nodes, not this level. Disconnect
			# it before those nodes leave; a later world's pickup otherwise calls
			# a surviving lambda with freed captures. Native behavior is retained.
			gate.tree_exiting.connect(game.disconnect.bind("truffle_collected", open_gate), CONNECT_ONE_SHOT)


# ------------------------------------------------------------------ Stick Scaffold (W1-3)

func _scaffold() -> void:
	var root := Node3D.new()
	root.name = "StickScaffold"
	add_child(root)
	var sticks := K.tex_mat("bark", Color(0.92, 0.72, 0.52), 0.7)
	var plank := K.tex_mat("wood_planks", Color(0.98, 0.8, 0.58), 0.7)
	var twine := K.mat(Color("d8c08a"), 0.85)
	if plat.has("scaffold_pole"):
		_scaffold_pole(root, plat["scaffold_pole"], sticks, twine)
	for i in range(1, 10):
		var id := "scaffold_sc%d" % i
		if not plat.has(id):
			continue
		var p: Dictionary = plat[id]
		var top := v3(p["top"])
		var size := v3(p["size"])
		var gh := gy(top.x, top.z)
		if String(p["type"]) == "crumbling_sticks":
			var fp := obj("FallingPlatform", top, {"size": size, "theme": PlatformLook.Kind.WOOD, "wobble_time": 1.8, "fall_distance": 6.0, "respawn_time": 4.0}, 0.0, root)
			if fp:
				fp.name = id
			continue
		if String(p["type"]) == "rocking_sticks":
			var rock := AnimatableBody3D.new()
			rock.name = id
			rock.sync_to_physics = true
			rock.position = top
			rock.set_script(load("res://scripts/worlds/w1_rocker.gd"))
			root.add_child(rock)
			K.shape_box(rock, size, Vector3(0, -size.y * 0.5, 0))
			K.rbox(rock, size, plank, Vector3(0, -size.y * 0.5, 0), Vector3.ZERO, 0.06)
			for k in 3:
				K.cyl(rock, 0.06, 0.06, size.z + 0.1, sticks, Vector3(-1.0 + k, 0.02, 0), Vector3(90, 0, 0), 6)
			# Fulcrum post under the middle, visibly a see-saw.
			var post_h := top.y - size.y - gh
			K.cyl(root, 0.16, 0.2, post_h, sticks, Vector3(top.x, gh + post_h * 0.5, top.z), Vector3.ZERO, 8)
			K.sphere(root, 0.22, twine, Vector3(top.x, top.y - size.y - 0.1, top.z))
			continue
		var b := K.platform(root, id, top, size, 0.0, plank, 0.05)
		# Lashed stick legs (X-legs or a tripod) down to the grove floor; the higher ones lean on birches.
		var leg_h := top.y - size.y - gh
		if leg_h > 0.05:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var lp := Vector3(sx * (size.x * 0.5 - 0.15), -size.y - leg_h * 0.5, sz * (size.z * 0.5 - 0.15))
					K.cyl(b, 0.07, 0.09, leg_h + 0.2, sticks, lp, Vector3(sz * 3.0, 0, -sx * 3.0), 6)
			# Cross braces.
			for k in int(leg_h / 2.0):
				K.cyl(b, 0.04, 0.04, size.x * 1.15, sticks, Vector3(0, -size.y - 0.8 - k * 2.0, size.z * 0.5 - 0.15), Vector3(0, 0, 90 + 30 * (1 if k % 2 else -1)), 5)
		K.torus(b, 0.07, 0.13, twine, Vector3(size.x * 0.5 - 0.15, -size.y - 0.1, size.z * 0.5 - 0.15))
		if i == 9:
			# Crow's-nest basket rim.
			K.torus(b, size.x * 0.48, size.x * 0.56, K.tex_mat("straw_thatch", Color(0.9, 0.75, 0.55), 0.9), Vector3(0, 0.05, 0), Vector3.ZERO)


func _scaffold_pole(root: Node3D, pd: Dictionary, sticks: Material, twine: Material) -> void:
	var top := v3(pd["top"])
	var aim := v3(pd["aim"])
	var base_y := gy(top.x, top.z)
	var h := top.y - base_y
	var pole := K.body(root, "ScaffoldPole", Vector3(top.x, base_y, top.z))
	K.shape_cyl(pole, 0.2, h, Vector3(0, h * 0.5, 0))
	pole.add_to_group("no_ledge_grab")
	var bark := K.tex_mat("bark", Color(0.95, 0.92, 0.86), 0.5)
	var grease := K.mat(Color("6b5536"), 0.12, 0.35)
	var grease_h := 9.0 - base_y
	K.cyl(pole, 0.22, 0.24, grease_h, grease, Vector3(0, grease_h * 0.5, 0), Vector3.ZERO, 12)
	K.cyl(pole, 0.21, 0.21, h - grease_h, bark, Vector3(0, grease_h + (h - grease_h) * 0.5, 0), Vector3.ZERO, 12)
	for k in 4:
		K.torus(pole, 0.2, 0.27, twine, Vector3(0, grease_h + 0.3 + k * 0.5, 0))
	# "NO PIGS" wolf stencil on the greased part, facing the scaffold's start.
	var lbl := Label3D.new()
	lbl.text = "NO PIGS"
	lbl.font_size = 40
	lbl.pixel_size = 0.006
	lbl.modulate = Color("f6ecd6")
	lbl.outline_size = 6
	lbl.outline_modulate = Color("3b2416")
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.position = Vector3(0, 2.2, 0)
	pole.add_child(lbl)
	# Red pennant on top pointing at sc7.
	var d := Vector3(aim.x - top.x, 0, aim.z - top.z).normalized()
	var pen := Node3D.new()
	pole.add_child(pen)
	pen.position = Vector3(0, h + 0.35, 0)
	pen.rotation.y = atan2(d.x, d.z)
	K.cyl(pen, 0.03, 0.03, 0.8, K.mat(Color("5c3a21")), Vector3(0, 0.0, 0), Vector3.ZERO, 6)
	K.cone(pen, 0.2, 0.7, K.mat(Color("c8302e"), 0.7), Vector3(0, 0.25, 0.35), Vector3(90, 0, 0), 4)
	var cl := obj("Climbable", Vector3(top.x, 9.0, top.z), {"look": Climbable.Look.POLE, "height": 2.0, "pole_radius": 0.15, "grab_radius": 0.65}, 0.0, root)
	if cl:
		cl.name = "ScaffoldPoleClimb"
		var vis := cl.get_node_or_null("Visual") as Node3D
		if vis:
			vis.visible = false
	# A32: six acorns orbiting the climbable top (collecting them is the orbit).
	var ring := obj("AcornGroup", Vector3(top.x, 10.6, top.z), {"shape": AcornGroup.Shape.RING, "count": 6, "radius": 0.9}, 0.0, root)
	if ring:
		ring.name = "A32"


# ------------------------------------------------------------------ windmill sail ride (W1-2)

func _windmill_ride() -> void:
	var hub := Vector3(40, 25.5, -41.6)
	var rp := obj("RotatingPlatform", hub, {
		"axis": RotatingPlatform.Axis.VERTICAL_PLANE,
		"arm_count": 4,
		"radius": 8.0,
		"degrees_per_second": -360.0 / 14.0,
		"keep_level": true,
		"platform_size": Vector3(2.0, 0.3, 1.6),
		"show_sails": false,
	})
	if rp:
		rp.name = "SailSteps"
		sail_rotor = rp
	# Generated sail blades turning with the steps (radius 7.4 m in the GLB -> 9 m).
	var sails := glb("res://assets/props/w1/windmill_sails/windmill_sails.glb")
	if sails:
		sail_visual = Node3D.new()
		sail_visual.name = "SailBlades"
		sail_visual.position = Vector3(40, 25.5, -42.9)
		add_child(sail_visual)
		var inst := sails.instantiate() as Node3D
		inst.scale = Vector3.ONE * 1.21
		sail_visual.add_child(inst)
		# Fix round 2 (visual r1: a bare ladder lattice, the rotation read weakly): cream sail cloth with a slight belly
		# on two opposite blades (the GLB's blades lie along its local X and Y axes), as in key art 05.
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = Color("efe9dc")
		cloth.roughness = 0.9
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloth.rim_enabled = true
		cloth.rim = 0.25
		var cm := _sail_cloth_mesh(1.45 * 1.21, (7.0 - 1.7) * 1.21, 0.28)
		for sgn in [1.0, -1.0]:
			var ci := MeshInstance3D.new()
			ci.name = "SailCloth"
			ci.mesh = cm
			ci.material_override = cloth
			sail_visual.add_child(ci)
			ci.position = Vector3(0, sgn * (1.7 + (7.0 - 1.7) * 0.5) * 1.21, 0.62 * 1.21)
			ci.rotation.z = 0.0 if sgn > 0.0 else PI
	# Weathervane deck on the cap, the truffle's perch.
	var wood := K.tex_mat("wood_planks", Color(1.0, 0.86, 0.66), 0.7)
	# Builder amendment: radius 2.0 (plan 1.4) centred 0.8 m toward the sails, so the crest jump is a 0.8 m gap.
	var deck_y := shell_y("mill", 40.0, -46.0, 28.0)
	deck_y = maxf(deck_y, 27.6) + 0.15
	var deck := K.body(self, "WeathervaneDeck", Vector3(40, deck_y, -45.2))
	K.shape_cyl(deck, 2.0, 0.3, Vector3(0, -0.15, 0))
	K.cyl(deck, 2.0, 2.05, 0.3, wood, Vector3(0, -0.15, 0), Vector3.ZERO, 24)
	K.torus(deck, 1.92, 2.1, K.mat(Color("5c3a21")), Vector3(0, 0.02, 0))
	for i in 6:
		var a := TAU * i / 6.0
		K.cyl(deck, 0.07, 0.07, 1.6, K.mat(Color("5c3a21")), Vector3(cos(a) * 1.6, -0.9, sin(a) * 1.6), Vector3(sin(a) * 20.0, 0, -cos(a) * 20.0), 6)
	var iron := K.mat(Color("3b3b44"), 0.4)
	K.cyl(deck, 0.05, 0.05, 2.2, iron, Vector3(-0.9, 1.1, 0.6), Vector3.ZERO, 6)
	K.rbox(deck, Vector3(0.8, 0.55, 0.08), iron, Vector3(-0.9, 2.2, 0.6))
	K.cone(deck, 0.12, 0.3, K.mat(Color("c8302e")), Vector3(-0.55, 2.35, 0.6), Vector3(0, 0, -90))
	plat["mill_weathervane_deck"]["top"] = [40.0, deck_y, -45.2]


# ------------------------------------------------------------------ bellows (W1-4)

var bellows_nodes: Dictionary = {}
var gust_zones: Dictionary = {}


func _bellows() -> void:
	var gusts: Dictionary = {}
	for h in lv.get("hazards", []):
		if String(h.get("type", "")) == "gust_zone":
			gusts[String(h["source"])] = h
	var bset := obj("BellowsSet", Vector3(2, 0.4, -3), {"group_id": "w1_bellows", "reward_truffle_id": "W1-4", "show_ghost_if_owned": true})
	if bset:
		bset.name = "BellowsSet_W1-4"
		var m := bset.get_node_or_null("TruffleMarker") as Node3D
		if m:
			m.position = Vector3(0, 12.5 - 0.9 - 0.4, 0)  # R2.4: truffle floats at (2, 12.5, -3) on the spout
		bset.connect("progress", _on_bellows_progress)
	# Fix round 2 (visual r1): v4 fixes the blank -X emblem and the notched nozzle (same size, origin and sockets).
	var bel_glb := glb("res://assets/props/w1/bellows_machine_v4/bellows_machine_v4.glb")
	if bel_glb == null:
		bel_glb = glb("res://assets/props/w1/bellows_machine_v3/bellows_machine_v3.glb")
	for land in lv.get("landmarks", []):
		var lid: String = land["id"]
		if not lid.begins_with("bellows_"):
			continue
		var pos := v3(land["pos"])
		var yaw: float = float(land.get("yaw_deg", 0.0))
		var g: Dictionary = gusts.get(lid, {})
		var zone: Node3D = null
		if not g.is_empty():
			var a := v3(g["from"])
			var c := v3(g["to"])
			var d := c - a
			# Fix round 2 (feel r1): B1's box topped out at y 3.8 and shoved Mak off bale tier 1 (top 3.7); it now tops at 3.4.
			var zh := float(g["height"]) + 0.6
			var zc := (a + c) * 0.5 + Vector3(0, 0.2, 0)
			if lid == "bellows_B1":
				zh = 3.0
				zc.y = 1.9
			var zprops := {
				"size": Vector3(float(g["width"]), zh, d.length()),
				"direction": Vector3(0, 0, -1),
				# Fix round 1 (fun critic r1: B3's swivelling gust tripled the Saddle Lane time): B3's mouth speed is capped.
				"strength": minf(float(g["wind_mps_at_mouth"]), 5.0) if lid == "bellows_B3" else float(g["wind_mps_at_mouth"]),
				"mode": WindZone.Mode.STEADY,
				"end_falloff": 0.6,
				"streak_color": Color(1.0, 0.95, 0.75, 0.6),
			}
			if lid == "bellows_B1":
				# Completion pass: G_B1 runs from the nozzle (x -11.2) through the straw house to x -25.2. At 8 m/s
				# (x0.5 on the ground) it pinned a grounded Mak against the east wall (x -16.4): he could not walk
				# north, south or out (W1-1 bot stuck 3 min at (-16.0, 24.0) after the WW4 fight). The last metre
				# before the wall and the house itself are calm now; the lane from the nozzle to x -15.4 still blows.
				# Local space: z = world x + 18.2 (the lane centre), x = 26 - world z.
				zprops["calm_boxes"] = [AABB(Vector3(-2.6, -2.0, -7.1), Vector3(5.2, 4.0, 9.9))] as Array[AABB]
			if lid == "bellows_B3":
				# Fix round 2 (feel r1): B3's swivelling gust leaked through the chimney wall and shoved Mak round the flue
				# floor. The W1 subclass never blows inside the flue and soot-door volumes (the cutaway boxes).
				zone = GUST.new()
				zone.add_child(Node3D.new())
				for k in zprops:
					zone.set(k, zprops[k])
				zone.set("exclude_aabbs", [AABB(Vector3(9.6, 11.6, -37.6), Vector3(3.6, 17.0, 3.3)), AABB(Vector3(12.9, 11.6, -37.0), Vector3(1.8, 2.8, 2.0))] as Array[AABB])
				zone.position = zc
				add_child(zone)
			else:
				zone = obj("WindZone", zc, zprops)
			if zone:
				zone.name = "Gust_" + lid
				zone.basis = Basis.looking_at(d.normalized(), Vector3.UP)
		var props := {"group_id": "w1_bellows", "pump_period": 4.0}
		if bel_glb:
			props["visual_scene"] = bel_glb
			props["visual_scale"] = 0.75
			props["visual_flip_180"] = true
		if zone:
			props["wind_zone_path"] = NodePath("../" + String(zone.name))
		var bel := obj("BellowsMachine", pos, props, yaw)
		if bel:
			bel.name = "Bellows_" + lid
			bellows_nodes[lid] = bel
			if zone:
				gust_zones[lid] = zone
				if life:
					life.call("add_plate", lid, bel, zone)
			if lid == "bellows_B3":
				_b3 = bel
				_b3_base = bel.basis
				_b3_zone = zone
				if zone:
					_b3_zone_rel = Transform3D(Basis(), pos).affine_inverse() * zone.global_transform
			# Collision that matches the generated cart (top of the pump plate about 2.4 m up).
			K.shape_box(bel as CollisionObject3D, Vector3(2.2, 2.35, 2.8), Vector3(0, 1.175, 0.1))
		# Iron-banded step crate behind the machine.
		var cid := lid + "_crate"
		if plat.has(cid):
			var cp: Dictionary = plat[cid]
			var ctop := v3(cp["top"])
			var cb := K.body(self, cid, ctop, yaw)
			var csz := v3(cp["size"])
			K.shape_box(cb, csz, Vector3(0, -csz.y * 0.5, 0))
			var crate := glb("res://assets/props/pickups/breakable_crate/breakable_crate.glb")
			if crate:
				var ci := crate.instantiate() as Node3D
				ci.scale = csz
				ci.position = Vector3(0, -csz.y, 0)
				cb.add_child(ci)
			for hy in [0.25, 0.8]:
				K.rbox(cb, Vector3(csz.x + 0.06, 0.1, csz.z + 0.06), K.mat(Color("3b3b44"), 0.4), Vector3(0, -csz.y * hy, 0), Vector3.ZERO, 0.03)
		# A painted warning sign pointing at the machine.
		D.wolf_sign(self, pos + Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)) * Vector3(1.8, 0, 1.6), yaw)


func _on_bellows_progress(n_broken: int, total: int) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		if n_broken < total:
			ui.call("toast", "Bellows busted: %d of %d" % [n_broken, total])
		else:
			ui.call("toast", "All bellows busted! Something stirs in the village well...")


# ------------------------------------------------------------------ missions

func _missions() -> void:
	var tr: Dictionary = {}
	for t in lv.get("truffles", []):
		tr[String(t["id"])] = t
	# W1-2 Top of the Windmill: always live on the weathervane deck.
	var deck_top := v3(plat["mill_weathervane_deck"]["top"])
	_truffle("W1-2", Vector3(40, deck_top.y, -45.4), "Top of the Windmill")
	# W1-3 The Stick Scaffold: by the treehouse hut door.
	# Builder: the amendment spot (-44.5, -29.0) is the P3 backflip take-off by the door, so the truffle sits on the
	# deck's south-west quarter, in view as you step off the scaffold.
	# Fix round 2 (QA r1: a long or triple jump round Hazel's gate to the deck's free corner was plausible): the truffle
	# only appears once Mak stands on the top of the scaffold (sc8 or sc9), so no route round the gate can take it.
	var sc_spawner := Node3D.new()
	sc_spawner.set_script(load("res://scripts/objects/truffle_spawner.gd"))
	sc_spawner.name = "ScaffoldReward_W1-3"
	sc_spawner.set("reward_truffle_id", "W1-3")
	sc_spawner.set("show_ghost_if_owned", true)
	sc_spawner.position = Vector3(-46.2, 16.0, -31.4)
	add_child(sc_spawner)
	for sid in ["scaffold_sc8", "scaffold_sc9"]:
		if not plat.has(sid):
			continue
		var stop := v3(plat[sid]["top"])
		var ssz := v3(plat[sid]["size"])
		var trig := Area3D.new()
		trig.name = "ScaffoldTop_" + sid
		trig.collision_layer = 128
		trig.collision_mask = 2
		trig.monitorable = false
		add_child(trig)
		trig.global_position = stop + Vector3(0, 0.6, 0)
		K.shape_box(trig, Vector3(ssz.x + 0.2, 1.2, ssz.z + 0.2))
		trig.body_entered.connect(func(b: Node) -> void:
			if b.is_in_group("player") and sc_spawner.has_method("give_reward"):
				sc_spawner.call("give_reward"))
	# W1-6 Up the Chimney: floating in the crown opening.
	_truffle("W1-6", Vector3(11.3, 12.0 + CHIMNEY_H - 0.4, -36.0), "Up the Chimney")
	# W1-1 Straw House Siege: appears at Pip's doorstep when the four Woolly Wolves are beaten.
	siege_spawner = Node3D.new()
	siege_spawner.set_script(load("res://scripts/objects/truffle_spawner.gd"))
	siege_spawner.name = "SiegeReward_W1-1"
	siege_spawner.set("reward_truffle_id", "W1-1")
	siege_spawner.set("show_ghost_if_owned", true)
	siege_spawner.position = Vector3(-20, gy(-20, 31.5) + 0.05, 31.5)
	add_child(siege_spawner)
	# Cousin Pip at the door.
	pip = _npc("Pip", "Cousin Pip", Vector3(-19.0, 0, 30.6), 180.0, 1.0, "", [
		"Cousin Mak! Thank goodness! Some of those sheep are not sheep. Real sheep don't have grey tails!",
		"Four of them are skulking round my house, one's hiding in the hay. Give 'em a sniff, or a puff from the bellows!",
	])
	_sheep()
	# Cousins Hazel (stick house) and Bertram (brick house), R1.3. Same piglet base model until their own meshes land.
	_npc("Hazel", "Cousin Hazel", Vector3(-36.0, 0, -11.5), 150.0, 1.0, "bandana", [
		"They pinched my ladder! The scaffold's all that's left.",
		"Do NOT stand still on the top bits. They're only tied with hope.",
	])
	_npc("Bertram", "Cousin Bertram", Vector3(14.6, 0, -33.6), -120.0, 1.08, "cap", [
		"Nobody's ever gone UP a chimney, old bean. Wolves only come down.",
		"The Foreman's hiding in the hay by the camp, old bean. Bring your nose.",
	])
	# W1-5 Lost Pages: truffle appears on the Ford Rock.
	var ford := v3(plat["ford_rock"]["top"])
	var lps := obj("LostPageSet", ford, {"world_id": "W1", "required": 5, "reward_truffle_id": "W1-5", "show_ghost_if_owned": true})
	if lps:
		lps.name = "LostPageSet_W1-5"
		var m := lps.get_node_or_null("TruffleMarker") as Node3D
		if m == null:
			m = Marker3D.new()
			m.name = "TruffleMarker"
			lps.add_child(m)
		m.position = Vector3.ZERO
	# W1-7 The Foreman's Charge (R1.9) is built with the enemies (FM1).
	# W1-8 Buried Treasure (R2.3): a three-dig map hunt, willow mud -> gravel bar -> bare ring in the orchard.
	_treasure_hunt()
	# Bonus W1-100: the hundred-acorn truffle pops out above Mak.
	acorn_hundred = obj("AcornHundred", Vector3(0, 1, 50), {"required": 100, "reward_truffle_id": "W1-100", "show_ghost_if_owned": false})
	if acorn_hundred:
		acorn_hundred.name = "AcornHundred_W1-100"
		acorn_hundred.connect("progress", _on_acorn_progress)


func _npc(node_name: String, speaker: String, at: Vector3, yaw: float, scl: float, accessory: String, lines: Array) -> Node3D:
	var pip_glb := glb("res://assets/characters/pip/pip.glb")
	# Own generated models for the cousins (meshes top-up); the Pip base plus an accessory is only the fallback.
	var own := glb("res://assets/characters/%s/%s.glb" % [node_name.to_lower(), node_name.to_lower()])
	if own and node_name != "Pip":
		pip_glb = own
		accessory = ""
		scl = 1.0
	# Builder 07:08: Pip uses the rigged pip_v2 at the amendment height (0.95 m; pip.glb is 0.70 m), per its README.
	if node_name == "Pip":
		var pv2 := glb("res://assets/characters/pip_v2/pip_v2.glb")
		if pv2:
			pip_glb = pv2
			scl = 1.0
	var pl := PackedStringArray()
	for l in lines:
		pl.append(String(l))
	at.y = gy(at.x, at.z)
	var n := obj("NPCTalker", at, {"speaker": speaker, "lines": pl, "visual_scene": pip_glb, "visual_scale": scl, "talk_radius": 3.0}, yaw)
	if n == null:
		return null
	n.name = node_name
	var vis := n.get_node_or_null("Visual") as Node3D
	if vis and accessory != "":
		var head_y := 0.62 * scl
		if accessory == "bandana":
			K.torus(vis, 0.2, 0.27, K.mat(Color("4f9a37"), 0.7), Vector3(0, head_y, 0), Vector3(8, 0, 0))
			K.rbox(vis, Vector3(0.12, 0.2, 0.04), K.mat(Color("4f9a37"), 0.7), Vector3(0, head_y - 0.08, 0.26), Vector3(0, 0, 20), 0.02)
			K.cyl(vis, 0.12, 0.1, 0.22, K.tex_mat("bark", Color.WHITE, 0.8), Vector3(0.24, 0.32, 0.0), Vector3(0, 0, 10), 8)
		elif accessory == "cap":
			K.cyl(vis, 0.24, 0.26, 0.1, K.mat(Color("6b5a3e"), 0.85), Vector3(0, head_y + 0.06, 0), Vector3.ZERO, 16)
			K.rbox(vis, Vector3(0.28, 0.04, 0.16), K.mat(Color("6b5a3e"), 0.85), Vector3(0, head_y + 0.03, -0.24), Vector3(-8, 0, 0), 0.02)
			K.rbox(vis, Vector3(0.05, 0.3, 0.07), K.mat(Color("b9b2a6"), 0.4), Vector3(0.26, 0.3, 0.0), Vector3(0, 0, -25), 0.02)
	return n


var digs: Array[Dictionary] = []
var dig_i := 0
var treasure_spawner: Node3D


func _treasure_hunt() -> void:
	var th: Dictionary = lv.get("treasure_hunt", {})
	var list: Array = th.get("digs", [])
	var game := get_node_or_null("/root/Game")
	treasure_spawner = Node3D.new()
	treasure_spawner.set_script(load("res://scripts/objects/truffle_spawner.gd"))
	treasure_spawner.name = "TreasureReward_W1-8"
	treasure_spawner.set("reward_truffle_id", "W1-8")
	treasure_spawner.set("show_ghost_if_owned", true)
	add_child(treasure_spawner)
	for i in list.size():
		var d: Dictionary = list[i]
		var p := v3(d["pos"])
		var ground := p.y if p.y < 0.0 else gy(p.x, p.z)
		p.y = ground
		var root := Node3D.new()
		root.name = "Dig%d_W1-8" % (i + 1)
		root.position = p
		add_child(root)
		var r: float = float(d.get("radius", 1.0))
		# Looks: a mud patch, a pale gravel bar spot, a bare brown ring in the grass.
		var col := Color("5a3b22") if i == 0 else (Color("b9b2a6") if i == 1 else Color("7a5634"))
		var disc := K.cyl(root, r, r, 0.04, K.mat(col, 0.95), Vector3(0, 0.02, 0), Vector3.ZERO, 20)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mound := K.sphere(root, 0.45, K.mat(Color("6b4a2c"), 0.95), Vector3(0, 0.0, 0), Vector3(1.4, 0.35, 1.4))
		mound.visible = false
		var sn := obj("SniffTarget", p, {"reveal_radius": 3.0, "scent_strength": 1.0, "active": false})
		if sn:
			sn.name = "Scent"
			sn.remove_from_group("sniff_target")
			sn.connect("sniffed", func(_by: Node) -> void: mound.visible = true)
		var sensor := SlamSensor.create(root, r + 0.2, 1.0, Vector3.ZERO)
		sensor.slammed.connect(_on_dig.bind(i))
		digs.append({"root": root, "sniff": sn, "mound": mound, "pos": p, "hint": String(d.get("hint", ""))})
	if i_owned("W1-8"):
		dig_i = digs.size()
	elif game and game.call("is_unlocked", "W1-8_dig2"):
		dig_i = 2
	elif game and game.call("is_unlocked", "W1-8_dig1"):
		dig_i = 1
	_activate_dig()


func i_owned(id: String) -> bool:
	var game := get_node_or_null("/root/Game")
	return game != null and bool(game.call("has_truffle", id))


func _activate_dig() -> void:
	for i in digs.size():
		var sn: Node = digs[i]["sniff"]
		if sn == null:
			continue
		var on := i == dig_i
		sn.set("active", on)
		if on and not sn.is_in_group("sniff_target"):
			sn.add_to_group("sniff_target")
		elif not on and sn.is_in_group("sniff_target"):
			sn.remove_from_group("sniff_target")


func _on_dig(_by: Node, i: int) -> void:
	if i != dig_i:
		return
	var d: Dictionary = digs[i]
	var at: Vector3 = d["pos"]
	(d["mound"] as Node3D).visible = true
	(d["mound"] as Node3D).scale = Vector3(1.8, 0.25, 1.8)
	ObjSvc.burst(self, at + Vector3(0, 0.3, 0), Color(0.4, 0.27, 0.15) if i != 1 else Color(0.75, 0.88, 1.0), 36, 7.0, 0.3, -14.0, 1.0)
	dig_i += 1
	_activate_dig()
	var game := get_node_or_null("/root/Game")
	var ui := get_node_or_null("/root/UI")
	if i < digs.size() - 1:
		if game:
			game.call("unlock", "W1-8_dig%d" % (i + 1))
		if ui and ui.has_method("show_dialog"):
			ui.call("show_dialog", "Map scrap %d of 3" % (i + 1), ["A scrap of a treasure map! It shows %s." % String(d["hint"]).trim_prefix("scrap %d: " % (i + 1))])
		elif ui and ui.has_method("toast"):
			ui.call("toast", "Map scrap %d of 3!" % (i + 1))
		return
	# Final dig: a treasure chest pops up and flips its lid; the truffle rises out of it.
	var chest := Node3D.new()
	chest.name = "TreasureChest"
	chest.position = at
	add_child(chest)
	var wood := K.tex_mat("wood_planks", Color(0.85, 0.6, 0.4), 0.9)
	var iron := K.mat(Color("c9a04a"), 0.35)
	K.rbox(chest, Vector3(1.0, 0.55, 0.7), wood, Vector3(0, 0.28, 0), Vector3.ZERO, 0.06)
	for x in [-0.35, 0.35]:
		K.rbox(chest, Vector3(0.08, 0.57, 0.72), iron, Vector3(x, 0.28, 0), Vector3.ZERO, 0.02)
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.55, -0.35)
	chest.add_child(lid)
	K.rbox(lid, Vector3(1.0, 0.22, 0.7), wood, Vector3(0, 0.1, 0.35), Vector3.ZERO, 0.08)
	chest.scale = Vector3.ONE * 0.05
	var tw := chest.create_tween()
	tw.tween_property(chest, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lid, "rotation_degrees:x", -110.0, 0.35).set_trans(Tween.TRANS_BACK)
	treasure_spawner.global_position = at + Vector3(0, 0.6, 0)
	tw.tween_callback(func() -> void: treasure_spawner.call("give_reward"))


## R1.3 real sheep (C05, generated model): W1-1 decoys among the Woolly Wolves and orchard grazers. They graze in
## small loops with a nod and a hop; the faint gag needs the enemies workstream's hurtbox (requested).
func _sheep() -> void:
	var g := glb("res://assets/characters/real_sheep/real_sheep.glb")
	if g == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for n in lv.get("npcs", []):
		var id := String(n["id"])
		if not id.begins_with("SH"):
			continue
		var p := v3(n["pos"])
		p.y = gy(p.x, p.z)
		var holder := Node3D.new()
		holder.name = id
		holder.position = p
		holder.rotation_degrees.y = float(n.get("yaw_deg", 0.0)) + 180.0
		add_child(holder)
		# Fix round 2: a react node between the grazing holder and the nodding body, for scatter hops and puff rolls.
		var react := Node3D.new()
		react.name = "React"
		holder.add_child(react)
		var body := Node3D.new()
		react.add_child(body)
		var inst := g.instantiate() as Node3D
		body.add_child(inst)
		# R3.10: oatmeal wool (#DCCBA6) so Mak stays the only near-white body in the meadow.
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			for si in m3.mesh.get_surface_count():
				var mat := m3.get_active_material(si)
				if mat is BaseMaterial3D:
					var dm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dm.albedo_color = Color(0.9, 0.84, 0.72)
					m3.set_surface_override_material(si, dm)
		var col := K.body(holder, "Body")
		K.shape_box(col, Vector3(0.7, 0.8, 1.0), Vector3(0, 0.4, 0))
		# Graze: slow wander around home, head-nod bobs, an occasional hop.
		var tw := holder.create_tween().set_loops()
		var home := p
		# LEGS pass (2026-10-19): turn toward each leg's own heading (it aimed from home, so later legs crab-walked
		# sideways) along the short way round, and face home before the walk back; NpcLife walks the legs.
		var from := home
		for k in 4:
			var tgt := home
			if k < 3:
				var a := rng.randf() * TAU
				tgt = home + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.6, 1.8)
				tgt.y = gy(tgt.x, tgt.z)
			var yaw := atan2(tgt.x - from.x, tgt.z - from.z)
			tw.tween_method(_sheep_turn.bind(holder, yaw), 0.0, 1.0, 0.6)
			tw.tween_property(holder, "position", tgt, rng.randf_range(2.5, 4.0) if k < 3 else 3.0)
			if k < 3:
				tw.tween_interval(rng.randf_range(1.5, 3.0))
			from = tgt
		var tw2 := body.create_tween().set_loops()
		tw2.tween_property(body, "rotation_degrees:x", 8.0, 0.5).set_delay(rng.randf_range(0.5, 2.0))
		tw2.tween_property(body, "rotation_degrees:x", 0.0, 0.5)
		tw2.tween_property(body, "position:y", 0.18, 0.15)
		tw2.tween_property(body, "position:y", 0.0, 0.2)
		if life:
			life.call("add_sheep", holder, react)


## Sheep graze turns: ease the holder's yaw toward `yaw` the short way round (k runs 0 -> 1 over the turn).
func _sheep_turn(k: float, holder: Node3D, yaw: float) -> void:
	if is_instance_valid(holder):
		holder.rotation.y = lerp_angle(holder.rotation.y, yaw, clampf(k * k * 1.5, 0.0, 1.0))


func _truffle(id: String, ground: Vector3, title: String) -> Node3D:
	var t := obj("Truffle", ground, {"truffle_id": id, "mission_title": title})
	if t:
		t.name = "Truffle_" + id
	return t


func _on_acorn_progress(count: int, required: int) -> void:
	if count < required or acorn_hundred == null:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		acorn_hundred.global_position = p.global_position + Vector3(0, 1.6, 0) - p.global_transform.basis.z * 1.5


func _relay() -> void:
	var straw_ridge := Vector3(-19.6, shell_y("straw", -19.6, 25.6, 6.3), 25.6)
	# The stick roof is too steep to stand on: the "bell" is a hoop hung over the woodpile at the porch gable.
	var stick_ridge := Vector3(-42, 5.6, -14.2)
	var brick_ridge := Vector3(4.6, 20.85, -36.0)
	var tt_ps := load(OBJ % "TimeTrial") as PackedScene
	if tt_ps == null:
		return
	var tt := tt_ps.instantiate() as Node3D
	tt.set("time_limit", 75.0)
	tt.set("ordered", true)
	tt.set("trial_label", "Rooftop Relay")
	tt.set("trial_key", "W1-7")
	tt.set("reward_truffle_id", "W1-7")
	tt.set("show_ghost_if_owned", true)
	tt.name = "RooftopRelay_W1-7"
	# TimeTrial reads StartGate/FinishGate/Rings in _ready, so its children are built before it enters the tree.
	for old in tt.get_children():
		if old.name in ["StartGate", "FinishGate", "Rings", "TruffleMarker"]:
			tt.remove_child(old)
			old.free()
	var sg := Node3D.new()
	sg.name = "StartGate"
	sg.position = straw_ridge
	sg.rotation_degrees.y = 90.0
	tt.add_child(sg)
	var fg := Node3D.new()
	fg.name = "FinishGate"
	fg.position = brick_ridge
	fg.rotation_degrees.y = 90.0
	tt.add_child(fg)
	var rings := Node3D.new()
	rings.name = "Rings"
	tt.add_child(rings)
	var ring_ps := load(OBJ % "TrialRing") as PackedScene
	if ring_ps:
		var r := ring_ps.instantiate() as Node3D
		r.name = "StickBell"
		r.set("radius", 1.4)
		r.position = stick_ridge + Vector3(0, 1.2, 0)
		r.rotation_degrees.y = 90.0
		rings.add_child(r)
	var m := Marker3D.new()
	m.name = "TruffleMarker"
	m.position = Vector3(1.0, 20.85, -36.0)
	tt.add_child(m)
	add_child(tt)
	D.relay_dressing(self, straw_ridge, stick_ridge, brick_ridge)


# ------------------------------------------------------------------ enemies

func _enemies() -> void:
	for e in lv.get("enemies", []):
		var id: String = e["id"]
		var fam: String = e["family"]
		var pos := v3(e["pos"])
		var patrol: Dictionary = e.get("patrol", {})
		if fam == "foreman":
			_hay_yard()
			continue
		if String(patrol.get("kind", "")) == "stuck_gag":
			_chimney_gag(pos)
			continue
		var scene := "WoollyWolf" if fam == "woolly_wolf" else "CrowBandit"
		var ps := load("res://scenes/enemies/%s.tscn" % scene) as PackedScene
		if ps == null:
			continue
		var n := ps.instantiate() as Node3D
		n.name = id
		if fam == "woolly_wolf":
			pos.y = gy(pos.x, pos.z) + 0.05
			n.set("notice_radius", float(e.get("notice_radius", 8.0)))
			var kind: String = patrol.get("kind", "graze")
			if kind == "line":
				var pts: Array[Vector3] = []
				for q in patrol.get("points", []):
					pts.append(Vector3(float(q[0]) - pos.x, 0, float(q[1]) - pos.z))
				n.set("patrol_points", pts)
				n.set("move_speed", float(patrol.get("speed", 1.2)))
			if id == "WW8":
				# Dozing camp guard (R1.12): a short notice radius stands in for the sneak rule.
				n.set("notice_radius", 3.0)
				n.set("patrol_points", [] as Array[Vector3])
				pos = Vector3(-29.0, gy(-29.0, -48.5) + 0.05, -48.5)
		else:
			n.set("notice_radius", 10.0)
		if id == "CB8" or id == "CB9":
			# R3.2 twine crows: perched on the knots of the two crumbling sticks of the builder's spiral.
			var st: Dictionary = plat.get("scaffold_sc%d" % (7 if id == "CB8" else 8), {})
			if not st.is_empty():
				var tp := v3(st["top"])
				pos = tp + Vector3(0.75, 0.35, 0.75)
		if id == "WW3" and life:
			# Fix round 2 (fun r1: "one hiding inside a haystack" was not true in game): WW3 waits inside a wiggling,
			# sneezing haystack at (-34, 32) and only enters the level, already unmasked, when it is burst open.
			var wps := ps
			var hp := Vector3(-34.0, gy(-34.0, 32.0), 32.0)
			n.free()
			life.call("add_hay_hide", hp, func(at: Vector3) -> void:
				var w := wps.instantiate() as Node3D
				w.name = "WW3"
				w.set("notice_radius", 12.0)
				w.position = at
				# Completion pass: WW3 appears 1.7 m toward Mak, inside the punch that burst the stack, and that same
				# punch beat him on his first frame (the twist never played). Hits clang for his first 0.7 s.
				var born := Time.get_ticks_msec()
				w.set_meta("hit_gate", func(_kind: String) -> bool: return Time.get_ticks_msec() - born > 700)
				add_child(w)
				if w.has_signal("defeated"):
					w.connect("defeated", _on_siege_wolf_defeated)
				if w.has_method("_rip_costume"):
					w.call_deferred("_rip_costume")
				_lod_nodes.append(w)
				_lod_radius.append(42.0))
			continue
		n.position = pos
		add_child(n)
		if fam == "woolly_wolf":
			get_tree().create_timer(0.5).timeout.connect(_oatmeal.bind(n))
			if id != "WW8":
				_sniff_reveal(n)
			if life:
				get_tree().create_timer(0.7).timeout.connect(func() -> void: life.call("add_tail", n))
		elif fam == "crow_bandit" and id != "CB8" and id != "CB9":
			# Fix round 2 (QA + visual r1: CB1 perched 0.84 m inside the straw roof, CB3 0.42 m inside the windmill shell):
			# every perch is re-seated on the surface under it once the colliders are in the physics space.
			_perch_fix.call_deferred(n)
		if id in SIEGE_IDS and n.has_signal("defeated"):
			n.connect("defeated", _on_siege_wolf_defeated)


func _perch_fix(n: Node3D) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(n):
		return
	var p := n.global_position
	var space := get_world_3d().direct_space_state
	var best := INF
	for up in [1.2, 2.6]:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, up, 0), p + Vector3(0, -2.5, 0), 1)
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var hy: float = (r["position"] as Vector3).y
		if hy - p.y > -1.0 and hy - p.y < 2.2 and absf(hy - p.y) < absf(best - p.y):
			best = hy
	if best == INF:
		return
	var np := Vector3(p.x, best + 0.08, p.z)
	n.global_position = np
	n.set("home", np)


## Fix round 1 (visual critic r1, R3.10): the disguised wolves' fleece was the brightest near-white in the meadow
## (Mak should be the only one) and gave the spot-the-wolf game away next to the oatmeal sheep. Re-tint the W1
## instances' disguise surfaces to oatmeal (#DCCBA6 on the white fleece).
var _oat_cache: Dictionary = {}


func _oatmeal(n: Node) -> void:
	if not is_instance_valid(n) or not bool(n.get("disguised")):
		return
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si) as StandardMaterial3D
			if src == null:
				continue
			var c: StandardMaterial3D = _oat_cache.get(src.get_instance_id())
			if c == null:
				c = src.duplicate() as StandardMaterial3D
				c.albedo_color = Color(0.87, 0.8, 0.66)
				_oat_cache[src.get_instance_id()] = c
			mi.set_surface_override_material(si, c)


## Fix round 1 (fun critic r1, R1.4): Snout Sniff unmasks a disguised wolf from up to 8 m with a green whiff, so
## spot-the-wolf has a nose-based answer and a reveal the player chooses (instead of a punch on a grazing "sheep").
func _sniff_reveal(w: Node3D) -> void:
	var ps := load(OBJ % "SniffTarget") as PackedScene
	if ps == null:
		return
	var st := ps.instantiate() as Node3D
	st.name = "WolfScent"
	st.set("reveal_radius", 8.0)
	st.set("scent_strength", 0.6)
	w.add_child(st)
	st.position = Vector3(0, 0.8, 0)
	st.connect("sniffed", func(_by: Node) -> void:
		st.set("active", false)
		st.remove_from_group("sniff_target")
		if is_instance_valid(w) and bool(w.get("disguised")) and w.has_method("_rip_costume"):
			ObjSvc.burst(self, w.global_position + Vector3(0, 1.0, 0), Color(0.55, 0.85, 0.35), 26, 3.5, 0.22, -2.0, 1.0)
			w.call("_rip_costume"))


## W1-7 The Foreman's Haystacks (W1_amendments R2.1): the shell game in the hay yard (w1_hayyard.gd).
func _hay_yard() -> void:
	var c := Vector3(-43.0, gy(-43.0, -48.5), -48.5)
	var hy := Node3D.new()
	hy.name = "HayYard_W1-7"
	hy.set_script(load("res://scripts/worlds/w1_hayyard.gd"))
	add_child(hy)
	hy.call("setup", c, self)
	_hay_sign()
	if life:
		# R3.6 Hay Hoist (interim procedural derrick until w1_hay_hoist lands): the finale landmark seen from the spawn.
		life.call("build_hoist", Vector3(-35.0, gy(-35.0, -56.0), -56.0), c, hy)
	hy.connect("defeated", func() -> void:
		var ui := get_node_or_null("/root/UI")
		if ui and ui.has_method("toast"):
			ui.call("toast", "The Foreman flees down the Camp Track in his smalls!")
		var game := get_node_or_null("/root/Game")
		if game == null or not bool(game.call("is_unlocked", "W1_punchline_seen")):
			if game:
				game.call("unlock", "W1_punchline_seen")
			# Fix round 1 (QA r1): the punchline used to cut in 2.5 s after the defeat, during the paused TRUFFLE GET!
			# splash. It now starts 0.6 s after the W1-7 celebration ends, or 14 s after the defeat (pausable timer)
			# for a player who leaves the truffle.
			var fired := [false]
			var go := func() -> void:
				if fired[0]:
					return
				fired[0] = true
				_punchline()
			var wr := get_parent()
			if wr and wr.has_signal("truffle_celebration_finished"):
				wr.connect("truffle_celebration_finished", func(id: String) -> void:
					if id == "W1-7":
						get_tree().create_timer(0.6).timeout.connect(go))
			get_tree().create_timer(14.0).timeout.connect(go))


## R3.3 the punchline: Sir Reginald tries to blow the brick house down himself, and fails. 8 s, first time only.
## Fix round 1 (fun critic r1): he stood on the windmill gallery behind the sail lattice, 40 px in the huff shot, with
## his lines above the frame. He now stands on the ridge in front of the windmill facing the house, filmed by
## StoryCam_G2_cameo (close, he fills about half the frame height) and StoryCam_J2_huff (a two-shot: house left,
## wolf right). The speech label is a sibling at a fixed height, so inflating him never pushes it out of frame.
## Mak is frozen and invulnerable for the whole beat.
func _punchline() -> void:
	var cams := get_parent().get_node_or_null("StoryCams")
	var prev := get_viewport().get_camera_3d()
	var path := "res://assets/characters/wolf_boss/wolf_boss.glb"
	if not ResourceLoader.exists(path) or cams == null:
		return
	cutscene_lock(8.4)
	var spot := Vector3(34.0, gy(34.0, -36.0), -36.0)
	var reg := Node3D.new()
	reg.name = "PunchlineReginald"
	add_child(reg)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	reg.add_child(model)
	var rposer := W1Poser.attach(model)
	if rposer:
		rposer.set_mode("talk")
	reg.global_position = spot
	reg.rotation.y = atan2(5.0 - spot.x, -34.0 - spot.z)  # face the brick house (model front is +Z)
	# Fix round 2 (fun r1: raw world-space Label3D lines): Reginald speaks through the game's speech pill (UI.bark),
	# each line held at least 1.8 s, on a fixed anchor so inflating him never pushes it out of frame.
	var say := Node3D.new()
	say.name = "PunchlineSpeech"
	add_child(say)
	say.global_position = spot + Vector3(-0.6, 0.0, 1.2)
	var ui := get_node_or_null("/root/UI")
	var talk := func(text: String, secs: float, h: float) -> void:
		if ui and ui.has_method("bark"):
			ui.call("bark", say, text, secs, {"speaker": "Sir Reginald", "height": h})
	var shot := func(cam_name: String) -> void:
		var c := cams.get_node_or_null(cam_name) as Camera3D
		if c:
			c.current = true
	shot.call("StoryCam_G2_cameo" if cams.has_node("StoryCam_G2_cameo") else "StoryCam_G_cameo")
	talk.call("So the Foreman failed. Fine. I shall do it MYSELF.", 1.8, 3.4)
	var tw := reg.create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(reg, "scale", Vector3(1.32, 1.22, 1.32), 1.2).set_trans(Tween.TRANS_BACK)
	var tile := K.rbox(self, Vector3(0.7, 0.08, 0.5), K.mat(Color("5b6577"), 0.6), Vector3(6.5, 20.2, -34.6), Vector3(-38, 0, 0), 0.03)
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		shot.call("StoryCam_J2_huff" if cams.has_node("StoryCam_J2_huff") else "StoryCam_J_huff")
		talk.call("HUFF... and... PUFF!", 2.4, 4.6)
		EnemyKit.sfx(self, "boss_huff_blast", spot, 1.0)
		if rposer:
			rposer.set_mode("huff")
		var swirl := D.fx(self, "GustSwirl", spot + Vector3(-1.2, 2.4, 0.2))
		if swirl:
			swirl.look_at(Vector3(9, 16, -34), Vector3.UP)
			swirl.set("length", 26.0)
			swirl.set("radius", 3.0)
			if swirl.has_method("set_active"):
				swirl.call("set_active", true)
			get_tree().create_timer(2.6).timeout.connect(swirl.queue_free)
		for k in 8:
			get_tree().create_timer(0.3 * k).timeout.connect(func() -> void:
				var a := spot.lerp(Vector3(9, 15, -34), float(k) / 8.0) + Vector3(0, 2.0, 0)
				ObjSvc.burst(self, a, Color(0.95, 0.97, 1.0), 14, 6.0, 0.25, 0.0, 0.8))
		if sail_rotor:
			sail_rotor.set("degrees_per_second", -360.0 / 14.0 * 4.0)
		var tt := tile.create_tween()
		tt.tween_property(tile, "position:y", 21.4, 0.8).set_trans(Tween.TRANS_SINE)
		tt.tween_property(tile, "position:y", 20.2, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var b3 := get_node_or_null("Bellows_bellows_B3") as Node3D
		if b3:
			var bt := b3.create_tween()
			for k in 6:
				bt.tween_property(b3, "rotation_degrees:z", 6.0 if k % 2 == 0 else -6.0, 0.2)
			bt.tween_property(b3, "rotation_degrees:z", 0.0, 0.2))
	get_tree().create_timer(4.6).timeout.connect(func() -> void:
		shot.call("StoryCam_F_arena")
		if ui and ui.has_method("clear_barks"):
			ui.call("clear_barks", say)
		var bert := get_node_or_null("Bertram")
		if bert:
			bert.set("lines", PackedStringArray(["Brick, old bean. Always brick."]))
			if bert.has_method("talk"):
				bert.call("talk"))
	get_tree().create_timer(6.2).timeout.connect(func() -> void:
		shot.call("StoryCam_G2_cameo" if cams.has_node("StoryCam_G2_cameo") else "StoryCam_G_cameo")
		talk.call("Pfffbbbtt...", 1.8, 3.4)
		# The failed huff lands: a deflating wheeze and a little camera shake.
		EnemyKit.sfx(self, "wolf_huff", spot, 0.55)
		var sc := get_viewport().get_camera_3d()
		if sc:
			var st := sc.create_tween()
			for k in 6:
				st.tween_property(sc, "h_offset", 0.08 if k % 2 == 0 else -0.08, 0.05)
			st.tween_property(sc, "h_offset", 0.0, 0.05)
		if rposer:
			rposer.set_mode("flee")
		if sail_rotor:
			sail_rotor.set("degrees_per_second", -360.0 / 14.0)
		var t2 := reg.create_tween()
		t2.tween_property(reg, "scale", Vector3(0.75, 0.8, 0.75), 0.5)
		t2.tween_property(reg, "global_position", spot + Vector3(26, 22, -26), 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t2.parallel().tween_property(reg, "rotation_degrees:y", reg.rotation_degrees.y + 720.0, 1.3)
		t2.tween_callback(reg.queue_free))
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		tile.queue_free()
		say.queue_free()
		if is_instance_valid(prev):
			prev.current = true)


## Freezes Mak (no input, no physics) and makes him invulnerable for a scripted beat; the camera is a story cam.
func cutscene_lock(seconds: float) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	if "invulnerable" in pl:
		pl.set("invulnerable", seconds + 1.5)
	pl.process_mode = Node.PROCESS_MODE_DISABLED
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("set_hud_visible"):
		ui.call("set_hud_visible", false)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if ui and ui.has_method("set_hud_visible"):
			ui.call("set_hud_visible", true)
		if is_instance_valid(pl):
			pl.process_mode = Node.PROCESS_MODE_INHERIT)


func _hay_sign() -> void:
	# Work-order board at the gate.
	var sp := load(OBJ % "SignPost") as PackedScene
	if sp:
		var b := sp.instantiate() as Node3D
		b.name = "SIGN_hayyard"
		b.set("board_text", "WORK ORDER")
		b.set("lines", PackedStringArray(["WORK ORDER: Hide in hay. Shuffle. Do NOT get sniffed. NO PIGS. - The Foreman"]))
		b.position = Vector3(-32.5, gy(-32.5, -49.4), -49.4)
		b.rotation_degrees.y = -100.0
		add_child(b)


## Superseded by R2.1 (kept for reference, unused): W1-7 The Foreman's Charge (R1.9): a big Woolly Wolf brute (the closest real model until the Foreman mesh lands)
## who charges in committed lines; the brick house, woodshed and chimney stop him dead (bonk, dizzy), then he can be
## Ham Slammed, stomped or punched. Three hits; the truffle rises at the arena centre.
func _foreman(pos: Vector3) -> void:
	var ps := load("res://scenes/enemies/WoollyWolf.tscn") as PackedScene
	if ps == null:
		return
	var f := ps.instantiate() as Node3D
	f.name = "FM1_Foreman"
	f.set("max_hp", 5)  # three Ham Slams (2 each) or five stomps
	f.set("charge_speed", 11.0)
	f.set("charge_time", 1.35)
	f.set("acorns_on_defeat", 8)
	f.scale = Vector3.ONE * 1.6
	f.position = Vector3(pos.x, gy(pos.x, pos.z) + 0.05, pos.z)
	add_child(f)
	f.set("notice_radius", 12.0)
	f.set("lose_radius", 18.0)
	var spawner := Node3D.new()
	spawner.set_script(load("res://scripts/objects/truffle_spawner.gd"))
	spawner.name = "ForemanReward_W1-7"
	spawner.set("reward_truffle_id", "W1-7")
	spawner.set("show_ghost_if_owned", true)
	spawner.position = Vector3(5.0, gy(5.0, -27.5) + 0.3, -27.5)
	add_child(spawner)
	if f.has_signal("defeated"):
		f.connect("defeated", func(_e: Node) -> void:
			var ui := get_node_or_null("/root/UI")
			if ui and ui.has_method("toast"):
				ui.call("toast", "The Foreman flees in his smalls!")
			var bert := get_node_or_null("Bertram")
			if bert:
				bert.set("lines", PackedStringArray(["Brick, old bean. Always brick."]))
				if bert.has_method("talk"):
					bert.call("talk")
			spawner.call("give_reward"))
	# A painted sign on the brick front door (R1.3 SIGN_door).
	var lbl := Label3D.new()
	lbl.text = "Not by the hair of my
chinny-chin-chin.
- The Management"
	lbl.font_size = 30
	lbl.pixel_size = 0.004
	lbl.modulate = Color("f6ecd6")
	lbl.outline_size = 8
	lbl.outline_modulate = Color("3b2416")
	lbl.position = Vector3(4.2, 14.9, -32.45)
	add_child(lbl)


## R1.10: WW9 wedged upside down on the soot ledge. A visual model with a slam sensor (no blocking body, so wall
## kicks pass); a Ham Slam pops him loose like a cork and he drops five acorns out of the soot door.
func _chimney_gag(pos: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "WW9_Stuck"
	holder.position = Vector3(10.6, 19.2, -35.0)
	add_child(holder)
	var g := glb("res://assets/enemies/woolly_wolf/woolly_wolf.glb")
	var model: Node3D = null
	if g:
		model = g.instantiate() as Node3D
		model.rotation_degrees = Vector3(0, 90, 180)
		model.position = Vector3(0, 1.0, 0)
		model.scale = Vector3.ONE * 0.9
		holder.add_child(model)
	var heckle := Label3D.new()
	heckle.text = "I was told it
goes DOWN!"
	heckle.font_size = 30
	heckle.pixel_size = 0.006
	heckle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	heckle.outline_size = 10
	heckle.position = Vector3(0, 1.9, 0)
	holder.add_child(heckle)
	var sensor := SlamSensor.create(holder, 0.9, 1.4, Vector3.ZERO)
	sensor.slammed.connect(func(_by: Node) -> void:
		heckle.text = "POP!"
		var tw := holder.create_tween()
		tw.tween_property(holder, "position", Vector3(10.6, 12.6, -35.6), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(holder, "position", Vector3(15.5, 12.4, -36.0), 0.5)
		tw.tween_callback(func() -> void:
			ObjSvc.spawn_acorns(self, Vector3(14.2, 12.3, -36.0), 5)
			holder.queue_free())
		sensor.queue_free())
	# Wiggle while stuck.
	if model:
		var tw2 := model.create_tween().set_loops()
		tw2.tween_property(model, "rotation_degrees:z", 172.0, 0.35)
		tw2.tween_property(model, "rotation_degrees:z", 188.0, 0.35)


func _on_siege_wolf_defeated(_enemy: Node) -> void:
	siege_left -= 1
	var ui := get_node_or_null("/root/UI")
	if siege_left > 0:
		if ui and ui.has_method("toast"):
			if siege_left == 1 and life and bool(life.call("hay_hidden")):
				ui.call("toast", "One Woolly Wolf left... and that haystack just sneezed.")
			else:
				ui.call("toast", "Woolly Wolves left: %d" % siege_left)
		return
	_blow_down()


## R1.4 blow-down: a 2.6 s cut to StoryCam_E_blowdown while B1 (or its wheezing wreck) gives one enormous gust.
## Fix round 1 (fun critic r1: "the tale never happens"): the straw roof now really comes off. The house mesh is split
## at the eave (w1_clip.gdshader): the roof cap copy hinges on the west eave, folds flat to the west in a storm of
## thatch chunks and becomes the bouncy thatch_flap (with acorn column A25). Persistent with W1-1 owned.
func _blow_down() -> void:
	var cam := get_parent().get_node_or_null("StoryCams/StoryCam_E_blowdown") as Camera3D
	var prev := get_viewport().get_camera_3d()
	cutscene_lock(2.8)
	if cam:
		cam.current = true
	var swirl := D.fx(self, "GustSwirl", Vector3(-12.0, 2.0, 26.0))
	if swirl:
		swirl.look_at(Vector3(-22.0, 2.5, 26.0), Vector3.UP)
		swirl.set("length", 12.0)
		swirl.set("radius", 2.5)
		if swirl.has_method("set_active"):
			swirl.call("set_active", true)
	for k in 6:
		get_tree().create_timer(0.25 * k).timeout.connect(func() -> void:
			ObjSvc.burst(self, Vector3(-20.0 + randf_range(-3, 3), 5.5, 26.0 + randf_range(-3, 3)), Color(0.95, 0.8, 0.4), 40, 9.0, 0.35, -6.0, 1.6))
	var house := get_node_or_null("StrawHouse") as Node3D
	if house:
		var tw := house.create_tween()
		for k in 3:
			tw.tween_property(house, "rotation_degrees:z", 3.0 if k % 2 == 0 else -2.5, 0.15)
		tw.tween_property(house, "rotation_degrees:z", 0.0, 0.2)
	get_tree().create_timer(0.5).timeout.connect(func() -> void: _straw_after(true))
	get_tree().create_timer(2.6).timeout.connect(func() -> void:
		if swirl and is_instance_valid(swirl):
			if swirl.has_method("set_active"):
				swirl.call("set_active", false)
			swirl.queue_free()
		if is_instance_valid(prev):
			prev.current = true
		if pip:
			pip.set("lines", PackedStringArray(["Well. It WAS a lovely house.", "They spun off in their smalls, cousin! Here, this Golden Truffle was in my porridge pot."]))
			if pip.has_method("talk"):
				pip.call("talk")
		if siege_spawner and siege_spawner.has_method("give_reward"):
			siege_spawner.call("give_reward"))


const STRAW_EAVE_Y := 3.8


## Gives every surface under `root` a clip material copy of its own (albedo colour and texture kept).
func _clip_materials(root: Node3D, keep_above: bool, world_y: float) -> void:
	var sh := load("res://assets/environment/w1/w1_clip.gdshader") as Shader
	if sh == null:
		return
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var local_clip := (mi.global_transform.affine_inverse() * Vector3(mi.global_position.x, world_y, mi.global_position.z)).y
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si)
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("clip_y", local_clip)
			m.set_shader_parameter("keep_above", 1.0 if keep_above else 0.0)
			if src is BaseMaterial3D:
				var bm := src as BaseMaterial3D
				m.set_shader_parameter("albedo_color", bm.albedo_color)
				m.set_shader_parameter("roughness_v", bm.roughness)
				if bm.albedo_texture:
					m.set_shader_parameter("albedo_tex", bm.albedo_texture)
					m.set_shader_parameter("has_tex", true)
			mi.set_surface_override_material(si, m)


## Procedural cottage: the roof node hinges on the west eave, swings up and over to the west in a storm of thatch
## chunks, lands upside down and collapses into the thatch_flap.
func _fold_roof(animate: bool, house: Node3D) -> void:
	var roof := straw_roof
	var rb := roof.get_node_or_null("StrawRoofBody") as StaticBody3D
	if rb:
		rb.queue_free()
	if not animate:
		roof.queue_free()
		straw_roof = null
		return
	var tw := roof.create_tween()
	tw.tween_property(roof, "rotation_degrees:z", 25.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(roof, "position:y", roof.position.y + 0.8, 0.3)
	tw.tween_property(roof, "rotation_degrees:z", 172.0, 0.75).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(roof, "position:y", roof.position.y - 0.4, 0.75)
	tw.tween_interval(0.45)
	tw.tween_property(roof, "scale", Vector3(1.0, 0.05, 1.0), 0.3)
	tw.tween_callback(func() -> void:
		roof.queue_free()
		straw_roof = null)
	var straw := K.tex_mat("straw_thatch", Color(1.1, 0.98, 0.76), 0.5)
	for k in 12:
		var c := K.rbox(self, Vector3(randf_range(0.5, 1.0), 0.18, randf_range(0.4, 0.8)), straw, Vector3(-20.0 + randf_range(-3.0, 3.0), STRAW_EAVE_Y + randf_range(0.8, 3.0), house.global_position.z + randf_range(-2.5, 2.5)), Vector3(randf_range(-30, 30), randf_range(0, 360), randf_range(-30, 30)), 0.06)
		var from := c.position
		var to := Vector3(from.x - randf_range(6.0, 13.0), gy(from.x - 9.0, from.z) + 0.1, from.z + randf_range(-3.0, 3.0))
		var spin := Vector3(randf_range(-720, 720), randf_range(-360, 360), randf_range(-720, 720))
		var ct := c.create_tween()
		ct.tween_method(func(kk: float) -> void:
			if is_instance_valid(c):
				c.position = from.lerp(to, kk) + Vector3(0, 3.0 * sin(kk * PI), 0)
				c.rotation_degrees = spin * kk, 0.0, 1.0, 1.2)
		ct.tween_interval(2.5)
		ct.tween_property(c, "scale", Vector3.ONE * 0.01, 0.5)
		ct.tween_callback(c.queue_free)


## The straw house after the blow-down: walls only (clip + wall-only collision), thatch_flap and A25 west of it.
## animate: the roof cap copy folds off first.
func _straw_after(animate: bool) -> void:
	var house := get_node_or_null("StrawHouse") as Node3D
	if house == null or house.has_meta("roof_off"):
		return
	house.set_meta("roof_off", true)
	var eave := STRAW_EAVE_Y
	if straw_roof and is_instance_valid(straw_roof):
		_fold_roof(animate, house)
	elif animate:
		var roof := house.duplicate() as Node3D
		roof.name = "StrawRoofFlap"
		var pivot := Node3D.new()
		pivot.name = "StrawRoofPivot"
		add_child(pivot)
		pivot.global_position = Vector3(-23.5, eave, house.global_position.z)
		pivot.add_child(roof)
		roof.global_transform = house.global_transform
		_clip_materials(roof, true, eave)
		var tw := pivot.create_tween()
		tw.tween_property(pivot, "position:y", eave + 1.2, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(pivot, "rotation_degrees:z", 40.0, 0.25)
		tw.tween_property(pivot, "rotation_degrees:z", 172.0, 0.75).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(pivot, "position:y", 1.2, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.5)
		tw.tween_property(pivot, "scale", Vector3(1.0, 0.05, 1.0), 0.3)
		tw.tween_callback(pivot.queue_free)
		# Thatch chunks flung west on spinning arcs.
		var straw := K.tex_mat("straw_thatch", Color(1.1, 0.98, 0.76), 0.5)
		for k in 10:
			var c := K.rbox(self, Vector3(randf_range(0.5, 1.0), 0.18, randf_range(0.4, 0.8)), straw, Vector3(-20.0 + randf_range(-2.5, 2.5), eave + randf_range(0.5, 2.5), house.global_position.z + randf_range(-2.5, 2.5)), Vector3(randf_range(-30, 30), randf_range(0, 360), randf_range(-30, 30)), 0.06)
			var from := c.position
			var to := Vector3(from.x - randf_range(6.0, 12.0), gy(from.x - 9.0, from.z) + 0.1, from.z + randf_range(-3.0, 3.0))
			var spin := Vector3(randf_range(-720, 720), randf_range(-360, 360), randf_range(-720, 720))
			var ct := c.create_tween()
			ct.tween_method(func(kk: float) -> void:
				if is_instance_valid(c):
					c.position = from.lerp(to, kk) + Vector3(0, 3.0 * sin(kk * PI), 0)
					c.rotation_degrees = spin * kk, 0.0, 1.0, 1.2)
			ct.tween_interval(2.5)
			ct.tween_property(c, "scale", Vector3.ONE * 0.01, 0.5)
			ct.tween_callback(c.queue_free)
	if straw_roof == null:
		_clip_materials(house, false, eave)
	# Collision: keep only the faces below the eave, so nobody stands on a roof that is no longer there.
	var shell := get_node_or_null("StrawHouseShell")
	if shell and shells.has("straw"):
		var faces: PackedVector3Array = shells["straw"]
		var keep := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			if maxf(faces[i].y, maxf(faces[i + 1].y, faces[i + 2].y)) < eave + 0.2:
				keep.append(faces[i])
				keep.append(faces[i + 1])
				keep.append(faces[i + 2])
		var cs := shell.get_child(0) as CollisionShape3D
		if cs and keep.size() >= 3:
			var shp := ConcavePolygonShape3D.new()
			shp.backface_collision = false
			shp.set_faces(keep)
			cs.shape = shp
		shells["straw"] = keep
	# thatch_flap: the folded roof lying west of the house, a bouncy mattress (apex 4 m) with acorn column A25.
	var fp: Dictionary = plat.get("thatch_flap", {})
	if fp.is_empty():
		return
	var top := v3(fp["top"])
	var size := v3(fp["size"])
	var flap := K.body(self, "thatch_flap", top - Vector3(0, size.y, 0))
	flap.add_to_group("bouncy")
	flap.set_meta("bounce_velocity", sqrt(2.0 * 28.0 * 4.0))
	K.shape_box(flap, size, Vector3(0, size.y * 0.5, 0))
	var thatch := K.tex_mat("straw_thatch", Color(1.1, 0.96, 0.72), 0.5)
	K.rbox(flap, Vector3(size.x, size.y, size.z), thatch, Vector3(0, size.y * 0.5, 0), Vector3(0, 0, 2.0), 0.25)
	for k in 5:
		K.rbox(flap, Vector3(size.x * 0.96, 0.12, 0.5), K.tex_mat("straw_thatch", Color(0.95, 0.82, 0.58), 0.5), Vector3(0, size.y + 0.02, -size.z * 0.4 + k * size.z * 0.2), Vector3(0, 0, 2.0), 0.05)
	if animate:
		flap.scale = Vector3(1, 0.01, 1)
		var ft := flap.create_tween()
		ft.tween_interval(1.0)
		ft.tween_property(flap, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for g in lv.get("acorn_groups", []):
		if String(g["id"]) == "A25":
			var a := v3(g["start"])
			var c2 := v3(g["end"]) if g.has("end") else a + Vector3(0, 4.0, 0)
			var n := obj("AcornGroup", a, {"shape": AcornGroup.Shape.LINE, "count": int(g.get("count", 5)), "length": a.distance_to(c2)})
			if n:
				n.name = "A25"
				n.basis = Basis.looking_at((c2 - a).normalized(), Vector3.FORWARD if absf((c2 - a).normalized().y) > 0.95 else Vector3.UP)


## R3.2 tale beat (fix round 1: "after W1-3 nothing happens to the stick house"): once, after the W1-3 celebration,
## a 3 s cut to StoryCam_I_sticks; B2 gives one enormous gust and the stick house folds into a heap (procedural
## until the stick_house_collapsed mesh lands), with stick_pile_top (y 6.0) and acorn ring A33 on it. Hazel, now
## on the treehouse deck: "Sticks were a phase." Persistent with W1-3 owned.
func _stick_collapse(animate: bool) -> void:
	var house := get_node_or_null("StickHouse") as Node3D
	if house == null or house.has_meta("collapsed"):
		return
	house.set_meta("collapsed", true)
	var shell := get_node_or_null("StickHouseShell")
	var prev := get_viewport().get_camera_3d()
	if animate:
		cutscene_lock(3.2)
		var cam := get_parent().get_node_or_null("StoryCams/StoryCam_I_sticks") as Camera3D
		if cam:
			cam.current = true
		var swirl := D.fx(self, "GustSwirl", Vector3(-28.0, 6.0, -16.0))
		if swirl:
			swirl.look_at(Vector3(-42.0, 6.5, -18.0), Vector3.UP)
			swirl.set("length", 14.0)
			swirl.set("radius", 3.0)
			if swirl.has_method("set_active"):
				swirl.call("set_active", true)
			get_tree().create_timer(2.2).timeout.connect(swirl.queue_free)
		var tw := house.create_tween()
		tw.tween_interval(0.5)
		for k in 4:
			tw.tween_property(house, "rotation_degrees:z", 5.0 if k % 2 == 0 else -4.0, 0.12)
		tw.tween_property(house, "scale", Vector3(1.15, 0.2, 1.1), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			house.visible = false
			for k in 5:
				ObjSvc.burst(self, Vector3(-42.0 + randf_range(-3, 3), 5.5, -18.0 + randf_range(-3, 3)), Color(0.62, 0.45, 0.28), 30, 7.0, 0.3, -9.0, 1.2)
			_stick_heap(true))
		get_tree().create_timer(3.2).timeout.connect(func() -> void:
			if is_instance_valid(prev):
				prev.current = true
			var hz := get_node_or_null("Hazel") as Node3D
			if hz:
				var dp := Vector3(-45.0, 16.0, -31.5)
				hz.global_position = dp
				hz.rotation_degrees.y = 120.0
				hz.set("lines", PackedStringArray(["Sticks were a phase.", "Brick next time. Bertram's been VERY smug about it."]))
				if hz.has_method("talk"):
					hz.call("talk"))
	else:
		house.visible = false
		_stick_heap(false)
	if shell:
		shell.queue_free()


func _stick_heap(animate: bool) -> void:
	var c := Vector3(-42.0, 4.0, -17.6)
	var heap := K.body(self, "StickHouseCollapsed", c)
	# Walkable top stick_pile_top at y 6.0 (2 m above the base), a lower apron so the woodpile route steps up.
	K.shape_box(heap, Vector3(6.0, 2.0, 5.0), Vector3(0, 1.0, 0))
	K.shape_box(heap, Vector3(7.2, 1.0, 6.2), Vector3(0, 0.5, 0))
	var bark := K.tex_mat("bark", Color(0.92, 0.72, 0.52), 0.6)
	var bark2 := K.tex_mat("bark", Color(0.75, 0.56, 0.4), 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 333
	for k in 46:
		var r := rng.randf_range(0.07, 0.15)
		var ln := rng.randf_range(1.8, 4.2)
		var layer := float(k) / 46.0
		var p := Vector3(rng.randf_range(-3.0, 3.0) * (1.0 - layer * 0.4), 0.2 + layer * 1.7, rng.randf_range(-2.5, 2.5) * (1.0 - layer * 0.4))
		K.cyl(heap, r, r * 1.1, ln, bark if k % 3 else bark2, p, Vector3(rng.randf_range(70, 110), rng.randf_range(0, 180), rng.randf_range(-15, 15)), 6)
	# The branch door flat on top, an upside-down chimney pot, twine everywhere.
	K.rbox(heap, Vector3(1.2, 0.12, 2.0), K.tex_mat("wood_planks", Color(0.9, 0.7, 0.5), 0.7), Vector3(0.6, 2.05, 0.3), Vector3(0, 25, 4), 0.04)
	K.cone(heap, 0.35, 0.6, K.mat(Color("c0703f")), Vector3(-1.4, 2.25, -0.6), Vector3(180, 0, 12), 10)
	var twine := K.mat(Color("d8c08a"), 0.85)
	for k in 6:
		K.torus(heap, 0.12, 0.2, twine, Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(0.6, 1.9), rng.randf_range(-2, 2)), Vector3(rng.randf_range(0, 90), 0, rng.randf_range(0, 90)))
	if animate:
		heap.scale = Vector3(1, 0.05, 1)
		var tw := heap.create_tween()
		tw.tween_property(heap, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for g in lv.get("acorn_groups", []):
		if String(g["id"]) == "A33":
			var n := obj("AcornGroup", v3(g["center"]), {"shape": AcornGroup.Shape.RING, "count": int(g["count"]), "radius": float(g["radius"])})
			if n:
				n.name = "A33"


# ------------------------------------------------------------------ collectibles

func _collectibles() -> void:
	for g in lv.get("acorn_groups", []):
		var kind: String = g["kind"]
		if String(g["id"]) == "A25" or String(g["id"]) == "A33":
			continue  # built with the straw-roof blow-down and the stick-house collapse (_straw_after, _stick_heap)
		match kind:
			"line":
				var a := v3(g["start"])
				var c := v3(g["end"])
				var n := obj("AcornGroup", a, {"shape": AcornGroup.Shape.LINE, "count": int(g["count"]), "length": a.distance_to(c)})
				if n:
					n.name = String(g["id"])
					var d := c - a
					var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.FORWARD
					n.basis = Basis.looking_at(d.normalized(), up)
			"ring":
				var n2 := obj("AcornGroup", v3(g["center"]), {"shape": AcornGroup.Shape.RING, "count": int(g["count"]), "radius": float(g["radius"])})
				if n2:
					n2.name = String(g["id"])
			"points":
				var holder := Node3D.new()
				holder.name = String(g["id"])
				add_child(holder)
				for q in g["points"]:
					obj("Acorn", v3(q), {}, 0.0, holder)
			"crates":
				for q in g["crates"]:
					var cp := v3(q)
					cp.y = gy(cp.x, cp.z)
					obj("BreakableCrate", cp, {"acorns": int(g.get("acorns_per_crate", 5))}, float((int(cp.x * 13.0) % 40) - 20))
	for p in lv.get("pages", []):
		var pp := v3(p["pos"])
		var n3 := obj("LostPage", pp - Vector3(0, 0.55, 0), {"world_id": "W1", "page_index": int(p["index"]), "hover_height": 0.55})
		if n3:
			n3.name = "Page_" + String(p["id"])
	_stashes()
	_json_signs()
	# Fix round 2 (feel r1: a fall from the W1-5 long jump meant a 39-54 m walk back): a checkpoint at the foot of the Tor.
	var cps: Array = lv.get("checkpoints", []).duplicate()
	cps.append({"id": "CP8_tor_foot", "pos": [30.0, 0.5, 2.0]})
	var cp_yaw := {"CP8_tor_foot": 60.0, "CP0_gate": 0.0, "CP1_green": 40.0, "CP2_grove": 35.0, "CP3_treehouse": -90.0, "CP4_plateau": -60.0, "CP5_ridge": 70.0, "CP6_orchard": 0.0}
	for c in cps:
		var pos := v3(c["pos"])
		pos.y = maxf(pos.y, gy(pos.x, pos.z))
		if String(c["id"]) == "CP3_treehouse":
			pos.y = 16.0
		var n4 := obj("Checkpoint", pos, {"world_id": "W1"}, float(cp_yaw.get(String(c["id"]), 0.0)))
		if n4:
			n4.name = String(c["id"])


## R1.12 sniff stashes: SniffTarget (reveal radius 6) plus a slam sensor; a Ham Slam pops five acorns.
func _stashes() -> void:
	for st in lv.get("sniff_stashes", []):
		var p := v3(st["pos"])
		p.y = gy(p.x, p.z)
		var n := obj("SniffTarget", p, {"reveal_radius": 6.0, "scent_strength": 0.6})
		if n == null:
			continue
		n.name = "Stash_" + String(st["id"])
		var mound := K.sphere(n, 0.5, K.mat(Color("6b4a2c"), 0.95), Vector3(0, 0.0, 0), Vector3(1.3, 0.35, 1.3))
		mound.visible = false
		if n.has_signal("sniffed"):
			n.connect("sniffed", func(_by: Node) -> void: mound.visible = true)
		var count := int(st.get("acorns", 5))
		var sensor := SlamSensor.create(n, 1.0, 1.2, Vector3.ZERO)
		sensor.slammed.connect(func(_by: Node) -> void:
			ObjSvc.spawn_acorns(self, n.global_position + Vector3(0, 0.2, 0), count)
			ObjSvc.burst(self, n.global_position + Vector3(0, 0.3, 0), Color(0.4, 0.27, 0.15), 24, 6.0, 0.25, -14.0, 0.8)
			n.set("active", false)
			n.remove_from_group("sniff_target")
			mound.visible = true
			mound.scale = Vector3(1.6, 0.2, 1.6)
			sensor.queue_free())


## Finishing pass (HERO camera tour): SignPost's own box stops at 1.9 m while the board mesh is taller, so a retreating
## camera passed through the top boards for about 8 frames. World-side fix: every W1 signpost gets a second box on the
## same body that covers its mesh up to the top (measured from the visual's AABB once the meshes exist).
func _sign_camera_colliders() -> void:
	await get_tree().process_frame
	var n_fixed := 0
	for n in find_children("*", "StaticBody3D", true, false):
		if not (n is SignPost):
			continue
		var body := n as StaticBody3D
		var inv := body.global_transform.affine_inverse()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for m in body.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var ab := mi.get_aabb()
			for k in 8:
				var c: Vector3 = inv * (mi.global_transform * ab.get_endpoint(k))
				lo = lo.min(c)
				hi = hi.max(c)
		if hi.y <= 1.95 or lo == Vector3.INF:
			continue
		var top := hi.y
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(hi.x - lo.x, 0.3), top - 1.8, maxf(hi.z - lo.z, 0.2))
		var cs := CollisionShape3D.new()
		cs.name = "CameraTopBox"
		cs.shape = box
		cs.position = Vector3((hi.x + lo.x) * 0.5, 1.8 + (top - 1.8) * 0.5, (hi.z + lo.z) * 0.5)
		body.add_child(cs)
		n_fixed += 1
	print("[W1] signpost camera boxes: %d" % n_fixed)



func _json_signs() -> void:
	var ps := load(OBJ % "SignPost") as PackedScene
	if ps == null:
		return
	# R3.5 brick chute rim sign (builder).
	var chute := ps.instantiate() as Node3D
	chute.name = "SIGN_chute"
	chute.set("board_text", "Brick Chute")
	chute.set("lines", PackedStringArray(["The quick way down to the green. One way only. Dive in snout first for extra wheee."]))
	chute.position = Vector3(11.2, gy(11.2, -23.0), -23.0)
	chute.rotation_degrees.y = 160.0
	add_child(chute)
	for sg in lv.get("signs", []):
		var sid := String(sg["id"])
		if sid == "SIGN_door":
			continue  # painted on the brick front door (see _foreman)
		var p := v3(sg["pos"])
		if p.y < 10.0 or sid == "SIGN_P3" or sid == "SIGN_P2":
			p.y = maxf(gy(p.x, p.z), p.y if sid in ["SIGN_P3", "SIGN_P2"] else -100.0)
		var n := ps.instantiate() as Node3D
		n.name = sid
		var txt := String(sg["text"])
		var short := {"SIGN_P1": "Hollow Log", "SIGN_P2": "Stone Finger", "SIGN_P3": "Hut Roof", "SIGN_P4": "Kick Cleft", "SIGN_P5": "Scarecrow Run", "SIGN_plan": "BATTLE PLAN"}
		n.set("board_text", String(short.get(sid, "Note")))
		n.set("lines", PackedStringArray([txt]))
		n.position = p
		n.rotation_degrees.y = float(sg.get("yaw_deg", 0.0))
		add_child(n)
		if life and sg.has("fallback_text"):
			life.call("add_sign", n, txt, String(sg["fallback_text"]))


# ------------------------------------------------------------------ hazards

func _hazards() -> void:
	for h in lv.get("hazards", []):
		var t: String = h.get("type", "")
		if t == "thistle_patch":
			var c := v3(h["center"])
			c.y = gy(c.x, c.z)
			var r: float = float(h["radius"])
			var hz := obj("HazardVolume", c + Vector3(0, 0.5, 0), {"size": Vector3(r * 2.0, 1.0, r * 2.0), "damage": int(h.get("damage", 1)), "look": HazardVolume.Look.THORNS, "knockback_up": 7.0})
			if hz:
				hz.name = String(h["id"])
			D.thistles(self, c, r)
		elif t == "current_zone":
			_stream_current(float(h.get("push_mps", 2.0)))
		elif t == "updraft_zone":
			_spout()


var spout_zone: Node3D
var spout_visual: Node3D


## R2.4: after the third bellows, the well erupts into a permanent water spout that lifts Mak to the truffle.
func _spout() -> void:
	var base := Vector3(2.0, gy(2.0, -3.0), -3.0)
	spout_zone = obj("WindZone", base + Vector3(0, 1.0 + 6.5, 0), {"size": Vector3(2.4, 13.0, 2.4), "direction": Vector3(0, 1, 0), "strength": 22.0, "mode": WindZone.Mode.STEADY, "end_falloff": 0.18, "enabled": false, "streak_color": Color(0.85, 0.95, 1.0, 0.7)})
	if spout_zone:
		spout_zone.name = "W_spout"
	spout_visual = Node3D.new()
	spout_visual.name = "SpoutVisual"
	spout_visual.position = base
	spout_visual.visible = false
	add_child(spout_visual)
	var wm := load("res://assets/shaders/materials/water_stream_ribbon.tres") as Material
	var col := K.cyl(spout_visual, 0.7, 1.0, 12.5, wm if wm else K.mat(Color(0.6, 0.85, 1.0, 0.6)), Vector3(0, 6.6, 0), Vector3.ZERO, 16)
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	K.sphere(spout_visual, 1.3, K.mat(Color(0.85, 0.95, 1.0, 0.55), 0.1, 0.0), Vector3(0, 12.9, 0), Vector3(1, 0.5, 1))
	D.fx(spout_visual, "WaterfallFoam", Vector3(0, 1.1, 0))
	var bset := get_node_or_null("BellowsSet_W1-4")
	var game := get_node_or_null("/root/Game")
	if game and game.call("has_truffle", "W1-4"):
		_erupt(false)
	elif bset:
		bset.connect("rewarded", func(_id: String) -> void: _erupt(true))


func _erupt(fanfare: bool) -> void:
	# The well's roof pops off (the generated well is one mesh, so the eruption swaps in a roofless stone ring).
	var well := get_node_or_null("VillageWell") as Node3D
	var shell := get_node_or_null("VillageWellShell") as CollisionObject3D
	if well:
		well.visible = false
	if shell:
		shell.process_mode = Node.PROCESS_MODE_DISABLED
		for cs in shell.get_children():
			(cs as CollisionShape3D).set_deferred("disabled", true)
	var base := Vector3(2.0, gy(2.0, -3.0), -3.0)
	var ring := K.body(self, "WellRing", base)
	K.shape_cyl(ring, 1.35, 0.95, Vector3(0, 0.475, 0))
	var stone := K.tex_mat("cobblestone", Color(1.05, 1.0, 0.95), 0.6)
	K.cyl(ring, 1.3, 1.38, 0.95, stone, Vector3(0, 0.475, 0), Vector3.ZERO, 22)
	K.torus(ring, 1.0, 1.4, K.mat(K.STONE), Vector3(0, 0.96, 0))
	for sx in [-1.0, 1.0]:
		K.rbox(ring, Vector3(0.22, 1.4, 0.22), K.mat(K.WOOD), Vector3(sx * 1.15, 1.4, 0), Vector3(0, 0, sx * 12.0), 0.04)
	# Owner fix 2026-10-19: the fallen shingle roof (tilted 28 degrees at (5.5, -7)) lay across the Brick Chute run-out,
	# the H3 hose and the Mill Lane sign and read as a broken prop in the best spot. The spout blows the roof away now:
	# the eruption leaves the roofless stone ring and its two posts only.
	if spout_zone:
		spout_zone.call("set_enabled", true)
	if spout_visual:
		spout_visual.visible = true
		if fanfare:
			spout_visual.scale = Vector3(1, 0.05, 1)
			var tw := spout_visual.create_tween()
			tw.tween_interval(1.2)
			tw.tween_property(spout_visual, "scale", Vector3.ONE, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _stream_current(push: float) -> void:
	var s: Array = lv["_derived"]["stream_samples"]
	var holder := Node3D.new()
	holder.name = "StreamCurrent"
	add_child(holder)
	var i := 0
	while i < s.size() - 1:
		var j := mini(i + 4, s.size() - 1)
		var a := Vector3(float(s[i][0]), -0.55, float(s[i][1]))
		var c := Vector3(float(s[j][0]), -0.55, float(s[j][1]))
		var d := c - a
		if d.length() > 0.5:
			var z := obj("WindZone", (a + c) * 0.5, {"size": Vector3(6.2, 0.75, d.length() + 0.3), "direction": Vector3(0, 0, -1), "strength": push, "mode": WindZone.Mode.STEADY, "show_particles": false, "end_falloff": 0.0}, 0.0, holder)
			if z:
				z.basis = Basis.looking_at(d.normalized(), Vector3.UP)
		i = j


func _probe() -> void:
	var probes := {
		"straw": [Vector2(-20, 26), Vector2(-20, 24), Vector2(-20, 28), Vector2(-20, 29.5), Vector2(-17, 26), Vector2(-16.5, 28), Vector2(-15.5, 27.4), Vector2(-23, 26), Vector2(-20, 22.5)],
		"stick": [Vector2(-42, -18), Vector2(-42, -16), Vector2(-42, -15.5), Vector2(-42, -20), Vector2(-40, -18), Vector2(-44, -18), Vector2(-42, -15.0)],
		"brick": [Vector2(5, -36), Vector2(1.4, -36), Vector2(5, -34), Vector2(5, -33), Vector2(5, -32.8), Vector2(7.5, -32.8), Vector2(7.5, -33.5), Vector2(2.5, -33), Vector2(8.5, -36), Vector2(0.5, -36), Vector2(9.5, -36)],
		"mill": [Vector2(40, -46), Vector2(40, -43), Vector2(40, -42.5), Vector2(43, -46), Vector2(43.3, -46), Vector2(37, -46)],
		"straw2": [],
		"bridge": [Vector2(-6, 14.5), Vector2(-6, 13), Vector2(-6, 10), Vector2(-6, 6), Vector2(-6, 5.5), Vector2(-7.5, 10)],
	}
	var lines := []
	for zz in [-32.6, -33.0, -33.4, -33.8, -34.2, -34.6, -35.0, -35.5, -36.0]:
		lines.append("z%.1f:%.2f/%.2f/%.2f" % [zz, shell_y("brick", 3.0, zz, -99), shell_y("brick", 5.5, zz, -99), shell_y("brick", 8.5, zz, -99)])
	print("[W1 probe] brick slope x3/5.5/8.5 ", " ".join(lines))
	lines = []
	for xx in [-16.0, -16.5, -17.0, -17.5, -18.0, -18.5, -19.0, -19.5]:
		lines.append("x%.1f:%.2f/%.2f/%.2f" % [xx, shell_y("straw", xx, 29.0, -99), shell_y("straw", xx, 28.0, -99), shell_y("straw", xx, 27.0, -99)])
	print("[W1 probe] straw east z29/28/27 ", " ".join(lines))
	for k in probes:
		if not shells.has(k):
			continue
		var out := []
		for p in probes[k]:
			out.append("(%.1f,%.1f)=%.2f" % [p.x, p.y, shell_y(k, p.x, p.y, -99.0)])
		print("[W1 probe] ", k, " ", " ".join(out))
