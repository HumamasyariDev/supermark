extends Node3D
## TOPUP_HUB fix stage, round 4 (ASSETS3_HUB, night 01): native verification of the hub/pickup/beanie deliveries.
## Sets: "before_" = the files the game ships today (v2), "after_" = the round 4 "use this file" deliveries (see README).
## "diag_" = armchair material diagnostics (normal map off, back-face culling on, unshaded) for the junction slivers.
## Test stage only; no level uses it.
## Run: python tools/godot.py run res://assets/props/hub/_topup_v4_fix_r4/TopupFixR4.tscn --seconds 400 -- --crit_out=<abs dir> --profile=assets3_hub [--only=after_,diag_] [--diag_chair=res://...glb]

const HUB := "res://assets/props/hub/"
const PICK := "res://assets/props/pickups/"
const MAK := "res://assets/characters/mak/"
const SETS := {
	"before": {"dx": 0.0, "chair": "wingback_armchair_v2/wingback_armchair_v2.glb", "clock": "grandfather_clock_v2/grandfather_clock_v2.glb",
		"tea": "tea_table_set_v2/tea_table_set_v2.glb", "chand": "brass_chandelier_v2/brass_chandelier_v2.glb", "mak": "mak_v2.glb",
		"truffle": "golden_truffle_v2/golden_truffle_v2.glb", "acorn": "acorn_v2/acorn_v2.glb"},
	"after": {"dx": 300.0, "chair": "wingback_armchair_v4/wingback_armchair_v4.glb", "clock": "grandfather_clock_v3/grandfather_clock_v3.glb",
		"tea": "tea_table_set_v4/tea_table_set_v4.glb", "chand": "brass_chandelier_v3/brass_chandelier_v3.glb", "mak": "mak_v4.glb",
		"truffle": "golden_truffle_v2/golden_truffle_v2.glb", "acorn": "acorn_v3/acorn_v3.glb"},
}

var _shots: Array = []
var _out := ""
var _only := ""

func _ready() -> void:
	_out = Dev.arg("crit_out", "")
	_only = Dev.arg("only", "")
	_stage()
	for set_name in SETS.keys():
		if _only != "" and not _only.contains(set_name):
			continue
		_build_set(set_name, SETS[set_name])
	if _only == "" or _only.contains("diag"):
		_build_diag()
	print("[TopupFixR4] cameras=", _shots.size())
	if _out != "":
		_run_shots()

func _exists(path: String) -> bool:
	return ResourceLoader.exists(path)

