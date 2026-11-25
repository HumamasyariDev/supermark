class_name TimeTrial
extends TruffleSpawner
## Time trial: children "StartGate" and "FinishGate" (Area3D or any node with an Area3D) and rings under "Rings"
## (TrialRing nodes, passed in any order unless `ordered`). Starting shows a HUD timer through the UI autoload
## (UI.timer_start(label, countdown) / UI.timer_stop() / UI.timer_hide()); success records the time with
## Game.record_time(trial_key, seconds) and spawns the truffle; failure resets.

signal started
signal succeeded(time: float)
signal failed(reason: String)

@export var time_limit: float = 30.0
@export var ordered: bool = false
@export var gate_color: Color = Color(1.0, 0.76, 0.22)
@export var trial_label: String = "Time Trial"
## Key for Game.record_time (defaults to the reward truffle id).
@export var trial_key: String = ""

var running := false
var elapsed := 0.0
var _rings: Array[Node] = []
var _next := 0
var _start: Area3D
var _finish: Area3D
var _finish_serial := 0


func _ready() -> void:
	super._ready()
	add_to_group("time_trial")
	_start = _gate("StartGate", Color(0.4, 0.85, 0.45), "START")
	_finish = _gate("FinishGate", Color(0.95, 0.35, 0.3), "FINISH")
	_start.body_entered.connect(func(b: Node) -> void:
		if ObjSvc.is_player(b) and not running:
			start())
	_finish.body_entered.connect(func(b: Node) -> void:
		if ObjSvc.is_player(b) and running:
			_try_finish())
	var rings := get_node_or_null("Rings")
	if rings:
		for r in rings.get_children():
			if r.has_signal("passed"):
				_rings.append(r)
				r.connect("passed", _on_ring_passed)
	_set_rings_active(false)
	# A fall-out or checkpoint respawn mid-trial fails it (back to the start gate), so the countdown never expires
	# somewhere else (critique objects r1).
	var game := ObjSvc.autoload("Game")
	if game != null and game.has_signal("player_respawned"):
		game.connect("player_respawned", func() -> void:
			if running:
				_fail("fell"))


## Leaving the world mid-trial must not leave a countdown running in the hub.
func _exit_tree() -> void:
	if running:
		running = false
		ObjSvc.call_on("UI", "timer_hide")


## Builds a gate placeholder (two posts and a banner) around an existing marker or Area3D child.
func _gate(n: String, col: Color, text: String) -> Area3D:
	var node := get_node_or_null(n) as Node3D
	var area: Area3D = node as Area3D
	if area == null:
		area = Area3D.new()
		area.name = n + "Area"
		if node == null:
			node = Node3D.new()
			node.name = n
			add_child(node)
		node.add_child(area)
	area.collision_layer = ObjSvc.L_TRIGGER
	area.collision_mask = ObjSvc.L_PLAYER
	if area.get_child_count() == 0 or area.get_node_or_null("Shape") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		cs.shape = ObjSvc.box_shape(Vector3(3.6, 3.0, 0.8))
		cs.position = Vector3(0, 1.5, 0)
		area.add_child(cs)
	var v := Node3D.new()
	v.name = "GateVisual"
	area.add_child(v)
	var post := ObjSvc.mat(Color(0.98, 0.95, 0.88), 0.5)
	var c := ObjSvc.mat(col, 0.5, 0.0, col, 0.25)
	for sx in [-1.0, 1.0]:
		ObjSvc.cylinder(v, 0.1, 0.12, 3.2, post, Vector3(sx * 1.9, 1.6, 0))
		ObjSvc.sphere(v, 0.18, c, Vector3(sx * 1.9, 3.25, 0))
	ObjSvc.soft_box(v, Vector3(3.6, 0.55, 0.08), c, Vector3(0, 2.85, 0), Vector3.ZERO, 0.04)
	var l := ObjSvc.label(v, text, Vector3(0, 2.85, -0.06), 80, Color.WHITE, false)
	l.rotation_degrees = Vector3(0, 180, 0)
	var l2 := ObjSvc.label(v, text, Vector3(0, 2.85, 0.06), 80, Color.WHITE, false)
	l2.outline_size = 12
	return area


func start() -> void:
	_finish_serial += 1
	running = true
	elapsed = 0.0
	_next = 0
	for r in _rings:
		if r.has_method("reset"):
			r.call("reset")
	_set_rings_active(true)
	ObjSvc.feedback("object_trial_start", global_position, {}, "trial_start")
	ObjSvc.call_on("UI", "timer_start", [trial_label, time_limit])
	started.emit()


func _set_rings_active(on: bool) -> void:
	for i in _rings.size():
		var r := _rings[i]
		if r.has_method("set_active"):
			r.call("set_active", on and (not ordered or i == _next))


func _on_ring_passed(ring: Node) -> void:
	if not running:
		return
	var idx := _rings.find(ring)
	if ordered and idx != _next:
		return
	_next += 1
	if ordered:
		_set_rings_active(true)


func rings_passed() -> int:
	var n := 0
	for r in _rings:
		if bool(r.get("is_passed")):
			n += 1
	return n


func _try_finish() -> void:
	if rings_passed() < _rings.size():
		ObjSvc.show_dialog(["You missed %d ring%s! Back to the start gate." % [_rings.size() - rings_passed(), "" if _rings.size() - rings_passed() == 1 else "s"]], "")
		_fail("missed_rings")
		return
	running = false
	_set_rings_active(false)
	ObjSvc.call_on("UI", "timer_stop")
	# The frozen time flashes for a 2.5 s flourish, then the timer leaves the HUD (the timer also runs during the
	# truffle pause). A trial restarted in the meantime keeps its timer.
	_finish_serial += 1
	var serial := _finish_serial
	# A node-owned tween (dies with the trial, so no freed-capture errors on scene change) that also runs while the
	# tree is paused for the truffle splash.
	var ht := create_tween()
	ht.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	ht.tween_interval(2.5)
	ht.tween_callback(func() -> void:
		if not running and serial == _finish_serial:
			ObjSvc.call_on("UI", "timer_hide"))
	ObjSvc.call_on("Game", "record_time", [trial_key if trial_key != "" else reward_truffle_id, elapsed])
	ObjSvc.feedback("object_trial_complete", global_position, {}, "trial_success")
	succeeded.emit(elapsed)
	give_reward()


func _fail(reason: String) -> void:
	running = false
	ObjSvc.call_on("UI", "timer_hide")
	ObjSvc.feedback("object_trial_fail", global_position, {}, "trial_fail")
	for r in _rings:
		if r.has_method("reset"):
			r.call("reset")
	_set_rings_active(false)
	failed.emit(reason)


func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if elapsed >= time_limit:
		_fail("timeout")
