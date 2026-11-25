extends Node3D
## ObjectsShowcase: every interactive object with its real generated model, in stations along +X, under the W1
## environment. Verification and making-of scene for the objects workstream (not gameplay).
## A Mak stand-in (the real mak_v2.glb on a CharacterBody3D in group "player", breathing through NpcLife) walks
## scripted paths so pickups, talk zones and doors react through their real Area3D triggers.
##   -- --demo=<station>   run that station's timeline (pickups, checkpoint, crate, npcs, door, portal, cage, wind)
##   -- --cam=Cam_<Name>   (Dev autoload) choose the camera; each station has Cam_<Station> and some close cams.
##   -- --env=W1|HUB|W2|W3 environment preset (default W1)

const O := "res://scenes/objects/"
const C := "res://assets/characters/"
const P := "res://assets/props/"

const STATIONS := {
	"pickups": 0.0, "checkpoint": 14.0, "crate": 28.0, "npcs": 42.0, "door": 70.0, "portal": 84.0, "cage": 98.0, "wind": 112.0, "dig": 126.0, "sky": 140.0,
}

var mak: CharacterBody3D
var mak_visual: Node3D
var nodes: Dictionary = {}
var _path: Array = []  # [[from, to, start_t, end_t], ...]
var _t := 0.0
var _demo := ""
var _events: Array = []  # [[t, callable]]


func _ready() -> void:
	var env := _arg("env", "W1")
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	FxEnvironments.apply(self, env)
	_ground()
	_spawn_mak()
	_pickups(STATIONS["pickups"])
	_checkpoint(STATIONS["checkpoint"])
	_crates(STATIONS["crate"])
	_npcs(STATIONS["npcs"])
	_door(STATIONS["door"])
	_portal(STATIONS["portal"])
	_cage(STATIONS["cage"])
	_wind(STATIONS["wind"])
	_dig(STATIONS["dig"])
	_sky(STATIONS["sky"])
	var j := get_node_or_null("/root/Juice")
	if j and j.has_signal("fired"):
		j.connect("fired", func(n: String, p: Vector3, _pa: Dictionary) -> void: print("[Showcase] t=%.2f juice %s at %s" % [_t, n, p]))
	_demo = _arg("demo", "")
	if _demo == "tour":
		_build_tour()
	elif _demo == "tour2":
		_build_tour(TOUR2)
	elif _demo == "tour3":
		_build_tour(TOUR3)
	elif _demo != "":
		_build_demo(_demo)


func _arg(k: String, d: String) -> String:
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("arg"):
		return str(dev.call("arg", k, d))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.split("=", true, 1)[1]
	return d


func _ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = ObjSvc.L_WORLD
	add_child(body)
	ObjSvc.add_shape(body, ObjSvc.box_shape(Vector3(260, 1, 60)), Vector3(56, -0.5, 0))
	var mat := ObjSvc.mat(Color(0.45, 0.66, 0.32), 0.95)
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 60)
	pm.subdivide_width = 64
	pm.subdivide_depth = 16
	var mi := ObjSvc.add_mesh(self, pm, mat, Vector3(56, 0, 0))
	mi.name = "GroundMesh"


func _cam(n: String, pos: Vector3, look: Vector3, fov: float = 50.0) -> Camera3D:
	var c := Camera3D.new()
	c.name = n
	c.fov = fov
	add_child(c)
	c.position = pos
	c.look_at(look, Vector3.UP)
	return c


func _obj(scene: String, pos: Vector3, props: Dictionary = {}, yaw_deg: float = 0.0, n: String = "") -> Node3D:
	var ps := load(O + scene + ".tscn") as PackedScene
	var o := ps.instantiate() as Node3D
	for k in props.keys():
		o.set(k, props[k])
	o.position = pos
	o.rotation_degrees.y = yaw_deg
	if n != "":
		o.name = n
	add_child(o)
	if n != "":
		nodes[n] = o
	return o


func _glb(path: String) -> PackedScene:
	return load(path) as PackedScene if ResourceLoader.exists(path) else null


# ------------------------------------------------------------------ Mak stand-in

