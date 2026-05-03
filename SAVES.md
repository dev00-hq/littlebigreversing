# Savegame Recovery Index

This file records named saves that have been used as probe inputs in this repo,
especially the custom prepared saves that may need to be recreated after a save
folder restore.

Recovery status as of 2026-05-03: the operator recreated the missing prepared
saves as best as possible. They are marked operationally recovered for moving
on, but not revalidated; do not treat any recreated save as fresh evidence until
a later explicit proof run passes its visual/runtime gates.

Critical rule: original-runtime named-save probes must hide active
`SAVE\autosave.lba` before launch and preserve any generated autosave afterward.
If autosave is active, the game can silently load the wrong state.

## Magic Ball Saves

### `new-game-cellar.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: repeatable Magic Ball pickup proof.
- Scene/context: early cellar state, scene `2`, background `0`, active cube `1`.
- Required setup: Twinsen starts before collecting the Magic Ball, with
  `FLAG_BALLE_MAGIQUE = 0`, `magic_level = 0`, `magic_point = 0`.
- Expected probe: walk to the cellar Magic Ball pickup and acknowledge the
  pickup dialog; `FLAG_BALLE_MAGIQUE` changes `0 -> 1`.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_pickup.md`,
  `work/live_proofs/phase5_magic_ball_launch_20260429_r2/summary.json`.

### `throw-ball.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: Magic Ball launch threshold and behavior-mode trajectory proof.
- Scene/context: scene `2`, background `0`, active cube `1` cellar.
- Required setup: Twinsen has Magic Ball, pose near
  `(5071,1024,1820,beta=3709)`, clear line to throw, Magic Ball selectable.
- Expected probe: select Magic Ball with `1`, choose behavior with `F5`-`F8`,
  hold `.` then release. Conservative rule is `0.75s`; threshold was about
  `0.62s`-`0.63s` depending on behavior.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_throw_projectile_launch.md`.

### `throw-ball-1.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: level-1 Magic Ball lifecycle/bounce comparison in an open direction.
- Required setup: same general throw lane as `throw-ball.LBA`, but with
  `magic_level = 1` and enough magic points for a bouncing ball.
- Expected probe: throw with `.` held `0.75s`; level-1 ball can bounce instead
  of immediately returning like level 0.

### `throw-ball-fire.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: fire/highest Magic Ball lifecycle/bounce comparison.
- Required setup: different scene was acceptable, but Twinsen must be positioned
  so a plain throw launches cleanly and the fire ball can bounce.
- Expected probe: throw with `.` held `0.75s`; discard long active outliers
  unless repeated.

### `throw-ball-fire-1-wall.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: repeated level-1 wall-bounce proof.
- Alias/context: this was the save observed on disk during proof runs when the
  requested name was `throw-ball-1-wall.LBA`.
- Required setup: Magic Ball level `1`, Normal mode, Magic Ball selected or
  selectable, Twinsen aimed at a wall so the first throw collides.
- Expected probe: run twice; `.` held `0.75s`; one magic point consumed; four
  bounce signatures then return/clear.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_bounce_return_wall_repeat.md`.

### `throw-ball-fire-wall.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: repeated fire-ball wall-bounce proof.
- Required setup: fire/highest Magic Ball, Normal mode, aimed at a wall.
- Expected probe: run twice; `.` held `0.75s`; one magic point consumed; four
  bounce signatures then clear.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_bounce_return_wall_repeat.md`.

### `tralu-attack.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: narrow Tralu enemy damage proof.
- Scene/context: Tralu dungeon, progression-locked to magic level `1`.
- Required setup: spawn in front of Tralu in Normal mode; first immediate throw
  must hit Tralu. Save should support two hits before Twinsen is hit.
