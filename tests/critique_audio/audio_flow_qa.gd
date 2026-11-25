extends Node
## Critique audio r1 (QA lens). Drives the REAL scene flow through the Router
## (title -> hub -> W1 (+truffle jingle, +checkpoint reload) -> hub -> W2 -> W3 -> BOSS -> title)
## with scripted pad input, and records:
##   - every AudioStreamPlayer start in the whole tree (stream, bus, volume, node), steals and restarts,
##   - concurrency per bus, duplicate starts of one stream within 60 ms, plays per second,
##   - a 10 Hz timeline of music/ambience state (keys, streams, player volumes, bus peaks),
##   - engine warnings/errors (missing keys, load errors) attributed to the active scene.
## The monitor lives under /root so it survives change_scene. Output: --qa-out=<abs dir> (JSON files).
## Run: python tools/godot.py run res://tests/critique_audio/AudioFlowQA.tscn --seconds 400 -- --profile=critique_audio
##      --qa-out=<abs dir> [--qa-short] [--juice-sfx-log]

func _ready() -> void:
	var mon := Node.new()
	mon.set_script(load("res://tests/critique_audio/audio_flow_monitor.gd"))
	mon.name = "AudioFlowMonitor"
	get_tree().root.add_child.call_deferred(mon)
