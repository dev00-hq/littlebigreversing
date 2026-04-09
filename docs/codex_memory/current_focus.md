# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Treat `19/19` as the only supported positive runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negatives, with `11/10` evidence/test-only.
- Keep switch-family life outside the supported boundary and fail-fast at the runtime/load seam.
- Keep `life_audit.zig` owning offline decoded-interior ranking and `tools/cli.zig` owning `rank-decoded-interior-candidates` plus `triage-same-index-decoded-interior-candidates`.
- Keep `runtime/room_state.zig` owning the guarded room/load seam plus unsupported-life and `invalid_fragment_zone_bounds` diagnostics.
- Keep fast Windows validation additive: `zig build test-fast` plus `scripts/verify_viewer.py --fast`.

## Active Streams

- Guarded `19/19` and negative-load diagnostics stay explicit.
- Phase 5 branch-B triage: `219` is first and `19` is `49/50` under `rank-decoded-interior-candidates`, while `triage-same-index-decoded-interior-candidates` reports `86/86` as the highest-ranked compatible same-index pair above baseline.
- Fragment-bearing triage is now explicit: `86/86` stays the zero-fragment/zero-GRM pass, while `187/187` is the first fragment-bearing compatible pair at `rank=16` with `fragment_count=2`, `grm_zone_count=2`, and `compatible_zone_count=2`.
- Top-candidate blocker: `inspect-room 219 219 --json` now emits six fragment-zone issues; the first is zone `1` `z=4208..5744`.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and missing checked-in life execution support.
- The only supported positive startup remains `19/19`, and it still lands on `raw_invalid_start` with `track_count=0`.
- The top-ranked offline candidate is not yet a valid guarded room/load pair: `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`, with six `misaligned_min` issues.
- Same-index compatibility above baseline is no longer a binary blocker, but the highest-ranked compatible result is still a zero-fragment/zero-GRM pass, so the next non-trivial fragment-bearing follow-up remains a deliberate choice rather than an automatic promotion.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Use the landed triage summaries for the next Phase 5 choice: preserve `86/86` as the highest-ranked compatible pair overall, but treat `187/187` as the first fragment-bearing compatible pair if the goal is new fragment-zone evidence.
- Use `zig build test-fast` plus `scripts/verify_viewer.py --fast` during iteration; keep bare `zig build test` plus `scripts/verify_viewer.py` for before-close validation.
- Keep future life work on unsupported-life diagnostics or new checked-in proof only.

## Relevant Subsystem Packs

- architecture
- backgrounds
- life_scripts
- scene_decode
- platform_windows
