# HERO critique tests

Test scenes only (not gameplay). Owner: HERO critics.

## Round 1, CHARACTER VISUALS lens

`res://tests/critique_hero/CritHeroVisualR1.tscn` loads a real world scene (the director node survives the scene change on the root),
waits `--settle` frames, prints mesh statistics for every visible mesh under the player (triangles, vertex split ratio, skinned,
materials), then saves native captures of the shipped player model in that world's lighting:

- gameplay camera at spawn, while running forward (`--walk` frames of `move_forward`), and settled after stopping
- face front, face 3/4, full body 3/4, profile, back 3/4, backpack close-up
- far views (7 m behind/above, 14 m to the side) for readability against the world
- top hat variant (the player's own `set_hat("top_hat")`): face 3/4, full front, 7 m behind

```
python tools/godot.py run res://tests/critique_hero/CritHeroVisualR1.tscn --seconds 200 --no-import -- --profile=crit_hero_r1 --hide-hud \
    --settle=480 --walk=70 --world=res://scenes/worlds/w1/W1.tscn --tag=w1 --out=<abs>/Docs/progress/critique/hero/r1_visual
```

Worlds used: `res://scenes/worlds/w1/W1.tscn`, `w2/W2.tscn`, `w3/W3.tscn`, `res://scenes/hub/Hub.tscn`. Run the hub and W3 twice on a
fresh profile: the first run plays the world intro (flag `hub_intro_seen` / `w3_intro_seen`), the second shows the gameplay camera.

Motion clip: `w1_visual_run.json` is a W1 replay (run, jump, double jump, three strikes, turns, crouch, jump):

```
python tools/godot.py movie res://scenes/worlds/w1/W1.tscn <abs>.avi --frames 840 --size 1600x900 -- --profile=crit_hero_r1 --hide-hud \
    --replay=<abs>/game/tests/critique_hero/w1_visual_run.json --replay-hold
```

Evidence: `Docs/progress/critique/hero/r1_visual/` (REPORT.md there).

Re-run on the current build (tag prefix `r1b-`, profile `crit_hero_r1b`): `log_r1b_visual.py <rows.json>` appends evidence rows
(`[{file, caption, observed, type?}]`, feature `critique-hero-r1-visual`) through `game/tests/log_evidence.py`.

## Round 1, GAME FEEL AND CAMERA lens

`res://tests/critique_hero/FeelCamProbeR1.tscn` instances MoveLab (default) or a world (`--scene=`), lets the real MakPlayer play a replay
and logs the gameplay camera every rendered frame to `--cam-out=` (position, pitch, yaw, arm, occlusion, inside-geometry, Mak's screen
position). `feel_r1.py` builds the sweeps (chain, buffer, wall kick, approach angles, platforms, lip, response, camera tour);
`feel_r1_post.py` re-runs the same replays on a newer build into `Docs/progress/critique/hero/r1_feel/post/` and adds `circle`
(camera-relative steering, held stick). `analyse_feel_post.py [folder]` prints chain/lip/wall-kick outcomes and camera statistics
(touchdown motion is measured relative to Mak per physics tick, because loaded headless runs render sparse frames).
`plot_feel_post.py <utc>` writes the before/after charts.

    python game/tests/critique_hero/feel_r1_post.py chain_sweep lip_sweep circle
    python game/tests/critique_hero/analyse_feel_post.py Docs/progress/critique/hero/r1_feel/post