func _spawn_mak() -> void:
	mak = CharacterBody3D.new()
	mak.name = "MakStandIn"
	mak.add_to_group("player")
	mak.collision_layer = ObjSvc.L_PLAYER
	mak.collision_mask = 0
	add_child(mak)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.25
	cs.shape = cap
	cs.position = Vector3(0, 0.625, 0)
	mak.add_child(cs)
	mak_visual = Node3D.new()
	mak_visual.name = "Visual"
	mak_visual.rotation.y = PI
	mak.add_child(mak_visual)
	# The stand-in wears whatever hero model the real player uses (the hero track swaps it), so the showcase never
	# shows a superseded Mak.
	var ps := _glb(_arg("mak", player_mesh_path()))  # -- --mak=<glb> previews another hero file
	if ps == null:
		ps = _glb(C + "mak/mak.glb")
	if ps:
		var m := ps.instantiate() as Node3D
		mak_visual.add_child(m)
		var life := NpcLife.attach(m)
		life.look_at_player = false
	mak.position = Vector3(-30, 0, 0)


## The hero model path the real Player.tscn uses: an override in the scene, else the script default.
static func player_mesh_path() -> String:
	var p := _player_mesh_path_raw()
	# The player wears a bare body and attaches the hat and pack itself; the stand-in uses the assembled outfit.
	if p.ends_with("_body.glb") and ResourceLoader.exists(p.trim_suffix("_body.glb") + ".glb"):
		return p.trim_suffix("_body.glb") + ".glb"
	return p


static func _player_mesh_path_raw() -> String:
	var fallback := "res://assets/characters/mak/mak_v2.glb"
	var pps := load("res://scenes/player/Player.tscn") as PackedScene if ResourceLoader.exists("res://scenes/player/Player.tscn") else null
	if pps == null:
		return fallback
	var st := pps.get_state()
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == &"rigged_mesh_path":
			return str(st.get_node_property_value(0, i))
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == &"script":
			var scr := st.get_node_property_value(0, i) as Script
			if scr != null:
				var v: Variant = scr.get_property_default_value(&"rigged_mesh_path")
				if v != null and ResourceLoader.exists(str(v)):
					return str(v)
	return fallback


func get_state_name() -> String:
	return "walk"


func _walk(from: Vector3, to: Vector3, t0: float, t1: float) -> void:
	_path.append([from, to, t0 + _t_off, t1 + _t_off])


func _physics_process(delta: float) -> void:
	_t += delta
	for e in _events.duplicate():
		if _t >= float(e[0]):
			_events.erase(e)
			(e[1] as Callable).call()
	for seg in _path:
		var t0: float = seg[2]
		var t1: float = seg[3]
		if _t >= t0 and _t <= t1:
			var u := (_t - t0) / maxf(t1 - t0, 0.01)
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			mak.global_position = a.lerp(b, u)
			var d := b - a
			d.y = 0.0
			if d.length() > 0.01:
				mak.rotation.y = lerp_angle(mak.rotation.y, atan2(-d.x, -d.z), 0.25)
			# A little walking bob so the stand-in does not glide like a statue.
			mak_visual.position.y = absf(sin(_t * 9.0)) * 0.05
			mak_visual.rotation.z = sin(_t * 9.0) * 0.05


func _at(t: float, f: Callable) -> void:
	_events.append([t + _t_off, f])


## Time offset for the "tour" demo (several station timelines played back to back in one clip).
var _t_off := 0.0
## Round 2 verification tour: [station, camera, seconds].
const TOUR := [
	["door", "Cam_Door_Oblique", 11.0], ["sky", "Cam_Sky", 8.5], ["cage_close", "Cam_Cage_Close", 9.0],
	["wind", "Cam_Wind", 9.0], ["dig", "Cam_Dig_Close", 9.0], ["portal", "Cam_Portal_Close", 4.0],
	["sign", "Cam_Sign_Front", 2.0], ["sign", "Cam_Sign_Back", 2.0],
]


const TOUR2 := [
	["sign", "Cam_Sign_Front", 2.5], ["sign", "Cam_Sign_Back", 2.0], ["dig", "Cam_Dig_Close", 9.0],
	["portal", "Cam_Portal_Close", 4.0], ["sky", "Cam_Sky", 8.5], ["npcs", "Cam_NPC_Close", 7.0],
]


## Fix stage round 1 (critique r1 re-run) verification tour: lock dressing, sign text, talk spacing, truffle skin,
## twinkles and the page glints.
const TOUR3 := [
	["door", "Cam_Door", 7.0], ["sign", "Cam_Sign_Front", 2.5], ["sign", "Cam_Sign_Back", 2.0],
	["npcs", "Cam_NPC_Close", 7.0], ["pickups", "Cam_Truffle_Close", 3.0], ["checkpoint", "Cam_Page_Close", 3.0],
	["sky", "Cam_Sky", 8.5], ["dig", "Cam_Dig_Close", 9.0],
]


