class_name BossCrow
extends Node3D
## Crow Bandit for the boss arena, on the rigged Tripo P2 crow (res://assets/enemies/crow_bandit/crow_bandit.glb),
## animated procedurally like the wolf. Spectators perch on the coping and cackle; minions (EN_crow_1/2)
## orbit at r 13, y 6.5 and dive onto the vent Mak is loading (cackle at +0.4 s, shadow for 1.0 s,
## impact at +1.4 s), then sit dazed for 1.2 s: punch, kick or stomp one for feathers and 3 acorns.

const GLB := "res://assets/enemies/crow_bandit/crow_bandit.glb"
const CROW_BONES := ["root", "hips", "spine", "head", "thigh_l", "shin_l", "thigh_r", "shin_r", "beak", "tail", "tail_2",
	"arm_l", "forearm_l", "hand_l", "arm_r", "forearm_r", "hand_r"]

signal defeated_crow(crow: BossCrow)

var boss: Node
var mode := "perch"
var t := 0.0
var perch := Vector3.ZERO
var perch_yaw := 0.0
var orbit_a := 0.0
var orbit_r := 13.0
var orbit_y := 6.5
var target := Vector3.ZERO
var rig: WolfRig
var hurt: BossWeakpoint
var shadow: MeshInstance3D
var nigel := false
var _from := Vector3.ZERO
var _cackle_t := -1.0
var _flap := 0.0
var _hop := 0.0


func _ready() -> void:
	rig = WolfRig.new()
	rig.glb_path = GLB
	rig.bone_names = CROW_BONES
	rig.with_cane = false
	add_child(rig)
	rig.set_layers(3)
	if nigel:
		scale = Vector3.ONE * 1.1
	hurt = BossWeakpoint.make(self, "crow", 0.8, 1.3)
	hurt.position = Vector3(0, -0.1, 0)
	add_child(hurt)
	hurt.set_open(true)
	shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	shadow.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.03, 0.08, 0.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = m
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.top_level = true
	add_child(shadow)
	if mode == "perch":
		global_position = perch
		rotation.y = perch_yaw


func take_off() -> void:
	mode = "orbit"
	t = 0.0
	_from = global_position
	orbit_a = atan2(global_position.x, -global_position.z)
	EnemyKit.sfx(self, "crow_caw", global_position)


func cackle() -> void:
	_cackle_t = 0.5
	EnemyKit.sfx(self, "crow_caw_2" if randf() < 0.5 else "crow_caw", global_position)


func flap_up() -> void:
	if mode == "perch":
		_hop = 2.0


func dive_at(p: Vector3) -> void:
	if mode != "orbit":
		return
	mode = "windup"
	t = 0.0
	target = Vector3(p.x, 0.0, p.z)
	_from = global_position


func weak_hit(_tag: String, kind: String, from_position: Vector3) -> bool:
	if mode != "recover":
		return false
	if not (kind in ["punch", "kick", "jump_kick", "dive", "slide", "stomp", "slam"]):
		return false
	mode = "dead"
	t = 0.0
	if ResourceLoader.exists("res://scenes/fx/FeatherBurst.tscn"):
		FxEffect.spawn(get_parent(), "res://scenes/fx/FeatherBurst.tscn", global_position + Vector3(0, 0.5, 0))
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.6, 0), "stars", [Color(1, 0.95, 0.6)], 12, 5.0)
	EnemyKit.sfx(self, "enemy_hit", global_position)
	EnemyKit.sfx(self, "enemy_defeat_poof", global_position)
	EnemyKit.drop_acorns(get_parent(), global_position + Vector3(0, 0.6, 0), 3)
	_from = global_position
	var away := global_position - from_position
	away.y = 0.0
	target = global_position + away.normalized() * 6.0 + Vector3(0, 9.0, 0)
	defeated_crow.emit(self)
	return true


func is_busy() -> bool:
	return mode == "windup" or mode == "dive" or mode == "recover"


func _player() -> Node3D:
	return EnemyKit.find_player(get_tree())


