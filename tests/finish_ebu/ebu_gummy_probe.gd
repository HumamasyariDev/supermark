extends Node3D
## Finish pass (ENEMIES-BOSS-UI): gummy checks with the lab stand-in player 6 m away and a camera on both.
## Logs: the landing disc alive during the jump ("attack"), the landing squash, and the state after a hurt
## (must go through the attack token: windup only when granted, else stalk).
## Run: python tools/godot.py run res://tests/finish_ebu/EbuGummyProbe.tscn --seconds 90 -- --profile=ebu_gummy


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(8, 6, 10)
	cam.look_at(Vector3(0, 0.5, 3))
	cam.make_current()
	var pl := EnemyLabPlayer.new()
	pl.keyboard = false
	pl.add_to_group("player")
	add_child(pl)
	pl.global_position = Vector3(0, 0.1, 6)
	var g := (load("res://scenes/enemies/GummyBrute.tscn") as PackedScene).instantiate() as Node3D
	add_child(g)
	g.global_position = Vector3(0, 0.05, 0)
	var last_state := ""
	var min_sy := 9.0
	var t := 0.0
	var hurt_done := false
	while t < 14.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var st := String(g.get("state"))
		if st != last_state:
			var mk: Variant = g.get("_marker")
			print("[EBU-GUMMY] t=%.2f %s -> %s marker=%s" % [t, last_state, st, str(mk != null and is_instance_valid(mk))])
			last_state = st
		if st == "attack" and g.get("_marker") == null:
			print("[EBU-GUMMY] t=%.2f FAIL: no landing disc during the jump" % t)
		if st == "recover":
			var rig: Variant = g.get("rig")
			if rig is Node3D:
				min_sy = minf(min_sy, (rig as Node3D).scale.y / maxf((g.get("scale_mult") as Vector3).y, 0.01))
		if not hurt_done and st == "recover" and float(g.get("state_time")) > 0.6:
			hurt_done = true
			print("[EBU-GUMMY] landing min rig sy (recover) = %.2f" % min_sy)
			g.set("_hit_cooldown", 0.0)
			var r: Variant = g.call("hit_by_player", "punch", g.global_position + Vector3(0, 0.5, 1.0))
			print("[EBU-GUMMY] punch landed=%s hp=%d" % [str(r), int(g.get("hp"))])
	get_tree().quit()
