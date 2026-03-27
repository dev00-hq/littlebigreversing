# Port Workspace

This directory is the home of the canonical modern LBA2 port implementation.

Current direction:

- Zig 0.15.2 plus SDL2
- Windows-first runtime target
- one canonical codepath per subsystem
- fail-fast diagnostics when evidence is incomplete

Current first package boundary:

- real Zig workspace bootstrap
- data-backed SDL2 interior viewer shell for explicit scene/background pairs
- canonical asset-root discovery and config
- HQR base reader and inspection CLI
- machine-readable asset inventory and golden-fixture pipeline
- initial validation harness

Implementation planning lives in `docs/LBA2_ZIG_PORT_PLAN.md`.

Keep `port/` separate from:

- `reference/` for imported upstream and reference material
- `work/` for generated artifacts, extracted payloads, and rebuildable state
- `docs/` for reports, plans, and reverse-engineering notes
