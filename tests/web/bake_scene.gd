extends Node
## Offline texture bake: real scene builders and the desktop palette algorithm.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var area := String(Dev.arg("bake-area", "HUB"))
	if area == "UI":
		await _bake_portraits()
		print("[WebBake] UI: %d entries" % RetroLook._web_manifest.size())
		get_tree().quit()
		return
	var path := WorldRegistry.scene_path(area)
	if area == "TITLE":
		path = "res://scenes/boot/Boot.tscn"
	seed(1863)
	var scene := (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	# Builders and late-spawned pickups need a few frames; stop physics to avoid
	# collecting anything or letting idle enemies hurt the test player.
	PhysicsServer3D.set_active(false)
	for frame in 40:
		await get_tree().process_frame
	RetroLook.apply_to(scene)
	if area == "W1":
		# The haystack and alerted wolves reveal a different model during play.
		# An idle scene visit only bakes its static-prop role elsewhere in the hub.
		# Exercise the real swap on the offline instance to bake the enemy role.
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy.has_method("_swap_to_cub_mesh"):
				enemy._swap_to_cub_mesh()
				break
		for _frame in 3:
			await get_tree().process_frame
		RetroLook.apply_to(scene)
	if area == "W2":
		# The fired pea uses a mesh from the original peapod model, while the
		# standing enemy uses its v2 model. Bake the actual projectile as well.
		var pea := PeaProjectile.new()
		scene.add_child(pea)
		pea.process_mode = Node.PROCESS_MODE_DISABLED
		RetroLook.apply_to(scene)
	for frame in 10:
		await get_tree().process_frame
	print("[WebBake] %s: %d entries" % [area, RetroLook._web_manifest.size()])
	get_tree().quit()


func _bake_portraits() -> void:
	var view := UIModelView.new()
	view.size = Vector2(32, 32)
	add_child(view)
	var seen: Dictionary = {}
	for info: Array in UISpeakers.SPEAKERS.values():
		var path := String(info[0])
		if seen.has(path):
			continue
		seen[path] = true
		view.set_model(path, "bust")
		for _frame in 3:
			await get_tree().process_frame
		RetroLook.apply_to(view)
		for _frame in 3:
			await get_tree().process_frame
