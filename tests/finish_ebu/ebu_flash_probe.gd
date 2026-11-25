extends Node3D
## Finish pass (ENEMIES-BOSS-UI): hit-flash decay probe. Spawns each family on a floor with a camera, lands a lethal
## stomp through the real EnemyBase.hit_by_player (Juice hit-stop included) and logs the white overlay alpha on every
## rendered frame; saves a capture 3 frames after the hit for the first family.
## Run: python tools/godot.py run res://tests/finish_ebu/EbuFlashProbe.tscn --seconds 60 -- --profile=ebu_flash

const FAMS := ["WoollyWolf", "PeapodPopper", "GummyBrute", "GingerbreadGrenadier", "CrowBandit", "BumbleBruiser"]


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.6, 4.5)
	cam.look_at(Vector3(0, 0.6, 0))
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	await get_tree().create_timer(0.3).timeout
	for fi in FAMS.size():
		var e := (load("res://scenes/enemies/%s.tscn" % FAMS[fi]) as PackedScene).instantiate() as Node3D
		e.set("ai_enabled", false)
		add_child(e)
		e.global_position = Vector3(0, 0.05, 0)
		await get_tree().create_timer(1.2).timeout
		e.set("hp", 1)
		e.set("_hit_cooldown", 0.0)
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_usec()
		e.call("hit_by_player", "stomp", e.global_position + Vector3(0, 3.0, 0))
		var row: Array = []
		for k in 14:
			await RenderingServer.frame_post_draw
			var tint: Color = e.get("_flash_tint")
			row.append("%d:%.2f" % [Engine.get_frames_drawn() - f0, tint.a])
			if fi == 0 and k == 2:
				var img := get_viewport().get_texture().get_image()
				img.save_png(ProjectSettings.globalize_path("res://").path_join("../Docs/progress/finish/enemies_boss_ui/after_defeat_flash_wolf_f3.png").simplify_path())
		var full := 0
		for r in row:
			if float(String(r).split(":")[1]) >= 0.5:
				full += 1
		print("[EBU-FLASH] %s frames with overlay >= 0.5: %d  (%s)  real %.0f ms" % [FAMS[fi], full, ", ".join(row), (Time.get_ticks_usec() - t0) / 1000.0])
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(e):
			e.queue_free()
	get_tree().quit()
