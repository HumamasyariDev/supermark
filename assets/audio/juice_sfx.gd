class_name JuiceSfx
extends Node
## Plays the sound side of Juice events from res://assets/audio/juice_sfx.json (owned by the audio track).
##
## Install once (the juice track does this in juice.gd `_ready`):
##     add_child(load("res://assets/audio/juice_sfx.gd").new())
## When its parent has a `fired(event_name, position, params)` signal it connects to it, so every
## `Juice.event(...)` call plays its sounds. Without the Juice autoload, call `JuiceSfx.ensure(node).handle(...)`.
##
## Per event: layers (several sounds at once), random variants (resolved by the Audio index), pitch and volume
## jitter, delays, chance, `cases` that switch layers by params (kind, impact, surface, enemy...), param templates
## in keys ("footstep_{surface}"), per-event and per-layer cooldowns, a per-second cap, voice priority with a
## global gap, and named loops that start and stop. Unknown events fall back to an Audio key of the same name.
## Everything is duck-typed: a missing Audio autoload or key never crashes.
##
## Runtime glue added in the fix stage (critique round 1):
## - area beds: this node plays each world's ambience as 2-3 layered loops with co-prime lengths on its own players,
##   plus a scatter emitter of one-shots around the camera; equal-power crossfades between worlds; the bed holds
##   through scene swaps and checkpoint reloads (no stale stop tween can kill it); boss beds follow the fight phase
## - per-world space: a reverb on the SFX and Voice buses whose size and wet level follow the world
## - continuous player states polled from the player: wall-slide loop, slide loop pitch/volume from speed, pole
##   climb steps, a soft low-health pulse
## - proximity loops (truffle sparkle, wind-zone gusts) near the camera
## - pause: low-pass and -6 dB on Music and Ambience, SFX that were playing are paused
## - music: fades under the page curl when the Router changes world; a duck for the death moment; the boss battle
##   music stops at the defeat and a calm cue follows the victory jingles
## - voice: a line started outside JuiceSfx (wolf, dialogue) counts as priority 4, so hero grunts never cut it
## - 3D plays beyond the preset's max distance are skipped; the same key never starts twice within 60 ms
##
## Fix stage r1b (critique r1 re-check):
## - delayed layers are dropped when the scene changes before they play, and a layer's `cancel_on` events cancel it
##   (Mak's death line no longer lands after the respawn)
## - `surface_map` on a layer or state maps surfaces without their own sound to the nearest one before key templating;
##   the polled slide loop follows the floor and crossfades to the new surface's loop mid-slide
## - the page curl into a new world plays that world's `ambience.curl_stings`, and fades scatter tails, proximity loops
##   and named loops with the bed (no storm tail on the title)
## - scatter entries may name an `anchor_group`: one-shots then come from a random node of that group within
##   `max_anchor_distance` of the camera (river, clock); when the group exists but none is near (or `anchor_only` is
##   set) the one-shot is skipped, and a world without the group keeps the random placement
## - `force_chance` (tests and labs) makes every layer play regardless of its chance

const CONFIG_PATH := "res://assets/audio/juice_sfx.json"
const POOL_3D_DEFAULTS := {"unit_size": 6.0, "max_distance": 70.0, "filter_hz": 9000.0, "filter_db": -24.0}

static var instance: JuiceSfx = null

var events: Dictionary = {}
var aliases: Dictionary = {}
var defaults: Dictionary = {}
var mix: Dictionary = {}
var fallback_to_keys := true
var log_plays := false  # tests: record what played
var played: Array = []  # [{t, event, key, delay, volume_db, pitch, positional}]
var print_plays := false  # --juice-sfx-log: print every play to stdout (recordings and real-play evidence)
var force_chance := false  # tests and labs: ignore layer chance so every layer plays
var _fired_at: Dictionary = {}  # canonical event -> last time it was handled (cancel_on for delayed layers)

var _last_event: Dictionary = {}
var _last_layer: Dictionary = {}
var _last_key: Dictionary = {}  # key -> last start time (same-key anti-stack)
var _recent: Dictionary = {}
var _loops: Dictionary = {}  # loop_id -> {player, follow, max_time, t0, base_db}
var _voice_busy_until := 0.0
var _voice_priority := 0
var _last_voice_key := ""
var ambience: Dictionary = {}  # see juice_sfx_build.py "ambience"
var surface_world_default: Dictionary = {}  # world_id -> surface used when the player reports the default "grass"
var surface_name_hints: Dictionary = {}  # world_id or "*" -> [[name substring, surface]] for untagged floors (W2 clouds)
var states: Dictionary = {}  # polled player states (juice_sfx.json "states")
var proximity: Array = []  # proximity loops (juice_sfx.json "proximity")
var ambience_follow := true  # tests can switch the bed follower off
var _amb_poll := 0.0

# ---- area beds (owned players)
var bed_world := ""  # world id of the bed playing ("" = none)
var bed_phase := 1
var _bed: Array = []  # [{player, key, base_db, phases(Array or null), w(float 0..1 via tween)}]
var _bed_out: Array = []  # fading-out players
var _bed_tween: Tween
var _no_world_polls := 0
var _scene_id := 0
var _scene_changed_at := -1e9
var _scatter_t: Array = []  # seconds to each scatter entry's next event
var _scatter_pool: Array[AudioStreamPlayer3D] = []
var _scatter_next := 0
var _reverb_world := "?"
var _leaving_scene := 0  # the scene the Router is curling away from: its bed must not restart during the curl

# ---- player state polling
var _player: Node = null
var _player_last_pos := Vector3.INF
var _state_t := {}  # state -> time spent out of it (grace), climb step timer, low health timer
var _death_at := -1e9

# ---- pause and music
var _paused_fx := false
var _paused_players: Array = []
var _duck_tween: Tween
var _boss_defeated_at := -1.0
var _jingle_was_playing := false
var _prox: Dictionary = {}  # node instance id -> {player, node, cfg}
var _prox_poll := 0.0


static func ensure(any_node: Node) -> JuiceSfx:
	if is_instance_valid(instance):
		return instance
	var n := JuiceSfx.new()
	n.name = "JuiceSfx"
	any_node.get_tree().root.add_child.call_deferred(n)
	instance = n
	return n


func _enter_tree() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	if "--juice-sfx-all" in OS.get_cmdline_user_args():
		force_handoff = true  # labs and recordings: play handoff events before the owns() handshake
	print_plays = "--juice-sfx-log" in OS.get_cmdline_user_args()
	reload()
	var p := get_parent()
	if p != null and p.has_signal("fired") and not p.is_connected("fired", _on_fired):
		p.connect("fired", _on_fired)
	_apply_mix()
	var r := get_tree().root.get_node_or_null("Router")
	if r != null and r.has_signal("transition_started") and not r.is_connected("transition_started", _on_transition_started):
		r.connect("transition_started", _on_transition_started)
	for i in 4:
		var s := AudioStreamPlayer3D.new()
		s.bus = "Ambience"
		s.unit_size = 14.0
		s.max_distance = 90.0
		s.attenuation_filter_cutoff_hz = 12000.0
		add_child(s)
		_scatter_pool.append(s)


