extends Node3D
## Enemies critique, round 1 (lens: encounter design and fairness). Read-only probes against the shipped
## enemy scenes and the real player (res://scenes/player/Player.tscn). Nothing here changes track files.
##
## Modes (after --):
##   --mode=lab     [--only=side_stomp,charge_hop,sidestep,shockwave,ledge] [--crit-out=<abs json>]
##   --mode=census  --world=res://scenes/worlds/w3/W3.tscn [--crit-out=<abs json>]
##   --mode=show    --show=sidestep_wolf|side_stomp_wolf|sergeant_w3 (framed beat for capture/movie)
## Always pass --profile=crit-enemies.

const FAMS := {"woolly_wolf": "WoollyWolf", "crow_bandit": "CrowBandit", "peapod_popper": "PeapodPopper",
	"bumble_bruiser": "BumbleBruiser", "gingerbread_grenadier": "GingerbreadGrenadier", "gummy_brute": "GummyBrute"}

var player: Node3D
var cam: Camera3D
var out: Dictionary = {}
var cam_focus: Vector3 = Vector3.ZERO
var cam_off: Vector3 = Vector3(5, 4, 7)
var _hits: Array = []


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.make_current()
	var mode := Dev.arg("mode", "lab")
	out["mode"] = mode
	out["utc"] = Time.get_datetime_string_from_system(true) + "Z"
	if mode == "census":
		_census.call_deferred()
	else:
		_build_arena()
		_spawn_player()
		if mode == "show":
			_show.call_deferred()
		else:
			_lab.call_deferred()


func _process(_delta: float) -> void:
	if cam != null and Dev.arg("mode", "lab") != "census":
		if not cam.current:
			cam.make_current()
		cam.global_position = cam_focus + cam_off
		cam.look_at(cam_focus, Vector3.UP)


# ------------------------------------------------------------------ arena

func _box(pos: Vector3, size: Vector3, col: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	sb.add_child(mi)
	add_child(sb)
	sb.global_position = pos
	return sb


func _build_arena() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.78, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	# Main floor (x -60..60, z -20..20), top at y 0, with a 1 m grid of darker stripes for scale.
	_box(Vector3(0, -0.5, 0), Vector3(120, 1, 40), Color(0.55, 0.72, 0.45))
	for i in range(-10, 11):
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.005, 40)
		line.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.5, 0.3)
		line.material_override = m
		add_child(line)
		line.global_position = Vector3(float(i), 0.003, 0)
	# Ledge rig far away (x 200): a floating 8x8 platform at y 4 with nothing below on the +X side.
	_box(Vector3(200, 3.5, 0), Vector3(8, 1, 8), Color(0.7, 0.6, 0.5))
	_box(Vector3(200 - 4 - 6, -0.5, 0), Vector3(12, 1, 12), Color(0.5, 0.6, 0.45))


func _spawn_player() -> void:
	var ps := load("res://scenes/player/Player.tscn") as PackedScene
	player = ps.instantiate() as Node3D
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0, 0.1, 15)


func _place(at: Vector3) -> void:
	player.call("respawn", Transform3D(Basis(), at))
	player.set("invulnerable", 0.0)


func _health() -> int:
	return int(EnemyKit.game_get(self, "health", 6))


func _heal() -> void:
	EnemyKit.game_call(self, "full_heal")


func _spawn(fam: String, at: Vector3, props: Dictionary = {}) -> EnemyBase:
	var ps := load("res://scenes/enemies/%s.tscn" % FAMS[fam]) as PackedScene
	var n := ps.instantiate() as EnemyBase
	for k in props:
		n.set(k, props[k])
	add_child(n)
	n.global_position = at
	n.home = at
	n.hit_taken.connect(func(kind: String, landed: bool) -> void:
		_hits.append({"family": fam, "kind": kind, "landed": landed,
			"player_feet_rel": snappedf(player.global_position.y - n.global_position.y, 0.01),
			"player_flat": snappedf(Vector2(player.global_position.x - n.global_position.x, player.global_position.z - n.global_position.z).length(), 0.01),
			"head_height": n.head_height}))
	return n


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _clear_enemies() -> void:
	for c in get_children():
		if c is EnemyBase or c is PeaProjectile or c is GummyShockwave:
			c.queue_free()
	await _frames(3)


