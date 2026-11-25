class_name MakInput
extends RefCounted
## Input sampling for MakPlayer, once per physics frame.
## Reads the Input actions from Controls.gd, or a replay given with --replay=<json> (Dev.replay).
## Replay format: game/tests/README.md. Frame 0 is the player's first physics frame.

var stick := Vector2.ZERO          ## x = right, y = forward; magnitude 0..1 after dead zone and curve
var stick_mag := 0.0
var cam := Vector2.ZERO            ## right-stick or replay camera input, -1..1
var jump_pressed := false
var jump_held := false
var jump_released := false
var crouch_pressed := false
var crouch_held := false
var attack_pressed := false
var attack_held := false
var sniff_held := false
var cam_center_pressed := false
var interact_pressed := false

var replay_active := false
var steer_world := false           ## replay "steer": "world" makes stick up = world -Z, right = +X
var end_frame := -1
var start: Dictionary = {}
var teleport: Dictionary = {}      ## set for one frame when a replay teleport event fires
var mark := ""                     ## set for one frame when a replay mark event fires
var call_request := ""             ## replay "call" event (allow-listed in MakPlayer), one frame
var frame := 0

var _events: Array = []
var _event_i := 0
var _reactive: Array = []          ## replay events with "on": fire relative to a notified tag
var _tag_counts := {}
var _held := {}                    ## replay: action -> true
var _hold_frames := {}             ## replay: action -> frames left
var _prev := {}
var _r_stick := Vector2.ZERO
var _r_cam := Vector2.ZERO
var _deadzone := 0.2
var _curve := 1.0

const ACTIONS := ["jump", "crouch", "attack", "sniff", "cam_center", "interact"]


func setup(replay: Dictionary, deadzone: float, curve: float) -> void:
	_deadzone = deadzone
	_curve = curve
	if replay.is_empty():
		return
	replay_active = true
	steer_world = str(replay.get("steer", "world")) == "world"
	end_frame = int(replay.get("end_frame", -1))
	var st: Variant = replay.get("start", {})
	if st is Dictionary:
		start = st
	var fps := float(replay.get("fps", 60))
	var evs: Variant = replay.get("events", [])
	if evs is Array:
		for e in evs:
			if e is Dictionary:
				var ev: Dictionary = (e as Dictionary).duplicate()
				if ev.has("on"):
					_reactive.append(ev)
					continue
				if not ev.has("f") and ev.has("t"):
					ev["f"] = int(round(float(ev["t"]) * fps))
				ev["f"] = int(ev.get("f", 0))
				_events.append(ev)
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["f"]) < int(b["f"]))


## Reactive replay events: {"on": "<tag>", "nth": 1, "delay": 0, ...action...} fire "delay" frames
## after the nth notification of the tag. Tags: "land", "state:<name>", "jump:<kind>".
func notify(tag: String) -> void:
	if _reactive.is_empty():
		return
	var n := int(_tag_counts.get(tag, 0)) + 1
	_tag_counts[tag] = n
	for e in _reactive:
		var ev: Dictionary = e
		if str(ev["on"]) == tag and int(ev.get("nth", 1)) == n:
			var copy := ev.duplicate()
			copy.erase("on")
			copy["f"] = frame + int(ev.get("delay", 0))
			_events.insert(_event_i, copy)
			_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["f"]) < int(b["f"]))


func sample(blocked: bool = false) -> void:
	## blocked: the UI owns the input (UI.is_input_blocked()); live input reads as neutral, and the
	## held state is still tracked so a button held to close a dialog does not fire on release of the block.
	teleport = {}
	mark = ""
	call_request = ""
	var held := {}
	if replay_active:
		_apply_events()
		for a in ACTIONS:
			held[a] = bool(_held.get(a, false)) or int(_hold_frames.get(a, 0)) > 0
		for a in _hold_frames.keys():
			_hold_frames[a] = int(_hold_frames[a]) - 1
		_set_stick(_r_stick)
		cam = _r_cam
	else:
		for a in ACTIONS:
			held[a] = InputMap.has_action(a) and Input.is_action_pressed(a)
		var v := Vector2.ZERO
		if InputMap.has_action("move_left"):
			v = Input.get_vector("move_left", "move_right", "move_back", "move_forward", 0.0)
		_set_stick(v)
		cam = Vector2.ZERO
		if InputMap.has_action("cam_left"):
			cam = Input.get_vector("cam_left", "cam_right", "cam_down", "cam_up", 0.15)
	if blocked and not replay_active:
		_prev = held
		for a in ACTIONS:
			held[a] = false
		_set_stick(Vector2.ZERO)
		cam = Vector2.ZERO
		jump_held = false
		crouch_held = false
		attack_held = false
		sniff_held = false
		jump_pressed = false
		jump_released = false
		crouch_pressed = false
		attack_pressed = false
		cam_center_pressed = false
		interact_pressed = false
		frame += 1
		return
	jump_held = held["jump"]
	crouch_held = held["crouch"]
	attack_held = held["attack"]
	sniff_held = held["sniff"]
	jump_pressed = jump_held and not bool(_prev.get("jump", false))
	jump_released = (not jump_held) and bool(_prev.get("jump", false))
	crouch_pressed = crouch_held and not bool(_prev.get("crouch", false))
	attack_pressed = attack_held and not bool(_prev.get("attack", false))
	cam_center_pressed = held["cam_center"] and not bool(_prev.get("cam_center", false))
	interact_pressed = held["interact"] and not bool(_prev.get("interact", false))
	if not replay_active:
		# Catch presses shorter than one physics frame.
		if Input.is_action_just_pressed("jump"):
			jump_pressed = true
		if Input.is_action_just_pressed("attack"):
			attack_pressed = true
		if Input.is_action_just_pressed("crouch"):
			crouch_pressed = true
	_prev = held
	frame += 1


func _set_stick(raw: Vector2) -> void:
	var m := raw.length()
	if m <= _deadzone:
		stick = Vector2.ZERO
		stick_mag = 0.0
		return
	var remapped := clampf((m - _deadzone) / (1.0 - _deadzone), 0.0, 1.0)
	remapped = pow(remapped, _curve)
	stick = raw / m * remapped
	stick_mag = remapped


func _apply_events() -> void:
	while _event_i < _events.size() and int(_events[_event_i]["f"]) <= frame:
		var e: Dictionary = _events[_event_i]
		_event_i += 1
		if e.has("stick"):
			var s: Array = e["stick"]
			_r_stick = Vector2(float(s[0]), float(s[1]))
		if e.has("cam"):
			var c: Array = e["cam"]
			_r_cam = Vector2(float(c[0]), float(c[1]))
		if e.has("press"):
			_held[str(e["press"])] = true
		if e.has("release"):
			_held[str(e["release"])] = false
			_hold_frames[str(e["release"])] = 0
		if e.has("tap"):
			_hold_frames[str(e["tap"])] = 1
		if e.has("hold"):
			_hold_frames[str(e["hold"])] = int(e.get("frames", 1))
		if e.has("teleport"):
			var p: Array = e["teleport"]
			teleport = {"pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "yaw_deg": float(e.get("yaw_deg", 0.0))}
		if e.has("mark"):
			mark = str(e["mark"])
		if e.has("call"):
			call_request = str(e["call"])
		if e.has("end"):
			end_frame = frame
