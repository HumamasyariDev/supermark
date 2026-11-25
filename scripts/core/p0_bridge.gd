extends Node
## Optional host integration. Desktop never touches JavaScriptBridge. Diagnostic and
## practice sessions cannot submit results, even if they exercise the real ending.

var _p0: JavaScriptObject
var _normal := false
var _saw_title := false
var _saw_hub := false
var _story_boss := false
var _won := false
var _save_pending := false
var _save_after := 0


## Called by Game before its ordinary file loaders, independently of autoload order.
## Host data never replaces the desktop profile or a diagnostic profile.
static func restore_host_files(game: Node) -> void:
	if not OS.has_feature("web") or not OS.get_cmdline_user_args().is_empty():
		return
	var window := JavaScriptBridge.get_interface("window")
	if window == null or window.p0 == null or window.p0.saved == null:
		return
	var saved: Variant = window.p0.saved
	var text: String = saved if saved is String else String(JavaScriptBridge.get_interface("JSON").stringify(saved))
	if text.to_utf8_buffer().size() > 16384:
		return
	var envelope: Variant = JSON.parse_string(text)
	if not envelope is Dictionary or envelope.get("super_mak_64") != 1:
		return
	var progress: Variant = envelope.get("save")
	var preferences: Variant = envelope.get("settings")
	if not progress is Dictionary or not preferences is Dictionary:
		return
	for key in ["truffles", "pages", "unlocks", "best_times", "stats"]:
		if progress.has(key) and not progress[key] is Dictionary:
			return
	for pages: Variant in progress.get("pages", {}).values():
		if not pages is Array:
			return
	# Keep Game's migration, type checks, backups and title Continue decision intact.
	game._atomic_write(game.save_path(), JSON.stringify(progress), "")
	game._atomic_write(game.settings_path(), JSON.stringify(preferences), "")
	print("[P0Bridge] restored host save and settings")


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_normal = OS.get_cmdline_user_args().is_empty()
	Game.truffle_collected.connect(_on_truffle)
	Game.progress_saved.connect(_queue_save)
	Game.settings_saved.connect(_queue_save)
	Router.transition_started.connect(_on_transition)
	_p0 = _host()


func _process(_delta: float) -> void:
	if _save_pending and Time.get_ticks_msec() >= _save_after:
		_flush_save()
	if not _saw_title and not get_tree().get_nodes_in_group("title_screen").is_empty():
		_saw_title = true


func _queue_save() -> void:
	if OS.has_feature("web") and _normal:
		_save_pending = true


func _flush_save() -> void:
	_save_pending = false
	var host := _host()
	if host == null or host.save == null:
		return
	var text := JSON.stringify({"super_mak_64": 1, "save": Game.data, "settings": Game.settings})
	if text.to_utf8_buffer().size() > 16384:
		push_warning("[P0Bridge] save exceeds the host's 16 KB limit")
		return
	host.save(text)
	_save_after = Time.get_ticks_msec() + 1000


func _on_transition(world: String) -> void:
	if world == "HUB" and _normal and _saw_title:
		_saw_hub = true
	if world == "BOSS":
		_story_boss = _normal and _saw_hub and not Game.current_mission.to_lower().contains("practice")
	else:
		_story_boss = false


func _host() -> JavaScriptObject:
	if not OS.has_feature("web"):
		return null
	# The embedding host can install its interface after the engine starts.
	# get_interface logs an engine error for a missing name, so first inspect
	# the always-present window object to make an absent host a quiet no-op.
	var window := JavaScriptBridge.get_interface("window")
	if window == null or window.p0 == null:
		_p0 = null
		return null
	_p0 = JavaScriptBridge.get_interface("p0")
	return _p0


func _on_truffle(id: String) -> void:
	if id != "BOSS-1" or _won or not _story_boss or Game.current_world != "BOSS":
		return
	var arena := get_tree().current_scene
	if arena == null or not arena is WolfRooftop or arena.boss == null or not arena.boss.defeated:
		return
	var host := _host()
	if host != null and host.win != null:
		_won = true
		host.win()


func record_time(board: String, seconds: float) -> void:
	if not OS.has_feature("web") or not _normal or not _saw_hub or board.is_empty():
		return
	if not is_finite(seconds) or seconds <= 0.0 or Game.current_mission.to_lower().contains("practice"):
		return
	var host := _host()
	if host == null or host.score == null:
		return
	var options: JavaScriptObject = JavaScriptBridge.create_object("Object")
	options.board = board
	options.lower = true
	host.score(seconds, options)
