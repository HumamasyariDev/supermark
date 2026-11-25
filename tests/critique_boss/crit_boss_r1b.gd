extends "res://tests/critique_boss/crit_boss_r1.gd"
## BOSS critique r1 (boss fight design lens), probe B. Read-only: nothing in the boss track is modified.
## --crit-mode=p2idle (use with --boss-phase=2 --no-cine): stand still at the spawn for 30 s and log every charge,
##   state and damage (does P2 pressure an idle player?). Then the fall test: wolf hits set to 1, cake set to 1 slice,
##   Mak placed just outside the west parapet gap so he falls out naturally. Logs cake and wolf hits after the respawn.

var _fall_phase := 0
var _fall_t := 0.0
var _states: Array = []
var _last_state := ""


func _p1_probe(delta: float) -> void:
	if boss.state != _last_state:
		_last_state = boss.state
		_states.append([snappedf(t, 0.01), boss.state, int(game.get("health"))])
	if _fall_phase == 0:
		_stick(Vector2.ZERO)
		if t > 30.0:
			_idle = {"seconds": snappedf(t, 0.01), "health_end": int(game.get("health")), "pos_end": str(p.global_position.snapped(Vector3.ONE * 0.1)), "states": _states}
			boss.set("hits", 1)
			game.set("health", 1)
			_fall = {"before": {"health": int(game.get("health")), "wolf_hits": int(boss.hits), "phase": int(boss.phase)}}
			p.global_position = WolfRooftop.polar(284.0, 20.5, 1.0)
			p.set("ext_vel", Vector3.ZERO)
			_fall_phase = 1
			_fall_t = 0.0
			_note("FALL TEST: health 1, wolf hits 1, Mak outside the west gap")
	elif _fall_phase == 1:
		_stick(Vector2.ZERO)
		_fall_t += delta
		if _fall_t > 6.0:
			_fall["after"] = {"health": int(game.get("health")), "wolf_hits": int(boss.hits), "phase": int(boss.phase), "boss_state": boss.state,
				"pos": str(p.global_position.snapped(Vector3.ONE * 0.1)), "secs_after": snappedf(_fall_t, 0.01)}
			_fall_phase = 2
			_write("done")
