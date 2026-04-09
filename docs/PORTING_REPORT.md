# LBA2 Modern Port Report

## Scope

This report is oriented toward a graduation-project goal: producing a modern port of **Twinsen's Little Big Adventure 2** using the materials already present in this workspace and the tooling available under `D:\repos\reverse`.

## Status Note

This report remains the canonical high-level feasibility and evidence survey.

The canonical implementation roadmap, runtime target, and first work-package boundary now live in `docs/LBA2_ZIG_PORT_PLAN.md`. Treat any older C++ or CMake-specific implementation guidance below as historical assessment context, not as the current execution plan.

It is based on:

- the extracted GOG installer payload,
- the nested original game CD image,
- the `mbn_tools` archive already unpacked in this repo,
- the historic `lba2-classic` source tree already present in the workspace,
- and the local reverse-engineering stack under `D:\repos\reverse`.

## Executive Summary

The shortest credible path to a full port is **not** a pure black-box reverse-engineering effort.

The workspace already gives you three major advantages:

1. **Original game data** extracted from the installer and the original CD image.
2. **Historic engine source code** in `lba2-classic`, including a large amount of C++, ASM, build scripts, and engine structure.
3. **Legacy community tooling** in `littlebigreversing/mbn_tools` that can inspect and manipulate many LBA2 asset/container formats.

Given that, the most practical strategy is:

- treat the historic source tree as the primary specification for engine behavior and subsystem boundaries,
- treat the extracted DOS/CD assets as the canonical data set,
- use the MBN tools to decode, inspect, and validate content formats,
- use Ghidra and the other RE tools only for the remaining opaque parts: missing libraries, binary-only behavior, and verification against shipping executables.

If you try to port the game by starting from the DOS executable alone, you will spend time rediscovering structure that is already present in source form.

## What Was Extracted

### Installer structure

The file `setup_twinsens_little_big_adventure_2_classic_3.2.4.3_(61767).exe` is a **GOG Inno Setup** installer.

I extracted it into:

- `D:\repos\reverse\littlebigreversing\work\_innoextract_full`

This contains:

- the GOG launcher/wrapper resources,
- the "classic" Windows-facing files such as `TLBA2C.exe`,
- the `Speedrun\Windows` subtree,
- and a large embedded file `Speedrun\Windows\LBA2.GOG`.

### Nested original game image

`LBA2.GOG` is not an arbitrary blob. It is a **raw CD image** with **2352-byte sectors**. Converting each sector to its 2048-byte payload produced:

- `D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2.iso`

That ISO was then extracted into:

- `D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom`

This gives you the original disc layout, including:

- `LBA2\LBA2.EXE`
- `LBA2\SCENE.HQR`
- `LBA2\RESS.HQR`
- `LBA2\VIDEO\VIDEO.HQR`
- `LBA2\VOX\*.VOX`
- `LBA2\MUSIC\*.WAV`
- `LBA2\DIRECTX\...`
- installer/support files from the original release

### Why this matters

For a port project, `LBA2_cdrom` is more important than the GOG wrapper. It is the closest thing here to the original shipping game content and runtime environment.

The GOG top-level files are still useful, but mostly for:

- launcher behavior,
- packaging,
- already-converted convenience assets,
- and comparison against the original disc layout.

## Important Workspace Assets

## 1. Historic source tree: `lba2-classic`

Path:

- `D:\repos\reverse\littlebigreversing\reference\lba2-classic`

This is the most important asset for a port.

The README states it is the historic engine source release, preserved largely as-developed. The tree includes:

- `SOURCES\*.CPP`
- `SOURCES\*.ASM`
- `SOURCES\MAKEFILE`
- `LIB386\...`

Observed facts:

- The build system targets DOS with **Watcom C/C++** and **MASM**.
- The makefile references `dos4g`, `wpp386`, `wlink`, and external libraries.
- The codebase already exposes engine-level modules such as:
  - configuration,
  - object logic,
  - rendering/grid handling,
  - life/tracks,
  - savegame,
  - music,
  - input,
  - menus,
  - compression/decompression.

What this means:

- You do not need to infer the whole engine architecture from the binary.
- You can map runtime behavior from source modules first, then use the binaries to confirm details.
- Missing proprietary libraries and missing original toolchains are still a problem, but that is a much smaller problem than reconstructing the entire engine from scratch.

