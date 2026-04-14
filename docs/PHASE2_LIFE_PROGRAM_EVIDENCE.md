# Phase 2 Life Program Evidence

## Scope

This memo audits the checked-in classic source that defines scene-local life-program structure:

- `reference/lba2-classic/SOURCES/COMMON.H` for the canonical `LM_*`, `LF_*`, and `LT_*` inventories
- `reference/lba2-classic/SOURCES/GERELIFE.CPP` for the live `DoLife`, `DoFuncLife`, and `DoTest` byte readers
- `reference/lba2-classic/SOURCES/DISKFUNC.CPP` for how scene payloads expose raw life blobs to the classic runtime
- `reference/lba2-classic/SOURCES/DEFINES.H`, `PERSO.CPP`, and `SAVEGAME.CPP` for the runtime state that `DoLife` mutates or preserves

The goal here is structural byte-layout evidence only. This memo does not claim full gameplay semantics for the life language, and it does not change the current repo boundary where raw `life_bytes` remain canonical.

## High-Level Findings

- `COMMON.H` defines `NB_MACROS_LIFE 155`, so the life-opcode space is `0..154`.
- Within that `155`-slot space, `COMMON.H` names `149` `LM_*` ids. Slots `5..9` are unnamed, and slot `132` is a commented-out duplicate `LM_NOP` alias rather than a supported opcode.
- `GERELIFE.CPP` has live `DoLife` switch cases for `142` named `LM_*` opcodes.
- `COMMON.H` names eight opcodes that do not have a live `DoLife` case: `LM_NOP`, `LM_ENDIF`, `LM_REM`, `LM_DEFAULT`, `LM_END_SWITCH`, `LM_SPY`, `LM_DEBUG`, and `LM_DEBUG_OBJ`.
- `GERELIFE.CPP` also contains one commented-out dead case, `LM_MESSAGE_CHAPTER`, that is not part of the `COMMON.H` inventory and must not be treated as live decoder evidence.
- Four live object-scoped opcodes are easy to miss when summarizing the switch because they sit far from their non-object variants: `LM_STOP_L_TRACK_OBJ`, `LM_RESTORE_L_TRACK_OBJ`, `LM_SAVE_COMPORTEMENT_OBJ`, and `LM_RESTORE_COMPORTEMENT_OBJ` each consume one `object_index_u8`.
- Life control flow is not a flat opcode stream. `LM_IF`/`LM_SWITCH`-family opcodes embed an `LF_*` function call parsed by `DoFuncLife`, then a comparison parsed by `DoTest`, then one or more jump offsets.
- Some control-flow opcodes mutate the program bytes in place at runtime: `LM_SWIF` rewrites itself to `LM_SNIF`, `LM_SNIF` rewrites back to `LM_SWIF`, and `LM_ONEIF` rewrites itself to `LM_NEVERIF`.
- The offline audit path at `zig build tool -- audit-life-programs [--json]` first proved that only `LM_DEFAULT` and `LM_END_SWITCH` blocked current real assets; the widened `2026-04-14` rerun of `--all-scene-entries` now audits all `221` non-header `SCENE.HQR` entries (`2..222`) and `3109` life blobs with `unsupported_blob_count = 0`.
- A follow-up raw one-client `cdb` pass on the stable late-family Scene11 runtime state now closes the structural marker-width question for the switch-family blockers:
  - [scene11-branchA-nextfetch74-proof.log](../work/crash/scene11-branchA-nextfetch74-proof.log) shows `LM_DEFAULT (0x74)` fetched at `PtrPrg = 0x...401`, then the next interpreter fetch immediately resumes at `PtrPrg = 0x...402`.
  - [scene11-branchA-nextfetch76.log](../work/crash/scene11-branchA-nextfetch76.log) shows `LM_END_SWITCH (0x76)` fetched at `PtrPrg = 0x...408`, then the next interpreter fetch immediately resumes at `PtrPrg = 0x...409`.
