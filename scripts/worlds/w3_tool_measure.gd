extends SceneTree
## Dev tool: prints AABB and a coarse top-height map (max vertex y per cell) of W3 prop GLBs, in the GLB's
## own frame (+Z front). Used to fit gameplay colliders to the generated meshes.
## Run: python tools/godot.py script res://scripts/worlds/w3_tool_measure.gd

const PATHS := [
	"res://assets/props/w3/gingerbread_cottage/gingerbread_cottage.glb",
	"res://assets/props/w3/cauldron/cauldron.glb",
	"res://assets/props/w3/cupcake_tower/cupcake_tower.glb",
]


func _init() -> void:
	for p in PATHS:
		var ps := load(p) as PackedScene
		if ps == null:
			print("missing ", p)
			continue
		var inst := ps.instantiate() as Node3D
		var verts := PackedVector3Array()
		_collect(inst, Transform3D(), verts)
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := -mn
		for v in verts:
			mn = mn.min(v)
			mx = mx.max(v)
		print("== %s verts=%d aabb min=%s max=%s" % [p.get_file(), verts.size(), mn, mx])
		var cell := 0.5
		var nx := int(ceil((mx.x - mn.x) / cell)) + 1
		var nz := int(ceil((mx.z - mn.z) / cell)) + 1
		var top := PackedFloat32Array()
		top.resize(nx * nz)
		top.fill(-1.0)
		for v in verts:
			var ix := int((v.x - mn.x) / cell)
			var iz := int((v.z - mn.z) / cell)
			var k := iz * nx + ix
			top[k] = maxf(top[k], v.y)
		# rows from back (-Z) to front (+Z)
		for iz in nz:
			var line := "z=%5.2f " % (mn.z + iz * cell)
			for ix in nx:
				var t := top[iz * nx + ix]
				line += ("  .  " if t < 0.0 else "%4.1f " % t)
			print(line)
		inst.free()
	quit(0)


func _collect(n: Node, xf: Transform3D, out: PackedVector3Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		if m:
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					out.append(t * v)
	for c in n.get_children():
		_collect(c, t, out)
