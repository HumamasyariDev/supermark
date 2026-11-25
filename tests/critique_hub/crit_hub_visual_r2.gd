extends Node
## CRITIC round 2, VISUAL POLISH lens, HUB. Instances the real Hub scene, then in one launch:
##  1. walks the main route by respawning Mak at each named spawn marker and saving the gameplay-camera frame (full res PNG);
##  2. saves close-ups of every on-screen character and key gameplay object (hero, Bramwell, sheep/cub, clock, truffle, acorn)
##     from a temporary Camera3D, so texel size, materials and model reality can be judged.
## Args (after --): --out=<abs dir> --tag=<label> [--spawns=A,B,...] [--closeups=0]
## Run: python tools/godot.py run res://tests/critique_hub/CritHubVisualR2.tscn --seconds 120 -- --profile=crit_hub_r2v --hide-hud --out=<dir>
## Writes nothing outside --out. Test file only; does not modify the world.

var _out := ""
var _tag := "r2v"
var _spawns: PackedStringArray = ["Default", "Book_W1", "Book_W2", "Fireside", "Test_Nook", "Test_Spiral", "Book_W3", "Book_BOSS", "Test_Cornice", "Test_TopBalcony", "Balcony", "Test_Mantel", "Test_Cub", "From_W1"]
var _closeups := true
var _hub: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--spawns="):
			_spawns = a.substr(9).split(",")
		elif a == "--closeups=0":
			_closeups = false
	DirAccess.make_dir_recursive_absolute(_out)
	_hub = load("res://scenes/hub/Hub.tscn").instantiate()
	add_child(_hub)
	print("[CritVisR2] start out=", _out)
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s_%s.png" % [_out, _tag, name]
	img.save_png(p)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	print("[CritVisR2] saved %s mak=%s" % [p, str(pl.global_position) if pl else "-"])


