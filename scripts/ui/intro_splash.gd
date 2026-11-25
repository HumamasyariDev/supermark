extends CanvasLayer
## Intro splash (owner fix 5, 2026-10-19): the logo builds itself before the title screen, in the spirit of the classic
## console intros (own art and sounds only). "SUPER" drops in letter by letter with a squash on each landing, "MAK" pops
## in letter by letter, the snout boings out with an oink, the 6 and 4 pop into the nostrils, Mak says "Super Mak!",
## sparkles twinkle, and the logo glides onto the title screen's logo while the backdrop fades. About 4 s; any key,
## button or click skips to the hand-off. Layers come from tools/split_logo_intro.py (assets/ui/intro/layers.json).
## Boot shows it on a plain launch only (see boot.gd). Emits want_title when the title should be built underneath.

signal want_title
signal done

const LAYERS_JSON := "res://assets/ui/intro/layers.json"
const LAYER_DIR := "res://assets/ui/intro/"
## Where the logo sits while it builds (1920x1080 canvas) and where the title screen draws it (title_screen.gd: a
## TextureRect at (90, 70) sized 860x480, KEEP_ASPECT_CENTERED).
const BUILD_CENTER := Vector2(960, 520)
const BUILD_WIDTH := 1480.0
const TITLE_RECT := Rect2(90, 70, 860, 480)
const T_SUPER := 0.22          ## first SUPER letter starts falling
const SUPER_STEP := 0.11
const T_MAK := 0.86
const MAK_STEP := 0.14
const T_SNOUT := 1.42
const T_DIGITS := [1.74, 1.86]
const T_VOICE := 2.02
const T_SPARKLE := 2.28
const T_HANDOFF := 3.25        ## the title is built under the finished logo here (the voice ends at about 3.1 s)
## Hand-off: the logo glides onto the title logo (0-0.4 s) over the still opaque backdrop, then the backdrop fades
## (0.3-0.7 s) and the splash logo, now exactly on the title logo, goes last (0.6-0.75 s).
const GLIDE := 0.4
const FADE := 0.75
const DROP_PX := 300.0
const SFX := {
	"pop": "res://assets/audio/sfx/pop.ogg",
	"pop2": "res://assets/audio/sfx/pop_2.ogg",
	"boing": "res://assets/audio/sfx/gummy_boing.ogg",
	"oink": "res://assets/audio/sfx/intro_oink.ogg",
	"chime": "res://assets/audio/sfx/chime.ogg",
	"voice": "res://assets/audio/voice/mak_supermak.ogg",
}

var _t := 0.0
var _layers: Array[Dictionary] = []
var _logo_size := Vector2(2048, 929)
var _events: Array = []
var _players: Array[AudioStreamPlayer] = []
var _handoff := false
var _fade_t := -1.0
var _canvas: Control
var _bg: ColorRect
## Dev: --intro-skip-at=<s> sends a real key press at that time (tests the skip path).
var _skip_at := -1.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_layers()
	_bg = ColorRect.new()
	_bg.color = Color("fff3dc")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	_canvas = _Canvas.new()
	_canvas.set("splash", self)
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	# Sound cues: [time, sound, volume_db, pitch, bus]. Levels follow the bank's measured mix (audio_index.json).
	for i in 5:
		_events.append([T_SUPER + i * SUPER_STEP + 0.2, "pop", -7.0, 0.95 + 0.07 * i, "SFX"])
	for i in 3:
		_events.append([T_MAK + i * MAK_STEP, "pop2", -4.0, 1.15 + 0.1 * i, "SFX"])
	_events.append([T_SNOUT, "boing", -2.5, 0.92, "SFX"])
	_events.append([T_SNOUT + 0.2, "oink", -2.0, 1.0, "SFX"])
	_events.append([T_DIGITS[0], "pop", -6.0, 1.6, "SFX"])
	_events.append([T_DIGITS[1], "pop", -6.0, 1.78, "SFX"])
	_events.append([T_VOICE, "voice", 0.0, 1.0, "Voice"])
	_events.append([T_SPARKLE, "chime", -4.0, 1.0, "SFX"])
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var dev := get_node_or_null("/root/Dev")
	if dev != null and dev.has_method("arg") and str(dev.call("arg", "intro-skip-at", "")) != "":
		_skip_at = float(str(dev.call("arg", "intro-skip-at", "")))
	print("[IntroSplash] start (%d layers)" % _layers.size())