func _build_tour(list: Array = TOUR) -> void:
	var t := 0.0
	for seg in list:
		var st: String = seg[0]
		var cam_name: String = seg[1]
		_t_off = t
		_at(0.0, func() -> void:
			var c := get_node_or_null(cam_name) as Camera3D
			if c:
				c.make_current()
			_close_any_dialog()
			print("[Showcase] tour t=%.1f %s %s" % [_t, st, cam_name]))
		if st != "sign":
			_build_demo(st)
		t += float(seg[2])
	_t_off = 0.0


## Critique objects r1 re-run: the locked door's sneer stayed up for ~50 s of the tour and covered later shots.
func _close_any_dialog() -> void:
	var ui := ObjSvc.autoload("UI")
	if ui == null:
		return
	var d: Variant = ui.get("dialog")
	if d is Object and is_instance_valid(d) and (d as Object).has_method("close") and bool(ObjSvc.call_on("UI", "is_dialog_open")):
		(d as Object).call("close")


# ------------------------------------------------------------------ stations

func _pickups(x: float) -> void:
	_obj("Truffle", Vector3(x - 1.4, 0, 0), {"truffle_id": "SHOW-1"}, 0.0, "Truffle_A")
	_obj("Truffle", Vector3(x + 1.6, 0, -1.0), {"truffle_id": "SHOW-2"}, 0.0, "Truffle_B")
	# An already-owned truffle (ghost look); collected in this showcase profile before it is placed.
	ObjSvc.collect_truffle("SHOW-GHOST")
	_obj("Truffle", Vector3(x + 0.2, 0, -4.6), {"truffle_id": "SHOW-GHOST"}, 0.0, "Truffle_Ghost")
	_cam("Cam_Ghost_Close", Vector3(x + 0.2, 1.2, -6.8), Vector3(x + 0.2, 0.95, -4.6), 40.0)
	_obj("AcornGroup", Vector3(x - 3.0, 0, 2.2), {"shape": 0, "count": 7, "length": 6.0}, -90.0, "Acorns_Line")
	_obj("AcornGroup", Vector3(x + 4.5, 0, 0.5), {"shape": 1, "count": 6, "radius": 1.0}, 0.0, "Acorns_Ring")
	_cam("Cam_Pickups", Vector3(x, 1.7, 7.0), Vector3(x, 0.7, 0.4))
	_cam("Cam_Truffle_Close", Vector3(x - 1.4, 1.2, 2.2), Vector3(x - 1.4, 0.95, 0.0), 40.0)
	_cam("Cam_Acorn_Close", Vector3(x + 0.2, 1.0, 4.6), Vector3(x + 0.2, 0.45, 2.2), 45.0)


func _checkpoint(x: float) -> void:
	_obj("Checkpoint", Vector3(x - 1.2, 0, 0), {}, 0.0, "Checkpoint_A")
	_obj("Checkpoint", Vector3(x + 3.8, 0, -1.5), {}, 0.0, "Checkpoint_B")
	_obj("LostPage", Vector3(x + 1.6, 0, 1.0), {"page_index": 2, "world_id": "W1"}, 0.0, "Page_A")
	_cam("Cam_Checkpoint", Vector3(x + 0.8, 1.8, 6.5), Vector3(x + 0.8, 1.0, 0.0))
	_cam("Cam_Checkpoint_Close", Vector3(x - 1.2, 1.5, 3.2), Vector3(x - 1.2, 1.1, 0.0), 45.0)
	_cam("Cam_Page_Close", Vector3(x + 1.6, 1.3, 3.0), Vector3(x + 1.6, 1.1, 1.0), 40.0)
	_obj("SignPost", Vector3(x + 7.5, 0, 0), {"board_text": "Mak Manor", "lines": PackedStringArray(["To Mak Manor."])}, 0.0, "Sign_A")
	_cam("Cam_Sign_Front", Vector3(x + 7.5, 1.6, 3.4), Vector3(x + 7.5, 1.4, 0.0), 45.0)
	_cam("Cam_Sign_Back", Vector3(x + 7.5, 1.6, -3.4), Vector3(x + 7.5, 1.4, 0.0), 45.0)


