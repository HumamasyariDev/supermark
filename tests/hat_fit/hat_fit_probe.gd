extends Node3D
## Hat fit probe (test tool only): the real MakPlayer (hero v2) with each hat, head close-ups from front, 3/4,
## side, back, above (gameplay camera height) and below, plus run frames and a hat-tilt-relative-to-head metric.
##
##   python tools/godot.py run res://tests/hat_fit/HatFitProbe.tscn --seconds 90 -- --out=C:/abs/dir \
##       [--hats=top_hat,golden_top_hat,beanie] [--prefix=before_] [--views=front,3q,side,back,above,low] [--run-frames=8]
## Writes <prefix><hat>__<view>.png, <prefix><hat>__run_<n>.png and <prefix>metrics.json (hat pitch/roll vs head).

const GoldenHatLib := preload("res://scripts/objects/golden_hat.gd")
const DT := 1.0 / 60.0
## Camera offsets from the head centre (Mak faces -Z here).
const VIEWS := {
	"front": Vector3(0.0, 0.05, -1.45),
	"3q": Vector3(1.0, 0.15, -1.05),
	"side": Vector3(1.45, 0.05, 0.0),
	"back": Vector3(0.0, 0.12, 1.45),
	"3qb": Vector3(-1.0, 0.2, 1.05),
	"above": Vector3(0.75, 1.05, -0.95),
	"above_back": Vector3(0.35, 1.15, 1.2),
	"low": Vector3(0.25, -0.45, -1.35),
}

var player: Node3D
var anim: Node
var skel: Skeleton3D
var cam: Camera3D
var _dev: Node
var _out := ""
var _metrics := {}


func _ready() -> void:
	_dev = get_tree().root.get_node_or_null("Dev")
	_build_stage()
	player = (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Node3D
	add_child(player)
	player.set_physics_process(false)
	var pc := player.get_node_or_null("MakCamera")
	if pc != null:
		pc.process_mode = Node.PROCESS_MODE_DISABLED
	anim = player.get_node("Animator")
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	_out = _arg("out")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://hat_fit")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _arg(k: String) -> String:
	if _dev != null and _dev.has_method("arg"):
		return str(_dev.call("arg", k, ""))
	return ""


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var env_path := "res://assets/shaders/environments/env_W1.tres"
	if ResourceLoader.exists(env_path):
		we.environment = load(env_path)
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.72, 0.42)
	ground.material_override = gm
	add_child(ground)


func _head_centre() -> Vector3:
	var hi := skel.find_bone("head")
	var ti := skel.find_bone("head_top")
	var h := skel.global_transform * skel.get_bone_global_pose(hi).origin
	var t := skel.global_transform * skel.get_bone_global_pose(ti).origin
	return h.lerp(t, 0.55)


func _shoot(name: String, view: String) -> void:
	var c := _head_centre()
	var off: Vector3 = VIEWS.get(view, VIEWS["3q"])
	cam.global_position = c + off * 1.75
	cam.look_at(c, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(path)
	print("[HatFit] saved ", path)


## Hat socket orientation relative to the head bone, minus the rest offset: (pitch, yaw, roll) in degrees.
func _hat_rel_deg() -> Vector3:
	var hi := skel.find_bone("head")
	var ti := skel.find_bone("head_top")
	var rest_rel := skel.get_bone_global_rest(hi).basis.orthonormalized().inverse() * skel.get_bone_global_rest(ti).basis.orthonormalized()
	var rel := skel.get_bone_global_pose(hi).basis.orthonormalized().inverse() * skel.get_bone_global_pose(ti).basis.orthonormalized()
	var d := (rest_rel.inverse() * rel).get_euler()
	return Vector3(rad_to_deg(d.x), rad_to_deg(d.y), rad_to_deg(d.z))


func _set_state(st: String, speed: float) -> void:
	player.set("state", st)
	player.set("velocity", Vector3(0, 0, -speed))
	player.set("vy", 0.0)
	player.set("forward_speed", speed)
	player.set("grounded", true)


func _wear(id: String) -> void:
	player.call("set_hat", id)
	var parts: Variant = player.get("v2_parts")
	if parts is Dictionary and (parts as Dictionary).has("top_hat"):
		GoldenHatLib.gild((parts as Dictionary)["top_hat"], GoldenHatLib.is_golden(id))
	for i in 40:
		anim.call("_process", DT)


func _run() -> void:
	anim.set_process(false)
	skel = player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		for n in player.find_children("*", "Skeleton3D", true, false):
			skel = n as Skeleton3D
			break
	var hats := _arg("hats").split(",", false)
	if hats.is_empty():
		hats = PackedStringArray(["top_hat", "golden_top_hat", "beanie"])
	var views := _arg("views").split(",", false)
	if views.is_empty():
		views = PackedStringArray(["front", "3q", "side", "back", "above", "low"])
	var prefix := _arg("prefix")
	var run_frames := int(_arg("run-frames")) if _arg("run-frames") != "" else 8
	for h in hats:
		# Neutral stance: idle, early in the state (no idle beat yet).
		_set_state("idle", 0.0)
		_wear(h)
		_set_state("idle", 0.0)
		for i in 20:
			anim.call("_process", DT)
		for v in views:
			await _shoot("%s%s__%s" % [prefix, h, v], v)
		# Run: 2 s at 7.5 m/s for the metric, then frames every 5 ticks from the 3/4 view.
		_set_state("walk", 7.5)
		var pitch := []
		var roll := []
		for i in 120:
			anim.call("_process", DT)
			var r := _hat_rel_deg()
			pitch.append(r.x)
			roll.append(r.z)
		var mx_p := 0.0
		var mx_r := 0.0
		for p in pitch:
			mx_p = maxf(mx_p, absf(float(p)))
		for r in roll:
			mx_r = maxf(mx_r, absf(float(r)))
		_metrics[h] = {"run_hat_pitch_max_deg": snappedf(mx_p, 0.01), "run_hat_roll_max_deg": snappedf(mx_r, 0.01),
			"run_hat_pitch_min_deg": snappedf(pitch.min(), 0.01), "run_hat_pitch_max_signed_deg": snappedf(pitch.max(), 0.01)}
		print("[HatFit] ", h, " ", _metrics[h])
		for f in run_frames:
			for i in 5:
				anim.call("_process", DT)
			await _shoot("%s%s__run_%d" % [prefix, h, f], "3q" if f % 2 == 0 else "above")
	var fa := FileAccess.open(_out.path_join(prefix + "metrics.json"), FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(_metrics, "  "))
		fa.close()
	get_tree().quit()