func _load_layers() -> void:
	var f := FileAccess.open(LAYERS_JSON, FileAccess.READ)
	if f == null:
		return
	var meta: Variant = JSON.parse_string(f.get_as_text())
	if not (meta is Dictionary):
		return
	_logo_size = Vector2(float(meta.get("width", 2048)), float(meta.get("height", 929)))
	var super_i := 0
	var mak_i := 0
	var spark_i := 0
	for L: Dictionary in meta.get("layers", []):
		var name := str(L["name"])
		var tex := load(LAYER_DIR + name + ".png") as Texture2D
		if tex == null:
			continue
		var d := {"name": name, "tex": tex, "rect": Rect2(float(L["x"]), float(L["y"]), float(L["w"]), float(L["h"]))}
		if name.begins_with("super_"):
			d["kind"] = "drop"
			d["t0"] = T_SUPER + super_i * SUPER_STEP
			super_i += 1
		elif name.begins_with("mak_"):
			d["kind"] = "pop"
			d["t0"] = T_MAK + mak_i * MAK_STEP
			mak_i += 1
		elif name == "snout":
			d["kind"] = "snout"
			d["t0"] = T_SNOUT
		elif name.begins_with("digit_"):
			d["kind"] = "digit"
			d["t0"] = T_DIGITS[0] if name == "digit_6" else T_DIGITS[1]
		else:
			d["kind"] = "sparkle"
			d["t0"] = T_SPARKLE + spark_i * 0.07
			spark_i += 1
		_layers.append(d)


func _process(delta: float) -> void:
	# Clamped so the title's build hitch at the hand-off does not jump the fade.
	var dt := minf(delta, 1.0 / 30.0)
	_t += dt
	if _skip_at >= 0.0 and _t >= _skip_at:
		_skip_at = -1.0
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = true
		Input.parse_input_event(ev)
	while not _events.is_empty() and _t >= float(_events[0][0]):
		var e: Array = _events.pop_front()
		if _fade_t < 0.0:
			_play(str(e[1]), float(e[2]), float(e[3]), str(e[4]))
	if not _handoff and _t >= T_HANDOFF:
		_begin_handoff()
	elif _fade_t >= 0.0:
		_fade_t += dt
		_bg.modulate.a = 1.0 - _smooth(clampf((_fade_t - 0.3) / 0.4, 0.0, 1.0))
		_canvas.modulate.a = 1.0 - _smooth(clampf((_fade_t - 0.6) / 0.15, 0.0, 1.0))
		if _fade_t >= FADE:
			print("[IntroSplash] done at %.2f s" % _t)
			done.emit()
			queue_free()
			return
	_canvas.queue_redraw()


func _begin_handoff() -> void:
	_handoff = true
	_t = maxf(_t, T_HANDOFF)
	_events.clear()
	want_title.emit()
	_fade_t = 0.0


func skip() -> void:
	if _handoff:
		_fade_t = maxf(_fade_t, GLIDE)
		return
	for p in _players:
		if is_instance_valid(p):
			p.stop()
	print("[IntroSplash] skipped at %.2f s" % _t)
	_t = T_HANDOFF
	_begin_handoff()


func _input(event: InputEvent) -> void:
	var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) \
		and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