func _crates(x: float) -> void:
	_obj("BreakableCrate", Vector3(x - 1.3, 0, 0), {"acorns": 3}, 15.0, "Crate_A")
	_obj("BreakableCrate", Vector3(x + 1.3, 0, 0), {"acorns": 2}, -10.0, "Crate_B")
	_obj("BreakableCrate", Vector3(x + 1.3, 1.0, 0), {"acorns": 0}, 30.0, "Crate_C")
	_cam("Cam_Crate", Vector3(x, 1.8, 6.0), Vector3(x, 0.8, 0.0))


func _npcs(x: float) -> void:
	var specs := [
		["Bramwell", null, 1.0, "Good evening, Master Mak."],
		["Pip", C + "pip/pip.glb", 1.36, "Cousin! The wolf blew my straw house away!"],
		["Hazel", C + "hazel/hazel.glb", 1.0, "My sticks went flying."],
		["Bertram", C + "bertram/bertram.glb", 1.0, "Bricks, cousin. Always bricks."],
		["Jack", C + "jack/jack.glb", 1.0, "Have you seen my beans?"],
		["Snap", C + "sergeant_snap/sergeant_snap.glb", 1.0, "Halt! Who goes there?"],
		["Goose", C + "golden_goose/golden_goose.glb", 1.2, "Honk."],
		["Sheep", C + "real_sheep/real_sheep.glb", 1.0, "Baa."],
		["Daisy", C + "daisy_cow/daisy_cow.glb", 1.0, "Moo."],
	]
	for i in specs.size():
		var s: Array = specs[i]
		var props := {"speaker": s[0], "lines": PackedStringArray([s[3]]), "talk_radius": 1.6}
		if s[1] != null:
			props["visual_scene"] = _glb(s[1])
			props["visual_scale"] = s[2]
		_obj("NPCTalker", Vector3(x + i * 2.2, 0, 0), props, 0.0, "NPC_" + s[0])
	var mid := x + (specs.size() - 1) * 1.1
	_cam("Cam_NPCs", Vector3(mid, 2.4, -9.5), Vector3(mid, 0.7, 0.0), 55.0)
	_cam("Cam_NPC_Close", Vector3(x + 1.1, 1.3, -3.6), Vector3(x + 1.1, 0.8, 0.0), 45.0)
	_cam("Cam_Hazel_Close", Vector3(x + 4.4 + 0.5, 0.95, -1.9), Vector3(x + 4.4, 0.62, 0.0), 40.0)
	_cam("Cam_NPC_Cousins", Vector3(x + 3.3, 1.9, -5.4), Vector3(x + 3.3, 0.5, 0.0), 50.0)


func _door(x: float) -> void:
	# Exactly as the hub places it (flip off, scale 1.2), including the hub's reparent of Visual under Hinge.
	var d := _obj("WolfDoor", Vector3(x, 0, 0), {"visual_scene": _glb(P + "hub/wolf_door/wolf_door.glb"), "visual_scale": 1.2,
		"visual_flip_180": false, "required_truffles": 99, "width": 2.4, "height": 3.8, "route_on_enter": false}, 0.0, "WolfDoor")
	var vis := d.get_node_or_null("Visual") as Node3D
	var hinge := d.get_node_or_null("Hinge") as Node3D
	if vis and hinge:
		vis.reparent(hinge, true)
	# The hub's chains and "12" padlock (a "Chains" child of the door), so the door's lock drop is verified here.
	var lock := Node3D.new()
	lock.name = "Chains"
	d.add_child(lock)
	var iron := ObjSvc.mat(ObjSvc.IRON, 0.4, 0.85)
	for diag in [[Vector3(-1.2, 0.4, 0.45), Vector3(1.2, 3.5, 0.45)], [Vector3(1.2, 0.4, 0.45), Vector3(-1.2, 3.5, 0.45)]]:
		var a: Vector3 = diag[0]
		var bb: Vector3 = diag[1]
		for i in 16:
			var p := a.lerp(bb, (float(i) + 0.5) / 16.0)
			var link := ObjSvc.torus(lock, 0.05, 0.1, iron, p, Vector3(90 if i % 2 == 0 else 0, 0, rad_to_deg(atan2(bb.y - a.y, bb.x - a.x))))
			link.name = "Link"
	ObjSvc.soft_box(lock, Vector3(0.5, 0.44, 0.18), ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.8), Vector3(0, 1.95, 0.55), Vector3.ZERO, 0.08)
	var lab := ObjSvc.label(lock, "12", Vector3(0, 1.93, 0.65), 90, Color("3b2416"), false)
	lab.outline_size = 0
	_cam("Cam_Door", Vector3(x + 1.5, 2.2, 7.5), Vector3(x, 1.7, 0.0))
	_cam("Cam_Door_Oblique", Vector3(x + 3.2, 1.9, 3.6), Vector3(x - 0.3, 1.7, -0.4), 60.0)
	_cam("Cam_Door_Side", Vector3(x + 5.0, 2.5, 3.5), Vector3(x, 1.5, -0.5))


