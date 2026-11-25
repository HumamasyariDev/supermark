class_name WorldRoot
extends Node3D
## Root of every playable area (TECH_CONTRACT.md "World scene contract").
## Spawns the player at the right marker, sets Game.current_world, plays music, enforces kill_y,
## honours --spawn, --mission and --unlock-all, and runs the TRUFFLE GET! celebration.
##
## Expected children: WorldEnvironment, a sun DirectionalLight3D, Spawns/ (Marker3D "Default" plus
## optional markers named by truffle id or "Book_W1" style hub markers), StoryCams/ (StoryCam_A..D),
## and optionally a Player instance. Without one, res://scenes/player/Player.tscn is spawned
## (or a simple stand-in while that scene does not exist yet).

signal player_spawned(player: Node3D)
signal truffle_celebration_finished(id: String)

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const STANDIN_SCRIPT := "res://scripts/core/standin_player.gd"

@export_enum("HUB", "W1", "W2", "W3", "BOSS") var world_id: String = "W1"
@export var display_name: String = ""
@export var music_key: String = ""
@export var ambience_key: String = ""
@export var kill_y: float = -40.0
@export var show_entry_banner: bool = true
@export var celebrate_truffles: bool = true
## Seconds the world freezes for the TRUFFLE GET! splash.
@export var celebration_seconds: float = 3.0

var player: Node3D
var spawn_name: String = ""
var _celebrating := false


func _ready() -> void:
	if display_name == "":
		display_name = WorldRegistry.display_name(world_id)
	if music_key == "":
		music_key = WorldRegistry.music_key(world_id)
	var game := _game()
	var router := get_node_or_null("/root/Router")
	var dev := get_node_or_null("/root/Dev")
	var dev_mission: String = dev.arg("mission", "") if dev else ""
	var dev_spawn: String = dev.arg("spawn", "") if dev else ""
	# Loaded directly (editor, --capture or a test) rather than through the Router.
	if game and game.current_world != world_id:
		game.begin_visit(world_id, dev_mission)
	elif game and dev_mission != "":
		game.current_mission = dev_mission
	var use_cp := false
	var routed_spawn := ""
	if router:
		use_cp = router.consume_checkpoint_flag()
		routed_spawn = router.consume_spawn()
	# Resolve the spawn.
	var xform: Variant = null
	if use_cp and game:
		xform = game.get_checkpoint(world_id)
	for candidate in [dev_spawn, routed_spawn, game.current_mission if game else "", "Default"]:
		if xform != null:
			break
		var m := find_marker(String(candidate))
		if m:
			spawn_name = String(candidate)
			xform = m.global_transform
	if xform == null:
		spawn_name = "(origin)"
		xform = Transform3D(Basis(), Vector3(0, 1, 0))
	_setup_player(xform)
	# Owner fix 2026-10-19: the world's way back is a closed gate that asks before returning to the library.
	WorldExits.install(self, world_id)
	# Signals.
	if game:
		game.truffle_collected.connect(_on_truffle_collected)
		game.cake_empty.connect(_on_cake_empty)
		game.checkpoint_set.connect(_on_checkpoint_set)
	var audio := get_node_or_null("/root/Audio")
	if audio:
		if music_key != "":
			audio.play_music(music_key)
		if ambience_key != "":
			audio.play_ambience(ambience_key)
	var ui := get_node_or_null("/root/UI")
	if ui:
		ui.set_gameplay(true)
	print("[WorldRoot] %s ready: spawn=%s mission=%s checkpoint=%s" % [world_id, spawn_name, game.current_mission if game else "", use_cp])
	if show_entry_banner:
		_entry_banner()


func _exit_tree() -> void:
	var ui := get_node_or_null("/root/UI")
	if ui:
		ui.set_gameplay(false)


func _game() -> Node:
	return get_node_or_null("/root/Game")


