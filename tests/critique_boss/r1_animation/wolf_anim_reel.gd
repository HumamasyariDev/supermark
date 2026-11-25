extends Node3D
## Critique BOSS r1 (animation lens): plays every wolf recipe in fight order on one WolfRig, with the
## same root motion, kicks and flashes wolf_boss.gd applies, so the performance can be judged up close
## and at gameplay distance. Not shipped. Dev args: --view=close|far|side, --quit-at=<s>.

const SEQ := [
	["sip", 3.0], ["sneer", 2.0], ["inhale", 1.2], ["huff", 1.4], ["head_turn", 0.5], ["huff", 1.2],
	["hop", 1.0], ["pant", 3.0], ["hurt", 2.0], ["hop", 1.2], ["paw", 1.2], ["charge", 1.2],
	["stuck", 3.0], ["pull_free", 1.0], ["feint*", 1.0], ["teeter", 2.5], ["dangle*", 2.0], ["dizzy", 1.8],
	["soot_tumble*", 1.6], ["trot", 1.5], ["spin", 2.0], ["look_up", 0.6], ["cough", 2.0],
	["swell", 1.2], ["wedged", 2.5], ["float_away", 2.0],
]

var rig: WolfRig
var cam: Camera3D
var label: Label
var _i := -1
var _st := 0.0
var _clock := 0.0
var _quit_at := 70.0


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	var view := "close"
	if dev != null and dev.call("has_arg", "view"):
		view = String(dev.call("arg", "view", "close"))
	if dev != null and dev.call("has_arg", "quit-at"):
		_quit_at = float(dev.call("arg", "quit-at", "70"))
	var we := WorldEnvironment.new()
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	FxEnvironments.apply(self, "BOSS", false)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	floor_mi.material_override = EnemyKit.mat(Color(0.78, 0.66, 0.68))
	add_child(floor_mi)
	rig = WolfRig.new()
	add_child(rig)
	rig.rotation.y = PI
	rig.set_layers(3)
	cam = Camera3D.new()
	add_child(cam)
	match view:
		"far":
			# Roughly BossFraming distance: Mak about 10-14 m from the wolf, camera 6.5 m behind Mak.
			cam.fov = 60.0
			cam.position = Vector3(3.0, 6.0, 17.0)
			cam.look_at(Vector3(0, 1.4, 0))
		"side":
			cam.fov = 40.0
			cam.position = Vector3(6.5, 2.0, 0.0)
			cam.look_at(Vector3(0, 1.6, 0))
		_:
			cam.fov = 40.0
			cam.position = Vector3(2.6, 2.3, 5.2)
			cam.look_at(Vector3(0, 1.7, 0))
	cam.current = true
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 10)
	cl.add_child(label)
	_next()


func _next() -> void:
	_i += 1
	_st = 0.0
	rig.position = Vector3.ZERO
	rig.rotation = Vector3(0, PI, 0)
	if _i >= SEQ.size():
		_i = 0
	var s: String = SEQ[_i][0]
	if s == "hurt":
		rig.flash(Color(1, 1, 1))
		rig.kick(0.7)
	if s == "stuck":
		rig.kick(0.5)
	if s == "huff":
		rig.kick(-0.25)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock >= _quit_at:
		get_tree().quit()
		return
	_st += delta
	var s: String = SEQ[_i][0]
	var dur: float = SEQ[_i][1]
	var anim := s
	var t := _st
	var p := {}
	match s:
		"inhale":
			p = {"k": clampf(_st / dur, 0.0, 1.0)}
		"huff":
			p = {"dur": dur, "t": _st, "yaw": 0.0}
		"head_turn":
			p = {"yaw": 0.8}
		"hop":
			var k := clampf(_st / dur, 0.0, 1.0)
			p = {"k": k}
			rig.position.y = sin(PI * k) * 1.4
			if k >= 1.0 and _st - delta < dur:
				rig.kick(0.55)
		"hurt":
			rig.position.y = sin(PI * clampf(_st / 0.9, 0.0, 1.0)) * 1.6
		"trot":
			p = {"speed": 6.0, "phase": _st * 9.0}
		"feint*":
			# wolf_boss.gd: anim = "teeter" if st < 0.3 else "paw"
			anim = "teeter" if _st < 0.3 else "paw"
		"dangle*":
			# wolf_boss.gd uses the hurt recipe while hanging 1.6 m below the lip.
			anim = "hurt"
			rig.position.y = -1.6 + clampf((_st - 1.4) / 0.6, 0.0, 1.0) * 1.6
		"soot_tumble*":
			var k2 := clampf(_st / 0.6, 0.0, 1.0)
			if k2 < 1.0:
				anim = "hurt"
				rig.position = Vector3(0, sin(PI * k2) * 1.5, -k2 * 3.0)
				rig.rotation.x = -k2 * TAU * 1.5
			else:
				anim = "dizzy"
				rig.rotation.x = 0.0
				rig.position = Vector3(0, 0, -3.0)
		"spin":
			rig.rotation.y = PI + _st * 9.4
		"swell":
			p = {"k": clampf(_st / dur, 0.0, 1.0)}
		"wedged":
			var b := 0.0
			if fmod(_st, 1.2) < 0.15:
				b = 1.0
			p = {"boing": b}
		"float_away":
			rig.rotation.z += 0.0
			rig.rotation = Vector3(0, PI, _st * TAU * 2.0)
			rig.position.y = _st * 1.2
			p = {"t": 0.0}
			t = 0.0
	rig.begin()
	WolfRecipes.apply(rig, anim, t, p)
	rig.update(delta)
	label.text = "%s  %.1f / %.1f s   (clock %.1f)" % [s, _st, dur, _clock]
	if _st >= dur:
		_next()
