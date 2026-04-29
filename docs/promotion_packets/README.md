# Promotion Packets

## Purpose

Promotion packets are the canonical evidence gate for widening runtime/gameplay seams in the Zig port. A decoded or inferred seam may appear in inspection tools as a candidate, but it must not affect canonical runtime behavior until a checked-in packet promotes it.

## Gate

A packet is required before any change makes decoded or inferred seam data affect canonical runtime behavior outside a deliberately named decode/evidence surface.

Packet-required changes include:

- admitting a new guarded room/load pair into runtime, viewer, or gameplay support
- making a transition, zone, cube, `NewPos`, inventory mutation, dialog trigger, life behavior, or collision behavior executable in `port/`
- changing tests from decoded-payload assertions to runtime-behavior assertions
- renaming a blocked or negative seam into a supported seam

Packet-not-required work includes:

- CLI decode display
- evidence scripts under `tools/life_trace/`
- docs explicitly marked `decode_only`, `live_negative`, or hypothesis
- negative tests that prevent promotion

## Statuses

Use only these statuses:

- `decode_only`: decoded structure exists, with no live runtime claim.
- `live_negative`: original-runtime probing ran and did not produce the required runtime signal.
- `live_positive`: original-runtime probing produced the required runtime signal.
- `approved_exception`: the user explicitly approved promotion without live-positive proof.

`canonical_runtime: true` in `manifest.json` is allowed only for `live_positive` or `approved_exception`.

## Evidence Classes

Initial evidence classes:

- `room_load`
- `zone_transition`
- `inventory_state`
- `life_branch`
- `collision_locomotion`
- `dialog_text`
- `render_only`

The class list is intentionally extensible. As decoding and porting reveal better distinctions, classes may be split, merged, renamed, or added. The invariant is that each promoted seam declares what kind of claim it makes and what runtime proof is sufficient for that claim.

`render_only` proof must not be reused as gameplay proof. For example, visual admission does not promote a `zone_transition`.

## Gameplay Validity Boundary

Promotion packets prove seams, not a room graph. A decoded room pair, zone, cube
destination, or forced teleport is only a candidate until the original runtime
shows the corresponding player-facing affordance in the relevant quest/world
state. For gameplay promotion, name the state context as tightly as the room
edge: inventory, quest flags, actor state, current cube, collision/locomotion
path, and any dialogue or script condition that gates the behavior.

Decoded transition data can guide probes, but it must not become the project
ordering model. Phase 5 follows normal player routes first, then uses decode
and live instrumentation to prove the exact runtime seam needed for that route.

## Decode-Only Boundary

`decode_only` seams can produce candidate records, never commit records.

Allowed before promotion:

- CLI decode display
- decode fixtures
- candidate ranking
- negative runtime tests
- original-runtime probes
- docs explicitly marked `decode_only` or `live_negative`

Forbidden before promotion:

- mutating canonical runtime state from the seam
- adding the seam to guarded runtime support as gameplay behavior
- relying on it as a fallback or provisional route
- naming tests or functions as commits, supports, or promotes unless packet-backed
- treating viewer or render success as gameplay proof

## Manifest

`manifest.json` is the machine-readable index. `py -3 tools/validate_promotion_packets.py` validates it, packet paths, status rules, evidence classes, and required packet headings.

Packets that promote runtime behavior must list the emitted runtime contract ids in `runtime_contracts`. The validator scans `port/src/tools/cli.zig` for `canonical_runtime_contract` string literals and requires every emitted contract id to be covered by a `canonical_runtime: true` packet with `live_positive` or `approved_exception` status.

The validator is intentionally low-brittleness beyond runtime contract coverage. When the port has explicit seam registries, add tests that require every runtime-supported seam id to exist in this manifest with `canonical_runtime: true` and a promotable status.

## Current 3/3 Rule

`3/3` zones `1` and `8` currently remain `zone_transition`, `live_negative`, and `canonical_runtime: false`. They cannot widen gameplay behavior until a new packet records a runtime-owned transition signal from a valid player path and state context, or the user explicitly approves an `approved_exception`.
