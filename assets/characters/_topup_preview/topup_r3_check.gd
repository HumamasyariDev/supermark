extends Node3D
## TOPUP_CHARS round 3 look-dev check (not gameplay): the accepted files next to their r3 `_vN` replacements,
## posed on the real Skeleton3D. "-- --only=<group>": snap, scarecrow, cow, sheep, giant, lineup.
## Cameras: Cam_<group>[_Close|_Top]. Left = before (current file), right = after (r3 file).

const C := "res://assets/characters/"
var _only := "snap"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_stage()
	match _only:
		"snap": _snap()
		"scarecrow": _scarecrow()
		"cow": _cow()
		"sheep": _sheep()
		"giant": _giant()
		"lineup": _lineup()
		"motion": _motion()
		"ao": _ao()
		"props": _props()
		"snap4": _snap4()
		"snap4_back": _snap4(true)
		"props4": _props4()
		"motion4": _motion4()

var _frames := 0
var _anim: Array = []  # [skeleton, [[bone, axis, base_deg, amp_deg, period_s, phase], ...]]
var _t := 0.0
func _process(d: float) -> void:
	_frames += 1
	_t += d
	for e in _anim:
		var sk: Skeleton3D = e[0]
		sk.reset_bone_poses()
		for b in e[1]:
			_rot_model(sk, b[0], b[1], b[2] + b[3] * sin(TAU * (_t / b[4]) + b[5]))
	if _frames > 20:
		return
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		if not is_ancestor_of(n):
			(n as VisualInstance3D).visible = false

func _snap() -> void:
	var down40 := {"arm_l": [Vector3(0, 0, 1), -40.0], "arm_r": [Vector3(0, 0, 1), 40.0]}
	var down55 := {"arm_l": [Vector3(0, 0, 1), -55.0], "arm_r": [Vector3(0, 0, 1), 55.0]}
	var up40 := {"arm_l": [Vector3(0, 0, 1), 40.0], "arm_r": [Vector3(0, 0, 1), -40.0]}
	var salute := {"arm_l": [Vector3(0, 0, 1), -50.0], "arm_r": [Vector3(1, 0, 0), -70.0]}
	_row("sergeant_snap/sergeant_snap.glb", [{}, down40, down55], 1.5, 0.0, 0.0)
	_row("sergeant_snap/sergeant_snap_v2.glb", [{}, down40, down55, up40, salute], 1.5, 5.0, 0.0)
	_label("before: rest / -40 / -55", Vector3(1.5, 2.25, 0))
	_label("after (v2): rest / -40 / -55 / +40 / salute", Vector3(8.0, 2.25, 0))
	_cam("Cam_snap", Vector3(5.6, 1.6, -9.5), Vector3(5.6, 0.95, 0), 50.0)
	_cam("Cam_snap_Close", Vector3(4.5, 1.2, -3.2), Vector3(4.5, 0.95, 0), 45.0)

func _scarecrow() -> void:
	_row("wolf_scarecrow/wolf_scarecrow.glb", [{}], 0.0, -3.2, 0.0)
	_row("wolf_scarecrow/wolf_scarecrow_v2.glb", [{}], 0.0, 3.2, 0.0)
	_label("before", Vector3(-3.2, 5.4, 0))
	_label("after (v2)", Vector3(3.2, 5.4, 0))
	_cam("Cam_scarecrow", Vector3(0, 4.6, -9.0), Vector3(0, 3.6, 0), 50.0)
	_cam("Cam_scarecrow_Top", Vector3(0, 10.5, -3.0), Vector3(0, 4.3, 0), 50.0)

func _cow() -> void:
	var jaw := {"_yaw": 90.0, "jaw": [Vector3(1, 0, 0), -12.0]}
	var graze := {"_yaw": 90.0, "head": [Vector3(1, 0, 0), 30.0]}
	_spawn(C + "mak/mak.glb", Vector3(-1.4, 0, 0), 0.0)
	_row("daisy_cow/daisy_cow.glb", [{"_yaw": 90.0}], 0.0, 0.0, 0.0)
	_row("daisy_cow/daisy_cow_v2.glb", [{"_yaw": 90.0}, jaw, graze], 2.6, 3.0, 0.0)
	_label("before 1.67 m", Vector3(0, 1.9, 0))
	_label("after 2.2 m / jaw -12 / graze", Vector3(5.6, 1.9, 0))
	_cam("Cam_cow", Vector3(3.6, 1.6, -9.5), Vector3(3.6, 0.8, 0), 50.0)
	_cam("Cam_cow_Close", Vector3(4.6, 1.2, -2.4), Vector3(5.6, 0.95, 0), 45.0)