func reload() -> void:
	events.clear()
	aliases.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("[JuiceSfx] no config at " + CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		push_warning("[JuiceSfx] juice_sfx.json is not a JSON object")
		return
	events = parsed.get("events", {})
	aliases = parsed.get("aliases", {})
	defaults = parsed.get("defaults", {})
	mix = parsed.get("mix", {})
	fallback_to_keys = bool(parsed.get("fallback_to_audio_keys", true))
	ambience = parsed.get("ambience", {})
	surface_world_default = parsed.get("surface_world_default", {})
	surface_name_hints = parsed.get("surface_name_hints", {})
	states = parsed.get("states", {})
	proximity = parsed.get("proximity", [])


func _on_fired(event_name: String, position: Vector3, params: Dictionary) -> void:
	handle(event_name, position, params)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _audio() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Audio")


func _game() -> Node:
	return get_tree().root.get_node_or_null("Game") if is_inside_tree() else null


## True when juice_sfx.json maps this event (Juice then skips its own fallback sound). Events with handoff "owns"
## report true only once the emitter has stopped playing its own sounds (see _handed_off).
func has_event(event_name: String) -> bool:
	var ev := _canonical(event_name, {})
	if not events.has(ev):
		return false
	return _handed_off(events[ev])


## Juice's naming: an alias table plus the `kind` suffix (player_jump + kind double -> player_jump_double).
func _canonical(event_name: String, params: Dictionary) -> String:
	if params.has("kind"):
		var alt := "%s_%s" % [event_name, str(params["kind"])]
		if events.has(alt):
			return alt
		if aliases.has(alt):
			return String(aliases[alt])
	if events.has(event_name):
		return event_name
	return String(aliases.get(event_name, event_name))


## Events with handoff "owns" stay silent here until Juice exposes owns(); none use it since the fix stage (the boss
## asks Juice.handles(event, "sfx") per moment and skips its own sound, like the player and the enemies).
func _handed_off(spec: Dictionary) -> bool:
	if String(spec.get("handoff", "")) != "owns":
		return true
	if force_handoff:
		return true
	var p := get_parent()
	return p != null and p.has_method("owns")


var force_handoff := false  # tests and labs: play handoff events even without Juice.owns()
var _chain: Dictionary = {}  # event -> [last_time, step]


## Plays the sounds for one event. Returns true when anything was scheduled.
func handle(event_name: String, position: Vector3 = Vector3.INF, params: Dictionary = {}) -> bool:
	if params.get("silent", false):
		return false
	var ev := _canonical(event_name, params)
	_fired_at[ev] = _now()
	var spec: Dictionary = events.get(ev, {})
	if spec.is_empty():
		var a := _audio()
		if fallback_to_keys and a != null and a.has_method("has_key") and a.call("has_key", event_name):
			return _play_key(event_name, position, {}, params, ev)
		return false
	if not _handed_off(spec):
		return false
	params = _world_surface(params)
	var skip := String(spec.get("skip_if_param", ""))
	if skip != "" and params.get(skip, false):
		return false  # the emitter already played this sound (UI)
	if spec.get("skip_if_lethal", false) and _health() <= 0:
		return false  # the death event that follows owns the moment (critique r1: hurt + death pile-up)
	var after_scene := float(spec.get("skip_after_scene", 0.0))
	if after_scene > 0.0 and _now() - _scene_changed_at < after_scene:
		return false  # world entry places the player with respawn(); the page turn already marks it
	spec = _resolve_cases(spec, params)
	if spec.get("silent", false):
		return false
	var ch: Dictionary = spec.get("chain", {})
	if not ch.is_empty():
		var st: Array = _chain.get(ev, [-1e9, -1])
		var t := _now()
		var step := 0 if t - float(st[0]) > float(ch.get("window", 0.7)) else mini(int(st[1]) + 1, int(ch.get("max_steps", 8)))
		_chain[ev] = [t, step]
		params = params.duplicate()
		params["_chain"] = step
		spec = spec.duplicate()
		spec["pitch_by"] = {"param": "_chain", "semitones": float(ch.get("semitones", 1.0)), "max": 2.0}
	var now := _now()
	var scope := String(spec.get("cooldown_scope", ""))
	var ck := ev + "|" + (str(params.get(scope, "")) if scope != "" else "")
	var cd := float(spec.get("cooldown", defaults.get("cooldown", 0.03)))
	if now - float(_last_event.get(ck, -1e9)) < cd:
		return false
	var cap := int(spec.get("max_per_second", defaults.get("max_per_second", 12)))
	var rec: Array = _recent.get(ev, [])
	while not rec.is_empty() and now - float(rec[0]) > 1.0:
		rec.pop_front()
	if rec.size() >= cap:
		return false
	rec.append(now)
	_recent[ev] = rec
	_last_event[ck] = now
	_actions(spec, params)
	for id in spec.get("stop", []):
		stop_loop(String(id), float(spec.get("stop_fade", 0.15)))
	var any := false
	for layer in spec.get("layers", []):
		if layer is Dictionary:
			any = _layer(layer, position, params, spec, ev) or any
	return any


func _health() -> int:
	var g := _game()
	if g == null or not "health" in g:
		return 99
	return int(g.get("health"))


## Non-sound side effects of an event: music duck, music stop/start, boss bed phase.
func _actions(spec: Dictionary, params: Dictionary) -> void:
	var duck: Dictionary = spec.get("duck_music", {})
	if not duck.is_empty():
		duck_music(float(duck.get("db", -12.0)), float(duck.get("attack", 0.05)), float(duck.get("hold", 1.0)), float(duck.get("release", 1.0)))
	if spec.has("bed_phase_param") and params.has(String(spec["bed_phase_param"])):
		set_bed_phase(int(params[String(spec["bed_phase_param"])]))
	if spec.has("bed_phase_set"):
		set_bed_phase(int(spec["bed_phase_set"]))
	var mu: Dictionary = spec.get("music", {})
	if not mu.is_empty():
		var a := _audio()
		if a != null and mu.has("stop") and a.has_method("stop_music"):
			a.call("stop_music", float(mu["stop"]))
		if mu.has("after_jingles"):
			_boss_defeated_at = _now()
			_jingle_was_playing = false
			set_meta("after_jingles", mu["after_jingles"])
	if spec.get("marks_death", false):
		_death_at = _now()


## The player reports "grass" for any floor without a `surface` meta or group. Indoors and in the candy and rooftop
## worlds that is wrong, so juice_sfx.json `surface_world_default` swaps that default for the world's ground
## (HUB wood, W3 candy, BOSS stone). Floors that carry their own meta are unaffected unless they say "grass".
func _world_surface(params: Dictionary) -> Dictionary:
	if String(params.get("surface", "")) != "grass" or (surface_world_default.is_empty() and surface_name_hints.is_empty()):
		return params
	var g := _game()
	var w := String(g.get("current_world")) if g != null and "current_world" in g else ""
	var hinted := _surface_from_floor_name(w)
	if hinted != "":
		var ph := params.duplicate()
		ph["surface"] = hinted
		return ph
	if not surface_world_default.has(w):
		return params
	var p := params.duplicate()
	p["surface"] = String(surface_world_default[w])
	return p


## r1b (critique r1 QA minor: W2 clouds played grass steps): an untagged floor whose node, parent or grandparent name
## (or script class) contains a hint substring gets that surface, e.g. W2's CloudDecks bodies and VanishingCloud -> cloud.
func _surface_from_floor_name(w: String) -> String:
	var hints: Array = []
	hints.append_array(surface_name_hints.get(w, []))
	hints.append_array(surface_name_hints.get("*", []))
	if hints.is_empty():
		return ""
	var pl := _find_player()
	if pl == null or not "floor_collider" in pl:
		return ""
	var fc: Variant = pl.get("floor_collider")
	if not fc is Node or not is_instance_valid(fc):
		return ""
	var n: Node = fc
	var names := ""
	for i in 3:
		if n == null:
			break
		names += String(n.name).to_lower() + "|"
		var sc: Variant = n.get_script()
		if sc is Script:
			names += String((sc as Script).get_global_name()).to_lower() + "|"
		n = n.get_parent()
	for h in hints:
		if h is Array and (h as Array).size() == 2 and names.find(String(h[0])) >= 0:
			return String(h[1])
	return ""


func _resolve_cases(spec: Dictionary, params: Dictionary) -> Dictionary:
	var cases: Array = spec.get("cases", [])
	if cases.is_empty():
		return spec
	for c in cases:
		if c is Dictionary and _matches(c.get("when", {}), params):
			var merged := spec.duplicate()
			merged.erase("cases")
			for k in c.keys():
				if k != "when":
					merged[k] = c[k]
			return merged
	return spec


func _matches(when: Dictionary, params: Dictionary) -> bool:
	for k in when.keys():
		var cond: Variant = when[k]
		var has := params.has(k)
		var v: Variant = params.get(k)
		if cond is Array and cond.size() == 2 and cond[0] is String and String(cond[0]) in [">", ">=", "<", "<=", "!=", "in"]:
			var op := String(cond[0])
			if op == "in":
				if not has or not (cond[1] as Array).has(v):
					return false
				continue
			if op == "!=":
				if has and str(v) == str(cond[1]):
					return false
				continue
			if not has:
				return false
			var f := float(v)
			var t := float(cond[1])
			if (op == ">" and not f > t) or (op == ">=" and not f >= t) or (op == "<" and not f < t) or (op == "<=" and not f <= t):
				return false
		elif not has:
			return false
		elif (cond is float or cond is int) and (v is float or v is int):
			if not is_equal_approx(float(v), float(cond)):
				return false
		elif str(v) != str(cond):
			return false
	return true


func _template(s: String, params: Dictionary) -> String:
	if s.find("{") < 0:
		return s
	for k in params.keys():
		s = s.replace("{" + String(k) + "}", str(params[k]).to_lower())
	return s


func _layer(layer: Dictionary, position: Vector3, params: Dictionary, spec: Dictionary, ev: String) -> bool:
	if not force_chance and randf() > float(layer.get("chance", 1.0)):
		return false
	var a := _audio()
	if a == null:
		return false
	params = _map_surface(params, layer.get("surface_map", {}))
	var key := _template(String(layer.get("key", "")), params)
	if key.find("{") >= 0 or not a.call("has_key", key):
		var found := false
		for fb in layer.get("fallback", []):
			var k2 := _template(String(fb), params)
			if a.call("has_key", k2):
				key = k2
				found = true
				break
		if not found:
			return false
	var now := _now()
	var lcd := float(layer.get("cooldown", 0.0))
	var lck := String(layer.get("cooldown_id", key))
	if lcd > 0.0:
		if now - float(_last_layer.get(lck, -1e9)) < lcd:
			return false
		_last_layer[lck] = now
	var delay := float(layer.get("delay", 0.0)) + randf_range(0.0, float(layer.get("delay_jitter", 0.0)))
	if delay > 0.0:
		var t := get_tree().create_timer(delay, true, false, true)
		t.timeout.connect(_play_delayed.bind(key, position, layer, params, ev, spec, _scene_id, now))
		return true
	return _play_key(key, position, layer, params, ev, spec)


## A delayed layer plays only if the scene is still the one it was scheduled in and none of its `cancel_on` events
## fired since (critique r1 QA: the death line landed after the respawn).
func _play_delayed(key: String, position: Vector3, layer: Dictionary, params: Dictionary, ev: String, spec: Dictionary,
		scene_id: int, t_sched: float) -> void:
	_watch_scene()
	if scene_id != _scene_id:
		return
	for c in layer.get("cancel_on", []):
		if float(_fired_at.get(String(c), -1e9)) >= t_sched:
			return
	_play_key(key, position, layer, params, ev, spec)


func _map_surface(params: Dictionary, m: Variant) -> Dictionary:
	if not m is Dictionary or (m as Dictionary).is_empty() or not params.has("surface"):
		return params
	var s := String(params["surface"]).to_lower()
	if not (m as Dictionary).has(s):
		return params
	var p := params.duplicate()
	p["surface"] = String((m as Dictionary)[s])
	return p


## Resolves a key template ("slide_loop_{surface}") with its fallbacks against the Audio index; "" when none exists.
func _resolve_key(tmpl: String, fallback: Array, params: Dictionary) -> String:
	var a := _audio()
	if a == null:
		return ""
	var k := _template(tmpl, params)
	if k.find("{") < 0 and a.call("has_key", k):
		return k
	for fb in fallback:
		var k2 := _template(String(fb), params)
		if k2.find("{") < 0 and a.call("has_key", k2):
			return k2
	return ""


func _play_key(key: String, position: Vector3, layer: Dictionary, params: Dictionary, ev: String, spec: Dictionary = {}) -> bool:
	var a := _audio()
	if a == null:
		return false
	var vol := float(layer.get("volume_db", 0.0))
	var vj := float(layer.get("volume_jitter_db", spec.get("volume_jitter_db", defaults.get("volume_jitter_db", 1.0))))
	vol += randf_range(-vj, vj)
	var sb: Dictionary = layer.get("volume_by", spec.get("volume_by", {}))
	if not sb.is_empty() and params.has(sb.get("param", "")):
		var r: Array = sb.get("range", [0.0, 1.0])
		var d: Array = sb.get("db", [-6.0, 0.0])
		var w := clampf(inverse_lerp(float(r[0]), float(r[1]), float(params[sb["param"]])), 0.0, 1.0)
		vol += lerpf(float(d[0]), float(d[1]), w)
	var pitch := float(layer.get("pitch", 1.0))
	var pj := float(layer.get("pitch_jitter", spec.get("pitch_jitter", defaults.get("pitch_jitter", 0.05))))
	pitch *= 1.0 + randf_range(-pj, pj)
	var pb: Dictionary = layer.get("pitch_by", spec.get("pitch_by", {}))
	if not pb.is_empty() and params.has(pb.get("param", "")):
		pitch *= minf(float(pb.get("max", 2.0)), pow(2.0, float(params[pb["param"]]) * float(pb.get("semitones", 1.0)) / 12.0))
	var positional := bool(layer.get("positional", spec.get("positional", true))) and position != Vector3.INF
	var at := position if positional else Vector3.INF
	var is_voice := bool(layer.get("voice", false))
	var is_loop := layer.has("loop_id")
	if positional and not is_loop and not _audible_at(at, layer, spec):
		return false  # critique r1: distant plays filled the 3D pool and stole audible voices
	if not is_voice and not is_loop and not bool(layer.get("allow_stack", false)):
		var gap := float(defaults.get("same_key_gap", 0.06))
		if _now() - float(_last_key.get(key, -1e9)) < gap:
			return false
		_last_key[key] = _now()
	if log_plays:
		played.append({"t": _now(), "event": ev, "key": key, "volume_db": snappedf(vol, 0.1), "pitch": snappedf(pitch, 0.001),
			"positional": positional, "voice": is_voice, "loop_id": String(layer.get("loop_id", ""))})
	if print_plays:
		print("[JuiceSfx] %.2f %s -> %s %.1f dB x%.2f%s" % [_now(), ev, key, vol, pitch, " 3D" if positional else ""])
	if is_voice:
		return _voice(a, key, int(layer.get("priority", 1)), float(layer.get("gap", defaults.get("voice_gap", 0.25))))
	if is_loop:
		return _start_loop(a, String(layer["loop_id"]), key, at, vol, pitch, layer, params)
	if not a.has_method("play_sfx"):
		return false
	var node: Variant = a.call("play_sfx", key, at, 0.0, vol)
	if node is Node:
		var n := node as Node
		n.set("pitch_scale", maxf(0.05, float(n.get("pitch_scale")) * pitch))
		if n is AudioStreamPlayer3D:
			_attenuate(n as AudioStreamPlayer3D, layer, spec)
			# the Audio pool slot is shared: put the pool's own attenuation back when this sound ends, so later direct
			# play_sfx calls do not inherit this preset (critique r1)
			var p3 := n as AudioStreamPlayer3D
			if not p3.finished.is_connected(_restore_pool_att.bind(p3)):
				p3.finished.connect(_restore_pool_att.bind(p3), CONNECT_ONE_SHOT)
	return node != null


func _restore_pool_att(p: AudioStreamPlayer3D) -> void:
	if not is_instance_valid(p) or p.playing:
		return
	p.unit_size = float(POOL_3D_DEFAULTS["unit_size"])
	p.max_distance = float(POOL_3D_DEFAULTS["max_distance"])
	p.attenuation_filter_cutoff_hz = float(POOL_3D_DEFAULTS["filter_hz"])
	p.attenuation_filter_db = float(POOL_3D_DEFAULTS["filter_db"])


func _preset(layer: Dictionary, spec: Dictionary) -> Dictionary:
	var att: Dictionary = defaults.get("attenuation", {})
	var pname := String(layer.get("attenuation", spec.get("attenuation", "default")))
	return att.get(pname, att.get("default", {}))


func _listener_pos() -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	return cam.global_position if cam != null else Vector3.INF


func _audible_at(at: Vector3, layer: Dictionary, spec: Dictionary) -> bool:
	var lp := _listener_pos()
	if lp == Vector3.INF:
		return true
	return lp.distance_to(at) <= float(_preset(layer, spec).get("max_distance", 70.0))


func _attenuate(p: AudioStreamPlayer3D, layer: Dictionary, spec: Dictionary) -> void:
	var preset := _preset(layer, spec)
	p.unit_size = float(preset.get("unit_size", 6.0))
	p.max_distance = float(preset.get("max_distance", 70.0))
	p.attenuation_filter_cutoff_hz = float(preset.get("filter_hz", 9000.0))
	p.attenuation_filter_db = float(preset.get("filter_db", -18.0))


func _voice(a: Node, key: String, priority: int, gap: float) -> bool:
	var now := _now()
	var vp: Variant = a.get("_voice")
	var voice_player: AudioStreamPlayer = vp as AudioStreamPlayer if vp is AudioStreamPlayer else null
	# A line still playing that JuiceSfx did not start (the wolf, dialogue, the narrator) outranks hero grunts:
	# only priority 4 (Mak's death call) may cut it (critique r1: Mak's hurt grunt cut the wolf's lines).
	if voice_player != null and voice_player.playing and now >= _voice_busy_until:
		if priority < int(defaults.get("external_voice_priority", 4)):
			return false
	if now < _voice_busy_until and priority <= _voice_priority:
		return false
	if key == _last_voice_key and now < _voice_busy_until + 0.6:
		return false
	if not a.has_method("play_voice"):
		return false
	a.call("play_voice", key)
	var length := 1.0
	if voice_player != null and voice_player.stream != null:
		length = voice_player.stream.get_length() / maxf(0.05, voice_player.pitch_scale)
	_voice_busy_until = now + length + gap
	_voice_priority = priority
	_last_voice_key = key
	return true


func _start_loop(a: Node, id: String, key: String, at: Vector3, vol: float, pitch: float, layer: Dictionary, params: Dictionary) -> bool:
	if _loops.has(id) and is_instance_valid(_loops[id]["player"]):
		var cur: Node = _loops[id]["player"]
		if cur.get("playing"):
			return true
		cur.queue_free()
	if not a.has_method("_stream_for"):
		return false
	var r: Dictionary = a.call("_stream_for", key)
	if r.is_empty():
		return false
	var stream: AudioStream = r["stream"]
	var entry: Dictionary = r["entry"]
	var p: Node
	if at != Vector3.INF:
		var p3 := AudioStreamPlayer3D.new()
		_attenuate(p3, layer, {})
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.set("bus", String(entry.get("bus", "SFX")))
	p.set("stream", stream)
	var target := float(entry.get("volume_db", 0.0)) + vol
	p.set("volume_db", -40.0)
	p.set("pitch_scale", maxf(0.05, pitch))
	add_child(p)
	if p is Node3D:
		(p as Node3D).global_position = at
	var length := stream.get_length() if stream != null else 0.0
	p.call("play", randf_range(0.0, length * 0.9) if bool(layer.get("random_start", false)) and length > 0.5 else 0.0)
	create_tween().tween_property(p, "volume_db", target, float(layer.get("fade_in", 0.08)))
	_loops[id] = {"player": p, "follow": params.get("node"), "max_time": float(layer.get("max_time", 30.0)), "t0": _now(), "base_db": target, "key": key}
	return true


func stop_loop(id: String, fade: float = 0.15) -> void:
	if not _loops.has(id):
		return
	var p: Node = _loops[id]["player"]
	_loops.erase(id)
	if not is_instance_valid(p):
		return
	var t := create_tween()
	t.tween_property(p, "volume_db", -50.0, maxf(0.01, fade))
	t.tween_callback(p.queue_free)


func _reset_cooldowns() -> void:
	_last_event.clear()
	_last_layer.clear()
	_last_key.clear()
	_recent.clear()
	_voice_busy_until = 0.0
	_voice_priority = 0
	_last_voice_key = ""


func stop_all_loops(fade: float = 0.2) -> void:
	for id in _loops.keys():
		stop_loop(String(id), fade)


func _process(delta: float) -> void:
	_watch_scene()
	_follow_ambience(delta)
	_pause_treatment()
	if not _paused_fx:
		_scatter(delta)
		_poll_player(delta)
		_poll_proximity(delta)
		_after_jingles()
	if _loops.is_empty():
		return
	var now := _now()
	for id in _loops.keys():
		var l: Dictionary = _loops[id]
		var f: Variant = l.get("follow")
		var p: Node = l["player"]
		if not is_instance_valid(p):
			_loops.erase(id)
			continue
		if typeof(f) == TYPE_OBJECT and not is_instance_valid(f):
			stop_loop(String(id))  # the owner was freed
			continue
		if f is Node3D and p is Node3D:
			(p as Node3D).global_position = (f as Node3D).global_position
		if now - float(l["t0"]) > float(l["max_time"]):
			stop_loop(String(id), 0.4)  # safety: a loop whose stop event never came


# =============================================================== scene, Router, music

func _watch_scene() -> void:
	if not is_inside_tree():
		return
	var cs := get_tree().current_scene
	var id := cs.get_instance_id() if cs != null else 0
	if id != _scene_id:
		_scene_id = id
		_leaving_scene = 0
		if cs != null:
			_scene_changed_at = _now()
			_amb_poll = 0.0  # poll the bed in this frame: the new world's bed replaces any old loop at once


## The Router curls the page away: when the target is another world, the music and the bed fade under the curl
## (TURN_OUT 0.85 s) instead of crossfading mid-swap (critique r1: a 15-20 LU hole at every scene swap). A
## checkpoint reload into the same world keeps both playing.
func _on_transition_started(target: String) -> void:
	var root := _world_root()
	var cur := String(root.get("world_id")) if root != null and "world_id" in root else ""
	if target != "" and target == cur:
		return
	var a := _audio()
	var fade := float(ambience.get("curl_fade_s", 1.0))
	if a != null and a.has_method("stop_music"):
		a.call("stop_music", fade)
	if bed_world != "" and target != bed_world:
		_bed_fade_all(fade)
		bed_world = ""
		_leaving_scene = _scene_id
	# r1b (QA polish): scatter tails (boss thunder), proximity loops and named loops fade with the bed under the curl,
	# so nothing of the old world carries into the title or the next world
	_fade_scatter(fade)
	for nid in _prox.keys():
		stop_loop(String(_prox[nid]), fade)
	_prox.clear()
	stop_all_loops(fade)
	_curl_sting(target)


func _fade_scatter(fade: float) -> void:
	for p in _scatter_pool:
		if is_instance_valid(p) and p.playing:
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, maxf(0.05, fade))
			t.tween_callback(p.stop)