- That raw-cdb evidence is sufficient to support both opcodes as one-byte structural markers in the offline decoder, while still leaving broader gameplay semantics outside the scope of this memo.

## Canonical Boundary After This Audit

- Keep raw `life_bytes` as the canonical scene-model and CLI surface.
- Treat `GERELIFE.CPP` rather than `COMMON.H` as the primary byte-layout oracle for a future decoder.
- Keep the first life decoder as an unwired module that works directly from raw bytes.
- Support `LM_DEFAULT` and `LM_END_SWITCH` in that decoder as one-byte structural markers with no extra operand bytes.
- Treat the remaining six named-but-unimplemented `LM_*` ids as still unsupported but not current real-asset blockers unless a future broader audit or asset set proves otherwise.
- The current decoder should still reject `LM_NOP`, `LM_ENDIF`, `LM_REM`, `LM_SPY`, `LM_DEBUG`, and `LM_DEBUG_OBJ` unless stronger evidence appears.

## Branch-A Evidence Threshold

Phase 4 branch A is supportable only if checked-in primary-source evidence fixes structural handling for `LM_DEFAULT` or `LM_END_SWITCH` beyond header names, comments, or asset-local recurrence.

Acceptable proof:

- a live checked-in byte reader
- preserved checked-in runtime logic that fixes operand layout or control-flow behavior
- another checked-in primary source with equally concrete structural detail

Unacceptable proof on their own:

- `COMMON.H` opcode names by themselves
- inline comments by themselves
- unsupported-hit offsets from the offline audit
- repeated asset-byte patterns
- local byte windows without interpreter fetch/advance proof

The current workspace now meets that branch-A threshold for both opcodes through the preserved raw-cdb fetch logs plus the widened decoder/audit reruns.

## Scene Loader Boundary

Classic scene loading preserves life programs as raw counted byte blobs before any interpretation:

- `DISKFUNC.CPP` reads a `u16` byte count for the hero track blob, then points `PtrTrack` at that raw slice.
- It immediately does the same for the hero life blob (`PtrLife = PtrSce`, then advances by the counted size).
- Each non-hero object repeats that same `u16`-length-plus-raw-bytes pattern for its track blob and life blob.

That matches the current Zig scene-model boundary: raw life bytes are a source-backed scene-local payload, but typed life decoding is still a separate step.

## `LM_*` Opcode Inventory By Structural Class

The strongest checked-in layout evidence is always the exact `PtrPrg` reads in `DoLife`.

### No Extra Bytes After The Opcode

These cases do not consume any additional bytes beyond the opcode itself:

- `LM_END`, `LM_END_LIFE`, `LM_RETURN`, `LM_END_COMPORTEMENT`
- `LM_SUICIDE`
- `LM_STOP_L_TRACK`, `LM_RESTORE_L_TRACK`
- `LM_INC_CHAPTER`, `LM_USE_ONE_LITTLE_KEY`, `LM_INC_CLOVER_BOX`
- `LM_FULL_POINT`
- `LM_GAME_OVER`, `LM_THE_END`, `LM_BRUTAL_EXIT`
- `LM_SAVE_COMPORTEMENT`, `LM_RESTORE_COMPORTEMENT`
- `LM_INVERSE_BETA`
- `LM_NO_BODY`
- `LM_POPCORN`
- `LM_SAVE_HERO`, `LM_RESTORE_HERO`
- `LM_ACTION`
- `LM_END_MESSAGE`

### One Signed Or Unsigned Byte After The Opcode

These cases consume exactly one byte after the opcode:

