extends Node
## Integration check with the real player (res://scenes/player/Player.tscn): drops Mak onto each
## family's head with respawn(), lets the player's own stomp code and the enemy HeadZone resolve it,
## and reports what happened. Run: EnemyLab.tscn -- --real-player --realstomp --quit-when-done

var lab: Node3D
var player: Node3D
var rows: Array = []


func start(l: Node3D) -> void:
	lab = l
	player = lab.get("player") as Node3D
	_run.call_deferred()


func _run() -> void:
	for i in 40:
		await get_tree().physics_frame
	var enemies: Dictionary = lab.get("enemies")
	# Freeze every enemy so only the stomp under test happens (no stray peas or dives).
	for k in enemies.keys():
		if is_instance_valid(enemies[k]):
			(enemies[k] as EnemyBase).ai_enabled = false
	if Dev.has_arg("contact-only"):
		await _contact_pass(enemies)
		return
	for id in ["woolly_wolf", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]:
		var raw: Variant = enemies.get(id)
		if not is_instance_valid(raw):
			continue
		var e := raw as EnemyBase
		e.ai_enabled = false
		var hp0 := e.hp
		var top := e.global_position + Vector3(0, e.head_height + 1.6, 0)
		lab.set("cam_target", e.global_position)
		lab.set("cam_offset", Vector3(2.4, 2.4, 5.4))
		if player.has_method("respawn"):
			player.call("respawn", Transform3D(Basis(), top))
		else:
			player.global_position = top
		var max_vy := -100.0
		for f in 75:
			await get_tree().physics_frame
			var v: Variant = player.get("velocity")
			if v is Vector3:
				max_vy = maxf(max_vy, (v as Vector3).y)
		if Dev.has_arg("debug"):
			print("[RealStomp] debug ", id, " enemy=", e.global_position if is_instance_valid(raw) else Vector3.ZERO, " player=", player.global_position, " state=", player.call("get_state_name") if player.has_method("get_state_name") else "?")
		var gone := not is_instance_valid(raw) or (raw as EnemyBase).is_defeated
		var hp1: int = -1 if not is_instance_valid(raw) else (raw as EnemyBase).hp
		var row := {"family": id, "hp_before": hp0, "hp_after": hp1, "defeated": gone, "player_max_vy_after": snappedf(max_vy, 0.1)}
		rows.append(row)
		print("[RealStomp] ", row)
		for f in 40:
			await get_tree().physics_frame
	# Contact pass: each attacker gets one go at a stationary real Mak (fresh enemies are needed, so
	# this runs only with --realcontact on a lab where the stomp pass was skipped via --contact-only).
	var path := Dev.arg("realstomp-out", "user://realstomp.json")
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify({"utc": Time.get_datetime_string_from_system(true) + "Z", "player": "res://scenes/player/Player.tscn", "rows": rows}, "  "))
		fa.close()
	print("[RealStomp] DONE -> ", path)
	if Dev.has_arg("quit-when-done"):
		get_tree().quit()


func _contact_pass(enemies: Dictionary) -> void:
	for id in ["woolly_wolf", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]:
		var raw: Variant = enemies.get(id)
		if not is_instance_valid(raw):
			continue
		var e := raw as EnemyBase
		var pens: Dictionary = lab.get("pens")
		var stand := (pens[id] as Node3D).global_position + Vector3(0, 0.2, 1.0)
		if id == "gingerbread_grenadier":
			stand = e.global_position + Vector3(0, 0.2, 1.8)
		elif id == "bumble_bruiser":
			stand = (pens[id] as Node3D).global_position + Vector3(0, 0.2, 6.5)
		player.call("respawn", Transform3D(Basis(), stand))
		lab.set("cam_target", stand)
		lab.set("cam_offset", Vector3(3.0, 2.8, 6.0))
		var h0: int = int(EnemyKit.game_get(self, "health", 6))
		if h0 < 6:
			EnemyKit.game_call(self, "full_heal")
			h0 = int(EnemyKit.game_get(self, "health", 6))
		for k in enemies.keys():
			if is_instance_valid(enemies[k]):
				(enemies[k] as EnemyBase).ai_enabled = String(k).begins_with(id)
		var t := 0.0
		var hurt := false
		while t < 9.0 and not hurt:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if int(EnemyKit.game_get(self, "health", 6)) < h0:
				hurt = true
			if Dev.has_arg("debug") and int(t * 60.0) % 12 == 0 and is_instance_valid(raw):
				print("[RealContact] dbg ", id, " ", e.state, " e=", e.global_position, " p=", player.global_position)
		for k in enemies.keys():
			if is_instance_valid(enemies[k]):
				(enemies[k] as EnemyBase).ai_enabled = false
		var row := {"family": id, "real_player_damaged": hurt, "seconds": snappedf(t, 0.1), "enemy_state": e.state if is_instance_valid(raw) else "gone"}
		rows.append(row)
		print("[RealContact] ", row)
		# Let the player's invulnerability frames run out before the next family.
		for f in 200:
			await get_tree().physics_frame
	var path := Dev.arg("realstomp-out", "user://realcontact.json")
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify({"utc": Time.get_datetime_string_from_system(true) + "Z", "player": "res://scenes/player/Player.tscn", "contact_rows": rows}, "  "))
		fa.close()
	print("[RealContact] DONE -> ", path)
	if Dev.has_arg("quit-when-done"):
		get_tree().quit()
