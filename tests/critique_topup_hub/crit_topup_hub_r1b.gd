extends Node3D
## CRITIC round 1 (pass b, after the track's r1 fixes), ASSET QA lens, TOPUP_HUB track (night 01). Test stage only.
## 1) Mesh/material audit of every delivered v2 GLB: triangles, material type, albedo/normal/ORM textures present,
##    vertex-colour arrays, metallic/roughness, AABB, hard-edge (split-normal) ratio, loose/degenerate triangles.
## 2) Native captures under env_HUB with an amber key and a cool fill (like the hub): back sides, close-ups, grazing light,
##    scale lineup at the hub's own placement scales next to mak_v2, beanie on the rig in ear/head poses, clock at 10:10 and
##    pendulum at +-4 degrees, chandelier from the floor at scl 1.75 with its candle markers shown, tea set as authored.
## Run: python tools/godot.py run res://tests/critique_topup_hub/CritTopupHubR1b.tscn --seconds 300 -- --crit_out=<abs dir> --profile=crit_topup_hub_r1b

const HUB := "res://assets/props/hub/"
const PICK := "res://assets/props/pickups/"
const MAK := "res://assets/characters/mak/"
const AUDIT := [
	"res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb",
	"res://assets/props/pickups/acorn_v2/acorn_v2.glb",
	"res://assets/characters/mak/mak_beanie_v2.glb",
	"res://assets/characters/mak/mak_v2.glb",
	"res://assets/props/hub/wingback_armchair_v2/wingback_armchair_v2.glb",
	"res://assets/props/hub/grandfather_clock_v2/grandfather_clock_v2.glb",
	"res://assets/props/hub/brass_chandelier_v2/brass_chandelier_v2.glb",
	"res://assets/props/hub/tea_table_set_v2/tea_table_set_v2.glb",
]

var _shots: Array = []
var _out := ""
var _only := ""
var _grazing: DirectionalLight3D
var _sun: DirectionalLight3D

