# Golden Targets

These are the locked phase 0 targets. They may change only through an explicit replan decision with replacement evidence.

## `interior-room-twinsens-house`

- semantic label: Twinsen's house interior room
- asset references: `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`
- evidence anchors:
  - `asset_entries`: `SCENE.HQR[2]` from topic `6707`, post `177798`
  - `evidence`: `10614` for the explicit `LBA_BKG.HQR[2]` to `scene #2` pairing
- current stance: strong enough to keep for phase 1

## `exterior-area-citadel-tavern-and-shop`

- semantic label: Citadel Island exterior scene with the tavern and the shop
- asset reference: `SCENE.HQR[44]`
- evidence anchors:
  - `asset_entries`: `SCENE.HQR[44]` from topic `6707`, post `177798`
  - `evidence`: `10609` for the explicit `~2` outside-scene classification and named scene description in the same `SCENE.HQR` list
  - classic source: `LoadScene(numscene)` loads `SCENE.HQR[numscene + 1]`, so this raw entry is loader scene `42`
  - classic source: island `0` maps through `IleLst[Island]` to `citadel`, and the exterior loader then opens the paired `CITADEL.ILE` / `CITADEL.OBL` resources
- current stance: this replaces the old misclassified `SCENE.HQR[4]` exterior target. `SCENE.HQR[44]` is the canonical first exterior target because the corpus marks it as `~2` outside-scene data, the live decoder reports `cube_mode == 1`, and the decoded island/cube coordinates are source-backed loader inputs rather than guessed labels

## `actor-player-scene2`

- semantic label: player actor instance in the Twinsen's house scene
- asset reference: hero block in `SCENE.HQR[2]`
- locked facts:
  - actor slot is `NUM_PERSO == 0`
  - the scene record stores the hero start position plus hero track/life blocks before the non-hero object list
- source anchors:
  - `reference/lba2-classic/SOURCES/COMMON.H`
  - `reference/lba2-classic/SOURCES/DISKFUNC.CPP`
  - `reference/lba2-classic/SOURCES/OBJECT.CPP`
- unresolved on purpose:
  - no direct body or animation entry is locked from `SCENE.HQR[2]` yet
  - later body selection flows through runtime defaults and `ChoiceHeroBody`, not a phase 0 scene-level proof

## `dialog-voice-holomap`

- semantic label: first English game voice line, "You just found your Holomap!"
- asset reference: `VOX/EN_GAM.VOX[1]`
- evidence anchors:
  - `evidence`: `11254`
  - supporting duplicate voice-text evidence: `11257`
- current stance: strong enough to keep for the first voice baseline

## `cutscene-ascenseu`

- semantic label: first cutscene entry in the movie list
- asset references: `VIDEO/VIDEO.HQR[1]`, `ASCENSEU.SMK`, and `RESS.HQR[49]`
- evidence anchors:
  - `evidence`: `11659` for the `VIDEO.HQR` ordering and `ASCENSEU.SMK`
  - `asset_entries`: `RESS.HQR[49]` from topic `6707`, post `175880`
- current stance: strong enough to keep for the first cutscene baseline

## `quest-state-house-key-cellar-access`

- semantic label: early Twinsen-house affordance tying hidden-key pickup to cellar access
- state context:
  - location: early Twinsen-house state
  - inventory: starts without the hidden key
  - player affordance: find hidden key, open the keyed cellar door, enter and return from the cellar
  - runtime gate: key pickup and consumption plus house/cellar active-cube changes
- asset references:
  - `SCENE.HQR[2]`
  - `LBA_BKG.HQR[1]` house background
  - `LBA_BKG.HQR[0]` cellar background
- evidence anchors:
  - `docs/lba2_walkthrough.md`: early route says to get the key in the back room and get the golden ball
  - `docs/PHASE5_0013_RUNTIME_PROOF.md`: live proof records `NbLittleKeys 0 -> 1`, key consumption, and house/cellar cube changes
  - `docs/promotion_packets/phase5/phase5_0013_key_door_cellar.md`: the key-door-cellar seam is `live_positive`
- current stance: retrospective Phase 0 quest-state target added after the Phase 5 model correction; strong enough for hidden-key and cellar-access planning, but not a claim that New Game equivalence, Sendell portrait clues, dialogue/flags, or magic ball pickup are already promoted
