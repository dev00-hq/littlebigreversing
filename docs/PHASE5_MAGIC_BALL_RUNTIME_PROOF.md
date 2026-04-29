# Phase 5 Magic Ball Runtime Proof

This note summarizes the original-runtime proof for the early cellar magic-ball pickup. The raw proof bundles are `work/live_proofs/phase5_magic_ball_manual_20260429` and `work/live_proofs/phase5_magic_ball_launch_20260429_r2`.

## Save And Startup

The live run attached to an already-open `LBA2.EXE` that the operator had placed in the cellar from the `new-game-cellar.LBA` save lane. The initial watched state was active cube `1`, Twinsen at `(9726,1024,1101,beta=3019)`, `MagicLevel=0`, `MagicPoint=0`, `ListVarGame[FLAG_BALLE_MAGIQUE]=0`, and magic-ball inventory model id `0`.

## Gameplay Contract

The operator manually walked Twinsen to the cellar magic ball and pressed `Enter` when the pickup dialog appeared. The watcher observed `ListVarGame[FLAG_BALLE_MAGIQUE] 0 -> 1` at `t=25.105s` while Twinsen remained in active cube `1` at `(5378,1024,1786,beta=2306)`.

`MagicLevel`, `MagicPoint`, and the watched inventory model id stayed `0` during this capture. The durable signal for this seam is therefore the game variable `FLAG_BALLE_MAGIQUE`, not a magic refill or model-id change.

## Repeatable Launch Proof

`work/live_proofs/phase5_magic_ball_launch_20260429_r2/summary.json` proves the feedback loop from a closed game. The probe hid `SAVE\autosave.lba`, launched `LBA2.EXE SAVE\new-game-cellar.LBA`, and restored autosave after the observed run.

That launch started in active cube `1` with Twinsen at `(9726,1024,1101,beta=3019)` and `ListVarGame[FLAG_BALLE_MAGIQUE]=0`. After the operator picked up the magic ball and acknowledged the dialog, the watcher observed `ListVarGame[FLAG_BALLE_MAGIQUE] 0 -> 1` at `t=17.219s`; final state remained active cube `1` with Twinsen at `(5293,1024,1786,beta=2446)`.

The repeatable run screenshots `01_initial.png`, `02_magic_ball_flag_change.png`, and `03_final.png` are all focused on the LBA2 window.

## Porting Implications

This proof promotes only the inventory/state mutation for owning the basic magic ball. It does not prove true New Game equivalence, the Sendell portrait clue, the dialog text payload, or generic inventory-menu behavior.

The repeatable watcher is `tools/life_trace/phase5_magic_ball_probe.py`. With the game already open, use `--attach-pid`; with no existing `LBA2.EXE`, use `--launch-save` against `new-game-cellar.LBA`. The launch path uses the canonical named-save rule: run `LBA2.EXE SAVE\<name>.LBA` with autosave hidden during the proof.