func _build_set(set_name: String, s: Dictionary) -> void:
	var dx: float = s["dx"]
	var p: String = set_name + "_"
	if _exists(MAK + s["mak"]):
		var poses := {
			"rest": [],
			"ears_back30": [["ear_l", Vector3.RIGHT, -30.0], ["ear_r", Vector3.RIGHT, -30.0]],
			"ears_fwd55": [["ear_l", Vector3.RIGHT, 55.0], ["ear_r", Vector3.RIGHT, 55.0]],
			"ears_up35": [["ear_l", Vector3.BACK, -35.0], ["ear_r", Vector3.BACK, 35.0]],
			"squash": [],
		}
		var x := dx
		for pn in poses.keys():
			var m := _spawn(self, MAK + s["mak"], Vector3(x, 0, 0), 0.0, 1.0)
			var sks := m.find_children("*", "Skeleton3D", true, false)
			if sks.size() > 0:
				var sk := sks[0] as Skeleton3D
				for r in poses[pn]:
					_rot_model(sk, r[0], r[1], r[2])
			var look_y := 0.98
			if pn == "squash":
				m.scale = Vector3(1.18, 0.78, 1.18)
				look_y = 0.78
			_cam(p + "Mak_%s_q34" % pn, Vector3(x + 0.9, 1.25, 1.7), Vector3(x, look_y, 0.0), 30.0)
			if pn == "rest":
				_cam(p + "Mak_rest_front_close", Vector3(x, 1.12, 1.25), Vector3(x, 1.05, 0.0), 30.0)
				_cam(p + "Mak_rest_side", Vector3(x - 1.9, 1.15, 0.05), Vector3(x, 1.0, 0.0), 30.0)
				_cam(p + "Mak_rest_side_r", Vector3(x + 1.9, 1.15, 0.05), Vector3(x, 1.0, 0.0), 30.0)
				_cam(p + "Mak_rest_back", Vector3(x - 0.5, 1.35, -1.8), Vector3(x, 1.0, 0.0), 30.0)
				_cam(p + "Mak_rest_top", Vector3(x + 0.4, 2.3, 0.9), Vector3(x, 1.05, 0.0), 30.0)
				_cam(p + "Mak_rest_gameplay6m", Vector3(x + 1.5, 2.6, 6.0), Vector3(x, 0.8, 0.0), 60.0)
			x += 4.0
	var cx := dx + 30.0
	var clk := _spawn(self, HUB + s["clock"], Vector3(cx, 0, 0), 0.0, 1.0)
	var hh := clk.find_child("hand_hour", true, false) as Node3D
	var hm := clk.find_child("hand_minute", true, false) as Node3D
	if hh: hh.rotation.z = deg_to_rad(-305.0)
	if hm: hm.rotation.z = deg_to_rad(-60.0)
	_cam(p + "Clock_front_full", Vector3(cx + 1.5, 1.3, 4.6), Vector3(cx + 1.5, 1.2, 0.0), 40.0)
	_cam(p + "Clock_back_q34_low", Vector3(cx + 1.6, 0.6, -1.9), Vector3(cx, 0.9, 0.0), 45.0)
	_cam(p + "Clock_finial", Vector3(cx + 0.45, 2.75, 1.0), Vector3(cx, 2.3, 0.0), 35.0)
	var chx := dx + 40.0
	_spawn(self, HUB + s["chand"], Vector3(chx, 3.0, 0), 0.0, 1.75)
	_cam(p + "Chandelier_from_floor", Vector3(chx + 4.5, 1.2, 5.0), Vector3(chx, 4.6, 0.0), 50.0)
	_cam(p + "Chandelier_arm_close", Vector3(chx + 0.6, 3.4, 3.6), Vector3(chx, 3.6, 1.6), 40.0)
	var ax := dx + 50.0
	if _exists(HUB + s["chair"]):
		_spawn(self, HUB + s["chair"], Vector3(ax, 0, 0), 0.0, 1.0)
		_cam(p + "Armchair_front_q34", Vector3(ax + 1.4, 1.3, 2.2), Vector3(ax, 0.65, 0.0), 40.0)
		_cam(p + "Armchair_seat_close", Vector3(ax + 0.35, 1.15, 1.25), Vector3(ax, 0.5, 0.2), 38.0)
		_cam(p + "Armchair_junction_close", Vector3(ax + 0.15, 1.05, 0.75), Vector3(ax - 0.25, 0.85, 0.0), 32.0)
		_cam(p + "Armchair_low_front", Vector3(ax + 0.35, 0.45, 1.6), Vector3(ax, 0.38, 0.0), 40.0)
		_cam(p + "Armchair_back_q34", Vector3(ax - 1.5, 1.35, -2.2), Vector3(ax, 0.7, 0.0), 40.0)
		_cam(p + "Armchair_back", Vector3(ax + 1.4, 1.4, -2.6), Vector3(ax, 0.7, 0.0), 40.0)
	var tx := dx + 60.0
	if _exists(HUB + s["tea"]):
		_spawn(self, HUB + s["tea"], Vector3(tx, 0, 0), 0.0, 1.0)
		_cam(p + "Tea_player_eye", Vector3(tx + 0.6, 0.75, 1.6), Vector3(tx, 0.25, 0.1), 40.0)
		_cam(p + "Tea_back", Vector3(tx - 1.0, 1.1, -1.9), Vector3(tx, 0.3, 0.0), 40.0)
		_cam(p + "Tea_pedestal_close", Vector3(tx + 1.1, 0.5, 0.2), Vector3(tx + 0.25, 0.3, -0.25), 40.0)
		_cam(p + "Tea_pedestal_side", Vector3(tx + 1.4, 0.35, -0.25), Vector3(tx + 0.25, 0.25, -0.25), 40.0)
		_cam(p + "Macro_tea_tabletop", Vector3(tx + 0.75, 0.75, -0.75), Vector3(tx + 0.12, 0.4, -0.25), 35.0)
	var px := dx + 70.0
	_spawn(self, PICK + s["truffle"], Vector3(px, 0, 0), 0.0, 1.0)
	_spawn(self, PICK + s["acorn"], Vector3(px + 0.7, 0, 0.1), 0.0, 1.0)
	_cam(p + "Acorn_macro", Vector3(px + 0.7, 0.2, 0.5), Vector3(px + 0.7, 0.16, 0.1), 30.0)
	_cam(p + "Acorn_macro_top", Vector3(px + 0.78, 0.55, 0.32), Vector3(px + 0.7, 0.2, 0.1), 30.0)
	_cam(p + "Truffle_close", Vector3(px, 0.45, 1.1), Vector3(px, 0.3, 0.0), 35.0)
	var lx := dx + 90.0
	if _exists(MAK + s["mak"]):
		_spawn(self, MAK + s["mak"], Vector3(lx, 0, 0), 0.0, 1.0)
	if _exists(HUB + s["chair"]):
		_spawn(self, HUB + s["chair"], Vector3(lx - 1.6, 0, -0.3), 20.0, 1.05)
	if _exists(HUB + s["tea"]):
		_spawn(self, HUB + s["tea"], Vector3(lx + 1.5, 0, 0.0), -10.0, 1.3)
	_spawn(self, HUB + s["clock"], Vector3(lx + 3.2, 0, -0.6), -15.0, 1.1)
	_spawn(self, PICK + s["truffle"], Vector3(lx + 0.75, 0.0, 0.9), 0.0, 1.4)
	_spawn(self, PICK + s["acorn"], Vector3(lx - 0.5, 0.0, 1.0), 0.0, 1.15)
	_cam(p + "Lineup_hub_scales", Vector3(lx + 0.6, 1.7, 6.2), Vector3(lx + 0.6, 0.9, 0.0), 45.0)

