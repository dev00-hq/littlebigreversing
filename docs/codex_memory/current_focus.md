# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep `19/19`, `2/2`, and `11/10` guarded-positive; keep `44/2` as the guarded exterior rejection.
- Keep `LM_DEFAULT` and `LM_END_SWITCH` supported as one-byte structural markers.
- Keep `life_audit`, `room_state`, `cdb-agent`, and `ghb` on current owner boundaries.
- Keep validation additive: `zig build test-fast`, `zig build test-cli-integration`, and tool-only same-index triage.

## Active Streams

- Phase 5 runtime/gameplay widening is current, with Phase 4 Branch A already settled.
- Guarded viewer/load widening stays on `19/19`, `2/2`, and `11/10`, with differentiated `raw_invalid_start` hints and bounded `2/2` recovery.
- Runtime owns hero intent consumption, mutable object positions, and generic pending `change_cube` scheduling for guarded viewer rooms.
- Pending `change_cube` transitions now distinguish provisional zone-relative points from final landing points.
- The guarded `2/2` public exit is Frida + `cdb` backed as an exterior-facing `ChangeCube` handoff, and tests keep `2/2` pinned to one enabled cube-`0` public-door seam, so the port rejects it as `unsupported_exterior_destination_cube`.
- Guarded `19/19` object-`2` is stateful behind the runtime tick: mutable life bytes, bounded bonus events, later reward loop.
- The structural life boundary now has the machine-readable `life-catalog-v2` surface from production enums.
- Offline decoded-interior ranking is widened; same-index fragment-zone triage stays explicit.

## Blocked Items

- The guarded `19/19` object-`2` slice still stops at bounded bonus-event emission; motion, pickup, UI, and save/load parity are pending.
- The guarded `2/2` `change_cube` slice is not an interior room-handoff proof anymore; parity there now depends on future exterior-transition work.
- The bounded Sendell room-`36` slice still lacks page-level dialog timing/state ownership and save/load parity.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the widened Branch-A boundary stable as the settled foundation for Phase 5 runtime/gameplay work.
- Keep the bounded `2/2` raw-zone recovery seam separate from future exterior-transition work.
- Choose the next bounded Phase 5 seam from either a real interior-to-interior transition candidate or the existing guarded gameplay slices (`19/19` object-`2`, room `36` story state).
- Capture the classic dialog pager state behind the visible room-`36` page turns.
- Consider the canonical investigative layers to choose the next guarded runtime widening target.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- scene_decode
- platform_windows
