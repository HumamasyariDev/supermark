extends Node3D
## TOPUP_HUB fix stage, round 1 (night 01): re-verification stage. Same cameras as the critic's CritTopupHubR1 (before/after pairs),
## plus the extra views the critic asked for. Test stage only; no level uses it.
## Loads every v2 model the track delivered under the hub environment and captures the views the
## track's own evidence does not show: back sides, the beanie on the rigged head in ear/head test poses
## (the animator drives ear bones up to about 55 degrees), gameplay-distance mip levels, the clock dial
## with the hands moved off their baked position, the chandelier from the floor, the armchair seat, and a
## RigidBody drop test of the tea pieces as authored (spawn interpenetration check).
## Run: python tools/godot.py run res://assets/props/hub/_topup_v2_fix_r1/TopupFixR1.tscn --seconds 240 -- --crit_out=<abs dir> --profile=topup_hub_fix_r1

const HUB := "res://assets/props/hub/"
const PICK := "res://assets/props/pickups/"
const MAK := "res://assets/characters/mak/"

var _shots: Array = []  # [cam_name, file]
var _out := ""
var _tea_bodies: Array = []
var _tea_start: Dictionary = {}
var _tea_peak: Dictionary = {}
var _phys_frames := 0

func _ready() -> void:
	_out = Dev.arg("crit_out", "")
	_stage()
	# --- Mr. Mak v2 (beanie on the rig) in poses ---
	var poses := {
		"rest": [],
		"ears_fwd55": [["ear_l", Vector3.RIGHT, 55.0], ["ear_r", Vector3.RIGHT, 55.0]],
		"ears_back30": [["ear_l", Vector3.RIGHT, -30.0], ["ear_r", Vector3.RIGHT, -30.0]],
		"ears_up35": [["ear_l", Vector3.BACK, -35.0], ["ear_r", Vector3.BACK, 35.0]],
		"head_down_turn": [["head", Vector3.RIGHT, 22.0], ["head", Vector3.UP, 35.0]],
	}
	var x := 0.0
	for p in poses.keys():
		var m := _spawn(self, MAK + "mak_v2.glb", Vector3(x, 0, 0), 0.0)
		var sk := m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for r in poses[p]:
			_rot_model(sk, r[0], r[1], r[2])
		# model faces +Z: front camera at +Z
		_cam("Mak_%s_q34" % p, Vector3(x + 0.9, 1.25, 1.7), Vector3(x, 0.98, 0.0), 30.0)
		if p == "rest":
			_cam("Mak_rest_back", Vector3(x - 0.5, 1.35, -1.8), Vector3(x, 1.0, 0.0), 30.0)
			_cam("Mak_rest_side", Vector3(x - 1.9, 1.15, 0.05), Vector3(x, 1.0, 0.0), 30.0)
			_cam("Mak_rest_top", Vector3(x + 0.3, 2.6, 0.9), Vector3(x, 1.05, 0.0), 30.0)
			_cam("Mak_rest_gameplay6m", Vector3(x + 1.5, 2.6, 6.0), Vector3(x, 0.8, 0.0), 60.0)
		x += 4.0
	# --- props ---
	var clk := _spawn(self, HUB + "grandfather_clock_v2/grandfather_clock_v2.glb", Vector3(30, 0, 0), 0.0)
	var hh := clk.find_child("hand_hour", true, false) as Node3D
	var hm := clk.find_child("hand_minute", true, false) as Node3D
	var pd := clk.find_child("pendulum", true, false) as Node3D
	if hh: hh.rotation.z = deg_to_rad(-200.0)
	if hm: hm.rotation.z = deg_to_rad(-140.0)
	if pd: pd.rotation.z = deg_to_rad(5.0)
	_cam("Clock_dial_moved_hands", Vector3(30.0, 1.92, 0.95), Vector3(30.0, 1.9, 0.0), 30.0)
	_cam("Clock_pendulum_5deg", Vector3(30.25, 1.2, 1.3), Vector3(30.0, 0.95, 0.0), 32.0)
	_cam("Clock_back", Vector3(29.0, 1.6, -2.8), Vector3(30.0, 1.2, 0.0), 45.0)
	_cam("Clock_side", Vector3(32.8, 1.5, 0.3), Vector3(30.0, 1.2, 0.0), 45.0)
	var ch := _spawn(self, HUB + "brass_chandelier_v2/brass_chandelier_v2.glb", Vector3(40, 3.0, 0), 0.0)
	ch.scale = Vector3.ONE * 1.7
	_cam("Chandelier_from_floor", Vector3(43.5, 1.2, 4.5), Vector3(40.0, 4.6, 0.0), 55.0)
	_spawn(self, HUB + "wingback_armchair_v2/wingback_armchair_v2.glb", Vector3(50, 0, 0), 0.0)
	_cam("Armchair_seat_close", Vector3(50.35, 1.15, 1.25), Vector3(50.0, 0.5, 0.2), 38.0)
	_cam("Armchair_back", Vector3(51.4, 1.4, -2.6), Vector3(50.0, 0.7, 0.0), 40.0)
	_spawn(self, HUB + "tea_table_set_v2/tea_table_set_v2.glb", Vector3(60, 0, 0), 0.0)
	_cam("Tea_player_eye", Vector3(60.6, 0.75, 1.6), Vector3(60.0, 0.25, 0.1), 40.0)
	_cam("Tea_back", Vector3(59.0, 1.1, -1.9), Vector3(60.0, 0.3, 0.0), 40.0)
	_spawn(self, PICK + "golden_truffle_v2/golden_truffle_v2.glb", Vector3(70, 0, 0), 0.0)
	_spawn(self, PICK + "acorn_v2/acorn_v2.glb", Vector3(70.7, 0, 0.1), 0.0)
	_cam("Pickups_close", Vector3(70.35, 0.55, 1.6), Vector3(70.35, 0.3, 0.0), 35.0)
	_cam("Pickups_back", Vector3(70.35, 0.7, -1.6), Vector3(70.35, 0.3, 0.0), 35.0)
	_tea_physics_test(Vector3(100, 0, 0))
	_extra()
	print("[TopupFixR1] cameras=", _shots.size())
	if _out != "":
		_run_shots()

