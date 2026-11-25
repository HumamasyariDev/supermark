extends SceneTree
## Lists every character/pickup GLB with its skeleton bones, node names and AABB (objects workstream tool).

func _init() -> void:
	var dirs := ["res://assets/characters/", "res://assets/props/pickups/", "res://assets/props/hub/wolf_door/"]
	for d in dirs:
		_scan(d)
	quit()

func _scan(d: String) -> void:
	var da := DirAccess.open(d)
	if da == null:
		return
	for sub in da.get_directories():
		_scan(d + sub + "/")
	for f in da.get_files():
		if f.ends_with(".glb"):
			var ps := load(d + f) as PackedScene
			if ps == null:
				continue
			var n := ps.instantiate() as Node3D
			var bones: Array = []
			for s in n.find_children("*", "Skeleton3D", true, false):
				var sk := s as Skeleton3D
				for i in sk.get_bone_count():
					bones.append(sk.get_bone_name(i))
			var names: Array = []
			for c in n.find_children("*", "Node3D", true, false):
				if not (c is Skeleton3D):
					names.append(str(c.name) + ":" + c.get_class().replace("MeshInstance3D", "Mesh"))
			var bb := AABB()
			var first := true
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				var xf := Transform3D()
				var p: Node = m
				while p != null and p != n:
					if p is Node3D:
						xf = (p as Node3D).transform * xf
					p = p.get_parent()
				var b := xf * m.mesh.get_aabb()
				bb = b if first else bb.merge(b)
				first = false
			print("GLB ", d + f, " size=", bb.size, " pos=", bb.position)
			print("   bones=", bones)
			print("   nodes=", names.slice(0, 14))
			n.free()
