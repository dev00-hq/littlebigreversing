# Scene11 Cross-Check Map

This note is the compact cross-check surface for the current `Scene11Pair` lane.

It exists because the relevant facts are currently split across:

- the `idajs` save map
- the staged runtime `SAVE` folder
- the Frida preset
- the task docs
- and the old IdaJS scene source files themselves

## Cross-Check Surfaces

### Source save map

Primary source:

- [work/idajs_samples_save_map.jsonl](/D:/repos/reverse/littlebigreversing/work/idajs_samples_save_map.jsonl)

This is the best current map for:

- save file name
- save file size
- `raw_scene_entry_index`
- `save_name`
- semantic `scene_lookup`

### Deterministic source crosswalk

Generated crosswalk:

- [idajs_scene_crosswalk.jsonl](/D:/repos/reverse/littlebigreversing/work/idajs_scene_crosswalk.jsonl)

Builder:

- [build_scene_crosswalk.py](/D:/repos/reverse/littlebigreversing/tools/build_scene_crosswalk.py)

This is the best current map for:

- old IdaJS source file
- source line number
- semantic `scene_id`
- derived raw scene entry index
- and matching sample-save rows

### Runtime save map

Runtime snapshot:

- [save-map.jsonl](/D:/repos/reverse/littlebigreversing/work/windbg/save-map.jsonl)

This is useful for:

- checking what the runtime `SAVE` directory actually contained at the time of a debug run
- proving that `current.lba` can drift away from the staged source save

### Frida preset

Structured lane owner:

- [trace_life.py](/D:/repos/reverse/littlebigreversing/tools/life_trace/trace_life.py#L72)

This is the checked-in source for:

- the staged runtime filename
- the scene-11 fingerprint bytes
- the primary target
- the comparison target

## Current Scene11Pair Mapping

### Source save

- source save file: `02-voisin.LBA`
- source map record: [work/idajs_samples_save_map.jsonl](/D:/repos/reverse/littlebigreversing/work/idajs_samples_save_map.jsonl)
- source file size: `9403`
- source save name: `02-voisin`

### Staged runtime save

- staged runtime file: [scene11-pair.LBA](/D:/repos/reverse/littlebigreversing/work/_innoextract_full/Speedrun/Windows/LBA2_cdrom/LBA2/SAVE/scene11-pair.LBA)
- staged runtime file size: `9403`
- staged runtime first visible save-name bytes: `02-voisin`

### Matching evidence

These facts line up between the source map and the staged runtime file:

- same size: `9403`
- same save-name bytes: `02-voisin`
- same promoted task lane in:
  - [LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md#L55)
  - [LM_CURRENT_TASK.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_CURRENT_TASK.md#L66)

Working assumption:

- `scene11-pair.LBA` is the staged runtime copy of source save `02-voisin.LBA`

## Numbering Map

This is the part that caused the ambiguity.

For source save `02-voisin.LBA`:

- raw scene entry index: `11`
- semantic scene id: `9`
- node kind: `iso`
- scene name: `Neighbour's House`
- section: `Twinsen's House Area`
- island: `Citadel island`
- planet: `Twinsun`
- semantic source file label: `Twinsun.ts`

## How To Read The Numbers

When someone says "scene 11" in this lane, ask which one they mean.

Possible meanings:

- raw save-map scene entry index:
  - `raw_scene_entry_index = 11`
- semantic mapped scene id:
  - `scene_id = 9`

Current repo lesson:

- the label `scene11-pair` came from the raw save-map entry index
- it did not come from the semantic mapped scene id

## Runtime Drift Warning

Do not use `current.lba` as a semantic anchor.

Why:

- `current.lba` can be overwritten by the original runtime during control runs
- `work/windbg/save-map.jsonl` already showed runtime-folder saves that no longer matched the staged scene-11 assumption

Operational rule:

- use `work/idajs_scene_crosswalk.jsonl` as the deterministic old-source-to-repo scene truth
- use `work/idajs_samples_save_map.jsonl` as the source-save truth
- use the staged `scene11-pair.LBA` file as the intended runtime copy
- use `work/windbg/save-map.jsonl` only to inspect what the runtime actually had during a specific run

## Best Current One-Line Summary

The safest current cross-check is:

- `02-voisin.LBA` in [work/idajs_samples_save_map.jsonl](/D:/repos/reverse/littlebigreversing/work/idajs_samples_save_map.jsonl)
  ->
- staged as [scene11-pair.LBA](/D:/repos/reverse/littlebigreversing/work/_innoextract_full/Speedrun/Windows/LBA2_cdrom/LBA2/SAVE/scene11-pair.LBA)
  ->
- labeled from `raw_scene_entry_index = 11`
  ->
- semantically mapped to `scene_id = 9`, `Neighbour's House`
