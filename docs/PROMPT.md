# Next Step: Targeted Switch-Family Life Evidence Pass

## Summary

The repo now has a broader offline audit path at `zig build tool -- audit-life-programs [--json]` on top of `port/src/game_data/scene/life_program.zig`. That command still defaults to the canonical scene set, but it can now also audit explicit scene-entry lists or the full `SCENE.HQR` archive through explicit flags.

The widened audit slice is complete and it materially narrowed the remaining blocker set:

- the canonical default report is unchanged: scenes `2`, `5`, and `44` still hit unsupported `LM_DEFAULT` and `LM_END_SWITCH`
- the explicit `--all-scene-entries` report audited all `221` non-header `SCENE.HQR` entries (`2..222`) and `3109` life blobs
- that full-archive run found `394` unsupported blobs across `145` scenes
- only two unsupported opcodes appeared anywhere in current real assets: `LM_DEFAULT` (`188` hits) and `LM_END_SWITCH` (`206` hits)
- the other six named-but-unimplemented `LM_*` ids still lack checked-in runtime evidence, but they did not appear in the current full-archive audit

The switch-family source pass is also still in force: checked-in source does not prove structural handling for `LM_DEFAULT` or `LM_END_SWITCH` beyond the `COMMON.H` names and the `LM_BREAK` comment `saute au END_SWITCH`.

The next bounded step is therefore no longer a broad inventory task. It is a tightly scoped evidence pass for `LM_DEFAULT` and `LM_END_SWITCH` only, aimed at deciding whether stronger non-header evidence exists for their structural layout or whether they should stay deliberately outside the supported decoder boundary.

This slice should:
- keep `life_program.zig`, `life_audit.zig`, `audit-life-programs`, the scene parser/model, and `inspect-scene` unchanged
- focus only on `LM_DEFAULT` and `LM_END_SWITCH`
- preserve raw `life_bytes` as the canonical scene surface
- treat the full-archive audit result as the current real-asset truth: no other unsupported named `LM_*` ids are active blockers until stronger evidence says otherwise
- keep the current fail-fast behavior for unsupported ids instead of adding skip logic or speculative marker layouts

## Key Changes

- Audit stronger evidence sources specifically for switch-family structure.
  - Re-check the classic source, disassembly notes, or other stronger checked-in/runtime-adjacent evidence only for `LM_DEFAULT` and `LM_END_SWITCH`.
  - Do not spend time on the other six named unsupported ids unless the current asset-backed audit changes.
  - If no stronger evidence exists, document that clearly instead of inferring operand widths or zero-byte markers from names alone.

- Keep the product boundary honest.
  - Do not widen `inspect-scene`, `SceneProgramBlob`, or parser-owned scene state.
  - Do not change `audit-life-programs` output shape or selection behavior as part of this slice.
  - Do not add compatibility skipping for unsupported ids just to continue decoding later bytes.
  - Keep `LM_DEFAULT` and `LM_END_SWITCH` explicitly unsupported unless the same diff adds concrete structural evidence.

- Refresh durable docs after the evidence pass lands.
  - Update `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md` with the switch-family conclusion.
  - Update `docs/PROMPT.md` again only after that conclusion changes the next boundary.
  - Update `docs/codex_memory/handoff.md`, append a task event, and append a decision record if the supported/unsupported boundary changes or is reaffirmed.
  - Run `python3 tools/codex_memory.py validate` after the memory/doc updates.

## Test Plan

- Keep `zig build test` as the primary gate.
- Keep `zig build tool -- audit-life-programs --json --all-scene-entries` as the executable evidence report that proves the narrowed blocker set.
- Add coverage only if the new evidence changes the supported decoder boundary; otherwise keep the current fail-fast tests and broader audit regressions intact.
- Acceptance commands:
  - `zig build test`
  - `zig build tool -- audit-life-programs --json --all-scene-entries`
  - `zig build tool -- inspect-scene 2 --json`

## Assumptions

- The full-archive audit already answered the broad inventory question: only `LM_DEFAULT` and `LM_END_SWITCH` are current real-asset blockers.
- Checked-in classic source still outranks header names and previous summaries if they drift, and the latest source pass did not prove `LM_DEFAULT` or `LM_END_SWITCH`.
- Raw `life_bytes` remain the canonical source of truth until unsupported real-asset life cases are either structurally proven or deliberately kept outside the product boundary.
- The local acceptance gate is still environment-dependent: `zig build test`, `audit-life-programs`, and `inspect-scene` depend on the canonical extracted asset tree and the repo-local SDL2 layout on this machine.
