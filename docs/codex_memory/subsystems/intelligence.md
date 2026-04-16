# Intelligence

## Purpose

Own the canonical repo-local, machine-facing per-room and per-scene inspection contract exposed by `inspect-room-intelligence`.

This pack defines the structured JSON surface used for combined scene, background, actor, and validation payloads on the checked-in port path. It does not replace the broader canonical investigative stack, and it does not own supported runtime behavior.

## Invariants

- `inspect-room-intelligence` is the canonical repo-local, machine-facing per-room/per-scene inspection surface for structured payloads and validation hints.
- `inspect-scene --json` remains the canonical scene inspection surface for typed `SCENE.HQR` decode.
- `inspect-room` and `inspect-room-fragment-zones` remain the canonical guarded room/load and blocker-diagnostics surfaces.
- `cdb-agent` and `ghb` remain canonical investigative layers alongside this CLI surface.
- Offline ranking and compatibility selection stay separate from this pack; do not collapse ranking tools into the room-intelligence contract.
- Supported runtime behavior stays owned by guarded runtime codepaths, not by `inspect-room-intelligence`.

## Current Parity Status

- `inspect-room-intelligence` is implemented, asset-backed, and covered by the canonical `test-cli-integration` shard.
- The command is JSON-only.
- The command supports explicit scene/background selection by entry index or friendly name.
- Parse, selection, load, validation, augmentation, and serialization failures all emit structured machine-facing JSON.
- The payload preserves raw-vs-decoded actor counts explicitly.
- The payload includes additive `validation` data instead of suppressing output for non-viewer-loadable pairs.
- Scene/background name resolution uses checked-in generated Zig metadata, not runtime reads from LBArchitect `.hqd` files.
- Large payload consumers can redirect the same JSON contract with `--out <path>`.

## Contract Boundaries

- Selection:
  - support `--scene-entry` / `--scene-name`
  - support `--background-entry` / `--background-name`
  - keep numeric selectors raw-index-first
  - include resolved numeric indices in output even when names are used as input
- Payload:
  - include resolved selection metadata
  - include scene header, hero start context, background context, actors, zones, tracks, and patches
  - include life and track structure without claiming full runtime semantic parity
  - include a `validation` block for viewer/runtime admission hints
- Failure behavior:
  - keep output machine-facing and JSON-only
  - preserve selector-specific parse/load failures rather than collapsing them into generic tool errors
  - distinguish extractability from guarded runtime admission

## Known Traps

- Do not describe `inspect-room-intelligence` as the sole canonical room/scene intelligence surface for the repo; that would blur ownership already held by `inspect-scene`, `inspect-room`, `inspect-room-fragment-zones`, ranking tools, `cdb-agent`, and `ghb`.
- Raw header object counts and decoded actor rows are intentionally distinct; use the explicit count fields instead of assuming they must match.
- `validation.viewer_loadable` is an admission hint, not proof of complete runtime parity.
- Name metadata is checked-in generated Zig data. Regenerate the artifacts instead of reviving runtime metadata reads.
- Downstream dossier, triage, and temporary seed-admission probes are not part of this canonical contract unless they are explicitly promoted later.

## Canonical Entry Points

- `port/src/tools/cli.zig`
- `port/src/tools/room_intelligence.zig`
- `port/src/tools/cli_room_load_integration_test.zig`
- `port/src/generated/room_metadata.zig`

## Important Files

- `port/src/generated/reference_metadata.zig`
- `tools/generate_room_metadata.py`
- `tools/generate_reference_metadata.py`
- `port/src/runtime/room_state.zig`

## Test / Probe Commands

- `cd port && zig build test-cli-integration`
- `cd port && zig build tool -- inspect-room-intelligence --scene-entry 2 --background-entry 2`
- `cd port && zig build tool -- inspect-room-intelligence --scene-entry 44 --background-entry 2`
- `cd port && zig build tool -- inspect-room-intelligence --scene-entry 219 --background-entry 219`
- `cd port && zig build tool -- inspect-room-intelligence --scene-name "Scene 0: Citadel Island, Twinsen's house" --background-name "Grid 0: Citadel Island, Twinsen's house"`

## Open Unknowns

- Whether any downstream room-dump ranking or dossier consumers deserve later canonical promotion.
- Whether future runtime widening should add more machine-facing validation detail to this surface or keep that detail owned by narrower runtime-specific tools.
