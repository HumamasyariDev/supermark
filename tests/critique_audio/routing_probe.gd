extends Node3D
## Audio director critic r1: routing probes through the real autoloads (Audio, Juice -> JuiceSfx).
## Read-only with respect to game data. Each probe prints "PROBE <name> <result>" and a final JSON line.
## Run: python tools/godot.py run res://tests/critique_audio/RoutingProbe.tscn --seconds 25 -- --profile=critic_audio

var res := {}


func _p(name: String, v: Variant) -> void:
	res[name] = v
	print("PROBE ", name, " ", v)


func _playing_streams() -> Array:
	var a := get_node("/root/Audio")
	var out := []
	for pool in [a.get("_pool2d"), a.get("_pool3d")]:
		for p in pool:
			if p.playing and p.stream != null:
				out.append([p.stream.resource_path.get_file(), snappedf(p.get_playback_position(), 0.01)])
	return out


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var audio := get_node("/root/Audio")
	var juice := get_node("/root/Juice")
	var sfx := juice.get_node_or_null("JuiceSfx")
	sfx.log_plays = true
	sfx.force_handoff = false

	# 1. Boss events whose wolf_boss.gd direct sound is skipped when Juice.handles(ev, "sfx") is true.
	for ev in ["boss_stomp", "boss_inhale", "boss_huff", "boss_hit", "boss_chimney_smash", "boss_winded"]:
		var before_sfx: int = int(juice.stats.get("sfx", 0))
		var before_plays: int = sfx.played.size()
		var handles: bool = juice.handles(ev, "sfx")
		juice.event(ev, Vector3(0, 0, -4), {})
		await get_tree().create_timer(0.15).timeout
		var heard: bool = sfx.played.size() > before_plays or int(juice.stats.get("sfx", 0)) > before_sfx
		_p("boss_" + ev, {"juice_handles_sfx": handles, "wolf_skips_direct": handles, "anything_played": heard,
			"silent_in_game": handles and not heard})

	# 2. Hurt: JuiceSfx player_hurt + HUD UIFx ui_cake_lose -> how many copies of cake_slice_lost overlap?
	await get_tree().create_timer(0.5).timeout
	juice.event("player_hurt", Vector3.ZERO, {})
	UIFx.event("ui_cake_lose", {"health": 4})
	await get_tree().create_timer(0.12).timeout
	var st := _playing_streams()
	var n := 0
	for s in st:
		if String(s[0]).begins_with("cake_slice_lost"):
			n += 1
	_p("hurt_cake_slice_lost_copies", {"copies": n, "streams": st})

	# 3. Voice channel: a boss line, then Mak gets hurt 0.4 s later.
	await get_tree().create_timer(1.5).timeout
	sfx._reset_cooldowns()
	audio.play_voice("voice_wolf_curses")
	var vp: AudioStreamPlayer = audio.get("_voice")
	var wolf_len: float = vp.stream.get_length()
	await get_tree().create_timer(0.4).timeout
	juice.event("player_hurt", Vector3.ZERO, {})
	await get_tree().create_timer(0.1).timeout
	_p("voice_wolf_line_cut_by_mak", {"wolf_line_s": snappedf(wolf_len, 0.01), "now_playing": vp.stream.resource_path.get_file(),
		"cut": not vp.stream.resource_path.get_file().begins_with("wolf_curses")})

	# 4. Slide loop on a long slope slide (W3 slide is ~8 s).
	await get_tree().create_timer(1.5).timeout
	juice.event("player_slide_start", Vector3.ZERO, {"kind": "slope", "node": self})
	await get_tree().create_timer(0.5).timeout
	var a1: bool = sfx._loops.has("slide")
	await get_tree().create_timer(2.6).timeout
	var a2: bool = sfx._loops.has("slide")
	juice.event("player_slide_end", Vector3.ZERO, {})
	_p("slide_loop_alive", {"at_0_5s": a1, "at_3_1s": a2})

	# 5. 2D pool stealing: a long jingle-like one-shot, then a burst of 16 short 2D sounds.
	await get_tree().create_timer(1.0).timeout
	var long_p: Node = audio.play_sfx("object_trial_complete" if audio.has_key("object_trial_complete") else "trial_complete")
	if long_p == null:
		long_p = audio.play_sfx("great_truffle_appear")
	var long_name := ""
	if long_p != null:
		long_name = (long_p as AudioStreamPlayer).stream.resource_path.get_file()
	for i in 16:
		audio.play_sfx("acorn_collect")
		await get_tree().create_timer(0.06).timeout
	_p("pool2d_long_sound_stolen", {"long": long_name, "long_len": snappedf((long_p as AudioStreamPlayer).stream.get_length(), 0.01) if long_p else 0.0,
		"still_same_stream": long_p != null and (long_p as AudioStreamPlayer).stream.resource_path.get_file() == long_name,
		"elapsed_s": 0.96})
	print("PROBE_JSON ", JSON.stringify(res))
	get_tree().quit()
