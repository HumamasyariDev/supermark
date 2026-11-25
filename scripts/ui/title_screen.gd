extends Node3D
## Title screen: the Grand Library hub seen through its TitleCam (a slow drifting dolly) with the
## real Mr. Mak model on the rug, the SUPER MAK 64 logo, "press any key", then the main menu
## (Continue, New Game, Settings, Quit). Falls back to the pop-up storybook diorama when
## res://scenes/hub/Hub.tscn does not exist. --title-diorama forces the diorama.

const LOGO_PATH := "res://assets/ui/logo.png"
const TOON := "res://assets/shaders/toon.gdshader"
const SETTINGS_SCENE := "res://scenes/ui/SettingsMenu.tscn"
const HUB_SCENE := "res://scenes/hub/Hub.tscn"
const MAK_MODELS := ["res://scenes/player/MakModel.tscn", "res://assets/characters/mak/mak_v2.glb", "res://assets/characters/mak/mak.glb", "res://assets/characters/mr_mak/mr_mak.glb", "res://assets/characters/mak/mr_mak.glb"]
const WOLF_MODELS := ["res://assets/characters/wolf_boss/wolf_boss.glb"]

## "press" -> "menu" -> "settings" / "confirm"
var state := "press"
var _t := 0.0
var _cam: Camera3D
var _spinners: Array[Node3D] = []
var _bobbers: Array = []
var _sails: Node3D
var _clouds: Array[Node3D] = []
var _ui: Control
var _logo: Control
var _press: Label
var _menu: VBoxContainer
var _menu_card: PanelContainer
var _confirm: PanelContainer
var _settings: Control
var _continue_btn: StoryButton
var _footer: Label
var _hub_cam: Camera3D
var _hub_cam_base := Transform3D()
var _mak: Node3D
var _mak_base := Vector3.ZERO
var _mak_skel: Skeleton3D
## Owner fix 2026-10-19 (title pose): the old MAK_POSE turned night-01 bones in their local axes, which on the hero v2
## rig (MakModel.tscn) folded both arms behind the back. The title now poses Mak through the player's rig adapter
## (MakRigAdapters.Skel, character-space angles, A-pose arms corrected to hang down) with MakAnimator's idle values.
var _mak_rig: MakRigAdapters.Skel
var _mak_lids := [-1, -1]
var _mak_lid_rest := [Quaternion.IDENTITY, Quaternion.IDENTITY]
## Seconds per title idle loop; the friendly wave plays once per loop (WAVE_IN..WAVE_OUT).
const MAK_LOOP := 6.0
const WAVE_IN := 1.2
const WAVE_OUT := 3.6
var _logo_k := 0.0
var _logo_squash := 0.0
var _prompt: UIPrompts
var _hub_root: Node
## 1 = full storybook dolly, eases toward 0 (the clear TitleCam pose) while a pillar blocks Mr. Mak.
var _dolly_w := 1.0
var _confirm_kind := "new"
var _confirm_title: Label
var _confirm_sub: Label
var _confirm_yes: StoryButton
var _confirm_no: StoryButton
## Mr. Mak's on-screen height on the title at 1080p (art director: at least 260 px, the hero of the frame).
const MAK_TITLE_PX := 320.0
## Small props closer than this to the title camera hide (they blur into blobs).
const NEAR_CULL_M := 4.5
const LOGO_GLINT := "res://scenes/ui/shaders/logo_glint.gdshader"


func _enter_tree() -> void:
	add_to_group("title_screen")
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("set_title_active"):
		ui.call("set_title_active", true)


