extends Node
const GoldenHatLib := preload("res://scripts/objects/golden_hat.gd")
## Game autoload: progress, health, checkpoints, unlocks, hats, settings and the save file.
##
## Save layout (per profile):
##   user://save.json, save.json.bak, settings.json           (default profile)
##   user://profiles/<name>/save.json ...                     (--profile=<name> dev runs)
## Saves are versioned JSON written atomically (temp file + rename) with a backup copy.
## A missing or damaged save falls back to the backup, then to a fresh game, and never crashes.
##
## Rules handled elsewhere (objects workstream) through the signals below:
##   - 100 acorns in one visit spawns a truffle: listen to `acorns_hundred(world_id)` or `acorns_changed`.
##   - 5 Lost Pages spawn a truffle: listen to `pages_completed(world_id)` or `page_collected`.

signal truffle_collected(id: String)
signal health_changed(value: int)
signal acorns_changed(value: int)
signal acorns_hundred(world_id: String)
signal page_collected(world_id: String, index: int)
signal pages_completed(world_id: String)
signal progress_saved
signal progress_loaded
signal unlocked(flag: String)
signal hat_changed(hat: String)
signal settings_changed
signal settings_saved
signal checkpoint_set(world_id: String, xform: Transform3D)
signal damaged(amount: int)
signal healed(amount: int)
signal cake_empty
signal player_respawned
signal world_changed(world_id: String)

const SAVE_VERSION := 1
const PAGES_PER_WORLD := 5
const ACORNS_FOR_TRUFFLE := 100
## "golden_top_hat" (completion pass) is the Wolf's reward: the top hat in gold (scripts/objects/golden_hat.gd).
const HATS := ["beanie", "top_hat", "golden_top_hat", "bowler", "teacosy", "deerstalker"]
## Story reward hats: wearable once their unlock flag is set AND their GLB exists (no stand-in hats).
const REWARD_HAT_MODELS := {
	"bowler": "res://assets/characters/mak/mak_bowler.glb",
	"teacosy": "res://assets/characters/mak/mak_teacosy.glb",
	"deerstalker": "res://assets/characters/mak/mak_deerstalker.glb",
}

var max_health: int = 6
var health: int = 6:
	set(v):
		var nv := clampi(v, 0, max_health)
		if nv != health:
			health = nv
			health_changed.emit(health)

## Acorns collected during the current visit (resets on entering a world).
var acorns: int = 0
var current_world: String = "":
	set(v):
		if v != current_world:
			current_world = v
			world_changed.emit(v)
var current_mission: String = ""
var profile: String = ""

## Persistent progress (saved).
var data: Dictionary = {}
## Settings (saved separately).
var settings: Dictionary = {}

var _transient_flags: Dictionary = {}  # flag -> true, never saved (see has_flag)
var _checkpoints: Dictionary = {}  # world_id -> Transform3D (per visit, not saved)
var _hundred_fired := false
var _fall_cooldown := 0.0
var _play_time_accum := 0.0
var _last_load_status := "none"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Parse --profile directly so the real save is never touched, whatever the autoload order.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			profile = a.substr(10).strip_edges()
	profile = profile.validate_filename()
	DirAccess.make_dir_recursive_absolute(_base_dir())
	settings = _default_settings()
	if OS.has_feature("web"):
		load("res://scripts/core/p0_bridge.gd").restore_host_files(self)
		_detect_graphics()
	load_settings()
	apply_settings()
	load_game()
	print("[Game] profile='%s' save=%s status=%s truffles=%d" % [profile, save_path(), _last_load_status, truffle_count()])
	# Golden Top Hat: every player that enters the tree gets the watcher that gilds its top hat while it is worn.
	get_tree().node_added.connect(_attach_golden_hat)


func _process(delta: float) -> void:
	if _fall_cooldown > 0.0:
		_fall_cooldown -= delta
	if current_world != "" and not get_tree().paused:
		_play_time_accum += delta
	if OS.has_feature("web") and current_world != "":
		_sample_fps()


# ---------------------------------------------------------------- paths

func _base_dir() -> String:
	if profile == "":
		return "user://"
	return "user://profiles/%s/" % profile


func save_path() -> String:
	return _base_dir() + "save.json"


func backup_path() -> String:
	return _base_dir() + "save.json.bak"


