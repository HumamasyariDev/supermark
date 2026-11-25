extends Node3D
## Preview only (vfx workstream): the enemy roster before (left, imported PBR) and after FxToon (right).
## Run: python tools/godot.py capture res://scenes/fx/ToonPreview.tscn out.png --cam StoryCam_A -- --profile=vfx

const ENEMIES := ["woolly_wolf", "woolly_wolf_cub", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]


func _ready() -> void:
	var we := WorldEnvironment.new()
	add_child(we)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	FxEnvironments.apply(self, "W1")
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	ground.mesh = pm
	ground.material_override = FxMaterials.toon(Color.WHITE, "grass", 0.25)
	add_child(ground)
	var x := -8.4
	for e in ENEMIES:
		var path := "res://assets/enemies/%s/%s.glb" % [e, e]
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		for side in 2:
			var inst := ps.instantiate() as Node3D
			add_child(inst)
			inst.position = Vector3(x, 0, -2.2 if side == 0 else 2.2)
			inst.rotation_degrees.y = -15.0
			if side == 1:
				FxToon.apply(inst)
		x += 2.8
	var post := FxPost.new()
	add_child(post)
	var cams := Node3D.new()
	cams.name = "StoryCams"
	add_child(cams)
	var c := Camera3D.new()
	c.name = "StoryCam_A"
	c.fov = 62.0
	cams.add_child(c)
	c.position = Vector3(0, 3.4, 10.5)
	c.look_at(Vector3(0, 0.5, 0.6), Vector3.UP)
	c.current = true
	var c2 := Camera3D.new()
	c2.name = "CloseCam"
	c2.fov = 40.0
	cams.add_child(c2)
	c2.position = Vector3(-5.6, 1.3, 5.6)
	c2.look_at(Vector3(-5.6, 0.6, 0.0), Vector3.UP)