func _audit() -> void:
	# D034 matte audit + primitive-character audit: every visible MeshInstance3D, its surface materials, and whether it
	# sits under a node in a character group with a primitive mesh.
	var rows: Array = []
	var glossy := 0
	var metallic_env := 0
	var nomat := 0
	var prim_chars: Array = []
	var total := 0
	var char_roots: Array = []
	for g in ["player", "enemy", "npc", "talker", "boss"]:
		for n in get_tree().get_nodes_in_group(g):
			char_roots.append(n)
	var stack: Array = [_hub]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		total += 1
		var in_char := false
		for r in char_roots:
			if r == mi or (r as Node).is_ancestor_of(mi):
				in_char = true
				break
		if in_char and (mi.mesh is PrimitiveMesh) and not (mi.mesh is PlaneMesh or mi.mesh is QuadMesh):
			prim_chars.append(str(mi.get_path()))
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m == null:
				nomat += 1
				rows.append({"path": str(mi.get_path()), "issue": "no_material"})
				continue
			if m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				if not in_char and bm.roughness < 0.6 and bm.metallic < 0.5:
					glossy += 1
					if rows.size() < 400:
						rows.append({"path": str(mi.get_path()), "issue": "glossy_env", "rough": bm.roughness, "spec": bm.metallic_specular, "mat": m.resource_name})
				if not in_char and bm.metallic >= 0.5:
					metallic_env += 1
					if rows.size() < 400:
						rows.append({"path": str(mi.get_path()), "issue": "metallic_env", "rough": bm.roughness, "metal": bm.metallic, "mat": m.resource_name})
				if in_char and rows.size() < 400:
					rows.append({"path": str(mi.get_path()), "issue": "char_material", "rough": bm.roughness, "metal": bm.metallic, "spec": bm.metallic_specular, "filter": bm.texture_filter, "mat": m.resource_name})
	var out := {"visible_meshes": total, "glossy_env_surfaces": glossy, "metallic_env_surfaces": metallic_env, "no_material_surfaces": nomat, "primitive_meshes_in_character_groups": prim_chars, "rows": rows}
	var f := FileAccess.open("%s/%s_material_audit.json" % [_out, _tag], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	print("[CritVisR2] audit meshes=%d glossy=%d metallic=%d nomat=%d primchars=%d" % [total, glossy, metallic_env, nomat, prim_chars.size()])


func _run() -> void:
	await _wait(6.0)
	_audit()
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	for s in _spawns:
		var m := _hub.get_node_or_null("Spawns/" + s) as Node3D
		if m == null or pl == null:
			print("[CritVisR2] missing spawn ", s)
			continue
		pl.call("respawn", m.global_transform)
		await _wait(1.8)
		await _save("route_" + s)
	if _closeups:
		await _do_closeups(pl)
	await _wait(0.3)
	get_tree().quit()


func _first_named(root: Node, names: Array) -> Node3D:
	for n in names:
		var f := root.find_child(n, true, false)
		if f is Node3D and (f as Node3D).is_visible_in_tree():
			return f
	return null


func _closeup(target: Node3D, label: String, dist: float, up: float, from_dir: Vector3) -> void:
	if target == null:
		print("[CritVisR2] closeup target missing ", label)
		return
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var c := target.global_position + Vector3(0, up, 0)
	var d := from_dir.normalized()
	cam.global_position = c + d * dist + Vector3(0, 0.25, 0)
	cam.look_at(c, Vector3.UP)
	cam.make_current()
	await _wait(0.6)
	await _save("close_" + label)
	cam.queue_free()


func _do_closeups(pl: Node3D) -> void:
	# Hero at spawn, viewed from the front-left.
	var m := _hub.get_node_or_null("Spawns/Default") as Node3D
	if m and pl:
		pl.call("respawn", m.global_transform)
		await _wait(1.0)
		await _closeup(pl, "hero_front", 2.6, 0.6, -m.global_transform.basis.z + m.global_transform.basis.x * 0.6)
		await _closeup(pl, "hero_back", 2.6, 0.6, m.global_transform.basis.z)
	var br := _first_named(_hub, ["Bramwell"])
	if br:
		var dir := (Vector3(0, 0, 11.5) - br.global_position)
		dir.y = 0
		await _closeup(br, "bramwell", 3.0, 0.8, dir)
	for g in ["enemy", "npc", "talker"]:
		var k := 0
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and (n as Node3D).is_visible_in_tree() and k < 4:
				var p3 := (n as Node3D).global_position
				var dir2 := Vector3(-p3.x, 0, -p3.z)
				if dir2.length() < 0.5:
					dir2 = Vector3(0, 0, 1)
				await _closeup(n, "%s_%d_%s" % [g, k, String(n.name)], 3.0, 0.6, dir2)
				k += 1
	var clock := _first_named(_hub, ["TruffleClock", "Clock", "HubClock"])
	await _closeup(clock, "clock", 6.0, 2.0, Vector3(0.2, 0.15, 1))
	var t := get_tree().get_first_node_in_group("truffle") as Node3D
	await _closeup(t, "truffle", 1.8, 0.2, Vector3(0.3, 0.2, 1))
	var a := get_tree().get_first_node_in_group("acorn") as Node3D
	await _closeup(a, "acorn", 1.4, 0.0, Vector3(0.3, 0.2, 1))
	# Book 1 diorama and the locked Book 2 with its seal.
	var b1 := _hub.get_node_or_null("Spawns/Book_W1") as Node3D
	if b1:
		var cam := Camera3D.new()
		cam.fov = 50.0
		add_child(cam)
		cam.global_position = Vector3(-4.6, 2.6, 9.4)
		cam.look_at(Vector3(-7.07, 1.3, 7.07), Vector3.UP)
		cam.make_current()
		await _wait(0.6)
		await _save("close_book1_diorama")
		cam.global_position = Vector3(4.6, 2.6, 9.4)
		cam.look_at(Vector3(7.07, 1.3, 7.07), Vector3.UP)
		await _wait(0.6)
		await _save("close_book2_locked")
		# Fireplace, wingbacks and tea spill.
		cam.fov = 55.0
		cam.global_position = Vector3(-8.0, 1.6, 2.5)
		cam.look_at(Vector3(-14.0, 1.4, 0.0), Vector3.UP)
		await _wait(0.6)
		await _save("close_fireplace")
		# Wolf's Door from the stair head.
		cam.global_position = Vector3(0.0, 5.9, -11.0)
		cam.look_at(Vector3(0.0, 6.2, -15.9), Vector3.UP)
		await _wait(0.6)
		await _save("close_wolf_door")
		# Dome and frescoes from the floor.
		cam.fov = 70.0
		cam.global_position = Vector3(0.0, 1.6, 6.0)
		cam.look_at(Vector3(0.0, 14.0, -4.0), Vector3.UP)
		await _wait(0.6)
		await _save("close_dome_frescoes")
		# Bookshelf texel check up close (gallery level).
		cam.fov = 45.0
		cam.global_position = Vector3(-9.5, 5.9, 8.0)
		cam.look_at(Vector3(-11.0, 6.2, 10.5), Vector3.UP)
		await _wait(0.6)
		await _save("close_shelves_texels")
		# Floor and rug texels.
		cam.global_position = Vector3(2.0, 1.2, 8.5)
		cam.look_at(Vector3(1.0, 0.0, 6.0), Vector3.UP)
		await _wait(0.6)
		await _save("close_floor_rug_texels")
		cam.queue_free()
