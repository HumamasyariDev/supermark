extends Node
## Audio autoload ("Audio"): buses, music crossfade, pooled 2D/3D SFX, voice and ambience.
##
## Keys resolve through res://assets/audio/audio_index.json (owned by the audio workstream).
## Accepted index shapes (all optional, mixed freely):
##   {"key": "music/w1.ogg"}                                     path relative to res://assets/audio/ or res://...
##   {"key": {"file": "...", "bus": "SFX", "volume_db": -3, "loop": true, "pitch": 1.0}}
##   {"key": {"files": ["a.ogg", "b.ogg"], ...}}                 random variant per play ("variants" also works)
##   {"music": {"key": ...}, "sfx": {...}, "voice": {...}}       category groups (bus defaults from the group name)
##   {"entries": [{"key": "...", "file": "..."}]}
## A missing key prints one warning and never crashes.

const INDEX_PATH := "res://assets/audio/audio_index.json"
const AUDIO_ROOT := "res://assets/audio/"
const BUSES := ["Music", "SFX", "Voice", "Ambience", "Jingle"]
## Jingles play on their own bus so ducking the Music bus never ducks the jingle itself.
const JINGLE_BUS := "Jingle"
const DUCK_DB := -18.0
const SFX_POOL_2D := 16
const SFX_POOL_3D := 24
const CROSSFADE := 1.2

var index: Dictionary = {}  # key -> {files:Array, bus, volume_db, loop, pitch}
var current_music := ""
var current_ambience := ""

var _streams: Dictionary = {}  # path -> AudioStream
var _warned: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _jingle: AudioStreamPlayer
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next2d := 0
var _next3d := 0
var _music_tween: Tween
var _duck_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_music_active = _music_a
	_ambience = _make_player("Ambience")
	_voice = _make_player("Voice")
	_jingle = _make_player(JINGLE_BUS)
	for i in SFX_POOL_2D:
		_pool2d.append(_make_player("SFX"))
	for i in SFX_POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_pool3d.append(p)
	reload_index()
	apply_volumes()


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


# ---------------------------------------------------------------- index

