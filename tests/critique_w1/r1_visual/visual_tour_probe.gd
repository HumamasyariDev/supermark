extends Node
## Critique W1 round 1, visual polish lens. Read-only: it only respawns the player and adds a temporary camera.
## 1) gameplay-camera screenshots at every spawn marker (HUD on), 2) a character census (generated GLB vs primitive
## meshes) for every NPC, sheep, enemy and the boss cameo, 3) close-up screenshots of each character, 4) a motion pair
## (two StoryCam_B frames 1.0 s apart) for a pixel-diff motion check. Writes tour.json under --tour-out.

var out_dir := ""
var world: Node3D
var player: CharacterBody3D
var report := {"shots": [], "census": []}
const PRIMS := ["SphereMesh", "BoxMesh", "CapsuleMesh", "CylinderMesh", "PrismMesh", "TorusMesh", "PlaneMesh", "QuadMesh"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.call("arg", "tour-out", OS.get_user_data_dir().path_join("w1_tour")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var p := out_dir.path_join("%sZ__%s.png" % [stamp, tag])
	img.save_png(p)
	report["shots"].append({"tag": tag, "file": p})
	print("[W1Tour] shot ", p)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and String(cs.get("world_id")) == "W1" and get_tree().get_first_node_in_group("player") != null and cs.get_node_or_null("Level") != null:
			world = cs as Node3D
			player = get_tree().get_first_node_in_group("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 240000:
			print("[W1Tour] TIMEOUT")
			get_tree().quit(2)
			return
	get_window().size = Vector2i(1920, 1080)
	var pass2: bool = get_node("/root/Dev").call("has_arg", "tour-pass2") if get_node_or_null("/root/Dev") else false
	await _wait(16.0 if pass2 else 4.0)
	if pass2:
		await _pass2()
		return
	# Story cams C and D (HUD and barks hidden), then the motion pair at StoryCam_B.
	var prev := get_viewport().get_camera_3d()
	var sc := world.get_node_or_null("StoryCams")
	var huds: Array = []
	for n in get_tree().get_nodes_in_group("hud"):
		if n is CanvasLayer and (n as CanvasLayer).visible:
			(n as CanvasLayer).visible = false
			huds.append(n)
	for cn in ["StoryCam_C", "StoryCam_D", "StoryCam_Intro_v2", "StoryCam_H2_hayyard", "StoryCam_I_sticks", "StoryCam_J2_huff"]:
		var c := sc.get_node_or_null(cn) as Camera3D if sc else null
		if c == null:
			continue
		c.current = true
		await _wait(1.5)
		await _snap(cn)
	for n in huds:
		if is_instance_valid(n):
			n.visible = true
	var cb := sc.get_node_or_null("StoryCam_B") as Camera3D if sc else null
	if cb:
		cb.current = true
		await _wait(1.0)
		await _snap("motion_B_t0")
		await _wait(1.0)
		await _snap("motion_B_t1")
	if is_instance_valid(prev):
		prev.current = true
	# Gameplay views.
	var sp := world.get_node_or_null("Spawns")
	for nm in ["Default", "W1-1", "W1-2", "W1-3", "W1-4", "W1-5", "W1-6", "W1-7", "W1-8", "T_W1-2_deck", "T_W1-3_deck", "T_bridge", "T_tor", "T_hill", "T_ridge", "T_W1-6_top"]:
		var m := sp.get_node_or_null(nm) as Node3D if sp else null
		if m == null:
			continue
		var yaw := m.global_rotation.y
		player.call("respawn", Transform3D(Basis(Vector3.UP, yaw), m.global_position + Vector3(0, 0.05, 0)))
		await _wait(2.5)
		await _snap("gameplay_" + nm)
	# Character census and close-ups.
	var chars: Array[Node3D] = []
	var level := world.get_node("Level")
	for nm in ["Pip", "Hazel", "Bertram"]:
		var n := level.find_child(nm, true, false) as Node3D
		if n:
			chars.append(n)
	for n in level.find_children("SH*", "Node3D", true, false):
		if String(n.name).length() <= 4:
			chars.append(n)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D:
			chars.append(e)
	for kw in ["Foreman", "Reginald", "Wolf_Boss", "WolfBoss", "Cameo", "Scarecrow", "Bee", "Duck", "Starling", "Fish", "Butterfl"]:
		for n in world.find_children("*" + kw + "*", "Node3D", true, false):
			if not chars.has(n):
				chars.append(n)
	var cam := Camera3D.new()
	cam.fov = 45
	world.add_child(cam)
	var shot_n := 0
	for c in chars:
		if not is_instance_valid(c):
			continue
		var info := _census(c)
		report["census"].append(info)
		if shot_n >= 34 or not c.is_visible_in_tree():
			continue
		var h: float = max(0.6, float(info.get("height", 1.0)))
		var fwd := c.global_basis.z.normalized()
		fwd.y = 0
		if fwd.length() < 0.1:
			fwd = Vector3(0, 0, 1)
		var focus := c.global_position + Vector3(0, h * 0.5, 0)
		var dist: float = clamp(h * 2.6, 2.2, 9.0)
		cam.global_position = focus + fwd.normalized().rotated(Vector3.UP, 0.5) * dist + Vector3(0, h * 0.35, 0)
		cam.look_at(focus, Vector3.UP)
		cam.current = true
		await _wait(0.4)
		shot_n += 1
		await _snap("char_%02d_%s" % [shot_n, String(c.name).validate_filename()])
	if is_instance_valid(prev):
		prev.current = true
	var f := FileAccess.open(out_dir.path_join("tour.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[W1Tour] done")
	get_tree().quit()


func _census(c: Node3D) -> Dictionary:
	var glbs: Array = []
	var prim := 0
	var meshes := 0
	var aabb := AABB()
	var first := true
	for n in [c] + c.find_children("*", "Node", true, false):
		if n is Node and String(n.scene_file_path).ends_with(".glb"):
			glbs.append(String(n.scene_file_path).get_file())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).is_visible_in_tree():
			meshes += 1
			if (n as MeshInstance3D).mesh.get_class() in PRIMS:
				prim += 1
			var mi := n as MeshInstance3D
			var bb := mi.global_transform * mi.get_aabb()
			if first:
				aabb = bb
				first = false
			else:
				aabb = aabb.merge(bb)
	return {"name": String(c.name), "path": str(c.get_path()).replace(str(world.get_path()), ""), "class": c.get_class(),
		"script": String(c.get_script().resource_path) if c.get_script() else "", "visible": c.is_visible_in_tree(),
		"pos": [snappedf(c.global_position.x, 0.1), snappedf(c.global_position.y, 0.1), snappedf(c.global_position.z, 0.1)],
		"glbs": glbs, "meshes": meshes, "primitive_meshes": prim, "height": snappedf(aabb.size.y, 0.01)}


## Pass 2: the intro is over, so the live camera is the player's follow camera.
func _pass2() -> void:
	var pcam := get_viewport().get_camera_3d()
	report["player_camera"] = str(pcam.get_path()) if pcam else ""
	var sp := world.get_node_or_null("Spawns")
	for nm in ["Default", "W1-1", "W1-2", "W1-3", "W1-4", "W1-5", "W1-6", "W1-7", "W1-8", "T_W1-2_deck", "T_W1-3_deck", "T_bridge", "T_tor", "T_hill", "T_ridge", "T_W1-6_top", "T_W1-8"]:
		var m := sp.get_node_or_null(nm) as Node3D if sp else null
		if m == null:
			continue
		player.call("respawn", Transform3D(Basis(Vector3.UP, m.global_rotation.y), m.global_position + Vector3(0, 0.05, 0)))
		await _wait(3.0)
		if is_instance_valid(pcam):
			pcam.current = true
		await _wait(0.3)
		await _snap("gp2_" + nm)
	var level := world.get_node("Level")
	var cam := Camera3D.new()
	cam.fov = 45
	world.add_child(cam)
	var picks: Array[Node3D] = []
	for nm in ["Pip", "Hazel", "Bertram", "WW1", "WW4", "WW6", "FM1_Foreman", "Scarecrow", "CB1", "CB2"]:
		var n := world.find_child(nm, true, false) as Node3D
		if n:
			picks.append(n)
	var i := 0
	for c in picks:
		var info := _census(c)
		var h: float = max(0.8, float(info.get("height", 1.0)))
		if String(c.name) == "Scarecrow":
			h = 4.2
		for side in [1.0, -1.0]:
			var fwd: Vector3 = c.global_basis.z * float(side)
			fwd.y = 0
			var focus := c.global_position + Vector3(0, h * 0.55, 0)
			var dist: float = clamp(h * 2.0, 2.0, 7.0)
			cam.global_position = focus + fwd.normalized().rotated(Vector3.UP, 0.35) * dist + Vector3(0, h * 0.25, 0)
			cam.look_at(focus, Vector3.UP)
			cam.current = true
			await _wait(0.4)
			i += 1
			await _snap("face_%02d_%s_%s" % [i, String(c.name).validate_filename(), "pz" if side > 0 else "nz"])
	var f := FileAccess.open(out_dir.path_join("tour_pass2.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[W1Tour] done pass2")
	get_tree().quit()