## A short sting under the page curl into a world that has one (ambience.curl_stings): the W3 -> boss swap had 1.5 s of
## flat silence before the battle music (critique r1 QA polish).
func _curl_sting(target: String) -> void:
	var st: Variant = (ambience.get("curl_stings", {}) as Dictionary).get(target, [])
	if not st is Array:
		return
	for s in st:
		if not s is Dictionary:
			continue
		var d := float((s as Dictionary).get("delay", 0.0))
		var key := String((s as Dictionary).get("key", ""))
		var vol := float((s as Dictionary).get("volume_db", 0.0))
		if d <= 0.0:
			_sting_play(key, vol)
		else:
			get_tree().create_timer(d, true, false, true).timeout.connect(_sting_play.bind(key, vol))


func _sting_play(key: String, vol: float) -> void:
	var a := _audio()
	if a == null or not a.has_method("play_sfx") or not a.call("has_key", key):
		return
	if log_plays:
		played.append({"t": _now(), "event": "curl_sting", "key": key, "volume_db": vol, "pitch": 1.0, "positional": false, "voice": false, "loop_id": ""})
	if print_plays:
		print("[JuiceSfx] %.2f curl_sting -> %s %.1f dB" % [_now(), key, vol])
	a.call("play_sfx", key, Vector3.INF, 0.0, vol)


