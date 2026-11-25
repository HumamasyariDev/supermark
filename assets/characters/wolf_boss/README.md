# Wolf boss (Sir Reginald Huffington III)

Rig, bones and sockets: see `ATTACH.md` (unchanged).

## Round 5 (2026-10-19, ASSETS3_CHARS): use `wolf_boss_v2.glb`

Use this file: `res://assets/characters/wolf_boss/wolf_boss_v2.glb`. It is a copy of `wolf_boss.glb` with only the ORM image
replaced and an occlusionTexture added to the Tripo material: mesh, skin, bone names and rest poses, the monocle and every node
name are byte-identical, so `wolf_rig.gd` / `wolf_recipes.gd` work unchanged (a Blender re-export was avoided on purpose: it
changes bone rests).

- ORM.R: Cycles self-occlusion AO (distance 0.59 m, strength 0.80, floor 0.30; mean 0.74). Before: flat 1.0.
- ORM.G: roughness floor 0.78 for fur and cloth (before 0.50: the waistcoat and coat had a plastic sheen); metal texels unchanged.
- Evidence: `Docs/progress/topup_chars/r5_fix/*__r5fix_Cam_wolf*` (native before | after), `*__r5fix_blender_bramwell_wolf_v1_v2.png`.
- Swap (boss owner): every `res://assets/characters/wolf_boss/wolf_boss.glb` -> `.../wolf_boss/wolf_boss_v2.glb`, no other change.
