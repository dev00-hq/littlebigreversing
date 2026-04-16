# Room Intelligence Plans

## Summary

This pack defines the `room intelligence` project inside `littlebigreversing`: a machine-facing scene and room inspection surface that extends the existing Zig CLI with a richer JSON payload for programs and agents.

This pack is a side quest only. It is not canonical until explicitly promoted.

Dominant docs-pack mode: `existing-codebase`.
Secondary repo reality: `legacy-port`.

This pack does not replace the repo-wide roadmap in `docs/LBA2_ZIG_PORT_PLAN.md`. It narrows one concrete tooling initiative that supports the port by turning scene data into stable programmatic intelligence.

## Current Baseline

- The repo already has typed `SCENE.HQR` decoding in `port/src/game_data/scene.zig`.
- `zig build tool -- inspect-scene <entry> --json` already emits scene header, hero start, raw objects, zones, tracks, patches, and decoded track instructions.
- `zig build tool -- inspect-room <scene> <background> --json` already emits scene plus background linkage and composition context.
- Life decoding and catalog work already exist through `inspect-life-program`, `inspect-life-catalog`, and `life_audit.zig`.
- Friendly room names exist in the preserved LBA metadata files and can be used as lookup input for a higher-level command.

## Scope

In scope for v1:

- Add a new CLI command: `inspect-room-intelligence`
- Keep output JSON-only in v1
- Accept scene and background selection by entry index and by friendly name
- Emit one stable payload with:
  - resolved selection metadata
  - scene header and hero start context
  - background linkage and room context
  - actor intelligence with raw and mapped fields
  - zones, tracks, and patches
  - life and track program summaries per actor
- Reuse existing decoders and audits rather than duplicating parsing logic

Out of scope for v1:

- Full Builder sidebar parity
- Full semantic decompilation of life scripts
- Scene editing or mutation
- Runtime behavior changes
- Heuristic same-index scene/background pairing

## Milestones

Current status: M1, M2, M3, M4, the downstream room triage consumer, the downstream actor triage consumer, and the actor dossier/runtime probe lane are implemented and validated in the side-quest branch of work.

### M1: Selection And Naming

- Add the command and selector parsing.
- Support:
  - `--scene-entry`
  - `--scene-name`
  - `--background-entry`
  - `--background-name`
- Resolve names from LBA metadata with deterministic case-insensitive matching.
- Fail explicitly on ambiguous or unknown names.

Proof:

- Parser tests pass for valid and invalid selector combinations.
- Name resolution tests cover exact, suffix, ambiguous, and missing matches.

### M2: Room Intelligence Payload

- Introduce a composed room-intelligence payload that layers over the existing scene and room decode surfaces.
- Include resolved names, canonical entry indices, classic loader scene number, scene header, hero start, background context, zones, tracks, and patches.
- Include explicit `decoded_actor_count` so raw header object counts are not confused with decoded actor rows.
- Include a structured `validation` block so machine consumers can see viewer/runtime admission without losing the payload.

Proof:

- JSON payload tests pin top-level keys and resolved selection metadata.
- Existing `inspect-scene` and `inspect-room` outputs remain unchanged.

### M3: Actor Intelligence

- Promote current raw scene object fields into a stable `actors` array with:
  - `raw`
  - `mapped`
  - `track`
  - `life`
- Preserve raw numeric truth and add grouped mapped semantics only where justified by current evidence.
- Surface raw flag words and bit-level breakdowns without guessing unknown names.

Proof:

- Actor count matches the decoded `SceneMetadata.objects` slice used to build the payload.
- Representative actor fields are pinned in JSON tests.
- Track instruction counts and life byte lengths match existing decoder outputs.

### M4: Port Validation Integration

- Make the new command part of the port-support tooling story without changing runtime codepaths.
- Add real subprocess-backed CLI coverage for the command entrypoint and stdout path.
- Keep numeric selectors raw-index-first, but fail early with selector-specific diagnostics when an entry is out of range.

Proof:

- CLI integration tests hit the actual command entrypoint.
- Positive and validation-failure probes both emit stable JSON.
- Out-of-range numeric selectors fail with command-scoped errors.
- Existing scene/room/life command tests still pass.

### M5: Downstream Triage Consumer