## Lowers the Music bus for a moment (death sting, big story beats) through this node's own Amplify effect, so it
## never fights the Audio autoload's jingle duck.
func duck_music(db: float, attack: float, hold: float, release: float) -> void:
	var fx := _bus_effect("Music", "AudioEffectAmplify", "juice_duck")
	if fx == null:
		return
	var amp := fx as AudioEffectAmplify
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(amp, "volume_db", db, maxf(0.01, attack))
	_duck_tween.tween_interval(maxf(0.0, hold))
	_duck_tween.tween_property(amp, "volume_db", 0.0, maxf(0.01, release))


## After the boss defeat: once the victory jingles are over, a calm cue replaces the stopped battle music.
func _after_jingles() -> void:
	if _boss_defeated_at < 0.0:
		return
	var a := _audio()
	if a == null:
		return
	var playing := bool(a.call("is_jingle_playing")) if a.has_method("is_jingle_playing") else false
	if playing:
		_jingle_was_playing = true
	var cfg: Dictionary = get_meta("after_jingles", {})
	var waited := _now() - _boss_defeated_at
	if (_jingle_was_playing and not playing and waited > float(cfg.get("min_s", 4.0))) or waited > float(cfg.get("max_s", 14.0)):
		_boss_defeated_at = -1.0
		var root := _world_root()
		if root != null and String(root.get("world_id")) == "BOSS" and a.has_method("play_music"):
			a.call("play_music", String(cfg.get("key", "music_hub_lively")), float(cfg.get("fade_s", 3.0)))