func reload_index() -> void:
	index.clear()
	_streams.clear()
	if not FileAccess.file_exists(INDEX_PATH):
		print("[Audio] no audio index yet at ", INDEX_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if not parsed is Dictionary:
		push_warning("[Audio] audio_index.json is not a JSON object")
		return
	_ingest(parsed, "")
	print("[Audio] index loaded: %d keys" % index.size())


func _ingest(d: Dictionary, group: String) -> void:
	for k in d.keys():
		var v: Variant = d[k]
		var key := String(k)
		if key.begins_with("_") or key in ["version", "notes", "meta", "generated", "credits", "licence", "license"]:
			continue
		if key == "entries" and v is Array:
			for e in v:
				if e is Dictionary and e.has("key"):
					_add_entry(String(e["key"]), e, group)
			continue
		if v is String:
			_add_entry(key, {"file": v}, group)
		elif v is Array:
			_add_entry(key, {"files": v}, group)
		elif v is Dictionary:
			if v.has("file") or v.has("files") or v.has("path") or v.has("variants") or v.has("paths"):
				_add_entry(key, v, group)
			else:
				_ingest(v, key)


func _add_entry(key: String, e: Dictionary, group: String) -> void:
	var files: Array = []
	for field in ["files", "variants", "paths"]:
		if e.get(field) is Array:
			for f in e[field]:
				if f is String:
					files.append(_resolve(f))
				elif f is Dictionary and f.has("file"):
					files.append(_resolve(String(f["file"])))
	for field in ["file", "path"]:
		if e.get(field) is String:
			files.append(_resolve(e[field]))
	var bus := String(e.get("bus", _bus_for_group(group, key)))
	if not bus in BUSES and bus != "Master":
		bus = _bus_for_group(group, key)
	index[key] = {
		"files": files,
		"bus": bus,
		"volume_db": float(e.get("volume_db", e.get("gain_db", 0.0))),
		"loop": bool(e.get("loop", bus == "Music" or bus == "Ambience")),
		"pitch": float(e.get("pitch", 1.0)),
	}


func _bus_for_group(group: String, key: String) -> String:
	var g := (group + "/" + key).to_lower()
	if g.begins_with("music") or key.begins_with("music"):
		return "Music"
	if g.begins_with("voice") or key.begins_with("vo_") or key.begins_with("voice"):
		return "Voice"
	if g.begins_with("amb") or key.begins_with("amb"):
		return "Ambience"
	return "SFX"


func _resolve(p: String) -> String:
	if p.begins_with("res://"):
		return p
	return AUDIO_ROOT + p.trim_prefix("/").trim_prefix("assets/audio/")


func has_key(key: String) -> bool:
	return index.has(key)


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[Audio] " + msg)


func _stream_for(key: String) -> Dictionary:
	## Returns {stream, entry} or {} when the key is unknown or no file loads.
	if key == "":
		return {}
	var e: Dictionary = index.get(key, {})
	if e.is_empty():
		_warn_once(key, "missing key '%s'" % key)
		return {}
	var files: Array = e["files"]
	if files.is_empty():
		_warn_once(key, "key '%s' has no files" % key)
		return {}
	var path := String(files[randi() % files.size()])
	if not _streams.has(path):
		var s: AudioStream = null
		if ResourceLoader.exists(path):
			s = load(path) as AudioStream
		if s == null:
			_warn_once(key + path, "cannot load '%s' for key '%s'" % [path, key])
			return {}
		_set_loop(s, bool(e["loop"]))
		_streams[path] = s
	return {"stream": _streams[path], "entry": e}


func _set_loop(s: AudioStream, loop: bool) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = loop
	elif s is AudioStreamWAV and loop:
		var w := s as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = int(w.get_length() * w.mix_rate)


# ---------------------------------------------------------------- music

func play_music(key: String, fade: float = CROSSFADE) -> void:
	if key == current_music and _music_active.playing:
		return
	current_music = key
	var r := _stream_for(key)
	var old := _music_active
	var nxt := _music_b if old == _music_a else _music_a
	if _music_tween:
		_music_tween.kill()
	if old.playing:
		_music_tween = create_tween()
		_music_tween.tween_property(old, "volume_db", -60.0, fade)
		_music_tween.tween_callback(old.stop)
	if r.is_empty():
		return
	var previous: AudioStream = nxt.stream
	nxt.stream = r["stream"]
	_release_sample(previous)
	nxt.volume_db = -60.0
	nxt.pitch_scale = 1.0
	nxt.play()
	_music_active = nxt
	var target := float(r["entry"]["volume_db"])
	var t2 := create_tween()
	t2.tween_property(nxt, "volume_db", target, max(fade, 0.01))


func stop_music(fade: float = CROSSFADE) -> void:
	current_music = ""
	for p in [_music_a, _music_b]:
		if p.playing:
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, fade)
			t.tween_callback(p.stop)


## A short fanfare over the music: the music ducks and comes back afterwards.
## The jingle plays on its own Jingle bus (its level follows the music volume setting) and the
## duck lowers only the Music bus, so the jingle itself is never ducked (night-01 bug fix).
## `key` may name the jingle directly ("jingle_truffle_get") or a short form ("truffle_get"):
## "jingle_<key>" is preferred when it exists.
func play_jingle(key: String) -> void:
	var k := key
	if not key.begins_with("jingle_") and index.has("jingle_" + key):
		k = "jingle_" + key
	var r := _stream_for(k)
	if r.is_empty():
		return
	var s: AudioStream = r["stream"]
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	_jingle.stream = s
	_jingle.bus = JINGLE_BUS
	_jingle.volume_db = float(r["entry"]["volume_db"])
	_jingle.play()
	var dur := 2.5
	if s.has_method("get_length"):
		dur = clampf(s.get_length(), 0.5, 12.0)
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_music_duck, _duck_db, DUCK_DB, 0.2)
	_duck_tween.tween_interval(maxf(0.1, dur - 0.4))
	_duck_tween.tween_method(_set_music_duck, DUCK_DB, 0.0, 1.4)