- `LM_COMPORTEMENT` (`raw_u8`; runtime only skips it)
- `LM_FALLABLE` (`fallable_mode_u8`)
- `LM_COMPORTEMENT_HERO` (`hero_comportement_id_u8`)
- `LM_SET_MAGIC_LEVEL` (`magic_level_u8`)
- `LM_SUB_MAGIC_POINT` (`magic_delta_u8`)
- `LM_CAM_FOLLOW` (`object_index_u8`)
- `LM_KILL_OBJ` (`object_index_u8`)
- `LM_BODY` (`body_id_u8`)
- `LM_SET_USED_INVENTORY` (`inventory_flag_u8`)
- `LM_FOUND_OBJECT` (`found_object_id_u8`)
- `LM_CHANGE_CUBE` (`destination_cube_u8`)
- `LM_ADD_FUEL` (`raw_fuel_delta_u8`; gameplay logic is commented out but the byte is still consumed)
- `LM_SUB_FUEL` (`raw_fuel_delta_u8`; gameplay logic is commented out but the byte is still consumed)
- `LM_SET_HOLO_POS` (`holomap_index_u8`)
- `LM_CLR_HOLO_POS` (`holomap_index_u8`)
- `LM_OBJ_COL` (`enabled_u8`)
- `LM_INVISIBLE` (`enabled_u8`)
- `LM_BRICK_COL` (`collision_mode_u8`)
- `LM_POS_POINT` (`track_point_index_u8`)
- `LM_BULLE` (`bubble_state_u8`)
- `LM_PLAY_MUSIC` (`music_id_u8`)
- `LM_SET_ARMURE` (`armor_s8`)
- `LM_PALETTE` (`palette_index_u8`)
- `LM_FADE_TO_PAL` (`palette_index_u8`)
- `LM_CAMERA_CENTER` (`camera_center_step_u8`; runtime multiplies it by `1024` and masks to `4095`)
- `LM_MEMO_ARDOISE` (`memo_index_u8`)
- `LM_TRACK_TO_VAR_GAME` (`var_game_index_u8`)
- `LM_VAR_GAME_TO_TRACK` (`var_game_index_u8`)
- `LM_SET_FRAME` (`frame_u8`)
- `LM_SET_FRAME_3DS` (`frame_u8`)
- `LM_NO_CHOC` (`enabled_u8`)
- `LM_CINEMA_MODE` (`cinema_mode_u8`)
- `LM_ANIM_TEXTURE` (`enabled_u8`)
- `LM_END_MESSAGE_OBJ` (`object_index_u8`; consumed but not used by the live body)
- `LM_INIT_BUGGY` (`buggy_param_u8`)
- `LM_ECLAIR` (`duration_tenths_u8`)
- `LM_PLUIE` (`duration_tenths_u8`)
- `LM_BACKGROUND` (`enabled_u8`)
- `LM_GIVE_BONUS` (`clear_after_use_u8`; `0` marks the object as exhausted)
- `LM_STOP_L_TRACK_OBJ` (`object_index_u8`)
- `LM_RESTORE_L_TRACK_OBJ` (`object_index_u8`)
- `LM_SAVE_COMPORTEMENT_OBJ` (`object_index_u8`)
- `LM_RESTORE_COMPORTEMENT_OBJ` (`object_index_u8`)

### Two Single-Byte Fields After The Opcode

These cases consume two one-byte fields after the opcode:

- `LM_SET_LIFE_POINT_OBJ` (`object_index_u8`, `life_points_u8`)
- `LM_SUB_LIFE_POINT_OBJ` (`object_index_u8`, `delta_life_u8`)
- `LM_ADD_LIFE_POINT_OBJ` (`object_index_u8`, `delta_life_u8`)
- `LM_HIT_OBJ` (`object_index_u8`, `hit_force_u8`)
- `LM_BODY_OBJ` (`object_index_u8`, `body_id_u8`)
- `LM_SET_VAR_CUBE` (`var_cube_index_u8`, `value_u8`)
- `LM_ADD_VAR_CUBE` (`var_cube_index_u8`, `delta_u8`)
- `LM_SUB_VAR_CUBE` (`var_cube_index_u8`, `delta_u8`)
- `LM_STATE_INVENTORY` (`inventory_flag_u8`, `object_state_u8`)
- `LM_ECHELLE` (`zone_num_u8`, `enabled_u8`)
- `LM_SET_HIT_ZONE` (`zone_num_u8`, `zone_info1_u8`)
- `LM_SET_GRM` (`zone_num_u8`, `enabled_u8`)
- `LM_SET_CHANGE_CUBE` (`change_cube_selector_u8`, `enabled_u8`)
- `LM_FLOW_POINT` (`track_point_index_u8`, `flow_kind_u8`)
- `LM_PCX` (`pcx_index_u8`, `effect_u8`)
- `LM_SET_CAMERA` (`camera_zone_num_u8`, `enabled_u8`)
- `LM_SET_RAIL` (`rail_zone_num_u8`, `switch_state_u8`)
- `LM_SHADOW_OBJ` (`object_index_u8`, `enabled_u8`)
- `LM_FLOW_OBJ` (`object_index_u8`, `flow_kind_u8`)
- `LM_POS_OBJ_AROUND` (`anchor_object_index_u8`, `subject_object_index_u8`)
- `LM_ESCALATOR` (`zone_num_u8`, `enabled_u8`)