func _physics_process(delta: float) -> void:
	t += delta
	var sm := shadow.material_override as StandardMaterial3D
	match mode:
		"perch":
			global_position = perch + Vector3(0, absf(sin(t * TAU)) * 0.03 + _hop_y(delta), 0)
			rotation.y = perch_yaw
			sm.albedo_color.a = 0.0
		"orbit":
			orbit_a += delta * 0.45
			var want := Vector3(sin(orbit_a) * orbit_r, orbit_y + sin(t * 1.3) * 0.4, -cos(orbit_a) * orbit_r)
			var prev := global_position
			global_position = global_position.lerp(want, 1.0 - exp(-2.5 * delta))
			var mv := global_position - prev
			if mv.length() > 0.001:
				rotation.y = atan2(-mv.x, -mv.z)
			sm.albedo_color.a = 0.0
		"windup":
			if t >= 0.4 and t - delta < 0.4:
				cackle()
			var k := clampf((t - 0.4) / 1.0, 0.0, 1.0)
			shadow.global_position = target + Vector3(0, 0.03, 0)
			shadow.scale = Vector3(0.3 + 0.9 * k, 1, 0.3 + 0.9 * k)
			sm.albedo_color.a = 0.15 + 0.45 * k
			if t >= 0.4:
				var e := k * k
				var mid := _from.lerp(target, 0.5) + Vector3(0, 3.0, 0)
				var pos := _from.lerp(mid, e).lerp(mid.lerp(target + Vector3(0, 0.6, 0), e), e)
				var dir := pos - global_position
				global_position = pos
				if Vector2(dir.x, dir.z).length() > 0.01:
					rotation.y = atan2(-dir.x, -dir.z)
			if t >= 1.4:
				_impact()
		"recover":
			global_position = target + Vector3(0, 0.25, 0)
			sm.albedo_color.a = 0.0
			if t > 1.2:
				mode = "orbit"
				t = 0.0
		"dead":
			var k := clampf(t / 1.2, 0.0, 1.0)
			global_position = _from.lerp(target, k)
			rotation.z += delta * 14.0
			scale = Vector3.ONE * (1.0 - k * 0.6)
			if k >= 1.0:
				queue_free()
	_animate(delta)


func _hop_y(delta: float) -> float:
	if _hop <= 0.0:
		return 0.0
	_hop -= delta
	return sin(clampf(_hop / 2.0, 0.0, 1.0) * PI) * 1.2


func _impact() -> void:
	mode = "recover"
	t = 0.0
	EnemyKit.burst(get_parent(), target + Vector3(0, 0.3, 0), "dust", [Color(0.6, 0.55, 0.6)], 12, 4.0)
	EnemyKit.sfx(self, "crow_swoop", target)
	var p := _player()
	if p == null:
		return
	var d := p.global_position - target
	if Vector2(d.x, d.z).length() < 1.3 and d.y < 1.6:
		if p.has_method("take_damage"):
			p.call("take_damage", 1, target)
		var g := get_node_or_null("/root/Game")
		# No second steal within 2 s of the last one (r1 fun minor).
		var fresh := boss == null or not ("last_steal_t" in boss) or float(boss.get("_clock")) - float(boss.get("last_steal_t")) > 2.0
		if fresh and g != null and g.has_method("spend_acorns") and int(g.get("acorns")) >= 3:
			g.call("spend_acorns", 3)
			if boss != null and "last_steal_t" in boss:
				boss.set("last_steal_t", float(boss.get("_clock")))
		if boss != null and boss.has_method("bark"):
			boss.call("bark", "bark_crow", "Good boy, Nigel.")


func _animate(delta: float) -> void:
	if rig == null:
		return
	rig.begin()
	var flying := mode == "orbit" or mode == "windup" or mode == "dead" or _hop > 0.0
	if flying:
		_flap += delta * (6.0 if (mode != "windup" or t < 0.4) else 2.0) * TAU
		var f := sin(_flap)
		var fold := mode == "windup" and t > 0.8
		var spread := 0.2 if fold else 0.9 + f * 0.8
		rig.pose("arm_l", Vector3(0, 0, spread))
		rig.pose("arm_r", Vector3(0, 0, -spread))
		rig.pose("forearm_l", Vector3(0, 0, -0.3 * f))
		rig.pose("forearm_r", Vector3(0, 0, 0.3 * f))
		rig.pose("thigh_l", Vector3(0.9, 0, 0))
		rig.pose("thigh_r", Vector3(0.9, 0, 0))
		rig.pose("spine", Vector3(0.5 if fold else 0.2, 0, 0))
		rig.pose("tail", Vector3(-0.3, 0, 0))
	else:
		var c := 0.0
		if _cackle_t > 0.0:
			_cackle_t -= delta
			c = absf(sin(_cackle_t * 30.0))
		rig.pose("head", Vector3(-0.3 * c + sin(t * 0.8) * 0.1, sin(t * 0.5) * 0.4, 0))
		rig.pose("beak", Vector3(0.4 * c, 0, 0))
		# Wings folded at the sides (the rig rests with them spread), a little flap on the cackle.
		rig.pose("arm_l", Vector3(0.2, 0, -1.25 + 0.5 * c))
		rig.pose("arm_r", Vector3(0.2, 0, 1.25 - 0.5 * c))
		rig.pose("forearm_l", Vector3(0, 0, -0.4))
		rig.pose("forearm_r", Vector3(0, 0, 0.4))
		rig.pose("tail", Vector3(0, sin(t * 2.0) * 0.15, 0))
		if mode == "recover":
			rig.pose("head", Vector3(sin(t * 12.0) * 0.3, cos(t * 12.0) * 0.3, 0))
			rig.root_rot.z = sin(t * 9.0) * 0.2
	rig.update(delta)