func settings_path() -> String:
	return _base_dir() + "settings.json"


func last_load_status() -> String:
	return _last_load_status


# ---------------------------------------------------------------- progress data

func _fresh_data() -> Dictionary:
	var now := Time.get_datetime_string_from_system(true)
	return {
		"version": SAVE_VERSION,
		"created": now,
		"updated": now,
		"truffles": {},
		"pages": {},
		"unlocks": {},
		"hat": "beanie",
		"acorns_total": 0,
		"best_times": {},
		"last_world": "",
		"play_time": 0.0,
		"stats": {"deaths": 0, "falls": 0},
	}


func new_game() -> void:
	data = _fresh_data()
	acorns = 0
	health = max_health
	_checkpoints.clear()
	current_world = ""
	current_mission = ""
	save_game()


func has_save() -> bool:
	return FileAccess.file_exists(save_path()) or FileAccess.file_exists(backup_path())


func has_progress() -> bool:
	return has_save() and (truffle_count() > 0 or float(data.get("play_time", 0.0)) > 1.0 or String(data.get("last_world", "")) != "")


# ---------------------------------------------------------------- truffles

func collect_truffle(id: String) -> void:
	if id == "":
		return
	var t: Dictionary = data.get("truffles", {})
	var is_new := not t.has(id)
	t[id] = {"utc": Time.get_datetime_string_from_system(true)} if is_new else t[id]
	data["truffles"] = t
	print("[Game] truffle ", id, " new=", is_new, " total=", truffle_count())
	truffle_collected.emit(id)
	save_game()


func has_truffle(id: String) -> bool:
	return data.get("truffles", {}).has(id)


func truffle_count() -> int:
	return data.get("truffles", {}).size()


func world_truffle_count(world_id: String) -> int:
	var n := 0
	for id in data.get("truffles", {}).keys():
		if String(id).begins_with(world_id + "-"):
			n += 1
	return n


# ---------------------------------------------------------------- acorns and health

func add_acorns(n: int = 1) -> void:
	## Adds acorns for this visit. Each acorn also restores one cake slice (DESIGN_V2).
	if n <= 0:
		return
	acorns += n
	data["acorns_total"] = int(data.get("acorns_total", 0)) + n
	acorns_changed.emit(acorns)
	heal(n)
	if acorns >= ACORNS_FOR_TRUFFLE and not _hundred_fired:
		_hundred_fired = true
		acorns_hundred.emit(current_world)


func spend_acorns(n: int) -> bool:
	if n > acorns:
		return false
	acorns -= n
	acorns_changed.emit(acorns)
	return true


func heal(n: int = 1) -> void:
	if n <= 0 or health >= max_health:
		return
	var before := health
	health = health + n
	if health > before:
		healed.emit(health - before)


func damage(n: int = 1) -> void:
	if n <= 0 or health <= 0:
		return
	health = health - n
	damaged.emit(n)
	if health <= 0:
		data["stats"]["deaths"] = int(data.get("stats", {}).get("deaths", 0)) + 1
		cake_empty.emit()
		# No lives and no game over: refill the cake and go back to the bookmark.
		get_tree().create_timer(0.9, true).timeout.connect(func() -> void:
			respawn_player()
			health = max_health)


func full_heal() -> void:
	health = max_health


# ---------------------------------------------------------------- pages

func collect_page(world_id: String, page_index: int) -> void:
	var pages: Dictionary = data.get("pages", {})
	var arr: Array = pages.get(world_id, [])
	if not arr.has(page_index):
		arr.append(page_index)
		arr.sort()
	pages[world_id] = arr
	data["pages"] = pages
	page_collected.emit(world_id, page_index)
	if arr.size() >= PAGES_PER_WORLD:
		pages_completed.emit(world_id)
	save_game()


func has_page(world_id: String, page_index: int) -> bool:
	return Array(data.get("pages", {}).get(world_id, [])).has(page_index)


func page_count(world_id: String) -> int:
	return Array(data.get("pages", {}).get(world_id, [])).size()


# ---------------------------------------------------------------- checkpoints and respawn

func set_checkpoint(world_id: String, xform: Transform3D) -> void:
	_checkpoints[world_id] = xform
	checkpoint_set.emit(world_id, xform)


func has_checkpoint(world_id: String = "") -> bool:
	return _checkpoints.has(world_id if world_id != "" else current_world)


