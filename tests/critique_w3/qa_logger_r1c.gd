extends Logger
## Critique W3 r1c (QA lens): writes every engine message, warning and error to <qa-out>/full_log.txt, because
## tools/godot.py keeps only the last 400 output lines and the RetroLook error flood pushes the game lines out.

var mutex := Mutex.new()
var f: FileAccess


func open(path: String) -> void:
	f = FileAccess.open(path, FileAccess.WRITE)


func _w(s: String) -> void:
	mutex.lock()
	if f:
		f.store_line(s)
		f.flush()
	mutex.unlock()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array) -> void:
	_w("%s: %s @ %s:%d %s" % [["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)], rationale if rationale != "" else code, file, line, function])


func _log_message(message: String, error: bool) -> void:
	_w(("STDERR " if error else "") + message.strip_edges(false, true))
