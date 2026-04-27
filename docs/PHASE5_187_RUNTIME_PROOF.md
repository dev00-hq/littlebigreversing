# Phase 5 187/187 Runtime Proof

This proof covers the guarded `187/187` Dark Monk statue zone `1` same-cube seam. The original runtime was launched through the canonical direct-save path: `LBA2.EXE SAVE\inside dark monk1.LBA`, with autosave hidden during launch and Frida used only for observation, coordinate injection, MCI support, and screenshots.

The canonical fixture is `tools/fixtures/phase5_187_runtime_proof.json`, distilled from `work/live_proofs/phase5_187187_transition_probe_run4_no_scene_start_sync`. Run4 is the important control because it teleported Twinsen into the source zone without syncing `SceneStart` or the saved start candidate globals.

## Result

- The save loads cube `185`, raw scene entry `187`, with Twinsen initially at `(28647,2304,21741)`.
- The source probe `(1536,256,4608)` is inside scene `187/background 187` zone `1`.
- The decoded zone destination is `(13824,5120,14848)`.
- The classic source-relative destination from the probe would be `(14336,5376,15360)`.
- The live runtime instead lands at `(28416,2304,21760)` in cube `185` with `new_cube=-1`.
- The saved context remains `SceneStart=(28648,2572,23036)` and `StartCube=(55,11,44)`.

## Port Contract

Do not admit the decoded `NewPos` as the live landing for this seam. The current port rejection for the decoded landing remains correct until the saved cube-start/context landing path is modeled explicitly and bounded by tests.
