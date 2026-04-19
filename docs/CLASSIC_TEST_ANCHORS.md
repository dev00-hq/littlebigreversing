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
- On the exact public house-door seam that the port models as guarded `2/2`, Frida plus a `cdb` write breakpoint on `0x00499E40` showed `NewCube` stays `0`, observed pulse writes include `LBA2+0x11AEB` / `0x11B2F`, and the first post-load hero landing is exterior-facing near `(18442,250,5660)`.

Port implications:

- Keep `ChangeCubeSemantics.test_brick`, `dont_readjust_twinsen`, `initially_on`, destination world position, and yaw source-backed to the classic `Info*` fields.
- Keep runtime room-transition assertions generic. They should prove pending transition metadata and bounded trigger reachability, not claim full handoff parity before the port owns real room loading.
- The guarded `2/2` public exit now has exact-seam Frida + `cdb` proof that it is an exterior-facing `ChangeCube` handoff rather than a same-index interior room hop, and the checked-in room/load tests keep `2/2` pinned to one enabled cube-`0` change-cube seam for that public door.

Current repo test anchors:

- `port/src/game_data/scene/tests/zone_tests.zig`: source-backed decode of `test_brick`, `dont_readjust_twinsen`, and `initially_on`.
- `port/src/game_data/scene/tests/asset_regressions.zig`: asset-backed change-cube semantics for guarded rooms.
- `port/src/app/viewer/state_test.zig`: guarded room fixtures preserve typed change-cube metadata.
- `port/src/runtime/update_test.zig`: generic pending room-transition fields match zone semantics, including the bounded `2/2` zone-recovery seam.

## Reward Resolution

Classic source anchors:

- `../lba-reference-repos/lba2-classic-community/SOURCES/GERELIFE.CPP`: `LM_GIVE_BONUS`.
- `../lba-reference-repos/lba2-classic-community/SOURCES/EXTRA.CPP`: `WhichBonus`, `GiveExtraBonus`, `ExtraBonus`, and the takable extra resolution path for `SPRITE_MAGIE`.

Observed rules:

- `LM_GIVE_BONUS` does not directly mutate hero magic or inventory. It calls `GiveExtraBonus(ptrobj)`, which resolves the allowed bonus kind from the option-flag mask and spawns a takable extra first.
- Magic pickup resolution happens later through the extra system. On hero contact, `SPRITE_MAGIE` raises `MagicPoint` by `Divers * 2`, capped at `MagicLevel * 20`, and only then is the extra consumed.

Port implications:

- Treat guarded `19/19` object-`2` reward resolution as a two-step contract: bounded collectible spawn first, bounded hero pickup second.
- Do not claim generic inventory or save/load parity from this slice.
- Under the guarded room model, raw scene-object placements are still not admitted floor-truth anchors, so the current port lands the emitted collectible on the nearest admitted standable cell instead of using the raw object point as a pickup-valid world position.

Current repo test anchors:

- `port/src/runtime/update_test.zig`: guarded `19/19` reward emission appends one magic collectible and later pickup resolves it into `MagicPoint`.
- `port/src/app/viewer_shell_test.zig`: the guarded `19/19` overlay distinguishes live reward drops from collected rewards.
- `port/src/main.zig`: bounded `bonus_pickup` diagnostics print the resolved guarded `19/19` magic reward.

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
- Do not treat `CurrentDial` alone as the room-36 dialog-progression oracle. The current direct-read lane can keep it stable while the visible `TypeAnswer` / `Value` lane still advances.
- Keep bounded Sendell room `36` runtime tests focused on story-state deltas, not faux persistence of classic dialog pagination or speaker-routing state.
- Save/load parity should not serialize transient dialog-page or live speaker-routing state by default.

Current repo test anchors:

- `port/src/runtime/object_behavior_test.zig`: the bounded room-36 sequence asserts story-state deltas only.
- `port/src/runtime/update_test.zig`: `advance_story` steps consume intent without inventing room-transition side effects.
- `tools/life_trace/capture_sendell_ball.py`: `CurrentDial` is read directly from the classic runtime as transient evidence only and stays separate from the captured durable-state field list.
- `tools/test_life_trace.py`: keep a unit test that `CurrentDial` stays transient-only, not durable.
