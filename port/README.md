# Port Workspace

This directory is the home of the canonical modern LBA2 port implementation.

Current direction:

- Zig 0.16.0 plus SDL2
- Windows-first runtime target
- one canonical codepath per subsystem
- fail-fast diagnostics when evidence is incomplete

Current landed baseline:

- real Zig workspace bootstrap
- data-backed SDL2 interior viewer shell for explicit scene/background pairs
- canonical asset-root discovery and config
- HQR base reader and inspection CLI
- machine-readable asset inventory and golden-fixture pipeline
- generated scene/background name metadata for `inspect-room-intelligence`, checked into `port/src/generated/room_metadata.zig` and regenerated with `tools/generate_room_metadata.py`
- generated reference metadata overlays for HQR and game-state aliases, checked into `port/src/generated/reference_metadata.zig` and verified with `zig build verify-reference-metadata`
- `inspect-room-intelligence` as the canonical repo-local machine-facing per-room/per-scene inspection surface for structured scene/background/actor payloads and validation hints
- `BRK`-backed viewer evidence surfaces for the supported guarded `19/19`, `2/2`, and `11/10` room/load set
- explicit background topology loading through `loadBackgroundTopologyMetadata`, with BRK/palette preview loading kept on the visual metadata path
- viewer interaction control split into `app/viewer/controller.zig`, with SDL lifecycle orchestration left in `viewer_shell.zig`
- render snapshot projection split into `runtime/room_projection.zig`, with `runtime/room_state.zig` kept as the guarded `RoomSnapshot` adaptation boundary
- Windows viewer verification through `scripts/verify_viewer.py`, with bare mode kept as the canonical milestone acceptance gate, `--fast` kept as the broader end-to-end pre-closeout pass, and `zig build test-fast` plus targeted tool probes used for slice-grade iteration
- guarded success for `19/19`, `2/2`, and `11/10`, plus expected guarded `ViewerSceneMustBeInterior` rejection for `44/2`
- offline life decoding now structurally supports `LM_DEFAULT` and `LM_END_SWITCH` as one-byte markers, and the all-scenes audit currently reports zero unsupported life blobs
- explicit runtime session seeding from world-position input
- runtime/gameplay seam widening gated by `docs/promotion_packets/` and `zig build test-promotion-packets`; decoded seams can remain candidates, but canonical runtime behavior requires a `live_positive` or `approved_exception` packet
- original-runtime launch tooling refuses to kill existing `LBA2.EXE`/`cdb.exe` proof sessions by default; pass `--takeover-existing-processes` only when the run should explicitly own and clear those processes

Roadmap phases, gates, and acceptance checks live in `docs/LBA2_ZIG_PORT_PLAN.md`. Active repo state and current blockers live in `docs/codex_memory/current_focus.md`. The canonical room-intelligence contract lives in `docs/codex_memory/subsystems/intelligence.md`. Canonical memory pickup excludes `sidequest/` and `LM_TASKS/` unless those streams are explicitly promoted.

Keep `port/` separate from:

- `reference/` for imported upstream and reference material
- `work/` for generated artifacts, extracted payloads, and rebuildable state
- `docs/` for reports, plans, and reverse-engineering notes

Reference metadata maintenance:

- `zig build verify-reference-metadata` checks the checked-in reference metadata against the local `..\..\lba-reference-repos\metadata` clone
- `zig build regen-reference-metadata` refreshes `port/src/generated/reference_metadata.zig` from that clone
- `zig build test-reference-metadata-generator` runs the generator unit tests without depending on the external clone

Canonical project pipeline:

- `py -3 scripts/project_pipeline.py --zig-root work/toolchains/zig-x86_64-windows-0.16.0` runs the Zig 0.16.0 build, `zig build test-fast`, Kimun metrics, and Lizard complexity export.
- Add `--bootstrap-tools` to clone/build pinned Kimun and install pinned Lizard before running.
- Quality artifacts are written to `work/quality/project-pipeline/`.
