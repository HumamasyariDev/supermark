extends Node
## Jingle audibility check (Movie Maker): music_w1 for 3 s, then play_jingle("truffle_get") (4 s), then music returns.
## Measure the recording's loudness per window: the jingle window must be louder than the music-only window.
var t := 0.0
var done := false

func _ready() -> void:
	var a := get_node_or_null("/root/Audio")
	a.call("play_music", "music_w1", 0.01)

func _process(d: float) -> void:
	t += d
	if t >= 3.0 and not done:
		done = true
		get_node("/root/Audio").call("play_jingle", "truffle_get")