Constraint:

- If you directly reuse or adapt this code, assume GPL obligations apply to your ported engine code. That is an engineering and project-licensing decision you should make early.

## 2. Legacy LBA tooling: `mbn_tools`

Path:

- `D:\repos\reverse\littlebigreversing\reference\littlebigreversing\mbn_tools`

This is best treated as a **format-lab and validation kit**, not as the foundation of the port itself.

The tools most relevant to a port are:

### `dl21_package-editor` - LBA Package Editor

Purpose:

- edits and inspects `HQR`, `ILE`, `OBL`, `VOX` packages for LBA1 and LBA2.

Why it matters:

- `HQR` is one of the core asset containers in LBA2.
- This is useful for cataloging container entries and understanding how the engine expects packaged resources.

Best use in the port:

- build a format inventory,
- inspect entry types,
- compare packed vs unpacked data,
- validate your own extractor/parser output.

### `dl30_winhqr` - WinHQR

Purpose:

- compare archives,
- decompress items without full extraction,
- replace items,
- create new HQRs,
- process archive manipulation scripts.

Why it matters:

- Useful when you want repeatable experiments against container files.
- Good for testing hypotheses while implementing your own HQR reader/writer.

Best use in the port:

- differential inspection of archives,
- validating decompression behavior,
- small replacement experiments for understanding resource binding.

### `dl23_scene-manager` - LBA Scene Manager

Purpose:

- edits LBA1 and LBA2 scenes,
- handles actors, zones, tracks, ambient/Twinsen data,
- includes life-script decompiling improvements.

Why it matters:

- `SCENE.HQR` is likely one of the core gameplay-definition assets.
- Scenes encode actor placement, zones, camera/room transitions, and script-linked data.

Best use in the port:

- understand scene structure,
- extract semantics for actors/zones/tracks,
- create validation fixtures for your scene loader and scene interpreter.

### `dl26_story-coder` - LBA Story Coder

Purpose:

- edits `.ls1` and `.ls2` story/script files.

Why it matters:

- Script behavior is one of the highest-risk subsystems in a port.
- If you want gameplay parity, script decoding and interpretation need to be treated as first-class work.

Best use in the port:

- derive script grammar,
- create a normalized intermediate representation for life/move/story logic,
- compare behavior between your interpreter and existing tools.

### `dl18_lbarchitect` - Little Big Architect

Purpose:

- edits room/island grid data,
- works with brick files, layout libraries, and grid files,
- explicitly supports LBA2 rooms.

Why it matters:

- This gives you leverage over the world composition pipeline:
  - bricks,
  - layouts,
  - grids,
  - room visualization.

Best use in the port:

- derive the static world representation,
- verify room assembly,
- understand how room/grid data and scenes fit together.

### `dl31_xtract` - Xtract

Purpose:

- extracts videos using `RESS.HQR` metadata and `VIDEO.HQR` data,
- emits Smacker (`.SMK`) files.

Why it matters:

- Video playback is a discrete subsystem that can be isolated and ported later.
- The fact that this tool reads video metadata from `RESS.HQR` is itself useful architectural information.

Best use in the port:

- document the video index format,
- verify video offsets and lookup logic,
- establish test vectors for a future movie subsystem.

### `dl24_screen-viewer` - LBA Screen Viewer

Purpose:

- loads images/movies from `HQR`, `ILE`, `LIM`, bricks/sprites, raw sprites, saved-game images.

Why it matters:

- Useful for quick visual validation when implementing image decoders.

Best use in the port:

- confirm palettes,
- verify sprite/brick/image decoding,
- inspect screen resources without writing custom visualization first.

### Other MBN tools

There are many additional editors/viewers in the pack. For a full port, most of them are secondary. They are useful if a subsystem blocks, but they should not drive the project plan.

Examples:

- font editors,
- shape editors,
- text editors,
- model viewers,
- island viewers.

These are best used for spot validation, not as primary infrastructure.

## 3. Local reverse-engineering stack under `D:\repos\reverse`

Observed tools:

- `ghidra`
- `x64dbg`
- `Detect-It-Easy`
- `PE-bear`

Recommended roles:

### Ghidra

Use it for:

- static analysis of `TLBA2C.exe`,
- static analysis of original PE-side support binaries,
- source-to-binary mapping against `lba2-classic`,
- identifying code that depends on missing proprietary libraries,
- annotating binary-only behavior not obvious from source.