var _duck_db := 0.0


func _set_music_duck(db: float) -> void:
	_duck_db = db
	var i := AudioServer.get_bus_index("Music")
	if i >= 0:
		AudioServer.set_bus_volume_db(i, _linear_to_db_safe(float(_setting("music_volume", 0.8))) + db)


func is_jingle_playing() -> bool:
	return _jingle != null and _jingle.playing


# ---------------------------------------------------------------- sfx, voice, ambience

## Finish pass (audio QA major, W3 enemy-step flood: 635 starts in 33 s, 206 same-file restarts under 60 ms, 21 at
## once, starts beyond 60 m, audible steals): per-key minimum gap, per-key voice cap, distance cull, and a free pool
## voice before any steal (the oldest voice is stolen last).
const SFX_GAP := {"enemy_step": 0.11, "wolf_cub_baa": 0.8, "gummy_wobble": 0.25, "sniff": 0.3}
const SFX_GAP_DEFAULT := 0.05
const SFX_KEY_CAP := 4
const SFX_CULL_M := 45.0
var _sfx_last := {}  # key -> msec of the last start


func _sfx_gate(key: String, at: Vector3) -> bool:
	var now := Time.get_ticks_msec()
	var gap := float(SFX_GAP.get(key, SFX_GAP_DEFAULT))
	if now - int(_sfx_last.get(key, -100000)) < int(gap * 1000.0):
		return false
	if at != Vector3.INF:
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		if cam != null and cam.global_position.distance_to(at) > SFX_CULL_M:
			return false
	var same := 0
	for p in _pool3d:
		if p.playing and String(p.get_meta("key", "")) == key:
			same += 1
	for p in _pool2d:
		if p.playing and String(p.get_meta("key", "")) == key:
			same += 1
	if same >= SFX_KEY_CAP:
		return false
	_sfx_last[key] = now
	return true


func _free_voice(pool: Array, start: int) -> int:
	for i in pool.size():
		var j := (start + i) % pool.size()
		if not pool[j].playing:
			return j
	return start


func play_sfx(key: String, at: Vector3 = Vector3.INF, pitch_jitter: float = 0.06, volume_db: float = 0.0) -> Node:
	if not _sfx_gate(key, at):
		return null
	var r := _stream_for(key)
	if r.is_empty():
		return null
	var e: Dictionary = r["entry"]
	var pitch := float(e["pitch"]) * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	if at == Vector3.INF:
		_next2d = _free_voice(_pool2d, _next2d)
		var p := _pool2d[_next2d]
		p.set_meta("key", key)
		_next2d = (_next2d + 1) % _pool2d.size()
		p.stream = r["stream"]
		p.bus = String(e["bus"])
		p.pitch_scale = max(0.05, pitch)
		p.volume_db = float(e["volume_db"]) + volume_db
		p.play()
		return p
	_next3d = _free_voice(_pool3d, _next3d)
	var p3 := _pool3d[_next3d]
	p3.set_meta("key", key)
	_next3d = (_next3d + 1) % _pool3d.size()
	p3.stream = r["stream"]
	p3.bus = String(e["bus"])
	p3.pitch_scale = max(0.05, pitch)
	p3.volume_db = float(e["volume_db"]) + volume_db
	p3.global_position = at
	p3.play()
	return p3


func play_ui(key: String) -> void:
	play_sfx(key, Vector3.INF, 0.02)


func play_voice(key: String) -> void:
	var r := _stream_for(key)
	if r.is_empty():
		return
	_voice.stream = r["stream"]
	_voice.volume_db = float(r["entry"]["volume_db"])
	_voice.pitch_scale = float(r["entry"]["pitch"])
	_voice.play()


func stop_voice() -> void:
	_voice.stop()


