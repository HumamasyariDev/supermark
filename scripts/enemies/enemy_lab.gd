extends Node3D
## EnemyLab: one pen per enemy family, story cameras, and a scripted test (pass --labtest)
## that drives a player through stomps and punches against each family and reports results.
## Args (after --): --labtest, --labtest-out=<abs json>, --shots=<abs dir>, --showcase, --only=<family>

const FAMILIES: Array[Dictionary] = [
	{"id": "woolly_wolf", "script": "res://scripts/enemies/woolly_wolf.gd", "x": -27.5},
	{"id": "crow_bandit", "script": "res://scripts/enemies/crow_bandit.gd", "x": -16.5},
	{"id": "peapod_popper", "script": "res://scripts/enemies/peapod_popper.gd", "x": -5.5},
	{"id": "bumble_bruiser", "script": "res://scripts/enemies/bumble_bruiser.gd", "x": 5.5},
	{"id": "gingerbread_grenadier", "script": "res://scripts/enemies/gingerbread_grenadier.gd", "x": 16.5},
	{"id": "gummy_brute", "script": "res://scripts/enemies/gummy_brute.gd", "x": 27.5},
]

var player: Node3D
var enemies: Dictionary = {}
var pens: Dictionary = {}
var follow_cam: Camera3D
var cam_target: Vector3 = Vector3.ZERO
var cam_offset: Vector3 = Vector3(0, 5.5, 9.0)
var cam_look_up: float = 0.9


func _ready() -> void:
	if Dev.has_arg("juice-log"):
		var j := get_node_or_null("/root/Juice")
		if j != null and j.has_signal("fired"):
			j.connect("fired", func(n: String, p: Vector3, pa: Dictionary) -> void:
				print("[JuiceLog] %.2f %s %s %s" % [Time.get_ticks_msec() / 1000.0, n, p, pa.get("family", "")]))
	_build_environment()
	if Dev.has_arg("env"):
		FxEnvironments.apply(self, Dev.arg("env"))
	_build_ground()
	_build_cams()
	for f in FAMILIES:
		if Dev.has_arg("only") and not (f["id"] in Dev.arg("only").split(",")):
			continue
		_build_pen(f)
	_spawn_player()
	if Dev.has_arg("only") and pens.has(Dev.arg("only")):
		cam_target = (pens[Dev.arg("only")] as Node3D).global_position + Vector3(0, 0, -1.5)
		cam_offset = Vector3(2.5, 2.2, 5.0)
		follow_cam.global_position = cam_target + cam_offset
		player.global_position = cam_target + Vector3(-1.0, 0.1, 4.5)
	if Dev.has_arg("lineup"):
		_lineup()
	if Dev.has_arg("poses"):
		_poses(Dev.arg("poses"))
	if Dev.has_arg("reel"):
		_reel(Dev.arg("reel"))
	if Dev.has_arg("walk"):
		_walk_setup()
	if Dev.has_arg("grouptest"):
		_group_test()
	if Dev.has_arg("realstomp"):
		var rs := (load("res://scripts/enemies/enemy_lab_realstomp.gd") as GDScript).new() as Node
		rs.name = "RealStomp"
		add_child(rs)
		rs.call("start", self)
	if Dev.has_arg("labtest") or Dev.has_arg("showcase"):
		var tester := (load("res://scripts/enemies/enemy_lab_test.gd") as GDScript).new() as Node
		tester.name = "LabTest"
		add_child(tester)
		tester.call("start", self)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.5, 0.92)
	sm.sky_horizon_color = Color(0.72, 0.84, 0.96)
	sm.ground_horizon_color = Color(0.86, 0.9, 0.96)
	sm.ground_bottom_color = Color(0.3, 0.38, 0.28)
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.9, 0.97)
	env.fog_density = 0.004
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_ground() -> void:
	var sb := StaticBody3D.new()
	sb.name = "Ground"
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 36)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	add_child(sb)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(80, 1, 36)
	mi.mesh = bm
	mi.position = Vector3(0, -0.5, 0)
	mi.material_override = EnemyKit.mat(Color(0.46, 0.68, 0.34), 0.9, 0.0)
	sb.add_child(mi)