# ------------------------------------------------------------------ lab

func _want(s: String) -> bool:
	return not Dev.has_arg("only") or s in Dev.arg("only").split(",")


func _lab() -> void:
	await _frames(30)
	if _want("side_stomp"):
		await _side_stomp()
	if _want("charge_hop"):
		await _charge_hop()
	if _want("sidestep"):
		await _sidestep()
	if _want("shockwave"):
		await _shockwave()
	if _want("ledge"):
		await _ledge()
	_finish()


## S1: Mak drops past the SIDE of a frozen enemy (no body overlap, feet well below the head).
## A fair stomp needs the feet above the head; the enemy's own HeadZone rule is feet >= 0.6 x head height.
func _side_stomp() -> void:
	var rows: Array = []
	for fam in ["woolly_wolf", "gingerbread_grenadier", "gummy_brute", "peapod_popper", "bumble_bruiser", "crow_bandit"]:
		for drop_frac in [0.15, 0.45]:
			_hits.clear()
			_heal()
			var y0 := 0.9 if fam in ["bumble_bruiser", "crow_bandit"] else 0.0
			var e := _spawn(fam, Vector3(0, y0, 0), {"ai_enabled": false})
			await _frames(4)
			var d := e.body_radius + 0.45
			var start_rel: float = e.head_height * float(drop_frac) + 0.05
			cam_focus = e.global_position + Vector3(0, 0.6, 0)
			cam_off = Vector3(0.5, 1.2, 4.5)
			_place(e.global_position + Vector3(d, start_rel, 0))
			var h0 := _health()
			var st_seen: Array = []
			for f in 60:
				await get_tree().physics_frame
				var s: String = player.call("get_state_name")
				if not s in st_seen:
					st_seen.append(s)
			var row := {"family": fam, "lateral_offset_m": snappedf(d, 0.01), "drop_start_feet_rel_m": snappedf(start_rel, 0.01),
				"head_height": e.head_height if is_instance_valid(e) else -1.0,
				"hits": _hits.duplicate(true), "player_damage": h0 - _health(),
				"enemy_defeated": not is_instance_valid(e) or e.is_defeated, "player_states": st_seen}
			rows.append(row)
			print("[CritFair] side_stomp ", row)
			if is_instance_valid(e):
				e.queue_free()
			await _frames(30)
	out["side_stomp"] = rows


## S2: Mak hops into an incoming attack (wolf charge, bee charge, grenadier lunge). Which wins?
func _charge_hop() -> void:
	var rows: Array = []
	for fam in ["woolly_wolf", "bumble_bruiser", "gingerbread_grenadier"]:
		for h in [0.5, 0.9, 1.3, 1.8]:
			_hits.clear()
			_heal()
			var y0 := 0.3 if fam == "bumble_bruiser" else 0.0
			var props := {"ai_enabled": true}
			if fam == "woolly_wolf":
				props["disguised"] = false
			var e := _spawn(fam, Vector3(0, y0, 0), props)
			e.rotation.y = PI  # face +Z (toward Mak)
			await _frames(3)
			var gap := 3.2 if fam != "gingerbread_grenadier" else 1.9
			_place(Vector3(0, h, gap))
			cam_focus = Vector3(0, 0.6, gap * 0.5)
			cam_off = Vector3(5.0, 1.6, 0.5)
			if fam == "gingerbread_grenadier":
				e.set_state("attack")
			else:
				e.set("charge_dir", Vector3(0, 0, 1))
				e.set_state("attack")
			var h0 := _health()
			for f in 70:
				await get_tree().physics_frame
			var row := {"family": fam, "mak_feet_start_m": h, "gap_m": gap, "hits": _hits.duplicate(true),
				"player_damage": h0 - _health(), "enemy_defeated": not is_instance_valid(e) or e.is_defeated}
			rows.append(row)
			print("[CritFair] charge_hop ", row)
			if is_instance_valid(e):
				e.queue_free()
			await _frames(30)
	out["charge_hop"] = rows