### One `s16` After The Opcode

These cases read one signed 16-bit value after the opcode:

- `LM_SET_COMPORTEMENT` (`life_offset_s16`)
- `LM_SET_TRACK` (`track_offset_s16`)
- `LM_MESSAGE` (`dialog_id_s16`)
- `LM_ADD_MESSAGE` (`dialog_id_s16`)
- `LM_MESSAGE_ZOE` (`dialog_id_s16`)
- `LM_GIVE_GOLD_PIECES` (`delta_money_s16`)
- `LM_ADD_GOLD_PIECES` (`delta_money_s16`)
- `LM_SET_DOOR_LEFT` (`distance_s16`)
- `LM_SET_DOOR_RIGHT` (`distance_s16`)
- `LM_SET_DOOR_UP` (`distance_s16`)
- `LM_SET_DOOR_DOWN` (`distance_s16`)
- `LM_ADD_CHOICE` (`choice_message_s16`)
- `LM_ASK_CHOICE` (`choice_prompt_message_s16`)
- `LM_BETA` (`beta_s16`)
- `LM_SAMPLE` (`sample_id_s16`)
- `LM_SAMPLE_RND` (`sample_id_s16`)
- `LM_SAMPLE_ALWAYS` (`sample_id_s16`)
- `LM_SAMPLE_STOP` (`sample_id_s16`)
- `LM_SET_SPRITE` (`sprite_id_s16`)

### One `u16` After The Opcode

These cases read one unsigned 16-bit value after the opcode:

- `LM_ANIM` (`anim_id_u16`)
- `LM_ANIM_SET` (`anim_id_u16`)
- `LM_SET_ANIM_DIAL` (`anim_dial_u16`)

### Mixed Fixed-Width Layouts

- `LM_SET_COMPORTEMENT_OBJ`: `object_index_u8`, `life_offset_s16`
- `LM_SET_TRACK_OBJ`: `object_index_u8`, `track_offset_s16`
- `LM_MESSAGE_OBJ`: `object_index_u8`, `dialog_id_s16`
- `LM_ADD_MESSAGE_OBJ`: `object_index_u8`, `dialog_id_s16`
- `LM_SET_VAR_GAME`: `var_game_index_u8`, `value_s16`
- `LM_ADD_VAR_GAME`: `var_game_index_u8`, `delta_s16`
- `LM_SUB_VAR_GAME`: `var_game_index_u8`, `delta_s16`
- `LM_SET_ARMURE_OBJ`: `object_index_u8`, `armor_s8`
- `LM_ANIM_OBJ`: `object_index_u8`, `anim_id_u16`
- `LM_ASK_CHOICE_OBJ`: `object_index_u8`, `choice_prompt_message_s16`
- `LM_REPEAT_SAMPLE`: `sample_id_s16`, `repeat_count_u8`
- `LM_PCX_MESS_OBJ`: `pcx_index_u8`, `effect_u8`, `object_index_u8`, `dialog_id_s16`
- `LM_IMPACT_OBJ`: `object_index_u8`, `impact_id_u16`, `y_offset_s16`
- `LM_IMPACT_POINT`: `track_point_index_u8`, `impact_id_u16`
- `LM_NEW_SAMPLE`: `sample_id_s16`, `sample_decalage_s16`, `sample_volume_u8`, `sample_frequency_s16`
- `LM_PARM_SAMPLE`: `sample_decalage_s16`, `sample_volume_u8`, `sample_frequency_s16`

