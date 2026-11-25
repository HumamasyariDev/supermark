extends Node3D
## JuiceLab: fires Juice events on a labelled stage with the real generated characters, for captures and reels.
## Args (after --):
##   --env=W1|W2|W3|HUB|BOSS      world environment and sun (default W1)
##   --group=<name>               player_move, player_combat, enemies, boss, objects_a, objects_b, world, ambient_w1,
##                                ambient_w2, ambient_w3, ambient_hub (default player_move)
##   --events=a,b,c               explicit station list instead of a group
##   --lead=<frames>              grid mode: fire every station <lead> frames before the --wait capture frame (default 9)
##   --reel                       reel mode: close-up camera cuts to each station in turn and fires it (Movie Maker)
##   --loop                       grid mode: re-fire all stations every 2.4 s (live viewing)
##   --cam=gameplay|behind        station cameras at the hero camera's gameplay distance (or the close behind view)
## Cameras: StoryCam_A (whole row), Cam_<index> close-ups.
##   python tools/godot.py capture res://scenes/fx/JuiceLab.tscn out.png --wait 120 -- --group=player_move --profile=juice

## Juice fix r3: the owner-approved hero v2 (assembled preview: body, top hat, pack); the night hero is the fallback.
const MAK := "res://assets/characters/mak_v2/mak_v2.glb"
const MAK_FALLBACK := "res://assets/characters/mak/mak_v2.glb"
const ENEMY := {
	"woolly_wolf": "res://assets/enemies/woolly_wolf/woolly_wolf.glb",
	"crow_bandit": "res://assets/enemies/crow_bandit/crow_bandit.glb",
	"peapod_popper": "res://assets/enemies/peapod_popper/peapod_popper_v2.glb",
	"bumble_bruiser": "res://assets/enemies/bumble_bruiser/bumble_bruiser_v2.glb",
	"gingerbread_grenadier": "res://assets/enemies/gingerbread_grenadier/gingerbread_grenadier.glb",
	"gummy_brute": "res://assets/enemies/gummy_brute/gummy_brute.glb",
}
const WOLF := "res://assets/characters/wolf_boss/wolf_boss.glb"
const TRUFFLE := "res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb"
const CRATE := "res://assets/props/pickups/breakable_crate/breakable_crate.glb"

var env_id := "W1"
var stations: Array[Dictionary] = []
var _args := {}
var _fire_frame := -1
var _hud: Label
var _cam: Camera3D
var _ground_mesh: PlaneMesh
var _ground_shape: BoxShape3D