func add_block(pos: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = EnemyKit.mat(color, 0.85, 0.1)
	sb.add_child(mi)
	(parent if parent != null else self).add_child(sb)
	sb.global_position = pos
	return sb


func _build_cams() -> void:
	var cams := Node3D.new()
	cams.name = "StoryCams"
	add_child(cams)
	var defs := {
		"StoryCam_A": [Vector3(0, 16, 30), Vector3(0, 0, 0)],
		"StoryCam_B": [Vector3(-22, 3.2, 8), Vector3(-22, 0.8, 0)],
		"StoryCam_C": [Vector3(0, 3.2, 8), Vector3(0, 0.8, 0)],
		"StoryCam_D": [Vector3(22, 3.2, 8), Vector3(22, 0.8, 0)],
	}
	for k in defs.keys():
		var c := Camera3D.new()
		c.name = k
		c.fov = 50.0
		cams.add_child(c)
		var pos: Vector3 = defs[k][0]
		var look: Vector3 = defs[k][1]
		c.look_at_from_position(pos, look, Vector3.UP)
	follow_cam = Camera3D.new()
	follow_cam.name = "FollowCam"
	follow_cam.fov = 55.0
	add_child(follow_cam)
	follow_cam.look_at_from_position(Vector3(0, 6, 12), Vector3.ZERO, Vector3.UP)
	follow_cam.make_current()


func _build_pen(f: Dictionary) -> void:
	var x: float = f["x"]
	var id: String = f["id"]
	var pen := Node3D.new()
	pen.name = "Pen_" + id
	add_child(pen)
	pen.position = Vector3(x, 0, 0)
	pens[id] = pen
	# Low fence corners and a sign.
	var post_col := Color(0.62, 0.42, 0.26)
	for cx in [-4.6, 4.6]:
		for cz in [-5.5, 5.5]:
			add_block(Vector3(x + cx, 0.4, cz), Vector3(0.3, 0.8, 0.3), post_col)
	var sign := Label3D.new()
	sign.text = id.replace("_", " ").capitalize()
	sign.font_size = 72
	sign.outline_size = 18
	sign.pixel_size = 0.008
	sign.position = Vector3(x, 2.8, -5.6)
	add_child(sign)
	var spawn := Vector3(x, 0.05, -1.5)
	var scr := load(f["script"]) as GDScript
	if scr == null:
		push_warning("[EnemyLab] missing script " + str(f["script"]))
		return
	match id:
		"crow_bandit":
			add_block(Vector3(x, 1.5, -4.0), Vector3(0.5, 3.0, 0.5), Color(0.5, 0.36, 0.24))
			add_block(Vector3(x, 3.05, -4.0), Vector3(1.2, 0.1, 0.4), Color(0.4, 0.28, 0.18))
			spawn = Vector3(x, 3.15, -4.0)
		"bumble_bruiser":
			add_block(Vector3(x, 1.5, -5.0), Vector3(8.0, 3.0, 0.6), Color(0.78, 0.6, 0.42))
			spawn = Vector3(x, 0.0, 1.5)
		"gingerbread_grenadier":
			var squad: Array = []
			for i in 3:
				var g := scr.new() as EnemyBase
				g.name = "Grenadier_%d" % i
				g.patrol_points = [Vector3(-2.5, 0, 0), Vector3(2.5, 0, 0)]
				g.set("formation_index", i)
				pen.add_child(g)
				g.global_position = Vector3(x - 1.1 + 1.1 * i, 0.05, -2.5 - 0.0 * i)
				squad.append(g)
				enemies["%s_%d" % [id, i]] = g
			for g in squad:
				g.set("squad", squad)
			enemies[id] = squad[1]
			return
	var e := scr.new() as EnemyBase
	e.name = id
	pen.add_child(e)
	e.global_position = spawn
	e.rotation.y = 0.0
	enemies[id] = e


## Portrait line-up of every family for story captures (--lineup).
func _lineup() -> void:
	var order := ["woolly_wolf", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]
	var x := -6.0
	for id in order:
		var e := enemies.get(id) as EnemyBase
		if e == null:
			continue
		e.ai_enabled = false
		var y := 0.05
		if id == "crow_bandit":
			y = 1.3
		elif id == "bumble_bruiser":
			y = 0.9
		e.global_position = Vector3(x, y, 11.0)
		e.home = e.global_position
		e.rotation.y = PI
		e.look_target = Vector3(x * 0.3, 1.0, 19.0)
		e.reset_physics_interpolation()
		if Dev.has_arg("lineup-state"):
			e.state = Dev.arg("lineup-state")
		x += 2.4
	for k in enemies.keys():
		var raw: Variant = enemies[k]
		if is_instance_valid(raw) and String(k).begins_with("gingerbread_grenadier_") and raw != enemies["gingerbread_grenadier"]:
			(raw as Node3D).queue_free()
	player.global_position = Vector3(0, 0.1, -14)
	cam_target = Vector3(0, 0.1, 11.0)
	cam_offset = Vector3(0, 1.9, 9.6)
	if Dev.has_arg("lineup-close"):
		cam_target = Vector3(0, 0.2, 11.0)
		cam_offset = Vector3(0, 1.0, 7.8)
	follow_cam.global_position = cam_target + cam_offset
	follow_cam.fov = 52.0


## --poses=<family>: one copy of the family per state in a row, AI off, for pose review sheets.
## --pose-states=idle,notice,... overrides the row; --pose-yaw=<deg> turns them (0 faces the camera).
func _poses(id: String) -> void:
	var states := ["idle", "notice", "windup", "attack", "recover", "dizzy"]
	match id:
		"crow_bandit":
			states = ["perch", "notice", "windup", "attack", "recover", "return"]
		"bumble_bruiser":
			states = ["hover", "notice", "windup", "attack", "recover", "dizzy"]
		"peapod_popper":
			states = ["idle", "notice", "windup", "attack", "recover", "idle"]
		"gingerbread_grenadier":
			states = ["patrol", "notice", "windup", "attack", "recover", "advance"]
		"gummy_brute":
			states = ["idle", "notice", "windup", "attack", "recover", "stalk"]
		"woolly_wolf":
			states = ["idle", "notice", "windup", "attack", "skid", "dizzy"]
	if Dev.has_arg("pose-states"):
		states = Array(Dev.arg("pose-states").split(","))
	var yaw := deg_to_rad(float(Dev.arg("pose-yaw", "0")))
	for k in enemies.keys():
		var raw: Variant = enemies[k]
		if is_instance_valid(raw):
			(raw as Node3D).queue_free()
	enemies.clear()
	var fam: Dictionary = {}
	for f in FAMILIES:
		if f["id"] == id:
			fam = f
	if fam.is_empty():
		return
	var scr := load(fam["script"]) as GDScript
	var gap := 2.3 if id == "gummy_brute" else 1.45
	var x := -float(states.size() - 1) * 0.5 * gap
	var i := 0
	for st in states:
		var e := scr.new() as EnemyBase
		e.name = "%s_%d" % [id, i]
		e.ai_enabled = false
		add_child(e)
		var y := 0.05
		if id == "crow_bandit" or id == "bumble_bruiser":
			y = 0.9
		e.global_position = Vector3(x, y, 11.0)
		e.home = e.global_position
		e.rotation.y = PI + yaw
		e._last_yaw = e.rotation.y
		e.look_target = Vector3(x * 0.3, 1.0, 19.0)
		e.reset_physics_interpolation()
		e.state = String(st)
		e.set_meta("pose_label", st)
		if id == "woolly_wolf" and not (String(st) in ["idle", "notice"]):
			# Every state after the reveal is posed on the unmasked cub, as in the game.
			e.set("disguised", false)
			e.call_deferred("_swap_to_cub_mesh")
		var l := Label3D.new()
		l.text = String(st)
		l.font_size = 48
		l.outline_size = 12
		l.pixel_size = 0.006
		add_child(l)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.global_position = Vector3(x, 0.12, 12.4)
		enemies["%s_%d" % [id, i]] = e
		x += gap
		i += 1
	player.global_position = Vector3(0, 0.1, -14)
	cam_target = Vector3(0, 0.1, 11.0)
	cam_offset = Vector3(0, 1.1, 5.4)
	if id == "gummy_brute":
		cam_offset = Vector3(0, 1.9, 8.6)
	elif id == "crow_bandit" or id == "bumble_bruiser":
		cam_offset = Vector3(0, 1.6, 5.4)
	follow_cam.global_position = cam_target + cam_offset
	follow_cam.fov = 52.0


## --reel=<family>: one enemy, AI off, scripted through every state and its defeat gag for close review
## clips (the lab player is hidden off to the side so projectiles and look-at still have a target).
func _reel(id: String) -> void:
	_poses(id)
	var keep: EnemyBase = null
	for k in enemies.keys():
		var e := enemies[k] as EnemyBase
		if keep == null:
			keep = e
		else:
			e.queue_free()
	for c in get_children():
		if c is Label3D and c.global_position.z > 12.0:
			c.queue_free()
	var e := keep
	var y := e.global_position.y
	e.global_position = Vector3(0, y, 11.0)
	e.home = e.global_position
	e.rotation.y = PI - 0.5
	e._last_yaw = e.rotation.y
	e.reset_physics_interpolation()
	player.global_position = Vector3(-4.0, 0.1, 16.0)
	player.visible = false
	cam_target = Vector3(0, y + (0.6 if id == "gummy_brute" else 0.15), 11.0)
	cam_offset = Vector3(0.45, 0.75, 3.5) if id != "gummy_brute" else Vector3(0.7, 1.3, 5.6)
	cam_look_up = 0.45 if id != "gummy_brute" else 0.8
	for c in get_children():
		if c is Label3D:
			c.visible = false
	follow_cam.global_position = cam_target + cam_offset
	follow_cam.fov = 45.0
	var hold := func(st: String, t: float) -> void:
		e.set_state(st)
		await get_tree().create_timer(t).timeout
	await get_tree().create_timer(0.8).timeout
	var first := String(e.state)
	e.set_state(first)
	await get_tree().create_timer(2.6).timeout
	e.notice_player("!", "")
	if id == "woolly_wolf":
		await get_tree().create_timer(0.38).timeout
		e.call("_rip_costume")
		await get_tree().create_timer(0.8).timeout
	else:
		await get_tree().create_timer(1.0).timeout
	await hold.call("windup", 1.0)
	e.set_state("attack")
	if id == "peapod_popper":
		for i in 3:
			e.call("_fire")
			await get_tree().create_timer(0.45).timeout
	elif id == "gummy_brute":
		await get_tree().create_timer(0.5).timeout
		e.call("_slam")
	else:
		await get_tree().create_timer(0.9).timeout
	match id:
		"woolly_wolf":
			await hold.call("skid", 1.0)
			e.call("_bonk")
			await get_tree().create_timer(2.0).timeout
		"bumble_bruiser":
			e.call("_bonk")
			await get_tree().create_timer(2.4).timeout
		"gummy_brute":
			await get_tree().create_timer(1.2).timeout
		_:
			await hold.call("recover", 1.4)
	var behind := e.global_position + e.global_transform.basis.z * 1.5 + Vector3(0, 0.5, 0)
	if e.max_hp > 1:
		e.hit_by_player("punch", behind)
		await get_tree().create_timer(1.4).timeout
		if id == "gummy_brute":
			e.set_state("recover")
	if Dev.arg("reel-defeat") == "stomp":
		# Lethal stomp from above: shows the pancake beat before the family's gag (critic request).
		e.hp = 1
		e.hit_by_player("stomp", e.global_position + Vector3(0, e.head_height + 0.4, 0))
	else:
		e.hit_by_player("punch", behind)
	await get_tree().create_timer(3.0).timeout
	print("[Reel] done ", id)


## --grouptest: Sergeant Snap's squad inside an EnemyGroup must award truffle W3-2 when cleared.
func _group_test() -> void:
	var grp := EnemyGroup.new()
	grp.name = "SnapGroup"
	grp.truffle_id = "W3-2"
	grp.mission_title = "Sergeant Snap"
	add_child(grp)
	grp.global_position = Vector3(0, 0, 13)
	var squad := GingerbreadSquad.new()
	squad.size = 2
	squad.with_sergeant = true
	grp.add_child(squad)
	squad.global_position = Vector3(0, 0, 13)
	cam_target = Vector3(0, 0.5, 13)
	cam_offset = Vector3(0, 2.4, 6.0)
	await get_tree().create_timer(2.0).timeout
	var snap := squad.members[0] as EnemyBase
	print("[GroupTest] members=", squad.members.size(), " sergeant=", snap.display_name, " hp=", snap.hp, " group remaining=", grp.remaining)
	for m in squad.members:
		(m as EnemyBase).defeat("stomp", (m as Node3D).global_position + Vector3(0, 2, 0))
		await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(2.5).timeout
	var found := false
	for t in get_tree().get_nodes_in_group("truffle"):
		if String(t.get("truffle_id")) == "W3-2":
			found = true
	print("[GroupTest] cleared, truffle W3-2 spawned: ", found)


func _spawn_player() -> void:
	var p: Node3D
	if Dev.has_arg("real-player") and ResourceLoader.exists("res://scenes/player/Player.tscn"):
		p = (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Node3D
	else:
		p = EnemyLabPlayer.new()
	p.name = "Player"
	add_child(p)
	p.global_position = Vector3(0, 0.1, 8)
	player = p


func _process(delta: float) -> void:
	if not _walkers.is_empty():
		_walk_sheep_step(delta)
		if _walk_follow != null and is_instance_valid(_walk_follow):
			cam_target = cam_target.lerp(Vector3(_walk_follow.global_position.x, 0.2, 10.0), 1.0 - exp(-4.0 * delta))
	if follow_cam != null and follow_cam.current:
		var want := cam_target + cam_offset
		follow_cam.global_position = follow_cam.global_position.lerp(want, 1.0 - exp(-3.0 * delta))
		follow_cam.look_at(cam_target + Vector3(0, cam_look_up, 0), Vector3.UP)


# ------------------------------------------------------------------ walk review (LEGS pass, 2026-10-19)

## --walk: the walking families and a W1 sheep in lanes with AI off, for leg review clips. Timeline per lane: stand,
## walk right, stop and turn round, run left, stop. The lab drives velocity (enemies) or position (the sheep, which
## W1 moves with tweens), so the families animate from real ground motion. --walk-close moves the camera in.
var _walkers: Array[Dictionary] = []
var _walk_t := 0.0
var _walk_follow: Node3D
const WALK_X0 := -3.0
const WALK_RUN_DIST := 5.5


func _walk_setup() -> void:
	for k in enemies.keys():
		var raw: Variant = enemies[k]
		if is_instance_valid(raw):
			(raw as Node3D).queue_free()
	enemies.clear()
	# id, walk state, run state, walk speed, run speed, lane z, disguised
	var rows := [
		["gummy_brute", "stalk", "stalk", 1.2, 2.2, 3.6, false],
		["gingerbread_grenadier", "patrol", "advance", 1.6, 2.4, 6.4, false],
		["woolly_wolf", "prowl", "attack", 1.5, 6.5, 8.9, false],
		["woolly_wolf", "idle", "idle", 1.0, 2.2, 11.3, true],
	]
	# --walk=<one>: gummy_brute, gingerbread_grenadier, wolf_cub, wolf_disguised or sheep, alone in lane z 10 with
	# a gameplay-distance follow camera (about 7 m, 20 degrees down).
	var one := Dev.arg("walk")
	var keys := ["gummy_brute", "gingerbread_grenadier", "wolf_cub", "wolf_disguised", "sheep"]
	var solo := one in keys
	for ri in rows.size():
		var r: Array = rows[ri]
		if solo and keys[ri] != one:
			continue
		if solo:
			r[5] = 10.0
		var fam: Dictionary = {}
		for f in FAMILIES:
			if f["id"] == r[0]:
				fam = f
		var e := (load(fam["script"]) as GDScript).new() as EnemyBase
		e.name = "Walk_%s_%d" % [r[0], _walkers.size()]
		e.ai_enabled = false
		add_child(e)
		e.global_position = Vector3(WALK_X0, 0.05, float(r[5]))
		e.home = e.global_position
		e.rotation.y = -PI * 0.5
		e._last_yaw = e.rotation.y
		e.reset_physics_interpolation()
		e.state = String(r[1])
		if r[0] == "woolly_wolf" and not bool(r[6]):
			e.set("disguised", false)
			e.call_deferred("_swap_to_cub_mesh")
		_walkers.append({"node": e, "walk": r[1], "run": r[2], "vw": r[3], "vr": r[4], "sheep": false})
	# A W1 sheep (oatmeal tint, NpcLife attached as NpcLifeAuto does in W1), moved by position like the W1 tweens.
	var sp := "res://assets/characters/real_sheep/real_sheep_v2.glb"
	if ResourceLoader.exists(sp) and (not solo or one == "sheep"):
		var holder := Node3D.new()
		holder.name = "WalkSheep"
		add_child(holder)
		holder.position = Vector3(WALK_X0, 0.0, 10.0 if solo else 13.8)
		holder.rotation.y = PI * 0.5
		var inst := (load(sp) as PackedScene).instantiate() as Node3D
		holder.add_child(inst)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			for si in m3.mesh.get_surface_count():
				var mat := m3.get_active_material(si)
				if mat is BaseMaterial3D:
					var dm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dm.albedo_color = Color(0.9, 0.84, 0.72)
					m3.set_surface_override_material(si, dm)
		NpcLife.attach(inst)
		_walkers.append({"node": holder, "walk": "", "run": "", "vw": 0.45, "vr": 1.2, "sheep": true})
	player.global_position = Vector3(0, 0.1, -14)
	player.visible = false
	cam_target = Vector3(-1.4, 0.2, 8.6)
	cam_offset = Vector3(0, 4.4, 7.6)
	cam_look_up = 0.5
	if Dev.has_arg("walk-close"):
		cam_target = Vector3(-1.2, 0.2, 10.0)
		cam_offset = Vector3(0, 2.0, 5.2)
	if solo:
		_walk_follow = (_walkers[0] as Dictionary)["node"]
		cam_offset = Vector3(0, 2.5, 6.6)
		if Dev.has_arg("walk-static"):
			# Fixed side camera close to the lane (planted feet must hold still against the ground).
			_walk_follow = null
			cam_offset = Vector3(0, 0.9, 3.6)
			cam_look_up = 0.25
			cam_target = Vector3(-1.2, 0.2, 10.0)
		cam_look_up = 0.45
		if _walk_follow != null:
			cam_target = _walk_follow.global_position
	follow_cam.global_position = cam_target + cam_offset
	follow_cam.fov = 50.0


func _physics_process(delta: float) -> void:
	if _walkers.is_empty():
		return
	_walk_t += delta
	for w in _walkers:
		var n: Node3D = w["node"]
		if not is_instance_valid(n):
			continue
		var t := _walk_t
		var v := 0.0
		var dir := 1.0
		var st := String(w["walk"])
		var t_run: float = WALK_RUN_DIST / float(w["vr"])
		if t < 0.6:
			v = 0.0
		elif t < 3.6:
			v = float(w["vw"]) * clampf((t - 0.6) / 0.3, 0.0, 1.0)
		elif t < 4.8:
			v = 0.0
		elif t < 4.8 + t_run:
			v = float(w["vr"]) * clampf((t - 4.8) / 0.25, 0.0, 1.0)
			dir = -1.0
			st = String(w["run"])
		else:
			v = 0.0
			dir = -1.0
		# Turn round during the stop (in-place turn), face left for the run.
		var yaw_r := -PI * 0.5 if not bool(w["sheep"]) else PI * 0.5
		var yaw_l := PI * 0.5 if not bool(w["sheep"]) else -PI * 0.5
		var u := clampf((t - 3.9) / 0.7, 0.0, 1.0)
		var yaw := lerp_angle(yaw_r, yaw_l, u * u * (3.0 - 2.0 * u))
		if bool(w["sheep"]):
			continue
		var e := n as EnemyBase
		if st != "" and e.state != st and not (st == "attack" and v == 0.0):
			e.state = st
		if st == "attack" and v == 0.0 and t > 4.8:
			e.state = "prowl"
		e.rotation.y = yaw
		# Compensate the 20/s velocity decay EnemyBase applies with AI off (the lab runs before its children).
		e.velocity.x = dir * (v + 20.0 * delta) if v > 0.0 else 0.0
		e.velocity.z = 0.0


func _walk_sheep_step(delta: float) -> void:
	var t := _walk_t
	for w in _walkers:
		if not bool(w["sheep"]):
			continue
		var n: Node3D = w["node"]
		var v := 0.0
		var dir := 1.0
		var t_run: float = WALK_RUN_DIST / float(w["vr"])
		if t < 0.6:
			v = 0.0
		elif t < 3.6:
			v = float(w["vw"]) * clampf((t - 0.6) / 0.3, 0.0, 1.0)
		elif t < 4.8:
			v = 0.0
		elif t < 4.8 + minf(t_run, 4.0):
			v = float(w["vr"]) * clampf((t - 4.8) / 0.25, 0.0, 1.0)
			dir = -1.0
		var u := clampf((t - 3.9) / 0.7, 0.0, 1.0)
		n.rotation.y = lerp_angle(PI * 0.5, -PI * 0.5, u * u * (3.0 - 2.0 * u))
		n.position.x += dir * v * delta