func _sheep() -> void:
	_spawn(C + "mak/mak.glb", Vector3(-1.2, 0, 0), 0.0)
	_row("real_sheep/real_sheep.glb", [{"_yaw": 90.0}], 0.0, 0.3, 0.0)
	_row("real_sheep/real_sheep_v2.glb", [{"_yaw": 90.0}], 0.0, 2.0, 0.0)
	_label("before 0.99 m", Vector3(0.3, 1.4, 0))
	_label("after 1.2 m", Vector3(2.0, 1.4, 0))
	_cam("Cam_sheep", Vector3(0.5, 1.2, -4.2), Vector3(0.5, 0.55, 0), 45.0)

func _giant() -> void:
	var situp := {"chest": [Vector3(1, 0, 0), -12.0]}
	var startle := {"chest": [Vector3(1, 0, 0), -18.0], "arms": [Vector3(1, 0, 0), -20.0], "upperarm_l": [Vector3(0, 0, 1), 15.0], "upperarm_r": [Vector3(0, 0, 1), -15.0]}
	_row("sleeping_giant/sleeping_giant.glb", [situp], 0.0, -4.5, 0.0, 0.8)
	_row("sleeping_giant/sleeping_giant_v2.glb", [situp, startle], 7.0, 4.5, 0.0, 0.8)
	_label("before: chest -12", Vector3(-4.5, 6.0, 0))
	_label("after (v2): chest -12 / startle", Vector3(8.0, 6.0, 0))
	_cam("Cam_giant", Vector3(3.0, 5.0, -20.0), Vector3(3.0, 2.6, 0), 50.0)

func _lineup() -> void:
	var items := [["mak/mak.glb", 0.0], ["pip_v2/pip_v3.glb", 0.0], ["hazel/hazel_v2.glb", 0.0], ["bertram/bertram_v2.glb", 0.0],
		["jack/jack_v2.glb", 0.0], ["sergeant_snap/sergeant_snap_v2.glb", 0.0], ["foreman/foreman_v2.glb", 0.0], ["foreman/foreman_underwear_v2.glb", 0.0],
		["real_sheep/real_sheep_v2.glb", 90.0], ["daisy_cow/daisy_cow_v2.glb", 90.0]]
	var x := 0.0
	var lower := {"arm_l": [Vector3(0, 0, 1), -50.0], "arm_r": [Vector3(0, 0, 1), 50.0]}
	for it in items:
		var n := _spawn(C + it[0], Vector3(x, 0, 0), it[1])
		if String(it[0]).begins_with("sergeant_snap"):
			_apply(n, lower)
		x += 1.6 if it[1] == 0.0 else 2.4
	_spawn(C + "wolf_scarecrow/wolf_scarecrow_v2.glb", Vector3(x + 1.5, 0, 2.0), 0.0)
	_spawn(C + "sleeping_giant/sleeping_giant_v2.glb", Vector3(x + 7.5, 0, 4.0), -20.0, 0.8)
	var mid := Vector3(x * 0.5 + 3.0, 1.2, 1.0)
	_cam("Cam_lineup", mid + Vector3(0, 6.5, -19.0), mid, 45.0)
	_cam("Cam_lineup_Low", Vector3(6.5, 1.4, -6.5), Vector3(6.5, 0.8, 0), 45.0)

## AO check: accepted file (left of each pair) vs r3 file with the baked ORM.R occlusion (right), close, sun dimmed
## so the sky ambient (which the AO texture darkens) carries most of the light.
func _ao() -> void:
	var pairs := [["jack/jack.glb", "jack/jack_v2.glb"], ["bertram/bertram.glb", "bertram/bertram_v2.glb"],
		["foreman/foreman.glb", "foreman/foreman_v2.glb"]]
	var x := 0.0
	for p in pairs:
		_spawn(C + p[0], Vector3(x + 1.25, 0, 0), 0.0)  # screen left (the cameras look along +Z, so +X is screen left)
		_spawn(C + p[1], Vector3(x, 0, 0), 0.0)
		_label("before | after", Vector3(x + 0.62, 2.1, 0))
		x += 3.2
	for n in find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).light_energy = 0.35
	_cam("Cam_ao", Vector3(3.8, 1.3, -5.2), Vector3(3.8, 0.9, 0), 50.0)
	_cam("Cam_ao_Close", Vector3(7.0, 1.5, -2.6), Vector3(7.0, 1.2, 0), 45.0)

