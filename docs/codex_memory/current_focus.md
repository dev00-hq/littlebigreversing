# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep `19/19`, `2/2`, and `11/10` guarded-positive; keep `44/2` as the guarded exterior rejection.
- Keep `LM_DEFAULT` and `LM_END_SWITCH` supported as one-byte structural markers.
- Keep `life_audit.zig` owning decoded-interior ranking and `room_state.zig` owning guarded room/load admission.
- Keep fast validation additive: `zig build test-fast` is the daily loop, and `zig build test-cli-slow` is the explicit same-index CLI triage repro shard.

## Active Streams

- Phase 4 Branch A remains the current path.
- Full-archive life audit decodes all `3109` audited blobs with `unsupported_blob_count = 0`.
- Guarded viewer/load widening is live, with differentiated `raw_invalid_start` hints.
- Offline decoded-interior ranking is widened, and same-index fragment-zone triage remains explicit.

## Blocked Items

- The next post-Branch-A runtime-facing slice is still undecided.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the widened Branch-A boundary in code, tests, and docs.
- Use the differentiated `raw_invalid_start` hints plus landed ranking to pick the next runtime-facing slice.
- Keep `zig build test-fast` as the daily loop; use `zig build test-cli-slow` only as the explicit same-index CLI triage repro shard.

## Relevant Subsystem Packs

- architecture
- backgrounds
- life_scripts
- scene_decode
- platform_windows
