# Room Intelligence Documentation

## What This Project Is

This docs pack covers the `room intelligence` extension for `littlebigreversing`. The goal is to make room and actor information available as stable machine-readable JSON so other programs, agents, and validation tools can reason about scene content directly.

This is a focused tooling project inside the larger Zig port effort. The repo-wide roadmap still lives in `docs/LBA2_ZIG_PORT_PLAN.md`, and the narrow next-slice prompt still lives in `docs/PROMPT.md`.

## Current Status

- Implemented today:
  - typed scene decoding
  - room inspection
  - zone semantics
  - track decoding
  - life decoding and auditing
- Planned by this pack:
  - `inspect-room-intelligence`
  - friendly room selection by name
  - richer actor intelligence JSON

## Important Commands

Current commands:

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-fast`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-scene 2 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room 2 2 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-program --scene-entry 2 --object-index 5 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-catalog --json`

Planned command contract:

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry 2 --background-entry 2`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-name "Scene 0: Citadel Island, Twinsen's house" --background-name "Grid 0: Citadel Island, Twinsen's house"`

## Repo Structure

- `port/`
  Active Zig implementation, CLI, runtime, and tests.
- `docs/`
  Roadmaps, evidence, prompts, and this docs pack.
- `reference/`
  Preserved source trees and historic tooling.
- `work/`
  Generated artifacts, probes, and evidence outputs.

For this project, read in this order:

1. `docs/plans.md`
2. `docs/architecture.md`
3. `docs/implement.md`
4. `docs/LBA2_ZIG_PORT_PLAN.md`

## Troubleshooting

- If a planned command is mentioned here but does not exist yet, treat it as design contract, not implementation fact.
- If a scene name matches multiple metadata entries, the future command should fail with an ambiguity diagnostic instead of guessing.
- If a room pair is invalid or unsupported, the command should preserve current diagnostics-first behavior rather than silently remapping indices.
- If actor semantics are unclear, prefer raw fields plus bit breakdowns over speculative friendly labels.

