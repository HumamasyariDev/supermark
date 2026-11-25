# Golden goose

`golden_goose.glb`: static Tripo mesh, 0.8 m tall, gold metal (ORM.B about 0.88, roughness about 0.29, kept on purpose).

## Round 5 (2026-10-19, ASSETS3_CHARS): use `golden_goose_v2.glb`

Pure path swap (byte-identical except the ORM image and one material field). ORM.R now carries a Cycles self-occlusion AO bake
(distance 0.11 m, strength 0.80, floor 0.35; mean 0.86) wired as the glTF occlusionTexture; before it was flat 1.0, so the
feather layers and wing joins had no contact shading. Roughness and metal are unchanged.
Evidence: `Docs/progress/topup_chars/r5_fix/*__r5fix_Cam_orm*`. Tools: `assets_src/topup/chars/tools/fix_r5/`.