Ghidra becomes especially valuable if you use the historic source as a map and then verify unresolved behavior in the binaries.

### x64dbg

Use it for:

- dynamic analysis of Windows executables such as `TLBA2C.exe`,
- GOG wrapper behavior,
- loader decisions,
- file-open sequences in the Windows layer.

It is less useful for the original DOS executable directly. For the DOS-side runtime, you will eventually want a DOS-aware debugger workflow if binary-level runtime tracing becomes necessary.

### Detect It Easy / PE-bear

Use them for:

- quick PE fingerprinting,
- section/resource/import inspection,
- wrapper/launcher triage,
- identifying packers/protectors and compiler signatures.

These are triage accelerators, not primary research environments.

## Planning Ownership

This report now stops at feasibility, evidence, workspace inventory, and risks.

The canonical execution plan lives in `docs/LBA2_ZIG_PORT_PLAN.md`, including:

- the Zig 0.15.2 + SDL2 target runtime
- the strategic phase map, including that the first-viewer gate is already crossed
- the current replan gate around `LM_DEFAULT` / `LM_END_SWITCH`
- the document-ownership split between the roadmap, `docs/codex_memory/current_focus.md`, and `docs/PROMPT.md`
- stable module boundaries
- the current test plan

At a high level, the recommended implementation posture remains:

- use the historic source tree as a behavioral reference
- use extracted original assets as canonical runtime inputs
- use preserved MBN tools and RE tooling as validators, not as architecture drivers
- build a new runtime instead of trying to preserve the original build environment

## How to Use the Available Tools Effectively

## Primary tools for the project

- `lba2-classic\SOURCES`
  - primary behavioral reference
- `dl21_package-editor`
  - package inspection and extraction experiments
- `dl30_winhqr`
  - archive comparison and decompression experiments
- `dl23_scene-manager`
  - scene structure and script-adjacent validation
- `dl26_story-coder`
  - script investigation
- `dl18_lbarchitect`
  - room/grid/world composition
- `ghidra`
  - binary/source gap analysis

## Secondary tools

- `dl31_xtract`
  - video extraction
- `dl24_screen-viewer`
  - image/sprite/palette validation
- `dl16_lba2-island-viewer`
  - world visualization cross-checks
- `dl19_model-viewer`
  - body/animation/model validation
- `x64dbg`
  - Windows wrapper/runtime observation
- `Detect-It-Easy`, `PE-bear`
  - binary triage

## Tools that should not define the architecture

The legacy editors/viewers are useful, but they are old utilities with narrow goals. They should help you understand data, not dictate your engine design.

Do not build your pipeline around:

- manual GUI-only editing,
- ad hoc archive patching,
- or reproducing the exact behavior of old utilities unless needed for correctness.

## Risks and Unknowns

## 1. Missing proprietary libraries and build dependencies

The historic source tree is valuable, but it is not a drop-in modern build. Some libraries/tooling are absent or obsolete.

Mitigation:

- use the source as specification first,
- isolate missing-library calls early,
- replace them with modern equivalents in your own runtime.

## 2. Script/runtime semantics may still be under-documented

Even with tools and source, there may be corner cases in scene/life logic.

Mitigation:

- build small scene-specific tests,
- compare behavior against the original runtime,
- use Ghidra only for unresolved semantics.

## 3. Asset formats may have edge cases not handled by old tools

The old community tools are helpful, but they are not guaranteed complete or bug-free.

Mitigation:

- never treat one legacy tool as absolute truth,
- cross-check against source, binaries, and multiple tools.

## 4. Scope creep

A "full port" can become too large if you try to modernize everything at once.

Mitigation:

- define a parity target first,
- ship a vertical slice early,
- postpone nonessential enhancements.

## Execution Plan Pointer

For current implementation direction and next steps, use `docs/LBA2_ZIG_PORT_PLAN.md` rather than this report.

## Final Assessment

You already have enough material in this workspace to make the project feasible.

The critical decision is not whether the game can be ported. It can.

The critical decision is whether you want to spend your time:

- reconstructing already-known structure from binaries,
- or building a new runtime with the source tree, extracted assets, and legacy tools acting as a reference system.

For a graduation project, the second approach is clearly stronger.

