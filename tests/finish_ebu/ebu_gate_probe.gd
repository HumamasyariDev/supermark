extends Node3D
## Finish pass (ENEMIES-BOSS-UI): hit-resolution probe through the real EnemyBase.hit_by_player.
## 1) Sergeant-style hit_gate: a gated stomp bounces and a gated punch clangs, hp untouched; an open gate hurts.
## 2) Grenadier: a frontal punch clangs in patrol, the third clang carries the hint, a punch in recover lands.
## 3) Wolf / peapod: a dive before they act stuns (wolf) or bounces (pod) instead of defeating.
## Run: python tools/godot.py run res://tests/finish_ebu/EbuGateProbe.tscn --seconds 60 -- --profile=ebu_gate

var _gate_open := false


func _gate(_kind: String) -> bool:
	return _gate_open


func _spawn(scene: String) -> Node3D:
	var e := (load(scene) as PackedScene).instantiate() as Node3D
	e.set("ai_enabled", false)
	add_child(e)
	e.global_position = Vector3(0, 0.05, 0)
	return e


func _hit(e: Node3D, kind: String, from: Vector3) -> String:
	e.set("_hit_cooldown", 0.0)
	var hp0 := int(e.get("hp"))
	var r: Variant = e.call("hit_by_player", kind, from)
	return "%s -> ret %s, hp %d->%d, state %s" % [kind, str(r), hp0, int(e.get("hp")), String(e.get("state"))]


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
	await get_tree().create_timer(0.3).timeout
	# 1) gate
	var g := _spawn("res://scenes/enemies/GingerbreadGrenadier.tscn")
	await get_tree().create_timer(1.0).timeout
	g.set("max_hp", 99)
	g.set("hp", 99)
	g.set_meta("hit_gate", _gate)
	var behind: Vector3 = g.global_position - (g.call("forward") as Vector3) * 1.0
	print("[EBU-GATE] gated stomp: ", _hit(g, "stomp", g.global_position + Vector3(0, 2.5, 0)))
	print("[EBU-GATE] gated punch (behind): ", _hit(g, "punch", behind))
	_gate_open = true
	await get_tree().create_timer(0.6).timeout
	print("[EBU-GATE] open punch (behind): ", _hit(g, "punch", behind))
	g.remove_meta("hit_gate")
	# 2) grenadier clang loop and recover
	await get_tree().create_timer(0.8).timeout
	g.call("set_state", "patrol")
	var front: Vector3 = g.global_position + (g.call("forward") as Vector3) * 1.0
	for i in 3:
		await get_tree().create_timer(0.3).timeout
		print("[EBU-GATE] frontal punch %d in patrol: %s, next block text '%s'" % [i + 1, _hit(g, "punch", front), String(g.get("_block_text_once"))])
	g.call("set_state", "recover")
	print("[EBU-GATE] frontal punch in recover: ", _hit(g, "punch", front))
	g.queue_free()
	# 3) dives
	var w := _spawn("res://scenes/enemies/WoollyWolf.tscn")
	await get_tree().create_timer(1.0).timeout
	w.call("set_state", "prowl")
	print("[EBU-GATE] wolf dive in prowl: ", _hit(w, "dive", w.global_position + Vector3(0, 0.3, 1.0)), " disguised=", w.get("disguised"))
	await get_tree().create_timer(0.5).timeout
	print("[EBU-GATE] wolf stomp while dizzy: ", _hit(w, "stomp", w.global_position + Vector3(0, 2.5, 0)))
	await get_tree().create_timer(1.0).timeout
	var p := _spawn("res://scenes/enemies/PeapodPopper.tscn")
	await get_tree().create_timer(1.0).timeout
	print("[EBU-GATE] pod dive in idle: ", _hit(p, "dive", p.global_position + Vector3(0, 0.3, 1.0)))
	await get_tree().create_timer(0.4).timeout
	print("[EBU-GATE] pod stomp: ", _hit(p, "stomp", p.global_position + Vector3(0, 2.5, 0)))
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
