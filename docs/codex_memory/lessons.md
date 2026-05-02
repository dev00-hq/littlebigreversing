# Lessons

Curated durable lessons for future agents. This file is not a task log, issue
queue, or replacement for typed JSONL evidence.

### trap.current-focus-heading-is-schema

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: codex-memory, validation
Related tests: tools/test_codex_memory.py
Related files: tools/codex_memory.py, docs/codex_memory/current_focus.md

`docs/codex_memory/current_focus.md` section headings are part of the validated
memory contract. Do not rename required headings such as `## Blocked Items`
unless `tools/codex_memory.py` and its tests change in the same diff.

### decision.task-briefing-is-derived

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: codex-memory, generated, canonical
Related tests: tools/test_codex_memory.py
Related files: tools/codex_memory.py, docs/codex_memory/README.md

`docs/codex_memory/generated/task_briefing.md` is a reproducible task lens, not
canonical truth. The canonical startup path remains `project_brief.md`,
`current_focus.md`, selected subsystem packs, and typed history through
`tools/codex_memory.py context`. Use explicit `--path`, `--subsystem`, `--tag`,
or `--lesson` briefing inputs when the task scope is known, because task prose
alone is only a retrieval hint.

### trap.lessons-are-not-logs

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: codex-memory, lessons, hard-cut
Related tests: tools/test_codex_memory.py
Related files: docs/codex_memory/README.md, ISSUES.md

`lessons.md` is curated operational truth. Do not append to it just because work
finished; add a lesson only when it states reusable future behavior, a durable
trap, a decision, or an invariant that remains useful after the immediate issue
is closed.

### decision.phase5-uses-quest-state-not-room-graph

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: phase5, runtime, promotion-packets, quest-state
Related tests: tools/validate_promotion_packets.py
Related files: docs/promotion_packets/README.md, docs/codex_memory/subsystems/architecture.md, ISSUES.md

Phase 5 candidate selection must start from a normal player affordance in a
known quest/world state, not from a decoded room-transition edge. LBA2 is a
story-gated hub adventure: inventory, dialogue, quest flags, actor state,
collision, current cube, and script conditions decide whether a decoded edge is
gameplay-valid. Decoded room pairs and forced teleports are useful evidence
surfaces, but they do not prove a playable route without runtime-owned state
signals from the corresponding player path.

### fact.original-runtime-throw-input-is-hold-release

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: original-runtime, gameplay-automation, magic-ball, input
Related tests: tools/life_trace/phase5_magic_ball_drive_probe.py
Related files: reference/lba2-classic/SOURCES/OBJECT.CPP, reference/lba2-classic/SOURCES/CONFIG/INPUT.CPP, tools/life_trace/phase5_magic_ball_drive_probe.py

Magic Ball automation must drive weapon input as a hold-then-release action,
not a tap. Source `OBJECT.CPP` keeps `I_THROW` active while aiming and switches
`MAGIC_BALL_LANCEE` to `MAGIC_BALL_LACHEE` only after release; default source
input is `ALT`, while this runtime profile maps weapon use to `.`. On the
`throw-ball.LBA` proof save at pose `(5071,1024,1820,beta=3709)`, a `.` hold of
`0.61s` failed, `0.62s` succeeded for Aggressive, and `0.63s` succeeded for
Normal, Sporty, and Discreet. Future automated gameplay probes should hold the
weapon key for at least `0.75s` before release unless a task is specifically
measuring the threshold.

### trap.original-runtime-autosave-overrides-named-save

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: original-runtime, gameplay-automation, autosave, named-save
Related tests: tools/life_trace/phase5_magic_ball_global_scan.py, tools/life_trace/phase5_magic_ball_tralu_sequence.py
Related files: tools/life_trace/phase5_magic_ball_global_scan.py, tools/life_trace/phase5_magic_ball_tralu_sequence.py
Evidence refs: work/live_proofs/phase5_magic_ball_global_scan_tralu_attack_select_run1_20260429/summary.json