static func S(ev: String, model: String = "mak", params: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var d := {"event": ev, "model": model, "params": params}
	d.merge(extra, true)
	return d


func _groups() -> Dictionary:
	var right := Vector3.RIGHT
	return {
		"player_move": [
			S("player_footstep", "mak", {"surface": "grass", "speed": 7.0}, {"label": "footstep (grass, run)"}),
			S("player_jump_1", "mak", {}, {"motion": "hop"}),
			S("player_jump_2", "mak", {}, {"motion": "hop"}),
			S("player_jump_3", "mak", {}, {"motion": "flip", "label": "player_jump_3 (spin trail)"}),
			S("player_long_jump", "mak", {"direction": right}, {"motion": "long"}),
			S("player_land", "mak", {"impact": 5.0}, {"label": "land 5 m/s"}),
			S("player_land", "mak", {"impact": 10.0}, {"label": "land 10 m/s"}),
			S("player_land", "mak", {"impact": 16.0}, {"label": "land 16 m/s"}),
			S("player_skid", "mak", {"direction": right}),
			S("player_wall_kick", "mak", {"normal": Vector3.BACK}, {"wall": true, "fire_offset": Vector3(0, 1.0, -0.45)}),
		],
		"player_combat": [
			S("player_ham_slam", "mak", {"impact": 14.0}, {"motion": "slam", "pre": "player_ham_slam_start", "label": "Ham Slam"}),
			S("player_dive", "mak", {"direction": right}, {"motion": "dive"}),
			S("player_slide_start", "mak", {}, {"motion": "slide", "post": "player_slide_end", "label": "belly slide trail"}),
			S("player_punch", "mak", {"direction": right, "combo": 1}),
			S("player_punch", "mak", {"direction": right, "combo": 2}, {"label": "punch (combo 2)"}),
			S("player_kick", "mak", {"direction": right}),
			S("player_jump_kick", "mak", {"direction": right}, {"motion": "hop"}),
			S("player_hurt", "mak"),
			S("player_heal", "mak"),
			S("player_sniff", "mak", {"direction": right}),
			S("player_respawn", "mak"),
		],
		"enemies": [
			S("enemy_notice", "woolly_wolf", {"family": "woolly_wolf"}, {"fire_offset": Vector3(0, 1.5, 0)}),
			S("enemy_hurt", "crow_bandit", {"family": "crow_bandit"}, {"fire_offset": Vector3(0, 0.7, 0.3)}),
			S("enemy_block", "gingerbread_grenadier", {"family": "gingerbread_grenadier"}, {"fire_offset": Vector3(0, 0.9, 0.4)}),
			S("enemy_stunned", "bumble_bruiser", {"family": "bumble_bruiser"}, {"post": "enemy_recover", "post_delay": 2.5}),
			S("enemy_slam", "gummy_brute", {"family": "gummy_brute"}),
			S("enemy_defeat", "woolly_wolf", {"family": "woolly_wolf"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: woolly wolf"}),
			S("enemy_defeat", "crow_bandit", {"family": "crow_bandit"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: crow bandit"}),
			S("enemy_defeat", "peapod_popper", {"family": "peapod_popper"}, {"hide": true, "fire_offset": Vector3(0, 0.5, 0), "label": "defeat: peapod popper"}),
			S("enemy_defeat", "bumble_bruiser", {"family": "bumble_bruiser"}, {"hide": true, "fire_offset": Vector3(0, 0.8, 0), "label": "defeat: bumble bruiser"}),
			S("enemy_defeat", "gingerbread_grenadier", {"family": "gingerbread_grenadier"}, {"hide": true, "fire_offset": Vector3(0, 0.7, 0), "label": "defeat: grenadier"}),
			S("enemy_defeat", "gummy_brute", {"family": "gummy_brute"}, {"hide": true, "fire_offset": Vector3(0, 0.7, 0), "label": "defeat: gummy brute"}),
		],
		"boss": [
			S("boss_inhale", "wolf", {"direction": Vector3.BACK}, {"fire_offset": Vector3(0, 2.6, 0.6), "spacing": 7.0}),
			S("boss_huff", "wolf", {"direction": Vector3(1, 0, 0.3).normalized()}, {"fire_offset": Vector3(0.5, 2.5, 0.6), "spacing": 7.0}),
			S("boss_winded", "wolf", {}, {"fire_offset": Vector3(0, 3.3, 0.3), "spacing": 7.0, "post": "boss_recover", "post_delay": 2.5}),
			S("boss_chimney_smash", "wolf", {}, {"fire_offset": Vector3(1.2, 0.0, 0.5), "spacing": 7.0}),
			S("boss_hit", "wolf", {}, {"fire_offset": Vector3(0, 2.2, 0.6), "spacing": 7.0}),
			S("boss_stomp", "wolf", {}, {"spacing": 7.0}),
			S("boss_swipe", "wolf", {"direction": Vector3.BACK}, {"spacing": 7.0}),
			S("boss_defeat", "wolf", {}, {"hide": true, "spacing": 7.0}),
		],
		"objects_a": [
			S("object_acorn_collect", "none", {}, {"fire_offset": Vector3(0, 0.6, 0)}),
			S("object_truffle_appear", "truffle"),
			S("object_truffle_collect", "truffle", {}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0)}),
			S("object_page_collect", "none", {}, {"fire_offset": Vector3(0, 0.6, 0)}),
			S("object_checkpoint", "none"),
			S("object_portal_enter", "none"),
			S("object_door_unlock", "none"),
			S("object_cage_open", "none"),
			S("object_pages_complete", "none"),
		],
		"objects_b": [
			S("object_bounce_pad", "none", {"impact": 14.0}, {"label": "bounce pad"}),
			S("object_bounce_pad", "none", {"impact": 14.0, "kind": "leaf"}, {"label": "bounce leaf"}),
			S("object_bounce_pad", "none", {"impact": 14.0, "kind": "gumdrop"}, {"label": "bounce gumdrop"}),
			S("object_crate_break", "crate", {}, {"hide": true, "fire_offset": Vector3(0, 0.5, 0)}),
			S("object_switch_press", "none"),
			S("object_cloud_vanish", "none"),
			S("object_bellows_blast", "none", {"direction": Vector3.RIGHT}, {"fire_offset": Vector3(0, 1.0, 0)}),
			S("object_dig", "none"),
			S("object_ring_pass", "none", {}, {"fire_offset": Vector3(0, 1.4, 0)}),
			S("object_platform_crumble", "none", {}, {"fire_offset": Vector3(0, 1.0, 0)}),
		],
		# Juice fix round 1 review set: the critic's problem stations, closer framing and the gameplay camera ("cam": "behind").
		"r1fix": [
			S("player_land", "mak", {"impact": 16.0}, {"label": "land 16 m/s"}),
			S("player_ham_slam", "mak", {"impact": 14.0}, {"motion": "slam", "pre": "player_ham_slam_start", "label": "Ham Slam"}),
			S("player_punch", "mak", {"direction": right, "combo": 1}, {"cam": "behind", "label": "punch (gameplay cam)"}),
			S("player_kick", "mak", {"direction": right}, {"cam": "behind", "label": "spin kick (gameplay cam)"}),
			S("enemy_hurt", "crow_bandit", {"family": "crow_bandit"}, {"fire_offset": Vector3(0, 0.7, 0), "cam": "behind", "label": "enemy hurt (gameplay cam)"}),
			S("enemy_defeat", "woolly_wolf", {"family": "woolly_wolf"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: woolly wolf"}),
			S("enemy_defeat", "gingerbread_grenadier", {"family": "gingerbread_grenadier"}, {"hide": true, "fire_offset": Vector3(0, 0.7, 0), "label": "defeat: grenadier"}),
			S("enemy_defeat", "bumble_bruiser", {"family": "bumble_bruiser"}, {"hide": true, "fire_offset": Vector3(0, 0.8, 0), "label": "defeat: bumble bruiser"}),
			S("enemy_notice", "woolly_wolf", {"family": "woolly_wolf"}, {"fire_offset": Vector3(0, 1.5, 0)}),
			S("object_truffle_collect", "truffle", {}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0)}),
			S("object_truffle_appear", "truffle"),
			S("object_page_collect", "none", {}, {"fire_offset": Vector3(0, 0.6, 0)}),
			S("object_portal_enter", "none"),
			S("object_cloud_vanish", "none"),
			S("player_respawn", "mak"),
			S("player_heal", "mak"),
			S("player_jump_3", "mak", {}, {"motion": "flip"}),
			S("world_cocoa_burn", "none"),
			S("object_hazard_touch", "mak"),
			S("object_bellows_blast", "none", {"direction": Vector3.RIGHT}, {"fire_offset": Vector3(0, 1.0, 0)}),
		],
		# Anticipation and transition events the earlier groups skipped (critic r1 lab coverage).
		"coverage": [
			S("enemy_windup", "gingerbread_grenadier", {"family": "gingerbread_grenadier"}, {"fire_offset": Vector3(0, 1.0, 0.3)}),
			S("enemy_attack", "woolly_wolf", {"family": "woolly_wolf", "direction": right}, {"fire_offset": Vector3(0, 0.6, 0)}),
			S("player_bonk", "mak", {"normal": Vector3.BACK, "impact": 8.0}, {"wall": true, "fire_offset": Vector3(0, 1.0, -0.45)}),
			S("player_backflip", "mak", {}, {"motion": "flip"}),
			S("player_side_flip", "mak", {"direction": right}, {"motion": "flip"}),
			S("player_ledge_grab", "mak", {"direction": right}),
			S("player_ledge_climb", "mak"),
			S("player_stomp", "mak", {"kind": "stomp"}),
			S("player_death", "mak"),
			S("object_crate_land", "crate", {"impact": 3.0}),
			S("object_bellows_break", "none", {}, {"fire_offset": Vector3(0, 0.6, 0)}),
			S("player_hat_change", "mak"),
		],
		"r1fix_reel": [
			S("player_land", "mak", {"impact": 16.0}, {"label": "land 16 m/s"}),
			S("player_ham_slam", "mak", {"impact": 14.0}, {"motion": "slam", "pre": "player_ham_slam_start", "label": "Ham Slam"}),
			S("player_punch", "mak", {"direction": right, "combo": 1}, {"cam": "behind", "label": "punch (gameplay cam)"}),
			S("enemy_hurt", "crow_bandit", {"family": "crow_bandit"}, {"fire_offset": Vector3(0, 0.7, 0), "cam": "behind", "label": "enemy hurt (gameplay cam)"}),
			S("enemy_defeat", "woolly_wolf", {"family": "woolly_wolf"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: woolly wolf"}),
			S("enemy_defeat", "gingerbread_grenadier", {"family": "gingerbread_grenadier"}, {"hide": true, "fire_offset": Vector3(0, 0.7, 0), "label": "defeat: grenadier"}),
			S("object_truffle_collect", "truffle", {}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0)}),
			S("object_cloud_vanish", "none"),
		],
		# Juice fix round 2 review set (shoot twice: default close-up and --cam=gameplay).
		"r2": [
			S("player_land", "mak", {"impact": 16.0}, {"label": "land 16 m/s"}),
			S("player_land", "mak", {"impact": 5.0}, {"label": "land 5 m/s (new soft tier)"}),
			S("player_ham_slam", "mak", {"impact": 14.0}, {"motion": "slam", "pre": "player_ham_slam_start", "label": "Ham Slam"}),
			S("player_jump_3", "mak", {}, {"motion": "flip"}),
			S("player_footstep", "mak", {"surface": "grass", "speed": 7.0}, {"label": "footstep (grass, run)"}),
			S("player_skid", "mak", {"direction": right}),
			S("player_wall_kick", "mak", {"normal": Vector3.BACK}, {"wall": true, "fire_offset": Vector3(0, 1.0, -0.45)}),
			S("player_sniff", "mak", {"direction": right}),
			S("player_heal", "mak"),
			S("player_hurt", "mak"),
			S("player_punch", "mak", {"direction": right, "combo": 1}),
			S("player_jump_kick", "mak", {"direction": right}, {"motion": "hop"}),
			S("player_dive", "mak", {"direction": right}, {"motion": "dive"}),
			S("enemy_hurt", "crow_bandit", {"family": "crow_bandit"}, {"fire_offset": Vector3(0, 0.7, 0)}),
			S("enemy_defeat", "woolly_wolf", {"family": "woolly_wolf"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: woolly wolf"}),
			S("enemy_defeat", "crow_bandit", {"family": "crow_bandit"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: crow bandit"}),
			S("enemy_defeat", "gingerbread_grenadier", {"family": "gingerbread_grenadier"}, {"hide": true, "fire_offset": Vector3(0, 0.7, 0), "label": "defeat: grenadier"}),
			S("object_truffle_collect", "truffle", {}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0)}),
			S("world_cocoa_burn", "none"),
			S("object_portal_enter", "none"),
			S("player_respawn", "mak"),
		],
		# r3 spot check: the Ham Slam flash and the hero-scale heavy beats.
		"r3_slam": [
			S("player_ham_slam", "mak", {"impact": 14.0}, {"motion": "slam", "pre": "player_ham_slam_start", "label": "Ham Slam"}),
			S("player_land", "mak", {"impact": 16.0}, {"label": "land 16 m/s"}),
			S("enemy_defeat", "crow_bandit", {"family": "crow_bandit"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: crow bandit"}),
			S("enemy_defeat", "woolly_wolf", {"family": "woolly_wolf"}, {"hide": true, "fire_offset": Vector3(0, 0.6, 0), "label": "defeat: woolly wolf"}),
			S("object_portal_enter", "none"),
		],
		# r2 small-feedback check at gameplay distance.
		"r2_small": [
			S("player_footstep", "mak", {"surface": "grass", "speed": 7.0}, {"label": "footstep (grass, run)"}),
			S("player_footstep", "mak", {"surface": "stone", "speed": 4.0}, {"label": "footstep (stone, walk)"}),
			S("player_land", "mak", {"impact": 5.0}, {"label": "land 5 m/s"}),
			S("player_skid", "mak", {"direction": right}),
			S("player_sniff", "mak", {"direction": right}),
		],
		"r1fix_boss": [
			S("boss_inhale", "wolf", {}, {"fire_offset": Vector3(0, 2.6, 0.6), "spacing": 9.0}),
			S("boss_huff", "wolf", {"direction": Vector3(1, 0, 0.3).normalized()}, {"fire_offset": Vector3(0.5, 2.5, 0.6), "spacing": 9.0}),
			S("boss_stomp", "wolf", {}, {"spacing": 9.0}),
			S("boss_swipe", "wolf", {"direction": Vector3.BACK}, {"spacing": 9.0}),
			S("boss_hit", "wolf", {}, {"fire_offset": Vector3(0, 2.2, 0.6), "spacing": 9.0}),
			S("boss_defeat", "wolf", {}, {"hide": true, "spacing": 9.0}),
		],
		"world": [
			S("world_splash", "none", {"impact": 10.0}),
			S("world_cocoa_splash", "none", {"impact": 10.0}),
			S("world_cocoa_burn", "none"),
			S("world_wind_gust", "none", {"direction": Vector3.RIGHT}, {"fire_offset": Vector3(0, 1.0, 0)}),
			S("world_debris", "none"),
			S("world_lightning", "none", {}, {"fire_offset": Vector3(0, 8, -20)}),
		],
	}


func _ambient(group: String) -> Array:
	match group:
		"ambient_w1":
			return [["res://scenes/fx/ambient/Pollen.tscn", Vector3(0, 1.6, 0), Vector3(14, 2, 10)], ["res://scenes/fx/Butterflies.tscn", Vector3(-3, 1.0, 1), Vector3.ZERO],
				["res://scenes/fx/FallingLeaves.tscn", Vector3(5, 4.0, -2), Vector3.ZERO], ["res://scenes/fx/ChimneySmoke.tscn", Vector3(-6, 4.0, -6), Vector3.ZERO]]
		"ambient_w2":
			return [["res://scenes/fx/ambient/CloudWisps.tscn", Vector3(0, 1.0, -4), Vector3(18, 3, 12)], ["res://scenes/fx/ambient/Petals.tscn", Vector3(0, 4.0, 0), Vector3.ZERO],
				["res://scenes/fx/Butterflies.tscn", Vector3(3, 1.2, 1), Vector3.ZERO]]
		"ambient_w3":
			return [["res://scenes/fx/ambient/CandySparkles.tscn", Vector3(0, 1.4, 0), Vector3(12, 2, 8)], ["res://scenes/fx/ambient/CocoaSteam.tscn", Vector3(0, 0.05, -3), Vector3(8, 0.1, 1.5)]]
		"ambient_hub":
			return [["res://scenes/fx/ambient/Fireflies.tscn", Vector3(0, 1.2, 0), Vector3(8, 1.5, 6)], ["res://scenes/fx/ambient/DustMotes.tscn", Vector3(-2, 3.0, -1), Vector3.ZERO],
				["res://scenes/fx/ambient/FireEmbers.tscn", Vector3(4, 0.4, -2), Vector3.ZERO]]
	return []


func _ready() -> void:
	_args = _parse_args()
	if _args.has("shots"):
		# r3: frame leads mean 60 fps time (uncapped runs drew about 95 fps, so "f24" was 0.25 s, not 0.4 s).
		Engine.max_fps = 60
	env_id = String(_args.get("env", "W1"))
	_build_stage()
	var group := String(_args.get("group", "player_move"))
	if group == "highlights":
		var g := _groups()
		var pick := [["player_move", 3], ["player_move", 7], ["player_combat", 0], ["player_combat", 1], ["player_combat", 3], ["player_combat", 5],
			["enemies", 6], ["enemies", 5], ["enemies", 10], ["enemies", 2], ["objects_a", 2], ["objects_b", 2], ["objects_b", 3], ["objects_b", 5],
			["objects_a", 5], ["world", 2], ["enemies", 4]]
		for pk in pick:
			stations.append(g[pk[0]][pk[1]])
	elif _args.has("events"):
		for n in String(_args["events"]).split(","):
			stations.append(S(n, "mak"))
	elif group.begins_with("ambient"):
		for a in _ambient(group):
			var fx: Node = (load(a[0]) as PackedScene).instantiate()
			if a[2] != Vector3.ZERO:
				fx.set("area", a[2])
			add_child(fx)
			fx.position = a[1]
		_place_mak(Vector3(0, 0, 2.0), 0.0)
	else:
		for s in _groups().get(group, []):
			stations.append(s)
	_layout()
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 34)
	_hud.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.08))
	_hud.add_theme_constant_override("outline_size", 10)
	_hud.position = Vector2(40, 30)
	var cl := CanvasLayer.new()
	cl.add_to_group("hud")
	add_child(cl)
	cl.add_child(_hud)
	_hud.text = "Juice lab: %s (%s)" % [group, env_id]
	if _args.has("shots"):
		_run_shots()
	elif _args.has("reel"):
		_run_reel()
	elif not group.begins_with("ambient"):
		var wait := int(_args.get("wait", "120"))
		_fire_frame = maxi(wait - int(_args.get("lead", "9")), 5)
		if not _args.has("capture"):
			_fire_frame = 60


func _parse_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, -35, 0)
	FxEnvironments.apply(self, env_id)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 80)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	ground.mesh = pm
	_ground_mesh = pm
	var mat_name: String = {"W1": "toon_grass", "W2": "toon_castle_stone", "W3": "toon_frosting", "HUB": "toon_library_carpet", "BOSS": "toon_roof_shingles_slate"}.get(env_id, "toon_grass")
	var m: Material = load("res://assets/shaders/materials/%s.tres" % mat_name) as Material
	if m != null:
		ground.material_override = m
	add_child(ground)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 80)
	_ground_shape = bs
	cs.shape = bs
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	_cam = Camera3D.new()
	_cam.name = "StoryCam_A"
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true


func _load_model(kind: String) -> Node3D:
	var path := ""
	match kind:
		"mak":
			path = MAK if ResourceLoader.exists(MAK) else MAK_FALLBACK
		"wolf":
			path = WOLF
		"truffle":
			path = TRUFFLE
		"crate":
			path = CRATE
		_:
			path = String(ENEMY.get(kind, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps != null else null


func _place_mak(at: Vector3, yaw_deg: float) -> Node3D:
	var m := _load_model("mak")
	if m != null:
		add_child(m)
		m.position = at
		m.rotation_degrees.y = yaw_deg
	return m


func _layout() -> void:
	var x := 0.0
	var positions: Array[float] = []
	# r3: at the gameplay camera (5.4 m back) neighbouring stations sat next to the lens and their effects leaked into
	# each other's frames (giant feathers, pages and rays); space the row out in that mode.
	var gp_cam := String(_args.get("cam", "")) == "gameplay"
	for s in stations:
		var sp: float = s.get("spacing", 3.6)
		if gp_cam:
			sp = maxf(sp, 11.0)
		positions.append(x + sp * 0.5)
		x += sp
	var total := x
	if total + 60.0 > 120.0 and _ground_mesh != null:
		# r3: the spaced-out gameplay-camera row is longer than the default stage; grow the ground with it.
		_ground_mesh.size = Vector2(total + 60.0, 80.0)
		_ground_shape.size = Vector3(total + 60.0, 1.0, 80.0)
		var gmi := get_node_or_null("Ground") as MeshInstance3D
		if gmi != null and gmi.material_override is ShaderMaterial:
			# Keep the texel density: scale the UVs with the plane's length.
			var gm := (gmi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			var uvs: Variant = gm.get_shader_parameter("uv_scale")
			if uvs is Vector2:
				gm.set_shader_parameter("uv_scale", Vector2((uvs as Vector2).x * (total + 60.0) / 120.0, (uvs as Vector2).y))
			gmi.material_override = gm
	for i in stations.size():
		var s: Dictionary = stations[i]
		var px := positions[i] - total * 0.5
		var root := Node3D.new()
		root.name = "Station_%d" % i
		add_child(root)
		root.position = Vector3(px, 0, 0)
		s["root"] = root
		var model := String(s.get("model", "mak"))
		var mn := _load_model(model)
		if mn != null:
			root.add_child(mn)
			if model == "mak":
				# Side view: Mak faces +X (glTF +Z rotated) so swishes, dives and skids read left-to-right.
				mn.rotation_degrees.y = 90.0
			elif model == "truffle":
				mn.position.y = 0.4
			s["model_node"] = mn
		if s.get("wall", false):
			var wall := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.4, 3.0, 0.4)
			wall.mesh = bm
			var wm: Material = load("res://assets/shaders/materials/toon_brick.tres") as Material
			if wm != null:
				wall.material_override = wm
			root.add_child(wall)
			wall.position = Vector3(0, 1.5, -0.7)
		var lab := Label3D.new()
		lab.text = String(s.get("label", s["event"]))
		lab.font_size = 40
		lab.outline_size = 12
		lab.pixel_size = 0.004
		lab.modulate = Color(1, 0.97, 0.88)
		lab.outline_modulate = Color(0.2, 0.13, 0.1)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = Vector3(0, 3.4 if model != "wolf" else 4.6, 0)
		root.add_child(lab)
		var cam := Camera3D.new()
		cam.name = "Cam_%d" % i
		var tall := 2.6 if model == "wolf" else 0.9
		var dist := 8.5 if model == "wolf" else 3.9
		root.add_child(cam)
		cam.position = Vector3(0.6, tall + 0.9, dist)
		var cam_mode := String(_args.get("cam", s.get("cam", "")))
		if cam_mode == "gameplay":
			# Juice fix r2: the hero camera's real framing (5.4 m behind and above Mak, FOV 62), for art direction at
			# gameplay distance (--cam=gameplay applies it to every station).
			cam.fov = 62.0
			cam.position = Vector3(-4.9, 2.3, 1.8) * (1.6 if model == "wolf" else 1.0)
			cam.look_at_from_position(root.global_position + cam.position, root.global_position + Vector3(0.6, tall * 0.9 + 0.2, 0))
		elif cam_mode == "behind":
			# Gameplay camera: behind Mak (he faces +X), slightly above, looking past him at the target.
			cam.position = Vector3(-2.9, 1.9, 0.8)
			cam.look_at_from_position(root.global_position + cam.position, root.global_position + Vector3(0.8, 0.8, 0))
		else:
			cam.look_at_from_position(root.global_position + cam.position, root.global_position + Vector3(0, tall, 0))
	# Overview camera frames the whole row.
	var half := maxf(total * 0.5, 4.0)
	var d := half / tan(deg_to_rad(_cam.fov * 0.5)) * 0.62
	_cam.position = Vector3(0, 2.6 + d * 0.18, d)
	_cam.look_at(Vector3(0, 1.1, 0))
	if stations.is_empty():
		_cam.position = Vector3(0, 2.4, 9.0)
		_cam.look_at(Vector3(0, 1.4, -2))


func _process(_delta: float) -> void:
	if _fire_frame > 0 and Engine.get_process_frames() >= _fire_frame:
		_fire_frame = -1
		for s in stations:
			_fire(s)
		if _args.has("loop") and not _args.has("capture"):
			get_tree().create_timer(2.4).timeout.connect(func() -> void: _fire_frame = Engine.get_process_frames() + 1)


func _fire(s: Dictionary) -> void:
	var root: Node3D = s["root"]
	var mn: Node3D = s.get("model_node")
	var params: Dictionary = (s.get("params", {}) as Dictionary).duplicate()
	if mn != null:
		params["node"] = mn
	var pos: Vector3 = root.global_position + (s.get("fire_offset", Vector3.ZERO) as Vector3)
	var motion := String(s.get("motion", ""))
	if s.has("pre"):
		Juice.event(String(s["pre"]), pos + Vector3(0, 2.0, 0), params)
	if s.get("hide", false) and mn != null:
		mn.visible = false
		get_tree().create_timer(2.0).timeout.connect(func() -> void: mn.visible = true)
	if mn != null and motion != "":
		_animate(mn, motion)
	if motion == "slam" and mn != null:
		mn.position.y = 2.0
		# r3: the drop itself (0.12 s at about the real 11.7 m/s), so the attached drop streaks ride down with Mak.
		var dtw := create_tween()
		dtw.tween_interval(0.5)
		dtw.tween_property(mn, "position:y", 0.0, 0.12).set_ease(Tween.EASE_IN)
		# Juice fix r3: the real Ham Slam hovers slam_spin_time (0.5 s) before the drop; impact about 0.12 s later.
		get_tree().create_timer(0.62).timeout.connect(func() -> void:
			mn.position.y = 0.0
			Juice.event(String(s["event"]), root.global_position, params))
		return
	Juice.event(String(s["event"]), pos, params)
	if s.has("post"):
		get_tree().create_timer(float(s.get("post_delay", 1.4))).timeout.connect(func() -> void:
			Juice.event(String(s["post"]), pos, params))


func _animate(mn: Node3D, motion: String) -> void:
	if not motion in ["hop", "flip", "long", "dive", "slide", "slam"]:
		return  # no empty tweens ("started with no Tweeners")
	var base := mn.position
	var tw := create_tween()
	match motion:
		"hop":
			tw.tween_property(mn, "position:y", 1.4, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(mn, "position:y", 0.0, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		"flip":
			tw.set_parallel(true)
			tw.tween_property(mn, "position:y", 2.2, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(mn, "rotation:z", -TAU, 0.6)
			tw.set_parallel(false)
			tw.tween_property(mn, "position:y", 0.0, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(func() -> void: mn.rotation.z = 0.0)
		"long", "dive":
			tw.set_parallel(true)
			tw.tween_property(mn, "position:x", base.x + 1.4, 0.45)
			tw.tween_property(mn, "position:y", 0.6, 0.22).set_ease(Tween.EASE_OUT)
			tw.chain().tween_property(mn, "position:y", 0.0, 0.22).set_ease(Tween.EASE_IN)
			tw.chain().tween_property(mn, "position", base, 0.01).set_delay(1.0)
		"slide":
			tw.tween_property(mn, "position:x", base.x + 1.6, 1.4)
			tw.tween_property(mn, "position", base, 0.01).set_delay(0.6)
		_:
			tw.tween_interval(0.01)


## Close-up stills: for each station, cut to its camera, fire, and save frames <leads> after the event.
## --shots=<abs dir> [--leads=4,12,28] ; files <dir>/<group>_<nn>_<event>_f<lead>.png, then quits.
func _run_shots() -> void:
	var dir := String(_args["shots"])
	DirAccess.make_dir_recursive_absolute(dir)
	var leads: Array[int] = []
	for t in String(_args.get("leads", "4,12,28")).split(","):
		leads.append(int(t))
	var group := String(_args.get("group", "x"))
	for _i in 90:
		await get_tree().process_frame
	for i in stations.size():
		var s: Dictionary = stations[i]
		var root: Node3D = s["root"]
		var c := root.get_node_or_null("Cam_%d" % i) as Camera3D
		if c != null:
			c.current = true
		# r2: only this station's model is visible (the gameplay camera looks down the row).
		for j in stations.size():
			var other: Node3D = stations[j].get("model_node")
			if other != null and j != i:
				other.visible = false
		var own: Node3D = s.get("model_node")
		if own != null:
			own.visible = true
		_hud.text = String(s.get("label", s["event"]))
		for _k in 3:
			await get_tree().process_frame
		_fire(s)
		var frame := 0
		var extra := 37 if String(s.get("motion", "")) == "slam" else 0
		for lead in leads:
			while frame < lead + extra:
				await get_tree().process_frame
				frame += 1
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var ev := String(s["event"]).replace("/", "_")
			img.save_png("%s/%s_%02d_%s_f%02d.png" % [dir, group, i, ev, lead])
		for _k in 70:
			await get_tree().process_frame
	print("[JuiceLab] shots done: ", stations.size())
	get_tree().quit()


func _run_reel() -> void:
	await get_tree().create_timer(0.6).timeout
	for i in stations.size():
		var s: Dictionary = stations[i]
		var root: Node3D = s["root"]
		var c := root.get_node_or_null("Cam_%d" % i) as Camera3D
		if c != null:
			c.current = true
		# Juice fix r4 (critic r2: neighbouring models leaked into close-ups): only this station's model is visible.
		for j in stations.size():
			var other: Node3D = stations[j].get("model_node")
			if other != null:
				other.visible = j == i
		_hud.text = String(s.get("label", s["event"]))
		await get_tree().create_timer(0.35).timeout
		_fire(s)
		var hold := 1.9 if String(s.get("model", "")) != "wolf" else 2.6
		if s.has("post"):
			hold = maxf(hold, float(s.get("post_delay", 1.4)) + 0.8)
		await get_tree().create_timer(hold).timeout
	_cam.current = true
	for st in stations:
		var m: Node3D = st.get("model_node")
		if m != null:
			m.visible = true
	_hud.text = "Juice lab: all events"
	await get_tree().create_timer(0.3).timeout
	for s in stations:
		_fire(s)