# =============================================================== area beds

## Area ambience beds (juice_sfx.json "ambience.worlds"). A WorldRoot without an `ambience_key` (or with an old
## single-layer loop listed in `ambience.upgrade`) gets its world's layered bed on this node's own players; an
## explicit key is respected and left to the Audio autoload. The bed holds through the scene swap (no current scene
## for a few frames) and through checkpoint reloads; it fades only when two polls in a row find no world and the
## Router is idle (title, credits). Ambience started by other code outside a world (tests, previews) is never touched.
func _follow_ambience(delta: float) -> void:
	if not ambience_follow or ambience.is_empty():
		return
	_amb_poll -= delta
	if _amb_poll > 0.0:
		return
	_amb_poll = float(ambience.get("poll_s", 0.25))
	var a := _audio()
	if a == null:
		return
	var root := _world_root()
	var busy := _router_busy()
	if root == null:
		if get_tree().current_scene == null or busy:
			return  # mid-swap: hold whatever plays
		_no_world_polls += 1
		if _no_world_polls >= 2 and bed_world != "":
			_bed_fade_all(float(ambience.get("exit_fade_s", 1.5)))
			bed_world = ""
		_apply_reverb("")
		return
	_no_world_polls = 0
	if _leaving_scene != 0 and _leaving_scene == _scene_id:
		return  # the old world is still on screen under the page curl
	var wid := String(root.get("world_id")) if "world_id" in root else ""
	var explicit := String(root.get("ambience_key")) if "ambience_key" in root else ""
	var upgrade: Array = ambience.get("upgrade", [])
	_apply_reverb(wid)
	var worlds: Dictionary = ambience.get("worlds", {})
	if (explicit != "" and not explicit in upgrade) or not worlds.has(wid):
		if bed_world != "":
			_bed_fade_all(1.5)
			bed_world = ""
		return
	# an old single loop started by the WorldRoot (the boss's amb_storm_loop): stop it, the layered bed replaces it
	var cur := String(a.get("current_ambience")) if "current_ambience" in a else ""
	if cur != "" and (cur in upgrade or cur == explicit) and a.has_method("stop_ambience"):
		a.call("stop_ambience", 0.3)
	if wid == bed_world and _bed_alive():
		return
	_start_bed(wid, worlds[wid])


func _bed_alive() -> bool:
	for b in _bed:
		var p: Variant = b.get("player")
		if is_instance_valid(p) and p is AudioStreamPlayer and (p as AudioStreamPlayer).playing:
			return true
	return false


func _start_bed(wid: String, cfg: Dictionary) -> void:
	var a := _audio()
	if a == null or not a.has_method("_stream_for"):
		return
	_bed_fade_all(float(ambience.get("crossfade_out_s", 1.2)))
	bed_world = wid
	bed_phase = int(cfg.get("start_phase", 1))
	_bed = []
	for l in cfg.get("layers", []):
		if not l is Dictionary:
			continue
		var r: Dictionary = a.call("_stream_for", String(l.get("key", "")))
		if r.is_empty():
			continue
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = r["stream"]
		p.volume_db = -80.0
		add_child(p)
		var length: float = (r["stream"] as AudioStream).get_length()
		p.play(randf_range(0.0, maxf(0.0, length - 0.5)))  # random start points decorrelate the layers per visit
		var entry: Dictionary = r["entry"]
		_bed.append({"player": p, "key": String(l["key"]), "base_db": float(entry.get("volume_db", 0.0)) + float(l.get("volume_db", 0.0)),
			"phases": l.get("phases"), "w": 0.0})
	var scat: Array = cfg.get("scatter", [])
	_scatter_t = []
	for s in scat:
		var iv: Array = (s as Dictionary).get("interval", [6.0, 14.0])
		_scatter_t.append(randf_range(float(iv[0]) * 0.3, float(iv[1])))
	if _bed_tween:
		_bed_tween.kill()
	_bed_tween = create_tween()
	_bed_tween.tween_method(_set_bed_weight, 0.0, 1.0, float(ambience.get("fade_s", 2.0)))
	if print_plays:
		print("[JuiceSfx] %.2f bed %s phase %d layers %d" % [_now(), wid, bed_phase, _bed.size()])


func _layer_phase_db(b: Dictionary) -> float:
	var ph: Variant = b.get("phases")
	if ph is Array and not (ph as Array).is_empty():
		var arr := ph as Array
		return float(arr[clampi(bed_phase - 1, 0, arr.size() - 1)])
	return 0.0


## Equal-power fade-in weight (0..1) applied to every layer of the current bed.
func _set_bed_weight(w: float) -> void:
	for b in _bed:
		b["w"] = w
		_apply_layer(b)