## Current Workspace Status

This section reflects the current state of the workspace after the initial setup and cleanup work. It is intended as a handoff note for the next agent.

### Current repo layout

The repo root is now organized like this:

- `docs/`
  - reports and notes
- `port/`
  - reserved for the new modern port implementation
- `reference/`
  - imported upstream/reference material
- `scripts/`
  - environment/bootstrap helpers
- `work/`
  - extracted artifacts and temporary analysis outputs

Important current paths:

- report: `D:\repos\reverse\littlebigreversing\docs\PORTING_REPORT.md`
- modern port workspace: `D:\repos\reverse\littlebigreversing\port`
- historic source tree: `D:\repos\reverse\littlebigreversing\reference\lba2-classic`
- imported MBN tools: `D:\repos\reverse\littlebigreversing\reference\littlebigreversing\mbn_tools`
- extracted GOG payload: `D:\repos\reverse\littlebigreversing\work\_innoextract_full`
- extracted original CD root: `D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2`
- installer binary: `D:\repos\reverse\littlebigreversing\reference\installers\setup_twinsens_little_big_adventure_2_classic_3.2.4.3_(61767).exe`

### Environment helpers already added

The current helper entrypoints are:

- `D:\repos\reverse\littlebigreversing\scripts\dev-shell.py`
- `D:\repos\reverse\littlebigreversing\scripts\check-env.py`

Use:

- `py -3 .\scripts\dev-shell.py shell`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test`
- `py -3 .\scripts\check-env.py`

`dev-shell.py` imports the Visual Studio toolchain environment for a child shell or command and exports:

- `LBA2_REPO_ROOT`
- `LBA2_ORIGINAL_CD_ROOT`
- `LBA2_SOURCE_ROOT`
- `LBA2_MBN_TOOLS_ROOT`

`check-env.py` currently validates:

- Visual Studio/MSVC/CMake/Ninja/MASM
- Python/Java/Git/7-Zip
- Ghidra/x64dbg/DIE/PE-bear
- the historic source tree
- the extracted CD data
- the MBN tools
- SDL2 headers/libs
- DOSBox runtime presence
- DOSBox-X presence
- OpenWatcom presence

### Modern build environment status

The modern build toolchain is available and working on this machine:

- Visual Studio 2022
- `cl`
- `cmake`
- `ninja`
- `MSBuild`
- `ml`

This is not fully on `PATH` by default in the shell, which is why `dev-shell.py` exists.

### SDL2 status

SDL2 has already been installed for the repo using manifest-mode `vcpkg`.

Files added/updated:

- `D:\repos\reverse\littlebigreversing\vcpkg.json`
- `D:\repos\reverse\littlebigreversing\vcpkg_installed\...`

Current manifest:

- dependency: `sdl2`
- baseline pinned in `vcpkg.json`

SDL2 is now detected successfully by `check-env.py`.

Important paths:

- SDL2 headers: `D:\repos\reverse\littlebigreversing\vcpkg_installed\x64-windows\include\SDL2`
- SDL2 library: `D:\repos\reverse\littlebigreversing\vcpkg_installed\x64-windows\lib\SDL2.lib`

This install is repo-local, not global. The repo uses manifest-mode `vcpkg`.

### Remaining missing environment items

At the moment, the environment check only reports two missing items:

- `DOSBox-X`
- `OpenWatcom`

Interpretation:

- `DOSBox-X` is needed for better DOS-side runtime investigation/debugging than the bundled DOSBox.
- `OpenWatcom` is needed only if you want to experiment with the historic build directly.

These are reference-track tools, not blockers for starting the modern SDL2/CMake port.

### Immediate next recommended step

The next engineering step should be:

1. create the initial `port/` CMake skeleton,
2. wire it to the existing `vcpkg.json`,
3. add a tiny SDL2 smoke-test executable,
4. confirm a clean native build from `dev-shell.py`.

After that, the first real implementation milestone should be:

- load one original asset path from `LBA2_ORIGINAL_CD_ROOT`,
- then build a minimal data-loading pipeline before attempting gameplay systems.

### Important git note

The repo underwent a light filesystem reorganization. As a result, `git status` will show a large move/delete/add set until staged.

That is expected.

Do not revert those moves casually. They were intentional to separate:

- `reference/`
- `work/`
- `docs/`
- `port/`

from one another.
