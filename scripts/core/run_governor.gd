extends Node
## RunGovernor autoload (registered first): caps concurrent game instances on this machine.
## Added by the integration owner after two RAM exhaustions grew the page file until the disk filled:
## each Forward+ game instance with a world loaded commits about 4-5 GB, and several agents launch
## Godot directly. The cap applies to every instance started from the project folder (editor binary),
## however it was launched; exported release builds and the editor itself are never affected.
## Slots are directories under game/.godot_slots/game/ (mkdir is atomic). A holder refreshes its pid
## file every 5 s; a slot is reclaimed only when its heartbeat is older than 20 s AND tasklist confirms
## the process is gone (OS.is_process_running only knows this instance's own children on Windows).
## After 45 minutes of waiting an instance proceeds anyway.

const DEFAULT_SLOTS := 2
const MAX_WINDOWED_WAITERS := 2
const WAIT_LIMIT_MS := 45 * 60 * 1000
const HEARTBEAT_S := 5.0
const STALE_S := 20

var _slot_dir := ""
var _beat := 0.0
var _background := false


func _init() -> void:
	if Engine.is_editor_hint() or OS.has_feature("template"):
		return
	var root := ProjectSettings.globalize_path("res://").path_join(".godot_slots/game")
	if DirAccess.make_dir_recursive_absolute(root) != OK and not DirAccess.dir_exists_absolute(root):
		return
	var slots := DEFAULT_SLOTS
	var env := OS.get_environment("SUPERMAK_GAME_SLOTS")
	if env.is_valid_int():
		slots = maxi(1, env.to_int())
	var start := Time.get_ticks_msec()
	var announced := false
	# Waiting costs memory for a windowed instance (its GPU context already exists), so only runs started by
	# tools/godot.py (which caps its own queue) and headless runs wait. A direct windowed launch gets one try.
	var headless := DisplayServer.get_name() == "headless"
	var token := OS.get_environment("SUPERMAK_WRAPPER_SLOT")
	var slotted := token == "2"  # launched by tools/godot.py while holding a run slot (at most 2 machine-wide)
	# Hard cap: windowed instances never wait inside Godot (each holds a GPU context, ~1 GB); tools/godot.py retries
	# refused launches from its own lightweight process. Only headless runs (about 0.07 GB while waiting) queue here.
	var may_wait := headless
	# Background mode (owner uses the PC): windowed runs must come from tools/godot.py, which puts them on a hidden desktop.
	var bg_flag := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("tools/.owner_using_pc")
	if FileAccess.file_exists(bg_flag) and not headless and not slotted and not ("--remote-debug" in OS.get_cmdline_args()):
		printerr("[RunGovernor] REFUSED (background mode: the owner is using the PC). Direct windowed Godot launches are not allowed now. Use `python tools/godot.py run|capture|movie ...`, which runs the game on a hidden desktop.")
		OS.delay_msec(100)
		OS.kill(OS.get_process_id())
		return
	# Windowed waiters each hold a GPU context (~0.9 GB): at most MAX_WINDOWED_WAITERS may queue.
	var wait_root := root.get_base_dir().path_join("wait")
	var wait_marker := ""
	if may_wait and not headless and not slotted:
		DirAccess.make_dir_recursive_absolute(wait_root)
		var live := 0
		for f in DirAccess.get_files_at(wait_root):
			var wpid := f.to_int()
			if wpid > 0 and _pid_alive(wpid):
				live += 1
			else:
				DirAccess.remove_absolute(wait_root.path_join(f))
		if live >= MAX_WINDOWED_WAITERS:
			may_wait = false
		else:
			wait_marker = wait_root.path_join(str(OS.get_process_id()))
			var wf := FileAccess.open(wait_marker, FileAccess.WRITE)
			if wf:
				wf.close()
	while true:
		for i in slots:
			var d := root.path_join("s%d" % i)
			if DirAccess.make_dir_absolute(d) == OK:
				_write_pid(d)
				_slot_dir = d
				if wait_marker != "":
					DirAccess.remove_absolute(wait_marker)
				if announced:
					print("[RunGovernor] slot %d acquired after %.0f s" % [i, (Time.get_ticks_msec() - start) / 1000.0])
				return
			_reclaim_if_stale(d)
		if not may_wait:
			if wait_marker != "":
				DirAccess.remove_absolute(wait_marker)
			printerr("[RunGovernor] REFUSED: this machine is at its memory cap (%d game instances running). This direct Godot launch exits now. Re-run it through `python tools/godot.py run|capture|movie ...` (from the entity folder), which waits for a free slot safely." % slots)
			OS.delay_msec(200)
			OS.kill(OS.get_process_id())
			return
		if not announced:
			print("[RunGovernor] all %d game slots busy on this machine; waiting (memory cap)..." % slots)
			announced = true
		if Time.get_ticks_msec() - start > WAIT_LIMIT_MS:
			print("[RunGovernor] waited 45 minutes; continuing without a slot")
			if wait_marker != "":
				DirAccess.remove_absolute(wait_marker)
			return
		OS.delay_msec(2000)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_background_mode()


## While the owner uses the PC (flag file <entity>/tools/.owner_using_pc), agent-launched game windows stay off-screen,
## never take focus and are muted. Editor play runs (--remote-debug), exported builds and headless runs are untouched.
func _apply_background_mode() -> void:
	if Engine.is_editor_hint() or OS.has_feature("template") or DisplayServer.get_name() == "headless":
		return
	if "--remote-debug" in OS.get_cmdline_args():
		return
	var flag := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("tools/.owner_using_pc")
	if not FileAccess.file_exists(flag):
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-32000, -32000))
	AudioServer.set_bus_mute(0, true)
	_background = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[RunGovernor] background mode: window at %s, focus disabled, muted, mouse never captured" % DisplayServer.window_get_position())


func _process(delta: float) -> void:
	if _background and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # never hold the owner's cursor while he uses the PC
	if _slot_dir == "":
		return
	_beat += delta
	if _beat >= HEARTBEAT_S:
		_beat = 0.0
		_write_pid(_slot_dir)


func _write_pid(d: String) -> void:
	var f := FileAccess.open(d.path_join("pid"), FileAccess.WRITE)
	if f:
		f.store_string(str(OS.get_process_id()))
		f.close()


func _reclaim_if_stale(d: String) -> void:
	var pid_path := d.path_join("pid")
	var now := Time.get_unix_time_from_system()
	if FileAccess.file_exists(pid_path):
		var age := now - FileAccess.get_modified_time(pid_path)
		if age < STALE_S:
			return
		var pid := FileAccess.get_file_as_string(pid_path).strip_edges().to_int()
		if pid > 0 and _pid_alive(pid):
			return
	else:
		var t := FileAccess.get_modified_time(d)
		if t <= 0 or now - t < 60:
			return
	_remove_slot(d)


func _pid_alive(pid: int) -> bool:
	var out: Array = []
	var code := OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH"], out, false, false)
	if code != 0 or out.is_empty():
		return true
	for token in String(out[0]).split(" ", false):
		if token == str(pid):
			return true
	return false


func _remove_slot(d: String) -> void:
	DirAccess.remove_absolute(d.path_join("pid"))
	DirAccess.remove_absolute(d)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		if _slot_dir != "":
			_remove_slot(_slot_dir)
			_slot_dir = ""