## Hand-socket test for Snap v2 with the arms lowered 50 degrees (the idle the cast uses). Left: the lance aimed from
## the hand's REST basis (what gingerbread_grenadier.gd does today), which tilts once the arm is lowered. Right: aimed
## from the POSED hand basis (the fix for scripts that lower the v2 arms), plus the parade drum on the hips.
func _props() -> void:
	var lower := {"arm_l": [Vector3(0, 0, 1), -50.0], "arm_r": [Vector3(0, 0, 1), 50.0]}
	for k in 2:
		var n := _spawn(C + "sergeant_snap/sergeant_snap_v2.glb", Vector3(1.2 - 2.4 * k, 0, 0), 0.0)
		_apply(n, lower)
		var sk := _skel(n)
		var hand := sk.find_bone("hand_r")
		var att := BoneAttachment3D.new()
		att.bone_name = "hand_r"
		sk.add_child(att)
		var lance := (load(C + "sergeant_snap/snap_lance.glb") as PackedScene).instantiate() as Node3D
		att.add_child(lance)
		var hb := sk.get_bone_global_rest(hand).basis if k == 0 else sk.get_bone_global_pose(hand).basis
		var up := Vector3(0, 1, 0.18).normalized()
		var side := Vector3(1, 0, 0)
		var want := Basis(side, up, side.cross(up).normalized())
		lance.transform = Transform3D(hb.orthonormalized().inverse() * want, Vector3.ZERO)
		var hips := sk.find_bone("hips")
		var hatt := BoneAttachment3D.new()
		hatt.bone_name = "hips"
		sk.add_child(hatt)
		var drum := (load(C + "sergeant_snap/snap_drum.glb") as PackedScene).instantiate() as Node3D
		hatt.add_child(drum)
		var hr := sk.get_bone_global_rest(hips).basis.orthonormalized()
		drum.transform = Transform3D(hr.inverse() * Basis(Vector3(1, 0, 0), deg_to_rad(15.0)), hr.inverse() * Vector3(0.30, -0.05, 0.25))
	_label("rest-basis lance (today)", Vector3(1.2, 2.5, 0))
	_label("posed-basis lance (use with v2)", Vector3(-1.2, 2.5, 0))
	_cam("Cam_props", Vector3(0, 1.4, -5.0), Vector3(0, 1.1, 0), 50.0)

## Round 4 (Snap v3): shoulder ball joints, cap UVs (valid tangents), sash fringe repaint. Pairs per pose: v2 | v3.
## Poses: rest, lowered 50 (idle), forward thrust 80 about X, overhead, salute.
func _snap4(back := false) -> void:
	var down50 := {"arm_l": [Vector3(0, 0, 1), -50.0], "arm_r": [Vector3(0, 0, 1), 50.0]}
	var fwd := {"arm_l": [Vector3(0, 0, 1), -45.0], "arm_r": [Vector3(1, 0, 0), -80.0]}
	var over := {"arm_l": [Vector3(1, 0, 0), -140.0], "arm_r": [Vector3(1, 0, 0), -140.0]}
	var salute := {"arm_l": [Vector3(0, 0, 1), -50.0], "arm_r": [Vector3(1, 0, 0), -70.0]}
	var poses := [{}, down50, fwd, over, salute]
	var names := ["rest", "-50", "thrust", "overhead", "salute"]
	# pairs per pose, v2 on screen left (+X), v3 on screen right; cameras look along +Z (or -Z for the back view)
	for i in poses.size():
		var x := -3.4 * i
		_apply(_spawn(C + "sergeant_snap/sergeant_snap_v2.glb", Vector3(x + 0.75, 0, 0), 0.0), poses[i])
		_apply(_spawn(C + "sergeant_snap/sergeant_snap_v3.glb", Vector3(x - 0.75, 0, 0), 0.0), poses[i])
		_label(names[i] + ": v2 | v3", Vector3(x, 2.15, 0))
		var zc := 3.4 if back else -3.4
		_cam("Cam_snap4_P%d" % i, Vector3(x, 1.25, zc), Vector3(x, 1.0, 0), 45.0)
	_cam("Cam_snap4", Vector3(-6.8, 2.2, 10.5 if back else -10.5), Vector3(-6.8, 0.95, 0), 50.0)