func play_ambience(key: String, fade: float = 2.0) -> void:
	if key == current_ambience and _ambience.playing:
		return
	current_ambience = key
	var r := _stream_for(key)
	if r.is_empty():
		_ambience.stop()
		return
	var previous: AudioStream = _ambience.stream
	_ambience.stream = r["stream"]
	_release_sample(previous)
	_ambience.volume_db = -50.0
	_ambience.play()
	create_tween().tween_property(_ambience, "volume_db", float(r["entry"]["volume_db"]), fade)


## Round 4 (web): a browser plays every stream as a Web Audio sample, decoded on first play into 48 kHz stereo floats
## that stay in the page's memory until released (about 40 MB for a 108 s track; Godot never releases them). A music
## track or ambience bed is released once no long player holds it, so a session keeps at most the two tracks of a
## crossfade and one bed (the ten music files alone decode to 218 MB). Short effects stay registered.
func _release_sample(stream: AudioStream) -> void:
	# --audio-keep: reviews measure the published behaviour against this one.
	if not OS.has_feature("web") or stream == null or OS.get_cmdline_user_args().has("--audio-keep"):
		return
	for p: AudioStreamPlayer in [_music_a, _music_b, _ambience, _jingle]:
		if p.stream == stream:
			return
	# Bound only by the round 4 web template (tools/engine/audio_sample_unregister.patch); Godot 4.7 leaves it unbound.
	if AudioServer.has_method("unregister_stream_as_sample") and AudioServer.is_stream_registered_as_sample(stream):
		AudioServer.call("unregister_stream_as_sample", stream)


## Round 4 (web): effects and voice lines decode the same way on their first play and stayed for the rest of the session
## (the game's 411 effects and lines decode to 263 MB). Between areas the Router releases the ones that are not playing;
## the UI's own sounds and Mak's steps, jumps and landings stay. An area decodes again what it plays, a few milliseconds
## per effect.
const KEEP_DECODED := ["ui_", "book_", "page_", "footstep", "jump", "land"]


func release_effect_samples() -> void:
	if not OS.has_feature("web") or OS.get_cmdline_user_args().has("--audio-keep") \
			or not AudioServer.has_method("unregister_stream_as_sample"):
		return
	var busy := {}
	var long_players: Array = [_music_a, _music_b, _ambience, _jingle]
	var players: Array = []
	players.append_array(_pool2d)
	players.append_array(_pool3d)
	players.append_array(long_players)
	players.append(_voice)
	for p: Node in players:
		var stream: AudioStream = p.get("stream")
		if stream != null and (bool(p.get("playing")) or p in long_players):
			busy[stream] = true
	var released := 0
	for path: String in _streams:
		var s: AudioStream = _streams[path]
		var file := path.get_file()
		if busy.has(s) or KEEP_DECODED.any(func(prefix: String) -> bool: return file.begins_with(prefix)):
			continue
		if AudioServer.is_stream_registered_as_sample(s):
			AudioServer.call("unregister_stream_as_sample", s)
			released += 1
	if released > 0:
		print("[Audio] web: released %d decoded effects between areas" % released)


func stop_ambience(fade: float = 1.5) -> void:
	current_ambience = ""
	var t := create_tween()
	t.tween_property(_ambience, "volume_db", -60.0, fade)
	t.tween_callback(_ambience.stop)


# ---------------------------------------------------------------- volumes

func _setting(key: String, default_value: Variant) -> Variant:
	var g := get_node_or_null("/root/Game")
	if g and "settings" in g:
		return g.settings.get(key, default_value)
	return default_value


func _linear_to_db_safe(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func apply_volumes() -> void:
	var map := {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume", "Voice": "voice_volume", "Ambience": "ambience_volume", "Jingle": "music_volume"}
	for bus in map.keys():
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			var v := float(_setting(map[bus], 1.0))
			AudioServer.set_bus_volume_db(i, _linear_to_db_safe(v) + (_duck_db if bus == "Music" else 0.0))
			AudioServer.set_bus_mute(i, v <= 0.001)