## S3: after the charge direction locks and the danger strip is drawn, Mak (standing still) is moved
## sideways by X metres off the charge line: a perfect sidestep. Does a step that clears the DRAWN strip
## (half-width 0.45 wolf, 0.4 bee) avoid damage?
func _sidestep() -> void:
	var rows: Array = []
	for fam in ["woolly_wolf", "bumble_bruiser"]:
		for x in [0.5, 0.7, 0.9, 1.1, 1.3, 1.5]:
			_heal()
			var props := {"ai_enabled": true}
			if fam == "woolly_wolf":
				props["disguised"] = false
			var y0 := 1.4 if fam == "bumble_bruiser" else 0.0
			var e := _spawn(fam, Vector3(0, y0, 0), props)
			e.rotation.y = PI
			await _frames(3)
			_place(Vector3(0, 0.05, 7.0))
			await _frames(2)
			e.set_state("windup")
			var lock_t := 0.5 if fam == "woolly_wolf" else 0.6
			var moved := false
			var h0 := _health()
			var strip_w := -1.0
			var min_flat := 99.0
			for f in 200:
				await get_tree().physics_frame
				if not is_instance_valid(e):
					break
				if not moved and e.state == "windup" and e.state_time > lock_t:
					moved = true
					var cd: Vector3 = e.get("charge_dir")
					var side := cd.cross(Vector3.UP).normalized()
					var on_line := e.global_position + cd * 7.0
					_place(Vector3(on_line.x, 0.05, on_line.z) + side * x)
					var strip: Variant = e.get("_strip")
					if strip != null and is_instance_valid(strip):
						var mi := (strip as Node3D).find_children("*", "MeshInstance3D", true, false)
						if mi.size() > 0 and (mi[0] as MeshInstance3D).mesh is BoxMesh:
							strip_w = ((mi[0] as MeshInstance3D).mesh as BoxMesh).size.x
				if moved:
					var dd := player.global_position - e.global_position
					min_flat = minf(min_flat, Vector2(dd.x, dd.z).length())
				if moved and (e.state == "recover" or e.state == "skid" or e.state == "dizzy"):
					break
			var row := {"family": fam, "sidestep_m": x, "drawn_strip_width_m": strip_w,
				"contact_radius_m": e.body_radius + 0.5 if is_instance_valid(e) else -1.0,
				"player_damage": h0 - _health(), "closest_pass_m": snappedf(min_flat, 0.01)}
			rows.append(row)
			print("[CritFair] sidestep ", row)
			if is_instance_valid(e):
				e.queue_free()
			await _frames(20)
	out["sidestep"] = rows


## S4: a Gummy Brute shockwave expands from the origin; Mak stands still at distance D.
## Records the drawn ring (outer radius r, inner 0.82 r) at the moment of the hit.
func _shockwave() -> void:
	var rows: Array = []
	for dist in [1.4, 2.0, 2.6, 3.2, 4.0, 4.8, 5.4, 5.9]:
		_heal()
		_place(Vector3(dist, 0.05, 0))
		cam_focus = Vector3(dist * 0.5, 0, 0)
		cam_off = Vector3(0, 7, 6)
		await _frames(10)
		var h0 := _health()
		var w := GummyShockwave.new()
		w.max_radius = 5.0
		add_child(w)
		w.global_position = Vector3.ZERO
		var hit_r := -1.0
		for f in 60:
			await get_tree().physics_frame
			if hit_r < 0.0 and _health() < h0 and is_instance_valid(w):
				var u := clampf(w.t / w.duration, 0.0, 1.0)
				hit_r = lerpf(0.4, w.max_radius, 1.0 - pow(1.0 - u, 2.0))
			if not is_instance_valid(w):
				break
		var row := {"player_dist_m": dist, "hit": _health() < h0, "ring_outer_r_at_hit": snappedf(hit_r, 0.01),
			"gap_body_edge_to_drawn_ring_m": snappedf(dist - 0.35 - hit_r, 0.01) if hit_r > 0.0 else null}
		rows.append(row)
		print("[CritFair] shockwave ", row)
		await _frames(20)
	out["shockwave"] = rows


