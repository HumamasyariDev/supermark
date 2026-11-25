extends Node
## Critique W1 round 1 (QA lens, pass r1c) harness: seeds three W1 pages into the (throwaway) test profile to model a player
## who found P1-P3 on an earlier visit, adds the QA probe under /root, then loads W1 as the current scene.
## Run: python tools/godot.py run res://tests/critique_w1/W1QA_r1c.tscn --seconds 1500 -- --profile=critic_w1_qa_<utc> --spawn=Default --qa-out=<abs dir>

const PROBE := preload("res://tests/critique_w1/w1_qa_r1c.gd")


func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	var dev := get_node_or_null("/root/Dev")
	if game and dev and dev.has_arg("qa-seed-pages"):
		for i in [0, 1, 2]:
			game.call("collect_page", "W1", i)
	var probe: Node = PROBE.new()
	probe.name = "W1QAProbe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w1/W1.tscn")
