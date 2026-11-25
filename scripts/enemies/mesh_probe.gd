extends Node3D
## Dev helper (res://scenes/enemies/MeshProbe.tscn): prints bounds, bones and which contract
## part names each generated enemy mesh provides, then quits. Run through tools/godot.py.

func _ready() -> void:
	for id in ["woolly_wolf", "woolly_wolf_cub", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]:
		var p := "res://assets/enemies/%s/%s.glb" % [id, id]
		if not ResourceLoader.exists(p):
			print("[MeshProbe] ", id, " missing")
			continue
		var n := (load(p) as PackedScene).instantiate() as Node3D
		add_child(n)
		var bones: Array = []
		for sk in n.find_children("*", "Skeleton3D", true, false):
			var s := sk as Skeleton3D
			for i in s.get_bone_count():
				bones.append(s.get_bone_name(i))
		print("[MeshProbe] ", id, " bones=", bones)
		n.queue_free()
	get_tree().quit()
