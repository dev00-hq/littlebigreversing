# Next Prompt

Relevant subsystem packs for this task: `architecture`, `life_scripts`, `scene_decode`, and `platform_windows`.

Current state:

- `19/19` is still the only supported positive branch-B runtime/load baseline.
- The guarded negative scene-life startup path is now settled behavior: `2/2`, `44/2`, and `11/10` fail fast with `ViewerUnsupportedSceneLife`, and both `inspect-room` and viewer startup print the same first-hit `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` line before the error.
- The guarded positive startup path now also prints a runtime-owned `event=neighbor_pattern_summary ...` line backed by `runtime/world_query.zig.summarizeObservedNeighborPatterns()`, and both `viewer_shell` unit coverage and `scripts/verify-viewer.ps1` pin the current baseline counts: `origin_cell_count=1246`, `occupied_surface_count=4828`, `empty_count=107`, `out_of_bounds_count=49`, `missing_top_surface_count=0`, `standable_neighbor_count=4828`, `blocked_neighbor_count=0`, `top_y_delta_buckets=0:4828`.
- `life_audit.zig.listDecodedInteriorSceneCandidates()` already proves there are `50` fully-decoded interior scenes under the current archive, with `SCENE.HQR[19]` as the earliest candidate by entry index.
- The current supported `19/19` startup is still diagnostic-only rather than gameplay-ready: the guarded viewer launch lands on `raw_invalid_start`, and the current scene metadata reports `track_count=0`.
- `inspect-scene --json` is the canonical scene-metadata surface for object, zone, and track counts; `audit-life-programs --json --all-scene-entries` is the canonical branch-B candidate inventory surface.

Next slice:

- Stop deepening `19/19` stderr-only diagnostics for now and make the Phase 5 blocker concrete instead: identify whether any fully-decoded interior branch-B scene is a better gameplay candidate than `19`.
- Build one canonical checked-in ranking/report surface from existing `life_audit` candidate data plus scene metadata. The result must answer whether `19` is still the best current branch-B candidate only because it is earliest, or whether another decoded interior scene is richer on scene-surface signals such as `object_count`, `zone_count`, and `track_count`.
- Keep this slice offline and discovery-only: do not widen the runtime/load boundary, do not admit a new positive runtime scene yet, and do not change viewer/runtime contracts.
- Treat a negative answer as useful output. If no decoded interior candidate is clearly richer or safer than `19`, make that explicit and use it to sharpen the next Phase 5 plan instead of inventing progress.

Hard-cut ownership:

- `life_audit.zig`: canonical decoded-candidate discovery and branch-B candidate inventory owner
- `scene.zig` plus scene parser/model/tests: canonical owner for object/zone/track metadata used to compare candidates
- `tools/cli.zig`: acceptable place for a stable JSON or human-readable ranking/report surface if one is needed
- `runtime/*`, `viewer_shell.zig`, `render.zig`, `main.zig`, and `room_state.zig`: unchanged for this slice unless a tiny plumbing edit is strictly required by tests

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases while you investigate richer decoded interior candidates offline.
- Prefer ranking inputs that already exist in checked-in code and tests: decoded blob count, `object_count`, `zone_count`, `track_count`, classic loader scene number, and scene kind.
- No runtime widening, no new supported positive startup pair, no life execution, no scene transitions, no inventory/state systems, no combat, no track execution, no movement-policy changes, and no new unchecked public-runtime path.
- Do not treat docs-only reasoning as enough. The ranking/report must come from checked-in code, tests, or a canonical CLI surface.

Useful work in scope:

- Reuse `listDecodedInteriorSceneCandidates()` and scene metadata to build a stable ranking/report of fully-decoded interior candidates.
- Pin the existing candidate-count facts (`50` decoded interior candidates, earliest entry `19`) while adding at least one stable comparison that shows whether any candidate beats `19` on scene-surface richness such as non-zero `track_count`.
- Surface the result in one canonical place: a CLI report, a tested helper, or a checked-in evidence test that future sessions can rerun without manual interpretation.
- If one candidate emerges as the best next Phase 5 target, surface its stable identifying fields. If none does, make that negative result explicit.

Acceptance:

- One canonical checked-in surface answers the question: what is the best current branch-B gameplay candidate among fully-decoded interior scenes?
- The answer is derived from existing life-audit and scene-metadata owners, not from ad hoc docs-only ranking.
- The repo makes it explicit whether `19` remains the best current candidate or whether another decoded interior scene is richer for the next Phase 5 slice.
- The guarded runtime/viewer boundary and its current startup/load diagnostics remain unchanged.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `zig build tool -- audit-life-programs --json --all-scene-entries`
  - `zig build tool -- inspect-scene 19 --json`
  - `# plus the new candidate-ranking surface if this slice adds one`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `.\scripts\verify-viewer.ps1`