func get_checkpoint(world_id: String = "") -> Variant:
	## Returns a Transform3D, or null when no bookmark has been set this visit.
	return _checkpoints.get(world_id if world_id != "" else current_world, null)


func clear_checkpoints() -> void:
	_checkpoints.clear()


func player_fell_out() -> void:
	if _fall_cooldown > 0.0:
		return
	_fall_cooldown = 1.0
	data["stats"]["falls"] = int(data.get("stats", {}).get("falls", 0)) + 1
	if health > 1:
		health = health - 1
		damaged.emit(1)
	else:
		health = max_health
	respawn_player()


func respawn_player() -> void:
	var world := get_world_root()
	if world and world.has_method("respawn_player"):
		world.respawn_player()
	else:
		var p := get_tree().get_first_node_in_group("player")
		var cp: Variant = get_checkpoint()
		if p and p.has_method("respawn"):
			p.respawn(cp if cp is Transform3D else Transform3D(Basis(), Vector3(0, 1, 0)))
	player_respawned.emit()


func get_world_root() -> Node:
	var scene := get_tree().current_scene
	if scene and scene.has_method("respawn_player") and "world_id" in scene:
		return scene
	return null


## Called by the Router when a world visit starts.
func begin_visit(world_id: String, mission_id: String = "") -> void:
	current_world = world_id
	current_mission = mission_id
	acorns = 0
	_hundred_fired = false
	acorns_changed.emit(acorns)
	health = max_health
	_checkpoints.clear()
	if world_id != "HUB" and world_id != "":
		data["last_world"] = world_id


func end_visit() -> void:
	acorns = 0
	_hundred_fired = false
	acorns_changed.emit(acorns)
	_checkpoints.clear()
	current_mission = ""


# ---------------------------------------------------------------- unlocks and hats

func unlock(flag: String) -> void:
	var u: Dictionary = data.get("unlocks", {})
	if u.has(flag):
		return
	u[flag] = true
	data["unlocks"] = u
	unlocked.emit(flag)
	save_game()


## Story flags as the hub scripts read them (HubKit.flag). Same as the saved unlocks, plus transient
## flags that are never saved: the title backdrop marks "hub_intro_seen" while it builds the hub so the
## Wolf intro never plays behind the logo (critique UI r1 blocker); New Game then plays it for real.
func has_flag(flag: String) -> bool:
	return _transient_flags.has(flag) or data.get("unlocks", {}).has(flag)


func set_transient_flag(flag: String, on: bool) -> void:
	if on:
		_transient_flags[flag] = true
	else:
		_transient_flags.erase(flag)


func is_unlocked(flag: String) -> bool:
	if debug_unlock_all():
		return true
	return data.get("unlocks", {}).has(flag)


func debug_unlock_all() -> bool:
	var dev := get_node_or_null("/root/Dev")
	return dev != null and dev.has_method("has_arg") and dev.has_arg("unlock-all")


## True when a book (or the boss door) is open: by truffle threshold, unlock flag or --unlock-all.
func is_book_open(world_id: String) -> bool:
	if debug_unlock_all() or is_unlocked("book_" + world_id):
		return true
	var need := WorldRegistry.truffles_required(world_id)
	return need >= 0 and truffle_count() >= need


func get_hat() -> String:
	# Finish pass (UI usability major: the Wardrobe said "beanie worn, top hat locked" while Mak wore the top hat).
	# Hero v2 wears the top hat unless the beanie was chosen on purpose (same rule as MakPlayer._resolve_saved_hat).
	var h := String(data.get("hat", "beanie"))
	if h == "beanie" and not bool(data.get("hat_explicit", false)):
		return "top_hat"
	return h


func available_hats() -> Array:
	# The top hat is Mak's default (hero v2), so it is always available; the beanie is the alternate.
	var out := ["top_hat", "beanie"]
	if is_unlocked("golden_top_hat"):
		out.append("golden_top_hat")
	for h in REWARD_HAT_MODELS.keys():
		if (is_unlocked("hat_" + h) or is_unlocked(h)) and ResourceLoader.exists(REWARD_HAT_MODELS[h]):
			out.append(h)
	return out


func set_hat(hat: String) -> void:
	if not available_hats().has(hat):
		return
	if hat == get_hat():
		return
	data["hat"] = hat
	data["hat_explicit"] = true
	hat_changed.emit(hat)
	save_game()


