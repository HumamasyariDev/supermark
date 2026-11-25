extends SceneTree
## Prints the ui_* InputMap events (critique probe).
func _initialize() -> void:
	for a in ["ui_accept", "ui_cancel", "ui_select", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next"]:
		var s: Array = []
		for e in InputMap.action_get_events(a):
			s.append(e.as_text() + " dev=" + str(e.device))
		print("[Probe] ", a, " -> ", s)
	quit()
