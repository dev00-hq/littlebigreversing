# Golden Targets

These are the locked phase 0 targets. They may change only through an explicit replan decision with replacement evidence.

## `interior-room-twinsens-house`

- semantic label: Twinsen's house interior room
- asset references: `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`
- evidence anchors:
  - `asset_entries`: `SCENE.HQR[2]` from topic `6707`, post `177798`
  - `evidence`: `10614` for the explicit `LBA_BKG.HQR[2]` to `scene #2` pairing
- current stance: strong enough to keep for phase 1

## `exterior-area-citadel-cliffs`

- semantic label: Citadel Island cliffs, Raph and Tralu scene
- asset reference: `SCENE.HQR[4]`
- evidence anchors:
  - `asset_entries`: `SCENE.HQR[4]` from topic `6707`, post `177798`
  - `evidence`: `10609` for the named scene description
- current stance: keep the target, but do not treat it as the canonical basis for exterior-camera or other exterior-specific semantics until the scene-number vs HQR-entry mapping is reconciled

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
