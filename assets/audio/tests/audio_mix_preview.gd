extends Node
## Mix preview in a real world: loads the world scene (its WorldRoot starts the music), starts the area ambience bed,
## then fires a scripted gameplay sound sequence through the Juice bus at the player (run, jumps, landings, acorn chain,
## an enemy encounter, a page, a Ham Slam, a cheer), followed by a few seconds of music and ambience alone.
## Args: --world=HUB|W1|W2|W3|BOSS. Record: python tools/godot.py movie res://assets/audio/tests/AudioMixPreview.tscn
##   <out.avi> --frames 1500 -- --world=W1 --juice-sfx-all --profile=audio

const WORLDS := {"HUB": "res://scenes/hub/Hub.tscn", "W1": "res://scenes/worlds/w1/W1.tscn", "W2": "res://scenes/worlds/w2/W2.tscn",
	"W3": "res://scenes/worlds/w3/W3.tscn", "BOSS": "res://scenes/boss/WolfRooftop.tscn"}
const SURF := {"HUB": "carpet", "W1": "grass", "W2": "cloud", "W3": "candy", "BOSS": "stone"}
const FAMILY := {"HUB": "woolly_wolf", "W1": "woolly_wolf", "W2": "bumble_bruiser", "W3": "gingerbread_grenadier", "BOSS": "crow_bandit"}

var world := "W1"
var t := 0.0
var seq: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world = a.substr(8).to_upper()
	var ps := load(WORLDS.get(world, WORLDS["W1"])) as PackedScene
	add_child(ps.instantiate())
	var s: String = SURF.get(world, "grass")
	var f: String = FAMILY.get(world, "woolly_wolf")
	seq = [[1.0, "amb"]]
	for i in 10:
		seq.append([2.0 + i * 0.3, "player_footstep", {"surface": s, "speed": 7.0}])
	seq += [[5.1, "player_jump", {"kind": "jump"}], [5.6, "player_land", {"impact": 6.0, "surface": s}],
		[5.75, "player_jump", {"kind": "double_jump"}], [6.4, "player_land", {"impact": 8.5, "surface": s}],
		[6.55, "player_jump", {"kind": "triple_jump"}], [7.6, "player_land", {"impact": 13.0, "surface": s}]]
	for i in 6:
		seq.append([8.4 + i * 0.16, "object_acorn_collect", {}])
	seq += [[10.0, "enemy_notice", {"family": f}, Vector3(4, 1, -6)], [11.0, "player_attack", {"kind": "punch", "step": 1}],
		[11.05, "enemy_hurt", {"family": f}, Vector3(3, 1, -4)], [11.4, "player_attack", {"kind": "kick"}],
		[11.45, "enemy_defeat", {"family": f}, Vector3(3, 1, -4)], [12.6, "object_page_collect", {"index": 2}],
		[13.4, "player_jump", {"kind": "jump"}], [13.8, "player_ham_slam_start", {}], [14.4, "player_slam", {"impact": 15.0, "surface": s}],
		[15.4, "player_celebrate", {}]]


func _process(delta: float) -> void:
	t += delta
	while not seq.is_empty() and t >= float(seq[0][0]):
		var e: Array = seq.pop_front()
		if e[1] == "amb":
			var audio := get_node_or_null("/root/Audio")
			if audio:
				audio.call("play_ambience", "amb_" + world.to_lower())
			continue
		var p := get_tree().get_first_node_in_group("player") as Node3D
		var base := p.global_position if p else Vector3.ZERO
		var pos: Vector3 = base + (e[3] if e.size() > 3 else Vector3.ZERO)
		var j := get_node_or_null("/root/Juice")
		if j:
			j.call("event", String(e[1]), pos, e[2])
