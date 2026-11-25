extends Node3D
## Audio director critic r1: 2D voice stealing. Plays a 2D thunder (2.95 s, as wolf_rooftop.gd does), then simulates
## ordinary running play through Juice: footsteps at 5 per second and one jump every 0.8 s. Reports whether the
## thunder's pool player was re-used (cut) before its natural end.
## Run: python tools/godot.py run res://tests/critique_audio/PoolProbe.tscn --seconds 20 -- --profile=critic_audio

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var audio := get_node("/root/Audio")
	var juice := get_node("/root/Juice")
	var p: AudioStreamPlayer = audio.play_sfx("thunder", Vector3.INF, 0.0)
	var name := p.stream.resource_path.get_file()
	var length := p.stream.get_length()
	var t0 := Time.get_ticks_msec()
	var cut_at := -1.0
	var i := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < length:
		await get_tree().create_timer(0.2).timeout
		i += 1
		juice.event("player_footstep", Vector3.ZERO, {"surface": "stone", "speed": 7.0, "foot": i % 2})
		if i % 4 == 0:
			juice.event("player_jump_1", Vector3.ZERO, {})
		if cut_at < 0.0 and (p.stream == null or p.stream.resource_path.get_file() != name or not p.playing):
			cut_at = (Time.get_ticks_msec() - t0) / 1000.0
	print("PROBE_JSON ", JSON.stringify({"sound": name, "length_s": snappedf(length, 0.01), "cut_at_s": snappedf(cut_at, 0.01),
		"cut": cut_at >= 0.0 and cut_at < length - 0.05, "pool2d": audio.get("_pool2d").size()}))
	get_tree().quit()
