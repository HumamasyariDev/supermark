extends Node
## Look-dev only (TOPUP_WORLDS): swaps the boss arena's graybox chimneys and tea trolley for the generated
## props at runtime, so they can be judged in the real arena without editing the boss owner's files.
## Integration recipe for the boss owner: the same calls belong in BossChimney._ready()/smash() and wolf_rooftop.gd.

const CHIMNEY := preload("res://assets/props/boss/boss_chimney/boss_chimney.glb")
const BROKEN := preload("res://assets/props/boss/boss_chimney_broken/boss_chimney_broken.glb")
const TROLLEY := preload("res://assets/props/boss/tea_trolley/tea_trolley.glb")
const TEAPOT := preload("res://assets/props/boss/teapot/teapot.glb")
## Uniform scale that fits the 5.4 m chimney to BossChimney.size (1.9 x 3.6 x 1.9).
const CHIMNEY_SCALE := 0.7

var _swapped: Array = []


func _ready() -> void:
	for i in 3:
		await get_tree().process_frame
	for c in get_tree().get_nodes_in_group("boss_chimney"):
		var ch := c as Node3D
		for k in ch.get_children():
			if k is Node3D and not (k is CollisionShape3D) and not (k is CPUParticles3D) and not (k is GPUParticles3D):
				(k as Node3D).visible = false
		var intact := CHIMNEY.instantiate() as Node3D
		intact.name = "TopupChimney"
		intact.scale = Vector3.ONE * CHIMNEY_SCALE
		ch.add_child(intact)
		var broken := BROKEN.instantiate() as Node3D
		broken.name = "TopupChimneyBroken"
		broken.scale = Vector3.ONE * CHIMNEY_SCALE
		broken.visible = false
		ch.add_child(broken)
		_swapped.append([ch, intact, broken, ch.get_child_count()])
	var t := get_tree().current_scene.find_child("TeaTrolley", true, false) as Node3D
	if t != null:
		for k in t.get_children():
			if k is Node3D:
				(k as Node3D).visible = false
		var tr := TROLLEY.instantiate() as Node3D
		tr.scale = Vector3.ONE * 1.25
		t.add_child(tr)
		var pot := TEAPOT.instantiate() as Node3D
		pot.scale = Vector3.ONE * 0.7
		var sock := tr.find_child("teapot_socket", true, false) as Node3D
		(sock if sock != null else tr).add_child(pot)


func _process(_dt: float) -> void:
	# BossChimney.smash() hides its own visual and adds a box rubble pile: show the generated stump instead.
	for s in _swapped:
		var ch: Node3D = s[0]
		if is_instance_valid(ch) and ch.get("smashed") == true and (s[1] as Node3D).visible:
			(s[1] as Node3D).visible = false
			(s[2] as Node3D).visible = true
			for i in range(int(s[3]), ch.get_child_count()):
				var k := ch.get_child(i)
				if k is Node3D and k != s[2]:
					(k as Node3D).visible = false