func _portal(x: float) -> void:
	var lectern := _glb(P + "hub/book_lectern/book_lectern.glb")
	_obj("StorybookPortal", Vector3(x - 2.0, 0, 0), {"world_id": "W1", "book_title": "The Three Little Pigs", "required_truffles": 0,
		"visual_scene": lectern, "visual_scale": 0.85, "scale_factor": 0.95, "route_on_enter": false}, 180.0, "Portal_Open")
	_obj("StorybookPortal", Vector3(x + 2.5, 0, 0), {"world_id": "W2", "book_title": "Jack and the Beanstalk", "required_truffles": 99,
		"cover_color": Color("3e9a45"), "page_glow": Color(0.75, 1.0, 0.6), "visual_scene": lectern, "visual_scale": 0.85,
		"scale_factor": 0.95, "route_on_enter": false}, 180.0, "Portal_Locked")
	_cam("Cam_Portal", Vector3(x, 2.8, 6.0), Vector3(x, 1.6, 0.0))
	_cam("Cam_Portal_Close", Vector3(x - 2.0, 3.3, 2.3), Vector3(x - 2.0, 2.1, 0.0), 45.0)


func _cage(x: float) -> void:
	_obj("BouncePad", Vector3(x - 5.0, 0, 0), {"look": 1, "radius": 1.0}, 0.0, "Pad_Gumdrop")
	var hay := _glb(P + "w1/hay_bale/hay_bale.glb")
	var hp := {"look": 0, "radius": 1.1}
	if hay:
		hp["visual_scene"] = hay
		hp["visual_scale"] = 1.2
	_obj("BouncePad", Vector3(x - 2.4, 0, 0), hp, 0.0, "Pad_Hay")
	_obj("SlamSwitch", Vector3(x + 0.6, 0, 2.2), {}, 0.0, "Switch_1")
	_obj("SlamSwitch", Vector3(x + 4.6, 0, 2.2), {}, 0.0, "Switch_2")
	var sw: Array[NodePath] = [NodePath("../Switch_1"), NodePath("../Switch_2")]
	var cage_props := {"radius": 1.45, "height": 3.4, "switches": sw}
	var cs := _glb(P + "w2/goose_cage/goose_cage.glb")
	if cs:
		cage_props["visual_scene"] = cs
		cage_props["visual_scale"] = 1.4
	var ps := load(O + "Cage.tscn") as PackedScene
	var cage := ps.instantiate() as Node3D
	for k in cage_props.keys():
		cage.set(k, cage_props[k])
	cage.name = "Cage"
	cage.position = Vector3(x + 2.6, 0, 0)
	var contents := cage.get_node_or_null("Contents") as Node3D
	if contents == null:
		contents = Node3D.new()
		contents.name = "Contents"
		cage.add_child(contents)
	var goose := _glb(C + "golden_goose/golden_goose.glb")
	if goose:
		var g := goose.instantiate() as Node3D
		g.name = "Goose"
		g.scale = Vector3.ONE * 1.55
		g.position = Vector3(0, 0.3, 0)
		contents.add_child(g)
	var jack := _glb(C + "jack/jack_v2.glb")
	if jack:
		var jk := jack.instantiate() as Node3D
		jk.name = "Jack"
		jk.position = Vector3(0.75, 0.05, 0.35)
		jk.rotation.y = 0.3
		contents.add_child(jk)
	add_child(cage)
	nodes["Cage"] = cage
	_cam("Cam_Cage", Vector3(x, 2.6, 8.5), Vector3(x, 1.2, 0.0))
	_cam("Cam_Cage_Close", Vector3(x + 3.4, 1.4, 4.2), Vector3(x + 3.2, 1.0, 0.2), 42.0)
	_cam("Cam_Pad_Close", Vector3(x - 3.7, 1.4, 4.0), Vector3(x - 3.7, 0.7, 0.0), 45.0)


