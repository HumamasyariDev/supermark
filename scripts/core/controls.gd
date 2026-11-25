extends Node
## Controls autoload: default input map, created at runtime so it can be rebound and saved.
## Action names are a contract (Docs/TECH_CONTRACT.md); add new ones, never rename.

const DEADZONE := 0.2

## action -> list of default events
var defaults := {
	"move_left": [_key(KEY_A), _joy_axis(JOY_AXIS_LEFT_X, -1.0)],
	"move_right": [_key(KEY_D), _joy_axis(JOY_AXIS_LEFT_X, 1.0)],
	"move_forward": [_key(KEY_W), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)],
	"move_back": [_key(KEY_S), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)],
	"cam_left": [_key(KEY_LEFT), _joy_axis(JOY_AXIS_RIGHT_X, -1.0)],
	"cam_right": [_key(KEY_RIGHT), _joy_axis(JOY_AXIS_RIGHT_X, 1.0)],
	"cam_up": [_key(KEY_UP), _joy_axis(JOY_AXIS_RIGHT_Y, -1.0)],
	"cam_down": [_key(KEY_DOWN), _joy_axis(JOY_AXIS_RIGHT_Y, 1.0)],
	"jump": [_key(KEY_SPACE), _joy_button(JOY_BUTTON_A)],
	"crouch": [_key(KEY_SHIFT), _key(KEY_CTRL), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
	"attack": [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_J), _joy_button(JOY_BUTTON_X)],
	"interact": [_key(KEY_E), _joy_button(JOY_BUTTON_Y)],
	"sniff": [_key(KEY_Q), _mouse(MOUSE_BUTTON_RIGHT), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)],
	"cam_center": [_key(KEY_TAB), _mouse(MOUSE_BUTTON_MIDDLE), _joy_button(JOY_BUTTON_LEFT_SHOULDER)],
	"reset_checkpoint": [_key(KEY_R)],
	"pause": [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START), _joy_button(JOY_BUTTON_BACK)],
	"ui_accept_game": [_key(KEY_ENTER), _key(KEY_SPACE), _joy_button(JOY_BUTTON_A)],
	"ui_back_game": [_key(KEY_ESCAPE), _key(KEY_BACKSPACE), _joy_button(JOY_BUTTON_B)],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		defaults["pause"][0] = _key(KEY_P)
		# Project 0 reserves Escape only. Enter keeps its desktop confirm binding.
		defaults["ui_back_game"].erase(defaults["ui_back_game"][0])
	for action in defaults:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		if InputMap.action_get_events(action).is_empty():
			for ev in defaults[action]:
				InputMap.action_add_event(action, ev)
	_ensure_pad_ui()
	if OS.has_feature("web"):
		for action in InputMap.get_actions():
			for event in InputMap.action_get_events(action):
				if event is InputEventKey and (event.keycode == KEY_ESCAPE \
					or event.physical_keycode == KEY_ESCAPE):
					InputMap.action_erase_event(action, event)
		# Backspace is the advertised cancel key inside the platform iframe.
		for action in ["ui_cancel", "ui_back_game"]:
			var events := InputMap.action_get_events(action)
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, _key(KEY_BACKSPACE))
			for event in events:
				if not (event is InputEventKey and event.physical_keycode == KEY_BACKSPACE):
					InputMap.action_add_event(action, event)


## Godot 4.7's built-in ui_accept / ui_cancel carry no joypad events (critique UI r1 blocker):
## controller A must press menu buttons and B must back out. Idempotent.
func _ensure_pad_ui() -> void:
	var wanted := {
		"ui_accept": [JOY_BUTTON_A],
		"ui_cancel": [JOY_BUTTON_B],
		"ui_up": [JOY_BUTTON_DPAD_UP],
		"ui_down": [JOY_BUTTON_DPAD_DOWN],
		"ui_left": [JOY_BUTTON_DPAD_LEFT],
		"ui_right": [JOY_BUTTON_DPAD_RIGHT],
	}
	for action: String in wanted:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		for button: int in wanted[action]:
			var has := false
			for ev in InputMap.action_get_events(action):
				if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
					has = true
			if not has:
				InputMap.action_add_event(action, _joy_button(button as JoyButton))
	# critique UI r1 re-run: Backspace backs out of pause and settings, like Escape (key captures in
	# Settings read raw keys before ui_cancel, so Backspace can still be bound there).
	var has_bs := false
	for ev in InputMap.action_get_events("ui_cancel"):
		if ev is InputEventKey and ((ev as InputEventKey).physical_keycode == KEY_BACKSPACE or (ev as InputEventKey).keycode == KEY_BACKSPACE):
			has_bs = true
	if not has_bs:
		InputMap.action_add_event("ui_cancel", _key(KEY_BACKSPACE))


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e