func _ready() -> void:
	_out = Dev.arg("crit_out", "")
	_only = Dev.arg("only", "")
	for p in AUDIT:
		_audit(p)
	_stage()
	# ---------- scale lineup at hub placement scales ----------
	var lx := -40.0
	_spawn(self, MAK + "mak_v2.glb", Vector3(lx, 0, 0), 0.0, 1.0)
	_spawn(self, HUB + "wingback_armchair_v2/wingback_armchair_v2.glb", Vector3(lx - 1.6, 0, -0.3), 20.0, 1.05)
	_spawn(self, HUB + "tea_table_set_v2/tea_table_set_v2.glb", Vector3(lx + 1.5, 0, 0.0), -10.0, 1.3)
	_spawn(self, HUB + "grandfather_clock_v2/grandfather_clock_v2.glb", Vector3(lx + 3.2, 0, -0.6), -15.0, 1.1)
	_spawn(self, PICK + "golden_truffle_v2/golden_truffle_v2.glb", Vector3(lx + 0.75, 0.0, 0.9), 0.0, 1.4)
	_spawn(self, PICK + "acorn_v2/acorn_v2.glb", Vector3(lx - 0.5, 0.0, 1.0), 0.0, 1.15)
	_cam("Lineup_hub_scales", Vector3(lx + 0.6, 1.7, 6.2), Vector3(lx + 0.6, 0.9, 0.0), 45.0)
	# ---------- Mak v2: beanie on the rig ----------
	var poses := {
		"rest": [],
		"ears_fwd55": [["ear_l", Vector3.RIGHT, 55.0], ["ear_r", Vector3.RIGHT, 55.0]],
		"ears_up35": [["ear_l", Vector3.BACK, -35.0], ["ear_r", Vector3.BACK, 35.0]],
		"head_down_turn": [["head", Vector3.RIGHT, 22.0], ["head", Vector3.UP, 35.0]],
	}
	var x := 0.0
	for p in poses.keys():
		var m := _spawn(self, MAK + "mak_v2.glb", Vector3(x, 0, 0), 0.0, 1.0)
		var sk := m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for r in poses[p]:
			_rot_model(sk, r[0], r[1], r[2])
		_cam("Mak_%s_q34" % p, Vector3(x + 0.9, 1.25, 1.7), Vector3(x, 0.98, 0.0), 30.0)
		if p == "rest":
			_cam("Mak_rest_back", Vector3(x - 0.5, 1.35, -1.8), Vector3(x, 1.0, 0.0), 30.0)
			_cam("Mak_rest_back_low", Vector3(x + 0.6, 0.95, -1.4), Vector3(x, 1.05, 0.0), 30.0)
			_cam("Mak_rest_top", Vector3(x + 0.3, 2.6, 0.9), Vector3(x, 1.05, 0.0), 30.0)
			_cam("Mak_rest_front_close", Vector3(x, 1.12, 1.25), Vector3(x, 1.05, 0.0), 30.0)
			_cam("Mak_rest_gameplay6m", Vector3(x + 1.5, 2.6, 6.0), Vector3(x, 0.8, 0.0), 60.0)
		x += 4.0
	# ---------- clock ----------
	var clk := _spawn(self, HUB + "grandfather_clock_v2/grandfather_clock_v2.glb", Vector3(30, 0, 0), 0.0, 1.0)
	var hh := clk.find_child("hand_hour", true, false) as Node3D
	var hm := clk.find_child("hand_minute", true, false) as Node3D
	var pd := clk.find_child("pendulum", true, false) as Node3D
	print("[CritR1b] clock nodes hour=%s minute=%s pendulum=%s" % [hh != null, hm != null, pd != null])
	if hh: hh.rotation.z = deg_to_rad(-305.0)  # 10:10
	if hm: hm.rotation.z = deg_to_rad(-60.0)
	if pd: pd.rotation.z = deg_to_rad(4.0)
	var clk2 := _spawn(self, HUB + "grandfather_clock_v2/grandfather_clock_v2.glb", Vector3(33, 0, 0), 0.0, 1.0)
	var pd2 := clk2.find_child("pendulum", true, false) as Node3D
	if pd2: pd2.rotation.z = deg_to_rad(-4.0)
	_cam("Clock_dial_1010", Vector3(30.0, 1.912, 0.85), Vector3(30.0, 1.912, 0.0), 30.0)
	_cam("Clock_dial_grazing", Vector3(30.55, 1.95, 0.55), Vector3(30.0, 1.912, 0.1), 30.0)
	_cam("Clock_pendulum_p4", Vector3(30.0, 1.15, 1.3), Vector3(30.0, 1.15, 0.0), 32.0)
	_cam("Clock_pendulum_m4", Vector3(33.0, 1.15, 1.3), Vector3(33.0, 1.15, 0.0), 32.0)
	_cam("Clock_front_full", Vector3(31.5, 1.3, 4.6), Vector3(31.5, 1.2, 0.0), 40.0)
	_cam("Clock_back", Vector3(29.0, 1.6, -2.8), Vector3(30.0, 1.2, 0.0), 45.0)
	_cam("Clock_side_q34", Vector3(32.0, 1.7, 1.8), Vector3(30.0, 1.3, 0.0), 45.0)
	_cam("Clock_hood_close", Vector3(30.6, 2.5, 0.9), Vector3(30.0, 2.25, 0.0), 35.0)
	# ---------- chandelier at the hub's 1.75 scale, seen from a player on the floor ----------
	var ch := _spawn(self, HUB + "brass_chandelier_v2/brass_chandelier_v2.glb", Vector3(40, 3.0, 0), 0.0, 1.75)
	for c in ch.find_children("candle_*", "Node3D", true, false):
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.025
		sm.height = 0.05
		dot.mesh = sm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(1, 0, 1)
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.no_depth_test = true
		dot.material_override = mm
		(c as Node3D).add_child(dot)
	print("[CritR1b] chandelier candle markers=", ch.find_children("candle_*", "Node3D", true, false).size(), " sway_pivot=", ch.find_child("sway_pivot", true, false) != null)
	_cam("Chandelier_from_floor", Vector3(44.5, 1.2, 5.0), Vector3(40.0, 4.6, 0.0), 50.0)
	_cam("Chandelier_straight_below", Vector3(40.6, 0.8, 0.6), Vector3(40.0, 5.0, 0.0), 60.0)
	_cam("Chandelier_candles_level", Vector3(40.0, 5.0, 6.0), Vector3(40.0, 4.6, 0.0), 40.0)
	# ---------- armchair ----------
	_spawn(self, HUB + "wingback_armchair_v2/wingback_armchair_v2.glb", Vector3(50, 0, 0), 0.0, 1.0)
	_cam("Armchair_front_q34", Vector3(51.4, 1.3, 2.2), Vector3(50.0, 0.65, 0.0), 40.0)
	_cam("Armchair_seat_close", Vector3(50.35, 1.15, 1.25), Vector3(50.0, 0.5, 0.2), 38.0)
	_cam("Armchair_junction_L", Vector3(49.3, 1.25, 0.8), Vector3(49.55, 0.85, -0.2), 35.0)
	_cam("Armchair_junction_R", Vector3(50.7, 1.25, 0.8), Vector3(50.45, 0.85, -0.2), 35.0)
	_cam("Armchair_back", Vector3(51.4, 1.4, -2.6), Vector3(50.0, 0.7, 0.0), 40.0)
	_cam("Armchair_low_legs", Vector3(50.9, 0.2, 1.6), Vector3(50.0, 0.2, 0.0), 40.0)
	# ---------- tea set as authored ----------
	_spawn(self, HUB + "tea_table_set_v2/tea_table_set_v2.glb", Vector3(60, 0, 0), 0.0, 1.0)
	_cam("Tea_player_eye", Vector3(60.6, 0.75, 1.6), Vector3(60.0, 0.25, 0.1), 40.0)
	_cam("Tea_top", Vector3(60.2, 2.0, 0.6), Vector3(60.0, 0.2, 0.0), 40.0)
	_cam("Tea_back", Vector3(59.0, 1.1, -1.9), Vector3(60.0, 0.3, 0.0), 40.0)
	_cam("Tea_teapot_close", Vector3(59.95, 0.4, 0.95), Vector3(59.84, 0.17, 0.27), 35.0)
	# ---------- pickups ----------
	_spawn(self, PICK + "golden_truffle_v2/golden_truffle_v2.glb", Vector3(70, 0, 0), 0.0, 1.0)
	_spawn(self, PICK + "acorn_v2/acorn_v2.glb", Vector3(70.7, 0, 0.1), 0.0, 1.0)
	_cam("Truffle_close", Vector3(70.0, 0.45, 1.1), Vector3(70.0, 0.3, 0.0), 35.0)
	_cam("Truffle_back", Vector3(70.0, 0.55, -1.1), Vector3(70.0, 0.3, 0.0), 35.0)
	_cam("Truffle_top", Vector3(70.0, 1.3, 0.35), Vector3(70.0, 0.4, 0.0), 35.0)
	_cam("Acorn_close", Vector3(70.7, 0.22, 0.75), Vector3(70.7, 0.17, 0.1), 35.0)
	_cam("Acorn_back", Vector3(70.7, 0.25, -0.55), Vector3(70.7, 0.17, 0.1), 35.0)
	_cam("Acorn_top", Vector3(70.75, 0.75, 0.25), Vector3(70.7, 0.2, 0.1), 35.0)
	_cam("Macro_truffle_face", Vector3(70.0, 0.32, 0.62), Vector3(70.0, 0.3, 0.0), 30.0)
	_cam("Macro_tea_tabletop", Vector3(60.75, 0.75, -0.75), Vector3(60.12, 0.4, -0.25), 35.0)
	_cam("Macro_armchair_seat_gap", Vector3(50.55, 0.85, 0.75), Vector3(50.38, 0.55, 0.15), 30.0)
	_cam("Lineup_side", Vector3(lx - 4.0, 1.4, 4.5), Vector3(lx + 0.8, 0.8, 0.0), 45.0)
	_cam("Pickups_gameplay8m", Vector3(71.5, 2.8, 8.0), Vector3(70.35, 0.3, 0.0), 60.0)
	print("[CritR1b] cameras=", _shots.size())
	if _out != "":
		_run_shots()