func _wind(x: float) -> void:
	var wz := _obj("WindZone", Vector3(x + 2.0, 0, 0), {"size": Vector3(6, 3, 3), "direction": Vector3(1, 0, 0), "strength": 6.0}, 0.0, "Wind")
	# Swap list #6 (Docs/ASSETS_TOPUP.md): the current bellows is v5 (its _busted twin is picked up automatically).
	var bel := _glb(P + "w1/bellows_machine_v5/bellows_machine_v5.glb")
	if bel == null:
		bel = _glb(P + "w1/bellows_machine_v3/bellows_machine_v3.glb")
	var bp := {"wind_zone_path": NodePath("../Wind")}
	if bel:
		bp["visual_scene"] = bel
		bp["visual_scale"] = 0.75
	_obj("BellowsMachine", Vector3(x - 2.0, 0, 0), bp, -90.0, "Bellows")
	_cam("Cam_Wind", Vector3(x, 2.2, 7.5), Vector3(x, 1.0, 0.0))
	if wz:
		pass


func _dig(x: float) -> void:
	_obj("BuriedTreasure", Vector3(x, 0, 0), {"truffle_id": "SHOW-DIG", "proximity_fallback": false}, 0.0, "Buried")
	_cam("Cam_Dig", Vector3(x + 0.6, 2.4, 6.0), Vector3(x, 0.6, 0.0))
	_cam("Cam_Dig_Close", Vector3(x + 0.4, 1.6, 3.4), Vector3(x, 0.4, 0.0), 45.0)


## Sky: vanishing clouds over a pale cloud sea and a trial ring, under the W2 environment (tell, vanish, return).
func _sky(x: float) -> void:
	var sea := ObjSvc.add_mesh(self, PlaneMesh.new(), ObjSvc.mat(Color(0.97, 0.97, 1.0), 0.9), Vector3(x, 0.02, 0))
	(sea.mesh as PlaneMesh).size = Vector2(14, 14)
	sea.name = "CloudSea"
	for i in 3:
		_obj("VanishingCloud", Vector3(x - 3.0 + i * 3.2, 1.2 + i * 0.4, 0), {"size": Vector3(2.6, 0.9, 2.6), "vanish_delay": 0.25,
			"respawn_time": 3.0}, 0.0, "Cloud_%d" % i)
	_obj("TrialRing", Vector3(x + 1.0, 3.6, -2.5), {"radius": 1.1}, 0.0, "SkyRing")
	_cam("Cam_Sky", Vector3(x, 4.6, 8.0), Vector3(x, 1.6, 0.0), 55.0)


