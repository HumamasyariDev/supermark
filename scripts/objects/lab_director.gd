extends Node3D
## ObjectsLab helper: spawns a player (the real Player.tscn when present, else ObjPlayerStub), marks one truffle id
## as owned so its ghost look can be reviewed (only with --profile=..., never on the real save), and adds name plates.

@export var player_spawn: Vector3 = Vector3(-13.0, 0.0, 2.8)
## Real Player.tscn when it exists (the scripted --demo always uses ObjPlayerStub, which it can drive).
@export var use_real_player: bool = true
@export var ghost_truffle_id: String = "LAB-GHOST"

const PLAYER_SCENE := "res://scenes/player/Player.tscn"


func _ready() -> void:
	var dev := ObjSvc.autoload("Dev")
	var profiled := dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "profile"))
	if profiled and ObjSvc.can("Game", "new_game"):
		# Deterministic lab: fresh progress in the test profile (never the real save).
		ObjSvc.call_on("Game", "new_game")
	ObjSvc.local_truffles[ghost_truffle_id] = true
	if profiled and ObjSvc.can("Game", "has_truffle") and not bool(ObjSvc.call_on("Game", "has_truffle", [ghost_truffle_id])):
		ObjSvc.call_on("Game", "collect_truffle", [ghost_truffle_id])
	_spawn_player.call_deferred()
	if profiled and dev.has_method("has_arg") and bool(dev.call("has_arg", "demo")):
		var plates := get_parent().get_node_or_null("Plates") as Node3D
		if plates:
			plates.visible = false
		_run_demo.call_deferred()


func _spawn_player() -> void:
	if get_tree().get_first_node_in_group("player") != null:
		return
	var p: Node3D = null
	var dev := ObjSvc.autoload("Dev")
	var demo := dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "demo"))
	var stub_demo := demo and bool(dev.call("has_arg", "stub"))
	if use_real_player and not stub_demo and ResourceLoader.exists(PLAYER_SCENE):
		var ps := load(PLAYER_SCENE) as PackedScene
		if ps:
			p = ps.instantiate() as Node3D
	if p == null:
		p = ObjPlayerStub.new()
	p.name = "Player"
	p.position = player_spawn
	p.rotation.y = deg_to_rad(200.0)
	get_parent().add_child(p)



# ------------------------------------------------------------------ scripted demo (--demo), for Movie Maker clips
# Offline deterministic capture. Drives the real Player.tscn through input actions (Input.action_press) and
# respawn() teleports, or the local ObjPlayerStub with --stub. Cameras cut between shots.

var _cam: Camera3D
var _p: Node3D


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(eye: Vector3, target: Vector3, fov: float = 50.0) -> void:
	_cam.fov = fov
	_cam.look_at_from_position(eye, target)
	_cam.make_current()


func _is_stub() -> bool:
	return _p.has_method("ham_slam")


