extends Control
## Audio showcase for night01 evidence: plays the bank through the real Audio autoload while a
## spectrum analyser on the Master bus draws what is actually being mixed. Record with Movie Maker.

const BAR_COUNT := 48
var _t := 0.0
var _i := 0
var _log: Array[String] = []
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _title: Label
var _list: Label
var _peaks := PackedFloat32Array()
var _viz: Control

# [time_s, kind, key, caption]
var _events := [
	[0.2, "music", "music_title", "Title: storybook overture"],
	[6.0, "music", "music_hub", "Hub: the Grand Library"],
	[7.0, "voice", "voice_butler_welcome", "Bramwell: \"Welcome home, sir.\""],
	[10.5, "music", "music_w1", "World 1: Huff & Puff Hollow"],
	[11.2, "voice", "voice_mak_tallyho", "Mr. Mak: \"Tally-ho!\""],
	[12.6, "sfx", "jump_1", "Jump 1"], [12.62, "voice", "voice_mak_jump1", ""],
	[13.3, "sfx", "jump_2", "Jump 2"], [13.32, "voice", "voice_mak_jump2", ""],
	[14.0, "sfx", "jump_3", "Triple jump"], [14.02, "voice", "voice_mak_jump3", ""],
	[14.9, "sfx", "land", "Land"],
	[15.3, "sfx", "footstep_grass", "Footsteps (grass)"], [15.6, "sfx", "footstep_grass", ""], [15.9, "sfx", "footstep_grass", ""], [16.2, "sfx", "footstep_grass", ""],
	[16.8, "sfx", "ham_slam", "Ham Slam"],
	[18.0, "sfx", "acorn_collect", "Acorns"], [18.25, "sfx", "acorn_collect", ""], [18.5, "sfx", "acorn_collect", ""],
	[19.2, "sfx", "wolf_cub_baa", "Woolly Wolf: fake baa"],
	[20.3, "sfx", "enemy_notice", "Enemy notices"],
	[21.0, "sfx", "punch", "Punch"], [21.3, "sfx", "enemy_hit", ""], [21.6, "sfx", "enemy_defeat_poof", "Defeat poof"],
	[22.6, "jingle", "music_truffle_get", "Golden Truffle jingle"], [22.7, "sfx", "truffle_get", ""],
	[24.4, "voice", "voice_mak_truffle", "Mr. Mak: \"Ooh, a truffle!\""],
	[26.5, "music", "music_w2", "World 2: Beanstalk Skyway"],
	[27.5, "sfx", "cloud_puff", "Cloud puff"], [28.3, "sfx", "gust_whoosh", "Gust"], [29.6, "sfx", "pea_pop", "Peapod Popper"],
	[31.5, "music", "music_w3", "World 3: Gingerbread Grove"],
	[32.5, "sfx", "gingerbread_crumble", "Gingerbread Grenadier crumbles"], [33.6, "sfx", "gummy_wobble", "Gummy Brute wobble"],
	[34.6, "sfx", "footstep_candy", "Footsteps (candy)"], [34.9, "sfx", "footstep_candy", ""], [35.2, "sfx", "footstep_candy", ""],
	[36.5, "music", "music_boss", "Boss: Sir Reginald Huffington III"],
	[37.3, "voice", "voice_wolf_littlepig", "Huffington: \"Little pig, little pig...\""],
	[40.0, "sfx", "boss_inhale", "Boss inhales"],
	[42.0, "voice", "voice_wolf_huffpuff", "Huffington: \"I'll huff, and I'll puff!\""],
	[44.2, "sfx", "boss_huff_blast", "Huff blast"],
	[46.0, "sfx", "boss_stomp", "Boss stomp"], [46.8, "sfx", "boss_stomp", ""],
	[47.6, "sfx", "boss_charge", "Boss charge"], [47.8, "voice", "voice_wolf_getback", "Huffington: \"Get back here!\""],
	[49.4, "voice", "voice_mak_hamslam", "Mr. Mak: \"Ham Slam!\""], [49.9, "sfx", "ham_slam", ""],
	[50.9, "voice", "voice_wolf_tail", "Huffington: \"Yeowch! My tail!\""],
	[53.6, "voice", "voice_wolf_curses", "Huffington: \"Curses, Piglet!\""],
	[55.4, "stop", "", ""], [55.5, "jingle", "music_victory", "Victory fanfare"],
	[57.6, "voice", "voice_mak_tophat", "Mr. Mak: \"A top hat! How dashing!\""],
	[62.0, "music", "music_w1", "Loop seam test: W1, last 4 s then wrap"], [62.1, "seek_end", "4.0", ""],
	[70.0, "music", "music_boss", "Loop seam test: boss, last 4 s then wrap"], [70.1, "seek_end", "4.0", ""],
]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.08, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_title = Label.new()
	_title.position = Vector2(60, 40)
	_title.add_theme_font_size_override("font_size", 54)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_title.text = "Super Mak 64: audio bank"
	add_child(_title)
	_list = Label.new()
	_list.position = Vector2(60, 140)
	_list.add_theme_font_size_override("font_size", 30)
	_list.add_theme_color_override("font_color", Color(0.96, 0.92, 0.85))
	add_child(_list)
	_viz = Control.new()
	_viz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viz)
	_viz.draw.connect(_draw_viz)
	var fx := AudioEffectSpectrumAnalyzer.new()
	fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(0, fx)
	_spectrum = AudioServer.get_bus_effect_instance(0, AudioServer.get_bus_effect_count(0) - 1)
	_peaks.resize(BAR_COUNT)