- Expected probe: hide autosave, launch, wait about `1.0s` for readiness, press
  `F5`, press `1`, hold `.` for `0.75s`, then trigger a second throw after the
  first Tralu hit with about `0.7s` delay. Tralu object `3` should lose `9`
  life per hit (`72 -> 63 -> 54`), then Twinsen is hit later.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_enemy_damage_tralu_level1.md`.

## Magic Ball Switch And Lever Saves

### `moon-switches-room.LBA`

- Status: custom prepared save; currently missing/reverted in recovered set.
- Used for: Emerald Moon three-switch Magic Ball activation and game-drive
  harness `magic_ball_throw` capability.
- Scene/context: scene `31`, raw scene entry `33`, Switches Building.
- Required setup: Twinsen has Magic Ball, Normal mode, magic level high enough
  for the promoted run, starts near `(4866,512,8324)`.
- Target details: three front switch objects are runtime objects `2`, `3`, `4`
  at `(2304,1536,9984)`, `(2304,1536,8448)`, `(2304,1536,6912)`.
- Expected probe: beta `2995` cleanly targets middle object `3`; beta around
  `2760` targets object `4`; earlier beta `2542` was a false third-switch
  claim. Use label-track transition plus screenshot, not generic object churn.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_switch_activation_emerald_moon.md`,
  `docs/codex_memory/lessons.md`.
- Reprepare hint: `work\saves\emerald moon building1.LBA` is a recovered same
  scene save, but its pose is not the prepared proof pose.

### `lever-magic-ball.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: primary Radar room Magic Ball lever activation.
- Scene/context: Emerald Moon Radar room, scene `23`.
- Required setup: Twinsen in front of lever-like object `19`, pose roughly
  `(27617,512,12245,beta=2800)`, Magic Ball owned/selectable, Normal mode.
- Expected probe: throw Magic Ball; object `19` changes
  `gen_anim/next_gen_anim 242 -> 244`; linked object/script state changes and
  a door opens.
- CDB proof: watch `ListObjet[19].GenAnim`; writer `0x004386ec` maps to generic
  `InitAnim`, not Magic-Ball-specific field writing.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_lever_activation_multi_family.md`.

### `lever-magicball-2.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: second Radar room lever toggle support.
- Required setup: another lever in the same Radar room, ready for two throws.
- Expected probe: throw twice to observe close then open behavior on linked
  door/platform state.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_lever_activation_multi_family.md`.

### `tralu-lever-1.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: supporting Magic Ball lever activation in Tralu dungeon.
- Required setup: Tralu cave/dungeon lever in front of Twinsen; Magic Ball
  owned/selectable.
- Expected probe: throw Magic Ball; object `2` reaches `label_track=100` and
  linked object `7` animates `0 -> 123 -> 0`.
- Caveat: supporting evidence only because NPC/enemy motion adds noise.

### `lever-wizard-tent.LBA`

- Status: custom prepared save; may be missing after restore.
- Used for: Wizard tent lever family proof and CDB writer proof.
- Required setup: Wizard tent lever in front of Twinsen, only one NPC
  (the wizard), Magic Ball owned/selectable, Normal mode.
- Expected probe: throw Magic Ball; object `2` advances
  `label_track 6 -> 8 -> 9`; linked object `3` moves to `z=5632`.
- CDB proof: watch `ListObjet[2].label_track`; writer `0x0042468c` maps to
  `DoTrack/TM_LABEL`.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_lever_activation_multi_family.md`.

### `01-warehouse.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: negative control for blocked/progression-gated lever.
- Required setup: load and throw Magic Ball at the blocked lever.
- Expected probe: Magic Ball launches, hits, returns, and emits a distinct
  sound, but lever does not activate. Object `25` only flag-toggles and stays
  `label_track=-1`.
- Evidence: `docs/promotion_packets/phase5/phase5_magic_ball_lever_activation_multi_family.md`.

## Dialogue And Text-Affordance Saves