func _ready() -> void:
	var dev0 := get_node_or_null("/root/Dev")
	var force_diorama: bool = dev0 != null and dev0.has_method("has_arg") and dev0.has_arg("title-diorama")
	if force_diorama or not _build_hub_backdrop():
		_build_world()
	_build_ui()
	if has_meta("from_intro"):
		# Owner fix 5: the intro splash hands its finished logo over in place, so no second logo pop.
		_logo_k = 1.0
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_music("music_title")
	var ui := get_node_or_null("/root/UI")
	if ui:
		ui.set_gameplay(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("arg"):
		match dev.arg("title-state", ""):
			"menu":
				_show_menu(true)
			"settings":
				_show_menu(true)
				_open_settings()
			"confirm":
				_show_menu(true)
				_show_confirm()
			"quit":
				_show_menu(true)
				_show_confirm("quit")


# ---------------------------------------------------------------- 3D diorama

func _mat(col: Color, rough: float = 0.8, emissive: float = 0.0) -> Material:
	if ResourceLoader.exists(TOON):
		var sm := ShaderMaterial.new()
		sm.shader = load(TOON)
		sm.set_shader_parameter("albedo", col)
		if emissive > 0.0:
			sm.set_shader_parameter("emission_color", col)
			sm.set_shader_parameter("emission_energy", emissive)
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive
	return m


func _mesh(mesh: Mesh, col: Color, pos: Vector3, parent: Node3D = null, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	(parent if parent else self).add_child(mi)
	return mi


func _sphere(r: float, h: float = -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = 32
	s.rings = 16
	return s


func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


func _cyl(top: float, bottom: float, h: float, segs: int = 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	return c


func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("2f6fd0")
	psm.sky_horizon_color = Color("a9d0f2")
	psm.ground_horizon_color = Color("ffe1b5")
	psm.ground_bottom_color = Color("d9c9ee")
	psm.ground_curve = 0.06
	psm.sun_angle_max = 30.0
	psm.sky_curve = 0.04
	psm.sky_energy_multiplier = 1.0
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color("ffd9b0")
	env.fog_density = 0.0015
	env.fog_aerial_perspective = 0.2
	env.fog_sky_affect = 0.12
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, -35, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("9fb8ff")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)

	var root := Node3D.new()
	root.name = "Diorama"
	add_child(root)
	# floating island under the book
	_mesh(_sphere(9.0, 7.0), Color("8a6a4a"), Vector3(0, -3.8, 0), root, Vector3.ZERO, Vector3(1, 0.7, 0.8))
	_mesh(_sphere(9.2, 2.4), Color("6fae4f"), Vector3(0, -1.2, 0), root, Vector3.ZERO, Vector3(1, 1, 0.82))
	# the open book: cover and two gently curved page blocks
	var book := Node3D.new()
	book.position = Vector3(0, -0.2, 0)
	root.add_child(book)
	_mesh(_box(Vector3(11.4, 0.3, 7.6)), Color("7a1f2b"), Vector3(0, 0, 0), book)
	_mesh(_box(Vector3(5.4, 0.6, 7.0)), Color("ecd9b0"), Vector3(-2.75, 0.4, 0), book, Vector3(0, 0, deg_to_rad(4)))
	_mesh(_box(Vector3(5.4, 0.6, 7.0)), Color("ecd9b0"), Vector3(2.75, 0.4, 0), book, Vector3(0, 0, deg_to_rad(-4)))
	_mesh(_cyl(0.35, 0.35, 7.0), Color("e8d9b6"), Vector3(0, 0.55, 0), book, Vector3(PI * 0.5, 0, 0))
	_mesh(_box(Vector3(0.25, 0.04, 5.0)), Color("c9a24a"), Vector3(1.5, 0.75, 1.0), book, Vector3(0, 0.2, -0.06))
	# pop-up hills on the pages
	var green := Color("7cc35a")
	_mesh(_sphere(2.0, 2.0), green, Vector3(-3.2, 0.7, 1.2), book, Vector3.ZERO, Vector3(1.0, 0.7, 0.9))
	_mesh(_sphere(1.6, 1.6), green.darkened(0.08), Vector3(-1.6, 0.7, -1.8), book, Vector3.ZERO, Vector3(1.1, 0.8, 0.9))
	_mesh(_sphere(1.9, 1.9), green.lightened(0.05), Vector3(3.3, 0.7, -1.4), book, Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
	# trees (smooth round canopies)
	for p in [Vector3(-4.2, 1.2, -1.8), Vector3(-0.9, 1.0, 2.4), Vector3(4.4, 1.2, 1.8), Vector3(2.0, 1.0, -2.6)]:
		var tree := Node3D.new()
		tree.position = p
		book.add_child(tree)
		_mesh(_cyl(0.12, 0.18, 1.2), Color("7a5232"), Vector3(0, 0.6, 0), tree)
		var c := _mesh(_sphere(0.75), Color("4f9a3c"), Vector3(0, 1.5, 0), tree)
		_mesh(_sphere(0.5), Color("5fb04a"), Vector3(0.35, 1.9, 0.1), tree)
		_bobbers.append({"n": c, "base": c.position, "ph": p.x})
	# straw house (left) and brick house (right)
	var straw := Node3D.new()
	straw.position = Vector3(-2.6, 0.95, -0.2)
	straw.rotation.y = 0.4
	book.add_child(straw)
	_mesh(_box(Vector3(1.4, 1.1, 1.2)), Color("e8c95a"), Vector3(0, 0.55, 0), straw)
	_mesh(_cyl(0.0, 1.05, 1.0, 4), Color("d9a93f"), Vector3(0, 1.6, 0), straw, Vector3(0, PI * 0.25, 0))
	_mesh(_box(Vector3(0.4, 0.6, 0.05)), Color("7a5232"), Vector3(0, 0.3, 0.61), straw)
	var brick := Node3D.new()
	brick.position = Vector3(2.4, 0.95, 0.6)
	brick.rotation.y = -0.5
	book.add_child(brick)
	_mesh(_box(Vector3(1.6, 1.3, 1.3)), Color("b5462e"), Vector3(0, 0.65, 0), brick)
	_mesh(_cyl(0.0, 1.2, 0.9, 4), Color("5a3a22"), Vector3(0, 1.75, 0), brick, Vector3(0, PI * 0.25, 0))
	_mesh(_box(Vector3(0.3, 0.7, 0.3)), Color("8e3a26"), Vector3(0.45, 2.0, 0), brick)
	_mesh(_box(Vector3(0.35, 0.35, 0.05)), Color("ffd27a"), Vector3(-0.4, 0.8, 0.66), brick)
	# windmill on the back hill with turning sails
	var mill := Node3D.new()
	mill.position = Vector3(3.3, 1.6, -2.0)
	book.add_child(mill)
	_mesh(_cyl(0.35, 0.6, 2.2), Color("f2e6cf"), Vector3(0, 1.1, 0), mill)
	_mesh(_cyl(0.0, 0.5, 0.7), Color("7a1f2b"), Vector3(0, 2.55, 0), mill)
	_sails = Node3D.new()
	_sails.position = Vector3(0, 1.9, 0.5)
	mill.add_child(_sails)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = i * PI * 0.5
		_sails.add_child(arm)
		_mesh(_box(Vector3(0.28, 1.3, 0.04)), Color("fff7e6"), Vector3(0, 0.75, 0), arm)
	# the wolf's red door in the distance (a hint of the villain)
	_mesh(_box(Vector3(0.9, 1.6, 0.2)), Color("8e1f2f"), Vector3(-4.6, 1.0, -2.9), book, Vector3(0, 0.5, 0))
	# pop-up characters (only when the meshes exist): the wolf looms behind the straw house,
	# Mr. Mak stands on the right page, ready to leap in.
	var wolf := _place_model(WOLF_MODELS, book, Vector3(-1.0, 0.72, -2.3), 3.0, 0.35)
	if wolf:
		_bobbers.append({"n": wolf, "base": wolf.position, "ph": 2.0, "amp": 0.05})
	var mak := _place_model(MAK_MODELS, book, Vector3(1.0, 0.72, 1.9), 1.25, -0.25)
	if mak:
		_bobbers.append({"n": mak, "base": mak.position, "ph": 0.0, "amp": 0.08})
	# floating golden truffles
	for i in 5:
		var tr := Node3D.new()
		var a := TAU * i / 5.0
		tr.position = Vector3(cos(a) * 6.5, 2.4 + (i % 2) * 1.2, sin(a) * 4.8)
		root.add_child(tr)
		var gold := Color("f2b632")
		var body := _mesh(_sphere(0.42), gold, Vector3.ZERO, tr)
		body.material_override = _mat(gold, 0.3, 0.35)
		for b in [Vector3(0.25, 0.15, 0.1), Vector3(-0.22, 0.1, 0.18), Vector3(0.05, -0.2, -0.24), Vector3(-0.1, 0.28, -0.12)]:
			var bump := _mesh(_sphere(0.24), gold, b, tr)
			bump.material_override = body.material_override
		_spinners.append(tr)
		_bobbers.append({"n": tr, "base": tr.position, "ph": float(i)})
	# clouds
	for i in 7:
		var cl := Node3D.new()
		var a := TAU * i / 7.0 + 0.3
		cl.position = Vector3(-30.0 + i * 10.0, 2.0 + (i % 3) * 3.0, -26.0 - (i % 2) * 8.0)
		cl.scale = Vector3.ONE * (1.6 + (i % 2) * 0.6)
		root.add_child(cl)
		for k in 4:
			var cm := _mesh(_sphere(0.9 + 0.3 * (k % 2)), Color("fffaf2"), Vector3(k * 0.9 - 1.3, (k % 2) * 0.4, 0), cl)
			cm.material_override = _mat(Color("fffaf2"), 1.0, 0.15)
		_clouds.append(cl)
	# a sea of clouds far below the island
	var sea_mat := _mat(Color("fff4ec"), 1.0, 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	for i in 46:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(12.0, 46.0)
		var puff := _mesh(_sphere(rng.randf_range(2.5, 5.5)), Color("fff4ec"), Vector3(cos(a) * rr, rng.randf_range(-13.0, -10.0), sin(a) * rr - 6.0), root, Vector3.ZERO, Vector3(1.4, 0.55, 1.2))
		puff.material_override = sea_mat
	# drifting gold motes
	var motes := CPUParticles3D.new()
	motes.amount = 90
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(10, 3, 7)
	motes.direction = Vector3(0, 1, 0)
	motes.spread = 40.0
	motes.gravity = Vector3(0, 0.15, 0)
	motes.initial_velocity_min = 0.2
	motes.initial_velocity_max = 0.6
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.2
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mm.albedo_color = Color(1.0, 0.85, 0.4)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.8, 0.3)
	mm.emission_energy_multiplier = 2.0
	qm.material = mm
	motes.mesh = qm
	motes.position = Vector3(0, 2.5, 0)
	root.add_child(motes)
	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _build_hub_backdrop() -> bool:
	if not ResourceLoader.exists(HUB_SCENE):
		return false
	var ps := load(HUB_SCENE) as PackedScene
	if ps == null:
		return false
	var hub := ps.instantiate() as Node3D
	if hub == null:
		return false
	# A backdrop, not a playable WorldRoot: no player, banner, gameplay HUD or visit bookkeeping.
	hub.set_script(null)
	hub.name = "HubBackdrop"
	hub.set_meta("title_backdrop", true)
	hub.add_to_group("title_backdrop")
	# critique UI r1 blocker: on a fresh profile the hub's EV_intro_wolf ran behind the logo, cut to the Wolf and
	# forced the gameplay HUD on. The hub reads its story flags synchronously in _ready, so a transient (never saved)
	# "hub_intro_seen" covers exactly the build; New Game loads the real hub with the flag unset and the intro plays there.
	var game := get_node_or_null("/root/Game")
	var transient := game != null and game.has_method("set_transient_flag")
	if transient:
		game.call("set_transient_flag", "hub_intro_seen", true)
	add_child(hub)
	if transient:
		game.call("set_transient_flag", "hub_intro_seen", false)
	var cam := hub.get_node_or_null("StoryCams/TitleCam") as Camera3D
	if cam == null:
		cam = hub.find_child("TitleCam", true, false) as Camera3D
	if cam == null:
		cam = hub.find_child("StoryCam_A", true, false) as Camera3D
	if cam == null:
		hub.queue_free()
		return false
	cam.make_current()
	_hub_cam = cam
	_cam = cam
	# Mr. Mak (the real rigged GLB) stands on the rug in the right third of the frame, facing us.
	var floor_pt := _floor_point(cam, Vector2(0.74, 0.83))
	if floor_pt != Vector3.INF:
		# critique UI r1 (art director): Mak read as a 170 px prop beside the orrery. Dolly the title camera
		# along its ray to Mak's chest (his screen spot stays put) until he stands MAK_TITLE_PX tall at 1080p.
		var chest := floor_pt + Vector3(0, 1.0, 0)
		var vs := get_viewport().get_visible_rect().size
		var px := cam.unproject_position(floor_pt).distance_to(cam.unproject_position(floor_pt + Vector3(0, 1.92, 0))) * 1080.0 / maxf(1.0, vs.y)
		if px > 1.0 and px < MAK_TITLE_PX:
			var d := cam.global_position.distance_to(chest)
			var nd := maxf(3.2, d * px / MAK_TITLE_PX)
			cam.global_position = chest + (cam.global_position - chest).normalized() * nd
		var to_cam := cam.global_position - floor_pt
		_mak = _place_model(MAK_MODELS, hub, floor_pt, 1.2 * 1.6, atan2(to_cam.x, to_cam.z))
		if _mak:
			_mak_base = _mak.position
			_mak_skel = _mak.find_children("*", "Skeleton3D", true, false).front() if not _mak.find_children("*", "Skeleton3D", true, false).is_empty() else null
			_setup_mak_rig()
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.82, 0.55)
			glow.light_energy = 1.6
			glow.omni_range = 4.0
			glow.position = floor_pt + Vector3(0, 2.2, 0) + to_cam.normalized() * 1.2
			hub.add_child(glow)
	_hub_cam_base = cam.global_transform
	_hide_hub_chatter(hub)
	# the closer title camera put small props (pickups, dust motes) within a few metres of the lens, where they
	# read as large blurred blobs (critique UI r1). Small things that close to the camera hide on the title.
	for delay in [0.1, 1.0, 3.0]:
		get_tree().create_timer(delay).timeout.connect(_cull_near_props)
	return true


func _cull_near_props() -> void:
	if _hub_root == null or not is_instance_valid(_hub_root) or _hub_cam == null:
		return
	var eye := _hub_cam_base.origin
	var fwd := -_hub_cam_base.basis.z
	for n in _hub_root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.visible or gi == _mak or (_mak and _mak.is_ancestor_of(gi)):
			continue
		var box := gi.global_transform * gi.get_aabb()
		if box.size.length() > 1.6:
			continue
		var to := box.get_center() - eye
		if to.dot(fwd) > 0.0 and to.length() < NEAR_CULL_M:
			gi.visible = false


## Hub speech bubbles, barks and plinth labels are for gameplay; the title keeps the frame clean.
## critique UI r1: the wolf's bark drew across the logo, so every Label3D under the hub hides,
## including ones the hub adds later (timed barks), and the "title_hide" group lets the hub opt
## any other node out of the title frame.
func _hide_hub_chatter(hub: Node) -> void:
	_hub_root = hub
	for n in hub.find_children("*", "Label3D", true, false):
		(n as Label3D).visible = false
	for n in get_tree().get_nodes_in_group("title_hide"):
		if n is Node3D:
			(n as Node3D).visible = false
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if _hub_root == null or not is_instance_valid(_hub_root):
		return
	if (n is Label3D or n.is_in_group("title_hide")) and _hub_root.is_ancestor_of(n):
		_hide_later.call_deferred(n)


func _hide_later(n: Node) -> void:
	if is_instance_valid(n) and n is Node3D:
		(n as Node3D).visible = false


func _exit_tree() -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("set_title_active"):
		ui.call("set_title_active", false)
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## True when the line from the camera to Mr. Mak (head and waist) is blocked by level geometry.
func _mak_blocked(from: Vector3) -> bool:
	if _mak == null:
		return false
	var space := get_world_3d().direct_space_state
	for h in [1.6, 0.8]:
		var to := _mak.global_position + Vector3(0, h, 0)
		var q := PhysicsRayQueryParameters3D.create(from, to.lerp(from, 0.06))
		q.collision_mask = 0xFFFFFFFF
		if not space.intersect_ray(q).is_empty():
			return true
	return false


func _setup_mak_rig() -> void:
	if _mak_skel == null or _mak == null or _mak_skel.find_bone("arm_l") < 0:
		return
	# MakAnimator's character space faces -Z; the GLB (and the holder, turned to the camera) faces +Z.
	var frame := Node3D.new()
	frame.name = "CharFrame"
	frame.rotation.y = PI
	_mak.add_child(frame)
	_mak_rig = MakRigAdapters.Skel.new(_mak_skel, frame, MakAnimator.JOINTS)
	for i in 2:
		var bi := _mak_skel.find_bone("eyelid_l" if i == 0 else "eyelid_r")
		_mak_lids[i] = bi
		if bi >= 0:
			_mak_lid_rest[i] = _mak_skel.get_bone_rest(bi).basis.get_rotation_quaternion()


func _mak_joint(j: String, deg: Vector3, stretch_y: float = 1.0) -> void:
	var b := Basis.from_euler(deg * (PI / 180.0))
	if stretch_y != 1.0:
		b = b * Basis.from_scale(Vector3(1.0, stretch_y, 1.0))
	_mak_rig.set_joint(j, b, Vector3.ZERO)


func _pose_mak() -> void:
	if _mak_rig == null:
		return
	# MakAnimator's idle (loose-hang arm set plus its ARM_ABD 12 degrees, breathing, weight shift, head drift), then once per
	# loop a friendly wave with Mak's right hoof: the arm rises out to the side, the hoof waves with a lagging forearm,
	# the head tilts toward it and the body leans a touch away. Character-space degrees (X right, Y up, -Z forward).
	var breath := sin(_t * 2.3)
	var shift := sin(_t * 0.85)
	var lt := fmod(_t, MAK_LOOP)
	var up := clampf((lt - WAVE_IN) / 0.45, 0.0, 1.0)
	var down := clampf((lt - (WAVE_OUT - 0.5)) / 0.5, 0.0, 1.0)
	var w := up * up * (3.0 - 2.0 * up) * (1.0 - down * down * (3.0 - 2.0 * down))
	var flap := sin((lt - WAVE_IN) * 11.0) * w
	var flap_lag := sin((lt - WAVE_IN) * 11.0 - 0.9) * w
	var hang_x := 3.0 + 2.5 * breath
	var hang_z := 38.0 + 2.0 * breath
	_mak_joint("arm_l", Vector3(hang_x, 0.0, -hang_z))
	_mak_joint("forearm_l", Vector3(12.0, 0.0, 0.0))
	_mak_joint("arm_r", Vector3(lerpf(hang_x, -28.0, w), 0.0, lerpf(hang_z, 145.0, w) + 12.0 * flap))
	_mak_joint("forearm_r", Vector3(lerpf(12.0, 16.0, w), 0.0, 24.0 * flap_lag))
	_mak_joint("spine", Vector3(-2.0 + 1.4 * breath, 0.0, 2.0 * shift + 4.0 * w), 1.0 + 0.026 * breath)
	_mak_joint("head", Vector3(3.0 + 2.6 * breath + 3.0 * w, 3.0 * sin(_t * 0.53) - 6.0 * w,
		-2.5 * shift + 2.0 * sin(_t * 0.71) - 9.0 * w))
	var ear := 4.0 * sin(_t * 1.9) + 6.0 * flap_lag
	_mak_joint("ear_l", Vector3(ear * 0.5, 0.0, ear))
	_mak_joint("ear_r", Vector3(-ear * 0.5, 0.0, -ear))
	_mak_joint("tail", Vector3(0.0, 14.0 * sin(_t * 2.2), 0.0))
	# Blink every few seconds, and a happy squint while waving.
	var bt := fmod(_t + 0.7, 3.7)
	var closed := 1.0 if bt < 0.12 else 0.35 * w
	for i in 2:
		var bi := int(_mak_lids[i])
		if bi >= 0:
			_mak_skel.set_bone_pose_rotation(bi, (_mak_lid_rest[i] as Quaternion) * Quaternion(Vector3.RIGHT, deg_to_rad(115.0 * closed)))


func _floor_point(cam: Camera3D, uv: Vector2) -> Vector3:
	var vs := get_viewport().get_visible_rect().size
	var from := cam.project_ray_origin(uv * vs)
	var dir := cam.project_ray_normal(uv * vs)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, 1)
	var hit := space.intersect_ray(q)
	if hit.has("position"):
		return hit["position"]
	if dir.y < -0.01:
		var t := -from.y / dir.y
		return from + dir * t
	return Vector3.INF


func _place_model(candidates: Array, parent: Node3D, pos: Vector3, height: float, yaw: float) -> Node3D:
	for path in candidates:
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var holder := Node3D.new()
		parent.add_child(holder)
		var inst := ps.instantiate() as Node3D
		if inst == null:
			holder.queue_free()
			continue
		holder.add_child(inst)
		var box := _aabb(inst, Transform3D.IDENTITY)
		if box.size.y > 0.001:
			var k := height / box.size.y
			inst.scale = Vector3.ONE * k
			inst.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)
		holder.position = pos
		holder.rotation.y = yaw
		return holder
	return null


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D:
		var b := t * (n as VisualInstance3D).get_aabb()
		out = b
		first = false
	for c in n.get_children():
		var cb := _aabb(c, t)
		if cb.size != Vector3.ZERO:
			out = cb if first else out.merge(cb)
			first = false
	return out


func _update_camera() -> void:
	var a := 0.45 + sin(_t * 0.12) * 0.3
	var dist := 18.0
	_cam.position = Vector3(sin(a) * dist, 7.5 + sin(_t * 0.3) * 0.4, cos(a) * dist)
	_cam.look_at(Vector3(0.0, 3.0, 0), Vector3.UP)
	# keep the diorama on the right half so the logo sits on the left
	_cam.h_offset = -5.2
	_cam.v_offset = 0.6


func _process(delta: float) -> void:
	_t += delta
	_logo_k = minf(1.0, _logo_k + delta * 1.4)
	if _logo:
		var lk := UIFx.elastic_out(_logo_k)
		_logo.pivot_offset = _logo.size * 0.5
		_logo_squash = move_toward(_logo_squash, 0.0, delta * 2.2)
		var sq := UIFx.pop(_logo_squash) * 0.07
		_logo.scale = Vector2.ONE * (lerpf(0.4, 1.0, lk) + sin(_t * 1.6) * 0.012) + Vector2(sq, -sq)
		_logo.rotation = sin(_t * 0.9) * 0.012 + (1.0 - lk) * -0.2
		_logo.modulate.a = clampf(_logo_k * 3.0, 0.0, 1.0)
	if _hub_cam:
		# slow storybook dolly around the TitleCam pose
		# critique UI r1 (exported build): the dolly drifted behind a pillar that hid Mr. Mak. Each frame
		# the full-strength pose is tested; while it is blocked the dolly eases back toward the clear base.
		var b := _hub_cam_base
		var off := b.basis.x * sin(_t * 0.13) * 0.9 + b.basis.y * sin(_t * 0.21) * 0.25
		var yaw := sin(_t * 0.13) * 0.035
		var blocked := _mak_blocked(b.origin + off)
		_dolly_w = move_toward(_dolly_w, 0.0 if blocked else 1.0, delta * (0.9 if blocked else 0.35))
		var w := _dolly_w * _dolly_w * (3.0 - 2.0 * _dolly_w)
		_hub_cam.global_transform = Transform3D(b.basis.rotated(Vector3.UP, yaw * w), b.origin + off * w)
		if _mak:
			_mak.position = _mak_base + Vector3(0, absf(sin(_t * 2.4)) * 0.04, 0)
			_mak.rotation.z = sin(_t * 2.4) * 0.025
			_pose_mak()
		if _press:
			_press.pivot_offset = _press.size * 0.5
			_press.scale = Vector2.ONE * (1.0 + 0.04 * sin(_t * 3.2))
			_press.text = "Press any button" if UIPrompts.device() == "gamepad" else "Press any key"
		return
	_update_camera()
	if _sails:
		_sails.rotation.z += delta * 0.9
	for s in _spinners:
		s.rotation.y += delta * 1.4
	for b in _bobbers:
		var n: Node3D = b["n"]
		n.position = b["base"] + Vector3(0, sin(_t * 1.6 + b["ph"]) * float(b.get("amp", 0.15)), 0)
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += sin(_t * 0.2 + i) * delta * 0.3
	if _press:
		_press.pivot_offset = _press.size * 0.5
		_press.scale = Vector2.ONE * (1.0 + 0.04 * sin(_t * 3.2))
		_press.text = "Press any button" if UIPrompts.device() == "gamepad" else "Press any key"


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UIStyle.theme()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	# soft left vignette so the logo reads over the sky
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.22, 0.08, 0.03, 0.32))
	gr.set_color(1, Color(0.22, 0.08, 0.03, 0.0))
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(0.62, 0.5)
	gt.width = 256
	gt.height = 8
	grad.texture = gt
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(grad)
	if ResourceLoader.exists(LOGO_PATH):
		var tr := TextureRect.new()
		tr.texture = load(LOGO_PATH)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(90, 70)
		tr.size = Vector2(860, 480)
		if ResourceLoader.exists(LOGO_GLINT):
			var gm := ShaderMaterial.new()
			gm.shader = load(LOGO_GLINT)
			tr.material = gm
		var tw := _LogoTwinkle.new()
		tw.set_anchors_preset(Control.PRESET_FULL_RECT)
		tw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.add_child(tw)
		_logo = tr
	else:
		_logo = _Logo.new()
		_logo.position = Vector2(80, 60)
		_logo.size = Vector2(900, 520)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_logo)
	_press = UIStyle.title_label("Press any key", 56)
	_press.position = Vector2(170, 760)
	_press.size = Vector2(740, 100)
	_press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_press.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var rb := _PressRibbon.new()
	rb.set_anchors_preset(Control.PRESET_FULL_RECT)
	rb.show_behind_parent = true
	rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_press.add_child(rb)
	_ui.add_child(_press)
	_footer = UIStyle.label("An original storybook adventure  •  night 01 build", 22, UIStyle.CREAM, false, 6, Color(0.2, 0.1, 0.05, 0.8))
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_footer.position = Vector2(40, 1030)
	_ui.add_child(_footer)
	# main menu card
	_menu_card = UIStyle.panel("parchment", 36)
	_menu_card.position = Vector2(230, 560)
	_menu_card.custom_minimum_size = Vector2(620, 0)
	_ui.add_child(_menu_card)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	_menu_card.add_child(_menu)
	var game := get_node_or_null("/root/Game")
	_continue_btn = _menu_button("Continue", _on_continue)
	_menu_button("New Game", _on_new_game)
	_menu_button("Settings", _open_settings)
	# critique UI r1: Quit ended the game on one press; it now asks first
	_menu_button("Quit", func() -> void: _show_confirm("quit"))
	var has_save: bool = game != null and game.has_save()
	_continue_btn.disabled = not has_save
	if not has_save:
		# critique UI r1: a disabled Continue took focus with no highlight
		_continue_btn.focus_mode = Control.FOCUS_NONE
	if has_save and game.truffle_count() > 0:
		var tc: int = game.truffle_count()
		_continue_btn.hint = "%d truffle%s" % [tc, "" if tc == 1 else "s"]
	_menu_card.visible = false
	# new game / quit confirmation, in the menu card's slot (lower left) so it never covers the logo's 64 badge
	_confirm = UIStyle.panel("parchment", 36)
	_confirm.position = Vector2(170, 560)
	_confirm.custom_minimum_size = Vector2(760, 0)
	_ui.add_child(_confirm)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm.add_child(cv)
	var ct := UIStyle.label("Begin a new story?", 52, UIStyle.RIBBON, true)
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(ct)
	_confirm_title = ct
	var cs := UIStyle.label("Your bookmarked progress will be replaced.", 28, UIStyle.INK)
	cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(cs)
	_confirm_sub = cs
	var ch := HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(ch)
	var yes := StoryButton.new("Yes, begin", 32)
	yes.custom_minimum_size = Vector2(330, 70)
	yes.chip = true
	yes.pressed.connect(_on_confirm_yes)
	_confirm_yes = yes
	var no := StoryButton.new("Keep my story", 32)
	no.custom_minimum_size = Vector2(330, 70)
	no.chip = true
	no.pressed.connect(_close_confirm)
	_confirm_no = no
	ch.add_child(yes)
	ch.add_child(no)
	var cf := UIPrompts.new()
	cf.items = [["ui_accept", "Choose"], ["ui_cancel", "Keep reading"]]
	cf.custom_minimum_size = Vector2(0, 52)
	cf.text_color = UIStyle.INK
	cf.outline_color = Color(UIStyle.PARCHMENT, 0.9)
	cf.font_size = 24
	cf.glyph_size = 40.0
	cv.add_child(cf)
	# focus stays inside the dialog (critique UI r1: focus leaked to the menu behind it)
	yes.focus_neighbor_left = yes.get_path_to(no)
	yes.focus_neighbor_right = yes.get_path_to(no)
	no.focus_neighbor_left = no.get_path_to(yes)
	no.focus_neighbor_right = no.get_path_to(yes)
	for b in [yes, no]:
		(b as Control).focus_neighbor_top = (b as Control).get_path_to(b)
		(b as Control).focus_neighbor_bottom = (b as Control).get_path_to(b)
	_confirm.visible = false


