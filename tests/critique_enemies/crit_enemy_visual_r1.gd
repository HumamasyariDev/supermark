extends Node3D
## Enemy-visuals critique, round 1 (critic-owned test; read-only towards the enemies track).
## Loads a real world, then for every enemy in group "enemy" (and, with --lineup, a row of all six families
## next to the real Mak) renders from the GAMEPLAY camera rig (orbit 5.4 m, pitch -17 deg, FOV 62, pivot 1 m),
## once normally and once as an exact mask (target meshes only, unshaded white on black), so palette contrast
## and 64 px silhouettes can be measured offline (tests/critique_enemies/analyse_r1.py).
## Also writes an inventory: model file, placeholder visibility, primitive meshes, measured height, materials.
## Args (after --): --world=res://... --crit-out=<abs dir> --tag=W1 [--lineup] [--gaps=4,12] [--max=12]

const FAMILIES := {"woolly_wolf": "res://scenes/enemies/WoollyWolf.tscn", "crow_bandit": "res://scenes/enemies/CrowBandit.tscn",
	"peapod_popper": "res://scenes/enemies/PeapodPopper.tscn", "bumble_bruiser": "res://scenes/enemies/BumbleBruiser.tscn",
	"gingerbread_grenadier": "res://scenes/enemies/GingerbreadGrenadier.tscn", "gummy_brute": "res://scenes/enemies/GummyBrute.tscn"}
const MASK_LAYER := 1 << 19

var world: Node
var cam: Camera3D
var out_dir := ""
var tag := "W"
var report: Dictionary = {"shots": [], "inventory": []}
var mask_env: Environment
var mask_mat: StandardMaterial3D
var mask_vp: SubViewport
var mask_cam: Camera3D


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	var wpath: String = dev.arg("world", "res://scenes/worlds/w1/W1.tscn") if dev else "res://scenes/worlds/w1/W1.tscn"
	out_dir = dev.arg("crit-out", OS.get_user_data_dir()) if dev else OS.get_user_data_dir()
	tag = dev.arg("tag", "W") if dev else "W"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ps := load(wpath) as PackedScene
	if ps == null:
		push_error("[CritEV] cannot load " + wpath)
		get_tree().quit(2)
		return
	world = ps.instantiate()
	add_child(world)
	cam = Camera3D.new()
	cam.name = "CritCam"
	cam.fov = 62.0
	cam.far = 600.0
	add_child(cam)
	mask_env = Environment.new()
	mask_env.background_mode = Environment.BG_COLOR
	mask_env.background_color = Color.BLACK
	mask_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	mask_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	mask_mat = StandardMaterial3D.new()
	mask_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask_mat.albedo_color = Color.WHITE
	mask_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Independent mask renderer: shares the world, sees only MASK_LAYER, so nothing else can touch it.
	mask_vp = SubViewport.new()
	mask_vp.own_world_3d = false
	mask_vp.transparent_bg = false
	mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mask_vp.size = Vector2i(get_viewport().get_visible_rect().size)
	add_child(mask_vp)
	mask_cam = Camera3D.new()
	mask_cam.cull_mask = MASK_LAYER
	mask_cam.environment = mask_env
	mask_vp.add_child(mask_cam)
	report["world"] = wpath
	report["tag"] = tag
	_run.call_deferred()


