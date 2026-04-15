# Room Intelligence Plans

## Summary

This pack defines the `room intelligence` project inside `littlebigreversing`: a machine-facing scene and room inspection surface that extends the existing Zig CLI with a richer JSON payload for programs and agents.

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

- Actor count matches decoded scene object count.
- Representative actor fields are pinned in JSON tests.
- Track instruction counts and life byte lengths match existing decoder outputs.

### M4: Port Validation Integration

- Make the new command part of the port-support tooling story without changing runtime codepaths.
- Add one canonical positive JSON probe for a checked-in room pair and one name-based probe.

Proof:

- CLI integration tests pass.
- Existing scene/room/life command tests still pass.

## Validation

Use the existing PowerShell-first repo workflow:

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-fast`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-scene 2 --json`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room 2 2 --json`
- planned: `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry 2 --background-entry 2`

The planned command must be clearly labeled as planned until it exists.

## Risks And Decisions

- The biggest risk is semantic overreach. V1 must not invent actor-field meanings that the repo cannot justify.
- Existing raw inspectors are already useful; the new command should be additive rather than replacing them.
- Name lookup is convenience, not canonical identity. The output must always include resolved numeric indices.
- This initiative is port support tooling, not a detached side project. It should improve validation and debugging for the runtime effort.

