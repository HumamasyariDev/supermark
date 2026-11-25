extends Node3D
## W1-7 "The Foreman's Haystacks" (W1_amendments R2.1): a shell game in the hay yard beside the henchmen's camp.
## The Foreman whistles, dives into one of five haystacks, the stacks shuffle, then Mak has a guess window: Snout Sniff
## finds the occupied stack (or keep your eye on it), double-jump on top and Ham Slam it. Right: he bursts out (HP -1)
## and runs his ram charges (dodge, or hurdle him for +3 acorns). Wrong: empty hay, or a stack wolf in his smalls.
## Three rounds. Built and run by the W1 builder (w1_level.gd); the Foreman uses the Woolly Wolf model scaled up
## until the Foreman mesh (C08) lands. Deterministic under --seed=<n>.

const K := preload("res://scripts/worlds/w1_kit.gd")
const STACK_R := 4.0
const PEN_R := 8.0
const GATE_BEARING := 100.0
## Fix round 1 (fun critic r1): R3.1 sniff rules per round. "full": the trail finds him; "nervous": when the trail
## lands he panics ("Who's SNIFFING?") and his stack makes one 0.9 s swap, then sniffing is spent; "sock": a sock decoy
## stack is the only scent (it hides a stack wolf). Sniff needs a 1.5 s hold before any scent appears.
const ROUNDS := [
	{"swaps": 2, "swap_s": 1.4, "pairs": 1, "window": 8.0, "sneeze": 3.0, "sneeze_first": 2.0, "sniff": "full", "wrong": ["empty", "empty", "empty", "empty"], "charges": 1, "windup": 1.0, "speed": 10.0},
	# Fix round 2 (fun r1: round 2 was a difficulty cliff, a stack wolf plus two charges drained all six cake): a longer
	# window, a slower wind-up, and the stack wolf only behind the last wrong stack in slot order.
	{"swaps": 4, "swap_s": 1.0, "pairs": 1, "window": 7.0, "sneeze": 4.0, "sneeze_first": 3.0, "sniff": "nervous", "wrong": ["empty", "empty", "empty", "wolf"], "charges": 2, "windup": 1.0, "speed": 10.5},
	{"swaps": 5, "swap_s": 0.9, "pairs": 2, "window": 5.0, "sneeze": 0.0, "sneeze_first": 0.0, "sniff": "sock", "wrong": ["wolf", "wolf", "empty", "empty"], "charges": 3, "windup": 0.85, "speed": 12.0},
]
const SNIFF_HOLD := 1.5
const ASSIST_SNEEZE := 3.0

signal defeated

var center := Vector3.ZERO
var stacks: Array[AnimatableBody3D] = []
var slot_of: Array[int] = []        # stack index -> slot index
var contents: Array[String] = []    # stack index -> "foreman" | "empty" | "wolf"
var sniffs: Array[Node] = []
var foreman: Node3D
var say_label: Label3D
var gate: StaticBody3D
var gate_visual: Node3D
var spawner: Node3D
var state := "idle"
var hp := 3
var round_i := 0
var t := 0.0
var _swap_queue: Array = []
var _swap_from: Dictionary = {}
var _swap_to: Dictionary = {}
var _swap_t := 0.0
var _swap_len := 1.0
var _sneeze_t := 0.0
var _charges_left := 0
var _charge_dir := Vector3.ZERO
var _charge_from := Vector3.ZERO
var _charge_len := 0.0
var _hurdled := false
var _strip: Node3D
var _rng := RandomNumberGenerator.new()
var _guessed := false
var _sniff_hold := 0.0
var _sniff_spent := false
var _nervous := false
var _wrong := 0
var _decoy := -1
var poser: W1Poser


func setup(c: Vector3, reward_parent: Node) -> void:
	center = c
	var dev := get_node_or_null("/root/Dev")
	_rng.seed = int(dev.call("arg", "seed", "7")) if dev else 7
	_build_pen()
	_build_stacks()
	_build_foreman()
	spawner = Node3D.new()
	spawner.set_script(load("res://scripts/objects/truffle_spawner.gd"))
	spawner.name = "HayYardReward_W1-7"
	spawner.set("reward_truffle_id", "W1-7")
	spawner.set("show_ghost_if_owned", true)
	reward_parent.add_child(spawner)
	spawner.global_position = center + Vector3(0, 0.7, 0)