- Add one sidequest-only consumer that reads `inspect-room-intelligence` dumps from disk rather than calling back into the runtime.
- Make it answer one question only: which dumped rooms are the strongest guarded-runtime follow-up targets?
- Prefer explicit evidence over hidden scoring magic:
  - viewer-loadable interior status
  - fragment-zone compatibility and layout presence
  - hero decode status and instruction count
  - decoded actor coverage and maximum actor instruction count
- Keep this consumer out of the canonical `port/` CLI until the side quest is promoted.

Proof:

- The consumer can rank `2/2`, `11/10`, `19/19`, and `44/2` from dump files alone.
- A non-viewer-loadable room is demoted to `decode-only` even if its scripts are rich.
- A viewer-loadable interior with richer runtime structure outranks a simpler one.

### M6: Actor Follow-Up Consumer

- Add one sidequest-only consumer that reads a single `inspect-room-intelligence` dump and ranks actors inside that room.
- Make it answer one question only: which actors are the strongest guarded-runtime follow-up targets?
- Keep the rule explicit and narrow:
  - decoded life status first
  - life instruction count second
  - track instruction count third
  - movement and combat only as tie-breakers
- Do not call back into the runtime from this consumer; it must justify the existing actor payload on its own.

Proof:

- The consumer can rank the top actors in `11/10` from a dump file alone.
- A non-decoded actor is demoted even if its numeric fields look rich.
- A behavior-rich actor outranks a mobility-only actor with weaker life logic.

### M7: Actor Dossier And Runtime Falsification

- Add one sidequest-only dossier reader that renders a focused report for selected actors from an existing dump.
- Use it to compare the top-ranked actor against at least one nearby actor and one low-ranked control.
- Add one sidequest-only runtime probe that tries a real runtime tick for a selected room/object and reports whether the current runtime boundary admits or rejects it.
- Do not hide runtime rejection: if the room is outside supported object-behavior coverage, report the exact failure.

Proof:

- The dossier for `11/10` actor `2` explains why it outranks actor `12` and a low-ranked control using existing dump fields only.
- The runtime probe on `11/10` actor `2` reports the actual current boundary result rather than inferring support from static richness.

### M8: Temporary Seed Admission Probe

- Add one sidequest-only probe that temporarily injects a selected actor as a runtime behavior seed for one tick.
- Report the real first blocker from the current runtime path.
- Also report the first interpreter-compatibility blocker behind that gate:
  - first unsupported life opcode or condition function
  - first unsupported track opcode

Proof:

- The probe for `11/10` actor `2` distinguishes the live dispatch failure from the next static interpreter failure.
- The output is enough to decide whether the next runtime step is dispatch widening or opcode support widening.

## Validation

Use the existing PowerShell-first repo workflow:

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-fast`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-cli-integration`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-scene 2 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room 2 2 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-program --scene-entry 2 --object-index 5 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry 2 --background-entry 2`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-name "Scene 0: Citadel Island, Twinsen's house" --background-name "Grid 0: Citadel Island, Twinsen's house"`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry 44 --background-entry 2`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry 219 --background-entry 219`
- `py -3 -m unittest sidequest\\tools\\test_room_intelligence_triage.py`
- Generate dump files with `--out` and run `py -3 sidequest\\tools\\room_intelligence_triage.py <dump-path>...`
- `py -3 -m unittest sidequest\\tools\\test_room_actor_triage.py`
- Generate a dump file with `--out` and run `py -3 sidequest\\tools\\room_actor_triage.py <dump-path> --top 5`
- `py -3 -m unittest sidequest\\tools\\test_room_actor_dossier.py`
- Generate a dump file with `--out` and run `py -3 sidequest\\tools\\room_actor_dossier.py <dump-path> 2 12 1`
- `py -3 .\\scripts\\dev-shell.py exec --cwd port -- zig run src\\sidequest_room_actor_runtime_probe.zig -- 11 10 2`
- `py -3 .\\scripts\\dev-shell.py exec --cwd port -- zig run src\\sidequest_room_actor_seed_admission_probe.zig -- 11 10 2`

## Risks And Decisions

- The biggest risk is semantic overreach. V1 must not invent actor-field meanings that the repo cannot justify.
- Existing raw inspectors are already useful; the new command should be additive rather than replacing them.
- Name lookup is convenience, not canonical identity. The output must always include resolved numeric indices.
- Viewer admission and payload extraction are different concerns. This command should expose both, not conflate them.
- This initiative is port support tooling, not a detached side project. It should improve validation and debugging for the runtime effort.
