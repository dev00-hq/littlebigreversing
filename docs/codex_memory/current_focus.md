# Current Focus

## Current Priorities

- Use this Codex memory system as the default handoff and state-externalization path for future repo work.
- Preserve the repo's existing split between canonical checked-in knowledge and rebuildable generated state.
- Keep reverse-engineering findings, task decisions, and next steps cheap for a new Codex session to reload.
- Align implementation planning around the Zig 0.15.2 + SDL2 port direction, keep the offline life decoder plus audit path canonical, treat the verified full-archive `LM_DEFAULT`/`LM_END_SWITCH` hits as the only current unsupported real-asset life blockers unless stronger checked-in evidence appears, and use the new `inspect-background` / `game_data/background.zig` path as the canonical interior metadata surface for the first viewer dependency.

## Active Streams

- MBN corpus analysis and evidence workbench maintenance
- Zig-first LBA2 port implementation and typed-decoding preparation
- Interior `LBA_BKG.HQR` decoding and room-background linkage for the first viewer dependency
- Codex memory hygiene for long-horizon repo work

## Blocked Items

- Phase 2 typed asset decoding now has both an unwired offline `life_program.zig` decoder and a separate `audit-life-programs` path, but scene-surface life integration is still blocked: the full-archive audit now finds unsupported `LM_DEFAULT` and `LM_END_SWITCH` across `145` of `221` non-header scene entries (`394` of `3109` life blobs), the switch-family source pass found no structural evidence beyond header names plus the `LM_BREAK` destination comment, and the other six named unsupported ids still lack live runtime cases even though they do not appear in the current asset tree.
- `zig build test` is still a real-asset gate that depends on the canonical extracted asset tree and the repo-local SDL2 layout.

## Next Actions

- Run `python3 tools/codex_memory.py validate` before and after substantive memory updates.
- Keep `handoff.md` aligned with the latest meaningful repo state.
- Record durable architecture or workflow conclusions in `decision_log.jsonl` instead of leaving them only in chat context.
- Keep raw HQR entry indices and classic loader scene numbers explicit when working with `SCENE.HQR` targets.
- Use `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`, `port/src/game_data/scene/life_program.zig`, and `port/src/game_data/scene/life_audit.zig` as the boundary documents/code when touching life decoding.
- Use `zig build tool -- audit-life-programs` as the executable report for canonical real-asset blockers before proposing parser or CLI integration.
- Use the broadened audit results to keep any future life-evidence work tightly scoped to `LM_DEFAULT` and `LM_END_SWITCH`; the other named unsupported ids are not current real-asset blockers.
- Do not repeat the completed switch-family source pass unless new checked-in evidence appears or the canonical asset corpus changes.
- Use `docs/phase0/golden_targets.md`, `reference/lba2-classic/SOURCES/GRILLE.CPP`, `reference/lba2-classic/SOURCES/DISKFUNC.CPP`, `reference/lba2-classic/SOURCES/INTEXT.CPP`, and `reference/lba2-classic/SOURCES/DEFINES.H` as the boundary when touching the first interior background decoder slice.
- Treat `LBA_BKG.HQR[0]` plus the late `TabAllCube` entry at `BkgHeader.Brk_Start + BkgHeader.Max_Brk` as canonical loader context; do not treat raw `LBA_BKG.HQR[2]` bytes in isolation as the whole interior background story.
- Use `port/src/game_data/background.zig`, `port/src/game_data/background/parser.zig`, `port/src/tools/cli.zig`, and `zig build tool -- inspect-background 2 --json` as the boundary when touching interior background metadata.
- Keep the split between the older one-based HQR helpers and the new classic-index helpers explicit; classic loader slot `0` is only reachable through `extractClassicEntryToBytes` / `decodeClassicEntryToBytes`.
- If viewer work continues, keep the next slice interior-only and build on the typed `GRI`/`BLL` metadata instead of folding background data into `inspect-scene`.
- Keep the next background slice interior-only and separate from exterior `.ILE/.OBL`, renderer work, and hero/object visual binding.
- Keep raw `life_bytes` canonical and do not add `life_instructions` to scene parsing or CLI until unsupported real-asset cases are either proven or deliberately rejected by the product boundary.
