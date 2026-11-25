extends Node3D
## Preview only (vfx workstream): instances the W1 world and applies FxDresser, so the dressing can be
## reviewed without touching the W1 builder's files. Run with --cam=StoryCam_A etc.

func _ready() -> void:
	var ps := load("res://scenes/worlds/w1/W1.tscn") as PackedScene
	if ps == null:
		push_warning("[W1DressPreview] W1.tscn missing")
		return
	var w := ps.instantiate() as Node3D
	add_child(w)
	var terrain := w.find_child("Terrain", true, false)
	FxDresser.dress(w, {"terrain": terrain, "grass_per_m2": 3.5, "avoid_channels": Vector4(1, 1, 1, 0), "palette": "W1",
		"butterflies": [Vector3(0, 2, 0), Vector3(-20, 2, 15)], "leaves": [], "post": true, "seed": 3})
	# The Dev autoload looks up --cam in the current scene; story cameras live in the W1 instance.
