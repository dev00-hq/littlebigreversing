# Intelligence

## Purpose

Own the canonical repo-local, machine-facing per-room and per-scene inspection contract exposed by `inspect-room-intelligence`.

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
- The payload preserves raw-vs-decoded actor counts and additive `validation` data.
- Scene/background name resolution uses checked-in generated Zig metadata, not runtime reads from LBArchitect `.hqd` files.
- Large payload consumers can redirect the same JSON contract with `--out <path>`.

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
- `cd port && zig build tool -- inspect-room-intelligence --scene-entry 219 --background-entry 219`
- `cd port && zig build tool -- inspect-room-intelligence --scene-entry 44 --background-entry 2`

## Open Unknowns

- Whether any downstream room-dump ranking or dossier consumers deserve later canonical promotion.
- Whether future runtime widening should add more machine-facing validation detail here or keep that detail owned by narrower runtime tools.
