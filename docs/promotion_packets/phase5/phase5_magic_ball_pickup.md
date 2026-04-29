# Phase 5 Magic Ball Pickup

## Packet Identity

- `id`: `phase5_magic_ball_pickup`
- `status`: `live_positive`
- `evidence_class`: `inventory_state`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: scene `2`, background `0`, active cube `1` cellar
- source: early cellar state reached from the house key/cellar access lane, with `ListVarGame[FLAG_BALLE_MAGIQUE]=0`
- destination: same room/cube after pickup, with `ListVarGame[FLAG_BALLE_MAGIQUE]=1`
- trigger: walk Twinsen to the cellar magic ball pickup and acknowledge the pickup dialog

## Decode Evidence

Classic `COMMON.H` defines `FLAG_BALLE_MAGIQUE` as game variable index `1`. The Phase 0 target `quest-state-house-key-cellar-access` leaves magic ball pickup unresolved, and `docs/lba2_walkthrough.md` names the early key/cellar/golden-ball route.

## Original Runtime Live Evidence

`work/live_proofs/phase5_magic_ball_manual_20260429/summary.json` records an attach-only manual run in the cellar. Initial state had active cube `1`, hero pose `(9726,1024,1101,beta=3019)`, `magic_ball_flag=0`, `magic_level=0`, and `magic_point=0`. At `t=25.105s`, after the operator picked up the magic ball and acknowledged the dialog, `magic_ball_flag` changed `0 -> 1` while active cube remained `1`.

`work/live_proofs/phase5_magic_ball_launch_20260429_r2/summary.json` records the repeatable launch run. The probe hid autosave, launched `LBA2.EXE SAVE\new-game-cellar.LBA`, started in the same cellar state with `magic_ball_flag=0`, then observed `magic_ball_flag 0 -> 1` at `t=17.219s`. Its initial, transition, and final screenshots are focused on the LBA2 window.

## Runtime Invariant

Picking up the early cellar magic ball sets `ListVarGame[FLAG_BALLE_MAGIQUE]` from `0` to `1`. The promoted port contract is `magic_ball_pickup`: scene `2/background 0` default action near object `3` sets game var `1` exactly once and does not imply dialog text, magic refill, inventory-menu rendering, or throwing behavior.

## Positive Test

- `tools/test_validate_promotion_packets.py` pins the checked-in fixture.
- `port/src/runtime/object_behavior_test.zig` asserts the live-backed cellar pickup pose mutates game var `1` without changing magic level/point or opening dialog.

## Negative Test

The negative boundary remains the same: this packet promotes only `magic_ball_pickup`. It does not promote New Game equivalence, the Sendell portrait clue, dialog text ownership, magic refill, inventory-menu behavior, or throwing/usability.

## Reproduction Command

Attach to a running cellar-state game:

```powershell
py -3 tools\life_trace\phase5_magic_ball_probe.py --attach-pid <pid> --duration-sec 45 --out-dir work\live_proofs\phase5_magic_ball_manual_YYYYMMDD
```

Launch from the repeatable save when no `LBA2.EXE` is running:

```powershell
py -3 tools\life_trace\phase5_magic_ball_probe.py --launch-save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\new-game-cellar.LBA --duration-sec 45 --out-dir work\live_proofs\phase5_magic_ball_launch_YYYYMMDD
```

## Failure Mode

If no `magic_ball_flag 0 -> 1` transition appears, do not promote inventory behavior. If using `--launch-save` while another `LBA2.EXE` is running, the probe fails fast and asks for `--attach-pid` or a closed game. Direct-launch proof must preserve the canonical autosave guard; if autosave is not hidden, the game can land at the menu or autosave instead of the requested named save.

## Docs And Memory

- `docs/PHASE5_MAGIC_BALL_RUNTIME_PROOF.md`
- `tools/fixtures/promotion_packets/phase5_magic_ball_pickup_live_positive.json`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/life_scripts.md`

## Old Hypothesis Handling

This proof closes the Phase 0 magic-ball pickup gap only for the durable inventory flag. It does not resolve New Game equivalence, the Sendell portrait clue, or dialog text ownership.

## Revision History

- 2026-04-29: Initial live-positive packet from the manual cellar pickup proof.
- 2026-04-29: Added repeatable launch proof from `SAVE\new-game-cellar.LBA` with autosave hidden.
- 2026-04-29: Promoted the narrow `magic_ball_pickup` port runtime contract.
