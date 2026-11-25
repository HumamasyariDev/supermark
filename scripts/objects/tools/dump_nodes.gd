extends SceneTree
## Prints node transforms and mesh AABBs of chosen GLBs (objects workstream tool).

func _init() -> void:
	for p in ["res://assets/props/pickups/bookmark_checkpoint/bookmark_checkpoint.glb", "res://assets/props/hub/wolf_door/wolf_door.glb",
			"res://assets/props/w2/goose_cage/goose_cage.glb", "res://assets/props/hub/book_lectern/book_lectern.glb",
			"res://assets/props/pickups/breakable_crate/breakable_crate_pieces.glb", "res://assets/props/pickups/lost_page/lost_page.glb"]:
		var n := (load(p) as PackedScene).instantiate() as Node3D
		print("== ", p)
		_walk(n, n, 0)
		n.free()
	quit()

func _walk(root: Node3D, n: Node, depth: int) -> void:
	if n is Node3D:
		var t := (n as Node3D).transform
		var extra := ""
		if n is MeshInstance3D:
			var m := (n as MeshInstance3D).mesh
			extra = " aabb=" + str(m.get_aabb()) + " surf=" + str(m.get_surface_count())
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				extra += " mat%d=%s" % [i, mat.resource_name if mat else "null"]
		print("  ".repeat(depth), n.name, " pos=", t.origin, " rot=", t.basis.get_euler() * 57.2958, " scl=", t.basis.get_scale(), extra)
	for c in n.get_children():
		_walk(root, c, depth + 1)
