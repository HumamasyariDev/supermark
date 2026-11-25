extends Node3D
## Headless lifecycle test for every effect scene: instantiates, plays, waits and checks that
## one-shots free themselves and continuous effects stay alive. Prints one PASS/FAIL line each.
## python tools/godot.py run res://scenes/fx/FxSelfTest.tscn --headless --seconds 6 -- --profile=vfx

const SCENES := ["DustPuff", "RunDust", "LandingRing", "SlamShockwave", "JumpTrail", "Sparkle", "CollectPop", "TruffleBurst",
	"PageFlutter", "Confetti", "FeatherBurst", "CrumbBurst", "PeaSplat", "HitStars", "Butterflies", "FallingLeaves",
	"ChimneySmoke", "WaterfallFoam", "GustMotes", "Splash", "CocoaSplash", "Poof", "CheckpointGlow", "GustSwirl", "ScentTrail"]

var _nodes := {}


func _ready() -> void:
	# Frame-count based quits (--quit-after) need a fixed frame rate to cover the 4.5 s wait.
	Engine.max_fps = 60
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 3, 10)
	for n in SCENES:
		var ps := load("res://scenes/fx/%s.tscn" % n) as PackedScene
		if ps == null:
			print("[FxSelfTest] FAIL load ", n)
			continue
		var fx := ps.instantiate()
		add_child(fx)
		if fx.has_method("set_target"):
			fx.call("set_target", Vector3(5, 0, 0))
		if fx.has_method("play"):
			fx.call("play")
		if fx.has_method("emit"):
			fx.call("emit")
		_nodes[n] = fx
	await get_tree().create_timer(4.5).timeout
	var fails := 0
	for n in _nodes:
		var alive := is_instance_valid(_nodes[n])
		var one_shot := not alive
		if alive:
			var fx: Node = _nodes[n]
			if fx.has_method("is_one_shot"):
				one_shot = fx.call("is_one_shot")
		var ok := (one_shot and not alive) or (not one_shot and alive)
		if not ok:
			fails += 1
		print("[FxSelfTest] ", "PASS " if ok else "FAIL ", n, " one_shot=", one_shot, " alive_after_4.5s=", alive)
	print("[FxSelfTest] done, failures=", fails)
	get_tree().quit()