func slot_pos(slot: int) -> Vector3:
	var b := deg_to_rad(slot * 72.0)
	return center + Vector3(sin(b), 0, -cos(b)) * STACK_R


func _bearing_dir(deg: float) -> Vector3:
	var b := deg_to_rad(deg)
	return Vector3(sin(b), 0, -cos(b))


func _build_pen() -> void:
	var hay: PackedScene = load("res://assets/props/w1/hay_bale/hay_bale.glb") if ResourceLoader.exists("res://assets/props/w1/hay_bale/hay_bale.glb") else null
	var body := K.body(self, "PenWall")
	gate = K.body(self, "PenGate")
	# Fix round 2 (fun r1): the bale ring blocks Mak (layer 3, in his mask) but not the camera's spring arm (layer 1 only),
	# so the fight camera never snaps in behind a bale.
	body.collision_layer = 4
	gate.collision_layer = 4
	gate_visual = Node3D.new()
	gate_visual.name = "GateBales"
	add_child(gate_visual)
	var n := 30
	for i in n:
		var bearing := 360.0 * i / n
		var off := absf(wrapf(bearing - GATE_BEARING, -180.0, 180.0))
		var is_gate := off < 15.0
		var d := _bearing_dir(bearing)
		var p := center + d * PEN_R
		p.y = W1Terrain.height(p.x, p.z)
		var basis := Basis.looking_at(Vector3(-d.z, 0, d.x), Vector3.UP)
		var holder := Node3D.new()
		holder.transform = Transform3D(basis, p)
		(gate_visual if is_gate else self).add_child(holder)
		if hay:
			var bi := hay.instantiate() as Node3D
			bi.position.y = 0.06
			holder.add_child(bi)
		else:
			K.rbox(holder, Vector3(1.6, 1.1, 1.2), K.tex_mat("straw_thatch"), Vector3(0, 0.55, 0))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.65, 1.1, 1.2)
		cs.shape = bs
		cs.transform = Transform3D(basis, p + Vector3(0, 0.55, 0))
		(gate if is_gate else body).add_child(cs)
	_set_gate(false)


func _set_gate(closed: bool) -> void:
	gate_visual.visible = closed
	for c in gate.get_children():
		(c as CollisionShape3D).set_deferred("disabled", not closed)


func _build_stacks() -> void:
	var hay := K.tex_mat("straw_thatch", Color(1.1, 1.2, 1.7), 0.5)
	for i in 5:
		var s := AnimatableBody3D.new()
		s.name = "HS%d" % (i + 1)
		s.sync_to_physics = true
		s.collision_layer = 1
		s.collision_mask = 0
		s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		add_child(s)
		s.global_position = slot_pos(i)
		K.shape_cyl(s, 1.02, 1.87, Vector3(0, 0.935, 0))
		var v := Node3D.new()
		v.name = "Visual"
		s.add_child(v)
		# Fix round 1 (visual critic r1: gold-orange balls read as oranges or pumpkins): straw-yellow beehive cones with a
		# rope band, base wisps and a pitchfork with tines.
		K.sphere(v, 1.06, hay, Vector3(0, 0.8, 0), Vector3(1.0, 1.0, 1.0))
		K.cone(v, 0.86, 1.05, hay, Vector3(0, 1.75, 0), Vector3.ZERO, 14)
		K.torus(v, 0.9, 1.02, K.mat(Color("8a6a3a"), 0.9), Vector3(0, 1.22, 0))
		var hay_dark := K.tex_mat("straw_thatch", Color(0.85, 0.82, 1.0), 0.5)
		for w in 6:
			var wa := TAU * w / 6.0 + 0.3
			K.cone(v, 0.22, 0.42, hay_dark, Vector3(cos(wa) * 1.0, 0.16, sin(wa) * 1.0), Vector3(sin(wa) * 35.0, 0, -cos(wa) * 35.0), 6)
		var fork := K.mat(Color("6e4a2c"))
		K.cyl(v, 0.035, 0.035, 1.6, fork, Vector3(0.62, 1.75, 0.25), Vector3(18, 0, -22), 6)
		for tn in [-0.08, 0.0, 0.08]:
			K.cyl(v, 0.015, 0.015, 0.32, K.mat(Color("8d877d"), 0.4), Vector3(0.95 + tn, 2.55, 0.5), Vector3(18, 0, -22), 5)
		var sensor := SlamSensor.create(s, 1.0, 0.9, Vector3(0, 1.85, 0))
		sensor.slammed.connect(_on_slam.bind(i))
		# Fix round 2 (fun r1: three Ham Slams in a row bounced off the side of the stack, feet at y 0.3, no hit): a Ham
		# Slam that lands at the foot of a stack (within 1.75 m of its centre) counts for that stack too.
		var foot := SlamSensor.create(s, 1.75, 1.6, Vector3(0, -0.3, 0))
		foot.name = "FootSensor"
		foot.slammed.connect(_on_slam.bind(i))
		var sn := load("res://scenes/objects/SniffTarget.tscn") as PackedScene
		var st: Node = sn.instantiate() if sn else null
		if st:
			st.set("active", false)
			st.set("reveal_radius", 2.0)
			s.add_child(st)
			(st as Node3D).position = Vector3(0, 1.0, 0)
			st.remove_from_group("sniff_target")
		sniffs.append(st)
		stacks.append(s)
		slot_of.append(i)
		contents.append("empty")


