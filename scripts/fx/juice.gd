extends Node
## Juice autoload: semantic gameplay feedback events -> VFX, SFX, camera shake, hitstop, rumble.
##
##   Juice.event("player_land", global_position, {"impact": 9.5})
##   Juice.event("enemy_defeat", pos, {"family": "crow_bandit"})
##   Juice.event("player_slide_start", global_position, {"node": self})   # starts an attached loop
##
## Gameplay code never needs to know which effect or sound plays. Data:
##   res://scripts/fx/juice_vfx.json     (juice/VFX track) effects, scale, tint, shake, hitstop, rumble, fallback sfx
##   res://assets/audio/juice_sfx.json   (audio track, played by its JuiceSfx child node) sound layers, variants, jitter,
##                                       delay, cooldown. The `sfx` field in juice_vfx.json is only a fallback.
## The full event catalogue, params and emitters are in Docs/JUICE.md. Unknown events warn once.
##
## Common params (all optional): node (Node3D: position fallback, attach target, facing), direction (Vector3, facing
## or travel), normal (Vector3, surface normal), impact (float m/s), scale (float), kind (String), family (String),
## tint (Color), surface (String), silent (bool: skip sfx), no_vfx (bool).
## Safety: hitstop always restores Engine.time_scale (counted in unscaled time, capped at 220 ms); effects are pooled;
## a global one-shot budget drops low-priority effects; a missing camera, Audio or JSON never errors.

signal fired(event_name: String, position: Vector3, params: Dictionary)

const VFX_PATH := "res://scripts/fx/juice_vfx.json"
## Shallow walkable water (look polish 2026-10-19): footsteps and landings there splash.
const WADE := preload("res://scripts/fx/water_wade.gd")
const SFX_PATH := "res://assets/audio/juice_sfx.json"
## Audio track's player for juice_sfx.json. Installed as a child; it listens to `fired` and plays the sounds.
const SFX_SCRIPT := "res://assets/audio/juice_sfx.gd"
const FX_DIR := "res://scenes/fx/"
const MAX_ACTIVE_ONESHOTS := 72
## Juice fix r2 (perf): a hard ceiling for every priority and for attached copies; past it the oldest copy is recycled.
const HARD_MAX_ONESHOTS := 96
## Heavy events (big flashes, billboard rings, lights) fired within this window share one screen-area budget: from the
## third heavy event on, the newest copy plays "lite" (no flash sprite, no billboard ring, no light).
const HEAVY_WINDOW_MSEC := 300
const HEAVY_FULL_COPIES := 2
## Default near clamp (m) for one-shots: effects spawned closer than this to the camera shrink (overdraw guard).
const DEFAULT_NEAR_CLAMP := 2.2
const HITSTOP_MAX_MS := 220.0
const HITSTOP_TIME_SCALE := 0.04
const DEFAULT_CULL_DISTANCE := 70.0

var enabled := true
var vfx_events: Dictionary = {}
var aliases: Dictionary = {}
var defaults: Dictionary = {}
## Counters for tests and the perf overlay.
var stats := {"events": 0, "vfx": 0, "sfx": 0, "reused": 0, "dropped": 0, "culled": 0, "unknown": 0, "shakes": 0, "hitstops": 0}
## Last 64 events (name, position, params, msec) for tests and debugging.
var history: Array[Dictionary] = []

var _warned: Dictionary = {}
var _cooldowns: Dictionary = {}
var _last_sfx_key: Dictionary = {}
var _pool: Dictionary = {}
var _active := 0
var _loops: Dictionary = {}
var _host: Node3D
var _host_always: Node3D
var _scene_id := 0
var _sfx_node: Node

var _hitstop_active := false
var _hitstop_left := 0.0
var _saved_time_scale := 1.0
var _hitstop_frames := 0

var _shake_cam: Camera3D
var _shake_left := 0.0
var _shake_dur := 0.0
var _shake_amp := 0.0
var _shake_base := Vector2.ZERO
var _shake_t := 0.0
var _last_usec := 0
var _movie_fps := -1
## Juice fix r3: hitstop jitter. The hero camera advances its shake on scaled time, so it froze during every hitstop.
## Until it shakes on unscaled time (it then sets `shake_unscaled = true`), Juice jitters the active camera's
## h_offset/v_offset for the length of the freeze, from the strength of the shake that came with the hit.
var _hs_jit_amp := 0.0
var _hs_jit_cam: Camera3D
var _hs_jit_base := Vector2.ZERO
var _hs_jit_t := 0.0
var _hs_total := 0.0
## Process frame of the last firing per canonical event (suppress_after: skip duplicates such as player_hit on a
## frame where the enemy already emitted enemy_hurt).
var _last_fired: Dictionary = {}
## Prewarm: effect keys already compiled this session, the time-sliced queue and copies to hide again.
var _warmed: Dictionary = {}
var _warm_queue: Array = []
var _warm_hide: Array = []
## Live one-shots in spawn order (for recycling the oldest low-priority effect when the budget is full).
var _live: Array = []
## Idle copies kept per pool key: frequent keys keep 12 (footsteps, hits), rare celebrations 4.
var _pool_cap := {}
## Scene serial per pool key when it was last used (trim keys idle for two scenes).
var _pool_used: Dictionary = {}
var _scene_serial := 0
## Real-time msec of recent heavy events (screen-area budget).
var _heavy_times: Array[int] = []
## Frames the last hitstop held (diagnostic; the self test reads it under Movie Maker).
var last_hitstop_frames := 0
var _attached_count := 0
## Juice fix r4: the last ground surface a player event reported (player_skid and friends carry none), the delayed effect
## items (one list ticked on real time, instead of a SceneTreeTimer per item), the cooldown prune clock, threaded audio
## preloads and the screen flash overlay.
var _last_surface := ""
var _repeats: Dictionary = {}
var _attached_live: Dictionary = {}
var _delayed: Array = []
var _clock_always := 0.0
var _clock_play := 0.0
var _prune_left := 2.0
var _audio_pending: Array[String] = []
var _audio_keep: Array = []
var _audio_requested := false
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_tween: Tween
## World default surface when a floor carries no surface meta ("grass" is the player's default for an untagged floor).
const WORLD_SURFACE := {"W1": "grass", "W2": "cloud", "W3": "candy", "HUB": "wood", "BOSS": "roof"}
## Close-up puff stacks (perf critic r2): these keys shrink to 25% within 1.5 m and are skipped within 1.2 m of the lens.
const NEAR_PUFF_KEYS := ["p:defeat_poof", "s:res://scenes/fx/DustPuff.tscn", "s:res://scenes/fx/Poof.tscn"]
const PREWARM_BUDGET_USEC := 1500
## Combat effects fire in bursts (a Ham Slam into a group): keep this many idle copies compiled and pooled.
const PREWARM_COPIES := {"p:hit_spark": 3, "p:hit_spark_big": 3, "s:res://scenes/fx/FeatherBurst.tscn": 2, "p:wool_burst": 2,
	"p:acorn_pop": 3, "s:res://scenes/fx/DustPuff.tscn": 3, "p:footstep_dust": 3, "p:footstep_grass": 3, "s:res://scenes/fx/Confetti.tscn": 2}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_host = Node3D.new()
	_host.name = "FxPool"
	_host.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_host)
	_host_always = Node3D.new()
	_host_always.name = "FxPoolAlways"
	_host_always.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_host_always)
	reload()
	if ResourceLoader.exists(SFX_SCRIPT):
		var scr := load(SFX_SCRIPT) as Script
		if scr != null:
			var n: Variant = scr.new()
			if n is Node:
				_sfx_node = n
				_sfx_node.name = "JuiceSfx"
				add_child(_sfx_node)


