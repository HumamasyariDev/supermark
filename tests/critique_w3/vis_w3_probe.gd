extends Node
## Critique W3 round 1, VISUAL POLISH AND SPECTACLE lens. Lives under /root while W3 is the current scene.
## Never edits the world: it respawns Mak at each test spawn marker along the main route, snaps the gameplay camera
## behind him, waits for it to settle and saves a native viewport screenshot. It also audits every character-like node
## (groups enemy/npc/creature, or scripts under enemies/ or npc) for real GLB models versus primitive meshes, and
## counts flat untextured primitive meshes in the level.
## Run: python tools/godot.py run res://tests/critique_w3/VisW3.tscn --seconds 400 -- --profile=critw3vis_route --hide-hud --vis-out=<abs dir>

var out_dir := ""
var world: Node3D
var player: Node3D
var report := {"shots": [], "characters": [], "prims": {}}

const ROUTE := ["", "Page2", "TierA", "Summit", "T_W3-4", "Islet", "T_W3-3", "T_W3-2", "Balcony", "Page5", "Page4", "T_W3-7",
	"MazeIn", "T_W3-1", "Pool", "T_W3-8", "T_W3-8b", "T_W3-6b", "T_W3-6", "Page1"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = String(dev.call("arg", "vis-out", OS.get_user_data_dir().path_join("w3_vis"))) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and String(cs.get("world_id")) == "W3" and get_tree().get_first_node_in_group("player") != null and cs.get_node_or_null("Level") != null:
			world = cs as Node3D
			player = get_tree().get_first_node_in_group("player") as Node3D
			break
		if Time.get_ticks_msec() - t0 > 240000:
			print("[W3VIS] TIMEOUT")
			get_tree().quit(2)
			return
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600, 900)
	await _wait(4.0)
	_audit_characters()
	_audit_prims()
	_audit_env()
	var dev2 := get_node_or_null("/root/Dev")
	if dev2 and dev2.call("has_arg", "vis-chars"):
		await _char_closeups()
		var f2 := FileAccess.open(out_dir.path_join("vis_w3_chars.json"), FileAccess.WRITE)
		f2.store_string(JSON.stringify(report, "  "))
		f2.close()
		print("[W3VIS] CHARS DONE")
		get_tree().quit(0)
		return
	var spawns := world.get_node_or_null("Spawns")
	for nm in ROUTE:
		var label: String = nm if nm != "" else "start"
		if nm != "":
			var m := spawns.get_node_or_null(nm) as Node3D if spawns else null
			if m == null:
				report["shots"].append({"label": label, "missing": true})
				continue
			player.call("respawn", Transform3D(Basis(Vector3.UP, m.rotation.y), m.global_position))
		await _wait(0.4)
		var cam := player.get_node_or_null("MakCamera")
		if cam and cam.has_method("snap_behind"):
			cam.call("snap_behind")
		await _wait(2.2)
		var fn := await _shot(label)
		report["shots"].append({"label": label, "png": fn, "mak": _v(player.global_position)})
	var f := FileAccess.open(out_dir.path_join("vis_w3_probe.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[W3VIS] DONE %d shots" % report["shots"].size())
	get_tree().quit(0)


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]


func _shot(label: String) -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var utc := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var fn := "%sZ__vis_%s.png" % [utc, label.replace(" ", "_").replace("/", "-")]
	img.save_png(out_dir.path_join(fn))
	return fn


func _is_char(n: Node) -> bool:
	if n == player:
		return false
	for g in ["enemy", "enemies", "npc", "npcs", "creature", "ambient_creature", "boss"]:
		if n.is_in_group(g):
			return true
	var s := n.get_script() as Script
	if s:
		var p := s.resource_path
		if p.contains("/enemies/") or p.contains("npc") or p.contains("creature"):
			return true
	return false


func _audit_characters() -> void:
	var seen := {}
	for n in world.find_children("*", "Node3D", true, false):
		if not _is_char(n):
			continue
		# Skip nested character nodes already counted under a character parent.
		var par := n.get_parent()
		var nested := false
		while par and par != world:
			if seen.has(par.get_instance_id()):
				nested = true
				break
			par = par.get_parent()
		if nested:
			continue
		seen[n.get_instance_id()] = true
		var glb := []
		var prim := []
		var arr := 0
		for d in n.find_children("*", "", true, false):
			if d.scene_file_path.ends_with(".glb") or d.scene_file_path.ends_with(".gltf"):
				glb.append(d.scene_file_path.get_file())
			if d is MeshInstance3D and (d as MeshInstance3D).is_visible_in_tree():
				var mesh := (d as MeshInstance3D).mesh
				if mesh is PrimitiveMesh:
					prim.append("%s:%s" % [d.name, mesh.get_class()])
				elif mesh != null:
					arr += 1
		var sp := n.get_script() as Script
		report["characters"].append({"name": String(n.name), "path": String(world.get_path_to(n)), "script": sp.resource_path.get_file() if sp else "",
			"scene": n.scene_file_path.get_file(), "glb": glb, "array_meshes": arr, "primitive_meshes": prim, "pos": _v((n as Node3D).global_position)})


