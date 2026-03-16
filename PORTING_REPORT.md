# LBA2 Modern Port Report

## Scope

This report is oriented toward a graduation-project goal: producing a modern port of **Twinsen's Little Big Adventure 2** using the materials already present in this workspace and the tooling available under `D:\repos\reverse`.

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

- `D:\repos\reverse\littlebigreversing\_innoextract_full`

This contains:

- the GOG launcher/wrapper resources,
- the "classic" Windows-facing files such as `TLBA2C.exe`,
- the `Speedrun\Windows` subtree,
- and a large embedded file `Speedrun\Windows\LBA2.GOG`.

### Nested original game image

`LBA2.GOG` is not an arbitrary blob. It is a **raw CD image** with **2352-byte sectors**. Converting each sector to its 2048-byte payload produced:

- `D:\repos\reverse\littlebigreversing\_innoextract_full\Speedrun\Windows\LBA2.iso`

That ISO was then extracted into:

- `D:\repos\reverse\littlebigreversing\_innoextract_full\Speedrun\Windows\LBA2_cdrom`

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

- `D:\repos\reverse\littlebigreversing\lba2-classic`

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

- `D:\repos\reverse\littlebigreversing\littlebigreversing\mbn_tools`

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

## Recommended Port Strategy

## Recommendation

The best project shape is:

**source-assisted reimplementation with extracted original assets and tool-assisted format validation**

That means:

- do not try to make the 1997 code compile as your final target,
- do not try to reverse the DOS binary from zero,
- do use the historic code as the authoritative behavioral map,
- do write a new modern runtime around documented and validated content formats.

This is the best tradeoff between:

- technical credibility,
- time-to-results,
- explainability in an academic setting,
- and the ability to demo a real modern port.

## What "modern port" should mean here

For this project, a modern port should probably aim for:

- native desktop build on a modern OS,
- modern windowing/input/audio stack,
- data-driven loading of the original game assets,
- no DOSBox dependency for the final runtime,
- faithful scene/script/gameplay behavior,
- enough rendering modernization to be maintainable without changing the original game design.

That is a better framing than "make the old code compile."

## A practical architecture

Suggested engine layers:

1. **Asset layer**
   - HQR reader
   - ILE/OBL readers
   - VOX/music/video metadata readers
   - decompression support

2. **Data model layer**
   - scene representation
   - actor/zone/track representation
   - room/grid/world representation
   - animation/body/model representation

3. **Runtime layer**
   - script interpreter
   - object update loop
   - collision and movement
   - event/trigger system
   - save/load

4. **Platform layer**
   - rendering
   - input
   - audio
   - filesystem
   - timing

5. **Validation/tooling layer**
   - comparison tools against original outputs
   - golden scenes
   - debug visualizations

## Why this is better than a straight source port

A straight source port will drag in:

- old compiler assumptions,
- DOS memory model assumptions,
- assembly dependencies,
- proprietary library gaps,
- and platform APIs that are not worth preserving.

A reimplementation guided by the source avoids most of that while preserving behavior.

## Suggested Work Breakdown

## Phase 1: Establish the canonical corpus

Use as canonical inputs:

- original CD data from `...LBA2_cdrom\LBA2`
- extracted GOG data for comparison
- historic source from `lba2-classic\SOURCES`

Deliverables:

- a documented asset inventory,
- per-format notes,
- a file map from original CD paths to modern runtime expectations.

## Phase 2: Recover format knowledge

Priority formats:

- `HQR`
- `SCENE.HQR`
- `RESS.HQR`
- `ANIM.HQR`
- `BODY.HQR`
- `SPRITES.HQR`
- `LBA_BKG.HQR`
- `ILE` / `OBL`
- `VOX`

Use:

- Package Editor
- WinHQR
- Scene Manager
- Story Coder
- Screen Viewer
- Xtract

Deliverables:

- parsers or parser notes,
- small fixtures for each format,
- known-good decoded outputs.

## Phase 3: Build the world loader

Target:

- load rooms/grids,
- load scene definitions,
- spawn actors,
- display static world correctly.

Use:

- LBArchitect for room/grid understanding,
- Scene Manager for scene semantics,
- Screen Viewer / model viewers for visual spot checks.

Deliverables:

- a scene viewer in your target engine,
- camera movement through at least one room,
- actor placement matching original data.

## Phase 4: Implement scripts and gameplay

This is likely the hardest phase.

Target:

- life/move/story script interpretation,
- triggers/zones,
- object behavior,
- transitions between rooms/scenes,
- inventory/state progression.

Use:

- `lba2-classic\SOURCES` as the primary behavioral reference,
- Scene Manager and Story Coder for structure and validation,
- Ghidra only where source and assets still leave ambiguity.

Deliverables:

- a playable slice,
- deterministic comparisons against the original for selected scenes.

## Phase 5: Audio, video, save/load, and polish

Target:

- music,
- voices,
- cutscenes,
- menus,
- savegame compatibility if desired.

Use:

- Xtract for video understanding,
- source tree for subsystem logic,
- Screen Viewer and package tools for media validation.

Deliverables:

- vertical slice with one full gameplay segment,
- stable boot-to-play flow.

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

## Concrete Recommendation

If this were my project, I would choose the following path:

1. Use `lba2-classic\SOURCES` as the architectural map.
2. Use `...LBA2_cdrom\LBA2` as the canonical original data set.
3. Implement a new asset-loading layer for `HQR`, scenes, grids, models, animations, and media metadata.
4. Build a debug-first viewer for rooms, actors, and zones.
5. Implement script execution and gameplay incrementally.
6. Use MBN tools as validators at each layer.
7. Use Ghidra only where the source tree or tools leave holes.

This gives you the strongest academic story:

- you are not just recompiling old code,
- you are not wasting time rediscovering known structure,
- and you are producing a maintainable modern runtime backed by a documented reverse-engineering process.

## Immediate Next Steps

The next high-value tasks are:

1. Write a machine-readable asset inventory from `LBA2_cdrom\LBA2`.
2. Identify the minimum format set needed to render one room and one actor.
3. Trace how `SCENE.HQR`, `LBA_BKG.HQR`, `BODY.HQR`, `ANIM.HQR`, and `SPRITES.HQR` connect.
4. Read the corresponding modules in `lba2-classic\SOURCES`.
5. Decide the target runtime stack for the port itself.

For the runtime stack, the safest choice is a modern C++ engine layer with SDL2/OpenGL or SDL2/software rendering, because it maps more naturally onto the existing source and data than a radically different stack.

## Final Assessment

You already have enough material in this workspace to make the project feasible.

The critical decision is not whether the game can be ported. It can.

The critical decision is whether you want to spend your time:

- reconstructing already-known structure from binaries,
- or building a new runtime with the source tree, extracted assets, and legacy tools acting as a reference system.

For a graduation project, the second approach is clearly stronger.
