# TOPUP_CHARS critique tests

Test scene only (not gameplay): `res://tests/critique_topup_chars/CritTopupCharsR1.tscn`.

Round 1 (asset QA lens) builds one row per TOPUP_CHARS model with Mr. Mak for scale and a battery of skeleton test poses:
rest, idle (arms down 45 deg), cheer (arms up 80 deg), stride, crouch, head turn + elbow bend, back view, side view.
Quadrupeds get rest, graze, head turn + tail, walk, back and side; the giant gets the W2 sit-up (head lift 0.5 m, jaw 16, nostrils 1.35);
the scarecrow gets jaw 25 + body sway + cans.

```
python tools/godot.py capture res://tests/critique_topup_chars/CritTopupCharsR1.tscn <out.png> --wait 45 --cam Cam_<id>[_Back|_Close] -- --profile=crit_topup_chars --only=<id>
python tools/godot.py movie res://tests/critique_topup_chars/CritTopupCharsR1.tscn <out.avi> --frames 300 -- --profile=crit_topup_chars --only=sweep
```

ids: snap, foreman, underwear, jack, hazel, bertram, pip, sheep, cow, giant, scarecrow (giant also has `Cam_giant_Side`).
Evidence: `Docs/progress/critique/topup_chars/r1_asset_qa/`, clip `Recordings/night01/M3/20261017T202925Z__crit_topup_chars_r1_sweep.mp4`.

## Round 1, pass B (asset QA, after the first r1 fixes)

`res://tests/critique_topup_chars/CritTopupCharsR1b.tscn` re-checks the fixed files and adds mirror-symmetry and gameplay-distance tests.
It hides 3D nodes that autoloads add outside the test scene.

```
python tools/godot.py capture res://tests/critique_topup_chars/CritTopupCharsR1b.tscn <out.png> --wait 30 --cam <Cam> --no-import -- --profile=crit_topup_chars_r1b --only=<group>
```

Groups and cameras: snap (Cam_snap, Cam_snap_Close, Cam_snap_Legs, Cam_snap_Side), pip (Cam_pip, Cam_pip_Close, Cam_pip_Low),
scarecrow (Cam_scarecrow, Cam_scarecrow_Close, Cam_scarecrow_Top), sym (Cam_sym, Cam_sym_Arms), lineup (Cam_lineup, Cam_lineup_Low).
Evidence: `Docs/progress/critique/topup_chars/r1_asset_qa/*__r1b_*.png`.

## Round 2 (asset QA, after fix pass C)

No new scene: round 2 re-runs `CritTopupCharsR1b.tscn` (groups snap and scarecrow) on the 06:05 and 06:09 game files, with `--profile=crit_topup_chars_r2`.
The ORM roughness/AO audit is a short PIL script over `assets/characters/*/*_ORM_*.webp` (mean roughness, 5th percentile, AO mean and spread).
Evidence: `Docs/progress/critique/topup_chars/r2_asset_qa/` (6 native captures plus 2 zoom crops).