## Stand-in Ham Slam: a hop up, a hang, and a drop onto `at`, then `f` (the same call the player's slam makes).
func _hop_slam(t: float, at: Vector3, f: Callable) -> void:
	_at(t, func() -> void:
		var tw := create_tween()
		tw.tween_property(mak, "global_position", at + Vector3(0, 1.6, 0), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.18)
		tw.tween_property(mak, "global_position", at, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(f))


# ------------------------------------------------------------------ demo timelines

func _build_demo(station: String) -> void:
	var x: float = STATIONS.get(station, 0.0)
	match station:
		"pickups":
			_walk(Vector3(x - 4.5, 0, 2.2), Vector3(x + 3.5, 0, 2.2), 1.0, 4.0)
			_walk(Vector3(x + 3.5, 0, 2.2), Vector3(x + 3.5, 0, -3.0), 4.1, 4.9)
			_walk(Vector3(x + 3.5, 0, -3.0), Vector3(x - 1.4, 0, -3.0), 4.9, 6.2)
			_walk(Vector3(x - 1.4, 0, -3.0), Vector3(x - 1.4, 0, -0.2), 6.3, 7.3)
		"checkpoint":
			_walk(Vector3(x - 4.0, 0, 1.0), Vector3(x - 1.2, 0, 0.6), 0.8, 2.2)
			_walk(Vector3(x - 1.2, 0, 0.6), Vector3(x + 1.6, 0, 1.0), 3.6, 5.0)
			_walk(Vector3(x + 1.6, 0, 1.0), Vector3(x + 3.8, 0, -1.2), 6.0, 7.2)
		"crate":
			mak.global_position = Vector3(x - 2.6, 0, 0.6)
			_at(1.5, func() -> void: (nodes["Crate_A"] as Node).call("hit_by_player", "punch", Vector3(x - 2.6, 0.6, 0.0)))
			_at(3.0, func() -> void: (nodes["Crate_B"] as Node).call("hit_by_player", "slam", Vector3(x + 1.3, 2.0, 0.0)))
			_at(3.6, func() -> void: (nodes["Crate_C"] as Node).call("hit_by_player", "kick", Vector3(x + 2.6, 1.2, 0.0)))
		"npcs":
			var x1: float = STATIONS["npcs"]
			_walk(Vector3(x1 - 3.0, 0, -1.3), Vector3(x1 + 19.0, 0, -1.3), 1.0, 15.0)
			_at(2.6, func() -> void: (nodes["NPC_Bramwell"] as Node).call("talk"))
			_at(4.4, func() -> void: (nodes["NPC_Pip"] as Node).call("talk"))
		"door":
			_walk(Vector3(x + 1.0, 0, 7.0), Vector3(x, 0, 2.2), 0.5, 2.0)
			_at(3.2, func() -> void: (nodes["WolfDoor"] as Node).set("required_truffles", 0))
			_walk(Vector3(x, 0, 2.2), Vector3(x + 1.0, 0, 6.0), 3.0, 3.8)
			_walk(Vector3(x + 1.0, 0, 6.0), Vector3(x, 0, 1.8), 6.0, 7.2)
			_walk(Vector3(x, 0, 1.8), Vector3(x, 0, -3.0), 9.0, 10.5)
		"portal":
			_at(2.0, func() -> void: (nodes["Portal_Locked"] as Node).set("required_truffles", 0))
		"cage":
			_at(1.0, func() -> void: (nodes["Pad_Gumdrop"] as Node).call("squash"))
			_at(1.8, func() -> void: (nodes["Pad_Hay"] as Node).call("squash"))
			_at(3.0, func() -> void: (nodes["Switch_1"] as Node).call("press"))
			_at(4.5, func() -> void: (nodes["Switch_2"] as Node).call("press"))
		"wind":
			_walk(Vector3(x + 0.5, 0, 4.0), Vector3(x + 0.5, 0, 0.0), 1.0, 2.5)
			_at(6.0, func() -> void: (nodes["Bellows"] as Node).call("hit_by_player", "slam", mak.global_position))
		"sky":
			# Mak hops onto each cloud in turn (the sensor reads the stand-in), then flies through the ring.
			for i in 3:
				var cpos: Vector3 = (nodes["Cloud_%d" % i] as Node3D).global_position
				_at(1.0 + i * 1.6, func() -> void:
					var tw := create_tween()
					tw.tween_property(mak, "global_position", cpos + Vector3(0, 0.05, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
			_at(6.2, func() -> void:
				var tw := create_tween()
				var rp: Vector3 = (nodes["SkyRing"] as Node3D).global_position
				tw.tween_property(mak, "global_position", rp + Vector3(0, -0.6, 1.5), 0.3)
				tw.tween_property(mak, "global_position", rp + Vector3(0, -0.6, -1.5), 0.4))
		"cage_close":
			_walk(Vector3(STATIONS["cage"] + 7.0, 0, 4.0), Vector3(STATIONS["cage"] + 3.6, 0, 1.9), 0.5, 3.0)
			_at(5.0, func() -> void: (nodes["Switch_1"] as Node).call("press"))
			_at(6.0, func() -> void: (nodes["Switch_2"] as Node).call("press"))
		"dig":
			var bt := nodes["Buried"] as Node
			_walk(Vector3(x - 3.5, 0, 0.4), Vector3(x - 0.8, 0, 0.4), 0.6, 1.6)
			# Slam before sniffing: only a mud splash and a wobble.
			_hop_slam(1.8, Vector3(x - 0.3, 0, 0.3), func() -> void: bt.call("_on_slam", mak))
			# The player's sniff reaches the patch: it calls on_sniffed(self).
			_at(3.4, func() -> void: bt.call("on_sniffed", mak))
			_hop_slam(5.0, Vector3(x - 0.3, 0, 0.3), func() -> void: bt.call("_on_slam", mak))
			_walk(Vector3(x - 0.3, 0, 0.3), Vector3(x + 0.2, 0, 0.0), 7.4, 8.2)