func _audio() -> Node:
	return get_node_or_null("/root/Audio")


func _process(delta: float) -> void:
	_t += delta
	var a := _audio()
	while _i < _events.size() and _t >= float(_events[_i][0]):
		var ev: Array = _events[_i]
		_i += 1
		if a == null:
			continue
		match String(ev[1]):
			"music":
				a.play_music(ev[2], 0.8)
			"voice":
				a.play_voice(ev[2])
			"sfx":
				a.play_sfx(ev[2])
			"jingle":
				a.play_jingle(ev[2])
			"stop":
				a.stop_music(0.3)
			"seek_end":
				var p: AudioStreamPlayer = a.get("_music_active")
				if p and p.stream:
					p.volume_db = -4.0
					p.seek(max(0.0, p.stream.get_length() - float(ev[2])))
		if String(ev[3]) != "":
			_log.append("%5.1fs  %s   [%s]" % [_t, ev[3], ev[2]])
			if _log.size() > 14:
				_log.pop_front()
			_list.text = "\n".join(_log)
	_viz.queue_redraw()


func _draw_viz() -> void:
	if _spectrum == null:
		return
	var w := _viz.size.x - 120.0
	var base := _viz.size.y - 60.0
	var bw := w / BAR_COUNT
	var f0 := 40.0
	for b in BAR_COUNT:
		var lo := f0 * pow(16000.0 / f0, float(b) / BAR_COUNT)
		var hi := f0 * pow(16000.0 / f0, float(b + 1) / BAR_COUNT)
		var m := _spectrum.get_magnitude_for_frequency_range(lo, hi).length()
		var energy := clampf((linear_to_db(maxf(m, 1e-6)) + 72.0) / 72.0, 0.0, 1.0)
		_peaks[b] = maxf(energy, _peaks[b] - 0.012)
		var h := energy * 300.0
		var col := Color(0.95, 0.55, 0.62).lerp(Color(1.0, 0.82, 0.35), float(b) / BAR_COUNT)
		_viz.draw_rect(Rect2(60.0 + b * bw + 2.0, base - h, bw - 4.0, h), col)
		_viz.draw_rect(Rect2(60.0 + b * bw + 2.0, base - _peaks[b] * 300.0 - 4.0, bw - 4.0, 3.0), Color(1, 1, 1, 0.8))
	_viz.draw_string(ThemeDB.fallback_font, Vector2(60, base + 40), "Master bus spectrum (live, AudioEffectSpectrumAnalyzer)", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.75, 0.7))
