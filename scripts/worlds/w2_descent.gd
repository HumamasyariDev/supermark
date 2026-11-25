extends Node
## W2 round 3 (P2): the seed-parachute descent after W2-8. When the TRUFFLE GET! celebration for W2-8 ends,
## Mak grabs a bean seed from the burst flower and glides one full turn round the beanstalk down to the
## garden (CP0) in 12 s on a Catmull-Rom path (seed_descent_r3.waypoints, Mak's feet). Input is locked
## (the player's physics is paused and Mak is carried); jump after 1.5 s skips to the landing.
## The parachute is a procedural prop until the Tripo P2 bean-seed parachute exists (requested).
## Dev: --w2-descent starts it 2 s after load (capture and test aid).

const DURATION := 12.0
const EASE_IN := 1.5
const EASE_OUT := 1.0
const SKIP_AFTER := 1.5

var world: Node3D
var data: Dictionary
var player: Node3D
var curve: Curve3D
var length := 0.0
var running := false
var t := 0.0
var chute: Node3D
var cam: Camera3D
var prev_cam: Camera3D
var beats_done := {}
var _end_pos := Vector3(0, 0, 31)
var _saved_layer := 2


func setup(w: Node3D, d: Dictionary) -> void:
	world = w
	data = d
	var sd: Dictionary = d.get("seed_descent_r3", {})
	var pts: Array = sd.get("waypoints", [])
	if pts.size() < 4:
		return
	curve = Curve3D.new()
	var v: Array[Vector3] = []
	for a: Array in pts:
		v.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	# Land on the Default spawn mark (CP0's open lawn) so the gameplay camera starts clear of the gate posts.
	var dm := w.get_node_or_null("Spawns/Default") as Node3D
	if dm:
		v[v.size() - 1] = dm.position - Vector3(0, 0.05, 0)
	_end_pos = v[v.size() - 1]
	# Catmull-Rom through the waypoints as cubic Bezier handles.
	for i in v.size():
		var p0 := v[maxi(i - 1, 0)]
		var p2 := v[mini(i + 1, v.size() - 1)]
		var tan := (p2 - p0) / 6.0
		curve.add_point(v[i], -tan if i > 0 else Vector3.ZERO, tan if i < v.size() - 1 else Vector3.ZERO)
	curve.bake_interval = 0.25
	length = curve.get_baked_length()
	if w.has_signal("truffle_celebration_finished"):
		w.connect("truffle_celebration_finished", func(id: String) -> void:
			if id == "W2-8":
				start())
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_arg("w2-descent"):
		get_tree().create_timer(2.0).timeout.connect(start)


func _find_player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] as Node3D if not ps.is_empty() else null


## Distance along the path for time s: ease in, cruise, ease out (piecewise, continuous speed).
func _dist(s: float) -> float:
	var cruise_t := DURATION - EASE_IN - EASE_OUT
	var v := length / (0.5 * EASE_IN + cruise_t + 0.5 * EASE_OUT)
	if s <= EASE_IN:
		return 0.5 * v * s * s / EASE_IN
	var d := 0.5 * v * EASE_IN
	if s <= EASE_IN + cruise_t:
		return d + v * (s - EASE_IN)
	d += v * cruise_t
	var u := minf(s - EASE_IN - cruise_t, EASE_OUT)
	return d + v * u - 0.5 * v * u * u / EASE_OUT


func start() -> void:
	if running or curve == null:
		return
	player = _find_player()
	if player == null:
		return
	running = true
	t = 0.0
	beats_done.clear()
	print("[W2] seed descent start, path %.1f m" % length)
	player.set_physics_process(false)
	# Carried, not simulated: hazards, enemies and pickups must not touch Mak on the way down.
	if player is CollisionObject3D:
		_saved_layer = (player as CollisionObject3D).collision_layer
		(player as CollisionObject3D).collision_layer = 0
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	_build_chute()
	prev_cam = get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.name = "DescentCam"
	cam.fov = 62.0
	cam.far = 1500.0
	world.add_child(cam)
	_place_cam(0.0, true)
	cam.make_current()
	_sfx("sfx_seed_whoosh")
	_say("Mak grabs a bean seed... and jumps!")


func _build_chute() -> void:
	chute = Node3D.new()
	chute.name = "SeedParachute"
	world.add_child(chute)
	var silk := StandardMaterial3D.new()
	silk.albedo_color = Color("fff3d6")
	silk.rim_enabled = true
	silk.rim = 0.5
	silk.cull_mode = BaseMaterial3D.CULL_DISABLED
	var canopy := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.2
	sm.height = 1.1
	sm.is_hemisphere = true
	sm.radial_segments = 24
	sm.rings = 8
	canopy.mesh = sm
	canopy.material_override = silk
	canopy.position = Vector3(0, 2.75, 0)
	canopy.scale = Vector3(1, 0.8, 1)
	chute.add_child(canopy)
	# Dandelion tufts round the rim.
	var tuft := SphereMesh.new()
	tuft.radius = 0.16
	tuft.height = 0.32
	for k in 12:
		var a := TAU * k / 12.0
		var m := MeshInstance3D.new()
		m.mesh = tuft
		m.material_override = silk
		m.position = Vector3(cos(a) * 1.18, 2.72, sin(a) * 1.18)
		chute.add_child(m)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("e8b23a")
	gold.metallic = 0.3
	gold.roughness = 0.35
	var seed := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.16
	cm.height = 0.6
	seed.mesh = cm
	seed.material_override = gold
	seed.position = Vector3(0, 1.75, 0)
	seed.rotation.z = PI * 0.5
	chute.add_child(seed)
	var line := StandardMaterial3D.new()
	line.albedo_color = Color("e9dcc0")
	for k in 6:
		var a := TAU * k / 6.0
		var top := Vector3(cos(a) * 1.15, 2.72, sin(a) * 1.15)
		var bot := Vector3(0, 1.8, 0)
		var s := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.015
		cy.bottom_radius = 0.015
		cy.height = top.distance_to(bot)
		s.mesh = cy
		s.material_override = line
		var up := (top - bot).normalized()
		var x := up.cross(Vector3.FORWARD).normalized()
		if x.length() < 0.1:
			x = Vector3.RIGHT
		s.transform = Transform3D(Basis(x, up, x.cross(up)), (top + bot) * 0.5)
		chute.add_child(s)