func _build_diag() -> void:
	var path: String = Dev.arg("diag_chair", HUB + "wingback_armchair_v3/wingback_armchair_v3.glb")
	var modes := ["default", "nonormal", "cullback", "unshaded"]
	var x := 600.0
	for mode in modes:
		var n := _spawn(self, path, Vector3(x, 0, 0), 0.0, 1.0)
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var mat := mesh.surface_get_material(si)
				if mat is BaseMaterial3D:
					var m2 := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					if mode == "nonormal":
						m2.normal_enabled = false
					elif mode == "cullback":
						m2.cull_mode = BaseMaterial3D.CULL_BACK
					elif mode == "unshaded":
						m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					(mi as MeshInstance3D).set_surface_override_material(si, m2)
		_cam("diag_%s_seat_close" % mode, Vector3(x + 0.35, 1.15, 1.25), Vector3(x, 0.5, 0.2), 38.0)
		_cam("diag_%s_junction_close" % mode, Vector3(x + 0.15, 1.05, 0.75), Vector3(x - 0.25, 0.85, 0.0), 32.0)
		x += 5.0

func _run_shots() -> void:
	for i in 240:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_out)
	for s in _shots:
		if _only != "" and not Array(_only.split(",")).any(func(pre): return String(s).begins_with(pre)):
			continue
		var c := find_child(s, true, false) as Camera3D
		c.make_current()
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join(s + ".png"))
		print("[TopupFixR4] saved ", s)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _spawn(parent: Node, path: String, pos: Vector3, yaw: float, scl: float) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("[TopupFixR4] cannot load " + path)
		var e := Node3D.new()
		parent.add_child(e)
		return e
	var n := ps.instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	n.scale = Vector3.ONE * scl
	return n

func _cam(cam_name: String, pos: Vector3, look: Vector3, fov: float) -> void:
	var c := Camera3D.new()
	c.name = cam_name
	add_child(c)
	c.fov = fov
	c.near = 0.02
	var up := Vector3.UP
	if absf((look - pos).normalized().dot(Vector3.UP)) > 0.97:
		up = Vector3.FORWARD
	c.look_at_from_position(pos, look, up)
	_shots.append(cam_name)

func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var i := skel.find_bone(bone)
	if i < 0:
		push_warning("no bone " + bone)
		return
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

func _stage() -> void:
	var we := WorldEnvironment.new()
	we.environment = load("res://assets/shaders/environments/env_HUB.tres") as Environment
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.76, 0.48)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, 35, 0)
	add_child(sun)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.36, 0.23, 0.13)
	floor_mat.roughness = 0.7
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1300, 40)
	f.mesh = pm
	f.material_override = floor_mat
	f.position = Vector3(300, 0, 0)
	add_child(f)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-25, 200, 0)
	add_child(fill)