## S5: ground enemies at a ledge. A wolf charge and a gummy jump toward Mak standing below the platform.
func _ledge() -> void:
	var rows: Array = []
	# Wolf charging toward the open edge (+X).
	var w := _spawn("woolly_wolf", Vector3(198, 4.05, 0), {"disguised": false})
	w.rotation.y = -PI * 0.5
	await _frames(3)
	_place(Vector3(188, 0.1, 6))
	cam_focus = Vector3(200, 3, 0)
	cam_off = Vector3(0, 6, 16)
	w.set("charge_dir", Vector3(1, 0, 0))
	w.set_state("attack")
	var samples: Array = []
	for f in 240:
		await get_tree().physics_frame
		if f % 60 == 59:
			samples.append(snappedf(w.global_position.y, 0.1) if is_instance_valid(w) else null)
	rows.append({"case": "wolf_charge_off_edge", "wolf_y_each_second": samples, "still_in_tree": is_instance_valid(w),
		"state": w.state if is_instance_valid(w) else "freed"})
	print("[CritFair] ledge ", rows[-1])
	if is_instance_valid(w):
		w.queue_free()
	# Gummy on the platform, Mak on the lower ground 5 m beyond the edge.
	var g := _spawn("gummy_brute", Vector3(201.5, 4.05, 0), {})
	await _frames(3)
	_place(Vector3(207.5, 0.1, 0))
	_box(Vector3(208, -0.5, 0), Vector3(6, 1, 6), Color(0.5, 0.6, 0.45))
	await _frames(2)
	_place(Vector3(207.5, 0.1, 0))
	g.set_state("windup")
	var slam_y := -999.0
	var ring_y := -999.0
	var h0 := _health()
	for f in 300:
		await get_tree().physics_frame
		if not is_instance_valid(g):
			break
		if slam_y < -998.0 and g.state == "recover":
			slam_y = g.global_position.y
			for c in get_children():
				if c is GummyShockwave:
					ring_y = (c as Node3D).global_position.y
	rows.append({"case": "gummy_jump_off_edge", "gummy_y_at_slam": snappedf(slam_y, 0.01), "shockwave_y": snappedf(ring_y, 0.01),
		"mak_ground_y": 0.0, "gummy_final_y": snappedf(g.global_position.y, 0.01) if is_instance_valid(g) else null, "player_damage": h0 - _health()})
	print("[CritFair] ledge ", rows[-1])
	out["ledge"] = rows


# ------------------------------------------------------------------ census (real worlds)