Original-runtime named-save probes must hide or remove active `autosave.lba`
before launch and preserve any generated autosave afterward; otherwise the game
can silently load the wrong state. Treat a clean named-save load as unproved
unless the save directory has no active `autosave.lba` at launch and no generated
`autosave.lba` is left active after the probe exits.

### fact.tralu-magic-ball-damage-probe-ready-sequence

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: original-runtime, gameplay-automation, magic-ball, tralu
Related tests: tools/life_trace/phase5_magic_ball_global_scan.py, tools/life_trace/phase5_magic_ball_tralu_sequence.py
Related files: work/live_proofs/phase5_magic_ball_tralu_sequence_after_hit_ready1_delay07_run1_20260429/summary.json, work/live_proofs/phase5_magic_ball_tralu_sequence_after_hit_ready1_delay07_run2_20260429/summary.json
Evidence refs: work/live_proofs/phase5_magic_ball_global_scan_tralu_attack_f5_select_ready1_run1_20260429/summary.json

For `tralu-attack.LBA`, immediate `.` and `F5 + 1 + .` without a post-load
settle failed to launch Magic Ball damage. A `1.0s` post-load settle followed by
`F5`, `1`, and a `0.75s` `.` hold repeatedly produced two Tralu Magic Ball hits:
object `3` dropped `72 -> 63`, then `63 -> 54`, before Twinsen object `0` was
hit later.

### trap.magic-ball-switch-object-noise-is-not-hit-proof

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: original-runtime, gameplay-automation, magic-ball, switches
Related tests: tools/life_trace/phase5_magic_ball_switch_probe.py
Related files: work/live_proofs/phase5_magic_ball_switch_probe_three_20260429/summary.json, work/live_proofs/phase5_magic_ball_switch_probe_obj4_corrected_20260429/summary.json

For Magic Ball switch probes, do not treat any changed object field as proof
that the ball hit that object. The Emerald Moon `moon-switches-room.LBA` run
showed follow-on flag/script noise across neighboring switch objects after a
throw, and the operator correctly caught a false third-switch claim. Use a
discriminating signal such as the intended target object's `label_track`
transition plus visual alignment/screenshot review before calling a switch hit
proved.

### fact.emerald-moon-switches-room-lever-objects

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: original-runtime, gameplay-automation, magic-ball, switches, scene31
Related tests: tools/life_trace/phase5_magic_ball_switch_probe.py
Related files: work/live_proofs/phase5_magic_ball_switch_probe_middle_wide_20260429/summary.json, work/live_proofs/phase5_magic_ball_switch_probe_obj4_corrected_20260429/summary.json

In `moon-switches-room.LBA` (`num_cube=31`, raw scene entry `33`, Switches
Building), the three front Magic Ball switch objects are runtime objects `2`,
`3`, and `4` at `(2304,1536,9984)`, `(2304,1536,8448)`, and `(2304,1536,6912)`.
The save starts Twinsen near `(4866,512,8324)`: current beta `2995` targets the
middle switch object `3`, while the lower/right switch object `4` needs a
corrected beta around `2760`; beta `2542` was too far off despite producing
misleading object noise.

`phase5_magic_ball_switch_activation_emerald_moon` promotes only object `3` and
corrected object `4` in this save. It is not proof for object `2`, Radar room
levers, or generic switch/lever behavior.

### fact.magic-ball-lever-activation-has-multiple-script-paths

Status: active
Confidence: high
Last verified: 2026-04-30
Tags: original-runtime, gameplay-automation, magic-ball, levers, cdb
Related tests: tools/life_trace/phase5_magic_ball_switch_probe.py, tools/life_trace/phase5_magic_ball_cdb_agent_watch_probe.py, tools/validate_promotion_packets.py
Related files: docs/promotion_packets/phase5/phase5_magic_ball_lever_activation_multi_family.md, work/live_proofs/phase5_magic_ball_radar_lever_cdb_watch_20260430_r7/summary.json, work/live_proofs/phase5_magic_ball_wizard_tent_lever_cdb_label_run1_20260430/summary.json, work/live_proofs/phase5_magic_ball_warehouse_blocked_lever_run1_20260430/summary.json