func find_marker(marker_name: String) -> Node3D:
	if marker_name == "":
		return null
	var n := get_node_or_null("Spawns/" + marker_name) as Node3D
	if n == null:
		var s := get_node_or_null("Spawns")
		if s:
			n = s.find_child(marker_name, true, false) as Node3D
	return n


func spawn_transform() -> Transform3D:
	var game := _game()
	var cp: Variant = game.get_checkpoint(world_id) if game else null
	if cp is Transform3D:
		return cp
	for candidate in [spawn_name, game.current_mission if game else "", "Default"]:
		var m := find_marker(String(candidate))
		if m:
			return m.global_transform
	return Transform3D(Basis(), Vector3(0, 1, 0))


func _setup_player(xform: Transform3D) -> void:
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node3D and is_ancestor_of(n):
			player = n
			break
	if player == null:
		var existing := get_node_or_null("Player") as Node3D
		if existing:
			player = existing
	if player == null:
		if ResourceLoader.exists(PLAYER_SCENE):
			player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
		else:
			player = CharacterBody3D.new()
			player.set_script(load(STANDIN_SCRIPT))
		player.name = "Player"
		add_child(player)
	_place(xform)
	player_spawned.emit(player)


func _place(xform: Transform3D) -> void:
	if player == null:
		return
	if player.has_method("respawn"):
		player.respawn(xform)
	else:
		player.global_transform = xform
		player.reset_physics_interpolation()
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO


func respawn_player() -> void:
	_place(spawn_transform())


func _physics_process(_delta: float) -> void:
	if player and is_instance_valid(player) and player.global_position.y < kill_y:
		var game := _game()
		if game:
			game.player_fell_out()
		else:
			respawn_player()


func _entry_banner() -> void:
	var router := get_node_or_null("/root/Router")
	if router and router.busy:
		await router.transition_finished
	else:
		await get_tree().create_timer(0.4).timeout
	var ui := get_node_or_null("/root/UI")
	var game := _game()
	if ui == null:
		return
	var mission: String = game.current_mission if game else ""
	if mission != "" and world_id != "HUB":
		# critique UI r1: the entry banner states the mission goal
		var goal := WorldRegistry.truffle_goal(mission)
		ui.show_banner(WorldRegistry.truffle_name(mission), goal if goal != "" else display_name, 3.8 if goal != "" else 3.2)
	elif world_id == "HUB":
		# critique UI r1: one name for the hub, matching the page turn ("The Grand Library", Mak Manor below),
		# and a first-visit nudge so a new player knows the books are the way in
		var first: bool = game != null and game.truffle_count() == 0
		ui.show_banner("The Grand Library", "Jump into a storybook to begin" if first else "Mak Manor", 4.4 if first else 3.2)
	else:
		ui.show_banner(display_name, WorldRegistry.book_title(world_id))


func _on_truffle_collected(id: String) -> void:
	if not celebrate_truffles or _celebrating or not is_inside_tree():
		return
	_celebrating = true
	var tree := get_tree()
	tree.paused = true
	var ui := get_node_or_null("/root/UI")
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_jingle("truffle_get")
	if player and player.has_method("celebrate"):
		player.celebrate()
	if ui:
		ui.truffle_get(id, "TRUFFLE GET!", celebration_seconds)
	await tree.create_timer(celebration_seconds, true).timeout
	var pause_open: bool = ui != null and ui.pause_menu != null and ui.pause_menu.is_open()
	if not pause_open and is_inside_tree():
		tree.paused = false
	_celebrating = false
	truffle_celebration_finished.emit(id)


func _on_cake_empty() -> void:
	var ui := get_node_or_null("/root/UI")
	if ui:
		ui.show_banner("Oh, crumbs!", "Back to the last bookmark", 1.8)


func _on_checkpoint_set(wid: String, _x: Transform3D) -> void:
	if wid != world_id:
		return
	var ui := get_node_or_null("/root/UI")
	if ui:
		ui.toast("Bookmark saved")
