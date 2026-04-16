# Room Intelligence Documentation

## What This Project Is

This docs pack covers the `room intelligence` extension for `littlebigreversing`. The goal is to make room and actor information available as stable machine-readable JSON so other programs, agents, and validation tools can reason about scene content directly.

This is a focused tooling project inside the larger Zig port effort. The repo-wide roadmap still lives in `docs/LBA2_ZIG_PORT_PLAN.md`, and the narrow next-slice prompt still lives in `docs/PROMPT.md`.

This pack is a side quest only. It is not canonical until explicitly promoted.

## Current Status

- Implemented today:
  - typed scene decoding
  - room inspection
  - zone semantics
  - track decoding
  - life decoding and auditing
  - `inspect-room-intelligence`
  - friendly room selection by name
  - richer actor intelligence JSON
  - explicit raw-vs-decoded actor counts
  - runtime-backed composition and fragment-zone layout for viewer-loadable rooms
  - optional `--out <path>` file output for large payload consumers
  - structured validation output for non-interior and fragment-invalid rooms
  - subprocess-backed CLI integration coverage
  - sidequest-only downstream triage consumer for ranking dumped rooms by runtime follow-up value
  - sidequest-only actor triage consumer for ranking follow-up targets inside one dumped room
  - sidequest-only actor dossier reader and runtime probe for falsifying actor follow-up claims
  - sidequest-only temporary seed admission probe that separates dispatch gating from opcode compatibility

## Important Commands

Current commands:

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-fast`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-cli-integration`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-scene 2 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room 2 2 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-program --scene-entry 2 --object-index 5 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-catalog --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry 2 --background-entry 2`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry 11 --background-entry 10 --out work\\room-intelligence-11-10.json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-name "Scene 0: Citadel Island, Twinsen's house" --background-name "Grid 0: Citadel Island, Twinsen's house"`
- `py -3 sidequest\\tools\\room_intelligence_triage.py work\\sidequest\\room-intelligence\\2-2.json work\\sidequest\\room-intelligence\\11-10.json work\\sidequest\\room-intelligence\\19-19.json work\\sidequest\\room-intelligence\\44-2.json`
- `py -3 -m unittest sidequest\\tools\\test_room_intelligence_triage.py`
- `py -3 sidequest\\tools\\room_actor_triage.py work\\sidequest\\room-intelligence\\11-10.json --top 5`
- `py -3 -m unittest sidequest\\tools\\test_room_actor_triage.py`
- `py -3 sidequest\\tools\\room_actor_dossier.py work\\sidequest\\room-intelligence\\11-10.json 2 12 1`
- `py -3 -m unittest sidequest\\tools\\test_room_actor_dossier.py`
- `py -3 .\\scripts\\dev-shell.py exec --cwd port -- zig run src\\sidequest_room_actor_runtime_probe.zig -- 11 10 2`
- `py -3 .\\scripts\\dev-shell.py exec --cwd port -- zig run src\\sidequest_room_actor_seed_admission_probe.zig -- 11 10 2`

`inspect-room-intelligence` still writes full JSON to stdout by default. Use `--out <path>` when a consumer wants the same payload through a file instead of stdout buffering. This side quest does not add summary mode, pagination, or selective-section switches yet.

`sidequest\\tools\\room_intelligence_triage.py` is the first downstream consumer. It reads existing dump files only and answers one question: which rooms are the strongest guarded-runtime follow-up targets?

`sidequest\\tools\\room_actor_triage.py` is the second downstream consumer. It reads one existing dump file only and answers one question: which actors inside that room are the strongest guarded-runtime follow-up targets?

`sidequest\\tools\\room_actor_dossier.py` and [sidequest_room_actor_runtime_probe.zig](/D:/repos/reverse/littlebigreversing/port/src/sidequest_room_actor_runtime_probe.zig:1) are the falsification lane. The dossier explains why a target actor looks promising from dump data alone; the runtime probe then tests whether the current runtime boundary actually admits that room/object slice. The probe lives under `port/src/` only because Zig's module-path rules block a standalone top-level sidequest Zig file from importing the runtime modules directly.

[sidequest_room_actor_seed_admission_probe.zig](/D:/repos/reverse/littlebigreversing/port/src/sidequest_room_actor_seed_admission_probe.zig:1) goes one step farther: it temporarily injects a chosen actor as a runtime behavior seed for one tick, then reports both the live runtime blocker and the next interpreter-compatibility blocker behind that gate.

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

1. `sidequest/docs/plans.md`
2. `sidequest/docs/architecture.md`
3. `sidequest/docs/implement.md`
4. `docs/LBA2_ZIG_PORT_PLAN.md`

## Troubleshooting

- If a planned command is mentioned here but does not exist yet, treat it as design contract, not implementation fact.
- If a scene name matches multiple metadata entries, the command should fail with an ambiguity diagnostic instead of guessing.
- If a room pair is decodable but not viewer-loadable, `inspect-room-intelligence` should still emit JSON and explain that in `validation`.
- If a room pair is viewer-loadable, `inspect-room-intelligence` may emit a much larger payload because runtime composition tiles, height grids, and fragment-zone layout are included.
- If a consumer cannot safely buffer that payload from stdout, use `--out <path>` instead of introducing a second JSON shape.
- If a numeric selector is out of range, fail early with a selector-specific error instead of waiting for deeper asset loaders to fail.
- If actor semantics are unclear, prefer raw fields plus bit breakdowns over speculative friendly labels.
