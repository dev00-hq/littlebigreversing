# Phase 5 Magic Ball Throw Projectile Launch

## Packet Identity

- `id`: `phase5_magic_ball_throw_projectile_launch`
- `status`: `live_positive`
- `evidence_class`: `collision_locomotion`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: scene `2`, background `0`, active cube `1` cellar
- source: `throw-ball.LBA` with `ListVarGame[FLAG_BALLE_MAGIQUE]=1`, Twinsen at `(5071,1024,1820,beta=3709)`
- trigger: select the Magic Ball, hold the weapon key (`.` in the runtime profile) long enough for the throw animation to arm, then release
- destination: a Magic Ball projectile row appears in `ListExtra` with sprite `8`, flags `33038`, origin `(5071,2224,1820)`, and behavior-mode-dependent velocity

## Decode Evidence

Classic `OBJECT.CPP` keeps `I_THROW` active while the Magic Ball throw is armed and changes `MagicBallFlags` from `MAGIC_BALL_LANCEE` to `MAGIC_BALL_LACHEE` only when input is released. Classic `CONFIG/INPUT.CPP` maps default `I_THROW` to `K_ALT`; the tested runtime profile maps weapon use to `.`. F5/F6/F7/F8 select Normal, Sporty, Aggressive, and Discreet behavior modes.

## Original Runtime Live Evidence

`tools/life_trace/phase5_magic_ball_drive_probe.py` hid `SAVE\autosave.lba`, direct-launched `SAVE\throw-ball.LBA`, selected the requested behavior mode with F5/F6/F7/F8, selected the Magic Ball with `1`, and held `.` for candidate durations until a `ListExtra` projectile row appeared.

The refined threshold runs found first launch at `0.63s` for Normal, `0.63s` for Sporty, `0.62s` for Aggressive, and `0.63s` for Discreet. The promoted automation rule is therefore a conservative `0.75s` hold before release.

The first observed projectile rows were:

- Normal: position `(5016,2241,1901)`, origin `(5071,2224,1820)`, velocity `(-55,18,81)`
- Sporty: position `(5013,2237,1906)`, origin `(5071,2224,1820)`, velocity `(-58,13,86)`
- Aggressive: position `(5071,2224,1820)`, origin `(5071,2224,1820)`, velocity `(-62,7,91)`
- Discreet: position `(5035,2299,1873)`, origin `(5071,2224,1820)`, velocity `(-36,77,53)`

## Runtime Invariant

When the basic Magic Ball flag is set, a scene-2 cellar throw creates one active Magic Ball projectile snapshot with sprite `8`, flags `33038`, zero timeout/divers fields, origin `hero + (0,1200,0)`, and the behavior-mode-specific initial row/velocity above. This packet promotes only projectile launch from the proof pose; it does not promote projectile integration, collision, bounce, return, damage, switch activation, or remote item pickup.

## Positive Test

- `tools/test_validate_promotion_packets.py` pins the checked-in throw fixture.
- `port/src/runtime/object_behavior_test.zig` asserts the four live-backed launch rows and velocities.
- `port/src/runtime/update_test.zig` asserts a queued throw intent is consumed through the runtime tick and creates the projectile snapshot.

## Negative Test

The packet fixture pins that sub-threshold holds did not launch: Normal `0.62s`, Sporty `0.62s`, Aggressive `0.61s`, and Discreet `0.62s`. The port-side negative boundary rejects a throw when `FLAG_BALLE_MAGIQUE` is unset.

## Reproduction Command

Run each mode sequentially; this probe owns `LBA2.EXE` and kills any existing instance before each attempt.

```powershell
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --mode normal --key period --durations 0.61,0.62,0.63,0.64,0.65 --out-dir work\live_proofs\phase5_magic_ball_drive_probe_refine2
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --mode sporty --key period --durations 0.61,0.62,0.63,0.64,0.65 --out-dir work\live_proofs\phase5_magic_ball_drive_probe_sporty_threshold
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --mode aggressive --key period --durations 0.61,0.62,0.63,0.64,0.65 --out-dir work\live_proofs\phase5_magic_ball_drive_probe_aggressive_threshold
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --mode discreet --key period --durations 0.61,0.62,0.63,0.64,0.65 --out-dir work\live_proofs\phase5_magic_ball_drive_probe_discreet_threshold
```

## Failure Mode

If no `ListExtra` projectile row appears, do not promote throw behavior. If the probe is run in parallel, attempts race because each process kills and owns `LBA2.EXE`; rerun sequentially. If autosave is not hidden, direct launch can land in autosave/menu state instead of `throw-ball.LBA`.

## Docs And Memory

- `docs/codex_memory/lessons.md`
- `tools/life_trace/phase5_magic_ball_drive_probe.py`
- `tools/life_trace/phase5_magic_ball_throw_probe.py`
- `tools/fixtures/promotion_packets/phase5_magic_ball_throw_projectile_launch_live_positive.json`

## Old Hypothesis Handling

This proof replaces the earlier operator-only throw observation as the canonical launch evidence. It still leaves Magic Ball collision, bounce/ricochet, return, damage eligibility, switches, and remote key pickup as separate proof targets.

## Revision History

- 2026-04-29: Initial live-positive packet from direct-launched `throw-ball.LBA` threshold runs across all four behavior modes.