func _attach_golden_hat(n: Node) -> void:
	if n is CharacterBody3D and n.has_signal("hat_changed") and n.get_node_or_null("GoldenHat") == null:
		var w := GoldenHatLib.new()
		w.name = "GoldenHat"
		n.add_child.call_deferred(w)


func cycle_hat() -> String:
	var hats := available_hats()
	var i := hats.find(get_hat())
	set_hat(hats[(i + 1) % hats.size()])
	return get_hat()


# ---------------------------------------------------------------- time trials

func record_time(key: String, seconds: float) -> bool:
	## Stores a best time; returns true if it is a new record.
	if OS.has_feature("web"):
		P0Bridge.record_time(key, seconds)
	var bt: Dictionary = data.get("best_times", {})
	var prev := float(bt.get(key, INF))
	if seconds < prev:
		bt[key] = seconds
		data["best_times"] = bt
		save_game()
		return true
	return false


func best_time(key: String) -> float:
	return float(data.get("best_times", {}).get(key, INF))


# ---------------------------------------------------------------- save / load

func save_game() -> bool:
	if data.is_empty():
		data = _fresh_data()
	data["version"] = SAVE_VERSION
	data["updated"] = Time.get_datetime_string_from_system(true)
	data["play_time"] = float(data.get("play_time", 0.0)) + _play_time_accum
	_play_time_accum = 0.0
	var ok := _atomic_write(save_path(), JSON.stringify(data, "\t"), backup_path())
	if ok:
		progress_saved.emit()
	else:
		push_warning("[Game] save failed: " + save_path())
	return ok


func load_game() -> bool:
	var primary: Variant = _read_json(save_path())
	if primary is Dictionary:
		data = _migrate(primary)
		_last_load_status = "ok"
	else:
		var backup: Variant = _read_json(backup_path())
		if backup is Dictionary:
			data = _migrate(backup)
			_last_load_status = "recovered_from_backup" if FileAccess.file_exists(save_path()) else "backup_only"
			push_warning("[Game] save missing or damaged; recovered from backup")
			if FileAccess.file_exists(save_path()):
				_quarantine(save_path())
			_atomic_write(save_path(), JSON.stringify(data, "\t"), "")
		else:
			if FileAccess.file_exists(save_path()):
				push_warning("[Game] save damaged and no usable backup; starting fresh (damaged file kept)")
				_quarantine(save_path())
				_last_load_status = "damaged_reset"
			else:
				_last_load_status = "fresh"
			data = _fresh_data()
			progress_loaded.emit()
			return false
	progress_loaded.emit()
	return true


func _migrate(d: Dictionary) -> Dictionary:
	var fresh := _fresh_data()
	var v := int(d.get("version", 0))
	if v > SAVE_VERSION:
		push_warning("[Game] save version %d is newer than %d; loading known fields only" % [v, SAVE_VERSION])
	# v0 -> v1: truffles may have been an Array of ids.
	if d.get("truffles") is Array:
		var t := {}
		for id in d["truffles"]:
			t[String(id)] = {"utc": ""}
		d["truffles"] = t
	for k in fresh.keys():
		if not d.has(k) or typeof(d[k]) != typeof(fresh[k]):
			if not (typeof(fresh[k]) == TYPE_FLOAT and typeof(d.get(k)) == TYPE_INT):
				d[k] = fresh[k]
	for k in fresh["stats"].keys():
		if not d["stats"].has(k):
			d["stats"][k] = fresh["stats"][k]
	# JSON numbers come back as floats; normalise page indices.
	var pages: Dictionary = d["pages"]
	for w in pages.keys():
		var arr: Array = []
		for i in pages[w]:
			arr.append(int(i))
		pages[w] = arr
	if not HATS.has(String(d["hat"])):
		d["hat"] = "beanie"
	d["version"] = SAVE_VERSION
	return d


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[Game] JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data if json.data is Dictionary else null


