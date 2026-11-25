extends Node
## Checks JuiceSfx's ambience bed follower in the real worlds: each world scene is loaded as a child of this test
## (the test is the current scene, as the Router's worlds are), and after a few seconds JuiceSfx must be playing that
## world's layered bed on its own players (2-4 layers, audible), the old single loop must be stopped (the boss's
## amb_storm_loop), and the reverb must follow the world; after the world is freed the bed must fade out.
## Fix stage r1 also checks the critique's blocker: a stop_ambience() call on the Audio autoload (the stale tween
## that killed the new bed after a transition) must not silence the bed any more.
## Run: python tools/godot.py run res://assets/audio/tests/AmbienceFollowCheck.tscn --seconds 160
##   -- --profile=audio   Prints AMBIENCE_FOLLOW {...}.

const WORLDS := ["HUB", "W1", "W2", "W3", "BOSS"]

var results := {}
var failures: Array = []


func _ready() -> void:
	await get_tree().process_frame
	var audio := get_node_or_null("/root/Audio")
	var juice := get_node_or_null("/root/Juice")
	var sfx: Node = juice.get_node_or_null("JuiceSfx") if juice else null
	if audio == null or sfx == null:
		_finish(["no Audio autoload or JuiceSfx"])
		return
	for w in WORLDS:
		var path := WorldRegistry.scene_path(w)
		if not ResourceLoader.exists(path):
			failures.append("%s: scene missing %s" % [w, path])
			continue
		var node := (load(path) as PackedScene).instantiate()
		add_child(node)
		await get_tree().create_timer(3.0).timeout
		# the critique's blocker: a stale stop tween on the Audio autoload's single ambience player
		if audio.has_method("stop_ambience"):
			audio.call("stop_ambience", 0.3)
		await get_tree().create_timer(1.5).timeout
		var bed: Array = sfx.get("_bed")
		var layers := {}
		var audible := 0
		for b in bed:
			var p: AudioStreamPlayer = b["player"]
			if is_instance_valid(p) and p.playing:
				layers[String(b["key"])] = snappedf(p.volume_db, 0.1)
				if p.volume_db > -40.0:
					audible += 1
		var amb_old: AudioStreamPlayer = audio.get("_ambience")
		var old_playing := amb_old != null and amb_old.playing and amb_old.volume_db > -40.0
		var bi := AudioServer.get_bus_index("SFX")
		var rev_on := false
		for i in AudioServer.get_bus_effect_count(bi):
			var e := AudioServer.get_bus_effect(bi, i)
			if e is AudioEffectReverb and AudioServer.is_bus_effect_enabled(bi, i):
				rev_on = true
		results[w] = {"bed_world": String(sfx.get("bed_world")), "layers": layers, "audible_layers": audible,
			"old_single_loop_playing": old_playing, "reverb_on": rev_on, "bed_phase": int(sfx.get("bed_phase"))}
		if String(sfx.get("bed_world")) != w:
			failures.append("%s: bed_world %s" % [w, sfx.get("bed_world")])
		if layers.size() < 2 or audible < 1:
			failures.append("%s: bed not audible %s" % [w, str(layers)])
		if old_playing:
			failures.append("%s: the old single loop still plays under the bed" % w)
		if not rev_on:
			failures.append("%s: no world reverb" % w)
		if w == "BOSS":
			# fix stage r1b (QA polish): a page curl toward the title must fade the bed, scatter tails, proximity and
			# named loops during the curl (curl_fade_s), so nothing of the storm reaches the title screen
			sfx.call("set_bed_phase", 3)
			await get_tree().create_timer(0.5).timeout
			var pre_loops: int = (sfx.get("_loops") as Dictionary).size()
			sfx.call("_on_transition_started", "")
			await get_tree().create_timer(float(sfx.ambience.get("curl_fade_s", 0.9)) + 0.25).timeout
			var loud := 0
			for b in sfx.get("_bed"):
				var pb: AudioStreamPlayer = b["player"]
				if is_instance_valid(pb) and pb.playing and pb.volume_db > -50.0:
					loud += 1
			for sp in sfx.get("_scatter_pool"):
				if is_instance_valid(sp) and sp.playing and sp.volume_db > -50.0:
					loud += 1
			var left_loops: int = (sfx.get("_loops") as Dictionary).size()
			var left_prox: int = (sfx.get("_prox") as Dictionary).size()
			results[w]["curl_to_title"] = {"loops_before": pre_loops, "loud_after_curl": loud, "loops_after": left_loops, "prox_after": left_prox,
				"bed_world": String(sfx.get("bed_world"))}
			if loud > 0 or left_loops > 0 or left_prox > 0 or String(sfx.get("bed_world")) != "":
				failures.append("BOSS: something still sounds after the curl toward the title %s" % str(results[w]["curl_to_title"]))
		node.queue_free()
		await get_tree().create_timer(2.5).timeout
		var still := 0
		for b in sfx.get("_bed"):
			var p2: AudioStreamPlayer = b["player"]
			if is_instance_valid(p2) and p2.playing:
				still += 1
		results[w]["after_exit_bed_world"] = String(sfx.get("bed_world"))
		results[w]["after_exit_layers"] = still
		if String(sfx.get("bed_world")) != "" or still > 0:
			failures.append("%s: bed still playing after the world left" % w)
	_finish(failures)


func _finish(f: Array) -> void:
	for w in results:
		print("%s %s" % [w, JSON.stringify(results[w])])
	print("AMBIENCE_FOLLOW " + JSON.stringify({"worlds": results.size(), "failures": f}))
	get_tree().quit(0 if f.is_empty() else 1)