### Variable Layouts That Depend On The Selected Move

- `LM_SET_DIR`: always starts with `move_id_u8`, then `AdjustDirObject` may consume one additional `track_point_index_u8` for `MOVE_FOLLOW`, `MOVE_SAME_XZ`, `MOVE_SAME_XZ_BETA`, `MOVE_CIRCLE`, and `MOVE_CIRCLE2`.
- `LM_SET_DIR_OBJ`: always starts with `object_index_u8`, then `move_id_u8`, then it follows the same conditional `AdjustDirObject` trailing-byte rule as `LM_SET_DIR`.

### Null-Terminated String Layout

- `LM_PLAY_ACF`: null-terminated string payload (`strlen((char *)PtrPrg) + 1`) after the opcode. The checked-in runtime treats it as an ACF resource name/path string.

### Control-Flow Layouts

- `LM_IF` and `LM_AND_IF`: `lf_expr + test + false_jump_offset_s16`
- `LM_OR_IF`: `lf_expr + test + true_jump_offset_s16`
- `LM_SWIF`: `lf_expr + test + jump_offset_s16`, and on success rewrites the opcode byte to `LM_SNIF`
- `LM_SNIF`: `lf_expr + test + jump_offset_s16`, always jumps, and on failure rewrites the opcode byte back to `LM_SWIF`
- `LM_ONEIF`: `lf_expr + test + jump_offset_s16`, and on success rewrites the opcode byte to `LM_NEVERIF`
- `LM_NEVERIF`: `lf_expr + test + jump_offset_s16`, always jumps after consuming the same nested expression/test bytes
- `LM_OFFSET`: `jump_offset_s16`
- `LM_ELSE`: `jump_offset_s16`
- `LM_SWITCH`: `lf_expr` only; it caches the `LF_*` selector, the computed value, and `TypeAnswer` into `ExeSwitch`
- `LM_CASE`: `case_jump_offset_s16 + test`, where the test-literal width comes from the cached `TypeAnswer`
- `LM_OR_CASE`: `case_jump_offset_s16 + test`, again keyed by the cached `TypeAnswer`
- `LM_BREAK`: `jump_offset_s16`

### Switch-Family Source-Pass Conclusion

The source pass alone still does not widen the supported boundary:

- `LM_SWITCH`, `LM_CASE`, `LM_OR_CASE`, and `LM_BREAK` are still the only live switch-family opcodes with checked-in `DoLife` byte-reading code.
- `LM_BREAK` still reads one `jump_offset_s16`, and its inline comment still says it jumps to `END_SWITCH`, but there is still no `case LM_END_SWITCH` in `GERELIFE.CPP`.
- `LM_DEFAULT` still has no direct checked-in classic-source runtime reader beyond its `COMMON.H` define.

What changed is the proof surface. The raw one-client `cdb` fetch logs now show that both opcodes are fetched as one-byte structural markers and that the interpreter resumes on the immediately following byte. That is enough to widen the offline decoder boundary even though classic source never added dedicated switch cases for either opcode.

### Opcode Decision: `LM_DEFAULT`

Proven today:

- `COMMON.H` names `LM_DEFAULT` as opcode `116`.
- Current real assets reach `LM_DEFAULT` in multiple scenes, including scene `2` hero byte offset `170`, scene `11` object `12` byte offset `38`, and scene `44` object byte offsets `274` and `43`.
- `GERELIFE.CPP` still does not provide a live `case LM_DEFAULT`.
- [scene11-branchA-nextfetch74-proof.log](../work/crash/scene11-branchA-nextfetch74-proof.log) shows the interpreter fetching `0x74` at `PtrPrg = 0x...401` and then immediately resuming the next fetch at `PtrPrg = 0x...402`.