func _play(key: String, db: float, pitch: float, bus: String) -> void:
	var path: String = SFX.get(key, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	add_child(p)
	_players.append(p)
	p.finished.connect(func() -> void:
		_players.erase(p)
		p.queue_free())
	p.play()


static func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Logo-space (logo pixels) to canvas transform: built centred, then glides onto the title's logo rect in the hand-off.
func logo_xform() -> Transform2D:
	var s0 := BUILD_WIDTH / _logo_size.x
	var o0 := BUILD_CENTER - _logo_size * s0 * 0.5
	var s1 := minf(TITLE_RECT.size.x / _logo_size.x, TITLE_RECT.size.y / _logo_size.y)
	var o1 := TITLE_RECT.get_center() - _logo_size * s1 * 0.5
	var k := _smooth(clampf(_fade_t / GLIDE, 0.0, 1.0)) if _fade_t >= 0.0 else 0.0
	# A gentle breath once the logo is complete.
	var breath := 1.0 + 0.012 * sin(maxf(_t - T_SPARKLE, 0.0) * 3.0) * (1.0 - k)
	var s := lerpf(s0, s1, k) * breath
	var c := (o0 + _logo_size * s0 * 0.5).lerp(o1 + _logo_size * s1 * 0.5, k)
	return Transform2D(0.0, Vector2(s, s), 0.0, c - _logo_size * s * 0.5)


## Per-layer animation: returns [visible, offset (logo px), scale Vector2, rotation, pivot (logo px), alpha].
func layer_pose(d: Dictionary) -> Array:
	var r: Rect2 = d["rect"]
	var u := _t - float(d["t0"])
	if u < 0.0:
		return [false]
	var bottom := Vector2(r.get_center().x, r.end.y)
	match str(d["kind"]):
		"drop":
			# Fall (ease-in, 0.2 s), then a squash on landing that springs back with a little stretch.
			if u < 0.2:
				var e := u / 0.2
				return [true, Vector2(0, -DROP_PX * (1.0 - e * e)), Vector2(0.9, 1.12), 0.0, bottom, clampf(u * 12.0, 0.0, 1.0)]
			var w := u - 0.2
			var sq := 0.3 * exp(-8.0 * w) * cos(21.0 * w)
			return [true, Vector2.ZERO, Vector2(1.0 + sq * 0.75, 1.0 - sq), 0.0, bottom, 1.0]
		"pop":
			var s := 1.0 - exp(-7.0 * u) * cos(17.0 * u)
			var wob := 0.14 * exp(-6.0 * u) * sin(17.0 * u)
			return [true, Vector2.ZERO, Vector2(s * (1.0 - wob), s * (1.0 + wob)), 0.0, bottom, 1.0]
		"snout":
			var s2 := 1.0 - exp(-5.0 * u) * cos(12.5 * u)
			var rot := 0.14 * exp(-4.0 * u) * sin(15.0 * u)
			return [true, Vector2.ZERO, Vector2(s2, s2), rot, r.get_center(), 1.0]
		"digit":
			var s3 := 1.0 - exp(-9.0 * u) * cos(20.0 * u)
			return [true, Vector2.ZERO, Vector2(s3, s3), 0.0, r.get_center(), 1.0]
		_:
			var s4 := 1.0 - exp(-8.0 * u) * cos(18.0 * u)
			var tw := 0.75 + 0.25 * sin(u * 7.0 + float(d["t0"]) * 13.0)
			return [true, Vector2.ZERO, Vector2(s4, s4) * tw, (1.0 - clampf(u * 4.0, 0.0, 1.0)) * PI, r.get_center(), 1.0]


class _Canvas:
	extends Control
	const GLINT_T := 2.28      ## = T_SPARKLE
	var splash: Node

	func _draw() -> void:
		if splash == null:
			return
		var sp: Variant = splash
		var t: float = sp.get("_t")
		# Storybook sunburst behind the logo: soft cream rays turning slowly.
		var c := size * 0.5 + Vector2(0, -20)
		var rays := 18
		for i in rays:
			var a0 := TAU * i / rays + t * 0.15
			var a1 := a0 + TAU / rays * 0.5
			var far := size.length()
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * far, c + Vector2(cos(a1), sin(a1)) * far]),
				Color(1.0, 0.82, 0.55, 0.16 * (sp.get("_bg") as ColorRect).modulate.a))
		var xf: Transform2D = sp.call("logo_xform")
		for d: Dictionary in sp.get("_layers"):
			var pose: Array = sp.call("layer_pose", d)
			if not bool(pose[0]):
				continue
			var r: Rect2 = d["rect"]
			var off: Vector2 = pose[1]
			var sc: Vector2 = pose[2]
			var rot: float = pose[3]
			var piv: Vector2 = pose[4]
			var local := Transform2D(rot, sc, 0.0, piv + off) * Transform2D(0.0, -piv)
			draw_set_transform_matrix(xf * local)
			draw_texture_rect(d["tex"], r, false, Color(1, 1, 1, float(pose[5])))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# Extra glints around the finished logo.
		var g := t - GLINT_T
		if g > 0.0:
			var pts := [Vector2(0.18, 0.12), Vector2(0.52, 0.06), Vector2(0.97, 0.2), Vector2(0.9, 0.93), Vector2(0.03, 0.62), Vector2(0.6, 0.98)]
			for i in pts.size():
				var ph := fmod(g * 1.3 + i * 0.37, 1.0)
				var k := sin(ph * PI)
				var p: Vector2 = xf * (Vector2(pts[i].x, pts[i].y) * Vector2(2048, 929))
				UIDraw.sparkle(self, p, 10.0 + 26.0 * k, Color(1.0, 0.97, 0.75, 0.9 * k))