func _census() -> void:
	var path := Dev.arg("world", "res://scenes/worlds/w3/W3.tscn")
	var ps := load(path) as PackedScene
	var world := ps.instantiate()
	add_child(world)
	out["world"] = path
	await _frames(150)
	var pl := EnemyKit.find_player(get_tree())
	if pl != null:
		pl.set("process_mode", Node.PROCESS_MODE_DISABLED)
	var rows: Array = []
	var all: Array[EnemyBase] = []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is EnemyBase:
			all.append(n as EnemyBase)
	for e in all:
		var row := {"name": String(e.name), "family": e.enemy_id, "pos": [snappedf(e.global_position.x, 0.1), snappedf(e.global_position.y, 0.1), snappedf(e.global_position.z, 0.1)],
			"max_hp": e.max_hp, "head_height": e.head_height, "body_radius": e.body_radius, "notice_radius": e.notice_radius,
			"ai_enabled": e.ai_enabled, "patrol_points": e.patrol_points.size(), "state": e.state,
			"visual_scale": snappedf(e.visual.scale.y, 0.001) if e.visual != null else 1.0,
			"visual_height_m": snappedf(_vis_height(e), 0.01), "hurtbox_top_m": snappedf(e.head_height + 0.2, 0.01),
			"headzone_top_m": snappedf(e.head_height + 0.45, 0.01), "mesh": e.mesh_path}
		if e.get("sergeant") != null:
			row["sergeant_flag"] = e.get("sergeant")
			row["has_drum"] = e.find_child("DrumSocket", true, false) != null
		var near := 0
		for o in all:
			if o != e and o.global_position.distance_to(e.global_position) < 10.0:
				near += 1
		row["others_within_10m"] = near
		if e.uses_gravity:
			row["ledge"] = _ledge_scan(e)
		rows.append(row)
		print("[CritCensus] ", row)
	out["enemies"] = rows
	if Dev.has_arg("probe"):
		var c := Dev.arg("probe").split(",")
		var pp := Vector3(float(c[0]), float(c[1]), float(c[2]))
		out["probe"] = {"at": [pp.x, pp.y, pp.z], "ledge": _ledge_scan_at(pp)}
		print("[CritCensus] probe ", out["probe"])
	if Dev.has_arg("track"):
		var tr: Array = []
		for k in 4:
			await _frames(120)
			for e in all:
				if is_instance_valid(e) and String(e.name) == Dev.arg("track"):
					tr.append({"frame_after_census": (k + 1) * 120, "pos": [snappedf(e.global_position.x, 0.1), snappedf(e.global_position.y, 0.1), snappedf(e.global_position.z, 0.1)], "state": e.state})
		out["track"] = tr
		print("[CritCensus] track ", tr)
	if Dev.has_arg("frame"):
		var tgt: EnemyBase = null
		for e in all:
			if is_instance_valid(e) and String(e.name) == Dev.arg("frame"):
				tgt = e
		if tgt != null:
			var o := Dev.arg("frame-off", "2.2,1.4,4.2").split(",")
			if pl != null and Dev.has_arg("mak-beside"):
				pl.set("process_mode", Node.PROCESS_MODE_INHERIT)
				pl.call("respawn", Transform3D(Basis(), tgt.global_position + tgt.global_transform.basis.x * -1.3 + Vector3(0, 0.1, 0)))
				await _frames(20)
				pl.set("process_mode", Node.PROCESS_MODE_DISABLED)
			tgt.ai_enabled = false
			if Dev.has_arg("draw-boxes"):
				_draw_boxes(tgt)
			cam.global_position = tgt.global_position + Vector3(float(o[0]), float(o[1]), float(o[2]))
			cam.look_at(tgt.global_position + Vector3(0, 0.9, 0), Vector3.UP)
			cam.make_current()
			await _frames(40)
			if Dev.has_arg("shot"):
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.save_png(Dev.arg("shot"))
				print("[CritCensus] shot -> ", Dev.arg("shot"))
	_finish()


## Review overlay: the hurtbox capsule (red) and the HeadZone stomp cylinder (yellow) as built by EnemyBase.
func _draw_boxes(e: EnemyBase) -> void:
	for spec in [[e.hurtbox, Color(1, 0.15, 0.1, 0.32)], [e.head_zone, Color(1, 0.9, 0.1, 0.4)]]:
		var area := spec[0] as Area3D
		for cs in area.get_children():
			if not cs is CollisionShape3D:
				continue
			var shp := (cs as CollisionShape3D).shape
			var mi := MeshInstance3D.new()
			if shp is CapsuleShape3D:
				var cm := CapsuleMesh.new()
				cm.radius = (shp as CapsuleShape3D).radius
				cm.height = (shp as CapsuleShape3D).height
				mi.mesh = cm
			elif shp is CylinderShape3D:
				var cy := CylinderMesh.new()
				cy.top_radius = (shp as CylinderShape3D).radius
				cy.bottom_radius = (shp as CylinderShape3D).radius
				cy.height = (shp as CylinderShape3D).height
				mi.mesh = cy
			var m := StandardMaterial3D.new()
			m.albedo_color = spec[1]
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.no_depth_test = true
			mi.material_override = m
			add_child(mi)
			mi.global_transform = (cs as CollisionShape3D).global_transform


