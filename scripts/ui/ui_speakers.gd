class_name UISpeakers
extends RefCounted
## Dialog speakers: name -> [real 3D model, name-plate colour, portrait yaw offset (radians)].
## Lookup is case-insensitive; the first key the speaker name starts with or contains wins.

const C := "res://assets/characters/"
## speaker name (lower case, first match by prefix) -> [model, plate colour, portrait yaw]
const SPEAKERS := {
	"bramwell": [C + "bramwell/bramwell.glb", Color("2e6f6a"), 0.0],
	"mr. mak": [C + "mak/mak_v2.glb", Color("8e1f2f"), 0.0],
	"mak": [C + "mak/mak_v2.glb", Color("8e1f2f"), 0.0],
	"sir reginald": [C + "wolf_boss/wolf_boss.glb", Color("4a2f6b"), 0.0],
	"huffington": [C + "wolf_boss/wolf_boss.glb", Color("4a2f6b"), 0.0],
	"the wolf": [C + "wolf_boss/wolf_boss.glb", Color("4a2f6b"), 0.0],
	"wolf": [C + "wolf_boss/wolf_boss.glb", Color("4a2f6b"), 0.0],
	"pip": [C + "pip_v2/pip_v2.glb", Color("b8733a"), 0.0],
	"golden goose": [C + "golden_goose/golden_goose.glb", Color("c98a1b"), 0.0],
	"goose": [C + "golden_goose/golden_goose.glb", Color("c98a1b"), 0.0],
	"jack": [C + "jack/jack.glb", Color("3e9a45"), 0.0],
	"hazel": [C + "hazel/hazel.glb", Color("d0607a"), 0.0],
	"bertram": [C + "bertram/bertram.glb", Color("6b4430"), 0.0],
	"daisy": [C + "daisy_cow/daisy_cow_v3.glb", Color("3f8f3a"), 0.0],
	"foreman": [C + "foreman/foreman.glb", Color("b84a32"), 0.0],
	"sergeant snap": [C + "sergeant_snap/sergeant_snap.glb", Color("8a4e24"), 0.0],
	"snap": [C + "sergeant_snap/sergeant_snap.glb", Color("8a4e24"), 0.0],
	"giant": [C + "sleeping_giant/sleeping_giant.glb", Color("7c86d9"), 0.0],
	"sheep": [C + "real_sheep/real_sheep.glb", Color("6d8f3a"), 0.0],
}


static func info(speaker: String) -> Array:
	var s := speaker.to_lower().strip_edges()
	if s == "":
		return ["", UIStyle.RIBBON, 0.0]
	if SPEAKERS.has(s):
		return SPEAKERS[s]
	for k in SPEAKERS.keys():
		if s.begins_with(k) or s.contains(String(k)):
			return SPEAKERS[k]
	return ["", UIStyle.RIBBON, 0.0]


static func list() -> Array:
	return SPEAKERS.keys()