## Twinkles four of the baked sparkle stars around the logo (critique UI r1: the logo never caught the light).
## Positions are fractions of the logo texture (logo v3, 19 Oct: "SUPER MAK" beside a snout with 6 and 4 in the nostrils,
## 2048x929), drawn KEEP_ASPECT_CENTERED. The v2 logo's truffle overlay is gone with the truffle itself.
class _LogoTwinkle:
	extends Control
	const STARS := [Vector2(0.533, 0.235), Vector2(0.946, 0.221), Vector2(0.958, 0.914), Vector2(0.569, 0.947)]
	const ASPECT := 2048.0 / 929.0
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var w := h * ASPECT
		if w > size.x:
			w = size.x
			h = w / ASPECT
		var org := (size - Vector2(w, h)) * 0.5
		for i in STARS.size():
			var ph := fmod(t * 0.55 + i * 0.29, 1.0)
			var k := clampf(sin(ph * PI * 3.0), 0.0, 1.0) if ph < 0.34 else 0.0
			if k <= 0.0:
				continue
			var p: Vector2 = org + Vector2(STARS[i].x * w, STARS[i].y * h)
			UIDraw.sparkle(self, p, 6.0 + 16.0 * k, Color(1.0, 1.0, 0.86, 0.95 * k))


class _PressRibbon:
	extends Control

	func _draw() -> void:
		UIDraw.ribbon(self, Rect2(Vector2(90, 10), size - Vector2(180, 20)), UIStyle.RIBBON, UIStyle.BRASS)


