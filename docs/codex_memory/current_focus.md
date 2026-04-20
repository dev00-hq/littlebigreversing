# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep the guarded room/load set stable: `19/19`, `2/2`, `11/10`, with `44/2` the guarded exterior rejection.
- Keep `LM_DEFAULT`, `LM_END_SWITCH`, `life_audit`, `room_state`, `cdb-agent`, and `ghb` on current owner boundaries.
- Keep validation additive: `zig build test-fast`, `zig build test-cli-integration`, and tool-only same-index triage.
- Keep original-runtime debug control on the committed `debug_compass` + `heading_inject` + `waypoint_step_probe` path, with burst outcome canonical.

## Active Streams

- Phase 5 runtime/gameplay widening is current, with Phase 4 Branch A already settled.
- Guarded viewer/load widening stays on `19/19`, `2/2`, and `11/10`, with differentiated `raw_invalid_start` hints.
- Original-runtime debug control now uses `debug_compass.py`, `heading_inject.py`, and `waypoint_step_probe.py`.
- Original-runtime launch now uses direct save launch (`LBA2.EXE <save>.LBA`) plus `Enter`.
- Pending `change_cube` transitions distinguish provisional zone-relative points from final landing points.
- The guarded `2/2` public exit is Frida + `cdb` backed as an exterior-facing `ChangeCube` handoff, and tests keep `2/2` pinned to one enabled cube-`0` public-door seam, so the port rejects it as `unsupported_exterior_destination_cube`.
- Guarded `19/19` object-`2` is stateful behind the runtime tick, and the sewer chest seam is now a bounded multi-bonus path with live-backed `Divers=5` semantics plus full-magic denial/rebound.

## Blocked Items

- Guarded `19/19` still has one open fidelity gap: pickup gating is admitted footing plus same-`top_y` and proximity, not a proved same-surface/floor-band rule.
- The guarded `2/2` `change_cube` slice is not an interior room-handoff proof anymore; parity there now depends on future exterior-transition work.
- On room `36/36`, visible page 2 is renderer pagination inside one decoded text record, not a new payload. The port keeps dialog id `3` across both visible pages; save/load parity is still open.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.

## Next Actions

- Use `waypoint_step_probe.py` as the step primitive for debug-control work.
- Reopen wall mapping only if a bounded navigation slice proves that room-scale persistent wall knowledge is the bottleneck.
- Choose the next bounded Phase 5 seam from either a real interior-to-interior transition candidate or the existing guarded gameplay slices.
- Treat guarded `19/19` reward-model work as settled unless a pickup-surface bug or contradiction appears.
- Keep room-`36` work on the live decoded-text lane until the port owns a real decoder / paginator.
- Use `dialog_text_dump.py` as the canonical live proof tool for `CurrentDial` / `PtText` / `PtDial` before making further room-36 claims.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