### `02-voisin.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: actor conversation and game-drive dialogue capability.
- Required setup: Twinsen positioned to talk to neighbor; press `W`.
- Expected probe: Twinsen says "Hello neighbor."; press `Space` to close;
  after about `1.3s` no-input actor-turn delay, NPC reply opens. `CurrentDial`
  can remain stale after visible close; use screenshots plus text-buffer state.
- Evidence: `docs/promotion_packets/phase5/phase5_text_interaction_affordance_families.md`.

### `02-dome.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: Dino-Fly actor service menu proof.
- Required setup: move Twinsen a little closer to Dino-Fly, face him, press `W`.
- Expected probe: first dialog says "Hi.", then "Where do you want to go,
  Twinsen?". Press `Space` to open destination menu; `Up`/`Down` changes
  selection; `Enter` confirms. First option is safe: "I'm staying here".
- Evidence: `docs/promotion_packets/phase5/phase5_text_interaction_affordance_families.md`.

### `imperial hotel window.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: ambient bark/proximity text proof.
- Required setup: face beta around `3500` toward the NPC/window and move toward
  her until the bark triggers.
- Expected probe: large centered bark text appears visually as "Theeeeee!!!"
  while decoded buffer captured `Hheeeeee!!!`; `CurrentDial=0` and
  `PtDial=0`, so this is not normal modal dialogue.
- Evidence: `docs/promotion_packets/phase5/phase5_text_interaction_affordance_families.md`.

### `04-house.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: object inspection text proof.
- Required setup: Twinsen inside house facing wall painting; press/hold `W`.
- Expected probe: opens painting inspection text with `CurrentDial=29`; repeated
  `W` advances `PtDial` through chunks of the same record. No NPC is involved.
- Evidence: `docs/promotion_packets/phase5/phase5_text_interaction_affordance_families.md`.

### `01-tralu-cave.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: dialogue save listed by operator; press `W`.
- Context: Tralu cave text/dialogue probe candidate.

### `01-house.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: dialogue save listed by operator; press `W`.
- Context: Twinsen house early interaction candidate.

### `07-landed-near-palace.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: dialogue save listed by operator; press `W`.
- Context: palace-adjacent text/dialogue candidate.

### `ball of sendell.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: older Sendell Ball event-text/pagination proof lane.
- Required setup: drive the Sendell Ball acquisition/event text lane through
  acknowledgement checkpoints.
- Expected probe: visible page turns are renderer pagination inside one decoded
  record unless proven otherwise; do not model as durable dialog-id changes.
- Evidence: `docs/ROOM36_DIALOG_DECODE.md`,
  `docs/promotion_packets/phase5/phase5_text_interaction_affordance_families.md`.

## Zone, Door, And Key Saves

### `0013-weapon.LBA`

- Status: recovered stock save exists in `work\saves`.
- Used for: cellar-source `3/3` zone candidate negative probes.
- Important caveat: do not call this a Tralu save. It is a cellar-side source
  save with `num_cube=1`, raw scene entry `3`.
- Expected probes: decoded zone `1 -> cube 19` and zone `8 -> cube 20` remain
  live-negative until a runtime-owned transition signal appears. Direct-center
  zone membership alone is not enough.
- Evidence: `docs/promotion_packets/phase5/phase5_003_003_zone1_cellar_to_cube19.md`,
  `docs/promotion_packets/phase5/phase5_003_003_zone8_cellar_to_cube20.md`.

### `scene2-bg1-key-midpoint-facing-key.LBA`

- Status: generated custom save; may be missing after restore.
- Used for: original-runtime `0013` save-creation validation.
- Required setup: scene `2`, background `1`, hero pose plus matching
  `SceneStartX/Y/Z` and `StartXCube/Y/Z`.
- Caveat: teleporting hero plus `CurrentSaveGame()` was not enough; reload
  memory snapshot must prove new coordinates.

## Harness Capability Saves

### `moon-switches-room.LBA`