class _Vignette:
	extends Control

	func _draw() -> void:
		var w := size.x
		for i in 40:
			var x := w * 0.62 * i / 40.0
			var a := 0.42 * pow(1.0 - i / 40.0, 1.6)
			draw_rect(Rect2(x, 0, w * 0.62 / 40.0 + 1, size.y), Color(0.25, 0.1, 0.05, a))


class _Logo:
	extends Control
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _word(text: String, origin: Vector2, fs: int, fill: Color, mid: Color, wave: float) -> float:
		var f := UIStyle.display_font()
		var x := origin.x
		for i in text.length():
			var ch := text[i]
			var y := origin.y + sin(t * 2.0 + i * 0.7) * wave
			var p := Vector2(x, y)
			draw_string_outline(f, p + Vector2(0, 12), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 34, Color(0.18, 0.07, 0.03, 0.55))
			draw_string_outline(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 34, UIStyle.INK)
			draw_string_outline(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 20, mid)
			draw_string(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
			# glossy highlight
			draw_string(f, p + Vector2(-2, -3), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.18))
			x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		return x

	func _draw() -> void:
		# ribbon behind SUPER
		UIDraw.ribbon(self, Rect2(150, 40, 440, 96), UIStyle.RIBBON, UIStyle.BRASS)
		_word("SUPER", Vector2(205, 118), 92, UIStyle.BRASS_LIGHT, UIStyle.RIBBON_DARK, 3.0)
		var end_x := _word("MAK", Vector2(40, 390), 300, UIStyle.CREAM, Color("f29bb0"), 6.0)
		# brass 64 medallion
		var c := Vector2(end_x + 110, 290)
		var bob := sin(t * 1.7) * 6.0
		c.y += bob
		draw_circle(c + Vector2(6, 12), 112, Color(0.15, 0.06, 0.02, 0.45), true, -1.0, true)
		draw_circle(c, 112, UIStyle.INK, true, -1.0, true)
		draw_circle(c, 104, UIStyle.BRASS_DARK, true, -1.0, true)
		draw_circle(c, 96, UIStyle.BRASS, true, -1.0, true)
		draw_arc(c, 84, 0, TAU, 64, UIStyle.BRASS_LIGHT, 3.0, true)
		for i in 24:
			var a := TAU * i / 24.0 + t * 0.2
			draw_circle(c + Vector2(cos(a), sin(a)) * 100, 3.5, UIStyle.BRASS_LIGHT, true, -1.0, true)
		var f := UIStyle.display_font()
		var w := f.get_string_size("64", HORIZONTAL_ALIGNMENT_LEFT, -1, 128).x
		draw_string_outline(f, c + Vector2(-w * 0.5, 44), "64", HORIZONTAL_ALIGNMENT_LEFT, -1, 128, 14, UIStyle.RIBBON_DARK)
		draw_string(f, c + Vector2(-w * 0.5, 44), "64", HORIZONTAL_ALIGNMENT_LEFT, -1, 128, UIStyle.CREAM)
		UIDraw.sparkle(self, c + Vector2(70, -80), 22.0 + sin(t * 4.0) * 6.0, Color(1, 1, 0.85, 0.95))
		# subtitle
		var sf := UIStyle.display_font_regular()
		var sub := "The Big Bad Wolf's Storybook Caper"
		draw_string_outline(sf, Vector2(70, 470), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, 10, Color(0.2, 0.08, 0.03, 0.85))
		draw_string(sf, Vector2(70, 470), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, UIStyle.BRASS_LIGHT)