func _build_foreman() -> void:
	foreman = Node3D.new()
	foreman.name = "FM1_Foreman"
	add_child(foreman)
	# The Foreman's own generated model (C08); the scaled Woolly Wolf is only the fallback.
	var path := "res://assets/characters/foreman/foreman_v2.glb"
	var scl := 1.2
	if not ResourceLoader.exists(path):
		path = "res://assets/characters/foreman/foreman.glb"
		scl = 1.0
	if not ResourceLoader.exists(path):
		path = "res://assets/enemies/woolly_wolf/woolly_wolf.glb"
		scl = 1.75
	if ResourceLoader.exists(path):
		var m := (load(path) as PackedScene).instantiate() as Node3D
		m.name = "Model"
		m.scale = Vector3.ONE * scl
		foreman.add_child(m)
		poser = W1Poser.attach(m)
	# Clipboard and a brass whistle, so the big wolf reads as the boss of the yard.
	K.rbox(foreman, Vector3(0.36, 0.5, 0.04), K.mat(Color("8a5a3b"), 0.7), Vector3(0.45, 1.0, 0.3), Vector3(-20, 0, 15), 0.02)
	K.rbox(foreman, Vector3(0.3, 0.38, 0.02), K.mat(Color("f6ecd6"), 0.9), Vector3(0.45, 1.02, 0.33), Vector3(-20, 0, 15), 0.01)
	K.cyl(foreman, 0.05, 0.05, 0.16, K.mat(Color("c9a04a"), 0.3), Vector3(0, 1.45, 0.42), Vector3(90, 0, 0), 8)
	say_label = Label3D.new()
	say_label.font_size = 64
	say_label.pixel_size = 0.006
	say_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	say_label.outline_size = 14
	say_label.modulate = Color(1, 0.95, 0.75)
	say_label.position = Vector3(0, 2.9, 0)
	foreman.add_child(say_label)
	foreman.global_position = center + Vector3(2.0, 0, 2.0)
	foreman.rotation_degrees.y = 200.0


func _pose(m: String) -> void:
	if poser and is_instance_valid(poser):
		poser.set_mode(m)


