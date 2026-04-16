# Classic Test Anchors

These anchors pin current repo behavior to the checked-out `lba2-classic-community` source tree before we widen runtime, save/load, or dialog claims.

## ChangeCube

Classic source anchors:

- `../lba-reference-repos/lba2-classic-community/docs/LIFECYCLES.md`: scene loading is triggered by `ChangeCube()` when the hero enters a zone-type-0 trigger or a life script executes `LM_CHANGE_CUBE`.
- `../lba-reference-repos/lba2-classic-community/SOURCES/OBJECT.CPP`: `CheckZoneSce`, `GereZoneChangeCube`, and `ChangeCube`.
- `../lba-reference-repos/lba2-classic-community/SOURCES/GERELIFE.CPP`: `LM_CHANGE_CUBE` and `LM_SET_CHANGE_CUBE`.

Observed rules:

- `CheckZoneSce()` only lets the hero fire type-0 change-cube zones, then `GereZoneChangeCube()` computes `NewCube`, `NewPosX/Y/Z`, yaw delta, and `FlagChgCube = 1`.
- `GereZoneChangeCube()` treats `Info5` as `ZONE_TEST_BRICK`, `Info6` as `ZONE_DONT_REAJUST_POS_TWINSEN`, and `Info7 & ZONE_ON` as the live enabled bit.
- `LM_CHANGE_CUBE` does not compute a zone-relative position. It sets `NewCube` and `FlagChgCube = 2`, which makes `ChangeCube()` use the saved start position path.
- `LM_SET_CHANGE_CUBE` toggles change-cube zones by matching `Type == 0` and `Info4 == selector`.

Port implications:

- Keep `ChangeCubeSemantics.test_brick`, `dont_readjust_twinsen`, `initially_on`, destination world position, and yaw source-backed to the classic `Info*` fields.
- Keep runtime room-transition assertions generic. They should prove pending transition metadata and bounded trigger reachability, not claim full handoff parity before the port owns real room loading.

Current repo test anchors:

- `port/src/game_data/scene/tests/zone_tests.zig`: source-backed decode of `test_brick`, `dont_readjust_twinsen`, and `initially_on`.
- `port/src/game_data/scene/tests/asset_regressions.zig`: asset-backed change-cube semantics for guarded rooms.
- `port/src/app/viewer/state_test.zig`: guarded room fixtures preserve typed change-cube metadata.
- `port/src/runtime/update_test.zig`: generic pending room-transition fields match zone semantics, including the bounded `2/2` zone-recovery seam.

## Save/Load Payload Structure

Classic source anchors:

- `../lba-reference-repos/lba2-classic-community/docs/SAVEGAME.md`
- `../lba-reference-repos/lba2-classic-community/SOURCES/SAVEGAME.CPP`: `SaveGame`, `LoadGame`, `SaveContexte`, `LoadContexte`, `LoadGameScreen`, and `LoadGamePlayerName`

Observed rules:

- The save header stores the version byte, cube index, player name, and optional decompressed size before the payload block.
- The payload is a `160x120` screenshot followed by the `SaveContexte()` stream, not a generic full-memory dump.
- `SaveContexte()` / `LoadContexte()` explicitly persist `ListVarGame`, `ListVarCube`, `MagicLevel`, `MagicPoint`, `SceneStartX/Y/Z`, `StartXCube/Y/Z`, inventory, holomap flags, timer, hero behavior/body, checksum, and later extended context blocks.
- Dialog UI state is not part of that persisted contract. The classic save path does not serialize `CurrentDial`, `FlagDial`, `FlagRunningDial`, or `NumObjSpeak`.

Port implications:

- When save/load lands in the port, serialize gameplay/session state separately from transient UI/dialog state.
- Use `SAVEGAME.CPP` plus `docs/SAVEGAME.md` as the payload oracle instead of LBArchitect exports or save-preview heuristics.

Current repo test anchors:

- `tools/test_life_trace.py`: single-slot `Load Game` staging and cleanup tests keep `current.lba`, staged named saves, and `autosave.lba` handling explicit, but they do not validate classic payload layout.
- `tools/test_life_trace.py`: Sendell summary tests keep persisted-style story-state fields such as `MagicLevel`, `MagicPoint`, and inventory-backed state separate from dialog UI state, but they are adjacent evidence rather than `SaveContexte()` layout tests.
- Missing port-side gate to add when serializer work begins: a golden round-trip test that pins header boundaries, screenshot placement, and the first `SaveContexte()` fields before claiming save/load parity.

## Dialog Transient-State Semantics

Classic source anchors:

- `../lba-reference-repos/lba2-classic-community/SOURCES/MESSAGE.CPP`: `CurrentDial`, `InitDial`, `CommonOpenDial`, `OpenDial`, `NextDialCar`, `CloseDial`, `Dial`, `MyDial`, and `PlaySpeakVoc`
- `../lba-reference-repos/lba2-classic-community/SOURCES/GERELIFE.CPP`: `LM_MESSAGE`, `LM_ADD_MESSAGE`, `LM_MESSAGE_OBJ`, `LM_ADD_MESSAGE_OBJ`, `LM_END_MESSAGE`, and `LM_END_MESSAGE_OBJ`

Observed rules:

- `CommonOpenDial()` resets line, page, and buffer state, sets `CurrentDial`, and marks `FlagRunningDial = TRUE`.
- `CloseDial()` clears the running flag and forces the pager state machine to reset through `NextDialCar()`.
- `NumObjSpeak` is temporary speaker-routing state for live voice playback and is reset to `-1` immediately after `PlaySpeakVoc()` configures the sample.
- Dialog progress is timer/input-driven in `NextDialCar()`, `Dial()`, and `MyDial()`. The meaningful durable mutations happen through surrounding script effects, not through persisted dialog-page state.
- `LM_END_MESSAGE` and `LM_END_MESSAGE_OBJ` do not add a separate durable dialog-state contract; they only advance the script stream.

Port implications:

- Keep `CurrentDial` evidence-only until the port owns a real dialog/UI subsystem.
- Keep bounded Sendell room `36` runtime tests focused on story-state deltas, not faux persistence of classic dialog pagination or speaker-routing state.
- Save/load parity should not serialize transient dialog-page or live speaker-routing state by default.

Current repo test anchors:

- `port/src/runtime/object_behavior_test.zig`: the bounded room-36 sequence asserts story-state deltas only.
- `port/src/runtime/update_test.zig`: `advance_story` steps consume intent without inventing room-transition side effects.
- `tools/life_trace/capture_sendell_ball.py`: `CurrentDial` remains an explicitly missing direct-read field until dialog/UI parity work starts.
- `tools/test_life_trace.py`: keep a unit test that `CurrentDial` stays in `MISSING_STATE_FIELDS` and not in the captured durable-state field list.