# ---------------------------------------------------------------- audit
func _audit(path: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		print("[CritR1b][AUDIT] %s LOAD FAILED" % path)
		return
	var root := ps.instantiate() as Node3D
	add_child(root)
	var tris_total := 0
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	print("[CritR1b][AUDIT] %s meshes=%d root=%s" % [path.get_file(), meshes.size(), root.name])
	for n in meshes:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		var aabb := mi.global_transform * mesh.get_aabb()
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols = arr[Mesh.ARRAY_COLOR]
			var idx = arr[Mesh.ARRAY_INDEX]
			var tris: int = (int(idx.size()) if idx != null else verts.size()) / 3
			tris_total += tris
			# split-normal / hard-edge statistics: positions shared by several vertices with diverging normals
			var bucket := {}
			for i in verts.size():
				var k := Vector3i(roundi(verts[i].x * 20000.0), roundi(verts[i].y * 20000.0), roundi(verts[i].z * 20000.0))
				if bucket.has(k):
					(bucket[k] as Array).append(i)
				else:
					bucket[k] = [i]
			var shared := 0
			var hard := 0
			for k in bucket.keys():
				var l: Array = bucket[k]
				if l.size() < 2:
					continue
				shared += 1
				var n0: Vector3 = norms[l[0]]
				for j in range(1, l.size()):
					if n0.angle_to(norms[l[j]]) > deg_to_rad(30.0):
						hard += 1
						break
			# degenerate triangles
			var degen := 0
			if idx != null:
				for t in tris:
					var a: Vector3 = verts[idx[t * 3]]
					var b: Vector3 = verts[idx[t * 3 + 1]]
					var c: Vector3 = verts[idx[t * 3 + 2]]
					if (b - a).cross(c - a).length() < 1e-10:
						degen += 1
			var mat := mi.get_active_material(s)
			var mdesc := "null"
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				mdesc = "%s alb_tex=%s nrm_tex=%s orm/rough_tex=%s metal=%.2f rough=%.2f alb=%s vcol_as_albedo=%s" % [
					bm.resource_name, bm.albedo_texture != null, bm.normal_enabled and bm.normal_texture != null,
					(bm is ORMMaterial3D and (bm as ORMMaterial3D).orm_texture != null) or bm.roughness_texture != null,
					bm.metallic, bm.roughness, bm.albedo_color.to_html(false), bm.vertex_color_use_as_albedo]
			elif mat != null:
				mdesc = mat.get_class()
			print("[CritR1b][AUDIT]   %s surf%d tris=%d verts=%d vcol=%s uniquepos=%d shared_pos=%d hard_split=%d (%.1f%%) degen=%d aabb_size=%s | %s" % [
				mi.name, s, tris, verts.size(), cols != null and (cols as PackedColorArray).size() > 0, bucket.size(), shared, hard,
				100.0 * float(hard) / maxf(1.0, float(bucket.size())), degen, aabb.size, mdesc])
	var sk := root.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		var s3 := sk[0] as Skeleton3D
		print("[CritR1b][AUDIT]   skeleton bones=%d" % s3.get_bone_count())
		for ba in root.find_children("*", "BoneAttachment3D", true, false):
			print("[CritR1b][AUDIT]   attachment %s bone=%s children=%s" % [ba.name, (ba as BoneAttachment3D).bone_name, ba.get_children().map(func(c): return c.name)])
	print("[CritR1b][AUDIT] %s total_tris=%d" % [path.get_file(), tris_total])
	root.queue_free()

# ---------------------------------------------------------------- shots
func _run_shots() -> void:
	for i in 360:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_out)
	for s in _shots:
		if _only != "" and not Array(_only.split(",")).any(func(pre): return String(s).begins_with(pre)):
			continue
		var c := find_child(s, true, false) as Camera3D
		c.make_current()
		_grazing.visible = String(s).ends_with("grazing")
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join(s + ".png"))
		print("[CritR1b] saved ", s)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _spawn(parent: Node, path: String, pos: Vector3, yaw: float, scl: float) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
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
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1, 0.76, 0.48)
	_sun.light_energy = 2.2
	_sun.shadow_enabled = true
	_sun.rotation_degrees = Vector3(-38, 35, 0)
	add_child(_sun)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.36, 0.23, 0.13)
	floor_mat.roughness = 0.7
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 40)
	f.mesh = pm
	f.material_override = floor_mat
	f.position = Vector3(20, 0, 0)
	add_child(f)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-25, 200, 0)
	add_child(fill)
	_grazing = DirectionalLight3D.new()
	_grazing.light_color = Color(1, 1, 1)
	_grazing.light_energy = 2.5
	_grazing.rotation_degrees = Vector3(-8, 95, 0)
	_grazing.visible = false
	add_child(_grazing)
