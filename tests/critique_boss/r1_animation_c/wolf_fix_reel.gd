extends Node3D
## Critique BOSS r1 animation, third pass (04:55 UTC): plays the recipes the boss fix round rebuilt
## (cane guard, hurt head/tail, feint, dangle, tumble, spin, swell, wedged) with the boss's root motion,
## plus a jaw-only probe (+0.8 / -0.8 rad) in a face close-up. Not shipped. --view=close|far

const SEQ := [
	["inhale_guard", 1.4], ["cane_guard", 0.9], ["hurt_head", 1.3], ["hurt_tail", 1.3], ["feint", 1.4],
	["dangle", 2.0], ["tumble", 1.2], ["spin", 1.4], ["swell", 1.6], ["wedged", 2.0],
	["jaw_plus", 1.0], ["jaw_minus", 1.0],
]

var rig: WolfRig
var cam: Camera3D
var label: Label
var _i := -1
var _st := 0.0
var _far := false


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	if dev != null and dev.call("has_arg", "view"):
		_far = String(dev.call("arg", "view", "close")) == "far"
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
	rig.set_layers(3)
	FxToon.apply(rig, {"rim": 0.45, "outline_width": 1.3})
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 10)
	cl.add_child(label)
	_next()


func _set_cam(face: bool) -> void:
	if face:
		var h := rig.bone_world("head")
		cam.fov = 30.0
		cam.position = h + Vector3(1.0, 0.25, 2.2)
		cam.look_at(h + Vector3(0, -0.05, 0.25))
	elif _far:
		cam.fov = 60.0
		cam.position = Vector3(3.0, 6.0, 17.0)
		cam.look_at(Vector3(0, 1.4, 0))
	else:
		cam.fov = 40.0
		cam.position = Vector3(2.6, 2.4, 6.0)
		cam.look_at(Vector3(0, 1.8, 0))


func _next() -> void:
	_i += 1
	if _i >= SEQ.size():
		get_tree().quit()
		return
	_st = 0.0
	rig.position = Vector3.ZERO
	rig.rotation = Vector3(0, PI, 0)
	var s: String = SEQ[_i][0]
	if s.begins_with("hurt"):
		rig.flash(Color(1, 1, 1))
		rig.kick(0.7)
	_set_cam(s.begins_with("jaw"))


func _physics_process(delta: float) -> void:
	_st += delta
	var s: String = SEQ[_i][0]
	var dur: float = SEQ[_i][1]
	var recipe := s
	var p := {}
	match s:
		"inhale_guard":
			recipe = "inhale"
			p = {"k": clampf(_st / dur, 0.0, 1.0), "guard": true}
		"hurt_head":
			recipe = "hurt"
			p = {"where": "head"}
		"hurt_tail":
			recipe = "hurt"
			p = {"where": "tail"}
		"tumble":
			rig.rotation.x = -_st * 7.0
			rig.position = Vector3(0, sin(PI * clampf(_st / dur, 0.0, 1.0)) * 1.8 + 1.0, _st * 2.0)
		"dangle":
			rig.position.y = -1.6
		"spin":
			rig.rotation.y = PI + _st * 9.4
		"swell":
			p = {"k": clampf(_st / 1.2, 0.0, 1.0)}
		"wedged":
			p = {"boing": 1.0 if fmod(_st, 1.0) < 0.15 else 0.0}
		"jaw_plus", "jaw_minus":
			recipe = "sneer"
	rig.begin()
	WolfRecipes.apply(rig, recipe, _st, p)
	if s == "jaw_plus":
		rig.pose("jaw", Vector3(0.8, 0, 0))
	elif s == "jaw_minus":
		rig.pose("jaw", Vector3(-0.8, 0, 0))
	rig.update(delta)
	label.text = "%s  %.1f / %.1f s" % [s, _st, dur]
	if _st >= dur:
		_next()
