# MBN Tools Cheat Sheet

## Use This As

Fast evidence lookup for the current decode-first interior viewer path.

Use these tools to confirm format facts, compare outputs, and generate fixtures.
Do not use them to justify compatibility shims, fallback parsers, or dual codepaths.

Current repo entry points:
- `cd port && zig build tool -- inspect-background 2 --json`
- `cd port && zig build tool -- inspect-room 2 2 --json`
- `cd port && zig build tool -- audit-life-programs --json`

## Highest-Value Tools

### `dl18_lbarchitect`

Best fit for interior world composition evidence.

Use it when you need to answer:
- how `LBA_BKG.HQR` rooms are built from grids, layouts, fragments, and bricks
- what the header block and layout-usage bits mean
- how columns, sub-columns, and block indices are structured
- how scene-adjacent room data is supposed to fit together

Practical takeaways:
- prefer the technical docs over the GUI for format facts
- treat the docs as validation material for `port/src/game_data/background.zig` and `port/src/game_data/background/parser.zig`
- keep fragment ordering and zero-based classic indices in mind

Relevant docs:
- `dl18_lbarchitect/help/technical/Room format - General information.txt`
- `dl18_lbarchitect/help/technical/Grid specification.txt`
- `dl18_lbarchitect/help/technical/Fragment specification.txt`
- `dl18_lbarchitect/help/technical/Library specification.txt`
- `dl18_lbarchitect/help/technical/LBA2_BinaryScript.txt`

### `dl21_package-editor` and `dl30_winhqr`

Best for archive-level verification.

Use them when you need to:
- inspect `HQR`, `ILE`, `OBL`, or `VOX` contents
- compare packed vs unpacked entries
- test decompression behavior without trusting one parser
- try small replacement experiments against resource binding

Practical takeaways:
- use them to validate `tools/mbn_workbench.py` and `port/src/assets/hqr.zig`
- prefer them for differential checks, not as implementation references

### `dl23_scene-manager` and `dl26_story-coder`

Best for scene and script semantics.

Use them when you need to:
- confirm actor, zone, and track structure in scenes
- inspect life-script and story-script behavior
- compare decoded opcode meaning against the current scene decoder

Practical takeaways:
- keep `SCENE.HQR` evidence separate from background evidence
- use them to deepen blockers in `port/src/game_data/scene/life_program.zig` and `port/src/game_data/scene/life_audit.zig`

### `dl24_screen-viewer`

Best for quick visual sanity checks.

Use it when you need to:
- confirm palettes
- verify bricks, sprites, and image decoding
- inspect image-like resources without writing new viewer code first

### `dl31_xtract`

Best for video-index evidence.

Use it when you need to:
- confirm `RESS.HQR` metadata used for `VIDEO.HQR`
- understand movie lookup before a future media slice

## Recommended Workflow

1. Pull the format fact from the preserved docs or tool output.
2. Cross-check it against the classic source tree and current port code.
3. Promote only the defended fact into checked-in docs or tests.
4. Stop once the evidence is enough for the canonical codepath.

## What Not To Do

- Do not build new compatibility layers around legacy quirks.
- Do not assume GUI behavior is authoritative when a spec doc exists.
- Do not spread scene, background, and video evidence across one blended note.
