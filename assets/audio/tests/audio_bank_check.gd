extends SceneTree
## Headless check of the audio bank: every key in audio_index.json resolves, loads as an AudioStream,
## has a sane length, and loop flags in the import match the index. Prints one JSON summary line.

const INDEX := "res://assets/audio/audio_index.json"


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	var ok := 0
	var bad: Array = []
	var loops_ok := 0
	var total_len := 0.0
	var seen := {}
	var offsets := {}
	for e in parsed["entries"]:
		var files: Array = e.get("files", [e.get("file", "")])
		for f in files:
			var path := "res://assets/audio/" + String(f)
			if seen.has(path):
				continue
			seen[path] = true
			var s := load(path) as AudioStream
			if s == null:
				bad.append(path)
				continue
			var length := s.get_length()
			total_len += length
			if length <= 0.05 or length > 200.0:
				bad.append("%s length %.2f" % [path, length])
				continue
			if bool(e.get("loop", false)):
				if s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop:
					loops_ok += 1
					if (s as AudioStreamOggVorbis).loop_offset > 0.0:
						offsets[String(f)] = snappedf((s as AudioStreamOggVorbis).loop_offset, 0.01)
				else:
					bad.append("%s not looping in import" % path)
					continue
			ok += 1
	print("AUDIO_BANK_CHECK ", JSON.stringify({"keys": parsed["entries"].size(), "files": seen.size(), "ok": ok,
		"loops_ok": loops_ok, "loop_offsets": offsets, "total_seconds": snappedf(total_len, 0.1), "bad": bad}))
	quit(0 if bad.is_empty() else 1)
