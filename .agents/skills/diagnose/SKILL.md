---
name: diagnose
description: Diagnose bugs and parity gaps in the Little Big Adventure 2 reverse-engineering port. Use for broken Zig port behavior, viewer/runtime regressions, original-runtime proof failures, asset/decode mismatches, transition/life-script gaps, flaky live probes, or performance/build regressions in this repo.
---

# Diagnose LBA2

This skill is repo-local to `D:\repos\reverse\littlebigreversing`.

The generic debugging loop is not enough here. Most failures in this repo are not just "code is wrong"; they are mismatches between:

- decoded asset facts
- guarded Zig port behavior
- original-runtime behavior
- generated evidence, promotion packets, and memory packs

Keep those layers separate until evidence proves they collapse.

## Phase 0 - Load Current Truth

Start every diagnosis from the repo's current-state memory, not from old notes or assumptions.

1. Run or read:

   ```powershell
   py -3 .\tools\codex_memory.py context
   ```

   If that fails, read these directly:

   ```powershell
   Get-Content -Raw docs\codex_memory\project_brief.md
   Get-Content -Raw docs\codex_memory\current_focus.md
   Get-Content -Raw docs\codex_memory\subsystems\architecture.md
   ```

2. Load only relevant subsystem packs:

   - `intelligence.md` for room/scene inspection and CLI contracts
   - `life_scripts.md` for life programs, save lanes, Frida/FRA/CDB proof lanes
   - `scene_decode.md` for typed `SCENE.HQR` decode issues
   - `backgrounds.md` for `LBA_BKG.HQR`, fragments, floor/wall/background loading
   - `platform_windows.md` for Windows build, toolchain, viewer, original-runtime startup
   - `assets.md` or `mbn_corpus.md` only when the failure is about source material

3. Read `ISSUES.md` before trusting an obvious explanation. This file is the trap log.

4. Check worktree state with native Windows Git:

   ```powershell
   git status --short
   ```

   Do not use WSL/Bash Git as the source of truth on this checkout.

If `tools/codex_memory.py context` fails because an index mapping points at a missing path, do not ignore it. Continue with direct memory reads and record the trap in `ISSUES.md` if it is new.

## Phase 1 - Name the Failing Surface

Classify the bug before building a loop. Pick the smallest truthful category:

- **asset/decode**: HQR parsing, scene/background metadata, generated metadata, typed decode
- **guarded port runtime**: `port/src/runtime`, room admission, movement, transitions, life/update logic
- **viewer/presentation**: SDL viewer, HUD/sidebar, input mapping, rendering, screenshots
- **tool/CLI**: `zig build tool -- ...`, JSON contracts, Python helpers, generated files
- **original-runtime proof**: live LBA2, direct-save launch, Frida/FRA/CDB, screenshots, run bundles
- **promotion/status**: `docs/promotion_packets/`, `canonical_runtime`, `live_positive`, approved exceptions
- **build/environment**: `scripts/dev-shell.py`, MSVC/Zig, locked executable, mounted CD
- **memory/docs trap**: stale subsystem pack, broken index, old history contradicted by current code

Write down the exact seam:

- room pair, scene/background entries, zone index, object index, save profile, opcode, CLI command, or viewer action
- whether the evidence is decoded-only, port-runtime, live-positive, live-negative, or approved exception
- what would count as a pass/fail signal

Do not generalize from one room, door, save lane, watcher, zone, or object to a subsystem-wide rule.

## Phase 2 - Build the Right Loop

Choose the loop that matches the surface. A "fast test" is only valid if it exercises the real seam.

### Zig Port / Runtime

Use the configured Windows dev shell:

```powershell
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-fast
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-cli-integration
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- <command> <args>
```

Use at least 220 seconds for `test-fast`.

For viewer/runtime changes, also build or run the actual target path. Unit tests alone can miss native key mappings and executable wiring:

```powershell
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build stage-viewer
```

### Room / Scene Intelligence

Prefer canonical inspection surfaces:

```powershell
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-scene --json <args>
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room <scene> <background> --json
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-fragment-zones <scene> <background> --json
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-intelligence --scene-entry <n> --background-entry <n> --json
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-transitions <scene> <background> --json
```

Keep decoded candidates separate from supported runtime behavior.

### Promotion Packets

When a runtime/gameplay claim crosses from decode/tooling into canonical behavior, validate promotion status:

```powershell
py -3 .\tools\validate_promotion_packets.py
```

`canonical_runtime: true` requires `live_positive` or `approved_exception`.

### Original Runtime

Use original-runtime proof only after the exact port/decode seam is named.

Canonical startup facts:

- mount the mixed-mode CUE on Alcohol `E:` if you run into the insert cd screen.
- launch named saves directly with `LBA2.EXE SAVE\<name>.LBA`
- hide/restore autosave when validating named-save load
- require stable non-splash frames before claiming the save loaded
- preserve RGB for game screenshots; alpha can be bogus

Choose the lane by question:

- `inspect-room-intelligence`: asset-side facts and validation hints
- Frida/FRA: coarse live behavior, Tavern-style proof, screenshots, event rows
- `cdb-agent`: debugger-backed snapshots and exact write ownership
- `ghb`: Ghidra-backed static analysis
- watcher scripts under `tools/life_trace/`: maintained proof lanes