- Status: missing/reverted custom prepared save.
- Used for: `game_drive_capability_ladder.py` cases:
  `load_visual_gate`, `rotation_left`, `translation_forward`,
  `magic_ball_throw`, `behavior_cycle`, `behavior_direct_f5_f8`,
  `behavior_speed_normal`, `behavior_speed_sporty`,
  `behavior_speed_aggressive`, `behavior_speed_discreet`,
  `direct_pose_visual_gate`.
- Required setup: same as the Magic Ball switch room entry above. The harness
  currently expects this save unless checkpoints are changed to a recovered
  same-scene substitute plus direct-pose visual gating.
  Behavior-speed probes direct-pose to `(4866,512,8324,beta=2995)`, press the
  requested `F5`-`F8` mode key, then hold Up for `0.50s` and record live
  `hero_x/hero_z/hero_beta` deltas plus before/after screenshots.
  The second-pose speed probes direct-pose to `(4866,512,8324,beta=2760)`,
  press the requested mode key, then hold Up for `1.00s`.
  The acceleration probes reuse that second pose and hold Up for `2.00s` while
  retaining the runner's roughly `50ms` runtime position samples.

### `otringal-open.LBA`

- Status: operator-prepared custom save; mirrored to `work\saves` on
  2026-05-03 after being found in the runtime `SAVE\` directory.
- Used for: cleaner open-area behavior movement/acceleration probes:
  `behavior_accel_otringal_normal`, `behavior_accel_otringal_sporty`,
  `behavior_accel_otringal_aggressive`, and
  `behavior_accel_otringal_discreet`. The same cases were rerun for
  animation-correlation evidence after `tools/game_drive_runner.py` started
  sampling candidate hero object animation fields.
- Required setup: Twinsen is already in an open outdoor Otringal gameplay area,
  facing clear forward walking space. The checkpoint intentionally uses the
  save's existing pose rather than a direct-pose override.
- Evidence: `docs/evidence_archive/game_drive/behavior-mode-accel-otringal-20260503-behavior_accel_otringal_normal/summary.json`,
  `docs/evidence_archive/game_drive/behavior-mode-accel-otringal-20260503-behavior_accel_otringal_sporty/summary.json`,
  `docs/evidence_archive/game_drive/behavior-mode-accel-otringal-20260503-behavior_accel_otringal_aggressive/summary.json`,
  `docs/evidence_archive/game_drive/behavior-mode-accel-otringal-20260503-behavior_accel_otringal_discreet/summary.json`.
- Notes: the live visual gate must describe an open Otringal gameplay area
  before accepting the movement time series. On the 2026-05-03 run, all four
  modes moved mostly along `hero_z`, making this a cleaner source than the
  Emerald Moon room for movement-speed ratios and startup latency. The
  animation-correlation rerun found the candidate hero object position fields
  tracked movement, while sampled `gen_body/gen_anim/next_gen_anim` stayed
  constant; treat that as a weak negative against those fields owning movement
  phase, not as proof that movement is not animation-coupled.

### `02-voisin.LBA`

- Status: recovered stock save exists.
- Used for: `dialogue_open` capability.
- Required setup: same as dialogue entry above.

## General Reprepare Checklist

- Put the prepared `.LBA` under the runtime `SAVE\` directory and optionally
  mirror it under `work\saves` if it should survive runtime folder churn.
- Before any probe, hide active `SAVE\autosave.lba`; after the run, preserve
  generated autosave under a timestamped name instead of leaving it active.
- For Magic Ball probes, use `1` to select Magic Ball when needed and hold `.`
  for `0.75s` before release.
- For behavior mode, prefer `F5` Normal, `F6` Sporty, `F7` Aggressive,
  `F8` Discreet.
- For prepared-position saves, record pose fields in the note:
  `scene/background/active_cube`, `x/y/z/beta`, magic level/points, weapon,
  behavior mode, and intended target object.
- For every teleport/direct-pose replacement, require a live-window screenshot
  visual gate before accepting runtime memory as proof.