Still unproven:

- higher-level gameplay meaning for the default branch body beyond “execution resumes on the following byte”
- whether any future runtime interpreter work needs extra explicit switch-frame bookkeeping beyond the decoder’s one-byte marker treatment

Branch-A supportability today:

- Branch A is supportable for `LM_DEFAULT` as a one-byte structural marker.
- The decoder may treat `LM_DEFAULT` as `byte_length = 1` with no extra operand bytes.

### Opcode Decision: `LM_END_SWITCH`

Proven today:

- `COMMON.H` names `LM_END_SWITCH` as opcode `118`.
- Current real assets reach `LM_END_SWITCH` at scene `5` hero byte offset `46` and scene `44` hero byte offset `713`.
- `GERELIFE.CPP` does not provide a live `case LM_END_SWITCH`.
- `LM_BREAK` reads `jump_offset_s16`, and its inline comment says that jump targets `END_SWITCH`.
- [scene11-branchA-nextfetch76.log](../work/crash/scene11-branchA-nextfetch76.log) shows the interpreter fetching `0x76` at `PtrPrg = 0x...408` and then immediately resuming the next fetch at `PtrPrg = 0x...409`, whose byte is `0x0c`.

Still unproven:

- the full gameplay role of the surrounding switch-family control flow beyond the marker width itself
- whether a future interpreter wants to model `LM_END_SWITCH` explicitly or simply preserve it structurally in the decoded stream

Branch-A supportability today:

- Branch A is supportable for `LM_END_SWITCH` as a one-byte structural marker.
- The decoder may treat `LM_END_SWITCH` as `byte_length = 1` with no extra operand bytes.

### Phase 4 Decision Outcome

The current workspace should take Phase 4 branch A.

- `LM_DEFAULT` and `LM_END_SWITCH` are now inside the supported offline decoder boundary as one-byte structural markers.
- Current real-asset life decoding no longer reports any unsupported blobs in the full-archive audit.
- Future life work should move from marker-width proof to semantic/runtime widening questions.

### Named But Unproven In Live Runtime Code

`COMMON.H` inventories these ids, but `GERELIFE.CPP` does not provide a live `DoLife` case:

- `LM_NOP`
- `LM_ENDIF`
- `LM_REM`
- `LM_DEFAULT`
- `LM_END_SWITCH`
- `LM_SPY`
- `LM_DEBUG`
- `LM_DEBUG_OBJ`

These ids are the main reason a decoder should reject unsupported opcodes instead of assuming that every named `COMMON.H` entry is currently usable.
Only six of them still remain outside the current supported decoder boundary: `LM_NOP`, `LM_ENDIF`, `LM_REM`, `LM_SPY`, `LM_DEBUG`, and `LM_DEBUG_OBJ`.

## `LF_*` Function Layouts Used By Control Flow

`DoFuncLife` defaults `TypeAnswer` to `RET_S8` before dispatch. Future decoding must preserve the exact return-type choice from source rather than inferring it from names.

### `LF_*` With No Extra Bytes

- `LF_COL`
- `LF_CHAPTER`
- `LF_LIFE_POINT` (`RET_S16`)
- `LF_HIT_BY`
- `LF_ACTION`
- `LF_ZONE`
- `LF_NB_GOLD_PIECES` (`RET_S16`)
- `LF_NB_LITTLE_KEYS`
- `LF_COMPORTEMENT_HERO`
- `LF_MAGIC_LEVEL`
- `LF_MAGIC_POINT`
- `LF_CHOICE` (`RET_S16`)
- `LF_FUEL` (`RET_S16`, but the live body does not assign `Value`)
- `LF_L_TRACK` (`RET_U8`)
- `LF_BODY`
- `LF_ANIM` (`RET_S16`)
- `LF_CARRY_BY`
- `LF_CDROM`
- `LF_BETA` (`RET_S16`)
- `LF_DEMO`
- `LF_COL_DECORS` (`RET_U8`)
- `LF_PROCESSOR`