func _run() -> void:
	await _frames(150)
	var dev := get_node_or_null("/root/Dev")
	var vs := get_viewport().get_visible_rect().size
	report["viewport"] = [vs.x, vs.y]
	print("[CritEV] viewport ", vs)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var spawn := world.find_child("Default", true, false) as Node3D
	var spawn_pos := spawn.global_position if spawn != null else Vector3.ZERO
	var enemies: Array[Node3D] = []
	var pool: Array[Node] = get_tree().get_nodes_in_group("enemy")
	pool.append_array(get_tree().get_nodes_in_group("boss"))
	for n in pool:
		if n is Node3D and (n as Node3D).is_visible_in_tree():
			enemies.append(n as Node3D)
			if "ai_enabled" in n:
				n.set("ai_enabled", false)
	enemies.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	print("[CritEV] enemies in world: ", enemies.size())
	for e in enemies:
		report["inventory"].append(_inventory(e))
	var gaps: PackedStringArray = (dev.arg("gaps", "4,12") if dev else "4,12").split(",")
	var max_n := int(dev.arg("max", "14")) if dev else 14
	var per_family: Dictionary = {}
	var shot_n := 0
	for e in enemies:
		var fam := String(e.get("enemy_id")) if "enemy_id" in e else String(e.name).to_snake_case()
		per_family[fam] = int(per_family.get(fam, 0)) + 1
		if int(per_family[fam]) > 2 or shot_n >= max_n:
			continue
		shot_n += 1
		for g in gaps:
			await _gameplay_shot(e, player, spawn_pos, float(g), "%s_%s_%s_gap%s" % [tag, fam, e.name, g])
	if dev and dev.has_arg("lineup"):
		await _lineup(player, spawn)
	var f := FileAccess.open(out_dir.path_join("%s_report.json" % tag), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("[CritEV] done ", report["shots"].size(), " shots")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _visual_meshes(e: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var root: Node = e.get("mesh_root") if "mesh_root" in e else null
	if root == null and "rig" in e and e.get("rig") is Node:
		root = e.get("rig")
	if root == null:
		root = e
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.is_visible_in_tree() and m.mesh != null:
			out.append(m)
	return out


func _aabb(meshes: Array[MeshInstance3D]) -> AABB:
	var have := false
	var box := AABB()
	for m in meshes:
		var b := m.global_transform * m.get_aabb()
		if m.skeleton != NodePath() and m.skin != null:
			pass
		box = b if not have else box.merge(b)
		have = true
	return box


func _inventory(e: Node3D) -> Dictionary:
	var d: Dictionary = {"name": String(e.name), "path": String(get_path_to(e)), "scene": e.scene_file_path,
		"enemy_id": e.get("enemy_id") if "enemy_id" in e else "", "pos": [e.global_position.x, e.global_position.y, e.global_position.z]}
	var ph: Node3D = e.get("placeholder") if "placeholder" in e else null
	d["placeholder_visible"] = ph != null and ph.is_visible_in_tree()
	var mr: Node3D = e.get("mesh_root") if "mesh_root" in e else null
	d["has_mesh_root"] = mr != null
	var glbs: Array = []
	if mr != null:
		for c in mr.get_children():
			glbs.append(c.scene_file_path)
	d["glbs"] = glbs
	var attachments: Array = []
	if mr != null:
		for b in mr.find_children("*", "BoneAttachment3D", true, false):
			for c in b.get_children():
				attachments.append("%s:%s" % [b.name, c.scene_file_path if c.scene_file_path != "" else String(c.name)])
	d["attachments"] = attachments
	var prim: Array = []
	for mi in e.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.is_visible_in_tree() and m.mesh is PrimitiveMesh:
			prim.append("%s (%s)" % [String(e.get_path_to(m)), m.mesh.get_class()])
	d["visible_primitive_meshes"] = prim
	var meshes := _visual_meshes(e)
	var box := _aabb(meshes)
	d["aabb_height"] = box.size.y
	var body_only: Array[MeshInstance3D] = []
	for m in meshes:
		var under_attach := false
		var n: Node = m.get_parent()
		while n != null and n != e:
			if n is BoneAttachment3D:
				under_attach = true
				break
			n = n.get_parent()
		if not under_attach:
			body_only.append(m)
	if not body_only.is_empty():
		var bb := _aabb(body_only)
		d["body_height"] = bb.size.y
		d["body_top_above_origin"] = bb.end.y - e.global_position.y
	d["aabb_size"] = [box.size.x, box.size.y, box.size.z]
	d["aabb_bottom_above_origin"] = box.position.y - e.global_position.y
	d["global_scale"] = [e.global_transform.basis.get_scale().x, e.global_transform.basis.get_scale().y]
	var tris := 0
	var mats: Dictionary = {}
	for m in meshes:
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array:
				tris += (idx as PackedInt32Array).size() / 3
			var mat := m.get_active_material(s)
			var key := mat.get_class() if mat != null else "null"
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
				key += ":" + (mat as ShaderMaterial).shader.resource_path.get_file()
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				key += ":transparent"
			mats[key] = int(mats.get(key, 0)) + 1
	d["triangles"] = tris
	d["materials"] = mats
	d["mesh_instances"] = meshes.size()
	return d


func _clear_line(from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _place_cam_for(target_center: Vector3, ground: Vector3, dir: Vector3, gap: float) -> Vector3:
	# Mak stands `gap` metres from the enemy towards the approach; the camera orbits 5.4 m behind Mak.
	var mak := ground + dir * gap
	var pitch := deg_to_rad(17.0)
	var pivot := mak + Vector3.UP * 1.0
	var cpos := pivot + dir * 5.4 * cos(pitch) + Vector3.UP * 5.4 * sin(pitch)
	cam.global_position = cpos
	# The real camera looks at Mak's pivot; aim between Mak and the enemy so both stay in frame (lead framing).
	var aim := pivot.lerp(target_center, 0.35)
	cam.look_at(aim, Vector3.UP)
	return mak


func _gameplay_shot(e: Node3D, player: Node3D, spawn_pos: Vector3, gap: float, name_: String) -> void:
	var meshes := _visual_meshes(e)
	if meshes.is_empty():
		return
	var box := _aabb(meshes)
	var center := box.get_center()
	var ground := Vector3(e.global_position.x, box.position.y, e.global_position.z)
	var base_dir := spawn_pos - e.global_position
	base_dir.y = 0.0
	if base_dir.length() < 0.5:
		base_dir = Vector3(0, 0, 1)
	base_dir = base_dir.normalized()
	var exclude: Array[RID] = []
	if e is CollisionObject3D:
		exclude.append((e as CollisionObject3D).get_rid())
	var dir := base_dir
	var chosen := false
	for k in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6]:
		var d := base_dir.rotated(Vector3.UP, deg_to_rad(30.0 * k))
		var mak := ground + d * gap
		var pitch := deg_to_rad(17.0)
		var cpos := mak + Vector3.UP * (1.0 + 5.4 * sin(pitch)) + d * 5.4 * cos(pitch)
		if _clear_line(cpos, center, exclude) and _clear_line(cpos, mak + Vector3.UP, exclude):
			dir = d
			chosen = true
			break
	var mak_at := _place_cam_for(center, ground, dir, gap)
	if player != null:
		# Real Mak stands at the gameplay spot for scale, facing the enemy.
		var q := PhysicsRayQueryParameters3D.create(mak_at + Vector3.UP * 4.0, mak_at + Vector3.DOWN * 8.0)
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		player.global_position = hit.position if not hit.is_empty() else mak_at
		# Step Mak 1.3 m to the side so he never hides the enemy from the analysis camera.
		var side := dir.cross(Vector3.UP).normalized() * 1.8
		var q2 := PhysicsRayQueryParameters3D.create(player.global_position + side + Vector3.UP * 4.0, player.global_position + side + Vector3.DOWN * 8.0)
		q2.collision_mask = 1
		var hit2 := get_world_3d().direct_space_state.intersect_ray(q2)
		player.global_position = hit2.position if not hit2.is_empty() else player.global_position + side
		player.look_at(Vector3(e.global_position.x, player.global_position.y, e.global_position.z), Vector3.UP)
		if player.has_method("reset_physics_interpolation"):
			player.reset_physics_interpolation()
	cam.make_current()
	await _render_pair(meshes, name_, {"enemy": String(e.name), "family": e.get("enemy_id") if "enemy_id" in e else String(e.name).to_snake_case(),
		"gap": gap, "clear_view": chosen, "cam_dist": cam.global_position.distance_to(center), "height": box.size.y})


func _hide_ui() -> void:
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in get_tree().root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not (ctl.get_parent() is Control):
			ctl.visible = false


func _render_pair(meshes: Array[MeshInstance3D], name_: String, meta: Dictionary) -> void:
	_hide_ui()
	cam.make_current()
	await _frames(6)
	_hide_ui()
	cam.make_current()
	await RenderingServer.frame_post_draw
	# Whatever camera actually drew the frame drives the mask, so the two always line up.
	var cur := get_viewport().get_camera_3d()
	meta["render_cam"] = String(cur.get_path()) if cur != null else ""
	if cur != null and cur != cam:
		print("[CritEV] note: frame drawn by ", cur.get_path(), " not CritCam")
	var img := get_viewport().get_texture().get_image()
	var color_path := out_dir.path_join(name_ + "__color.png")
	img.save_png(color_path)
	# Mask pass in the SubViewport: only the target meshes, unshaded white on black.
	mask_vp.size = Vector2i(img.get_width(), img.get_height())
	var src_cam: Camera3D = cur if cur != null else cam
	mask_cam.global_transform = src_cam.get_global_transform_interpolated()
	mask_cam.fov = src_cam.fov
	mask_cam.near = src_cam.near
	mask_cam.far = src_cam.far
	mask_cam.current = true
	var saved: Array = []
	for m in meshes:
		saved.append([m, m.layers, m.material_override, m.material_overlay])
		m.layers = MASK_LAYER
		m.material_override = mask_mat
		m.material_overlay = null
	await _frames(3)
	await RenderingServer.frame_post_draw
	var mimg := mask_vp.get_texture().get_image()
	var mask_path := out_dir.path_join(name_ + "__mask.png")
	mimg.save_png(mask_path)
	for sv in saved:
		var m := sv[0] as MeshInstance3D
		m.layers = int(sv[1])
		m.material_override = sv[2]
		m.material_overlay = sv[3]
	# Background pass: target hidden, so the analysis knows which mask pixels were actually visible.
	var vis_before: Array = []
	for m in meshes:
		vis_before.append(m.visible)
		m.visible = false
	_hide_ui()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var bimg := get_viewport().get_texture().get_image()
	var bg_path := out_dir.path_join(name_ + "__bg.png")
	bimg.save_png(bg_path)
	for i in meshes.size():
		meshes[i].visible = vis_before[i]
	meta["bg"] = bg_path
	meta["name"] = name_
	meta["color"] = color_path
	meta["mask"] = mask_path
	report["shots"].append(meta)
	print("[CritEV] shot ", name_)


func _lineup(player: Node3D, spawn: Node3D) -> void:
	var basis := spawn.global_transform.basis if spawn != null else Basis()
	var origin := spawn.global_position if spawn != null else Vector3.ZERO
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var center := origin + fwd * 7.0
	var row: Array[Node3D] = []
	var i := 0
	var fams := FAMILIES.keys()
	for fam in fams:
		var ps := load(FAMILIES[fam]) as PackedScene
		var e := ps.instantiate() as Node3D
		e.set("ai_enabled", false)
		var at := center + right * (float(i) - 2.0) * 2.4
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 15.0, at + Vector3.DOWN * 30.0)
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			at = hit.position
		world.add_child(e)
		e.global_position = at
		e.look_at(at - fwd, Vector3.UP)
		row.append(e)
		i += 1
	await _frames(20)
	for e in row:
		if "ai_enabled" in e:
			e.set("ai_enabled", false)
	if player != null:
		var at := center - right * 7.2
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 15.0, at + Vector3.DOWN * 30.0)
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		player.global_position = hit.position if not hit.is_empty() else at
		player.look_at(player.global_position - fwd, Vector3.UP)
	await _frames(20)
	# Gameplay-height camera, 11 m back (Mak at ~6 m in front of a 5.4 m orbit), so it reads like the real game.
	var cpos := center - fwd * 11.0 + Vector3.UP * 2.6
	cam.global_position = cpos
	cam.look_at(center + Vector3.UP * 0.7, Vector3.UP)
	cam.make_current()
	for e in row:
		report["inventory"].append(_inventory(e).merged({"lineup": true}))
	var k := 0
	for e in row:
		var meshes := _visual_meshes(e)
		if meshes.is_empty():
			continue
		var box := _aabb(meshes)
		await _render_pair(meshes, "%s_lineup_%d_%s" % [tag, k, String(e.get("enemy_id"))],
			{"enemy": String(e.name), "family": e.get("enemy_id"), "gap": -1, "lineup": true,
			"cam_dist": cam.global_position.distance_to(box.get_center()), "height": box.size.y})
		k += 1
	if player != null:
		var pm: Array[MeshInstance3D] = []
		var pv: Node = player.get_node_or_null("Visual")
		for mi in (pv if pv != null else player).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.is_visible_in_tree() and m.mesh != null and m.get_aabb().size.length() < 6.0:
				pm.append(m)
		var pbox := _aabb(pm)
		report["mak_height"] = pbox.size.y
		await _render_pair(pm, "%s_lineup_mak" % tag, {"enemy": "Mak", "family": "mak", "gap": -1, "lineup": true,
			"cam_dist": cam.global_position.distance_to(pbox.get_center()), "height": pbox.size.y})
