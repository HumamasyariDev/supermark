extends SceneTree
## Measures the reading surface of the generated book lectern (page bounds and slope) for StorybookPortal.

func _init() -> void:
	var n := (load("res://assets/props/hub/book_lectern/book_lectern.glb") as PackedScene).instantiate()
	var mi := n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var top := -1e9
	for p in v:
		top = maxf(top, p.y)
	print("top y ", top)
	# Slice the top 0.45 m into z bins and report max y per bin (desk slope) and x extent per bin.
	for zi in range(-7, 8):
		var z0 := zi * 0.1
		var my := -1e9
		var minx := 1e9
		var maxx := -1e9
		for p in v:
			if p.y > top - 0.6 and absf(p.z - z0) < 0.05:
				my = maxf(my, p.y)
				if p.y > top - 0.6:
					minx = minf(minx, p.x)
					maxx = maxf(maxx, p.x)
		if my > -1e8:
			print("z %.1f  maxy %.3f  x %.2f..%.2f" % [z0, my, minx, maxx])
	# Height profile across x at z = 0 (page dip at the spine).
	for xi in range(-9, 10):
		var x0 := xi * 0.1
		var my2 := -1e9
		for p in v:
			if absf(p.x - x0) < 0.04 and absf(p.z) < 0.1:
				my2 = maxf(my2, p.y)
		print("x %.1f  maxy(z~0) %.3f" % [x0, my2])
	n.free()
	quit()
