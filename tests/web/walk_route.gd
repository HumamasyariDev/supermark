extends "res://scripts/worlds/w1_bot.gd"
## Uses the desktop check's real MakInput steering, without respawns or AI edits.
var world := ""
var result: Dictionary = {"done": false}

func _ready() -> void:
	process_physics_priority = -100
	p = get_tree().get_first_node_in_group("player") as CharacterBody3D
	level = get_parent().get_node_or_null("Level")
	if p == null:
		result = {"done": true, "error": "player missing"}
		return
	inp = p.get("inp")
	inp.set("replay_active", true)
	inp.set("steer_world", true)
	if world != "":
		_run.call_deferred()

func tp(at: Vector3, _yaw_deg: float = 0.0) -> void:
	# The desktop mission check starts a leg with a teleport. This version
	# walks there from the ordinary spawn; failures remain failures.
	if world == "W1" and at.z < 29.5 and pos().z > 29.5:
		# Page Lane reaches the house from its south side. A direct diagonal
		# crosses the house; walk round its east and north faces first.
		for waypoint: Vector3 in [Vector3(-10,0,38),Vector3(-10,0,20),Vector3(-22,0,20)]:
			if not await go(waypoint,0.5,12.0):
				return
	await go(at, 0.5, 20.0)

func _run() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	if world == "W1":
		ok = await t_w1_1()
	elif world == "W2":
		ok = await _beanstalk()
	elif world == "HUB":
		ok = true
		var origin := p.global_position
		for offset: Vector3 in [Vector3(4,0,0),Vector3(4,0,-6),Vector3(-4,0,-6),Vector3(-4,0,0),Vector3.ZERO]:
			ok = await go(origin+offset,0.5,12.0) and ok
	else:
		# The route is intentionally a measured input attempt, not a shortcut
		# that changes progress when navigation cannot reach its destination.
		var origin := p.global_position
		for offset: Vector3 in [Vector3(0,0,-8),Vector3(-6,0,-8),Vector3.ZERO]:
			ok = await go(origin+offset,0.5,12.0)
	stick = Vector2.ZERO
	inp.set("replay_active", false)
	result = {"done": true, "world": world, "passed": ok, "seconds":(Time.get_ticks_msec()-start)/1000.0,
		"log":_log, "truffles":Game.data.get("truffles",{}),"teleports":0,
		"scope":"first mission" if world in ["W1","W2"] else "walking input sample"}
	print("[WebRoute] ",JSON.stringify(result))

func _beanstalk() -> bool:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/w2/w2_level.json"))
	var platforms: Dictionary = {}
	for platform: Dictionary in data["platforms"]:
		var at: Array = platform["pos"]
		platforms[platform["id"]] = Vector3(at[0],at[1],at[2])
	await go(Vector3(5,0,8),0.5,15.0)
	await go(Vector3(1.6,0,6),0.4,8.0)
	for id in ["L01","L02","L03","L04","L05","L06","L07","L08"]:
		if not await hop(platforms[id],Vector3.INF,18,0.65):
			# As in the desktop platform chain, retry a missed jump from the
			# actual landing position. Never place Mak on the destination leaf.
			await frames(4)
			if not await hop(platforms[id],Vector3.INF,18,0.65):
				note("leaf route stopped at "+id)
				return false
	var vine: Vector3 = platforms["V1"]
	steer_to(vine)
	hold("jump",18)
	for f in 120:
		if String(p.call("get_state_name")) == "pole_climb":
			break
		steer_to(vine)
		await frames(1)
	if String(p.call("get_state_name")) != "pole_climb":
		return false
	stick = Vector2(0,1)
	for f in 240:
		if pos().y >= 13.9:
			break
		await frames(1)
	var want: Vector3 = (platforms["L09"]-vine).normalized()
	for f in 240:
		var radial := Vector3(pos().x-vine.x,0,pos().z-vine.z).normalized()
		if radial.dot(Vector3(want.x,0,want.z).normalized()) > 0.985:
			break
		stick = Vector2(0.6,0)
		await frames(1)
	if not await hop(platforms["L09"],Vector3.INF,24,0.65):
		return false
	# Remaining upward route is attempted through actual player jumps and bounce.
	for id in ["BL1","L11","L12","L13","C1"]:
		if not platforms.has(id):
			continue
		if not await hop(platforms[id],Vector3.INF,18,0.65):
			return false
	await go(Vector3(-9.6,25,-16.2),0.4,10.0)
	await frames(90)
	return Game.has_truffle("W2-1")