func _pos_at(s: float) -> Vector3:
	return curve.sample_baked(clampf(_dist(s), 0.0, length), true)


func _place_cam(s: float, snap := false) -> void:
	var p := _pos_at(s) + Vector3(0, 1.0, 0)
	var ahead := _pos_at(minf(s + 0.4, DURATION)) + Vector3(0, 1.0, 0)
	var tan := ahead - p
	if tan.length() < 0.01:
		tan = Vector3(0, 0, 1)
	tan = tan.normalized()
	# Outward from the stalk axis (about x -4, z -8) so the stalk stays in frame.
	var out := Vector3(p.x + 4.0, 0, p.z + 8.0)
	out = out.normalized() if out.length() > 0.1 else Vector3(0, 0, 1)
	var want: Vector3
	var look: Vector3
	if s < EASE_IN:
		want = p - tan * 7.0 + Vector3(0, 3.0, 0) + out * 3.0
		look = p - Vector3(0, 0.5, 0)
	else:
		# Keep the horizon in frame: flatten the look direction so the castle, stalk and garden read.
		var flat := Vector3(tan.x, tan.y * 0.35, tan.z)
		var hz := Vector3(tan.x, 0.0, tan.z)
		hz = hz.normalized() if hz.length() > 0.05 else -out
		want = p - hz * 7.0 + Vector3(0, 2.0, 0) + out * 3.0
		look = p + flat * 6.0 + Vector3(0, 0.3, 0)
	if s > DURATION - EASE_OUT:
		var k := smoothstep(DURATION - EASE_OUT, DURATION, s)
		var a2 := world.get_node_or_null("StoryCams/StoryCam_A_v2") as Camera3D
		if a2:
			want = want.lerp(a2.global_position, k * 0.5)
	if snap:
		cam.global_position = want
	else:
		cam.global_position = cam.global_position.lerp(want, 0.12)
	if cam.global_position.distance_to(look) > 0.1:
		cam.look_at(look, Vector3.UP)


func _physics_process(delta: float) -> void:
	if not running:
		return
	t += delta
	if t > SKIP_AFTER and Input.is_action_just_pressed("jump"):
		t = DURATION
	var s := minf(t, DURATION)
	var p := _pos_at(s)
	var nxt := _pos_at(minf(s + 0.1, DURATION))
	var dir := nxt - p
	dir.y = 0.0
	if is_instance_valid(player):
		var b := player.global_basis
		if dir.length() > 0.02:
			b = Basis.looking_at(dir.normalized(), Vector3.UP)
		player.global_transform = Transform3D(b, p + Vector3(0, sin(t * 2.2) * 0.08, 0))
	if chute:
		var sway := Basis(Vector3(0, 0, 1), sin(t * 1.7) * 0.12) * Basis(Vector3(1, 0, 0), sin(t * 1.3) * 0.08)
		chute.global_transform = Transform3D(sway, p + Vector3(0, -0.35, 0))
	if cam:
		_place_cam(s)
	_beats(s)
	if t >= DURATION:
		_finish()


func _beats(s: float) -> void:
	var lines := [
		[1.5, "ding!"],
		[3.4, "The Giant snores on: Zzz..."],
		[4.5, "Scarecrow: \"Bon voyage! ...I mean, halt!\""],
		[9.6, "Daisy: \"Moo! Show-off.\""],
	]
	for l: Array in lines:
		if s >= float(l[0]) and not beats_done.has(l[0]):
			beats_done[l[0]] = true
			_say(String(l[1]))


func _finish() -> void:
	running = false
	var land := Transform3D(Basis(), _end_pos + Vector3(0, 0.05, 0))
	var dmk := world.get_node_or_null("Spawns/Default") as Node3D
	if dmk:
		land = dmk.global_transform
	if is_instance_valid(player):
		player.set_physics_process(true)
		if player is CollisionObject3D:
			(player as CollisionObject3D).collision_layer = _saved_layer
		if player.has_method("respawn"):
			player.call("respawn", land)
		else:
			player.global_transform = land
		if player.has_method("celebrate"):
			player.call("celebrate")
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("set_checkpoint"):
		game.call("set_checkpoint", "W2", land)
	if chute:
		var c := chute
		chute = null
		var tw := c.create_tween()
		tw.tween_property(c, "global_position", c.global_position + Vector3(2.0, 9.0, -3.0), 3.0).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c, "scale", Vector3.ONE * 0.2, 3.0)
		tw.tween_callback(c.queue_free)
	if prev_cam and is_instance_valid(prev_cam):
		prev_cam.make_current()
	if cam:
		cam.queue_free()
		cam = null
	_say("Jack: \"BRAVO! Did you see that, Daisy? He FLEW!\"")
	print("[W2] seed descent end at %s" % (player.global_position if is_instance_valid(player) else Vector3.ZERO))


func _say(text: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.call("toast", text)


func _sfx(key: String) -> void:
	var au := get_node_or_null("/root/Audio")
	if au and au.has_method("play_sfx"):
		au.call("play_sfx", key)
