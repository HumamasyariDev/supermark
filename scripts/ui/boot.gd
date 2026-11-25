extends Node
## Boot: shows the intro splash, then the title screen. Dev shortcuts (after "--"):
##   --goto=HUB|W1|W2|W3|BOSS   skip the title and enter that area through the Router
##   --mission=<truffle id>     with --goto, the mission to enter
##   --intro                    show the intro splash even with other dev arguments (captures of the intro)
##   --no-intro                 never show it
## Owner fix 5 (2026-10-19): the intro splash (scenes/ui/IntroSplash.tscn) plays on a plain launch. Any dev argument
## (--goto, --replay, --capture, --profile, bots ...) and headless runs skip it unless --intro is given.

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const INTRO_SCENE := "res://scenes/ui/IntroSplash.tscn"

var _title_added := false


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	var goto: String = dev.arg("goto", "") if dev else ""
	if goto != "":
		var router := get_node_or_null("/root/Router")
		if router:
			if goto == "HUB":
				router.go_to_hub.call_deferred(dev.arg("spawn", ""))
			else:
				router.enter_world.call_deferred(goto, dev.arg("mission", ""))
			return
	if _want_intro(dev) and ResourceLoader.exists(INTRO_SCENE):
		var splash := (load(INTRO_SCENE) as PackedScene).instantiate()
		splash.connect("want_title", _add_title.bind(true))
		add_child(splash)
		if OS.has_feature("web"):
			WebRuntime.loaded()
		return
	_add_title(false)


func _want_intro(dev: Node) -> bool:
	if dev != null and dev.has_method("has_arg"):
		if bool(dev.call("has_arg", "no-intro")):
			return false
		if bool(dev.call("has_arg", "intro")):
			return true
		var a: Variant = dev.get("args")
		if a is Dictionary and not (a as Dictionary).is_empty():
			return false
	return DisplayServer.get_name() != "headless"


func _add_title(from_intro: bool) -> void:
	if _title_added:
		return
	_title_added = true
	if OS.has_feature("web"):
		WebRuntime.loading("Opening the library...")
		await get_tree().process_frame
	var load_t := WebRuntime.trace_start()
	var title_pack := load(TITLE_SCENE) as PackedScene
	WebRuntime.trace_end("resource_load:TITLE", load_t)
	var scene_t := WebRuntime.trace_start()
	var title := title_pack.instantiate()
	WebRuntime.trace_end("scene_instantiate:TITLE", scene_t)
	if from_intro:
		# The splash glides its logo onto the title's logo, so the title skips its own logo pop.
		title.set_meta("from_intro", true)
	var ready_t := WebRuntime.trace_start()
	add_child(title)
	WebRuntime.trace_end("scene_add_ready:TITLE", ready_t)
	if OS.has_feature("web"):
		await get_tree().process_frame
		get_tree().paused = true
		Router._title.text = "SUPER MAK 64"
		Router._subtitle.text = "Opening the library"
		Router._note.text = ""
		Router._back.visible = true
		await WebRuntime.warm_scene(title)
		Router._back.visible = false
		get_tree().paused = false
		WebRuntime.loaded()
