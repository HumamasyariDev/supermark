extends Node
## Critique W3 r1c (QA lens): watches a W3 bot run (--w3-bot) and writes what the log would say to JSON, because
## godot.py keeps only the last 400 output lines and the RetroLook error flood pushes every [W3 bot] line out.
## Records: bot step changes and result, fort phase/sub/hits, Snap state, player state changes, damage, truffles.
## Output: --qa-out=<abs dir> -> bot_watch.json (rewritten every second and at exit).

var out_dir := ""
var ev: Array = []
var world: Node
var _last := {}
var _t := 0.0
var _f := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir()) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var g := get_node_or_null("/root/Game")
	if g:
		g.truffle_collected.connect(func(id: String) -> void: _e("truffle", id))
		if g.has_signal("damaged"):
			g.damaged.connect(func(a: int) -> void: _e("damaged", a))


func _e(kind: String, v: Variant) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var p := pl.global_position if pl else Vector3.ZERO
	ev.append({"f": _f, "t": snappedf(_t, 0.01), "kind": kind, "v": str(v), "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]})


func _watch(key: String, v: Variant) -> void:
	var s := str(v)
	if _last.get(key, null) != s:
		_last[key] = s
		_e(key, s)


func _physics_process(delta: float) -> void:
	_f += 1
	_t += delta
	var cs := get_tree().current_scene
	if cs == null or not ("world_id" in cs):
		return
	world = cs
	var bot := cs.find_child("W3Bot", true, false)
	if bot:
		_watch("bot_step", bot.get("step"))
		_watch("bot_done", bot.get("_done"))
	var fort := cs.find_child("FortEncounter", true, false)
	if fort:
		_watch("fort", "phase %s sub %s hits %s won %s" % [fort.get("phase"), fort.get("_sub"), fort.get("hits"), fort.get("_won")])
		var snap: Variant = fort.get("_snap")
		if is_instance_valid(snap):
			_watch("snap_state", "%s def=%s" % [(snap as Object).get("state"), (snap as Object).get("is_defeated")])
	var pl := get_tree().get_first_node_in_group("player")
	if pl and pl.has_method("get_state_name"):
		_watch("player_state", pl.call("get_state_name"))
	if _f % 60 == 0:
		_save()


func _exit_tree() -> void:
	_save()


func _save() -> void:
	var f := FileAccess.open(out_dir.path_join("bot_watch.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"events": ev}, " "))
		f.close()
