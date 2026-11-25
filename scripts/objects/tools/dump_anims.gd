extends SceneTree
## Objects tool: lists AnimationPlayer clips of every character GLB, and runs the Wolf Door stud split report.

func _init() -> void:
	var d := "res://assets/characters/"
	var da := DirAccess.open(d)
	for sub in da.get_directories():
		var da2 := DirAccess.open(d + sub)
		if da2 == null:
			continue
		for f in da2.get_files():
			if not f.ends_with(".glb"):
				continue
			var ps := load(d + sub + "/" + f) as PackedScene
			if ps == null:
				continue
			var n := ps.instantiate()
			var clips: Array = []
			for ap in n.find_children("*", "AnimationPlayer", true, false):
				for a in (ap as AnimationPlayer).get_animation_list():
					clips.append("%s(%.2fs)" % [a, (ap as AnimationPlayer).get_animation(a).length])
			print("ANIMS ", sub, "/", f, " ", clips)
			n.free()
	var door := (load("res://assets/props/hub/wolf_door/wolf_door.glb") as PackedScene).instantiate() as Node3D
	var leaf := door.find_child("door_leaf", true, false) as MeshInstance3D
	var frame := leaf.get_parent() as MeshInstance3D
	print("DOOR leaf=", leaf.mesh.get_aabb(), " leaf_xf=", leaf.transform, " frame=", frame.mesh.get_aabb())
	var res: Array = WolfDoor._split_frame(frame.mesh as ArrayMesh, leaf.mesh, leaf.transform)
	print("DOOR split ", WolfDoor.split_report, " ok=", not res.is_empty())
	door.free()
	quit()