`phase5_magic_ball_lever_activation_multi_family` promotes Magic Ball lever
activation only as a narrow impact-to-object-script contract. Radar room and
Wizard tent prove different live write paths: Radar slot `19` uses writer
`0x004386ec` for the `gen_anim/next_gen_anim 242 -> 244` animation path, and
source/decompilation maps that writer to generic `InitAnim`. Wizard tent slot
`2` uses writer `0x0042468c` for the `label_track 6 -> 8 -> 9` script-state
path, and source/decompilation maps that writer to `DoTrack/TM_LABEL`. The
`01-warehouse.LBA` blocked-lever run proves that Magic Ball contact alone is not
sufficient for activation; script/progression eligibility still matters. Do not
implement broad lever support by matching one observed field delta or by writing
lever fields directly from projectile collision code.

### trap.dialog-currentdial-is-not-modal-state

Status: active
Confidence: high
Last verified: 2026-05-01
Tags: original-runtime, gameplay-automation, dialogue, actors
Related tests: tools/life_trace/dialog_text_dump.py
Related files: work/live_proofs/phase5_dialogue_voisin_turn_reply_20260501-210353/summary.json

For original-runtime dialogue probes, do not treat `CurrentDial != 0` as proof
that a dialogue box is currently visible. In `02-voisin.LBA`, Twinsen's `W`
interaction opened `CurrentDial=504` (`Hello neighbor.`); pressing `Space`
closed the visible box while `CurrentDial` still retained `504`. After about a
1.3s no-input actor-turn window, the NPC reply opened automatically and then
settled to `CurrentDial=88` (`Hello Twinsen!`). The later long response used one
`CurrentDial=83` record while `PtDial` advanced through visible text chunks.
Model dialogue probes as actor interaction/conversation scripts with visible
UI state, speaker turns, delays, and `PtDial` cursor progression; use
screenshots plus text-buffer state, not `CurrentDial` alone.

### fact.dinofly-dialogue-is-service-menu-affordance

Status: active
Confidence: high
Last verified: 2026-05-01
Tags: original-runtime, gameplay-automation, dialogue, actors, menu, dinofly
Related tests: tools/life_trace/dialog_text_dump.py
Related files: work/live_proofs/phase5_dialogue_dome_dinofly_close_target_20260501-213340/summary.json, work/live_proofs/phase5_dialogue_dome_dinofly_menu_safe_20260501-213937/summary.json

Do not classify Dino-Fly interaction as ordinary NPC dialogue. In
`02-dome.LBA`, `W` only triggered after Twinsen was close enough and facing
Dino-Fly; the first line was `CurrentDial=101` (`Hi.`), followed by
`CurrentDial=289` (`Where do you want to go, Twinsen?`). Pressing `Space` from
that prompt opened a choice menu with destination options. `Up`/`Down` changed
the highlighted choice, and `Enter` confirmed the first safe option
(`I'm staying here.`), closing the menu without travel. During menu navigation,
`CurrentDial` stayed on prompt id `289` while `PtText`/decoded text reflected the
selected option. Model this as an actor service interaction with range/facing,
dialogue prompt, menu state, selection, and confirmation dispatch; travel
transitions remain a separate unproved path.

### trap.ambient-barks-use-text-renderer-without-dialog-records

Status: active
Confidence: high
Last verified: 2026-05-01
Tags: original-runtime, gameplay-automation, dialogue, ambient-bark, text-ui
Related tests: tools/life_trace/dialog_text_dump.py
Related files: work/live_proofs/phase5_dialogue_hotel_window_bark_facing_20260501-214702/summary.json