func say(text: String, dur := 1.8) -> void:
	say_label.text = text
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_callback(func() -> void:
		if say_label.text == text:
			say_label.text = "")


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _toast(s: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.call("toast", s)


func _physics_process(delta: float) -> void:
	var pl := _player()
	if pl == null or state == "done":
		return
	t += delta
	var pp := pl.global_position
	var flat := Vector2(pp.x - center.x, pp.z - center.z).length()
	match state:
		"idle":
			if flat < 11.0 and t > 3.0:
				t = 0.0
				say("Oi! No pigs in the hay yard!", 2.0)
			if flat < PEN_R - 0.8:
				_start_fight()
		"whistle":
			if t > 1.0:
				_dive()
		"dive":
			if t > (1.4 if _decoy >= 0 else 0.6):
				foreman.visible = false
				_begin_shuffle(int(ROUNDS[round_i]["swaps"]))
		"shuffle":
			_shuffle_step(delta)
		"window":
			_sniff_step(pl, delta)
			if _nervous:
				_shuffle_step(delta)
				return
			_sneeze_t -= delta
			var every: float = ROUNDS[round_i]["sneeze"]
			if _wrong >= 2:
				every = ASSIST_SNEEZE
			if every > 0.0 and _sneeze_t <= 0.0:
				_sneeze_t = every
				var s := stacks[contents.find("foreman")]
				ObjSvc.burst(self, s.global_position + Vector3(0, 1.9, 0), Color(1.0, 0.86, 0.45), 14, 3.0, 0.15, -6.0, 0.6)
				_float_text(s.global_position + Vector3(0, 2.6, 0), "Achoo!")
			if t > float(ROUNDS[round_i]["window"]):
				_burst(false)
		"charge_windup":
			if t > float(ROUNDS[round_i]["windup"]):
				_charge_from = foreman.global_position
				var tgt := pp
				_charge_dir = Vector3(tgt.x - _charge_from.x, 0, tgt.z - _charge_from.z).normalized()
				_charge_len = 0.0
				_hurdled = false
				if _strip:
					EnemyKit.fade_free(_strip)
					_strip = null
				state = "charge"
				t = 0.0
				_pose("charge")
				ObjSvc.sfx("wolf_charge", foreman.global_position)
			else:
				var d := Vector3(pp.x, 0, pp.z) - Vector3(foreman.global_position.x, 0, foreman.global_position.z)
				if d.length() > 0.1:
					foreman.rotation.y = atan2(d.x, d.z)
				if _strip == null and t > 0.15:
					_strip = EnemyKit.ground_strip(self, foreman.global_position + d.normalized() * 0.6, d.normalized(), 9.0, 1.0)
		"charge":
			var speed: float = ROUNDS[round_i]["speed"]
			var step := speed * delta
			var np := foreman.global_position + _charge_dir * step
			_charge_len += step
			var stop := _charge_len > 12.0 or Vector2(np.x - center.x, np.z - center.z).length() > PEN_R - 1.0
			if not stop:
				np.y = W1Terrain.height(np.x, np.z)
				foreman.global_position = np
			# Contact damage, or the hurdle bonus when Mak is 2 m up as he thunders past.
			var hd := Vector2(pp.x - np.x, pp.z - np.z).length()
			var feet_up := pp.y - W1Terrain.height(pp.x, pp.z)
			if hd < 1.5 and feet_up >= 2.0 and not _hurdled:
				_hurdled = true
				var g := get_node_or_null("/root/Game")
				if g and g.has_method("add_acorns"):
					g.call("add_acorns", 3)
				_float_text(pp + Vector3(0, 1.6, 0), "Ole! +3")
			elif hd < 1.1 and feet_up < 1.4 and pl.has_method("take_damage") and t > 0.1:
				pl.call("take_damage", 1, np)
				stop = true
			if stop:
				EnemyKit.burst(self, foreman.global_position, "dust", [Color(0.9, 0.84, 0.7)], 10, 2.5)
				_charges_left -= 1
				t = 0.0
				state = "charge_windup" if _charges_left > 0 else "rest"
				_pose("windup" if _charges_left > 0 else "idle")
				if _charges_left > 0:
					_back_off(pp)
		"rest":
			if t > 1.0:
				if hp <= 0:
					_defeat()
				else:
					_whistle()
	if state not in ["idle", "done"] and flat > PEN_R + 0.6:
		_nervous = false
		_decoy = -1
		_pose("idle")
		# Leaving the pen resets the current round (HP is kept).
		state = "idle"
		t = 0.0
		_overhead(false)
		_set_gate(false)
		foreman.visible = true
		for i in 5:
			contents[i] = "empty"
			_set_sniff(i, false)
		_toast("The Foreman resets the yard.")


func _start_fight() -> void:
	_set_gate(true)
	_toast("The Foreman's Haystacks!")
	say("OI! Right, you asked for it!", 1.6)
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("show_banner"):
		ui.call("show_banner", "The Foreman's Haystacks", "Sniff him out. Slam the stack!", 2.2)
	_whistle()


var _over_cam: Camera3D
var _prev_cam: Camera3D


## R3.1: an overhead camera holds through the whistle, dive and shuffle so every swap reads; it hands back at the window.
func _overhead(on: bool) -> void:
	if on:
		if _over_cam == null:
			_over_cam = Camera3D.new()
			_over_cam.name = "CamHint_hay_shuffle"
			_over_cam.fov = 55.0
			add_child(_over_cam)
			# Fix round 1: near-vertical (critics r1: canopies hid 3 of 5 stacks from the R3.1 (-43, 15, -37) view);
			# trees in this frustum are also rejected at dressing time (W1Dress.CAM_CLEAR).
			_over_cam.global_position = Vector3(center.x, center.y + 18.7, center.z + 4.5)
			_over_cam.look_at(center, Vector3.UP)
		var cur := get_viewport().get_camera_3d()
		if cur != _over_cam:
			_prev_cam = cur
		_over_cam.current = true
	elif _over_cam and _over_cam.current:
		if is_instance_valid(_prev_cam):
			_prev_cam.current = true


func _whistle() -> void:
	_overhead(true)
	state = "whistle"
	t = 0.0
	foreman.visible = true
	foreman.global_position = center + Vector3(0, W1Terrain.height(center.x, center.z) - center.y, 0)
	say("PHWEEEET!", 1.0)
	_pose("whistle")
	_set_bouncy(true)
	_sniff_spent = false
	_sniff_hold = 0.0
	_nervous = false


func _dive() -> void:
	state = "dive"
	t = 0.0
	var pick := _rng.randi() % 5
	var wrong: Array = ROUNDS[round_i]["wrong"]
	var k := 0
	for i in 5:
		if i == pick:
			contents[i] = "foreman"
		else:
			contents[i] = String(wrong[k % wrong.size()])
			k += 1
	var s := stacks[pick]
	_pose("burst")
	_decoy = -1
	if String(ROUNDS[round_i]["sniff"]) == "sock":
		# R3.1 sock decoy: he flings a sock into a stack-wolf stack; that stack is the only scent this round.
		_decoy = contents.find("wolf")
		if _decoy >= 0:
			say("Sniff THAT, piggy!", 1.4)
			_fling_sock(foreman.global_position + Vector3(0, 1.6, 0), stacks[_decoy])
	var tw := create_tween()
	tw.tween_property(foreman, "global_position", s.global_position + Vector3(0, 1.9, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		ObjSvc.burst(self, s.global_position + Vector3(0, 1.8, 0), Color(1.0, 0.86, 0.45), 24, 5.0, 0.2, -10.0, 0.8))


func _begin_shuffle(n: int) -> void:
	state = "shuffle"
	t = 0.0
	_swap_queue.clear()
	for i in n:
		_swap_queue.append(i)
	_swap_t = 1e9
	_swap_len = float(ROUNDS[round_i]["swap_s"])
	_next_swap()


func _next_swap() -> void:
	if _swap_queue.is_empty():
		_open_window()
		return
	_swap_queue.pop_front()
	_swap_from.clear()
	_swap_to.clear()
	var pairs := int(ROUNDS[round_i]["pairs"])
	var free_stacks: Array[int] = [0, 1, 2, 3, 4]
	for pi in pairs:
		if free_stacks.size() < 2:
			break
		var a: int = free_stacks.pop_at(_rng.randi() % free_stacks.size())
		var b: int = free_stacks.pop_at(_rng.randi() % free_stacks.size())
		_swap_from[a] = slot_of[a]
		_swap_from[b] = slot_of[b]
		_swap_to[a] = slot_of[b]
		_swap_to[b] = slot_of[a]
	_swap_t = 0.0
	ObjSvc.sfx("ui_page_flip", center)


func _shuffle_step(delta: float) -> void:
	_swap_t += delta
	var k := clampf(_swap_t / _swap_len, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	for i in _swap_from.keys():
		var a := slot_pos(int(_swap_from[i]))
		var b := slot_pos(int(_swap_to[i]))
		var mid := (a + b) * 0.5
		# Opposite half-circle arcs: offset the midpoint sideways, one stack each way.
		var side := Vector3(-(b - a).z, 0, (b - a).x).normalized() * (1.6 if int(i) % 2 == 0 else -1.6)
		var p := a.lerp(b, e) + side * sin(e * PI) * (1.0 if (b - a).length() > 0.1 else 0.0)
		p.y = W1Terrain.height(p.x, p.z)
		stacks[int(i)].global_position = p
	if k >= 1.0:
		for i in _swap_from.keys():
			slot_of[int(i)] = int(_swap_to[int(i)])
		_swap_from.clear()
		if _nervous:
			_nervous = false
			_swap_len = float(ROUNDS[round_i]["swap_s"])
			return
		_next_swap()


func _open_window() -> void:
	_overhead(false)
	state = "window"
	t = 0.0
	_guessed = false
	var first: float = ROUNDS[round_i]["sneeze_first"]
	_sneeze_t = first if _wrong < 2 else 0.8
	_set_bouncy(false)
	_sniff_hold = 0.0
	for i in 5:
		_set_sniff(i, false)
	say("", 0.1)
	if round_i == 0 and _wrong == 0:
		_toast("Which stack? Hold Sniff, then Ham Slam it!")


## The stack the scent leads to this round (-1: sniffing is spent or gives nothing).
func _scent_stack() -> int:
	if _sniff_spent:
		return -1
	if String(ROUNDS[round_i]["sniff"]) == "sock":
		return _decoy if _decoy >= 0 and contents[_decoy] == "sockwolf" else -1
	return contents.find("foreman")


## R3.1: the scent only appears after a 1.5 s held sniff; round 2's trail makes him panic and swap once.
func _sniff_step(pl: Node3D, delta: float) -> void:
	var sniffing := pl.has_method("get_state_name") and String(pl.call("get_state_name")) == "sniff"
	var target := _scent_stack()
	if not sniffing or _nervous:
		if _sniff_hold > 0.0:
			_sniff_hold = 0.0
			for i in 5:
				_set_sniff(i, false)
		return
	_sniff_hold += delta
	if _sniff_hold < SNIFF_HOLD:
		return
	if target < 0:
		if _sniff_hold - delta < SNIFF_HOLD:
			_float_text(pl.global_position + Vector3(0, 1.8, 0), "Phew! SOCK!" if _decoy >= 0 else "Achoo! Hay dust!")
		return
	_set_sniff(target, true)
	if String(ROUNDS[round_i]["sniff"]) == "nervous" and _sniff_hold > SNIFF_HOLD + 0.9:
		_nervous_swap()


func _nervous_swap() -> void:
	var i := contents.find("foreman")
	_sniff_spent = true
	_set_sniff(i, false)
	_float_text(stacks[i].global_position + Vector3(0, 2.8, 0), "Who's SNIFFING?")
	ObjSvc.burst(self, stacks[i].global_position + Vector3(0, 1.9, 0), Color(1.0, 0.86, 0.45), 16, 3.0, 0.15, -6.0, 0.6)
	var others: Array[int] = []
	for k in 5:
		if k != i:
			others.append(k)
	var j: int = others[_rng.randi() % others.size()]
	_swap_from.clear()
	_swap_to.clear()
	_swap_from[i] = slot_of[i]
	_swap_from[j] = slot_of[j]
	_swap_to[i] = slot_of[j]
	_swap_to[j] = slot_of[i]
	_swap_t = 0.0
	_swap_len = 0.9
	_nervous = true
	ObjSvc.sfx("ui_page_flip", center)


func _fling_sock(from: Vector3, s: Node3D) -> void:
	var sock := Node3D.new()
	sock.name = "Sock"
	add_child(sock)
	sock.global_position = from
	var white := K.mat(Color("f3efe6"), 0.9)
	var stripe := K.mat(Color("c8302e"), 0.8)
	K.rbox(sock, Vector3(0.18, 0.45, 0.14), white, Vector3(0, 0.1, 0), Vector3.ZERO, 0.06)
	K.rbox(sock, Vector3(0.18, 0.14, 0.3), white, Vector3(0, -0.12, 0.1), Vector3.ZERO, 0.06)
	K.rbox(sock, Vector3(0.19, 0.06, 0.15), stripe, Vector3(0, 0.25, 0), Vector3.ZERO, 0.02)
	var to := s.global_position + Vector3(0, 1.9, 0)
	var tw := sock.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(sock):
			sock.global_position = from.lerp(to, k) + Vector3(0, 3.0 * sin(k * PI), 0)
			sock.rotation.z = k * TAU * 2.0, 0.0, 1.0, 1.2)
	tw.tween_callback(func() -> void:
		var i := stacks.find(s)
		if i >= 0 and contents[i] == "wolf":
			contents[i] = "sockwolf"
		ObjSvc.burst(self, to, Color(1.0, 0.86, 0.45), 14, 3.0, 0.15, -8.0, 0.6)
		sock.queue_free())


## Before a second or third charge, a Foreman who stopped close to Mak hops back so every wind-up is readable.
func _back_off(pp: Vector3) -> void:
	var fp := foreman.global_position
	var away := Vector3(fp.x - pp.x, 0, fp.z - pp.z)
	if away.length() > 4.5:
		return
	if away.length() < 0.1:
		away = Vector3(center.x - pp.x, 0, center.z - pp.z)
	var dest := Vector3(pp.x, 0, pp.z) + away.normalized() * 5.5
	var off := Vector3(dest.x - center.x, 0, dest.z - center.z)
	if off.length() > PEN_R - 1.5:
		dest = center + off.normalized() * (PEN_R - 1.5)
	dest.y = W1Terrain.height(dest.x, dest.z)
	t = -0.45
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		foreman.global_position = fp.lerp(dest, k) + Vector3(0, 1.2 * sin(k * PI), 0), 0.0, 1.0, 0.4)


func _set_sniff(i: int, on: bool) -> void:
	if i < 0 or i >= sniffs.size() or sniffs[i] == null:
		return
	var st := sniffs[i]
	st.set("active", on)
	if on and not st.is_in_group("sniff_target"):
		st.add_to_group("sniff_target")
	elif not on and st.is_in_group("sniff_target"):
		st.remove_from_group("sniff_target")


func _set_bouncy(on: bool) -> void:
	for s in stacks:
		if on:
			s.add_to_group("bouncy")
			s.set_meta("bounce_velocity", 10.6)
		else:
			if s.is_in_group("bouncy"):
				s.remove_from_group("bouncy")


func _on_slam(_by: Node, i: int) -> void:
	if state != "window":
		return
	var c := contents[i]
	var s := stacks[i]
	ObjSvc.burst(self, s.global_position + Vector3(0, 1.9, 0), Color(1.0, 0.86, 0.45), 30, 6.0, 0.25, -12.0, 0.9)
	if c == "foreman":
		_burst(true)
		return
	contents[i] = "empty_done"
	_wrong += 1
	var was_decoy := c == "sockwolf"
	if was_decoy:
		_sniff_spent = true
		c = "wolf"
	if c == "wolf":
		var ps := load("res://scenes/enemies/WoollyWolf.tscn") as PackedScene
		if ps:
			var w := ps.instantiate() as Node3D
			if ResourceLoader.exists("res://assets/enemies/woolly_wolf_cub/woolly_wolf_cub.glb"):
				w.set("mesh_path", "res://assets/enemies/woolly_wolf_cub/woolly_wolf_cub.glb")
			w.set("notice_radius", 12.0)
			w.set("acorns_on_defeat", 2)
			get_parent().add_child(w)
			w.global_position = s.global_position + (center - s.global_position).normalized() * 1.6 + Vector3(0, 0.1, 0)
		_float_text(s.global_position + Vector3(0, 2.6, 0), "Phew! SOCK!" if was_decoy else "A stack wolf!")
	else:
		_float_text(s.global_position + Vector3(0, 2.6, 0), "Just hay!")
		# Fix round 2: acorns refill cake, so an empty stack spills a couple (the fight stays fair after a bad guess).
		ObjSvc.spawn_acorns(get_parent(), s.global_position + (center - s.global_position).normalized() * 1.6 + Vector3(0, 0.4, 0), 2)
	var fs := stacks[contents.find("foreman")]
	_float_text(fs.global_position + Vector3(0, 3.0, 0), "Cold! Freezing!")
	for k in 5:
		_set_sniff(k, false)
	_overhead(true)
	_begin_shuffle(2)


func _burst(hit: bool) -> void:
	var i := contents.find("foreman")
	_set_sniff(i, false)
	var s := stacks[i]
	foreman.visible = true
	_pose("burst")
	var from := s.global_position + Vector3(0, 1.0, 0)
	foreman.global_position = from
	# Fix round 1 (critics r1): he used to land 1.8 m inside the stack, on top of Mak, and charge at once. Now he leaps
	# to the far side of the pen from Mak (>= 5 m away) and only then winds up.
	var pl := _player()
	var mp := pl.global_position if pl else center
	var away := Vector3(center.x - mp.x, 0, center.z - mp.z)
	if away.length() < 0.5:
		away = Vector3(center.x - s.global_position.x, 0, center.z - s.global_position.z)
	var land := center + away.normalized() * 5.6
	land.y = W1Terrain.height(land.x, land.z)
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		foreman.global_position = from.lerp(land, k) + Vector3(0, 2.5 * sin(k * PI), 0), 0.0, 1.0, 0.7)
	var fd := Vector3(mp.x - land.x, 0, mp.z - land.z)
	if fd.length() > 0.1:
		foreman.rotation.y = atan2(fd.x, fd.z)
	ObjSvc.burst(self, s.global_position + Vector3(0, 1.6, 0), Color(1.0, 0.86, 0.45), 40, 7.0, 0.3, -12.0, 1.0)
	contents[i] = "empty"
	if hit:
		hp -= 1
		say("OOF! Straw in me horns!" if hp > 0 else "MY FLEECE!", 1.6)
		_toast("Foreman: %d to go" % hp if hp > 0 else "The Foreman is beaten!")
		EnemyKit.burst(self, foreman.global_position + Vector3(0, 2.0, 0), "stars", [Color(1, 0.95, 0.4)], 14, 4.0)
		ObjSvc.spawn_acorns(get_parent(), s.global_position + Vector3(0, 0.6, 0), 4)
	else:
		say("Too slow, piglet!", 1.6)
	if hp <= 0:
		state = "rest"
		t = 0.0
		return
	if hit:
		round_i = mini(round_i + 1, ROUNDS.size() - 1)
		_wrong = 0
	_charges_left = int(ROUNDS[round_i]["charges"])
	state = "charge_windup"
	t = -1.0
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if state == "charge_windup":
			_pose("windup"))


