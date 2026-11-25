# HERO V2 critique tools (round 1, animation director lens)

These are test tools only. They change no gameplay file. The output goes to `Docs/progress/critique/hero_v2/r1_animation/`.

- `HeroV2AnimCritR1.tscn` / `hero_v2_anim_crit_r1.gd`: instances MoveLab and lets the real MakPlayer play a replay. A close camera follows him: `--view=side|3q|front|back`, `--dist`, `--fov` and `--yfollow`.
  - `--bones-out=<jsonl>` writes per-frame world positions of 26 bones.
  - It also writes the eyelid angle (`lid`), the hat tilt relative to the head (`hat_rel`), the head rotation relative to rest (`head_rot`) and the hips scale (`hips_s`).
- `record_r1.py --view side|3q [--dist 3.2] [-- --yfollow=40]`: records `replays/showcase_hero_v2.json` in chunks with Movie Maker through `tools/godot.py movie`. Each chunk becomes an MP4 and its AVI is deleted.
- `record_reel_r1.py --set a|b --views side 3q`: records PoseLab in-place clip reels of every move (set a: idle and ground moves; set b: air and combat moves). It writes a JSON index of clip start frames next to each MP4.
- `sheet.py <mp4> <out.png> <first> <last> <step> [--crop x,y,w,h]`: makes a numbered frame contact sheet. `reel_sheets.py <reel.mp4>` makes one sheet per clip.
- `analyse_r1.py <bones dir> side`: reports foot slip per speed band, hoof penetration, blinks, and the hat, pack, head and ear ranges per state.
