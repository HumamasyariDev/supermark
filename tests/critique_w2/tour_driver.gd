extends Node
## Critic round 1 (visual lens) tour driver for W2. Test-only; never part of the game.
## Started by visual_tour.tscn: it loads W2 as the current scene, then
##   1. captures every StoryCam under StoryCams/ (HUD hidden),
##   2. measures motion: two StoryCam_A_v2 frames 1 s apart, fraction of changed pixels,
##   3. walks the main route with the gameplay camera (Mak respawned facing the next point),
##   4. frames close-ups of every character-like node it can find,
##   5. writes an audit JSON: primitive meshes, meshes with no material, character nodes.
## Args (after --): --tour-out=<abs dir> [--tour-only=story|route|chars|audit]

const W2 := "res://scenes/worlds/w2/W2.tscn"

var out_dir := ""
var only := ""
var settle := 45
var pick := ""
var stamp := ""
var world: Node3D
var log_lines: PackedStringArray = PackedStringArray()

# Route: [label, position (feet), next point to face]
var route := [
	["r00_spawn_default", Vector3(0, 0.1, 31), Vector3(0, 10, 0)],
	["r01_garden_L03", Vector3(4.54, 3.5, -1.33), Vector3(-2.83, 6.5, -3.37)],
	["r02_L06", Vector3(-2.83, 6.8, -3.37), Vector3(3.28, 14.2, 2.19)],
	["r03_L09", Vector3(3.28, 14.5, 2.19), Vector3(1.31, 21.6, -7.46)],
	["r04_L12", Vector3(1.31, 21.9, -7.46), Vector3(-5.5, 24.0, -13.5)],
	["r05_cloud_landing_C1", Vector3(-4.0, 24.3, -12.0), Vector3(-4.56, 25.2, -5.49)],
	["r06_pea_bridge", Vector3(6.55, 24.3, -11.0), Vector3(23, 24, -4)],
	["r07_allotment", Vector3(14.5, 24.3, -3.0), Vector3(23, 24, -4)],
	["r08_M03", Vector3(-2.74, 27.9, -0.63), Vector3(1.68, 33.2, -3.76)],
	["r09_M06", Vector3(1.28, 35.9, -10.84), Vector3(-4.9, 38.0, -13.18)],
	["r10_U02", Vector3(-3.27, 46.7, -7.78), Vector3(2.5, 48.8, -13.2)],
	["r11_upper_cloudbank_UC", Vector3(-12.5, 44.3, -8.5), Vector3(-29.5, 44, -16.5)],
	["r12_LB2_pads", Vector3(-29.5, 44.4, -16.5), Vector3(-38, 45, -26)],
	["r13_puff06", Vector3(-31.48, 31.8, -10.96), Vector3(-33.94, 37.1, -7.68)],
	["r14_castle_gate", Vector3(10.5, 50.3, -19.0), Vector3(12.5, 50, -34)],
	["r15_courtyard", Vector3(13.0, 50.3, -29.0), Vector3(12.5, 50, -40)],
	["r16_kitchen_floor", Vector3(0.0, 50.3, -27.0), Vector3(-5.5, 55.6, -34)],
	["r17_chair", Vector3(3.2, 54.7, -34.0), Vector3(-5.5, 55.6, -34)],
	["r18_table", Vector3(-6.6, 55.9, -31.4), Vector3(-12.6, 59.6, -36.2)],
	["r19_bell", Vector3(-8.4, 63.1, -16.6), Vector3(-18, 66, -24)],
	["r20_B1_belfry", Vector3(-18.0, 58.3, -17.6), Vector3(-18, 70, -24)],
]

var char_patterns := ["jack", "daisy", "cow", "giant", "goose", "scarecrow", "caw", "reginald", "wolf", "pip",
	"swallow", "bird", "harp", "popper", "peapod", "crow", "bumble", "bee", "butterfly", "e0", "e1", "npc", "talker"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour-out="):
			out_dir = a.substr(11)
		elif a.begins_with("--tour-only="):
			only = a.substr(12)
		elif a.begins_with("--tour-settle="):
			settle = int(a.substr(14))
		elif a.begins_with("--tour-pick="):
			pick = a.substr(12)
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("critique_w2")
	DirAccess.make_dir_recursive_absolute(out_dir)
	stamp = Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "") + "Z"
	_run.call_deferred()