func _apply_layer(b: Dictionary) -> void:
	var p: Variant = b.get("player")
	if not is_instance_valid(p) or not (p is AudioStreamPlayer):
		return
	var w := float(b.get("w", 1.0))
	var pdb := _layer_phase_db(b)
	var g := sin(clampf(w, 0.0, 1.0) * PI * 0.5)
	var lin := g * db_to_linear(pdb)
	(p as AudioStreamPlayer).volume_db = float(b["base_db"]) + (-80.0 if lin <= 0.0001 else linear_to_db(lin))


func _bed_fade_all(fade: float) -> void:
	if _bed_tween:
		_bed_tween.kill()
		_bed_tween = null
	for b in _bed:
		var p: Variant = b.get("player")
		if is_instance_valid(p) and p is AudioStreamPlayer:
			var pl := p as AudioStreamPlayer
			var t := create_tween()
			# equal-power fade-out: cos curve on the linear gain
			t.tween_method(_fade_out_step.bind(pl, pl.volume_db), 0.0, 1.0, maxf(0.05, fade))
			t.tween_callback(pl.queue_free)
	_bed = []


func _fade_out_step(x: float, pl: AudioStreamPlayer, start_db: float) -> void:
	if is_instance_valid(pl):
		var c := cos(x * PI * 0.5)
		pl.volume_db = start_db + (-80.0 if c <= 0.0001 else linear_to_db(c))


func _phase_step(x: float, bb: Dictionary, d0: float, d1: float) -> void:
	var pl: Variant = bb.get("player")
	if is_instance_valid(pl) and pl is AudioStreamPlayer:
		var lin := lerpf(db_to_linear(d0), db_to_linear(d1), x) * sin(clampf(float(bb.get("w", 1.0)), 0.0, 1.0) * PI * 0.5)
		(pl as AudioStreamPlayer).volume_db = float(bb["base_db"]) + (-80.0 if lin <= 0.0001 else linear_to_db(lin))


## Boss fight: the bed's layers follow the phase (phase 1 dry wind under the sunset, rain from phase 2, the full
## storm in phase 3, calm wind after the defeat). Crossfades over `phase_fade_s`.
func set_bed_phase(p: int) -> void:
	if p == bed_phase:
		return
	var from := bed_phase
	bed_phase = p
	if print_plays:
		print("[JuiceSfx] %.2f bed phase %d -> %d" % [_now(), from, p])
	var fade := float(ambience.get("phase_fade_s", 3.0))
	for b in _bed:
		var ph: Variant = b.get("phases")
		if not ph is Array:
			continue
		var arr := ph as Array
		var d0 := float(arr[clampi(from - 1, 0, arr.size() - 1)])
		var d1 := float(arr[clampi(p - 1, 0, arr.size() - 1)])
		create_tween().tween_method(_phase_step.bind(b, d0, d1), 0.0, 1.0, fade)


## Scatter emitter: random one-shots from the world's list every few seconds, placed 15-30 m around the camera on
## this node's own 3D players (never the shared Audio pool).
func _scatter(delta: float) -> void:
	if bed_world == "" or _scatter_t.is_empty():
		return
	var cfg: Dictionary = (ambience.get("worlds", {}) as Dictionary).get(bed_world, {})
	var scat: Array = cfg.get("scatter", [])
	var a := _audio()
	if a == null or scat.size() != _scatter_t.size():
		return
	var lp := _listener_pos()
	if lp == Vector3.INF:
		return
	for i in scat.size():
		_scatter_t[i] = float(_scatter_t[i]) - delta
		if float(_scatter_t[i]) > 0.0:
			continue
		var s: Dictionary = scat[i]
		var iv: Array = s.get("interval", [6.0, 14.0])
		_scatter_t[i] = randf_range(float(iv[0]), float(iv[1]))
		var phases: Variant = s.get("phases")
		if phases is Array and not (phases as Array).has(bed_phase):
			continue
		if randf() > float(s.get("chance", 1.0)):
			continue
		var keys: Array = s.get("keys", [])
		if keys.is_empty():
			continue
		var r: Dictionary = a.call("_stream_for", String(keys[randi() % keys.size()]))
		if r.is_empty():
			continue
		var dist: Array = s.get("distance", [15.0, 30.0])
		var ang := randf() * TAU
		var d := randf_range(float(dist[0]), float(dist[1]))
		var anchor := _scatter_anchor(s, lp)
		var ag := String(s.get("anchor_group", ""))
		if anchor == Vector3.INF and ag != "" and (bool(s.get("anchor_only", false)) or get_tree().has_group(ag)):
			continue  # the world has anchors but none is near the camera: stay silent rather than plop on the summit
		var p := _scatter_pool[_scatter_next]
		_scatter_next = (_scatter_next + 1) % _scatter_pool.size()
		p.stream = r["stream"]
		p.unit_size = float(s.get("unit_size", 14.0))
		p.volume_db = float((r["entry"] as Dictionary).get("volume_db", 0.0)) + float(s.get("volume_db", -8.0)) + randf_range(-2.0, 2.0)
		var pr: Array = s.get("pitch", [0.95, 1.05])
		p.pitch_scale = randf_range(float(pr[0]), float(pr[1]))
		if anchor != Vector3.INF:
			var j := float(s.get("anchor_jitter", 2.0))
			p.global_position = anchor + Vector3(randf_range(-j, j), randf_range(0.0, j * 0.5), randf_range(-j, j))
			d = anchor.distance_to(lp)
		else:
			p.global_position = lp + Vector3(cos(ang) * d, randf_range(float(s.get("height", 3.0)) * 0.5, float(s.get("height", 3.0)) * 1.5), sin(ang) * d)
		p.play()
		if log_plays:
			played.append({"t": _now(), "event": "ambience_scatter", "key": String(keys[0]), "volume_db": snappedf(p.volume_db, 0.1),
				"pitch": snappedf(p.pitch_scale, 0.001), "positional": true, "voice": false, "loop_id": ""})
		if print_plays:
			print("[JuiceSfx] %.2f scatter %s %.1f m %.1f dB" % [_now(), String(keys[0]), d, p.volume_db])


## A random node of the entry's `anchor_group` within `max_anchor_distance` of the listener (Vector3.INF if none).
func _scatter_anchor(s: Dictionary, lp: Vector3) -> Vector3:
	var g := String(s.get("anchor_group", ""))
	if g == "" or not is_inside_tree():
		return Vector3.INF
	var maxd := float(s.get("max_anchor_distance", 40.0))
	var cands: Array = []
	for n in get_tree().get_nodes_in_group(g):
		if n is Node3D and (n as Node3D).is_inside_tree() and (n as Node3D).global_position.distance_to(lp) <= maxd:
			cands.append((n as Node3D).global_position)
	if cands.is_empty():
		return Vector3.INF
	return cands[randi() % cands.size()]


# =============================================================== space (reverb per world)

func _apply_reverb(wid: String) -> void:
	if wid == _reverb_world:
		return
	_reverb_world = wid
	var cfg: Dictionary = (ambience.get("reverb", {}) as Dictionary).get(wid, {})
	for bus in ["SFX", "Voice"]:
		var fx := _bus_effect(bus, "AudioEffectReverb", "juice_space")
		if fx == null:
			continue
		var bi := AudioServer.get_bus_index(bus)
		var idx := _effect_index(bus, fx)
		if cfg.is_empty():
			AudioServer.set_bus_effect_enabled(bi, idx, false)
			continue
		var rv := fx as AudioEffectReverb
		rv.room_size = float(cfg.get("room_size", 0.4))
		rv.damping = float(cfg.get("damping", 0.6))
		rv.predelay_msec = float(cfg.get("predelay_ms", 30.0))
		rv.predelay_feedback = float(cfg.get("predelay_feedback", 0.2))
		rv.hipass = float(cfg.get("hipass", 0.15))
		rv.spread = float(cfg.get("spread", 0.8))
		rv.dry = 1.0
		rv.wet = float(cfg.get("wet", 0.1)) * (float(cfg.get("voice_scale", 0.6)) if bus == "Voice" else 1.0)
		AudioServer.set_bus_effect_enabled(bi, idx, true)


