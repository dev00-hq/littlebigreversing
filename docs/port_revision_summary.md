# Port Revision Summary

This revision tightened the current Zig port boundaries without broadening promoted runtime behavior.

Completed changes:

- Split background loading so runtime-facing topology can be loaded through `loadBackgroundTopologyMetadata` without requiring BRK preview data.
- Extracted viewer interaction policy into `port/src/app/viewer/controller.zig`, leaving SDL orchestration in `viewer_shell.zig`.
- Moved render snapshot projection into `port/src/runtime/room_projection.zig`, keeping `room_state.zig` focused on guarded `RoomSnapshot` adaptation.
- Made original-runtime proof launch ownership explicit: proof tools now fail fast when existing `LBA2.EXE` or `cdb.exe` sessions are present unless `--takeover-existing-processes` is passed.
- Aligned the documented validation tiers around promotion packets, fast Zig tests, CLI integration, viewer verification, and the project pipeline.

The revision preserved the hard gate that runtime/gameplay widening requires a valid promotion packet under `docs/promotion_packets/`.
