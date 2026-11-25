extends Node3D
## Critique BOSS r1 (animation lens): one BossCrow through perch, cackle, flap-up, take-off, orbit,
## dive wind-up, dive, dazed recover and the defeat, at close range. Not shipped.

var crow: BossCrow
var cam: Camera3D
var label: Label
var _clock := 0.0
var _done := {}


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
	var perch := StaticBody3D.new()
	add_child(perch)
	EnemyKit.box(perch, Vector3(2.0, 0.8, 0.8), Color(0.64, 0.27, 0.18), Vector3(0, 0.4, 0))
	crow = BossCrow.new()
	crow.perch = Vector3(0, 0.8, 0)
	crow.perch_yaw = PI
	crow.orbit_r = 3.5
	crow.orbit_y = 3.0
	add_child(crow)
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	cam.position = Vector3(2.2, 2.4, 6.5)
	cam.look_at(Vector3(0, 1.4, 0))
	cam.current = true
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 10)
	cl.add_child(label)


func _once(key: String, at: float) -> bool:
	if _clock >= at and not _done.has(key):
		_done[key] = true
		return true
	return false


func _physics_process(delta: float) -> void:
	_clock += delta
	if _once("cackle", 1.5):
		crow.cackle()
	if _once("flap", 3.5):
		crow.flap_up()
	if _once("off", 7.0):
		crow.take_off()
	if _once("dive", 11.0):
		crow.dive_at(Vector3(0, 0, 1.5))
	if _once("hit", 13.2):
		crow.weak_hit("crow", "punch", crow.global_position + Vector3(0, 0, 1.5))
	if _clock > 16.0:
		get_tree().quit()
	label.text = "crow mode=%s  t=%.1f  (clock %.1f)" % [crow.mode if is_instance_valid(crow) else "freed", crow.t if is_instance_valid(crow) else 0.0, _clock]
