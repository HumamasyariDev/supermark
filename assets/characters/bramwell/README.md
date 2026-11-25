# Bramwell (tortoise butler)

`bramwell.glb`: static (unrigged) Tripo mesh, 1.5 m tall, one Tripo PBR material. Faces glTF +Z (wrap in a `Visual` Node3D
rotated 180 degrees about Y).

## Round 5 (2026-10-19, ASSETS3_CHARS): use `bramwell_v2.glb`

Use this file: `res://assets/characters/bramwell/bramwell_v2.glb`. It is a byte-for-byte copy of `bramwell.glb` except the ORM
image and one material field, so it is a pure path swap (same node names, size, origin).

- ORM.R: Cycles self-occlusion AO (distance 0.21 m, strength 0.85, floor 0.30; mean 0.76), wired as the glTF occlusionTexture,
  so Godot 4.7 uses it as `ao_texture`. Before: flat 1.0 (no AO at all).
- ORM.G: roughness floor 0.72 (before 0.40, which read as wet plastic on the tailcoat and shell). ORM.B (metal) unchanged.
- Evidence: `Docs/progress/topup_chars/r5_fix/*__r5fix_Cam_orm*` (native, before | after) and
  `*__r5fix_blender_bramwell_wolf_v1_v2.png`. Tools: `assets_src/topup/chars/tools/fix_r5/` (`bake_ao_map.py`, `orm_pack_r5.py`).
- Swap (hub, W3 and boss owners): every `res://assets/characters/bramwell/bramwell.glb` -> `.../bramwell/bramwell_v2.glb`, no transform change.