### `LF_*` With One `u8` Argument

- `LF_HIT_OBJ_BY`
- `LF_LIFE_POINT_OBJ` (`RET_S16`)
- `LF_COL_OBJ`
- `LF_DISTANCE` (`RET_S16`)
- `LF_DISTANCE_3D` (`RET_S16`)
- `LF_CONE_VIEW` (`RET_S16`)
- `LF_ZONE_OBJ`
- `LF_VAR_CUBE` (`RET_U8`)
- `LF_VAR_GAME` (`RET_S16`)
- `LF_USE_INVENTORY`
- `LF_L_TRACK_OBJ` (`RET_U8`)
- `LF_BODY_OBJ`
- `LF_ANIM_OBJ` (`RET_S16`)
- `LF_CARRY_OBJ_BY`
- `LF_ECHELLE`
- `LF_RND` (`RET_U8`)
- `LF_RAIL`
- `LF_BETA_OBJ` (`RET_S16`)
- `LF_ANGLE` (`RET_S16`)
- `LF_ANGLE_OBJ` (`RET_S16`)
- `LF_REAL_ANGLE` (`RET_S16`)
- `LF_DISTANCE_MESSAGE` (`RET_S16`)
- `LF_COL_DECORS_OBJ` (stays at the default `RET_S8` in live code)
- `LF_OBJECT_DISPLAYED`

## `DoTest` Comparator Layout

`DoTest` always starts with one comparator byte (`LT_EQUAL`, `LT_SUP`, `LT_LESS`, `LT_SUP_EQUAL`, `LT_LESS_EQUAL`, `LT_DIFFERENT`), then reads the literal using the current `TypeAnswer`:

- `RET_S8`: one signed byte literal
- `RET_U8`: one unsigned byte literal
- `RET_S16`: one signed 16-bit literal
- `RET_STRING`: one null-terminated string literal

For `RET_STRING`, the live code only gives meaningful results for `LT_EQUAL` and `LT_DIFFERENT`; the ordered comparisons return `FALSE`.

## Boundary Blockers For Immediate Scene Integration

- The checked-in source does not prove live handling for every named `COMMON.H` opcode.
- `LM_SWITCH`/`LM_CASE` and the `LM_IF` family require nested `LF_*` plus `DoTest` parsing, so there is no shallow “easy subset” that reflects real control flow without also implementing those subgrammars.
- `LM_SWIF`, `LM_SNIF`, `LM_ONEIF`, and `LM_NEVERIF` are stateful and self-mutating, so a decoder must preserve structural truth rather than normalizing them away.
- A few `LF_*` helpers are asymmetric in source in ways that matter structurally:
  - `LF_FUEL` declares `RET_S16` but leaves `Value` unwritten in the live body.
  - `LF_COL_DECORS` sets `RET_U8`, while the similar `LF_COL_DECORS_OBJ` leaves the default `RET_S8`.

## Current Decoder Boundary

The first safe implementation step is now in place as the unwired offline decoder at `port/src/game_data/scene/life_program.zig`. That decoder should continue to:

- decode only the opcodes with live `GERELIFE.CPP` evidence
- implement the nested `LF_*` and `DoTest` subgrammars exactly as the checked-in source reads them
- preserve self-mutating control-flow opcodes structurally instead of inventing cleaner semantics
- support `LM_DEFAULT` and `LM_END_SWITCH` as one-byte structural markers
- reject the remaining named-but-unimplemented `LM_*` ids fail-fast
- leave `SceneProgramBlob.life` and `inspect-scene` unchanged until stronger evidence justifies scene-surface integration

The broader offline inventory is now complete too. The current `zig build tool -- audit-life-programs --json --all-scene-entries` rerun decodes all `3109` audited life blobs with `unsupported_blob_count = 0`. The remaining follow-up question is no longer whether `LM_DEFAULT` / `LM_END_SWITCH` must stay unsupported; it is which runtime/gameplay slice should use the widened structural decoder boundary next.
