extends Node
## Finish pass (ENEMIES-BOSS-UI): Wardrobe vs worn hat. Fresh profile: Game.get_hat() must be the top hat Mak wears;
## choosing the beanie must switch; the pause Wardrobe is captured in the hub.
## Run: python tools/godot.py run res://tests/finish_ebu/EbuHatProbe.tscn --seconds 90 -- --profile=ebu_hat_<n>


func _ready() -> void:
	if name != "EbuHatRunner":
		var r := Node.new()
		r.name = "EbuHatRunner"
		r.set_script(get_script())
		get_tree().root.add_child.call_deferred(r)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var g := get_node("/root/Game")
	print("[EBU-HAT] fresh: get_hat=%s available=%s" % [g.call("get_hat"), str(g.call("available_hats"))])
	get_node("/root/Router").call("go_to_hub", "")
	await get_tree().create_timer(8.0, true, false, true).timeout
	var p := get_tree().get_first_node_in_group("player")
	print("[EBU-HAT] in hub: player hat=%s" % [str(p.get("hat")) if p != null else "-"])
	get_node("/root/UI").call("open_pause")
	await get_tree().create_timer(1.2, true, false, true).timeout
	_shot("after_wardrobe_default_top_hat")
	get_node("/root/UI").get("pause_menu").call("close") if get_node("/root/UI").get("pause_menu").has_method("close") else null
	await get_tree().create_timer(0.5, true, false, true).timeout
	g.call("set_hat", "beanie")
	await get_tree().create_timer(0.5, true, false, true).timeout
	print("[EBU-HAT] after choosing beanie: get_hat=%s explicit=%s player hat=%s" % [g.call("get_hat"), str((g.get("data") as Dictionary).get("hat_explicit")), str(p.get("hat")) if p != null else "-"])
	g.call("set_hat", "top_hat")
	print("[EBU-HAT] back to top hat: get_hat=%s" % [g.call("get_hat")])
	get_tree().quit()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://").path_join("../Docs/progress/finish/enemies_boss_ui/%s.png" % tag).simplify_path())