## Hand-socket test for Snap v3 (posed-basis aiming): lance on hand_r in the idle, the thrust and the salute; drum on hips.
func _props4() -> void:
	var down50 := {"arm_l": [Vector3(0, 0, 1), -50.0], "arm_r": [Vector3(0, 0, 1), 50.0]}
	var fwd := {"arm_l": [Vector3(0, 0, 1), -45.0], "arm_r": [Vector3(1, 0, 0), -80.0]}
	var over := {"arm_l": [Vector3(0, 0, 1), -50.0], "arm_r": [Vector3(1, 0, 0), -140.0]}
	# figure 0 = the old props (glTF default gold metal 1.0 / rough 0.3, candy 0.28) for the before/after
	var props := ["snap_lance.glb", "snap_lance_v2.glb", "snap_sabre_v2.glb", "snap_mace_v2.glb"]
	var drums := ["snap_drum.glb", "snap_drum_v2.glb", "snap_drum_v2.glb", "snap_drum_v2.glb"]
	var i := 0
	for p in [down50, down50, fwd, over]:
		var n := _spawn(C + "sergeant_snap/sergeant_snap_v3.glb", Vector3(3.6 - 2.4 * i, 0, 0), 0.0)
		_apply(n, p)
		var sk := _skel(n)
		var hand := sk.find_bone("hand_r")
		var att := BoneAttachment3D.new()
		att.bone_name = "hand_r"
		sk.add_child(att)
		var w := (load(C + "sergeant_snap/" + props[i]) as PackedScene).instantiate() as Node3D
		att.add_child(w)
		var hb := sk.get_bone_global_pose(hand).basis.orthonormalized()
		var arm_dir := (sk.get_bone_global_pose(hand).origin - sk.get_bone_global_pose(sk.find_bone("forearm_r")).origin).normalized()
		var up := Vector3(0, 1, 0.18).normalized() if i <= 1 else (arm_dir if i == 2 else Vector3(0, 1, 0.3).normalized())
		var side := Vector3(1, 0, 0)
		var fwd_v := side.cross(up).normalized()
		side = up.cross(fwd_v).normalized()
		w.transform = Transform3D(hb.inverse() * Basis(side, up, fwd_v), Vector3.ZERO)
		var hips := sk.find_bone("hips")
		var hatt := BoneAttachment3D.new()
		hatt.bone_name = "hips"
		sk.add_child(hatt)
		var drum := (load(C + "sergeant_snap/" + drums[i]) as PackedScene).instantiate() as Node3D
		hatt.add_child(drum)
		var hr := sk.get_bone_global_rest(hips).basis.orthonormalized()
		drum.transform = Transform3D(hr.inverse() * Basis(Vector3(1, 0, 0), deg_to_rad(15.0)), hr.inverse() * Vector3(0.30, -0.05, 0.25))
		i += 1
	_label("old props | v2 props: lance (idle) / sabre (thrust) / mace (raised), drum on hips", Vector3(0, 2.6, 0))
	_cam("Cam_props4", Vector3(0.0, 1.5, -7.4), Vector3(0, 1.1, 0), 50.0)
	_cam("Cam_props4_Close", Vector3(2.4, 1.3, -3.0), Vector3(2.4, 1.0, 0), 45.0)

## Round 4 motion loop: Snap v3 marching with an arm sweep from idle through thrust to overhead (shoulder ball check).
func _motion4() -> void:
	var a := _skel(_spawn(C + "sergeant_snap/sergeant_snap_v2.glb", Vector3(1.2, 0, 0), 20.0))
	var b := _skel(_spawn(C + "sergeant_snap/sergeant_snap_v3.glb", Vector3(-1.2, 0, 0), 20.0))
	for sk in [a, b]:
		_anim.append([sk, [["arm_l", Vector3(0, 0, 1), -50.0, 0.0, 2.0, 0.0], ["arm_r", Vector3(1, 0, 0), -70.0, 70.0, 3.0, 0.0],
			["thigh_l", Vector3(1, 0, 0), 0.0, 25.0, 1.2, 0.0], ["thigh_r", Vector3(1, 0, 0), 0.0, -25.0, 1.2, 0.0]]])
	_label("v2", Vector3(1.2, 2.2, 0))
	_label("v3", Vector3(-1.2, 2.2, 0))
	_cam("Cam_motion4", Vector3(-1.2, 1.7, -5.6), Vector3(0, 1.0, 0), 50.0)