func _ledge_scan_at(base: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var rows: Array = []
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dir := Vector3(cos(a), 0, sin(a))
		var drop_at := 99.0
		var void_at := 99.0
		var dd := 0.5
		while dd <= 14.0:
			var p := base + dir * dd
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p + Vector3(0, -200, 0))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				void_at = minf(void_at, dd)
				drop_at = minf(drop_at, dd)
				break
			if base.y - (hit.position as Vector3).y > 2.5:
				drop_at = minf(drop_at, dd)
			dd += 0.5
		rows.append({"dir_deg": int(rad_to_deg(a)), "drop_m": drop_at, "void_m": void_at})
	return {"dirs": rows}


func _vis_height(e: EnemyBase) -> float:
	var lo := INF
	var hi := -INF
	for mi in e.visual.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var bb := m.global_transform * m.get_aabb()
		lo = minf(lo, bb.position.y)
		hi = maxf(hi, bb.end.y)
	return hi - lo if hi > lo else 0.0


## 16 directions: the distance at which the floor drops more than 2.5 m (or vanishes), up to 14 m.
func _ledge_scan(e: EnemyBase) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var dists: Array = []
	var base := e.global_position
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dir := Vector3(cos(a), 0, sin(a))
		var found := 99.0
		var dd := 0.5
		while dd <= 14.0:
			var p := base + dir * dd
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p + Vector3(0, -40, 0))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty() or base.y - (hit.position as Vector3).y > 2.5:
				found = dd
				break
			dd += 0.5
		dists.append(found)
	var mn: float = 99.0
	var within_6 := 0
	var within_13 := 0
	for d in dists:
		mn = minf(mn, float(d))
		if float(d) <= 6.0:
			within_6 += 1
		if float(d) <= 13.0:
			within_13 += 1
	return {"min_drop_dist_m": mn, "dirs_drop_within_6m": within_6, "dirs_drop_within_13m": within_13}


# ------------------------------------------------------------------ show beats (for captures)

func _show() -> void:
	await _frames(20)
	match Dev.arg("show", "sidestep_wolf"):
		"sidestep_wolf":
			var x := float(Dev.arg("x", "0.7"))
			var e := _spawn("woolly_wolf", Vector3(0, 0, 0), {"disguised": false})
			e.rotation.y = PI
			cam_focus = Vector3(0, 0, 4.0)
			cam_off = Vector3(0.01, 11.0, 2.5)
			await _frames(3)
			_place(Vector3(0, 0.05, 7.0))
			await _frames(30)
			e.set_state("windup")
			var moved := false
			for f in 400:
				await get_tree().physics_frame
				if not moved and is_instance_valid(e) and e.state == "windup" and e.state_time > 0.5:
					moved = true
					var cd: Vector3 = e.get("charge_dir")
					_place(e.global_position + cd * 7.0 + cd.cross(Vector3.UP).normalized() * x + Vector3(0, 0.05, 0))
		"side_stomp_grenadier":
			# The lance grenadier faces Mak's camera side; Mak drops past its flank with his feet at its belt.
			var e := _spawn("gingerbread_grenadier", Vector3(0, 0, 0), {"ai_enabled": false})
			cam_focus = Vector3(0.4, 0.7, 0)
			cam_off = Vector3(0.0, 0.6, -3.6)
			await _frames(40)
			_place(Vector3(e.body_radius + 0.45, 0.65, 0))
			await _frames(400)


func _finish() -> void:
	var path := Dev.arg("crit-out", "")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out, "  "))
			f.close()
	print("[CritFair] DONE -> ", path)
	if Dev.has_arg("quit-when-done"):
		get_tree().quit()
