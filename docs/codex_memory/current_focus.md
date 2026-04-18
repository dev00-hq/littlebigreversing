# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep the guarded-positive room/load set stable: `19/19`, `2/2`, `11/10`, with `44/2` the guarded exterior rejection.
- Keep `LM_DEFAULT`, `LM_END_SWITCH`, `life_audit`, `room_state`, `cdb-agent`, and `ghb` on current owner boundaries.
- Keep validation additive: `zig build test-fast`, `zig build test-cli-integration`, and tool-only same-index triage.
- Keep original-runtime debug control on the committed `debug_compass` + `heading_inject` + `waypoint_step_probe` path, with burst outcome canonical and `collision_observer` diagnostic-only.

## Active Streams

- Phase 5 runtime/gameplay widening is current, with Phase 4 Branch A already settled.
- Guarded viewer/load widening stays on `19/19`, `2/2`, and `11/10`, with differentiated `raw_invalid_start` hints and bounded `2/2` recovery.
- Runtime owns hero intent consumption, mutable object positions, and generic pending `change_cube` scheduling for guarded viewer rooms.
- Original-runtime debug control now has reusable probe helpers: `debug_compass.py`, `heading_inject.py`, `waypoint_step_probe.py`, with `collision_observer.py` narrowed to `persistent_collision_pin` vs `transient_pin_then_escape`.
- Pending `change_cube` transitions now distinguish provisional zone-relative points from final landing points.
- The guarded `2/2` public exit is Frida + `cdb` backed as an exterior-facing `ChangeCube` handoff, and tests keep `2/2` pinned to one enabled cube-`0` public-door seam, so the port rejects it as `unsupported_exterior_destination_cube`.
- Guarded `19/19` object-`2` is stateful behind the runtime tick: mutable life bytes, bounded bonus events, later reward loop, and viewer/main reward diagnostics.

## Blocked Items

- The guarded `19/19` object-`2` slice now reaches bounded reward diagnostics; motion, pickup, and save/load parity are still pending.
- The guarded `2/2` `change_cube` slice is not an interior room-handoff proof anymore; parity there now depends on future exterior-transition work.
- The bounded Sendell room-`36` slice still lacks page-level dialog timing/state ownership and save/load parity.
- The wall-mapping spike did not earn promotion to `main`; room-scale wall overlays are deferred.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the widened Branch-A boundary stable as the settled foundation for Phase 5 runtime/gameplay work.
- Use `waypoint_step_probe.py` as the canonical original-runtime step primitive for future autoplay/debug-control work.
- Reopen wall mapping only if a bounded navigation slice proves that room-scale persistent wall knowledge is the bottleneck.
- Choose the next bounded Phase 5 seam from either a real interior-to-interior transition candidate or the existing guarded gameplay slices.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
