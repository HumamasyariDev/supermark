extends "res://tests/critique_boss/crit_boss_r1.gd"
## BOSS critique r1 (boss fight design lens), probe C. Read-only: nothing in the boss track is modified.
## --crit-mode=ringcheck (P1, --no-cine): after the intro prewarm, log every P3 tea-ring piece (visible, monitorable,
## global position) and walk Mak straight north across the roof centre during the sip opener, logging any damage.

var _rc_logged := false
var _ring_rows: Array = []
var _cross: Dictionary = {}


func _p1_probe(_delta: float) -> void:
	if not _rc_logged and t > 0.8:
		_rc_logged = true
		var r: Node3D = boss.ring
		_cross["ring_exists"] = r != null
		if r != null:
			_cross["ring_visible"] = r.visible
			_cross["ring_pos"] = str(r.global_position)
			for a in boss.ring_pieces:
				var ar := a as Area3D
				_ring_rows.append({"pos": str(ar.global_position.snapped(Vector3.ONE * 0.01)), "monitorable": ar.monitorable,
					"layer": ar.collision_layer, "in_hazard_group": ar.is_in_group("hazard"), "r": snappedf(Vector2(ar.global_position.x, ar.global_position.z).length(), 0.01)})
		_cross["ring_on"] = boss.ring_on
		_cross["boss_state"] = boss.state
		p.global_position = Vector3(-2.4, 0.05, 6.0)
		_cross["health_before"] = int(game.get("health"))
		_note("RINGCHECK: %d pieces logged, Mak placed at (-2.4, 0, 6), walking north" % _ring_rows.size())
	if _rc_logged and not _cross.has("health_after"):
		_stick(Vector2.ZERO)
		if t < 3.4:
			_move_to(Vector3(-2.4, 0, -6.0), 0.2)
		else:
			_cross["health_after"] = int(game.get("health"))
			_cross["pos_after"] = str(p.global_position.snapped(Vector3.ONE * 0.1))
			_note("RINGCHECK done: health %d -> %d" % [_cross["health_before"], _cross["health_after"]])
			_idle = {"ringcheck": _cross, "pieces": _ring_rows}
			_write("complete")
