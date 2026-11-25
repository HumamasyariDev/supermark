# _topup_v2_preview (look-dev only, not gameplay)

`TopupV2Preview.tscn` loads the hub environment (`env_HUB.tres`) and the hub sun colour and shows two identical sets: `New` (all v2
models, plus `mak_v2.glb` in a test pose) and `Before` (the procedural models they replace, 40 m to +X). Cameras: `Cam_Wide_v2` /
`Cam_Wide_before`, `Cam_Hub_*`, `Cam_Mak_*`, `Cam_Pickups_*`, `Cam_MakPose_v2`. The v2 set animates the clock pendulum and hands, the
chandelier sway and the truffle spin, and prints a rig comparison of `mak.glb` against `mak_v2.glb`. No level uses this scene.

    python tools/godot.py capture res://assets/props/hub/_topup_v2_preview/TopupV2Preview.tscn out.png --wait 90 --cam Cam_Wide_v2 -- --profile=topup_hub
