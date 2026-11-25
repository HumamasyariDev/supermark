extends Node
## Read-only verification of Juice effects and ambient drop-ins inside the real worlds, through the real gameplay
## camera. Loads the world as the current scene (nothing is saved), drops the world's ambient effects in front of
## Mak the way a world builder would, fires representative events and saves native frames.
##   python tools/godot.py run res://scenes/fx/JuiceWorldProbe.tscn --seconds 90 -- --world=W1 --out=<abs dir> --profile=juice
## Worlds: HUB, W1, W2, W3, BOSS. Files: <out>/<world>_<nn>_<label>.png. Quits when done.

const WORLDS := {
	"HUB": "res://scenes/hub/Hub.tscn",
	"W1": "res://scenes/worlds/w1/W1.tscn",
	"W2": "res://scenes/worlds/w2/W2.tscn",
	"W3": "res://scenes/worlds/w3/W3.tscn",
	"BOSS": "res://scenes/boss/WolfRooftop.tscn",
}
const AMBIENT := {
	"HUB": [["ambient/Fireflies", Vector3(0, 1.0, 5), Vector3(6, 1.5, 5)], ["ambient/DustMotes", Vector3(1.5, 2.0, 4), Vector3(3, 2.5, 3)]],
	"W1": [["ambient/Pollen", Vector3(0, 1.4, 6), Vector3(10, 2, 8)], ["Butterflies", Vector3(-2, 1.0, 5), Vector3.ZERO]],
	"W2": [["ambient/CloudWisps", Vector3(0, 0.5, 9), Vector3(12, 2.5, 8)], ["ambient/Petals", Vector3(0, 3.0, 5), Vector3.ZERO]],
	"W3": [["ambient/CandySparkles", Vector3(0, 1.2, 5), Vector3(8, 2, 6)]],
	"BOSS": [],
}
const FAMILY := {"HUB": "woolly_wolf", "W1": "woolly_wolf", "W2": "peapod_popper", "W3": "gingerbread_grenadier", "BOSS": "crow_bandit"}

var runner := false
var world := "W1"
var out := ""
## Optional comma-separated event labels to fire (default all); "--skip_ambient" skips the ambient and FxDresser shots.
var only := ""
var skip_ambient := false
## "--late=N" waits N frames after every event instead of the per-event default (lifecycle checks).
var late := 0