func _menu_button(caption: String, cb: Callable) -> StoryButton:
	var b := StoryButton.new(caption, 40)
	b.custom_minimum_size = Vector2(540, 78)
	b.pressed.connect(cb)
	_menu.add_child(b)
	return b


func _show_menu(instant: bool = false) -> void:
	state = "menu"
	_press.visible = false
	_menu_card.visible = true
	if not instant:
		_menu_card.modulate.a = 0.0
		_menu_card.position.y = 640
		_menu_card.pivot_offset = _menu_card.size * 0.5
		_menu_card.scale = Vector2(0.92, 0.92)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_menu_card, "modulate:a", 1.0, 0.22)
		tw.tween_property(_menu_card, "position:y", 560.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_menu_card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var i := 0
		for b in _menu.get_children():
			if b is StoryButton:
				(b as StoryButton).appear = 0.0
				tw.tween_property(b, "appear", 1.0, 0.35).set_delay(0.12 + i * 0.07)
				i += 1
		UIFx.event("ui_title_start")
		_logo_squash = 1.0
	_focus_menu_default()


func _focus_menu_default() -> void:
	if _continue_btn.disabled:
		(_menu.get_child(1) as Control).grab_focus()
	else:
		_continue_btn.grab_focus()


func _set_menu_focusable(on: bool) -> void:
	for b in _menu.get_children():
		if b is Control:
			var c := b as Control
			c.focus_mode = Control.FOCUS_ALL if on and not (c is BaseButton and (c as BaseButton).disabled) else Control.FOCUS_NONE
			c.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func _close_confirm() -> void:
	_confirm.visible = false
	_set_menu_focusable(true)
	_menu_card.visible = true
	state = "menu"
	UIFx.event("ui_back")
	(_menu.get_child(3 if _confirm_kind == "quit" else 1) as Control).grab_focus()


func _open_settings() -> void:
	if _settings == null:
		_settings = (load(SETTINGS_SCENE) as PackedScene).instantiate()
		_ui.add_child(_settings)
		_settings.closed.connect(func() -> void:
			state = "menu"
			_menu_card.visible = true
			(_menu.get_child(2) as Control).grab_focus())
	state = "settings"
	_menu_card.visible = false
	_settings.open()


func _on_continue() -> void:
	var game := get_node_or_null("/root/Game")
	var router := get_node_or_null("/root/Router")
	if game == null or router == null:
		return
	game.load_game()
	var last: String = game.data.get("last_world", "")
	router.go_to_hub("Book_" + last if last != "" else "")


func _on_new_game() -> void:
	var game := get_node_or_null("/root/Game")
	if game and game.has_progress():
		_show_confirm("new")
	else:
		_start_new_game()


func _on_confirm_yes() -> void:
	if _confirm_kind == "quit":
		UIFx.event("ui_close", {"context": "quit"})
		get_tree().quit()
	else:
		_start_new_game()


func _show_confirm(kind: String = "new") -> void:
	_confirm_kind = kind
	if kind == "quit":
		# critique UI r1 re-run: "Close the book?" reused the mission-book metaphor and never said it quits
		_confirm_title.text = "Leave the library?"
		_confirm_sub.text = "This closes Super Mak 64. Your place is saved."
		_confirm_yes.caption = "Quit game"
		_confirm_no.caption = "Keep reading"
	else:
		_confirm_title.text = "Begin a new story?"
		_confirm_sub.text = "Your bookmarked progress will be replaced."
		_confirm_yes.caption = "Yes, begin"
		_confirm_no.caption = "Keep my story"
	state = "confirm"
	_set_menu_focusable(false)
	_menu_card.visible = false
	_confirm.visible = true
	UIFx.event("ui_open")
	_confirm.pivot_offset = _confirm.size * 0.5
	_confirm.scale = Vector2(0.82, 0.82)
	_confirm.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_confirm, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_confirm, "modulate:a", 1.0, 0.16)
	(_confirm.get_child(0).get_child(2).get_child(1) as Control).grab_focus()


func _start_new_game() -> void:
	_confirm.visible = false
	UIFx.event("ui_new_game")
	var game := get_node_or_null("/root/Game")
	var router := get_node_or_null("/root/Router")
	if game:
		game.new_game()
	if router:
		router.go_to_hub("")


func _input(event: InputEvent) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("note_device"):
		ui.note_device(event)
	if state == "press":
		var any := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
		if any:
			get_viewport().set_input_as_handled()
			_show_menu()
	elif state == "confirm":
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_back_game"):
			get_viewport().set_input_as_handled()
			_close_confirm()
	elif state == "menu":
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			state = "press"
			_menu_card.visible = false
			_press.visible = true
