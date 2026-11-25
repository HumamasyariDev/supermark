class_name UIFx
extends RefCounted
## UI feedback helpers: menu sounds with fallbacks, Juice ui_* events and shared UI textures.
##
## Every UI action calls UIFx.event("ui_<name>", {...}). It plays the mapped UI sound (the UI owns
## its sounds) and emits Juice.event(name, Vector3.INF, params) with params["ui_sfx"] = true, so the
## juice track can add screen-level feedback (rumble, post-fx pulses) without double sounds.
## Event names: ui_move, ui_accept, ui_back, ui_open, ui_close, ui_pause, ui_resume, ui_book_open,
## ui_book_close, ui_mission_choose, ui_dialog_open, ui_dialog_advance, ui_dialog_close, ui_text_blip,
## ui_banner, ui_toast, ui_truffle_get, ui_truffle_count, ui_acorn_count, ui_cake_lose, ui_cake_gain,
## ui_cake_low, ui_page_popup, ui_timer_start, ui_timer_tick, ui_timer_end, ui_hat_change,
## ui_boss_bar_show, ui_boss_hit, ui_settings_change, ui_title_start, ui_new_game.

const TEX := {
	"truffle": "res://assets/ui/icon_truffle.png",
	"acorn": "res://assets/ui/icon_acorn.png",
	"page": "res://assets/ui/icon_page.png",
	"cake": "res://assets/ui/icon_cake.png",
	"cake_plate": "res://assets/ui/icon_cake_plate.png",
	"cake_slice": "res://assets/ui/icon_cake_slice.png",
	"parchment": "res://assets/ui/parchment_panel.png",
	"logo": "res://assets/ui/logo.png",
	"cover_W1": "res://assets/ui/cover_three_little_pigs.png",
	"cover_W2": "res://assets/ui/cover_beanstalk.png",
	"cover_W3": "res://assets/ui/cover_hansel_gretel.png",
}

## UI event -> [audio key candidates (first existing wins), volume offset dB, pitch jitter]
const SOUNDS := {
	"ui_move": [["ui_move"], 0.0, 0.04],
	"ui_accept": [["ui_accept", "ui_select"], 0.0, 0.02],
	"ui_back": [["ui_back"], 0.0, 0.02],
	"ui_open": [["ui_open", "ui_select"], -2.0, 0.02],
	"ui_close": [["ui_close", "ui_back"], -2.0, 0.02],
	"ui_pause": [["ui_pause", "book_open"], -4.0, 0.0],
	"ui_resume": [["ui_resume", "ui_back"], -2.0, 0.0],
	"ui_book_open": [["ui_book_open", "book_open"], 0.0, 0.0],
	"ui_book_close": [["ui_book_close", "book_page_turn"], -2.0, 0.03],
	"ui_mission_choose": [["ui_confirm", "ui_accept"], 0.0, 0.0],
	"ui_dialog_open": [["ui_dialog_open", "book_page_turn"], -6.0, 0.05],
	"ui_dialog_advance": [["ui_page_flip", "book_page_turn"], -9.0, 0.08],
	"ui_text_blip": [["ui_text_blip", "talk_blip", "ui_move"], -14.0, 0.18],
	"ui_banner": [["ui_banner", "book_page_turn"], -6.0, 0.0],
	"ui_toast": [["ui_toast", "ui_select"], -8.0, 0.02],
	"ui_truffle_get": [], # the WorldRoot plays the truffle jingle
	"ui_truffle_count": [["ui_truffle_count"], 0.0, 0.0],
	"ui_acorn_count": [],  # objects play acorn_collect
	"ui_cake_lose": [["cake_slice_lost"], -2.0, 0.04],
	"ui_cake_gain": [["cake_slice_gained"], -2.0, 0.04],
	"ui_cake_low": [],
	"ui_page_popup": [],  # objects play page_collect
	"ui_timer_start": [["trial_start", "ui_confirm"], -4.0, 0.0],
	"ui_timer_tick": [["ui_timer_tick", "ui_move"], -2.0, 0.0],
	"ui_timer_end": [["ui_timer_end", "ui_back"], 0.0, 0.0],
	"ui_hat_change": [["ui_hat_change", "ui_confirm"], 0.0, 0.0],
	"ui_boss_bar_show": [["ui_boss_bar_show", "book_page_turn"], -4.0, 0.0],
	"ui_boss_hit": [],  # the boss plays its own hit sound
	"ui_settings_change": [["ui_move"], -4.0, 0.0],
	"ui_title_start": [["ui_accept", "ui_select"], 0.0, 0.0],
	"ui_new_game": [["ui_confirm", "ui_accept"], 0.0, 0.0],
}

