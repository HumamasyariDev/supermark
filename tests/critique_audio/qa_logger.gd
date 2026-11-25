extends Logger
## Critique audio r1: captures engine warnings/errors (push_warning, push_error, script errors) so the audio QA
## run can attribute missing keys and load errors to the scene that was active.

var mutex := Mutex.new()
var lines: Array = []
var scene_name := ""
var t := 0.0


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array) -> void:
	mutex.lock()
	lines.append({"t": snappedf(t, 0.01), "scene": scene_name, "type": ["error", "warning", "script", "shader"][clampi(error_type, 0, 3)],
		"msg": (rationale if rationale != "" else code), "where": "%s:%d %s" % [file.get_file(), line, function]})
	mutex.unlock()


func _log_message(message: String, error: bool) -> void:
	if message.begins_with("[Audio]") or message.begins_with("[JuiceSfx]") or error:
		mutex.lock()
		lines.append({"t": snappedf(t, 0.01), "scene": scene_name, "type": "stderr" if error else "msg", "msg": message.strip_edges()})
		mutex.unlock()


func take() -> Array:
	mutex.lock()
	var out := lines.duplicate()
	mutex.unlock()
	return out