func _log(s: String) -> void:
	print("[TOUR] ", s)
	log_lines.append(s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := out_dir.path_join("%s__%s.png" % [stamp, name])
	img.save_png(p)
	_log("shot %s %s" % [p, img.get_size()])
	return p


func _hide_hud() -> void:
	for n in get_tree().get_nodes_in_group("hud"):
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl.layer >= 1 and not String(cl.get_path()).contains("Router"):
			cl.visible = false


func _run() -> void:
	get_window().size = Vector2i(1920, 1080)
	await _frames(5)
	get_tree().change_scene_to_file(W2)
	var t := 0
	while t < 3000:
		await get_tree().process_frame
		t += 1
		var cs := get_tree().current_scene
		if cs is Node3D and cs.get("player") != null and t > 30:
			world = cs as Node3D
			break
	if world == null:
		_log("ERROR world never became ready")
		_finish()
		return
	_log("world ready after %d frames" % t)
	await _frames(240)
	_hide_hud()
	await _frames(5)
	if only == "" or only == "audit":
		_audit()
	if only == "" or only == "story":
		await _story()
	if only == "" or only == "route":
		await _route()
	if only == "" or only == "chars":
		await _chars()
	_finish()


func _finish() -> void:
	var f := FileAccess.open(out_dir.path_join("%s__tour_log.txt" % stamp), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
		f.close()
	get_tree().quit()


func _story() -> void:
	var cams := world.get_node_or_null("StoryCams")
	if cams == null:
		_log("no StoryCams")
		return
	for c in cams.get_children():
		if c is Camera3D:
			(c as Camera3D).current = true
			await _frames(30)
			await _shot("story_" + c.name)
	# Motion: StoryCam_A_v2 (fallback StoryCam_A) two frames 1 s apart.
	var mc := cams.get_node_or_null("StoryCam_A_v2") as Camera3D
	if mc == null:
		mc = cams.get_node_or_null("StoryCam_A") as Camera3D
	if mc:
		mc.current = true
		await _frames(20)
		await RenderingServer.frame_post_draw
		var a := get_viewport().get_texture().get_image()
		await _frames(60)
		await RenderingServer.frame_post_draw
		var b := get_viewport().get_texture().get_image()
		a.resize(480, 270)
		b.resize(480, 270)
		var changed := 0
		var total := 480 * 270
		for y in 270:
			for x in 480:
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
					changed += 1
		_log("motion %s: %.2f%% of pixels changed over 1 s" % [mc.name, 100.0 * changed / total])


func _player_cam_current() -> void:
	for n in get_tree().get_nodes_in_group("game_camera"):
		var cam := n.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true
			return


func _route() -> void:
	var p: Node3D = world.get("player")
	_player_cam_current()
	for r in route:
		if pick != "" and not pick.split(",").has(String(r[0]).substr(0, 3)):
			continue
		var pos: Vector3 = r[1]
		var nxt: Vector3 = r[2]
		var d := nxt - pos
		d.y = 0.0
		if d.length() < 0.1:
			d = Vector3(0, 0, -1)
		var basis := Basis.looking_at(d.normalized(), Vector3.UP)
		if p.has_method("respawn"):
			p.call("respawn", Transform3D(basis, pos))
		await _frames(settle)
		_log("route %s player at %s on_floor=%s" % [r[0], p.global_position, p.call("is_on_floor") if p.has_method("is_on_floor") else "?"])
		await _shot("gameplay_" + String(r[0]))


func _visual_aabb(n: Node3D) -> AABB:
	var have := false
	var box := AABB()
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		if not v.is_visible_in_tree():
			continue
		var b := v.global_transform * v.get_aabb()
		if b.size.length() > 60.0:
			continue
		if not have:
			box = b
			have = true
		else:
			box = box.merge(b)
	if not have:
		box = AABB(n.global_position - Vector3(0.5, 0, 0.5), Vector3(1, 1.5, 1))
	return box


func _is_char_name(s: String) -> bool:
	var l := s.to_lower()
	for pat in char_patterns:
		if pat.length() <= 2:
			continue
		if l.contains(pat):
			return true
	return l.length() >= 3 and l.begins_with("e") and l.substr(1, 2).is_valid_int()


func _chars() -> void:
	var seen := {}
	var picks: Array[Node3D] = []
	for n in world.find_children("*", "Node3D", true, false):
		var nn := n as Node3D
		if not _is_char_name(nn.name):
			continue
		# Skip children of an already picked character.
		var skip := false
		for q in picks:
			if q.is_ancestor_of(nn):
				skip = true
				break
		if skip or picks.size() >= 40:
			continue
		if nn is MeshInstance3D or nn is Skeleton3D or nn is CollisionShape3D or nn is Area3D and not nn.name.begins_with("E"):
			continue
		if not nn.is_visible_in_tree():
			continue
		var box := _visual_aabb(nn)
		var key := "%d_%d_%d" % [int(box.get_center().x), int(box.get_center().y), int(box.get_center().z)]
		if seen.has(key):
			continue
		seen[key] = true
		picks.append(nn)
	var cam := Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.current = true
	var i := 0
	for nn in picks:
		if not is_instance_valid(nn) or not nn.is_inside_tree():
			continue
		var box := _visual_aabb(nn)
		var c := box.get_center()
		var r := maxf(0.6, box.size.length() * 0.5)
		var fwd := -nn.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.1:
			fwd = Vector3(0, 0, 1)
		fwd = fwd.normalized()
		# Front three-quarter view.
		var dir := (fwd.rotated(Vector3.UP, 0.6) + Vector3(0, 0.35, 0)).normalized()
		cam.global_position = c + dir * r * 2.6
		cam.look_at(c, Vector3.UP)
		await _frames(8)
		var label := "char_%02d_%s" % [i, String(nn.name).validate_filename()]
		_log("char %s path=%s center=%s size=%s visible_meshes=%d" % [label, nn.get_path(), c, box.size, nn.find_children("*", "MeshInstance3D", true, false).size()])
		await _shot(label)
		i += 1


func _audit() -> void:
	var prims := []
	var nomat := []
	var by_class := {}
	var total := 0
	for n in world.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		total += 1
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			continue
		if mesh is PrimitiveMesh:
			var cls := mesh.get_class()
			by_class[cls] = int(by_class.get(cls, 0)) + 1
			var col := ""
			var m: Material = gi.material_override
			if m == null and gi is MeshInstance3D and mesh.get_surface_count() > 0:
				m = (gi as MeshInstance3D).get_active_material(0)
			if m is StandardMaterial3D:
				col = (m as StandardMaterial3D).albedo_color.to_html(false)
			elif m is ShaderMaterial:
				col = "shader"
			prims.append({"path": String(gi.get_path()).replace(String(world.get_path()), ""), "class": cls,
				"aabb": str(mesh.get_aabb().size), "pos": str(gi.global_position), "color": col, "visible": gi.is_visible_in_tree()})
		if gi is MeshInstance3D and gi.material_override == null:
			var mi := gi as MeshInstance3D
			var missing := 0
			for s in mesh.get_surface_count():
				if mi.get_active_material(s) == null:
					missing += 1
			if missing > 0:
				nomat.append({"path": String(gi.get_path()).replace(String(world.get_path()), ""), "class": mesh.get_class(), "surfaces_without_material": missing, "pos": str(gi.global_position)})
	var rep := {"geometry_instances": total, "primitive_by_class": by_class, "primitives": prims, "no_material": nomat}
	var f := FileAccess.open(out_dir.path_join("%s__audit.json" % stamp), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, "  "))
		f.close()
	_log("audit geometry=%d primitives=%d no_material=%d classes=%s" % [total, prims.size(), nomat.size(), by_class])
