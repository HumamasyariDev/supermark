extends Node3D
## Finish pass (ENEMIES-BOSS-UI): dormant bee wake check (notice radius 0). Derived from the gummy probe.
## Original: gummy checks with the lab stand-in player 6 m away and a camera on both.
## Logs: the landing disc alive during the jump ("attack"), the landing squash, and the state after a hurt
## (must go through the attack token: windup only when granted, else stalk).
## Run: python tools/godot.py run res://tests/finish_ebu/EbuBeeProbe.tscn --seconds 60 -- --profile=ebu_bee


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
	var b := (load("res://scenes/enemies/BumbleBruiser.tscn") as PackedScene).instantiate() as Node3D
	add_child(b)
	b.global_position = Vector3(0, 1.5, 0)
	await get_tree().create_timer(0.3).timeout
	b.set("notice_radius", 0.0)
	b.call("set_state", "hover")
	pl.global_position = Vector3(0, 0.1, 6)
	await get_tree().create_timer(2.0).timeout
	print("[EBU-BEE] dormant, Mak at 6 m after 2 s: state=%s" % String(b.get("state")))
	pl.global_position = Vector3(0, 0.1, 2.0)
	await get_tree().create_timer(1.5).timeout
	print("[EBU-BEE] dormant, Mak at 2 m after 1.5 s: state=%s" % String(b.get("state")))
	get_tree().quit()
