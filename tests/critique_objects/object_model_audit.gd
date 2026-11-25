extends SceneTree
## Critique OBJECTS r1 (visual lens): loads a world, waits for the builders, then audits
##  (1) every node driven by a res://scripts/objects/ script: does it show a generated model (a descendant instanced
##      from res://assets/) or only runtime-built procedural meshes?
##  (2) every character GLB instance (res://assets/characters/ or res://assets/enemies/): is it animated
##      (NpcLife, a playing AnimationPlayer, or an enemy script above it) or a frozen rest pose?
## Usage: python tools/godot.py script tests/critique_objects/object_model_audit.gd -- --world=res://scenes/worlds/w1/W1.tscn --out=<abs.json>

var _world_path := ""
var _out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			_world_path = a.split("=", true, 1)[1]
		elif a.begins_with("--out="):
			_out = a.split("=", true, 1)[1]
	_run.call_deferred()


func _from_assets(n: Node, stop: Node) -> bool:
	var c := n
	while c != null:
		if c.scene_file_path.begins_with("res://assets/"):
			return true
		if c == stop:
			break
		c = c.get_parent()
	return false


func _run() -> void:
	var ps := load(_world_path) as PackedScene
	if ps == null:
		push_error("cannot load " + _world_path)
		quit(1)
		return
	var w := ps.instantiate()
	root.add_child(w)
	for i in 90:
		await process_frame
	var objects := []
	var chars := []
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script() as Script
		var sp := s.resource_path if s != null else ""
		if sp.begins_with("res://scripts/objects/") and n is Node3D:
			var gen := 0
			var proc := 0
			var glbs := {}
			for m in n.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				if not mi.is_visible_in_tree() or mi.mesh == null:
					continue
				if _from_assets(mi, n):
					gen += 1
				else:
					proc += 1
			for d in n.find_children("*", "Node3D", true, false):
				if (d as Node).scene_file_path.begins_with("res://assets/"):
					glbs[(d as Node).scene_file_path.get_file()] = true
			objects.append({"name": str(n.name), "script": sp.get_file(), "visible": (n as Node3D).is_visible_in_tree(),
				"generated_meshes": gen, "procedural_meshes": proc, "glbs": glbs.keys()})
		if n is Node3D and (n.scene_file_path.begins_with("res://assets/characters/") or n.scene_file_path.begins_with("res://assets/enemies/")):
			var has_life := false
			var anim_playing := false
			var driver := ""
			for c in n.get_children():
				if c.get_script() != null and str((c.get_script() as Script).resource_path).ends_with("npc_life.gd"):
					has_life = true
			for ap in n.find_children("*", "AnimationPlayer", true, false):
				if (ap as AnimationPlayer).is_playing():
					anim_playing = true
			var p := n.get_parent()
			var depth := 0
			while p != null and depth < 4:
				for c in p.get_children():
					if c.get_script() != null and str((c.get_script() as Script).resource_path).ends_with("npc_life.gd"):
						has_life = true
				if p.get_script() != null and driver == "":
					driver = str((p.get_script() as Script).resource_path).get_file()
				p = p.get_parent()
				depth += 1
			chars.append({"node": str(n.get_path()).replace(str(w.get_path()), ""), "glb": n.scene_file_path.get_file(),
				"visible": (n as Node3D).is_visible_in_tree(), "npc_life": has_life, "anim_playing": anim_playing, "driver_script": driver})
	var summary := {"world": _world_path, "objects": objects, "characters": chars}
	var txt := JSON.stringify(summary, "  ")
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string(txt)
		f.close()
	var proc_only := 0
	for o in objects:
		if o["visible"] and o["generated_meshes"] == 0 and o["procedural_meshes"] > 0:
			proc_only += 1
			print("[Audit] PROCEDURAL-ONLY ", o["script"], " ", o["name"], " meshes=", o["procedural_meshes"])
	var frozen := 0
	for c in chars:
		if c["visible"] and not c["npc_life"] and not c["anim_playing"]:
			frozen += 1
			print("[Audit] STATIC CHARACTER ", c["glb"], " at ", c["node"], " driver=", c["driver_script"])
	print("[Audit] objects=", objects.size(), " procedural_only=", proc_only, " characters=", chars.size(), " static=", frozen)
	quit(0)