static var _tex_cache: Dictionary = {}


static func _root() -> Window:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root if ml else null


static func _node(path: String) -> Node:
	var r := _root()
	return r.get_node_or_null(path) if r else null


static func tex(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path: String = TEX.get(key, key)
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[key] = t
	return t


## Plays the UI sound mapped to `event_name` and emits the Juice event.
static func event(event_name: String, params: Dictionary = {}, pitch: float = 1.0) -> void:
	sound(event_name, pitch)
	var j := _node("/root/Juice")
	if j and j.has_method("event"):
		var p := params.duplicate()
		p["ui_sfx"] = true
		j.call("event", event_name, Vector3.INF, p)


## Only the sound part of an event (used for repeated ticks such as the typewriter).
static func sound(event_name: String, pitch: float = 1.0) -> void:
	var spec: Array = SOUNDS.get(event_name, [[event_name], 0.0, 0.03])
	if spec.is_empty():
		return
	var a := _node("/root/Audio")
	if a == null:
		return
	for k in spec[0]:
		if a.has_method("has_key") and a.call("has_key", k):
			var p: Node = a.call("play_sfx", k, Vector3.INF, float(spec[2]), float(spec[1]))
			if p is AudioStreamPlayer and pitch != 1.0:
				(p as AudioStreamPlayer).pitch_scale *= pitch
			return


## Ease helpers used by the procedural UI.
static func back_out(x: float, s: float = 1.70158) -> float:
	x = clampf(x, 0.0, 1.0) - 1.0
	return x * x * ((s + 1.0) * x + s) + 1.0


static func elastic_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	if x <= 0.0 or x >= 1.0:
		return x
	return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * TAU / 3.0) + 1.0


## Damped "pop" curve: 0 at rest, overshoots on t in [0,1] (t counts down from 1 to 0).
static func pop(t: float) -> float:
	if t <= 0.0:
		return 0.0
	var x := 1.0 - t
	return sin(x * PI * 2.5) * exp(-x * 4.0) * t * 1.6


## Draws a texture centred at `c` with a uniform `size` (px of the longer side) and rotation.
static func draw_icon(ci: CanvasItem, t: Texture2D, c: Vector2, size: float, rot: float = 0.0, modulate: Color = Color.WHITE) -> void:
	if t == null:
		return
	var ts := t.get_size()
	var k := size / maxf(ts.x, ts.y)
	var sz := ts * k
	if absf(rot) < 0.0001:
		ci.draw_texture_rect(t, Rect2(c - sz * 0.5, sz), false, modulate)
		return
	ci.draw_set_transform(c, rot, Vector2.ONE)
	ci.draw_texture_rect(t, Rect2(-sz * 0.5, sz), false, modulate)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Text with a thick cream outline and a soft drop shadow (HUD numerals).
static func draw_outlined(ci: CanvasItem, f: Font, pos: Vector2, text: String, fs: int, fill: Color, outline: Color = UIStyle.INK, ow: int = 12, shadow: bool = true) -> void:
	if shadow:
		ci.draw_string_outline(f, pos + Vector2(0, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow + 2, Color(0.12, 0.05, 0.02, 0.45))
	ci.draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, outline)
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)


## Little 4-point star burst used by counters and pickups.
static func draw_burst(ci: CanvasItem, c: Vector2, t: float, count: int, radius: float, col: Color, seed_v: int = 0) -> void:
	if t <= 0.0 or t >= 1.0:
		return
	for i in count:
		var a := TAU * (i + 0.5 * float(seed_v % 2)) / count + float(seed_v) * 0.37
		var d := radius * (0.35 + 0.9 * UIFx.back_out(t, 1.2))
		var s := radius * 0.22 * (1.0 - t) * (0.7 + 0.3 * float((i * 7 + seed_v) % 3))
		UIDraw.sparkle(ci, c + Vector2(cos(a), sin(a)) * d, s, Color(col, 1.0 - t * t))
