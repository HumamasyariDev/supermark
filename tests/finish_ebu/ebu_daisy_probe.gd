extends Node3D
## Finish pass (ENEMIES-BOSS-UI): Daisy talk check. Builds an NPCTalker with the ORIGINAL daisy_cow.glb (as W2 asks for
## v2), so ObjSvc.upgrade_character must hand it daisy_cow_v3; sets NpcLife talking and captures the open mouth.
## Run: python tools/godot.py run res://tests/finish_ebu/EbuDaisyProbe.tscn --seconds 60 -- --profile=ebu_daisy


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	add_child(sun)
	var ps := load("res://scenes/objects/NPCTalker.tscn") as PackedScene
	var npc := ps.instantiate() as Node3D
	npc.set("visual_scene", load("res://assets/characters/daisy_cow/daisy_cow_v2.glb"))
	npc.set("visual_scale", 1.0)
	npc.set("speaker", "Daisy")
	add_child(npc)
	await get_tree().create_timer(1.0).timeout
	var life: Variant = npc.get("life")
	var src := ""
	for n in npc.find_children("*", "Node3D", true, false):
		if String((n as Node).scene_file_path).contains("daisy_cow"):
			src = (n as Node).scene_file_path
			break
	print("[EBU-DAISY] model: ", src, " life: ", life != null)
	var head := npc.global_position + Vector3(0, 1.3, 0)
	for n in npc.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		var bi := sk.find_bone("head")
		if bi >= 0:
			head = sk.global_transform * sk.get_bone_global_pose(bi).origin
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 30.0
	var center := npc.global_position + Vector3(0, 0.8, 0)
	var dir := (head - center) * Vector3(1, 0, 1)
	dir = dir.normalized() if dir.length() > 0.05 else Vector3(0, 0, 1)
	var side := dir.cross(Vector3.UP)
	cam.global_position = head + dir * 1.9 + side * 0.7 + Vector3(0, 0.15, 0)
	cam.look_at(head)
	cam.make_current()
	if life != null:
		(life as Object).set("talking", true)
	for k in 3:
		await get_tree().create_timer(0.23).timeout
		var jaw := 0.0
		for n in npc.find_children("*", "Skeleton3D", true, false):
			var sk := n as Skeleton3D
			var bi := sk.find_bone("jaw")
			if bi >= 0:
				var rest := sk.get_bone_rest(bi).basis.get_rotation_quaternion()
				jaw = rad_to_deg((rest.inverse() * sk.get_bone_pose_rotation(bi)).get_euler().x)
		print("[EBU-DAISY] talking jaw x = %.1f deg" % jaw)
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://").path_join("../Docs/progress/finish/enemies_boss_ui/after_daisy_v3_talk_%d.png" % k).simplify_path())
	get_tree().quit()