func _audit_prims() -> void:
	var by_kind := {}
	var untextured := 0
	var total := 0
	for d in world.find_children("*", "MeshInstance3D", true, false):
		var mi := d as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		total += 1
		var mesh := mi.mesh
		if mesh is PrimitiveMesh:
			var k := mesh.get_class()
			by_kind[k] = int(by_kind.get(k, 0)) + 1
			var mat := mi.material_override if mi.material_override else mi.get_surface_override_material(0)
			if mat == null:
				mat = (mesh as PrimitiveMesh).material
			if mat == null or (mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture == null):
				untextured += 1
	report["prims"] = {"visible_mesh_instances": total, "primitive_by_kind": by_kind, "primitive_untextured_or_flat": untextured}


func _audit_env() -> void:
	var env_info := {}
	var we := world.find_children("*", "WorldEnvironment", true, false)
	if we.size() > 0 and (we[0] as WorldEnvironment).environment:
		var e := (we[0] as WorldEnvironment).environment
		env_info = {"bg": e.background_mode, "sky": e.sky != null, "sky_mat": e.sky.sky_material.get_class() if e.sky and e.sky.sky_material else "",
			"tonemap": e.tonemap_mode, "exposure": e.tonemap_exposure, "glow": e.glow_enabled, "glow_thr": e.glow_hdr_threshold,
			"ssao": e.ssao_enabled, "ssil": e.ssil_enabled, "fog": e.fog_enabled, "fog_density": e.fog_density, "fog_color": str(e.fog_light_color),
			"vol_fog": e.volumetric_fog_enabled, "adj": e.adjustment_enabled, "sat": e.adjustment_saturation, "ambient_src": e.ambient_light_source,
			"ambient_energy": e.ambient_light_energy}
	var lights := []
	for l in world.find_children("*", "Light3D", true, false):
		var li := l as Light3D
		if li is DirectionalLight3D:
			lights.append({"name": String(li.name), "energy": li.light_energy, "color": str(li.light_color), "shadow": li.shadow_enabled, "rot": _v(li.global_rotation_degrees)})
	var omni := world.find_children("*", "OmniLight3D", true, false).size() + world.find_children("*", "SpotLight3D", true, false).size()
	var parts := world.find_children("*", "GPUParticles3D", true, false).size() + world.find_children("*", "CPUParticles3D", true, false).size()
	var anims := world.find_children("*", "AnimationPlayer", true, false).size()
	var glbs := {}
	for d in world.find_children("*", "Node3D", true, false):
		var sf: String = d.scene_file_path
		if sf.ends_with(".glb"):
			glbs[sf.get_file()] = int(glbs.get(sf.get_file(), 0)) + 1
	report["env"] = {"world_env": env_info, "directional": lights, "local_lights": omni, "particles": parts, "anim_players": anims, "glb_instances": glbs}


const CLOSE := ["CorporalCrumb", "Hansel", "Gretel", "MotherTreacle", "NPCTalker", "sergeant_snap", "brute_clearing", "crow_bridge"]


func _char_closeups() -> void:
	for nm in CLOSE:
		var n := world.find_child(nm, true, false) as Node3D
		if n == null:
			report["shots"].append({"label": nm, "missing": true})
			continue
		var p := n.global_position
		# Stand Mak 3.2 m away on the side facing the camera default (south, +Z), facing the character.
		var off := Vector3(0, 0, 3.2)
		var q := p + off + Vector3(0, 1.0, 0)
		var space := (world as Node3D).get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3(0, 4, 0), q - Vector3(0, 12, 0)))
		if hit:
			q = hit["position"] + Vector3(0, 0.2, 0)
		player.call("respawn", Transform3D(Basis(Vector3.UP, 0.0), q))
		await _wait(0.4)
		var cam := player.get_node_or_null("MakCamera")
		if cam and cam.has_method("snap_behind"):
			cam.call("snap_behind")
		await _wait(2.0)
		var fn := await _shot("char_" + nm)
		var sp := n.get_script() as Script
		var glb := []
		for d in n.find_children("*", "", true, false):
			if d.scene_file_path.ends_with(".glb"):
				glb.append(d.scene_file_path.get_file())
		var vis_prims := []
		for d in n.find_children("*", "MeshInstance3D", true, false):
			if (d as MeshInstance3D).is_visible_in_tree() and (d as MeshInstance3D).mesh is PrimitiveMesh:
				vis_prims.append("%s:%s" % [d.name, (d as MeshInstance3D).mesh.get_class()])
		report["shots"].append({"label": nm, "png": fn, "char_pos": _v(p), "mak": _v(player.global_position), "glb": glb,
			"visible_primitives": vis_prims.slice(0, 20), "visible_primitive_count": vis_prims.size(), "script": sp.resource_path.get_file() if sp else ""})
