# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep `19/19`, `2/2`, and `11/10` guarded-positive; keep `44/2` as the guarded exterior rejection.
- Keep `LM_DEFAULT` and `LM_END_SWITCH` supported as one-byte structural markers.
- Keep `life_audit.zig` owning decoded-interior ranking and `room_state.zig` owning guarded room/load admission.
- Keep validation additive: `zig build test-fast` daily, `zig build test-cli-integration` for bounded room/load coverage, and same-index triage tool-only.

## Active Streams

- Phase 4 Branch A remains the current path.
- Guarded viewer/load widening is live, with differentiated `raw_invalid_start` hints.
- Guarded locomotion seeding now reaches `19/19`, `2/2`, and `11/10`, with fragment navigation split from hero locomotion.
- Runtime now owns hero intent consumption and mutable object-position copies for guarded viewer rooms.
- The guarded `19/19` object-`2` slice is stateful behind the runtime tick: mutable life bytes, bounded bonus events, and the checked-in later reward loop all live in runtime.
- The structural life decoder boundary now has a machine-readable `life-catalog-v1` surface via `zig build tool -- inspect-life-catalog --json`, sourced from the production `life_program.zig` enums rather than markdown-only notes.
- Sendell's Ball room (`36`) now has a typed `sendell_summary.json` lane with direct `MagicLevel`, `MagicPoint`, and `ListVarGame[FLAG_BOULE_SENDELL]` reads.
- Runtime now owns a bounded Sendell room-`36` story-state slice driven by viewer `F` / `Enter` intents.
- Offline decoded-interior ranking is widened, and same-index fragment-zone triage remains explicit.

## Blocked Items

- The later guarded `19/19` object-`2` reward branch is runtime-backed now, but the slice currently stops at bounded bonus-event emission; classic extra motion, pickup, UI, and save/load parity are still pending.
- The bounded Sendell room-`36` slice still stops at direct story-state transitions; dialog/UI timing, `CurrentDial`, and save/load parity are pending.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the widened Branch-A boundary in code, tests, and docs.
- Keep Sendell's Ball separate from the guarded `19/19` sewer reward loop; the direct Sendell lightning/dialog flow is not generic extra-spawn evidence.
- Keep the Sendell state contract anchored to `MagicLevel`, `MagicPoint`, and `ListVarGame[FLAG_BOULE_SENDELL]`, not screenshots.
- Decide whether the next Sendell widening step is `CurrentDial` / UI parity or a broader runtime scheduler slice.
- Move the scheduler boundary farther away from viewer input once a second behavior-bearing runtime slice exists.

## Relevant Subsystem Packs

- architecture
- backgrounds
- life_scripts
- scene_decode
- platform_windows