func _defeat() -> void:
	_overhead(false)
	state = "done"
	_set_gate(false)
	_set_bouncy(false)
	say("Curses! Me fleece!", 2.0)
	ObjSvc.burst(self, foreman.global_position + Vector3(0, 1.2, 0), Color(0.96, 0.93, 0.86), 40, 6.0, 0.3, -8.0, 1.0)
	# Fleece off: swap to the polka-dot underwear model for the flee.
	var uw := "res://assets/characters/foreman/foreman_underwear_v2.glb"
	if not ResourceLoader.exists(uw):
		uw = "res://assets/characters/foreman/foreman_underwear.glb"
	if ResourceLoader.exists(uw):
		var old := foreman.get_node_or_null("Model")
		if old:
			old.queue_free()
		var m2 := (load(uw) as PackedScene).instantiate() as Node3D
		m2.name = "Model2"
		m2.scale = Vector3.ONE * 1.2
		foreman.add_child(m2)
		poser = W1Poser.attach(m2)
	_pose("flee")
	var flee := Vector3(-24.0, W1Terrain.height(-24, -28), -28.0)
	var fdir := flee - foreman.global_position
	foreman.rotation.y = atan2(fdir.x, fdir.z)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(foreman, "global_position", flee, 3.0)
	tw.tween_callback(foreman.queue_free)
	spawner.call("give_reward")
	defeated.emit()


func _float_text(at: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 56
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 12
	l.modulate = Color(1, 0.95, 0.7)
	add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", at + Vector3(0, 1.0, 0), 1.2)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2)
	tw.tween_callback(l.queue_free)


## For tests and the hint system: which stack holds the Foreman right now (-1 outside a round).
func foreman_stack() -> int:
	return contents.find("foreman")
