extends SceneTree
## Objects tool: prints the wolf_door.glb hierarchy, AABBs and how many door_frame triangles sit over the leaf.

func _init() -> void:
	var n := (load("res://assets/props/hub/wolf_door/wolf_door.glb") as PackedScene).instantiate() as Node3D
	for c in n.find_children("*", "Node3D", true, false):
		var t := (c as Node3D).transform
		var extra := ""
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D).mesh
			extra = " aabb=%s surf=%d" % [m.get_aabb(), m.get_surface_count()]
		print(c.name, " parent=", c.get_parent().name, " origin=", t.origin, " basis_euler=", t.basis.get_euler() * 57.2958, extra)
	quit()
