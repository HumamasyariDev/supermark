extends SceneTree
## Hub builder tool: prints the AABB (metres) of every GLB the hub may use.
## python tools/godot.py script res://scripts/worlds/hub_tool_measure.gd


func _init() -> void:
	var dirs := ["res://assets/props/hub", "res://assets/characters", "res://assets/props/w1", "res://assets/props/w2", "res://assets/props/w3"]
	for d in dirs:
		_scan(d)
	quit()


func _scan(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	for sub in da.get_directories():
		_scan(path + "/" + sub)
	for f in da.get_files():
		if f.ends_with(".glb"):
			var p := path + "/" + f
			var ps := load(p) as PackedScene
			if ps == null:
				print("HUBMEASURE ", p, " LOAD FAILED")
				continue
			var n := ps.instantiate() as Node3D
			var box := _aabb(n, Transform3D.IDENTITY)
			var tris := _tris(n)
			print("HUBMEASURE %s size=%s pos=%s tris=%d" % [p, box.size, box.position, tris])
			n.free()


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a := t * (n as MeshInstance3D).mesh.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _aabb(c, t)
		if ca.size != Vector3.ZERO:
			out = ca if first else out.merge(ca)
			first = false
	return out


func _tris(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				c += (idx as PackedInt32Array).size() / 3
			else:
				c += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for ch in n.get_children():
		c += _tris(ch)
	return c
