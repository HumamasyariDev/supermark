extends Node3D
## In-world enemy verification (enemies track). Loads a real world scene, frames one enemy of a family
## with a close review camera and plays a short scripted beat: idle, provoke (the real player is moved
## into view so the enemy notices and attacks), then a forced defeat so the gag and FX show in context.
## Args (after --): --world=res://scenes/worlds/w1/W1.tscn --family=woolly_wolf [--index=0]
##   [--cam-dist=4.5] [--cam-height=1.6] [--cam-side=0.35] [--provoke-at=2.0] [--defeat-at=6.0] [--no-defeat]
## Use with tools/godot.py capture (--wait) or movie (--frames).

var world: Node
var target: EnemyBase
var cam: Camera3D
var t: float = 0.0
var _provoked: bool = false
var _defeated: bool = false
var _base_y: float = 0.0


func _ready() -> void:
	var path := Dev.arg("world", "res://scenes/worlds/w1/W1.tscn")
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("[WorldCheck] cannot load " + path)
		return
	world = ps.instantiate()
	add_child(world)
	cam = Camera3D.new()
	cam.name = "ReviewCam"
	cam.fov = 50.0
	add_child(cam)
	_pick.call_deferred()


func _pick() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var fam := Dev.arg("family", "woolly_wolf")
	var idx := int(Dev.arg("index", "0"))
	var found: Array[EnemyBase] = []
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as EnemyBase
		if e != null and e.enemy_id == fam and not e.is_defeated:
			found.append(e)
	found.sort_custom(func(a: EnemyBase, b: EnemyBase) -> bool: return String(a.name) < String(b.name))
	print("[WorldCheck] ", fam, " found ", found.size(), " in ", Dev.arg("world"))
	if found.is_empty() or Dev.has_arg("place"):
		# The world has none placed yet (W3 tonight): drop one in front of the default spawn, on the ground.
		found.clear()
		var e := _place_one(fam)
		if e == null:
			return
		await get_tree().physics_frame
		await get_tree().physics_frame
		found.append(e)
	target = found[clampi(idx, 0, found.size() - 1)]
	print("[WorldCheck] target ", target.name, " at ", target.global_position)
	# Keep Mak out of the enemy's sight until the provoke beat.
	var p := EnemyKit.find_player(get_tree())
	if p != null and not Dev.has_arg("keep-player"):
		p.global_position = target.global_position + Vector3(0, 0, 30)
		if p.has_method("reset_physics_interpolation"):
			p.reset_physics_interpolation()
	_base_y = target.global_position.y
	cam.make_current()
	_place_cam(1.0)


const SCENES := {"woolly_wolf": "WoollyWolf", "crow_bandit": "CrowBandit", "peapod_popper": "PeapodPopper",
	"bumble_bruiser": "BumbleBruiser", "gingerbread_grenadier": "GingerbreadSquad", "gummy_brute": "GummyBrute"}


func _place_one(fam: String) -> EnemyBase:
	var sp := world.find_child("Default", true, false) as Node3D
	var at := sp.global_position if sp != null else Vector3.ZERO
	var off := Dev.arg("place-offset", "0,0,-7").split(",")
	at += Vector3(float(off[0]), float(off[1]), float(off[2]))
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 20, 0), at + Vector3(0, -40, 0))
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position
	var ps := load("res://scenes/enemies/%s.tscn" % SCENES.get(fam, "WoollyWolf")) as PackedScene
	var n := ps.instantiate() as Node3D
	if fam == "gingerbread_grenadier":
		n.set("with_sergeant", Dev.has_arg("sergeant"))
		n.set("size", int(Dev.arg("squad", "3")))
	if fam == "crow_bandit":
		at.y += 2.5
	world.add_child(n)
	n.global_position = at + Vector3(0, 0.05, 0)
	n.rotation.y = deg_to_rad(float(Dev.arg("place-yaw", "0")))
	print("[WorldCheck] placed ", fam, " at ", n.global_position)
	if n is EnemyBase:
		return n as EnemyBase
	for c in n.get_children():
		if c is EnemyBase:
			return c as EnemyBase
	return null


var _cam_off: Vector3 = Vector3.ZERO


## Chooses a fixed 3/4 view between the enemy's front and the side Mak will come from, rejecting
## directions blocked by world geometry, then keeps that offset (the camera only trails big moves).
func _place_cam(k: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var focus := target.global_position + Vector3(0, target.head_height * 0.55, 0)
	if _cam_off == Vector3.ZERO:
		var dist := float(Dev.arg("cam-dist", "4.5"))
		var h := float(Dev.arg("cam-height", "1.6"))
		var f := -target.global_transform.basis.z
		f.y = 0
		f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
		var base := deg_to_rad(float(Dev.arg("provoke-angle", "-70")) * 0.5)
		var best := Vector3.ZERO
		for i in 12:
			var a := base + deg_to_rad(float(i / 2) * 30.0 * (1.0 if i % 2 == 0 else -1.0))
			var dir := f.rotated(Vector3.UP, a)
			var off := dir * dist + Vector3(0, h - target.head_height * 0.55, 0)
			var q := PhysicsRayQueryParameters3D.create(focus, focus + off * 1.1)
			q.collision_mask = 0xFFFFFFFF
			q.exclude = [target.get_rid()]
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				best = off
				break
		_cam_off = best if best != Vector3.ZERO else f * dist + Vector3(0, h, 0)
	var want := focus + _cam_off
	cam.global_position = cam.global_position.lerp(want, k)
	cam.look_at(focus, Vector3.UP)


func _physics_process(_delta: float) -> void:
	# The player's gameplay camera re-takes "current" when Mak is teleported for the provoke beat (impl3 world clips
	# switched to it); the review camera keeps the shot.
	if target != null and cam != null and not cam.current:
		cam.make_current()


func _process(delta: float) -> void:
	t += delta
	if target == null:
		return
	if not cam.current:
		cam.make_current()
	if fmod(t, 2.0) < delta:
		var vc := get_viewport().get_camera_3d()
		print("[WorldCheck] t=", snappedf(t, 0.1), " viewport camera ", vc.get_path() if vc != null else NodePath("none"), " review current=", cam.current)
	if not is_instance_valid(target):
		return
	if not cam.current:
		cam.make_current()
	if is_instance_valid(target):
		# Lock the framing to the first placement; only follow when the enemy moves away a lot.
		_place_cam(0.03 if t > 0.2 else 1.0)
	var provoke_at := float(Dev.arg("provoke-at", "2.0"))
	if not _provoked and t > provoke_at and is_instance_valid(target):
		_provoked = true
		var p := EnemyKit.find_player(get_tree())
		if p != null:
			var f := -target.global_transform.basis.z
			f.y = 0
			f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
			var ang := deg_to_rad(float(Dev.arg("provoke-angle", "-70")))
			var d := f.rotated(Vector3.UP, ang) * float(Dev.arg("provoke-dist", "5.5"))
			p.global_position = target.global_position + d + Vector3(0, 0.3, 0)
			if p.has_method("reset_physics_interpolation"):
				p.reset_physics_interpolation()
		print("[WorldCheck] provoke at t=", snappedf(t, 0.01))
	var defeat_at := float(Dev.arg("defeat-at", "6.0"))
	if not _defeated and not Dev.has_arg("no-defeat") and t > defeat_at and is_instance_valid(target):
		_defeated = true
		print("[WorldCheck] defeat at t=", snappedf(t, 0.01), " state=", target.state)
		target.defeat("stomp", target.global_position + Vector3(0, 2, 0))