Do not revive staged menu-driven `Load Game`, scratch save-folder surgery, broad hot instruction hooks, or WinMM proxy as default startup unless the task explicitly asks for that old lane.

### Build / Environment

Use native PowerShell for canonical commands. If an executable install fails with `AccessDenied`, check for stale `lba2.exe` before diagnosing code.

Do not trust Bash-wrapped Zig validation on Windows. Use `scripts/dev-shell.py exec`.

## Phase 3 - Reproduce and Pin Evidence

Run the loop and capture the exact symptom:

- failing command and exit code
- JSON field mismatch
- stderr event
- screenshot path
- run bundle path
- save name and coordinates
- zone membership / `NewCube` / `NewPos`
- object index, opcode, global address, or write site

Confirm the failure matches the user's bug. A nearby failure is not enough.

For live original-runtime failures, require both machine evidence and visual evidence when visuals are part of the claim.

## Phase 4 - Rank Hypotheses by Layer

Generate 3-8 falsifiable hypotheses. Rank them by the layer most likely to own the failure:

1. stale or contradicted memory/trap note
2. wrong seam classification
3. decoded asset fact misunderstood
4. generated metadata or CLI contract stale
5. guarded runtime code is wrong
6. viewer/presentation path is miswired
7. original-runtime lane is invalid, flaky, or proving a different thing
8. environment/setup issue

Each hypothesis must predict a concrete observation.

Example:

> If this is a decoded-only candidate being promoted too far, then `inspect-room-transitions` will show the row while `docs/promotion_packets/` has no `live_positive` or `approved_exception`, and runtime tests should reject the transition.

Show the ranked list to the user when useful, then proceed if they are not available.

Use the $critical-sparring skill to do a pass on the hypotheses in order to discard the ones that are most obviosuly not the cause and rerank the rest.

## Phase 5 - Instrument Safely

Probe the narrow boundary that separates hypotheses.

Rules:

- Tag temporary debug output with `[DEBUG-<shortid>]`.
- Do not add compatibility fallbacks, migration paths, dual behavior, or silent recovery.
- Fail fast with explicit diagnostics.
- Do not rename raw fields to final/runtime terms until live evidence proves that meaning.
- Do not replace current canonical lanes with scratch scripts when maintained tools exist.

Original-runtime escalation order:

1. maintained watcher/probe script
2. Frida/FRA function or probe-form hooks
3. `cdb-agent` one-shot read/snapshot
4. CDB write watch only when exact write ownership matters
5. hot instruction hooks only with an explicit reason and a rollback plan

If a hot hook crashes, back off and combine safer probes.

## Phase 6 - Fix With a Current-State Contract

Before editing, decide what contract the fix is enforcing:

- stricter decode validation
- guarded runtime behavior
- viewer presentation/input correctness
- original-runtime proof-lane stability
- promotion/status correctness
- memory/docs accuracy

Use the repo's canonical path, not compatibility glue. Under the hard-cut policy, delete old-state behavior instead of preserving it unless the user explicitly asks for compatibility.

Regression test at the correct seam:

- `test-fast` for fast runtime/unit contracts
- `test-cli-integration` for asset-backed CLI contracts
- direct `zig build tool -- <command>` for real subcommand wiring
- `stage-viewer` / viewer verification for native viewer paths
- maintained Python unittest for proof helpers
- promotion packet validation for runtime promotion status
- live proof rerun for claims about original LBA2 behavior

If no correct test seam exists, say so explicitly and keep the claim bounded.

## Phase 7 - Cleanup and Record

Before declaring done:

- rerun the original loop
- rerun the focused regression gate
- remove all `[DEBUG-...]` instrumentation
- delete throwaway scripts or move proof artifacts under an explicit `work/` proof/run directory
- validate promotion packets when touched
- validate memory when touched:

  ```powershell
  py -3 .\tools\codex_memory.py validate
  ```

- update `ISSUES.md` for any new trap or recurring confusion point
- append typed memory history after meaningful milestones with `tools/codex_memory.py` rather than editing JSONL history in place
- update `current_focus.md` only if active repo status changed

State the root cause in terms of the proven layer, not just the code change.

Good:

> The failure was a port-runtime promotion bug: a decoded `change_cube` row was treated as canonical without a live-positive promotion packet.

Bad:

> The transition code was wrong.

## Common Repo-Specific Wrong Turns

- Treating `viewer_loadable` as gameplay parity.
- Treating decoded `change_cube` destination fields as final landing coordinates.
- Reusing old unsupported-life expectations for current guarded `2/2` or `11/10`.
- Calling `0013-weapon.LBA` a Tralu save.
- Treating `3/3` zone `1` membership as a live transition proof.
- Using stale scratch scripts under `work/` as maintained proof lanes.
- Reviving staged `Load Game` menu automation.
- Trusting a screenshot before the Adeline splash has actually handed off.
- Treating `CurrentSaveGame()` as named-save proof.
- Treating CDB watch failures with malformed commands as negative evidence.
- Letting offline ranking, dump-derived hints, or temporary seed probes become runtime policy.
- Debugging Bash/WSL Git or Zig behavior before checking native PowerShell commands.
