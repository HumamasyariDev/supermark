# Topup characters look-dev (not gameplay)

`TopupLineup.tscn` + `topup_lineup.gd` load every character delivered by the TOPUP_CHARS track, wrap each in a `Visual` node turned 180 degrees, pose a few bones in-engine and run a small procedural motion loop (snore, sway, wave, graze, tail flick) to prove the skins work in Godot 4.7. Mr. Mak (`mak/mak.glb`) stands in the row for scale. Cameras: `Cam_Lineup`, `Cam_Close`, `Cam_Foreman`, `Cam_Big`. Captures: `Docs/progress/assets/topup/*__topup_chars_godot_*`. Safe to delete once the worlds use the characters.

## Round 3 check scene

`TopupR3Check.tscn` + `topup_r3_check.gd` put each accepted file next to its round-3 replacement (`*_v2.glb`, `pip_v3.glb`) on the real
Skeleton3D. Pass `-- --only=<group>`: `snap` (rest, -40, -55, +40, salute; cameras `Cam_snap`, `Cam_snap_Close`), `scarecrow`
(`Cam_scarecrow`, `Cam_scarecrow_Top`), `cow` (`Cam_cow`, `Cam_cow_Close`), `sheep`, `giant`, `lineup` (`Cam_lineup`, `Cam_lineup_Low`),
`ao` (`Cam_ao`, `Cam_ao_Close`: before/after AO with the sun dimmed), `props` (`Cam_props`: Snap v2 with the lance on `hand_r` and the drum on
`hips`, rest-basis vs posed-basis aiming) and `motion` (`Cam_motion`, a looping pose cycle for Movie Maker). Captures:
`Docs/progress/topup_chars/r3_fix/`. Not gameplay; safe to delete once the worlds use the r3 files.

## Round 5 check scene

`TopupR5Check.tscn` + `topup_r5_check.gd`: `-- --only=cow` (Daisy v2 at jaw -10 as npc_life drives it today, then v3 at 0 / +12 /
+20 / -10; cameras `Cam_cow`, `Cam_cow_P0..P4`), `orm` (Bramwell and the golden goose, v1 | v2; `Cam_orm`, `Cam_orm_Close`),
`wolf` (wolf boss v1 | v2; `Cam_wolf`, `Cam_wolf_Close`), `cow_motion` (v3 moo loop next to v2; `Cam_cow_motion`, for Movie Maker).
Captures: `Docs/progress/topup_chars/r5_fix/`. Not gameplay.
