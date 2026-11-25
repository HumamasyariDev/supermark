extends Node3D
## Critique JUICE r2, PERFORMANCE lens: where does the JuiceSfx burst cost go? Empty stage (no world), real audio
## driver. Times, on the main thread:
##   a) Audio.play_sfx(key, pos) for 12 different juice keys in one frame (the real path, pool slot re-streamed)
##   b) the same 12 plays straight on fresh AudioStreamPlayer3D nodes that already hold their stream (no re-stream)
##   c) the same 12 streams through one AudioStreamPolyphonic playback (play_stream, 3D player with 32 voices)
##   d) JuiceSfx.handle() for the 12 heavy events (its own logic plus a)
##   e) first-ever load() cost of the audio files those events use (lazy _stream_for)
##   python tools/godot.py run res://tests/critique_juice/PerfAudioR2.tscn --seconds 120 -- --profile=crit_juice_perf_r2 --out=<abs json>

const HEAVY := ["player_ham_slam", "object_truffle_collect", "boss_defeat", "enemy_defeat", "enemy_defeat", "enemy_defeat",
	"enemy_defeat", "object_checkpoint", "object_crate_break", "player_land", "object_bounce_pad", "boss_chimney_smash"]
const FAMS := ["", "", "", "woolly_wolf", "crow_bandit", "gummy_brute", "gingerbread_grenadier", "", "", "", "", ""]

var out := ""
var res := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2, 6)
	cam.current = true
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2]) if not s.is_empty() else 0.0


func _run() -> void:
	await _frames(30)
	var audio := get_node("/root/Audio")
	var sfx: Node = Juice.get_node_or_null("JuiceSfx")
	# Keys JuiceSfx would play for the 12 heavy events (first layer of each, resolved through the Audio index).
	var keys: Array = []
	var cfg: Dictionary = sfx.get("events") if sfx != null else {}
	for ev in HEAVY:
		var spec: Dictionary = cfg.get(ev, {})
		for layer in spec.get("layers", []):
			var k := String((layer as Dictionary).get("key", ""))
			if k != "" and k.find("{") < 0 and bool(audio.call("has_key", k)):
				keys.append(k)
	res["keys"] = keys
	print("[PerfAudio] %d layer keys for 12 heavy events" % keys.size())
	# e) first load of every file behind those keys (Audio._stream_for loads lazily, on the main thread, at first play).
	var t_load := Time.get_ticks_usec()
	var streams: Array = []
	for k in keys:
		var r: Dictionary = audio.call("_stream_for", k)
		if not r.is_empty():
			streams.append(r["stream"])
	res["e_first_stream_for_all_ms"] = snappedf((Time.get_ticks_usec() - t_load) / 1000.0, 0.01)
	print("[PerfAudio] e) first _stream_for for %d keys: %.2f ms" % [keys.size(), res["e_first_stream_for_all_ms"]])
	await _frames(30)
	# a) the real path
	var a_ms: Array = []
	for rep in 8:
		var t := Time.get_ticks_usec()
		for k in keys:
			audio.call("play_sfx", k, Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 0.0, -30.0)
		a_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		await _frames(40)
	res["a_audio_play_sfx_ms"] = a_ms
	# b) fresh players holding their stream (no stream swap on a busy slot)
	var players: Array = []
	for s in streams:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = -30.0
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	await _frames(10)
	var b_ms: Array = []
	for rep in 8:
		var t := Time.get_ticks_usec()
		for p in players:
			(p as AudioStreamPlayer3D).play()
		b_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		await _frames(40)
	res["b_fixed_players_play_ms"] = b_ms
	for p in players:
		(p as AudioStreamPlayer3D).stop()
	# c) one polyphonic playback
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 32
	var pp := AudioStreamPlayer3D.new()
	pp.stream = poly
	pp.bus = "SFX"
	pp.volume_db = -30.0
	add_child(pp)
	pp.play()
	await _frames(5)
	var pb := pp.get_stream_playback() as AudioStreamPlaybackPolyphonic
	var c_ms: Array = []
	for rep in 8:
		var t := Time.get_ticks_usec()
		for s in streams:
			pb.play_stream(s, 0.0, 0.0, 1.0)
		c_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		await _frames(40)
	res["c_polyphonic_play_stream_ms"] = c_ms
	# d) JuiceSfx.handle for the 12 events
	var d_ms: Array = []
	if sfx != null:
		for rep in 8:
			var t := Time.get_ticks_usec()
			for i in HEAVY.size():
				sfx.call("handle", HEAVY[i], Vector3(0, 0, -2), {"family": FAMS[i], "impact": 16.0})
			d_ms.append((Time.get_ticks_usec() - t) / 1000.0)
			await _frames(60)
	res["d_juicesfx_handle_12_ms"] = d_ms
	# f) the same number of plays on fresh players holding a 1 s 16-bit PCM AudioStreamWAV (what a WAV/QOA import gives).
	var pcm := PackedByteArray()
	pcm.resize(48000 * 2)
	for i in 48000:
		pcm.encode_s16(i * 2, int(sin(float(i) * 0.05) * 3000.0))
	var wplayers: Array = []
	for i in streams.size():
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = 48000
		w.data = pcm
		var p := AudioStreamPlayer3D.new()
		p.stream = w
		p.volume_db = -40.0
		p.bus = "SFX"
		add_child(p)
		wplayers.append(p)
	await _frames(10)
	var f_ms: Array = []
	for rep in 8:
		var t := Time.get_ticks_usec()
		for p in wplayers:
			(p as AudioStreamPlayer3D).play()
		f_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		await _frames(40)
	res["f_wav_players_play_ms"] = f_ms
	res["driver"] = AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else ""
	res["mix_rate"] = AudioServer.get_mix_rate()
	res["output_latency_ms"] = snappedf(AudioServer.get_output_latency() * 1000.0, 0.1)
	for k in ["a_audio_play_sfx_ms", "b_fixed_players_play_ms", "c_polyphonic_play_stream_ms", "d_juicesfx_handle_12_ms", "f_wav_players_play_ms"]:
		print("[PerfAudio] %s median=%.2f all=%s" % [k, _med(res[k]), str(res[k])])
	print("[PerfAudio] output latency %.1f ms, mix rate %d" % [res["output_latency_ms"], res["mix_rate"]])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(res, "  "))
			f.close()
	get_tree().quit()