## Finds (or adds, once, disabled for reverb) an effect this node owns on a bus. Our effects carry resource_name.
func _bus_effect(bus: String, cls: String, tag: String) -> AudioEffect:
	var bi := AudioServer.get_bus_index(bus)
	if bi < 0:
		return null
	for i in AudioServer.get_bus_effect_count(bi):
		var e := AudioServer.get_bus_effect(bi, i)
		if e != null and e.resource_name == tag:
			return e
	var fx: AudioEffect = null
	match cls:
		"AudioEffectReverb":
			fx = AudioEffectReverb.new()
		"AudioEffectAmplify":
			fx = AudioEffectAmplify.new()
		"AudioEffectLowPassFilter":
			fx = AudioEffectLowPassFilter.new()
		"AudioEffectHardLimiter":
			fx = AudioEffectHardLimiter.new()
	if fx == null:
		return null
	fx.resource_name = tag
	# insert before any limiter so the limiter stays last on the bus
	var at := AudioServer.get_bus_effect_count(bi)
	for i in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, i) is AudioEffectHardLimiter:
			at = i
			break
	if cls == "AudioEffectHardLimiter":
		at = AudioServer.get_bus_effect_count(bi)
	AudioServer.add_bus_effect(bi, fx, at)
	if cls == "AudioEffectReverb" or cls == "AudioEffectLowPassFilter":
		AudioServer.set_bus_effect_enabled(bi, _effect_index(bus, fx), false)
	return fx


func _effect_index(bus: String, fx: AudioEffect) -> int:
	var bi := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, i) == fx:
			return i
	return -1


# =============================================================== pause

## Pause menu (tree paused while the Router is idle): Music and Ambience go through a low-pass at -6 dB, and SFX
## that were playing (pool voices, loops, scatter) pause until the game resumes. Router loading pauses are skipped.
func _pause_treatment() -> void:
	if not is_inside_tree():
		return
	var want := get_tree().paused and not _router_busy() and _pause_menu_open()
	if want == _paused_fx:
		return
	_paused_fx = want
	var cfg: Dictionary = mix.get("pause", {})
	if cfg.is_empty():
		return
	for bus in ["Music", "Ambience"]:
		var lpf := _bus_effect(bus, "AudioEffectLowPassFilter", "juice_pause_lp")
		var amp := _bus_effect(bus, "AudioEffectAmplify", "juice_pause_db")
		if lpf == null or amp == null:
			continue
		(lpf as AudioEffectLowPassFilter).cutoff_hz = float(cfg.get("lowpass_hz", 900.0))
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(bus), _effect_index(bus, lpf), want)
		(amp as AudioEffectAmplify).volume_db = float(cfg.get("db", -6.0)) if want else 0.0
	if want:
		_paused_players = []
		var a := _audio()
		var pools: Array = []
		if a != null:
			for n in ["_pool2d", "_pool3d"]:
				var v: Variant = a.get(n)
				if v is Array:
					pools.append_array(v)
		for id in _loops.keys():
			pools.append(_loops[id]["player"])
		pools.append_array(_scatter_pool)
		for p in pools:
			if is_instance_valid(p) and p is Node and bool((p as Node).get("playing")) and String((p as Node).get("bus")) != "Voice":
				(p as Node).set("stream_paused", true)
				_paused_players.append(p)
	else:
		for p in _paused_players:
			if is_instance_valid(p) and p is Node:
				(p as Node).set("stream_paused", false)
		_paused_players = []


# =============================================================== player states and proximity loops

func _find_player() -> Node:
	if is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	_player_last_pos = Vector3.INF
	return _player


## Continuous player states that have no one-shot event: the wall-slide loop (volume from the fall speed), the slide
## loop (pitch and volume from the slide speed; started here for slopes too), climb steps while moving on a pole,
## and a soft pulse at one slice of cake. juice_sfx.json "states" holds the keys and ranges.
func _poll_player(delta: float) -> void:
	if states.is_empty() or delta <= 0.0:
		return
	var pl := _find_player()
	if pl == null or not pl.has_method("get_state_name") or not (pl is Node3D):
		for id in ["wall_slide", "slide"]:
			if _loops.has(id) and String(_loops[id].get("owner", "")) == "poll":
				stop_loop(id, 0.2)
		return
	var st := String(pl.call("get_state_name"))
	var pos := (pl as Node3D).global_position
	var vel := Vector3.ZERO
	if _player_last_pos != Vector3.INF:
		vel = (pos - _player_last_pos) / delta
	_player_last_pos = pos
	var a := _audio()
	if a == null:
		return
	# wall slide
	var ws: Dictionary = states.get("wall_slide", {})
	if not ws.is_empty():
		if st in ws.get("states", ["wall_slide"]):
			_state_t["ws_out"] = 0.0
			if not _loops.has("wall_slide"):
				_poll_loop_start(a, "wall_slide", String(ws["key"]))
			_modulate("wall_slide", -vel.y, ws, 1.0)
		elif _loops.has("wall_slide"):
			_state_t["ws_out"] = float(_state_t.get("ws_out", 0.0)) + delta
			if float(_state_t["ws_out"]) > float(ws.get("grace_s", 0.12)):
				stop_loop("wall_slide", 0.15)
	# slide (belly and slope)
	var sl: Dictionary = states.get("slide", {})
	if not sl.is_empty():
		if st in sl.get("states", ["belly_slide", "slope_slide"]):
			_state_t["sl_out"] = 0.0
			var surf := String(pl.get("surface")) if "surface" in pl else "grass"
			var sp := _map_surface(_world_surface({"surface": surf}), sl.get("surface_map", {}))
			var want := _resolve_key(String(sl["key"]), sl.get("fallback", []), sp)
			if want != "" and _loops.has("slide") and String(_loops["slide"].get("key", want)) != want:
				# r1b: the floor changed mid-slide (grass -> wood): crossfade to that surface's loop
				var lp0: Variant = _loops["slide"]["player"]
				var keep_db := float((lp0 as Node).get("volume_db")) if is_instance_valid(lp0) else -20.0
				stop_loop("slide", 0.12)
				_poll_loop_start(a, "slide", want)
				if _loops.has("slide") and is_instance_valid(_loops["slide"]["player"]):
					(_loops["slide"]["player"] as Node).set("volume_db", keep_db - 6.0)
			elif want != "" and not _loops.has("slide"):
				_poll_loop_start(a, "slide", want)
			_modulate("slide", Vector2(vel.x, vel.z).length(), sl, 1.0)
		elif _loops.has("slide"):
			_state_t["sl_out"] = float(_state_t.get("sl_out", 0.0)) + delta
			if float(_state_t["sl_out"]) > float(sl.get("grace_s", 0.25)):
				stop_loop("slide", 0.2)
	# pole climb steps
	var cl: Dictionary = states.get("climb", {})
	if not cl.is_empty() and st in cl.get("states", ["pole_climb"]):
		var sp := absf(vel.y)
		if sp > float(cl.get("min_speed", 0.4)):
			_state_t["climb"] = float(_state_t.get("climb", 0.0)) - delta
			if float(_state_t["climb"]) <= 0.0:
				_state_t["climb"] = float(cl.get("interval", 0.32)) * clampf(2.0 / maxf(sp, 0.5), 0.6, 1.6)
				handle(String(cl.get("event", "player_climb_step")), Vector3.INF, {"speed": sp})
	# low health pulse
	var lh: Dictionary = states.get("low_health", {})
	if not lh.is_empty():
		var hp := _health()
		if hp > 0 and hp <= int(lh.get("health_max", 1)) and st != "dead" and st != "fallout":
			_state_t["lh"] = float(_state_t.get("lh", 0.0)) - delta
			if float(_state_t["lh"]) <= 0.0:
				_state_t["lh"] = float(lh.get("interval", 3.2))
				handle(String(lh.get("event", "player_low_health")), Vector3.INF, {})
		else:
			_state_t["lh"] = float(lh.get("first_delay", 1.5))