## Motion loop for Movie Maker: Snap lowers/raises and marches, Daisy chews and grazes, the scarecrow turns its head
## (hat on the head bone), the giant does the startle sit-up with the arms block and sleeves.
func _motion() -> void:
	var snap := _skel(_spawn(C + "sergeant_snap/sergeant_snap_v2.glb", Vector3(0, 0, 0), 0.0))
	_anim.append([snap, [["arm_l", Vector3(0, 0, 1), -20.0, 35.0, 2.4, 0.0], ["arm_r", Vector3(0, 0, 1), 20.0, -35.0, 2.4, 0.0],
		["thigh_l", Vector3(1, 0, 0), 0.0, 25.0, 1.2, 0.0], ["thigh_r", Vector3(1, 0, 0), 0.0, -25.0, 1.2, 0.0]]])
	var cow := _skel(_spawn(C + "daisy_cow/daisy_cow_v2.glb", Vector3(-3.2, 0, 0.5), 60.0))
	_anim.append([cow, [["jaw", Vector3(1, 0, 0), -6.0, 6.0, 0.6, 0.0], ["head", Vector3(1, 0, 0), 12.0, 14.0, 4.0, 0.0]]])
	var sc := _skel(_spawn(C + "wolf_scarecrow/wolf_scarecrow_v2.glb", Vector3(4.2, 0, 2.5), 0.0, 0.6))
	_anim.append([sc, [["head", Vector3(0, 1, 0), 0.0, 12.0, 3.0, 0.0]]])
	var gi := _skel(_spawn(C + "sleeping_giant/sleeping_giant_v2.glb", Vector3(0.5, 0, 9.0), 0.0, 0.5))
	_anim.append([gi, [["chest", Vector3(1, 0, 0), -9.0, 9.0, 3.0, PI], ["arms", Vector3(1, 0, 0), -10.0, 10.0, 3.0, PI],
		["upperarm_l", Vector3(0, 0, 1), 7.0, 7.0, 3.0, PI], ["upperarm_r", Vector3(0, 0, 1), -7.0, -7.0, 3.0, PI]]])
	_cam("Cam_motion", Vector3(0.3, 2.6, -7.5), Vector3(0.3, 1.2, 2.0), 55.0)

# ---------------------------------------------------------------- helpers (same conventions as the critic scenes)

func _row(path: String, poses: Array, dx: float, x0: float, z: float, scale := 1.0) -> void:
	var i := 0
	for p in poses:
		var yaw := 0.0
		if p.has("_yaw"):
			yaw = p["_yaw"]
		var n := _spawn(C + path, Vector3(x0 + i * dx, 0, z), yaw, scale)
		_apply(n, p)
		i += 1

func _apply(n: Node3D, pose: Dictionary) -> void:
	var s := _skel(n)
	if s == null:
		return
	for bone in pose.keys():
		if String(bone).begins_with("_"):
			continue
		_rot_model(s, bone, pose[bone][0], pose[bone][1])

func _spawn(path: String, pos: Vector3, yaw_deg: float, scale := 1.0) -> Node3D:
	var visual := Node3D.new()
	add_child(visual)
	visual.position = pos
	visual.rotation_degrees = Vector3(0, 180.0 + yaw_deg, 0)
	visual.scale = Vector3.ONE * scale
	var n := (load(path) as PackedScene).instantiate() as Node3D
	visual.add_child(n)
	return n

func _skel(n: Node3D) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return s[0] as Skeleton3D if s.size() > 0 else null

func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var i := skel.find_bone(bone)
	if i < 0:
		return
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

func _label(t: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = t
	l.position = pos
	l.rotation_degrees = Vector3(0, 180, 0)
	l.font_size = 64
	l.pixel_size = 0.004
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)

func _cam(n: String, pos: Vector3, target: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.name = n
	cam.fov = fov
	add_child(cam)
	cam.look_at_from_position(pos, target)

func _stage() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.62, 0.9)
	sm.sky_horizon_color = Color(0.86, 0.88, 0.92)
	sm.ground_horizon_color = Color(0.8, 0.76, 0.7)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 155, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.72, 0.52)
	ground.material_override = gm
	add_child(ground)