func _ready() -> void:
	if runner:
		_run.call_deferred()
		return
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var r := Node.new()
	r.set_script(load("res://scripts/fx/juice_world_probe.gd"))
	r.set("runner", true)
	r.set("world", String(args.get("world", "W1")))
	r.set("out", String(args.get("out", OS.get_user_data_dir().path_join("juice_probe"))))
	r.set("only", String(args.get("only", "")))
	r.set("skip_ambient", args.has("skip_ambient"))
	r.set("late", int(args.get("late", "0")))
	r.name = "JuiceWorldProbe"
	get_tree().root.add_child.call_deferred(r)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(idx: int, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%02d_%s.png" % [out, world, idx, label]
	img.save_png(path)
	print("[JuiceWorldProbe] saved ", path)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var path: String = WORLDS.get(world, WORLDS["W1"])
	get_tree().change_scene_to_file(path)
	await _frames(200)
	# Juice fix r4 (VFX critic r2 tooling): HUB and BOSS open on an intro cinematic and a banner pause, so the old probe
	# fired at the intro camera. Wait (up to 20 s) until the hero camera rig's own camera is current and nothing is paused.
	for _w in 1200:
		var gc := get_tree().get_first_node_in_group("game_camera")
		var gcam: Variant = gc.get("cam") if gc != null else null
		var cur := get_viewport().get_camera_3d()
		if not get_tree().paused and (gc == null or (gcam != null and cur == gcam)):
			break
		await get_tree().process_frame
	await _frames(20)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		print("[JuiceWorldProbe] FAIL no player or camera in ", path)
		get_tree().quit(1)
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var base := player.global_position
	var to_world := func(local: Vector3) -> Vector3:
		return base + right * local.x + Vector3.UP * local.y + fwd * local.z
	var n := 0
	await _shot(n, "before")
	n += 1
	# Ambient drop-ins exactly as Docs/JUICE.md tells world builders to place them.
	var scene := get_tree().current_scene
	for a in ([] if skip_ambient else AMBIENT.get(world, [])):
		var ps := load("res://scenes/fx/%s.tscn" % a[0]) as PackedScene
		if ps == null:
			continue
		var fx := ps.instantiate() as Node3D
		if a[2] != Vector3.ZERO:
			fx.set("area", a[2])
		scene.add_child(fx)
		fx.global_position = to_world.call(a[1])
	if not skip_ambient and not AMBIENT.get(world, []).is_empty():
		await _frames(150)
		await _shot(n, "ambient")
		n += 1
	# FxDresser drop-in (no terrain: only ambient volumes and the storybook post), as a world builder would call it.
	if world != "BOSS" and not skip_ambient:
		var dressing := FxDresser.dress(scene as Node3D, {"terrain": null, "post": true,
			"butterflies": [to_world.call(Vector3(-1.5, 1.0, 5.0))], "leaves": [to_world.call(Vector3(2.0, 3.0, 6.0))]})
		await _frames(120)
		await _shot(n, "fxdresser_post")
		n += 1
		# Remove the post again so the event shots below show the world's own grade.
		var post := dressing.get_node_or_null("StorybookPost")
		if post != null:
			post.queue_free()
		await _frames(2)
	var fam: String = FAMILY.get(world, "woolly_wolf")
	var events := [
		["land_heavy", "player_land", Vector3.ZERO, {"impact": 16.0}, 8],
		["ham_slam", "player_ham_slam", Vector3.ZERO, {"impact": 15.0}, 9],
		["punch", "player_punch", Vector3.ZERO, {"direction": right, "combo": 1, "node": player}, 3],
		["jump_3", "player_jump_3", Vector3.ZERO, {"node": player}, 10],
		["enemy_notice", "enemy_notice", Vector3(1.0, 1.2, 3.0), {"family": fam}, 14],
		["enemy_defeat_" + fam, "enemy_defeat", Vector3(0, 0.6, 3.0), {"family": fam}, 10],
		["truffle_collect", "object_truffle_collect", Vector3(0, 1.0, 2.5), {}, 40],
		["checkpoint", "object_checkpoint", Vector3(1.5, 0, 2.5), {}, 20],
		["bounce", "object_bounce_pad", Vector3(-1.5, 0, 2.5), {"impact": 14.0, "kind": {"W2": "leaf", "W3": "gumdrop"}.get(world, "pad")}, 8],
	]
	if world == "W3":
		events.append(["cocoa_burn", "world_cocoa_burn", Vector3(0, 0, 2.0), {}, 12])
	if world == "W2":
		events.append(["cloud_vanish", "object_cloud_vanish", Vector3(0, 0, 3.0), {}, 14])
	if world == "BOSS":
		events.append(["boss_chimney_smash", "boss_chimney_smash", Vector3(2.5, 0, 6.0), {}, 12])
	for ev in events:
		if only != "" and not (String(ev[0]) in only.split(",")):
			continue
		await _frames(70)
		var pos: Vector3 = to_world.call(ev[2])
		Juice.event(String(ev[1]), pos, ev[3])
		await _frames(late if late > 0 else int(ev[4]))
		await _shot(n, String(ev[0]))
		n += 1
	await _frames(30)
	print("[JuiceWorldProbe] done ", world, " shots=", n, " juice stats=", Juice.stats)
	var names: Array = []
	for h in Juice.history:
		names.append("%s@%d" % [h["name"], int(h["msec"])])
	print("[JuiceWorldProbe] history ", names)
	get_tree().quit()
