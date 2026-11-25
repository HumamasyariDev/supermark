extends SceneTree
## Decodes music loops through Godot's own AudioStreamPlayback (mix_audio, no audio device) from the start,
## for the whole file plus 4 s, and writes raw float32 stereo PCM so the wrap to loop_offset can be verified offline.
## Usage: tools/godot.py script res://assets/audio/tests/loop_wrap_dump.gd -- --out=<dir> [--names=a,b]

func _init() -> void:
	var out_dir := "user://wrap"
	var names := ["title_storybook_overture", "boss_huffington"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--names="):
			names = a.substr(8).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for name in names:
		var s := load("res://assets/audio/music/%s.ogg" % name) as AudioStreamOggVorbis
		s.loop = true
		var pb := s.instantiate_playback()
		pb.start(0.0)
		var want := int(44100.0 * (s.get_length() + 4.0))
		var f := FileAccess.open(out_dir.path_join(name + ".f32"), FileAccess.WRITE)
		var total := 0
		while total < want:
			var chunk: PackedVector2Array = pb.mix_audio(1.0, mini(want - total, 4096))
			if chunk.is_empty():
				break
			for v in chunk:
				f.store_float(v.x)
				f.store_float(v.y)
			total += chunk.size()
		f.close()
		print("WRAP_DUMP ", name, " frames=", total, " len=", s.get_length(), " offset=", s.loop_offset)
	quit(0)