Ambient bark text can use the text renderer without behaving like deliberate
dialogue. In `imperial hotel window.LBA`, after forcing Twinsen to face beta
`3500` and moving toward the NPC/window, proximity triggered the large centered
bark (`Theeeeee!!!` visually, `Hheeeeee!!!` in decoded text). `CurrentDial`
remained `0` and `PtDial` remained null while `PtText` changed to the bark text
buffer; the bark auto-cleared visually after a short wait. Do not use text
appearance alone as evidence of an actor conversation or modal dialogue. For
proximity barks, prove trigger movement/range, visual text, and buffer change
separately from `W`-driven dialogue.

### fact.painting-inspection-is-object-text-affordance

Status: active
Confidence: high
Last verified: 2026-05-01
Tags: original-runtime, gameplay-automation, dialogue, object-inspection, text-ui
Related tests: tools/life_trace/dialog_text_dump.py
Related files: work/live_proofs/phase5_dialogue_04_house_painting_inspect_repeat_20260501-220141/summary.json

Do not collapse object inspection text into NPC dialogue. In `04-house.LBA`,
Twinsen starts facing the wall painting; holding `W` for about 180ms opened
`CurrentDial=29` with the decoded record `"To my future descendants: I have lent
to Miss Bloop's private museum, the Medallion and the Ancestral Tunic which
rightfully belong to you. Signed: Twinsen."` The screenshot shows Twinsen
looking at the painting with the text box open and no NPC actor involved.
Repeated `W` presses advanced `PtDial` through chunks of the same record
instead of starting an actor turn or service menu. Model this as deliberate
object/prop inspection with range/facing and text pagination; it shares
`TextUiState` with dialogue, but not actor conversation semantics.

### policy.teleport-requires-visual-checkpoint

Status: active
Confidence: high
Last verified: 2026-05-02
Tags: original-runtime, gameplay-automation, teleport, visual-proof, codex-exec
Related tests: tools/test_game_drive_checkpoint.py
Related files: tools/game_drive_checkpoint.py, tools/fixtures/game_drive_checkpoints/pose_ready_magic_ball_middle_switch.json

Every original-runtime teleport or direct pose-set operation must be followed
by a screenshot checkpoint and `codex exec` visual classification before any
gameplay action is allowed. Runtime memory alone can say the scene, pose, and
object fields look correct while the screenshot shows Twinsen facing the wrong
way, standing in the wrong room, falling, respawning, or blocked by UI. The
visual classifier response must be structured JSON and include a non-empty
`summary` field that justifies the boolean observations. Teleport/direct-pose
checkpoint contracts must also declare negative visual controls so screenshot
classification is not used only as a confirmation-biased rubber stamp.

### trap.live-directdraw-window-capture-can-be-unavailable

Status: active
Confidence: high
Last verified: 2026-05-02
Tags: original-runtime, gameplay-automation, visual-proof, save-preview, directdraw
Related tests: tools/test_game_drive_runner.py, tools/test_game_drive_checkpoint.py
Related files: tools/game_drive_runner.py, tools/game_drive_checkpoint.py

Unattended original-runtime runs can load the correct save and expose valid
runtime globals while live window screenshot capture returns a black DirectDraw
surface or cannot access the desktop. Do not silently treat that as visual
proof. Game-drive checkpoints must declare their visual source explicitly. A
prepared named-save checkpoint may use `save_embedded_preview` paired with live
runtime globals, but teleport/direct-pose checkpoints must use
`live_window_capture` and remain blocked if live screenshots are unavailable.

### trap.movement-rungs-need-live-window-checkpoints

Status: active
Confidence: high
Last verified: 2026-05-02
Tags: original-runtime, gameplay-automation, movement, visual-proof, input-focus
Related tests: tools/test_game_drive_capability_ladder.py
Related files: tools/game_drive_capability_ladder.py, tools/game_drive_runner.py

Save-embedded previews are sufficient for proving a named save's stored
preview and expected runtime globals, but they are not sufficient for movement
or rotation action rungs. In live ladder runs, plain arrow-key actions could
load the correct runtime pose yet produce zero movement until the rung used a
live-window checkpoint/direct-pose setup immediately before the action. Movement
capability claims should therefore use live-window visual checkpoints and exact
runtime postconditions such as beta or position deltas, not save-preview-only
visual gates.
