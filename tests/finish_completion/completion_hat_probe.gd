extends Node
const GoldenHatLib := preload("res://scripts/objects/golden_hat.gd")
## Completion pass: Golden Top Hat (boss reward). Fresh profile: the golden hat is not available; after the boss's
## unlock (Game.unlock("golden_top_hat"), as WolfBoss._on_truffle does) it is, Mak wears it gilded in the hub, the
## Wardrobe shows its card, and choosing the plain top hat removes the gold.
## Run: python tools/godot.py run res://tests/finish_completion/CompletionHatProbe.tscn --seconds 120 -- --profile=completion_hat_<n>


func _ready() -> void:
	if name != "CompletionHatRunner":
		var r := Node.new()
		r.name = "CompletionHatRunner"
		r.set_script(get_script())
		get_tree().root.add_child.call_deferred(r)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var g := get_node("/root/Game")
	print("[HAT] fresh: get_hat=%s available=%s" % [g.call("get_hat"), str(g.call("available_hats"))])
	g.call("unlock", "golden_top_hat")
	g.call("set_hat", "golden_top_hat")
	print("[HAT] after unlock: get_hat=%s available=%s" % [g.call("get_hat"), str(g.call("available_hats"))])
	get_node("/root/Router").call("go_to_hub", "From_BOSS")
	var p: Node = null
	for i in 120:
		await get_tree().create_timer(0.5, true, false, true).timeout
		p = get_tree().get_first_node_in_group("player")
		if p != null and get_tree().current_scene != null and String(get_tree().current_scene.name) == "Hub":
			break
	await get_tree().create_timer(4.0, true, false, true).timeout
	print("[HAT] in hub: player hat=%s gilded=%s watcher=%s" % [str(p.get("hat")), str(_gilded(p)), str(p.get_node_or_null("GoldenHat") != null)])
	# A close-up camera in front of Mak (the first hub visit opens on the Wolf's door taunt, not on Mak).
	await get_tree().create_timer(6.0, true, false, true).timeout
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	var pn := p as Node3D
	var fwd := -pn.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3(0, 0, 1)
	cam.global_position = pn.global_position + fwd * 2.4 + Vector3(0, 1.3, 0)
	cam.look_at(pn.global_position + Vector3(0, 0.95, 0), Vector3.UP)
	cam.fov = 40.0
	cam.current = true
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("hat_golden_in_hub")
	cam.current = false
	if prev:
		prev.current = true
	cam.queue_free()
	get_node("/root/UI").call("open_pause")
	await get_tree().create_timer(1.2, true, false, true).timeout
	_shot("hat_golden_wardrobe")
	var pm: Node = get_node("/root/UI").get("pause_menu")
	if pm and pm.has_method("close"):
		pm.call("close")
	await get_tree().create_timer(0.5, true, false, true).timeout
	g.call("set_hat", "top_hat")
	await get_tree().create_timer(0.5, true, false, true).timeout
	print("[HAT] plain top hat: player hat=%s gilded=%s" % [str(p.get("hat")), str(_gilded(p))])
	g.call("set_hat", "golden_top_hat")
	await get_tree().create_timer(0.5, true, false, true).timeout
	print("[HAT] golden again: player hat=%s gilded=%s" % [str(p.get("hat")), str(_gilded(p))])
	get_tree().quit()


func _gilded(p: Node) -> bool:
	var parts: Variant = p.get("v2_parts")
	if not (parts is Dictionary) or not (parts as Dictionary).has("top_hat"):
		return false
	var hat := (parts as Dictionary)["top_hat"] as Node
	for mi in hat.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == GoldenHatLib.material():
			return true
	return false


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://").path_join("../Docs/progress/finish/completion/%s.png" % tag).simplify_path())
