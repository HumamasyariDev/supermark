extends Node3D
## Critique BOSS r1 animation (re-check 04:00 UTC): the key problem states on a WolfRig with the
## shipped FxToon look (wolf_boss.gd now applies it), close 3/4 camera. Not shipped.

const SEQ := [["huff", 1.6], ["pant", 2.0], ["hurt", 2.0], ["spin", 1.2], ["swell", 1.2], ["wedged", 2.0]]

var rig: WolfRig
var label: Label
var _i := -1
var _st := 0.0


func _ready() -> void:
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
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	cam.position = Vector3(2.4, 2.6, 5.6)
	cam.look_at(Vector3(0, 1.9, 0))
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


func _next() -> void:
	_i = (_i + 1) % SEQ.size()
	_st = 0.0
	rig.position = Vector3.ZERO
	rig.rotation = Vector3(0, PI, 0)
	var s: String = SEQ[_i][0]
	if s == "hurt":
		rig.flash(Color(1, 1, 1))
		rig.kick(0.7)
	if s == "huff":
		rig.kick(-0.25)


func _physics_process(delta: float) -> void:
	_st += delta
	var s: String = SEQ[_i][0]
	var dur: float = SEQ[_i][1]
	var p := {}
	match s:
		"huff":
			p = {"dur": dur, "t": _st, "yaw": 0.0}
		"hurt":
			rig.position.y = sin(PI * clampf(_st / 0.9, 0.0, 1.0)) * 1.6
		"spin":
			rig.rotation.y = PI + _st * 9.4
		"swell":
			p = {"k": clampf(_st / dur, 0.0, 1.0)}
		"wedged":
			p = {"boing": 1.0 if fmod(_st, 1.2) < 0.15 else 0.0}
	rig.begin()
	WolfRecipes.apply(rig, s, _st, p)
	rig.update(delta)
	label.text = "%s  %.1f / %.1f s" % [s, _st, dur]
	if _st >= dur:
		_next()