## Re-reads both JSON tables (also usable at runtime while tuning).
func reload() -> void:
	vfx_events.clear()
	aliases.clear()
	defaults.clear()
	var v: Variant = _read_json(VFX_PATH)
	if v is Dictionary:
		vfx_events = (v as Dictionary).get("events", {})
		aliases = (v as Dictionary).get("aliases", {})
		defaults = (v as Dictionary).get("defaults", {})
	if _sfx_node != null and is_instance_valid(_sfx_node) and _sfx_node.has_method("reload"):
		_sfx_node.call("reload")


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_warning("[Juice] JSON parse error in %s line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


# ---------------------------------------------------------------- the API

func event(event_name: String, position: Vector3 = Vector3.INF, params: Dictionary = {}) -> void:
	if (event_name == "player_footstep" or event_name == "player_land") and enabled and not params.has("wade"):
		# Look polish 2026-10-19: steps and landings in shallow water (WaterWade) splash instead of thudding on grass.
		var wade := WADE.probe(get_tree(), position)
		if not wade.is_empty():
			params = params.duplicate()
			params["wade"] = wade
			params["surface"] = "water"
			var at := Vector3(position.x, float(wade["surface_y"]) + 0.02, position.z)
			if event_name == "player_footstep":
				params.erase("no_vfx")   # ripples sit at the waterline, so they never hide the legs
				position = at
			else:
				params["no_vfx"] = true
				params["silent"] = true
				event("player_wade_land", at, {"impact": params.get("impact", 0.0), "node": params.get("node"),
					"surface": "water", "wade": wade, "heavy": params.get("heavy", false)})
	fired.emit(event_name, position, params)
	stats["events"] += 1
	history.append({"name": event_name, "position": position, "params": params, "msec": Time.get_ticks_msec()})
	if history.size() > 64:
		history.pop_front()
	if not enabled:
		return
	_check_scene()
	var name := _canonical(event_name, params)
	var rp: Variant = vfx_events.get(name, {}).get("repeat")
	if rp is Dictionary:
		# Juice fix r4: consecutive repeats of one fact on one node (a grenadier blocking punch after punch) escalate:
		# params.repeat = 1, 2, 3... within the window, for by_param variants and for the sound side.
		var nd: Variant = params.get("node")
		var rk := "rep:" + name + ("#%d" % (nd as Object).get_instance_id() if nd is Object and is_instance_valid(nd) else "")
		var now_ms := Time.get_ticks_msec()
		var prev: Array = _repeats.get(rk, [0, 0])
		var cnt := int(prev[0]) + 1 if now_ms - int(prev[1]) <= int(float((rp as Dictionary).get("window", 2.5)) * 1000.0) else 1
		_repeats[rk] = [cnt, now_ms]
		params = params.duplicate()
		params["repeat"] = cnt
	var e := _resolve(name, params)
	var frame := Engine.get_process_frames()
	# Duplicate facts on one frame (player_hit after the enemy's own enemy_hurt; player_bounce after player_stomp):
	# the catalogue lists the events that already covered this one.
	var sup: Variant = e.get("suppress_after")
	_last_fired[name] = frame
	if sup is Array:
		for other in sup:
			if String(other) != name and frame - int(_last_fired.get(String(other), -100)) <= 1:
				stats["suppressed"] = int(stats.get("suppressed", 0)) + 1
				return
	var has_sfx := e.has("sfx") or _sfx_handles(event_name)
	# UI code (ui_fx.gd) plays its own sounds and marks the event; never double them or warn about them.
	if params.get("ui_sfx", false):
		params = params.duplicate()
		params["silent"] = true
		if e.is_empty():
			return
	if e.is_empty() and not has_sfx:
		stats["unknown"] += 1
		if not _warned.has(event_name):
			_warned[event_name] = true
			push_warning("[Juice] unknown event: " + event_name)
		return
	var node: Node3D = params.get("node") as Node3D if params.get("node") is Node3D else null
	var pos := position
	if pos == Vector3.INF and node != null and is_instance_valid(node) and node.is_inside_tree():
		pos = node.global_position
	# Event-level cooldown (rapid repeats, for example footsteps from several sources).
	var cd: float = float(e.get("cooldown", 0.0))
	if cd > 0.0:
		var key := name + ("#%d" % node.get_instance_id() if node != null else "")
		var now := Time.get_ticks_msec()
		if now < int(_cooldowns.get(key, 0)):
			return
		_cooldowns[key] = now + int(cd * 1000.0)
		if _cooldowns.size() > 256:
			_prune_cooldowns(now)
	if params.get("surface") is String and name.begins_with("player_") and String(params["surface"]) != "":
		_last_surface = String(params["surface"])
	var k := _scale_factor(e, params)
	if not params.get("no_vfx", false):
		_play_vfx(name, e, pos, params, node, k)
	elif e.has("impact_vfx"):
		# Juice fix r4 (critic r2: wolf, grenadier and gummy defeats passed no_vfx, so nothing marked the impact frame and the
		# enemy kit's old glints showed instead): no_vfx skips the family gag only; the impact beat still plays here.
		var e2 := e.duplicate()
		e2["vfx"] = e["impact_vfx"]
		_play_vfx(name, e2, pos, params, node, k)
	if not params.get("silent", false) and not _sfx_handles(event_name):
		_play_sfx(name, e, pos, params)
	var sh: Variant = e.get("shake")
	if sh is Array and (sh as Array).size() >= 2:
		var amp := float(sh[0]) * (k if e.get("shake_scales", true) else 1.0)
		shake(amp, float(sh[1]), pos if e.get("shake_falloff", true) else Vector3.INF)
	var hs := float(e.get("hitstop_ms", 0.0))
	if hs > 0.0:
		hitstop(hs * (clampf(k, 0.6, 1.4) if e.get("hitstop_scales", false) else 1.0))
	var ru: Variant = e.get("rumble")
	if ru is Array and (ru as Array).size() >= 3:
		rumble(float(ru[0]), float(ru[1]), float(ru[2]))
	var fv: Variant = e.get("fov")
	if fv is Array and (fv as Array).size() >= 1:
		fov_kick(float(fv[0]) * clampf(k, 0.6, 1.4), float(fv[1]) if (fv as Array).size() > 1 else 0.3, pos if e.get("shake_falloff", true) else Vector3.INF)
	var fn: Variant = e.get("flash_node")
	if fn is Array and node != null and is_instance_valid(node) and node.is_inside_tree():
		# A white silhouette flash on the target (enemy defeat: 2 frames of white before the despawn).
		FxToon.flash(node, float(fn[0]), float(fn[1]) if (fn as Array).size() > 1 else 1.0)


## Channel ownership for emitters that keep their own fallback feedback (objects, player, enemies):
## handles(event, "vfx") is true when the table spawns an effect for it, handles(event, "sfx") when the audio
## track's JuiceSfx, a same-named Audio key or this table's fallback `sfx` plays a sound for it.
## channel "shake"/"hitstop" report those too. Emitters skip only the channels Juice owns.
func handles(event_name: String, channel: String = "vfx", params: Dictionary = {}) -> bool:
	var name := _canonical(event_name, params)
	var e := _resolve(name, params)
	match channel:
		"vfx":
			if e.has("stop_loop"):
				return true
			var v: Variant = e.get("vfx", [])
			return v is Array and not (v as Array).is_empty()
		"sfx":
			return e.has("sfx") or _sfx_handles(event_name) or (name != event_name and _sfx_handles(name))
		"shake":
			return e.has("shake")
		"hitstop":
			return e.has("hitstop_ms")
	return false


## The audio track's JuiceSfx plays the layered sounds of events marked handoff "owns" (the boss's) only when Juice
## owns them; the emitters then skip their own sounds (they check handles(event, "sfx")). Juice owns every event.
func owns(_event_name: String = "") -> bool:
	return true


## Compiles every effect's particle and draw shaders once per session, invisibly, so the first real Ham Slam or truffle
## never hitches. Time-sliced: _process warms queued keys until about 1.5 ms of each frame is spent. Keys warmed once
## stay warm (the pool and the pipeline cache live in this autoload), so later scene changes cost nothing.
func prewarm(web_light_context := false) -> void:
	if OS.has_feature("web") and web_light_context:
		# Compatibility specializes draw programs for each area's lights. Reuse
		# pooled effects, but draw them in the new context before play resumes.
		_warmed.clear()
	_request_audio()
	var seen := {}
	for q in _warm_queue:
		seen[_effect_key(q)] = true
	for name in vfx_events:
		var e: Dictionary = vfx_events[name]
		var items: Array = []
		items.append_array(e.get("vfx", []))
		var bp: Variant = e.get("by_param")
		if bp is Dictionary:
			for k in bp.get("map", {}):
				items.append_array(bp["map"][k].get("vfx", []))
		var tiers: Variant = e.get("tiers")
		if tiers is Dictionary:
			for st in tiers.get("steps", []):
				items.append_array(st.get("vfx", []))
		for it in items:
			if not (it is Dictionary) or it.has("loop"):
				continue
			var key := _effect_key(it)
			if key == "" or seen.has(key) or _warmed.has(key):
				continue
			seen[key] = true
			if key.begins_with("s:"):
				# Juice fix r2: scene effects load on a worker thread; _warm_step instantiates them once loaded.
				ResourceLoader.load_threaded_request(key.substr(2), "PackedScene")
			for _c in int(PREWARM_COPIES.get(key, 1)):
				_warm_queue.append(it)


func _warm_step() -> void:
	if _warm_queue.is_empty() or not is_inside_tree():
		return
	# ROUND3: with the web engine's background linking, preparation no longer stops frames, so effects are prepared in
	# batches instead of one per frame. Their lights cast no shadows, so overlapping lights add no program variants.
	var parallel_links: bool = OS.has_feature("web") and WebRuntime.async_programs()
	if OS.has_feature("web") and not _warm_hide.is_empty() and not parallel_links:
		# Keep preparation lights from overlapping and inventing combinations
		# that no individual live effect uses.
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var t0 := Time.get_ticks_usec()
	var batch: Array = []
	var scenes_this_frame := 0
	var tries := 0
	while not _warm_queue.is_empty() and Time.get_ticks_usec() - t0 < PREWARM_BUDGET_USEC and tries < 64:
		# Shader compilation runs after this CPU budget is measured. On WebGL
		# one effect per frame is the only useful upper bound available here.
		if OS.has_feature("web") and not batch.is_empty() and not parallel_links:
			break
		tries += 1
		var it: Dictionary = _warm_queue.pop_front()
		var ek := _effect_key(it)
		if ek.begins_with("s:"):
			# At most one scene item per frame, and only once its threaded load finished (re-queued otherwise).
			var st := ResourceLoader.load_threaded_get_status(ek.substr(2))
			if scenes_this_frame >= 1 or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_warm_queue.append(it)
				continue
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(ek.substr(2))
			scenes_this_frame += 1
		var fx := _take_pooled(it, Color.WHITE, bool(it.get("pause_proof", false)))
		_warmed[_effect_key(it)] = true
		if fx == null:
			continue
		# Tiny (node scale also shrinks local-space layers, meshes and confetti cards) and hidden again after a few
		# frames: the draw compiles the pipelines, nobody sees it. Prewarm copies never count against the budget.
		fx.global_basis = Basis.IDENTITY.scaled(Vector3.ONE * 0.01)
		fx.fx_scale = 0.002
		fx.global_position = cam.global_position - cam.global_basis.z * 4.0
		fx.set_meta("prewarm", true)
		if OS.has_feature("web"):
			fx.set_meta("web_warm_process_mode", fx.process_mode)
			fx.process_mode = Node.PROCESS_MODE_ALWAYS
		_active = maxi(_active - 1, 0)
		fx.set_meta("juice_uncounted", true)
		fx.play()
		fx.remove_meta("prewarm")
		batch.append(fx)
	stats["prewarmed"] = _warmed.size()
	if not batch.is_empty():
		# Three uncapped frames can be shorter than one particle simulation tick.
		var until_ms := Time.get_ticks_msec() + 100 if OS.has_feature("web") else 0
		_warm_hide.append([Engine.get_process_frames() + 3, batch, until_ms])


func _warm_hide_step() -> void:
	var f := Engine.get_process_frames()
	while not _warm_hide.is_empty() and f >= int(_warm_hide[0][0]) and Time.get_ticks_msec() >= int(_warm_hide[0][2]):
		var entry: Array = _warm_hide.pop_front()
		for fx_v in entry[1]:
			if is_instance_valid(fx_v) and (fx_v as Node).has_meta("web_warm_process_mode"):
				fx_v.process_mode = fx_v.get_meta("web_warm_process_mode")
				fx_v.remove_meta("web_warm_process_mode")
			# Only end copies that are still the prewarm play (a live event clears juice_uncounted).
			if is_instance_valid(fx_v) and (fx_v as Node).has_meta("juice_uncounted"):
				(fx_v as FxEffect).recycle()


## True when the event has VFX or SFX data (tests and emitters can check before relying on it).
func has_event(event_name: String) -> bool:
	return vfx_events.has(event_name) or aliases.has(event_name) or _sfx_handles(event_name)


## True when the audio track's JuiceSfx (juice_sfx.json) plays this event's sound; then the fallback `sfx` field in
## juice_vfx.json is skipped so nothing doubles. JuiceSfx also plays an Audio key with the same name as the event.
func _sfx_handles(event_name: String) -> bool:
	if _sfx_node == null or not is_instance_valid(_sfx_node):
		return false
	if _sfx_node.has_method("has_event") and bool(_sfx_node.call("has_event", event_name)):
		return true
	var audio := get_node_or_null("/root/Audio")
	return audio != null and audio.has_method("has_key") and bool(audio.call("has_key", event_name))


## Stops every attached loop started for `node` (or all loops when node is null). Called automatically on scene change.
func stop_loops(node: Node = null) -> void:
	for key in _loops.keys():
		# Read as Variant: the owner (and the loop with it) may already be freed (an enemy defeated while dizzy).
		var v: Variant = _loops[key]
		if not is_instance_valid(v):
			_loops.erase(key)
			continue
		if node == null or (v as Node).get_parent() == node:
			_end_loop(key)


# ---------------------------------------------------------------- resolution

func _canonical(event_name: String, params: Dictionary) -> String:
	if vfx_events.has(event_name):
		return event_name
	# "player_jump" + {"kind": "double"} -> "player_jump_double" when that exists (checked before plain aliases).
	if params.has("kind"):
		var alt := "%s_%s" % [event_name, str(params["kind"])]
		if vfx_events.has(alt):
			return alt
		if aliases.has(alt):
			return str(aliases[alt])
	if aliases.has(event_name):
		return str(aliases[event_name])
	return event_name


func _resolve(name: String, params: Dictionary) -> Dictionary:
	if not vfx_events.has(name):
		return {}
	# Juice fix r2 (perf): the table entry itself is returned unless a by_param or tiers branch merges in (then a shallow
	# copy). Callers only read it.
	var src: Dictionary = vfx_events[name]
	if not src.has("by_param") and not src.has("tiers"):
		return src
	var e: Dictionary = src.duplicate()
	var bp: Variant = e.get("by_param")
	if bp is Dictionary:
		var val := str(params.get(bp.get("param", ""), bp.get("default", "")))
		var m: Dictionary = bp.get("map", {})
		if m.has(val):
			e.merge(m[val], true)
		elif m.has("_default"):
			e.merge(m["_default"], true)
	var tiers: Variant = e.get("tiers")
	if tiers is Dictionary:
		var v := float(params.get(tiers.get("param", ""), 0.0))
		var pick: Dictionary = {}
		for step in tiers.get("steps", []):
			if v >= float(step.get("min", 0.0)):
				pick = step
		if not pick.is_empty():
			e.merge(pick, true)
	return e


func _scale_factor(e: Dictionary, params: Dictionary) -> float:
	var k := float(params.get("scale", 1.0))
	var sb: Variant = e.get("scale_by")
	if sb is Dictionary and params.has(sb.get("param", "")):
		var v := float(params[sb["param"]])
		var a: Array = sb.get("in", [0.0, 1.0])
		var b: Array = sb.get("out", [1.0, 1.0])
		var t := clampf(inverse_lerp(float(a[0]), float(a[1]), v), 0.0, 1.0)
		k *= lerpf(float(b[0]), float(b[1]), t)
	return k


# ---------------------------------------------------------------- VFX

func _play_vfx(name: String, e: Dictionary, pos: Vector3, params: Dictionary, node: Node3D, k: float) -> void:
	var stop_id := String(e.get("stop_loop", ""))
	if stop_id != "":
		_stop_loop_for(stop_id, node)
	var list: Variant = e.get("vfx", [])
	if not (list is Array) or (list as Array).is_empty():
		return
	if pos == Vector3.INF:
		return
	var cull := float(e.get("cull_distance", defaults.get("cull_distance", DEFAULT_CULL_DISTANCE)))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.global_position.distance_to(pos) > cull:
		stats["culled"] += 1
		return
	var lite := _heavy_lite(e)
	for item_v in list:
		if not (item_v is Dictionary):
			continue
		var item: Dictionary = item_v
		if item.has("chance") and randf() > float(item["chance"]):
			continue
		if lite and not item.has("loop"):
			item = item.duplicate()
			item["lite"] = true
		var delay := float(item.get("delay", 0.0))
		if delay > 0.0:
			var always: bool = item.get("pause_proof", false)
			# Real time, like JuiceSfx's delayed layers, so a hitstop never pushes the effect away from its sound. Juice fix r4
			# (perf critic r2: SceneTreeTimer churn crept the object count): one list ticked in _process, no timer per item.
			_delayed.append([(_clock_always if always else _clock_play) + delay, always, name, item, pos, params, node, k, _scene_serial])
		else:
			_spawn_item(name, item, pos, params, node, k)


func _spawn_item(name: String, item: Dictionary, pos: Vector3, params: Dictionary, node: Node3D, k: float) -> void:
	if node != null and not is_instance_valid(node):
		node = null
	if item.get("surface", false) and item.has("preset"):
		# Juice fix r4: ground layers take the surface's colours ("land_heavy@cloud"); see FxPresetsJuice.SURFACES.
		var surf := _surface_for(params)
		if surf != "":
			item = item.duplicate()
			item["preset"] = "%s@%s" % [String(item["preset"]), surf]
	var scale_mul := float(item.get("scale", 1.0)) * (k if item.get("scales", true) else 1.0)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and pos != Vector3.INF:
		# cam_scale [ref_m, max]: far hits (the boss 15-20 m away) grow so they still read on screen.
		var cs: Variant = item.get("cam_scale")
		if cs is Array and (cs as Array).size() >= 2:
			scale_mul *= clampf(cam.global_position.distance_to(pos) / float(cs[0]), 1.0, float(cs[1]))
		# near_clamp (m): shrink within this distance of the camera so a near '!' never runs off the frame. Juice fix r2:
		# every non-attached one-shot gets DEFAULT_NEAR_CLAMP unless it sets its own (metre-scale cards at the lens).
		var nc := float(item.get("near_clamp", DEFAULT_NEAR_CLAMP if not item.get("attach", false) else 0.0))
		var ek0 := _effect_key(item)
		if ek0 in NEAR_PUFF_KEYS:
			# Juice fix r4 (perf critic r2: 4-6 puff quads over 40% of a close-up frame): puffs at the lens are skipped, and
			# shrink to 25% within 1.5 m.
			var dcam := cam.global_position.distance_to(pos)
			if dcam < 1.2:
				return
			if dcam < 1.5:
				scale_mul *= 0.25
				nc = 0.0
		if nc > 0.0:
			scale_mul *= clampf(cam.global_position.distance_to(pos) / nc, 0.4, 1.0)
		# toward_camera (m): contact sparks pull out of the target's body toward the gameplay camera (behind Mak).
		var tc := float(item.get("toward_camera", 0.0))
		if tc > 0.0:
			var contact := pos
			var to_cam := cam.global_position - pos
			if item.get("flat_toward", false):
				# Ground effects (r2): slide toward the camera along the ground so dust at Mak's feet shows past his body.
				to_cam.y = 0.0
			if to_cam.length() > tc + 0.5:
				pos += to_cam.normalized() * tc + Vector3.UP * float(item.get("lift", 0.3))
			if not item.get("flat_toward", false):
				pos = _spark_beside_target(pos, contact, node, cam)
	var tint := Color.WHITE
	if item.has("tint"):
		tint = _color(item["tint"])
	if params.get("tint") is Color and item.get("param_tint", true):
		tint = tint * (params["tint"] as Color)
	var basis := _basis_for(String(item.get("align", "none")), params, node)
	var offset := _vec3(item.get("offset", [0, 0, 0]))
	var loop_id := String(item.get("loop", ""))
	if loop_id != "":
		_start_loop(loop_id, item, node, tint, scale_mul, offset)
		return
	var attach: bool = item.get("attach", false) and node != null
	var priority := int(item.get("priority", 1))
	if not attach and _active >= MAX_ACTIVE_ONESHOTS and priority < 2 and not _recycle_oldest():
		stats["dropped"] += 1
		return
	# Hard ceiling for every priority and attached copies: recycle the oldest live copy below priority 3.
	if _active + _attached_n() >= HARD_MAX_ONESHOTS and not _recycle_oldest(3):
		stats["dropped"] += 1
		return
	var fx: FxEffect
	if attach:
		fx = _take_attached(item, tint, bool(item.get("pause_proof", false)))
		if fx == null:
			return
		if fx.get_parent() != null:
			fx.get_parent().remove_child(fx)
		node.add_child(fx)
		fx.basis = Basis.IDENTITY
		fx.position = offset
		if basis != Basis.IDENTITY:
			fx.global_basis = basis
		fx.fx_scale = scale_mul
	else:
		var pause_proof: bool = item.get("pause_proof", false)
		fx = _take_pooled(item, tint, pause_proof)
		if fx == null:
			return
		fx.global_basis = basis
		fx.fx_scale = scale_mul
		fx.global_position = pos + basis * offset
		fx.reset_physics_interpolation()
		fx.set_meta("juice_priority", priority)
		_live.append(fx)
	stats["vfx"] += 1
	fx.lite = bool(item.get("lite", false))
	_pool_used[_effect_key(item)] = _scene_serial
	fx.play()


## Juice fix r4: the surface for ground effects. The event's own `surface`, else the last one a player event reported;
## an untagged floor reports "grass", which maps to the world's own ground (W2 cloud, W3 candy, hub wood, boss roof).
func _surface_for(params: Dictionary) -> String:
	var s := String(params.get("surface", "")) if params.get("surface") is String else ""
	if s == "":
		s = _last_surface
	if s == "water" or s == "cocoa":
		return ""
	if s == "" or s == "grass":
		var g := get_node_or_null("/root/Game")
		var w := String(g.get("current_world")) if g != null else ""
		s = String(WORLD_SURFACE.get(w, "grass"))
	return s


## Juice fix r4 (critic r2: punch and kick stars sat on Mak's backpack, and hit stars covered the enemy's face). From the
## gameplay camera Mak stands between the lens and the target, so a star pulled toward the camera lands on his body.
## When the pulled spark lies within 0.6 m of the camera-to-Mak ray, it moves to the target's visible edge on the side
## away from Mak; otherwise it still shifts a little sideways so the target's face stays readable.
func _spark_beside_target(pulled: Vector3, contact: Vector3, node: Node3D, cam: Camera3D) -> Vector3:
	var mak := get_tree().get_first_node_in_group("player") as Node3D
	if mak == null or cam == null:
		return pulled
	var right := cam.global_basis.x
	var centre := contact
	var radius := 0.45
	if node != null and is_instance_valid(node) and node != mak:
		centre = node.global_position + Vector3.UP * maxf(contact.y - node.global_position.y, 0.0)
		var br: Variant = node.get("body_radius")
		if br is float or br is int:
			radius = clampf(float(br), 0.25, 1.6)
	var mak_c := mak.global_position + Vector3.UP * 0.7
	if contact.distance_to(mak_c) < 0.9 or node == mak:
		return pulled  # an effect on Mak himself (hurt, heal) stays on him
	var side := signf((centre - mak_c).dot(right))
	if is_zero_approx(side):
		side = 1.0
	var cpos := cam.global_position
	var seg := mak_c - cpos
	var t := clampf((pulled - cpos).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.6)
	var occluded := pulled.distance_to(cpos + seg * t) < 0.6 and t > 0.35
	if occluded:
		stats["spark_moved"] = int(stats.get("spark_moved", 0)) + 1
		var to_cam := (cpos - contact)
		to_cam.y = 0.0
		return contact + right * side * (radius + 0.25) + to_cam.normalized() * 0.2 + Vector3.UP * 0.1
	if node != null and is_instance_valid(node) and node != mak:
		return pulled + right * side * minf(radius * 0.5, 0.3)
	return pulled


## Juice fix r2: screen-area budget. True when this heavy event is the third (or later) heavy event inside
## HEAVY_WINDOW_MSEC: its flash sprites, billboard rings and lights are skipped (FxEffect.lite).
func _heavy_lite(e: Dictionary) -> bool:
	var sh: Variant = e.get("shake")
	var heavy := bool(e.get("heavy", false)) or (sh is Array and (sh as Array).size() >= 1 and float(sh[0]) >= 0.2)
	if not heavy:
		return false
	var now := Time.get_ticks_msec()
	while not _heavy_times.is_empty() and now - _heavy_times[0] > HEAVY_WINDOW_MSEC:
		_heavy_times.pop_front()
	_heavy_times.append(now)
	if _heavy_times.size() > HEAVY_FULL_COPIES:
		stats["lite"] = int(stats.get("lite", 0)) + 1
		return true
	return false


## Budget full: end the oldest live low-priority one-shot early instead of dropping the new (closer, newer) event.
func _recycle_oldest(below_priority: int = 2) -> bool:
	var i := 0
	while i < _live.size():
		var v: Variant = _live[i]
		if not is_instance_valid(v) or not (v as Node).visible:
			_live.remove_at(i)
			continue
		if int((v as Node).get_meta("juice_priority", 1)) < below_priority:
			_live.remove_at(i)
			(v as FxEffect).recycle()
			stats["recycled"] = int(stats.get("recycled", 0)) + 1
			return true
		i += 1
	return false


func _effect_key(item: Dictionary) -> String:
	if item.has("preset"):
		return "p:" + String(item["preset"])
	var sc := String(item.get("scene", ""))
	if sc == "":
		return ""
	return "s:" + (sc if sc.begins_with("res://") else FX_DIR + sc + ".tscn")


## Juice fix r2 (perf): tints are quantised to 8 levels per channel in the pool key, so a continuously varying tint
## (ring colours, gummy hues) can never grow the pool without bound. The copy is built with the quantised tint.
static func _quant_tint(c: Color) -> Color:
	return Color(roundf(c.r * 7.0) / 7.0, roundf(c.g * 7.0) / 7.0, roundf(c.b * 7.0) / 7.0, roundf(c.a * 7.0) / 7.0)


static func _tint_key(c: Color) -> String:
	return _quant_tint(c).to_html()


func _instantiate(item: Dictionary, tint: Color) -> FxEffect:
	var key := _effect_key(item)
	if key == "":
		return null
	var fx: FxEffect
	if key.begins_with("p:"):
		fx = FxEffect.new()
		fx.preset = key.substr(2)
	else:
		var ps := load(key.substr(2)) as PackedScene
		if ps == null:
			_warn("missing effect scene " + key.substr(2))
			return null
		var n := ps.instantiate()
		fx = n as FxEffect
		if fx == null:
			_warn("effect scene is not an FxEffect: " + key.substr(2))
			n.free()
			return null
	fx.autoplay = false
	fx.tint = _quant_tint(tint)
	if item.has("area"):
		fx.area = _vec3(item["area"])
	return fx


func _take_pooled(item: Dictionary, tint: Color, pause_proof: bool) -> FxEffect:
	var key := "%s|%s|%s" % [_effect_key(item), _tint_key(tint), pause_proof]
	var free_list: Array = _pool.get(key, [])
	while not free_list.is_empty():
		var cand: Variant = free_list.pop_back()
		if is_instance_valid(cand):
			stats["reused"] += 1
			_active += 1
			if (cand as Node).has_meta("juice_uncounted"):
				(cand as Node).remove_meta("juice_uncounted")
			return cand
	var fx := _instantiate(item, tint)
	if fx == null:
		return null
	fx.pooled = true
	fx.free_when_done = false
	fx.pause_proof = pause_proof
	(_host_always if pause_proof else _host).add_child(fx)
	fx.finished.connect(_on_pooled_done.bind(fx, key))
	_pool[key] = free_list
	if not _pool_cap.has(key):
		var ek := _effect_key(item)
		var busy := ek.contains("footstep") or ek.contains("hit_spark") or ek.contains("DustPuff") or ek.contains("acorn_pop") or ek.contains("swish")
		_pool_cap[key] = 12 if busy else 4
	_active += 1
	return fx


## Attached effects (spin trail, heal, Ham Slam twirl) are pooled too: a copy rides on params.node while it plays and
## returns to the hidden pool host when done. A copy freed with its owner simply never comes back.
func _take_attached(item: Dictionary, tint: Color, pause_proof: bool) -> FxEffect:
	var key := "%s|%s|%s|attach" % [_effect_key(item), _tint_key(tint), pause_proof]
	var free_list: Array = _pool.get(key, [])
	while not free_list.is_empty():
		var cand: Variant = free_list.pop_back()
		if is_instance_valid(cand):
			stats["reused"] += 1
			_attached_count += 1
			_attached_live[(cand as Object).get_instance_id()] = true
			return cand
	var fx := _instantiate(item, tint)
	if fx == null:
		return null
	fx.pooled = true
	fx.free_when_done = false
	fx.pause_proof = pause_proof
	fx.finished.connect(_on_attached_done.bind(fx, key))
	_pool[key] = free_list
	_attached_count += 1
	_attached_live[fx.get_instance_id()] = true
	return fx


## Juice fix r4 (perf critic r2: the attached count leaked +2 per scene change mid triple jump): a copy freed with its
## owner never emits `finished`. Live copies are tracked by instance id; freed ones are dropped from the count here.
func _attached_n() -> int:
	for id in _attached_live.keys():
		if not is_instance_id_valid(int(id)):
			_attached_live.erase(id)
			stats["attached_freed"] = int(stats.get("attached_freed", 0)) + 1
	_attached_count = _attached_live.size()
	return _attached_count


func _on_attached_done(fx: FxEffect, key: String) -> void:
	if is_instance_valid(fx):
		_attached_live.erase(fx.get_instance_id())
	_attached_count = _attached_live.size()
	if not is_instance_valid(fx):
		return
	_return_attached.call_deferred(fx, key)


func _return_attached(fx: Variant, key: String) -> void:
	if not is_instance_valid(fx):
		return
	var f := fx as FxEffect
	f.visible = false
	var host := _host_always if f.pause_proof else _host
	if f.get_parent() != host:
		if f.get_parent() != null:
			f.get_parent().remove_child(f)
		host.add_child(f)
	var free_list: Array = _pool.get(key, [])
	if free_list.size() < 4:
		free_list.append(f)
		_pool[key] = free_list
	else:
		f.queue_free()


func _on_pooled_done(fx: FxEffect, key: String) -> void:
	if not is_instance_valid(fx):
		_active = maxi(_active - 1, 0)
		return
	_live.erase(fx)
	if fx.get_meta("juice_uncounted", false):
		fx.remove_meta("juice_uncounted")
	else:
		_active = maxi(_active - 1, 0)
	var free_list: Array = _pool.get(key, [])
	if free_list.size() < int(_pool_cap.get(key, 4)):
		free_list.append(fx)
		_pool[key] = free_list
	else:
		fx.queue_free()


func _start_loop(loop_id: String, item: Dictionary, node: Node3D, tint: Color, scale_mul: float, offset: Vector3) -> void:
	if node == null:
		_warn("loop '%s' needs params.node" % loop_id)
		return
	var key := "%s#%d" % [loop_id, node.get_instance_id()]
	var existing: Variant = _loops.get(key)
	if existing != null and is_instance_valid(existing):
		(existing as FxEffect).set_active(true)
		(existing as FxEffect).set_meta("juice_ending", false)
		return
	var fx := _instantiate(item, tint)
	if fx == null:
		return
	fx.free_when_done = false
	node.add_child(fx)
	fx.position = offset
	fx.fx_scale = scale_mul
	fx.play()
	_loops[key] = fx
	if not node.tree_exiting.is_connected(_on_loop_owner_exiting):
		node.tree_exiting.connect(_on_loop_owner_exiting.bind(node.get_instance_id()), CONNECT_ONE_SHOT)
	stats["vfx"] += 1


func _on_loop_owner_exiting(owner_id: int) -> void:
	var suffix := "#%d" % owner_id
	for key in _loops.keys():
		if String(key).ends_with(suffix):
			_loops.erase(key)


func _stop_loop_for(loop_id: String, node: Node3D) -> void:
	if node == null:
		for key in _loops.keys():
			if String(key).begins_with(loop_id + "#"):
				_end_loop(key)
		return
	_end_loop("%s#%d" % [loop_id, node.get_instance_id()])


func _end_loop(key: String) -> void:
	var fx: Variant = _loops.get(key)
	_loops.erase(key)
	if fx == null or not is_instance_valid(fx):
		return
	var f := fx as FxEffect
	f.set_active(false)
	f.set_meta("juice_ending", true)
	# Let the last particles finish before freeing (bound method, no lambda capture of a node that may be freed).
	get_tree().create_timer(1.6, false).timeout.connect(_free_ended_loop.bind(f))


func _free_ended_loop(f: Variant) -> void:
	if is_instance_valid(f) and (f as Node).get_meta("juice_ending", false):
		(f as Node).queue_free()


func _basis_for(align: String, params: Dictionary, node: Node3D) -> Basis:
	match align:
		"normal":
			var n := _param_vec(params, "normal", Vector3.UP)
			if n.length_squared() < 0.0001:
				return Basis.IDENTITY
			n = n.normalized()
			var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
			var x := ref.cross(n).normalized()
			var z := x.cross(n).normalized()
			return Basis(x, n, z)
		"direction", "yaw":
			var d := _param_vec(params, "direction", Vector3.ZERO)
			if d == Vector3.ZERO and node != null and is_instance_valid(node):
				d = -node.global_basis.z
			if align == "yaw":
				d.y = 0.0
			if d.length_squared() < 0.0001:
				return Basis.IDENTITY
			d = d.normalized()
			var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.BACK
			return Basis.looking_at(d, up)
		"node":
			if node != null and is_instance_valid(node):
				return node.global_basis.orthonormalized()
	return Basis.IDENTITY


func _param_vec(params: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var v: Variant = params.get(key, fallback)
	if v is Vector3:
		return v
	return fallback


# ---------------------------------------------------------------- SFX

func _play_sfx(name: String, e: Dictionary, pos: Vector3, params: Dictionary) -> void:
	var spec: Variant = e.get("sfx")
	if spec == null:
		return
	var audio := get_node_or_null("/root/Audio")
	if audio == null:
		return
	var d := _sfx_dict(spec)
	if d.is_empty():
		return
	var cd := float(d.get("cooldown", 0.0))
	if cd > 0.0:
		var now := Time.get_ticks_msec()
		if now < int(_cooldowns.get("sfx:" + name, 0)):
			return
		_cooldowns["sfx:" + name] = now + int(cd * 1000.0)
	var at := pos if d.get("positional", true) else Vector3.INF
	if name.begins_with("ui_"):
		at = Vector3.INF
	_play_layer(name, d, at, params, audio)
	for layer_v in d.get("layers", []):
		var layer := _sfx_dict(layer_v)
		if not layer.is_empty():
			_play_layer(name, layer, at, params, audio)


func _sfx_dict(spec: Variant) -> Dictionary:
	if spec is String:
		return {"keys": [spec]}
	if spec is Array:
		return {"keys": spec}
	if spec is Dictionary:
		var d: Dictionary = spec
		if not d.has("keys"):
			if d.has("key"):
				d = d.duplicate()
				d["keys"] = [d["key"]]
			elif d.has("variants"):
				d = d.duplicate()
				d["keys"] = d["variants"]
		return d
	return {}


func _play_layer(name: String, d: Dictionary, at: Vector3, params: Dictionary, audio: Node) -> void:
	var keys: Array = d.get("keys", [])
	if keys.is_empty():
		return
	if d.has("chance") and randf() > float(d["chance"]):
		return
	var key := String(keys[0])
	if keys.size() > 1:
		var last := String(_last_sfx_key.get(name + str(keys.size()), ""))
		for _i in 4:
			key = String(keys[randi() % keys.size()])
			if key != last:
				break
		_last_sfx_key[name + str(keys.size())] = key
	var vol := float(d.get("volume_db", 0.0))
	var vj := float(d.get("volume_jitter_db", 0.0))
	if vj > 0.0:
		vol += randf_range(-vj, vj)
	var pitch := 1.0
	var pr: Variant = d.get("pitch", [1.0, 1.0])
	if pr is Array and (pr as Array).size() >= 2:
		pitch = randf_range(float(pr[0]), float(pr[1]))
	elif pr is float or pr is int:
		pitch = float(pr)
	if d.has("pitch_jitter"):
		var pj := float(d["pitch_jitter"])
		pitch *= 1.0 + randf_range(-pj, pj)
	for mod_key in ["pitch_by", "volume_by"]:
		var m: Variant = d.get(mod_key)
		if m is Dictionary and params.has(m.get("param", "")):
			var t := clampf(inverse_lerp(float(m["in"][0]), float(m["in"][1]), float(params[m["param"]])), 0.0, 1.0)
			var v := lerpf(float(m["out"][0]), float(m["out"][1]), t)
			if mod_key == "pitch_by":
				pitch *= v
			else:
				vol += v
	var delay := float(d.get("delay", 0.0))
	if delay > 0.0:
		get_tree().create_timer(delay, false).timeout.connect(_emit_sound.bind(key, at, vol, pitch, d, audio))
	else:
		_emit_sound(key, at, vol, pitch, d, audio)


func _emit_sound(key: String, at: Vector3, vol: float, pitch: float, d: Dictionary, audio: Node) -> void:
	if not is_instance_valid(audio):
		return
	stats["sfx"] += 1
	if ((key.begins_with("voice_") or key.begins_with("vo_")) and not d.get("as_sfx", false)) and audio.has_method("play_voice"):
		audio.call("play_voice", key)
		return
	if not audio.has_method("play_sfx"):
		return
	var p: Variant = audio.call("play_sfx", key, at, 0.0, vol)
	if p is Node and is_instance_valid(p) and not is_equal_approx(pitch, 1.0):
		(p as Node).set("pitch_scale", maxf(0.05, float((p as Node).get("pitch_scale")) * pitch))


# ---------------------------------------------------------------- shake, hitstop, rumble

## Camera shake. strength: 0..1 trauma-style (0.1 footstep-heavy, 0.35 Ham Slam, 1.0 boss defeat); duration in seconds.
## Calls add_shake(strength, duration) on the node in group "game_camera"; otherwise shakes the active Camera3D
## through h_offset/v_offset. `at` attenuates with distance from the camera (full within 8 m, none past 35 m).
func shake(strength: float, duration: float, at: Vector3 = Vector3.INF) -> void:
	var mult := float(_setting("screen_shake", 1.0))
	if mult <= 0.0 or strength <= 0.0 or duration <= 0.0:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if at != Vector3.INF and cam != null:
		var dist := cam.global_position.distance_to(at)
		strength *= clampf(1.0 - (dist - 8.0) / 27.0, 0.0, 1.0)
		if strength <= 0.005:
			return
	strength *= mult
	stats["shakes"] += 1
	var gc := get_tree().get_first_node_in_group("game_camera") if is_inside_tree() else null
	if gc != null and gc.has_method("add_shake"):
		gc.call("add_shake", strength, duration)
		var su: Variant = gc.get("shake_unscaled")
		if not (su is bool and su):
			_hs_jit_amp = maxf(_hs_jit_amp, strength)
		return
	if cam == null:
		return
	if _shake_cam != cam:
		_restore_shake_cam()
		_shake_cam = cam
		_shake_base = Vector2(cam.h_offset, cam.v_offset)
	_shake_amp = maxf(_shake_amp * (_shake_left / maxf(_shake_dur, 0.001)), strength)
	_shake_dur = maxf(duration, 0.05)
	_shake_left = _shake_dur


## Freezes the game for `ms` milliseconds of real time (time_scale 0.04, capped at 220 ms; Godot's process delta is not
## scaled reliably, so Juice counts wall-clock time, or fixed frames under Movie Maker). Overlapping calls extend
## to the longest end; the previous time scale is always restored, also on scene change and exit.
func hitstop(ms: float) -> void:
	if not bool(_setting("hitstop", true)) or ms <= 0.0:
		return
	ms = minf(ms, HITSTOP_MAX_MS)
	stats["hitstops"] += 1
	if not _hitstop_active:
		_saved_time_scale = Engine.time_scale
		_hitstop_active = true
		_hitstop_frames = 0
		Engine.time_scale = _saved_time_scale * HITSTOP_TIME_SCALE
	_hitstop_left = maxf(_hitstop_left, ms / 1000.0)
	_hs_total = maxf(_hs_total, _hitstop_left)


func is_hitstop_active() -> bool:
	return _hitstop_active


func end_hitstop() -> void:
	_end_hitstop_jitter()
	if _hitstop_active:
		_hitstop_active = false
		_hitstop_left = 0.0
		Engine.time_scale = _saved_time_scale


## Juice fix r3: the camera keeps jittering through a hitstop (screen-space offset, about 1.3x the hero camera's own
## shake amplitude for that strength, decaying over the freeze), then the offsets are restored exactly.
func _hitstop_jitter(real_dt: float) -> void:
	if _hs_jit_amp <= 0.0:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	if cam != _hs_jit_cam:
		_end_hitstop_jitter(false)
		if cam == _shake_cam:
			return  # the fallback shake already drives this camera's offsets
		_hs_jit_cam = cam
		_hs_jit_base = Vector2(cam.h_offset, cam.v_offset)
	_hs_jit_t += real_dt
	var k := clampf(_hitstop_left / maxf(_hs_total, 0.001), 0.0, 1.0)
	var a := _hs_jit_amp * 0.36 * (0.35 + 0.65 * k)
	_hs_jit_cam.h_offset = _hs_jit_base.x + (sin(_hs_jit_t * 71.0) + 0.5 * sin(_hs_jit_t * 113.0)) * a
	_hs_jit_cam.v_offset = _hs_jit_base.y + (sin(_hs_jit_t * 53.0 + 1.3) + 0.5 * sin(_hs_jit_t * 97.0)) * a


func _end_hitstop_jitter(clear_amp: bool = true) -> void:
	if _hs_jit_cam != null and is_instance_valid(_hs_jit_cam):
		_hs_jit_cam.h_offset = _hs_jit_base.x
		_hs_jit_cam.v_offset = _hs_jit_base.y
	_hs_jit_cam = null
	if clear_amp:
		_hs_jit_amp = 0.0
		_hs_total = 0.0


## FOV punch (juice fix r2): degrees (negative = zoom in), seconds. Calls fov_kick(deg, seconds) on the node in group
## "game_camera" when it has one (the hero track's camera merges kicks); otherwise does nothing. Attenuated with
## distance like shake and scaled by the screen_shake comfort setting.
func fov_kick(deg: float, seconds: float = 0.3, at: Vector3 = Vector3.INF) -> void:
	var mult := float(_setting("screen_shake", 1.0))
	if mult <= 0.0 or is_zero_approx(deg):
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if at != Vector3.INF and cam != null:
		deg *= clampf(1.0 - (cam.global_position.distance_to(at) - 8.0) / 27.0, 0.0, 1.0)
		if absf(deg) < 0.2:
			return
	var gc := get_tree().get_first_node_in_group("game_camera") if is_inside_tree() else null
	if gc != null and gc.has_method("fov_kick"):
		gc.call("fov_kick", deg * mult, seconds)
		stats["fov"] = int(stats.get("fov", 0)) + 1
	elif gc != null and gc.get("_fov_kick") != null:
		# Juice fix r4 stop-gap (critic r2: the FOV channel was dead in normal play, the hero camera has no fov_kick() yet):
		# write the camera's own kick term when ours is larger; mak_camera decays it (9 deg/s on its scaled delta, so the
		# punch holds through the hitstop). Remove once mak_camera.fov_kick() exists.
		var cur := float(gc.get("_fov_kick"))
		if absf(deg * mult) > absf(cur):
			gc.set("_fov_kick", deg * mult)
			stats["fov"] = int(stats.get("fov", 0)) + 1


## True when `pos` is inside the active camera's view (with a margin in NDC units). Off-screen priority events can use
## it for an edge indicator or a panned sound; the UI track's notice chevron reads it from Juice.fired.
func is_on_screen(pos: Vector3, margin: float = 0.0) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or pos == Vector3.INF:
		return true
	if cam.is_position_behind(pos):
		return false
	var sp := cam.unproject_position(pos)
	var r := get_viewport().get_visible_rect()
	var m := r.size * margin
	return sp.x >= -m.x and sp.y >= -m.y and sp.x <= r.size.x + m.x and sp.y <= r.size.y + m.y


## Controller rumble on every connected pad (weak and strong motor 0..1, seconds).
func rumble(weak: float, strong: float, duration: float) -> void:
	if not bool(_setting("rumble", true)):
		return
	for dev in Input.get_connected_joypads():
		Input.start_joy_vibration(dev, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


## Unscaled seconds since the last frame: wall clock in play; under Movie Maker the engine's fixed step divided by the
## time scale. Godot does not list engine options such as --write-movie in OS.get_cmdline_args(), so Movie Maker is
## detected through Engine.get_write_movie_path(). (Before: hitstop counted down on the wall clock while Movie Maker
## spent 50-70 ms per frame, and no capture showed a freeze.)
func _real_delta(delta: float) -> float:
	var now := Time.get_ticks_usec()
	var dt := 0.0 if _last_usec == 0 else float(now - _last_usec) / 1000000.0
	_last_usec = now
	if _movie_fps < 0:
		_movie_fps = 0
		if Engine.get_write_movie_path() != "":
			_movie_fps = int(ProjectSettings.get_setting("editor/movie_writer/fps", 60))
	if _movie_fps > 0:
		# Juice fix r2 (the video blocker): under Movie Maker every rendered frame is exactly 1/fps of video time. The
		# delta reaching _process is already unscaled there, so dividing it by the hitstop time scale hit the 0.1 s clamp
		# and every hitstop ended after one frame. Return the fixed step itself.
		return 1.0 / float(_movie_fps)
	return clampf(dt, 0.0, 0.1)


## True under Movie Maker (offline capture).
func is_movie() -> bool:
	return _movie_fps > 0


## Seconds of video per rendered frame under Movie Maker (1/fps), 0.0 in normal play. Cameras that animate on
## unscaled time use it instead of dt / time_scale while recording.
func movie_step() -> float:
	return 1.0 / float(_movie_fps) if _movie_fps > 0 else 0.0


func _process(delta: float) -> void:
	var real_dt := _real_delta(delta)
	_check_scene()
	_clock_always += real_dt
	if is_inside_tree() and not get_tree().paused:
		_clock_play += real_dt
	if not _delayed.is_empty():
		_tick_delayed()
	_prune_left -= real_dt
	if _prune_left <= 0.0:
		_prune_left = 2.0
		_prune_cooldowns(Time.get_ticks_msec())
	if not _audio_pending.is_empty():
		_audio_step()
	if not _warm_queue.is_empty():
		_warm_step()
	if not _warm_hide.is_empty():
		_warm_hide_step()
	if _hitstop_active:
		_hitstop_left -= real_dt
		_hitstop_frames += 1
		_hitstop_jitter(real_dt)
		if _hitstop_left <= 0.0:
			last_hitstop_frames = _hitstop_frames
			if is_movie():
				# Offline captures: log how many rendered frames the freeze held (evidence for the hitstop fix).
				print("[Juice] hitstop held %d movie frames (frame %d)" % [_hitstop_frames, Engine.get_frames_drawn()])
			end_hitstop()
	elif _hs_jit_amp > 0.0:
		_end_hitstop_jitter()
	if _shake_left > 0.0:
		if _shake_cam == null or not is_instance_valid(_shake_cam):
			_shake_left = 0.0
			_shake_cam = null
		else:
			_shake_left -= real_dt
			_shake_t += real_dt
			var k := clampf(_shake_left / _shake_dur, 0.0, 1.0)
			var a := _shake_amp * k * k * 0.32
			var off := Vector2(sin(_shake_t * 61.0) + 0.5 * sin(_shake_t * 97.0 + 1.7), sin(_shake_t * 53.0 + 0.9) + 0.5 * sin(_shake_t * 83.0)) * a
			_shake_cam.h_offset = _shake_base.x + off.x
			_shake_cam.v_offset = _shake_base.y + off.y
			if _shake_left <= 0.0:
				_restore_shake_cam()


func _tick_delayed() -> void:
	var i := 0
	while i < _delayed.size():
		var d: Array = _delayed[i]
		if int(d[8]) != _scene_serial:
			_delayed.remove_at(i)
			continue
		var now := _clock_always if bool(d[1]) else _clock_play
		if now >= float(d[0]):
			_delayed.remove_at(i)
			_spawn_item(String(d[2]), d[3], d[4], d[5], d[6] as Node3D if is_instance_valid(d[6]) else null, float(d[7]))
			continue
		i += 1


## Juice fix r4 (perf critic r2: the first burst of a session hitched 42-97 ms because Audio loads each file synchronously
## on its first play): every file behind a juice_sfx.json key is requested on a worker thread when prewarm runs, and the
## loaded streams are kept referenced, so Audio's own load() later is a cache hit.
func _request_audio() -> void:
	if _audio_requested:
		return
	var audio := get_node_or_null("/root/Audio")
	if audio == null:
		return
	var index: Variant = audio.get("index")
	if not (index is Dictionary) or (index as Dictionary).is_empty():
		return
	_audio_requested = true
	var keys := {}
	_collect_strings(_read_json(SFX_PATH), keys)
	var seen := {}
	for key in keys:
		var e: Variant = (index as Dictionary).get(key)
		if not (e is Dictionary) or bool((e as Dictionary).get("loop", false)):
			continue
		for f in (e as Dictionary).get("files", []):
			var path := String(f)
			if seen.has(path) or not ResourceLoader.exists(path):
				continue
			seen[path] = true
			if ResourceLoader.load_threaded_request(path, "AudioStream") == OK:
				_audio_pending.append(path)
	stats["audio_preload"] = _audio_pending.size()


func _collect_strings(v: Variant, out: Dictionary) -> void:
	if v is String:
		out[v] = true
	elif v is Array:
		for x in v:
			_collect_strings(x, out)
	elif v is Dictionary:
		for kk in v:
			_collect_strings(v[kk], out)


func _audio_step() -> void:
	var done := 0
	var i := 0
	while i < _audio_pending.size() and done < 8:
		var path := _audio_pending[i]
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			i += 1
			continue
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_audio_keep.append(ResourceLoader.load_threaded_get(path))
		_audio_pending.remove_at(i)
		done += 1
	stats["audio_preloaded"] = _audio_keep.size()


## Juice fix r4: true once every effect key is compiled and every Juice sound file is loaded. Core can hold the page-turn
## curtain until is_warm() (plus a few frames) so the first frames of a world never hitch.
func is_warm() -> bool:
	return _warm_queue.is_empty() and _warm_hide.is_empty() and _audio_pending.is_empty()


## Juice fix r4: a full-screen flash that runs on real time (a hitstop never holds it) and stays modest (D034).
## For the boss track's impact flash: Juice.screen_flash(0.5) instead of a 0.85 ColorRect tween on scaled time.
func screen_flash(peak: float = 0.5, hold: float = 0.017, fade: float = 0.08, color: Color = Color(1, 0.97, 0.9)) -> void:
	if not is_inside_tree():
		return
	if _flash_layer == null or not is_instance_valid(_flash_layer):
		_flash_layer = CanvasLayer.new()
		_flash_layer.layer = 90
		_flash_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_flash_layer)
		_flash_rect = ColorRect.new()
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_layer.add_child(_flash_rect)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color = Color(color, clampf(peak, 0.0, 0.6))
	_flash_rect.visible = true
	_flash_tween = create_tween()
	_flash_tween.set_ignore_time_scale(true)
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_interval(maxf(hold, 0.0))
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, maxf(fade, 0.016))
	_flash_tween.tween_callback(func() -> void: _flash_rect.visible = false)
	stats["screen_flash"] = int(stats.get("screen_flash", 0)) + 1


func _restore_shake_cam() -> void:
	if _shake_cam != null and is_instance_valid(_shake_cam):
		_shake_cam.h_offset = _shake_base.x
		_shake_cam.v_offset = _shake_base.y
	_shake_cam = null
	_shake_left = 0.0
	_shake_amp = 0.0


func _check_scene() -> void:
	if not is_inside_tree():
		return
	var cs := get_tree().current_scene
	var id := cs.get_instance_id() if cs != null else 0
	if id != _scene_id:
		_scene_id = id
		_on_scene_changed()


func _on_scene_changed() -> void:
	end_hitstop()
	_scene_serial += 1
	_heavy_times.clear()
	_trim_pool()
	# Juice fix r2 (perf): effect OmniLights tripled W3 GPU time in combat bursts (stepped light clusters on the W3
	# terrain); W3 uses the flash sprites without lights until a re-measure says otherwise.
	var g := get_node_or_null("/root/Game")
	FxEffect.lights_enabled = not (g != null and String(g.get("current_world")) == "W3")
	# Queue only keys never warmed this session (time-sliced in _process; in practice only the first world pays).
	if not OS.has_feature("web"):
		prewarm()
	_restore_shake_cam()
	stop_loops()
	_loops.clear()
	_live.clear()
	_delayed.clear()
	_repeats.clear()
	_end_screen_flash()
	_prune_cooldowns(Time.get_ticks_msec(), true)
	if _sfx_node != null and is_instance_valid(_sfx_node) and _sfx_node.has_method("stop_all_loops"):
		_sfx_node.call("stop_all_loops")
	# Pooled effects still flying from the previous scene are hidden; they return to the pool when done.
	for host in [_host, _host_always]:
		for c in host.get_children():
			if c is FxEffect:
				(c as FxEffect).visible = false


func _end_screen_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _flash_rect != null and is_instance_valid(_flash_rect):
		_flash_rect.visible = false


## Juice fix r2 (perf): the idle pool only grew during a session. On each scene change idle lists are trimmed to 2
## copies (busy keys 6) and keys not fired in the last two scenes are freed entirely.
func _trim_pool() -> void:
	for key in _pool.keys():
		var list: Array = _pool[key]
		var ek := String(key).get_slice("|", 0)
		var cap := 6 if int(_pool_cap.get(key, 4)) > 4 else 2
		if _scene_serial - int(_pool_used.get(ek, _scene_serial)) > 2:
			cap = 0
		while list.size() > cap:
			var v: Variant = list.pop_back()
			if is_instance_valid(v):
				(v as Node).queue_free()
		_pool[key] = list


## Drops expired cooldowns (and every per-node key on a scene change) so the table never grows with every emitter.
func _prune_cooldowns(now: int, nodes_too: bool = false) -> void:
	for key in _cooldowns.keys():
		if int(_cooldowns[key]) <= now or (nodes_too and String(key).contains("#")):
			_cooldowns.erase(key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_audio_keep.clear()
		if _hitstop_active:
			Engine.time_scale = _saved_time_scale
			_hitstop_active = false


func _setting(key: String, fallback: Variant) -> Variant:
	var g := get_node_or_null("/root/Game")
	if g != null and g.has_method("get_setting"):
		var v: Variant = g.call("get_setting", key, fallback)
		return fallback if v == null else v
	return fallback


func _warn(msg: String) -> void:
	if not _warned.has(msg):
		_warned[msg] = true
		push_warning("[Juice] " + msg)


static func _color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.html(v) if Color.html_is_valid(v) else Color.WHITE
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return Color.WHITE


static func _vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
