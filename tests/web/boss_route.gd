extends "res://scripts/boss/boss_bot.gd"
## Existing desktop player-input routine, with an in-memory result sink.
var result: Dictionary = {"done": false}

func _finish(why: String) -> void:
	if _done:
		return
	_done = true
	_stick(Vector2.ZERO)
	result = {"done": true, "why": why, "seconds": t, "phases": _phase_seen,
		"defeated": boss.defeated, "truffle": Game.has_truffle("BOSS-1"),
		"hits": boss.stats["hits"], "inputs": events, "teleports": 0}
	print("[WebRoute] boss ", JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("makReview").lastRoute = JSON.stringify(result)
