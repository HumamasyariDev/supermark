extends SceneTree
## W2 builder tool: prints the bounds and node names of the W2 prop and character GLBs.

const PATHS := [
	"res://assets/props/w2/giant_leaf/giant_leaf.glb",
	"res://assets/props/w2/giant_leaf/giant_leaf_bouncy.glb",
	"res://assets/props/w2/beanstalk_segment/beanstalk_segment.glb",
	"res://assets/props/w2/bean_flower/bean_flower.glb",
	"res://assets/props/w2/jack_cottage/jack_cottage.glb",
	"res://assets/props/w2/giant_castle/giant_castle.glb",
	"res://assets/props/w2/giant_teacup/giant_teacup.glb",
	"res://assets/props/w2/giant_loaf/giant_loaf.glb",
	"res://assets/props/w2/pocket_watch/pocket_watch.glb",
	"res://assets/props/w2/goose_cage/goose_cage.glb",
	"res://assets/props/w2/golden_harp/golden_harp.glb",
	"res://assets/props/w2/giant_chair/giant_chair.glb",
	"res://assets/props/w2/sugar_bowl/sugar_bowl.glb",
	"res://assets/characters/golden_goose/golden_goose.glb",
	"res://assets/characters/pip/pip.glb",
	"res://assets/characters/bramwell/bramwell.glb",
	"res://assets/characters/sleeping_giant/sleeping_giant.glb",
	"res://assets/characters/jack/jack.glb",
	"res://assets/characters/daisy_cow/daisy_cow.glb",
	"res://assets/characters/wolf_scarecrow/wolf_scarecrow.glb",
]


func _init() -> void:
	for p in PATHS:
		if not ResourceLoader.exists(p):
			print("MISSING ", p)
			continue
		var n: Node3D = (load(p) as PackedScene).instantiate()
		var aabb := AABB()
		var first := true
		var names := []
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			names.append(m.name)
			var xf := Transform3D()
			var c: Node = m
			while c != n and c != null:
				if c is Node3D:
					xf = (c as Node3D).transform * xf
				c = c.get_parent()
			var b := xf * m.get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		print("%s pos=%s size=%s meshes=%s" % [p.get_file(), aabb.position, aabb.size, names])
		n.free()
	quit()
