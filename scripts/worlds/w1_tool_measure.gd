extends SceneTree
## W1 dev tool: prints the AABB of every generated GLB the W1 builder may use.
## Run: python tools/godot.py script res://scripts/worlds/w1_tool_measure.gd

func _init() -> void:
	var dirs: Array[String] = ["res://assets/props/w1/", "res://assets/props/pickups/", "res://assets/characters/", "res://assets/enemies/"]
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			var p: String = d + sub + "/" + sub + ".glb"
			if not ResourceLoader.exists(p):
				continue
			var ps := load(p) as PackedScene
			if ps == null:
				continue
			var inst := ps.instantiate() as Node3D
			var a := W1Kit._aabb(inst, Transform3D.IDENTITY)
			var tris := 0
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).mesh
				if m:
					for s in m.get_surface_count():
						var arr := m.surface_get_arrays(s)
						var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
						tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			print("[measure] %s pos=%s size=%s tris=%d anim=%s" % [p, a.position, a.size, tris, inst.find_children("*", "AnimationPlayer", true, false).size()])
			inst.free()
	quit(0)