func _release() -> void:
	for a in ["jump", "crouch", "attack", "sniff", "move_forward"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	if _is_stub():
		_p.set("move_dir", Vector3.ZERO)


func _put(at: Vector3, face: Vector3 = Vector3.INF) -> void:
	_release()
	var yaw := _p.rotation.y
	if face != Vector3.INF:
		var d := face - at
		yaw = atan2(-d.x, -d.z)
	if _p.has_method("respawn"):
		_p.call("respawn", Transform3D(Basis(Vector3.UP, yaw), at))
	else:
		_p.global_position = at
	_p.set("velocity", Vector3.ZERO)


func _tap(action: String, hold: int = 3) -> void:
	Input.action_press(action)
	await _frames(hold)
	Input.action_release(action)


func _slam() -> void:
	if _is_stub():
		_p.call("ham_slam")
	else:
		await _tap("crouch", 3)


func _punch() -> void:
	if _is_stub():
		_p.call("punch", "punch")
	else:
		await _tap("attack", 2)


## Walk away from the current demo camera (the real player steers relative to the active camera).
func _walk(frames_n: int, dir_world: Vector3) -> void:
	if _is_stub():
		_p.set("move_dir", dir_world.normalized() * 0.55)
		await _frames(frames_n)
		_p.set("move_dir", Vector3.ZERO)
	else:
		Input.action_press("move_forward", 0.55)
		await _frames(frames_n)
		Input.action_release("move_forward")


func _run_demo() -> void:
	await _frames(3)
	var lab := get_parent()
	_p = get_tree().get_first_node_in_group("player") as Node3D
	if _p == null:
		push_warning("[LabDirector] demo: no player")
		return
	_cam = Camera3D.new()
	_cam.name = "DemoCam"
	lab.add_child(_cam)
	# Shot 1: walk into the golden truffle (the real player celebrates).
	var cam_eye := Vector3(-23.5, 1.9, 4.6)
	var truffle := Vector3(-21.0, 0.0, 0.0)
	_shot(cam_eye, truffle + Vector3(0, 0.9, 0), 48.0)
	var fwd := truffle - cam_eye
	fwd.y = 0.0
	fwd = fwd.normalized()
	_put(truffle - fwd * 2.6 + Vector3(0, 0.05, 0), truffle)
	await _frames(30)
	await _walk(60, fwd)
	await _frames(110)
	# Shot 1b: grab a torn Lost Page.
	cam_eye = Vector3(-4.4, 1.9, 3.6)
	var page := Vector3(-6.0, 0.0, -0.5)
	_shot(cam_eye, page + Vector3(0, 1.0, 0), 50.0)
	fwd = page - cam_eye
	fwd.y = 0.0
	fwd = fwd.normalized()
	_put(page - fwd * 2.4 + Vector3(0, 0.05, 0), page)
	await _frames(20)
	await _walk(55, fwd)
	await _frames(60)
	# Shot 2: Ham Slam both switches; the cage lifts and releases a truffle.
	_shot(Vector3(21.5, 5.0, 9.5), Vector3(21.5, 1.2, -1.0), 55.0)
	_put(Vector3(19.0, 3.2, 1.0), Vector3(19.0, 3.2, -5.0))
	await _frames(12)
	await _slam()
	await _frames(60)
	_put(Vector3(24.0, 3.2, 1.0), Vector3(24.0, 3.2, -5.0))
	await _frames(12)
	await _slam()
	await _frames(150)
	# Shot 3: drum bounce pad.
	_shot(Vector3(-12.0, 3.0, -3.0), Vector3(-12.0, 2.6, -11.0), 55.0)
	_put(Vector3(-12.0, 4.0, -11.0), Vector3(-12.0, 4.0, -5.0))
	await _frames(170)
	# Shot 4: punch the crates; planks fly and acorns pop out and get pulled in.
	_shot(Vector3(13.6, 2.2, 4.8), Vector3(15.6, 0.8, 0.0), 50.0)
	_put(Vector3(14.6, 0.05, 1.3), Vector3(15.5, 0.05, 0.0))
	await _frames(25)
	await _punch()
	await _frames(30)
	await _punch()
	await _frames(80)
	# Shot 5: the bellows gust pushes Mak; a Ham Slam breaks it, the gust stops and the reward truffle appears.
	_shot(Vector3(13.0, 4.5, -17.5), Vector3(7.0, 1.0, -25.0), 55.0)
	_put(Vector3(6.0, 0.05, -24.5), Vector3(6.0, 0.05, -20.0))
	await _frames(80)
	_put(Vector3(6.0, 3.5, -27.3), Vector3(6.0, 3.5, -20.0))
	await _frames(12)
	await _slam()
	await _frames(150)
	# Shot 6: land on a vanishing cloud; it trembles, then puffs away.
	_shot(Vector3(4.0, 5.0, -5.5), Vector3(7.5, 3.0, -12.0), 50.0)
	_put(Vector3(7.5, 4.6, -12.0), Vector3(7.5, 4.6, -6.0))
	await _frames(150)
	print("[LabDirector] demo done at frame ", Engine.get_physics_frames())