func _poll_loop_start(a: Node, id: String, key: String) -> void:
	if _start_loop(a, id, key, Vector3.INF, -60.0, 1.0, {"fade_in": 0.01, "max_time": 120.0}, {}):
		_loops[id]["owner"] = "poll"
		var e: Dictionary = (a.call("_stream_for", key) as Dictionary).get("entry", {})
		_loops[id]["base_db"] = float(e.get("volume_db", 0.0))


## Sets a polled loop's volume and pitch from a speed (smoothed: about 80 ms to settle).
func _modulate(id: String, speed: float, cfg: Dictionary, _k: float) -> void:
	if not _loops.has(id):
		return
	var p: Variant = _loops[id]["player"]
	if not is_instance_valid(p):
		return
	var r: Array = cfg.get("speed_range", [1.0, 8.0])
	var w := clampf(inverse_lerp(float(r[0]), float(r[1]), speed), 0.0, 1.0)
	var dbr: Array = cfg.get("db", [-10.0, 0.0])
	var pr: Array = cfg.get("pitch", [1.0, 1.0])
	var target := float(_loops[id].get("base_db", 0.0)) + float(cfg.get("volume_db", 0.0)) + lerpf(float(dbr[0]), float(dbr[1]), w)
	if speed < float(r[0]) * 0.5:
		target -= float(cfg.get("still_db", 12.0))
	var cur := float((p as Node).get("volume_db"))
	(p as Node).set("volume_db", lerpf(cur, target, 0.18))
	var cp := float((p as Node).get("pitch_scale"))
	(p as Node).set("pitch_scale", lerpf(cp, lerpf(float(pr[0]), float(pr[1]), w), 0.18))


## Positional loops on nearby nodes of a group (truffle sparkle, wind-zone gusts), at most `max` per group, chosen
## by distance to the camera; they fade when the node leaves range, hides or is freed.
func _poll_proximity(delta: float) -> void:
	_prox_poll -= delta
	if proximity.is_empty() or _prox_poll > 0.0:
		return
	_prox_poll = 0.4
	var lp := _listener_pos()
	var a := _audio()
	if a == null:
		return
	var keep := {}
	if lp != Vector3.INF and bed_world != "":
		for cfg in proximity:
			if not cfg is Dictionary:
				continue
			var c: Dictionary = cfg
			var worlds: Array = c.get("worlds", [])
			if not worlds.is_empty() and not worlds.has(bed_world):
				continue
			var cands: Array = []
			for n in get_tree().get_nodes_in_group(String(c.get("group", ""))):
				if n is Node3D and (n as Node3D).is_visible_in_tree():
					var d := (n as Node3D).global_position.distance_to(lp)
					if d <= float(c.get("radius", 20.0)):
						cands.append([d, n])
			cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
			for i in mini(cands.size(), int(c.get("max", 2))):
				var n: Node3D = cands[i][1]
				var nid := n.get_instance_id()
				keep[nid] = true
				if not _prox.has(nid):
					var id := "prox_%d" % nid
					var lay := {"fade_in": 0.6, "max_time": 1e9, "attenuation": String(c.get("attenuation", "near")), "random_start": true}
					if _start_loop(a, id, String(c["key"]), n.global_position, float(c.get("volume_db", 0.0)), randf_range(0.97, 1.03), lay, {"node": n}):
						_prox[nid] = id
	for nid in _prox.keys():
		if not keep.has(nid):
			stop_loop(String(_prox[nid]), 0.6)
			_prox.erase(nid)


func _router_busy() -> bool:
	var router := get_tree().root.get_node_or_null("Router") if is_inside_tree() else null
	return router != null and "busy" in router and bool(router.get("busy"))


## Only the pause menu counts: the truffle celebration and mission select also pause the tree, and their jingle and
## sting must keep playing.
func _pause_menu_open() -> bool:
	var ui := get_tree().root.get_node_or_null("UI")
	if ui == null or not "pause_menu" in ui:
		return false
	var pm: Variant = ui.get("pause_menu")
	return is_instance_valid(pm) and pm is Node and (pm as Node).has_method("is_open") and bool((pm as Node).call("is_open"))


func _world_root() -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	if cs is WorldRoot:
		# The title screen instances the hub as a backdrop child; only a real current WorldRoot counts.
		return cs
	for c in cs.get_children():
		if c is WorldRoot:
			return c
	return null


## Mix helpers applied at runtime (bus layout stays core's): a sidechain compressor on Music keyed by Voice so
## dialogue sits on top, a limiter on SFX (stacked impacts peaked above 0 dBFS before the master, critique r1) and
## a hard limiter on Master so nothing clips.
func _apply_mix() -> void:
	if mix.is_empty():
		return
	var sc: Dictionary = mix.get("music_duck_under_voice", {})
	var mi := AudioServer.get_bus_index("Music")
	if not sc.is_empty() and mi >= 0 and AudioServer.get_bus_index(String(sc.get("sidechain", "Voice"))) >= 0:
		var found := false
		for i in AudioServer.get_bus_effect_count(mi):
			if AudioServer.get_bus_effect(mi, i) is AudioEffectCompressor:
				found = true
		if not found:
			var c := AudioEffectCompressor.new()
			c.sidechain = StringName(String(sc.get("sidechain", "Voice")))
			c.threshold = float(sc.get("threshold_db", -26.0))
			c.ratio = float(sc.get("ratio", 3.0))
			c.attack_us = float(sc.get("attack_us", 8000.0))
			c.release_ms = float(sc.get("release_ms", 350.0))
			c.gain = 0.0
			AudioServer.add_bus_effect(mi, c)
	var sl: Dictionary = mix.get("sfx_limiter", {})
	if not sl.is_empty():
		var h2 := _bus_effect("SFX", "AudioEffectHardLimiter", "juice_sfx_limiter")
		if h2 != null:
			(h2 as AudioEffectHardLimiter).ceiling_db = float(sl.get("ceiling_db", -2.0))
	var lim: Dictionary = mix.get("master_limiter", {})
	var ma := AudioServer.get_bus_index("Master")
	if not lim.is_empty() and ma >= 0:
		var has := false
		for i in AudioServer.get_bus_effect_count(ma):
			if AudioServer.get_bus_effect(ma, i) is AudioEffectHardLimiter:
				has = true
		if not has:
			var h := AudioEffectHardLimiter.new()
			h.ceiling_db = float(lim.get("ceiling_db", -0.5))
			h.pre_gain_db = float(lim.get("pre_gain_db", 0.0))
			AudioServer.add_bus_effect(ma, h)
	# create the duck and pause effects up front so the first use never edits the bus graph mid-sound
	_bus_effect("Music", "AudioEffectAmplify", "juice_duck")
	for bus in ["Music", "Ambience"]:
		_bus_effect(bus, "AudioEffectLowPassFilter", "juice_pause_lp")
		_bus_effect(bus, "AudioEffectAmplify", "juice_pause_db")
	for bus in ["SFX", "Voice"]:
		_bus_effect(bus, "AudioEffectReverb", "juice_space")