func _physics_process(_dt: float) -> void:
	if _tea_bodies.is_empty():
		return
	_phys_frames += 1
	for b in _tea_bodies:
		var rb := b as RigidBody3D
		_tea_peak[rb.name] = maxf(float(_tea_peak.get(rb.name, 0.0)), rb.linear_velocity.length())
	if _phys_frames == 180:
		var worst := ""
		for b in _tea_bodies:
			var rb := b as RigidBody3D
			var s: Transform3D = _tea_start[rb.name]
			var d := rb.global_position.distance_to(s.origin)
			var ang := rad_to_deg(s.basis.get_rotation_quaternion().angle_to(rb.global_basis.get_rotation_quaternion()))
			print("[TopupFixR1] tea_drop %s moved=%.3f m rot=%.1f deg peak_v=%.2f m/s" % [rb.name, d, ang, float(_tea_peak[rb.name])])

func _tea_physics_test(at: Vector3) -> void:
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(10, 0.2, 10)
	fs.shape = bx
	fs.position = Vector3(0, -0.1, 0)
	floor_body.add_child(fs)
	floor_body.position = at
	add_child(floor_body)
	var src := (load(HUB + "tea_table_set_v2/tea_table_set_v2.glb") as PackedScene).instantiate() as Node3D
	add_child(src)
	src.position = at
	await get_tree().process_frame
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var rb := RigidBody3D.new()
		rb.name = String(m.name)
		var cs := CollisionShape3D.new()
		cs.shape = m.mesh.create_convex_shape(true, true)
		var g := m.global_transform
		rb.add_child(cs)
		var vis := MeshInstance3D.new()
		vis.mesh = m.mesh
		rb.add_child(vis)
		add_child(rb)
		rb.global_transform = g
		_tea_start[rb.name] = g
		_tea_bodies.append(rb)
	src.queue_free()

func _run_shots() -> void:
	for i in 40:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_out)
	for s in _shots:
		var c := find_child(s, true, false) as Camera3D
		c.make_current()
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join(s + ".png"))
		print("[TopupFixR1] saved ", s)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _spawn(parent: Node, path: String, pos: Vector3, yaw: float) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	return n

func _cam(cam_name: String, pos: Vector3, look: Vector3, fov: float) -> void:
	var c := Camera3D.new()
	c.name = cam_name
	add_child(c)
	c.fov = fov
	c.look_at_from_position(pos, look, Vector3.UP)
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
	pm.size = Vector2(240, 40)
	f.mesh = pm
	f.material_override = floor_mat
	f.position = Vector3(50, 0, 0)
	add_child(f)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-25, 200, 0)
	add_child(fill)


func _clock_pose(at: Vector3, hour_deg: float, min_deg: float, pend_deg: float) -> Node3D:
	var clk := _spawn(self, HUB + "grandfather_clock_v2/grandfather_clock_v2.glb", at, 0.0)
	(clk.find_child("hand_hour", true, false) as Node3D).rotation.z = deg_to_rad(-hour_deg)
	(clk.find_child("hand_minute", true, false) as Node3D).rotation.z = deg_to_rad(-min_deg)
	(clk.find_child("pendulum", true, false) as Node3D).rotation.z = deg_to_rad(pend_deg)
	return clk

func _extra() -> void:
	# clock at 4:40 (pendulum +4 deg) and 7:05 (pendulum -4 deg): hands clockwise = negative z
	_clock_pose(Vector3(-30, 0, 0), 140.0, 240.0, 4.0)
	_cam("Clock_dial_0440", Vector3(-30.0, 1.92, 0.95), Vector3(-30.0, 1.9, 0.0), 30.0)
	_cam("Clock_pendulum_p4", Vector3(-29.75, 1.2, 1.3), Vector3(-30.0, 0.95, 0.0), 32.0)
	_cam("Clock_front_full", Vector3(-30.0, 1.3, 3.6), Vector3(-30.0, 1.2, 0.0), 45.0)
	_clock_pose(Vector3(-36, 0, 0), 212.5, 30.0, -4.0)
	_cam("Clock_dial_0705", Vector3(-36.0, 1.92, 0.95), Vector3(-36.0, 1.9, 0.0), 30.0)
	_cam("Clock_pendulum_m4", Vector3(-36.25, 1.2, 1.3), Vector3(-36.0, 0.95, 0.0), 32.0)
	# chandelier from the floor at 30 and 60 degrees elevation (piece at y 3, scale 1.7 as in the critic stage)
	_cam("Chandelier_floor_30deg", Vector3(45.9, 1.2, 0.6), Vector3(40.0, 4.6, 0.0), 60.0)
	_cam("Chandelier_floor_60deg", Vector3(41.96, 1.2, 0.4), Vector3(40.0, 4.6, 0.0), 75.0)
	# armchair front, three-quarter
	_cam("Armchair_front", Vector3(50.0, 1.0, 2.6), Vector3(50.0, 0.65, 0.0), 40.0)
	_cam("Armchair_q34", Vector3(51.8, 1.3, 2.0), Vector3(50.0, 0.6, 0.0), 40.0)