func _atomic_write(path: String, text: String, backup: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[Game] cannot open temp file %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# Verify the temp file before replacing anything.
	var check := FileAccess.get_file_as_string(tmp)
	if check.length() != text.length():
		push_warning("[Game] temp file verification failed: " + tmp)
		return false
	var abs_path := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	if backup != "" and FileAccess.file_exists(path):
		var abs_bak := ProjectSettings.globalize_path(backup)
		# Only back up a save that still parses, so a damaged file never overwrites a good backup.
		if _read_json(path) is Dictionary:
			if FileAccess.file_exists(backup):
				DirAccess.remove_absolute(abs_bak)
			DirAccess.copy_absolute(abs_path, abs_bak)
	var err := DirAccess.rename_absolute(abs_tmp, abs_path)
	if err != OK:
		# Some platforms refuse to rename over an existing file.
		DirAccess.remove_absolute(abs_path)
		err = DirAccess.rename_absolute(abs_tmp, abs_path)
	return err == OK


func _quarantine(path: String) -> void:
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".damaged_" + stamp))


func delete_save() -> void:
	for p in [save_path(), backup_path()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	data = _fresh_data()


# ---------------------------------------------------------------- settings

## Actions whose controller button can be rebound in Settings (stick axes stay fixed).
const PAD_REBINDABLE_ACTIONS := ["jump", "attack", "crouch", "interact", "sniff", "cam_center", "pause"]
const REBINDABLE_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch", "attack", "interact", "sniff", "cam_center", "pause"]


func _default_settings() -> Dictionary:
	return {
		"version": 1,
		"master_volume": 0.5,  # owner fix 2026-10-19: default loudness halved (0.5 linear = -6 dB on the Master bus)
		"music_volume": 0.8,
		"sfx_volume": 0.9,
		"voice_volume": 1.0,
		"ambience_volume": 0.8,
		"mouse_sensitivity": 1.0,
		"gamepad_sensitivity": 1.0,
		"invert_x": false,
		"invert_y": false,
		"fullscreen": false,
		"vsync": true,
		"classic_textures": true,  # RetroLook (scripts/fx/retro_look.gd) reads it live; Settings > Display toggles it
		"soft_shadows": true,  # soft sun shadows (scripts/fx/soft_shadows.gd via RetroLook); Settings > Display > Shadows: Soft / Off
		"graphics": "",  # Round 4, web only: "" follows the device check, "high" (Full) or "low" (Light: no dynamic shadows); Settings > Display > Graphics
		"bindings": {},  # action -> physical keycode (int) for the primary keyboard key
		"pad_bindings": {},  # action -> JoyButton index (int) for the primary controller button
	}


func get_setting(key: String, default_value: Variant = null) -> Variant:
	# Round 4: the Light level draws without dynamic shadows (the blob-only look); the saved Shadows choice stays.
	if key == "soft_shadows" and low_graphics():
		return false
	return settings.get(key, default_value)


func set_setting(key: String, value: Variant, persist: bool = true) -> void:
	settings[key] = value
	apply_settings()
	settings_changed.emit()
	if persist:
		save_settings()


func load_settings() -> void:
	var d: Variant = _read_json(settings_path())
	if d is Dictionary:
		for k in d.keys():
			if settings.has(k) and (typeof(d[k]) == typeof(settings[k]) or (typeof(settings[k]) == TYPE_FLOAT and typeof(d[k]) == TYPE_INT)):
				settings[k] = d[k]


func save_settings() -> bool:
	var ok := _atomic_write(settings_path(), JSON.stringify(settings, "\t"), "")
	if ok:
		settings_saved.emit()
	return ok


func apply_settings() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("apply_volumes"):
		audio.apply_volumes()
	var headless := DisplayServer.get_name() == "headless"
	var dev := get_node_or_null("/root/Dev")
	var test_run: bool = dev != null and dev.has_method("is_test_run") and dev.is_test_run()
	if not headless and not test_run:
		var want_fs := bool(settings.get("fullscreen", false))
		var mode := DisplayServer.window_get_mode()
		var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	if OS.has_feature("web"):
		_apply_graphics()
	_apply_bindings()


# ---------------------------------------------------------------- graphics level (Round 4, web only)

## Light level for slower devices: no dynamic shadows. A browser on an integrated or software GPU, with four cores or
## fewer, or with 4 GB of memory or less starts on it; so does one that keeps missing 24 FPS at the Full level (moved
## between areas, see settle_graphics). The player's own choice ("high" or "low") always wins. The desktop build is
## never affected.
const SLOW_FPS := 24.0
const SLOW_SAMPLES := 20
var graphics_device := ""
var _auto_low := false
var _fps_samples: Array[float] = []
var _fps_at := 0
var _atlas_size := 0


func low_graphics() -> bool:
	if not OS.has_feature("web"):
		return false
	var choice := String(settings.get("graphics", ""))
	return choice == "low" or (choice == "" and _auto_low)


## Light draws without dynamic shadows (the blob-only look; get_setting reports Shadows off), so the shadow maps shrink
## to almost nothing: in the hub that is 541 draw calls instead of 2,145 and 138 FPS instead of 90 on the review PC.
## A lower 3D render scale was measured and rejected: the web renderer's scaled path cost about 15 ms a frame
## (HUB 90 -> 38 FPS at 50 %). Full keeps the published look with a 4096 sun atlas (was 8192: the blurred soft shadows
## look the same and the web saves 96 MB of video memory; a one-page A/B showed the same frame rate).
func _apply_graphics() -> void:
	var low := low_graphics()
	get_viewport().positional_shadow_atlas_size = 512 if low else 2048
	var atlas := 1024 if low else 4096
	if atlas != _atlas_size:
		_atlas_size = atlas
		RenderingServer.directional_shadow_atlas_set_size(atlas, true)


## The device check, once at start: the GPU the browser names, its cores and memory.
func _detect_graphics() -> void:
	var navigator := JavaScriptBridge.get_interface("navigator")
	if navigator == null:
		return
	var cores := int(navigator.hardwareConcurrency) if navigator.hardwareConcurrency != null else 0
	var memory := float(navigator.deviceMemory) if navigator.deviceMemory != null else 0.0
	graphics_device = _gpu_name()
	var name := graphics_device.to_lower()
	var weak_gpu := RegEx.create_from_string("swiftshader|llvmpipe|softpipe|basic render|intel|mali|adreno|powervr|radeon\\(tm\\) graphics|radeon graphics|vega \\d+ graphics").search(name) != null
	if name.contains("arc"):
		weak_gpu = false  # Intel Arc is a discrete card
	_auto_low = weak_gpu or (cores > 0 and cores <= 4) or (memory > 0.0 and memory <= 4.0)
	# Reviews pin the level: --graphics=low or --graphics=high.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--graphics="):
			_auto_low = a.substr(11) == "low"
	print("[Game] graphics: %s (gpu '%s', %d cores, %s GB)" % ["light" if _auto_low else "full", graphics_device, cores, memory if memory > 0.0 else "?"])


func _gpu_name() -> String:
	var document := JavaScriptBridge.get_interface("document")
	var canvas: JavaScriptObject = document.getElementById("canvas") if document != null else null
	var gl: JavaScriptObject = canvas.getContext("webgl2") if canvas != null else null
	if gl == null:
		return ""
	var info: JavaScriptObject = gl.getExtension("WEBGL_debug_renderer_info")
	var value: Variant = gl.getParameter(info.UNMASKED_RENDERER_WEBGL) if info != null else gl.getParameter(gl.RENDERER)
	return String(value) if value != null else ""


## Frame rate during play (not paused, not between areas, at least 5 s after an area opened), one sample a second.
func _sample_fps() -> void:
	var now := Time.get_ticks_msec()
	if now < _fps_at:
		return
	_fps_at = now + 1000
	var router := get_node_or_null("/root/Router")
	if get_tree().paused or (router != null and bool(router.call("is_transitioning"))):
		_fps_samples.clear()
		_fps_at = now + 5000
		return
	_fps_samples.append(Engine.get_frames_per_second())
	if _fps_samples.size() > SLOW_SAMPLES:
		_fps_samples.pop_front()


## Router calls this behind the chapter page, before the next area loads: an automatic Full level that kept missing
## SLOW_FPS moves to Light, so the next area is built light from the start. Returns true when it switched.
func settle_graphics() -> bool:
	if not OS.has_feature("web") or String(settings.get("graphics", "")) != "" or _auto_low or _fps_samples.size() < SLOW_SAMPLES:
		return false
	var sorted := _fps_samples.duplicate()
	sorted.sort()
	if sorted[sorted.size() / 2] >= SLOW_FPS:
		return false
	_auto_low = true
	_fps_samples.clear()
	print("[Game] graphics: light after a median of %.1f FPS at the full level" % sorted[sorted.size() / 2])
	apply_settings()
	settings_changed.emit()
	return true


func _apply_bindings() -> void:
	var b: Dictionary = settings.get("bindings", {})
	for action in b.keys():
		if OS.has_feature("web") and int(b[action]) == KEY_ESCAPE:
			continue
		if InputMap.has_action(action):
			_replace_primary_key(action, int(b[action]))
	var pb: Dictionary = settings.get("pad_bindings", {})
	for action in pb.keys():
		# Pause stays on Start/Back (critique UI r1: a face-button Pause pushed Interact onto Start)
		if action == "pause" or int(pb[action]) == JOY_BUTTON_START or int(pb[action]) == JOY_BUTTON_BACK:
			continue
		if InputMap.has_action(action):
			_replace_primary_pad(action, int(pb[action]))


## Controller rebinding: replaces the action's first joypad button (trigger axes are kept).
## No duplicates: when another rebindable action already owns the button, it takes this action's old one.
func rebind_pad(action: String, button_index: int) -> void:
	if action == "pause" or button_index == JOY_BUTTON_START or button_index == JOY_BUTTON_BACK:
		return
	var old_btn := primary_pad_button(action)
	var pb: Dictionary = settings.get("pad_bindings", {})
	if old_btn >= 0 and old_btn != button_index:
		for other in PAD_REBINDABLE_ACTIONS:
			if other != action and other != "pause" and primary_pad_button(other) == button_index:
				pb[other] = old_btn
				_replace_primary_pad(other, old_btn)
	pb[action] = button_index
	settings["pad_bindings"] = pb
	_replace_primary_pad(action, button_index)
	settings_changed.emit()
	save_settings()


func primary_pad_button(action: String) -> int:
	if not InputMap.has_action(action):
		return -1
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return ev.button_index
	return -1


func _replace_primary_pad(action: String, button_index: int) -> void:
	var first: InputEventJoypadButton = null
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			first = ev
			break
	if first:
		InputMap.action_erase_event(action, first)
	var e := InputEventJoypadButton.new()
	e.button_index = button_index as JoyButton
	e.device = -1
	var rest := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	# keyboard and mouse first (menus show them), then the new pad button, then the rest
	for ev in rest:
		if ev is InputEventKey or ev is InputEventMouseButton:
			InputMap.action_add_event(action, ev)
	InputMap.action_add_event(action, e)
	for ev in rest:
		if not (ev is InputEventKey or ev is InputEventMouseButton):
			InputMap.action_add_event(action, ev)


func rebind_key(action: String, physical_keycode: int) -> void:
	if OS.has_feature("web") and physical_keycode == KEY_ESCAPE:
		return
	var b: Dictionary = settings.get("bindings", {})
	b[action] = physical_keycode
	settings["bindings"] = b
	_replace_primary_key(action, physical_keycode)
	settings_changed.emit()
	save_settings()


func reset_bindings() -> void:
	settings["bindings"] = {}
	settings["pad_bindings"] = {}
	var controls := get_node_or_null("/root/Controls")
	if controls and "defaults" in controls:
		for action in REBINDABLE_ACTIONS:
			if not InputMap.has_action(action):
				continue
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey or ev is InputEventJoypadButton:
					InputMap.action_erase_event(action, ev)
			for ev in controls.defaults.get(action, []):
				if ev is InputEventKey or ev is InputEventJoypadButton:
					InputMap.action_add_event(action, ev)
	settings_changed.emit()
	save_settings()


func primary_key(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	return 0


func primary_key_name(action: String) -> String:
	var k := primary_key(action)
	if k == 0:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				return ["", "Left Mouse", "Right Mouse", "Middle Mouse"][clampi(ev.button_index, 0, 3)]
		return "-"
	return OS.get_keycode_string(k if OS.has_feature("web") else DisplayServer.keyboard_get_keycode_from_physical(k))


func _replace_primary_key(action: String, physical_keycode: int) -> void:
	var events := InputMap.action_get_events(action)
	var first_key: InputEventKey = null
	for ev in events:
		if ev is InputEventKey:
			first_key = ev
			break
	var e := InputEventKey.new()
	e.physical_keycode = physical_keycode as Key
	if first_key:
		InputMap.action_erase_event(action, first_key)
	# Keep the new primary key first so menus show it.
	var rest := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, e)
	for ev in rest:
		InputMap.action_add_event(action, ev)
