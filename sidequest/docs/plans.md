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

Current status: M1, M2, M3, and M4 are implemented and validated in the side-quest branch of work.

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

## Risks And Decisions

- The biggest risk is semantic overreach. V1 must not invent actor-field meanings that the repo cannot justify.
- Existing raw inspectors are already useful; the new command should be additive rather than replacing them.
- Name lookup is convenience, not canonical identity. The output must always include resolved numeric indices.
- Viewer admission and payload extraction are different concerns. This command should expose both, not conflate them.
- This initiative is port support tooling, not a detached side project. It should improve validation and debugging for the runtime effort.
