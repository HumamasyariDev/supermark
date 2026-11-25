# Mr. Mak beanie v4 (TOPUP_HUB round 4, ASSETS3_HUB, night 01)

New files (nothing existing was overwritten; `mak_v2.glb`, `mak_beanie_v2.glb` and the unreleased v3 pair stay as backups):

| File | What |
| --- | --- |
| `mak_beanie_v4.glb` | Clean rebuilt rib-knit watch cap with knitted ear openings. 19,576 triangles, one material `beanie_knit_v4` (256 px tileable knit colour + normal, roughness 0.9, metallic 0). **Use this one.** |
| `mak_v4.glb` | `mak.glb` (default outfit, shared source untouched) with the `mak_beanie` mesh swapped for v4. Same rig, node names (`mak_rig`, `mak_body`, `mak_beanie` on bone `head_top`, `mak_backpack` on `backpack`) and weights as `mak_v2.glb`. **Point the player (`mak_player.gd` `rigged_mesh_path`), the title diorama, the UI speakers, the showcase and the juice lab at `mak_v4.glb`.** |

Attachment: unchanged. Origin at the centre of the cuff's lower rim (the v2 rim point), socket `head_top`, offset (0, -0.1326, -0.0097),
rotation (0, 0, 0); the `mak_beanie` entry in `attach.json` applies as is. Code that hides `mak_beanie` for the top hat keeps working.
Size on the head 0.56 (W) x 0.35 (H) x 0.52 (D) m, the same silhouette as v2 (shape sampled from the v2 cap).

## What changed (critic r2 major: cuff slivers, ears through the cuff, desaturated albedo)

- Surface: no Tripo knit any more. The cap is rebuilt from the v2 silhouette as clean quad topology: crown pole fan, 36 real rib
  columns fading toward the crown, a rolled fold at the cuff top, a turned-up cuff, a rolled hem lip and an inner lining (no open
  edge visible from below). At least 27 mm clearance to the skull everywhere. No atlas seams, so no dark seam slivers can appear.
- Ears: one smooth elliptic opening per ear, cut exactly on an elliptic cylinder fitted around the places where the ears cross the
  knit in the rest pose and the animator's moderate poses (forward 30, back 20, spread 20 degrees) plus 10 mm clearance, finished
  with a rolled knit hem along the curve (open at the bottom, so it reads as a knitted ear cut-out). The ears no longer pass through
  the knit (`ear_points_within_3mm_of_knit` in the report: 1-11 points of about 4,000 per pose, all on the hem edge).
- Colour: knit tile mean #8C94A0, a neutral slate grey matched to ART_V2 #8E949B (slightly cooler so it stays grey under the hub's
  amber key). **`mak_rig_fix.gd` `tint_beanie()` was written for the v2 colour map (#7C7C8A); do not apply it to mak_v4** (it would
  push the knit to a pale #A2A6A5).
- Not in this file: the brow pull from the ear weights. `ear_l`/`ear_r` weights in the shared `mak.glb` still reach a few brow and
  eyelid vertices; a per-shell fix belongs to the meshes track (request in the round 4 report). mak_v4 inherits mak.glb's weights.

Tools: `assets_src/topup/hub/tools/beanie_r5.py` (beanie), `build_mak_v4.py` (swap), renders with `beanie_r4_render.py`.
Work files and renders: `assets_src/topup/hub/mak_beanie/r5/`. Native captures (v2 vs v4, rest, ears back 30, forward 55, up 35,
landing squash, back, top, gameplay 6 m): `Docs/progress/topup_hub/*__r4fix_Mak_*`.
