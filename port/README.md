# Port Workspace

This directory is the home of the canonical modern LBA2 port implementation.

Current direction:

- Zig 0.15.2 plus SDL2
- Windows-first runtime target
- one canonical codepath per subsystem
- fail-fast diagnostics when evidence is incomplete

Current landed baseline:

- real Zig workspace bootstrap
- data-backed SDL2 interior viewer shell for explicit scene/background pairs
- canonical asset-root discovery and config
- HQR base reader and inspection CLI
- machine-readable asset inventory and golden-fixture pipeline
- `BRK`-backed viewer evidence surfaces for the supported guarded `19/19` baseline plus the explicit test-only unchecked `11/10` fragment evidence path
- native PowerShell viewer verification through `scripts/verify-viewer.ps1`, with bare mode kept as the canonical gate and `-Fast` available for the daily local loop
- guarded success for `19/19` and expected guarded `ViewerUnsupportedSceneLife` rejection for `2/2`, `44/2`, and `11/10`
- explicit runtime session seeding from world-position input, with `runtime/room_state.zig` remaining the `RoomSnapshot` adaptation boundary

Roadmap phases, gates, and acceptance checks live in `docs/LBA2_ZIG_PORT_PLAN.md`. Active repo state and current blockers live in `docs/codex_memory/current_focus.md`. Canonical memory pickup excludes `sidequest/` and `LM_TASKS/` unless those streams are explicitly promoted.

Keep `port/` separate from:

- `reference/` for imported upstream and reference material
- `work/` for generated artifacts, extracted payloads, and rebuildable state
- `docs/` for reports, plans, and reverse-engineering notes
