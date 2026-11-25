extends Node3D
## Look-dev lab for the wolf's procedural recipes (not gameplay). Lays out one WolfRig per state.
## Dev arg --poses=a,b,c picks the states; --t=<seconds> freezes the recipe time.

const DEFAULT := ["sip", "inhale", "huff", "pant", "charge", "stuck", "spin", "hurt", "swell", "paw"]

var rigs: Array = []
var states: Array = []
var _t := 0.0
var _freeze := -1.0


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	states = DEFAULT.duplicate()
	if dev != null and dev.call("has_arg", "poses"):
		states = String(dev.call("arg", "poses", "")).split(",")
	if dev != null and dev.call("has_arg", "t"):
		_freeze = float(dev.call("arg", "t", "1.0"))
	if ClassDB.class_exists("Node") and ResourceLoader.exists("res://scripts/fx/fx_environments.gd"):
		FxEnvironments.apply(self, "BOSS")
	var n := states.size()
	for i in n:
		var r := WolfRig.new()
		add_child(r)
		r.position = Vector3((float(i) - float(n - 1) * 0.5) * 3.6, 0, 0)
		r.rotation.y = PI
		rigs.append(r)
		var l := Label3D.new()
		l.text = String(states[i])
		l.font_size = 64
		l.outline_size = 12
		l.position = r.position + Vector3(0, -0.4, 1.6)
		l.rotation_degrees.x = -30
		add_child(l)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 20)
	floor_mi.mesh = pm
	floor_mi.material_override = EnemyKit.mat(Color(0.7, 0.64, 0.64))
	add_child(floor_mi)


func _process(delta: float) -> void:
	_t += delta
	var t := _freeze if _freeze >= 0.0 else _t
	for i in rigs.size():
		var r: WolfRig = rigs[i]
		r.begin()
		WolfRecipes.apply(r, String(states[i]), t, {"k": 1.0} if String(states[i]) in ["inhale", "swell"] else {})
		r.update(delta if _freeze < 0.0 else 1.0)
