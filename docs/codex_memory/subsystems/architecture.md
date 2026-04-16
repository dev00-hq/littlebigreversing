# Architecture

## Purpose

Own repo direction and the canonical Codex memory workflow across the Zig port and original-runtime evidence lane.

## Invariants

- `port/` stays the canonical implementation path.
- Original-runtime evidence work stays explicit and tool-owned; it is supporting evidence, not the default port execution path.
- `inspect-room-intelligence`, `cdb-agent`, and local `ghb` are the canonical evidence layers for narrowing runtime gaps.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo confusion.

## Current Parity Status

- The Zig port remains decode-first, Windows-first, and fail-fast.
- `life_audit.zig` owns offline decoded-interior ranking and the canonical all-scenes life inventory.
- Viewer input stops at intent submission; runtime owns the pending intent and its minimal consumption tick.
- Runtime owns mutable object positions on the live viewer/app path, while `RoomSnapshot` stays immutable decode state.
- Guarded `19/19` now also carries an explicit immutable object-behavior seed for object `2`, while runtime owns the mutable life-byte copy and later reward-loop state.
- The life decoder now has a machine-readable `life-catalog-v2` CLI surface sourced from production enums.
- `inspect-room-intelligence` scene/background naming now comes from `port/src/generated/room_metadata.zig`, regenerated with `tools/generate_room_metadata.py`.
- `inspect-room-intelligence` is the approved repo-local gap-discovery surface.
- `cdb-agent` is the approved debugger/live-trace layer, and `ghb` is the approved Ghidra layer.
- The canonical original-runtime split is stable: Tavern uses FRA, Scene11 uses debugger snapshots, and Sendell writes `sendell_summary.json`.
- Runtime also owns a bounded Sendell room-`36` seam: viewer input submits `cast_lightning` / `advance_story`, and object behavior advances the red-ball slice.

## Known Traps

- `docs/PROMPT.md` can lag; prefer subsystem packs and typed history.
- `sidequest/` and `LM_TASKS/` are independent workstreams unless a prompt explicitly widens scope.
- Dump-driven rankings, dossiers, and temporary seed-admission probes are evidence only, not supported runtime behavior.
- `work/` artifacts can lag the real worktree; verify code, `git status`, and asset paths before trusting generated outputs.
- Prefer native Windows Git for repo-state checks; Bash-under-`/mnt/d` can over-report dirtiness.
- In PowerShell-hosted sessions, prefer single-quoted `bash -lc` payloads.
- If room-name labels need to change, regenerate `port/src/generated/room_metadata.zig`; do not revive runtime reads from LBArchitect `.hqd` files.
- Keep the tiny top-level Zig test roots under `port/src/`; direct subdirectory roots can fail with `import of file outside module path`.
- `scripts/verify_viewer.py` is the canonical Windows acceptance gate for the port path.
- Original-runtime evidence helpers are not default port pickup; use `life_scripts.md` for Tavern, Scene11, Frida, or debugger capture work.
- Sendell proof menus need held-key input; keep that quirk in `life_scripts.md` instead of generalizing it into the port path.
- On the current Sendell proof lane, use `0x00499E98` as the direct `ListVarGame` base, not Ghidra `DAT_00499E96`.

## Canonical Entry Points

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `port/README.md`

## Important Files

- `AGENTS.md`
- `ISSUES.md`
- `tools/codex_memory.py`
- `tools/life_trace/trace_life.py`

## Test / Probe Commands

- `py -3 .\tools\codex_memory.py validate`

## Open Unknowns

- Which future runtime seams deserve their own subsystem packs.
- Whether the next runtime widening slice should pay down `19/19` object-`2` bonus parity or push the scheduler farther from viewer-driven ticks first.
