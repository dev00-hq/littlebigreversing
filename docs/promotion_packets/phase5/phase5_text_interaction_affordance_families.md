# Phase 5 Text Interaction Affordance Families

## Packet Identity

- `id`: `phase5_text_interaction_affordance_families`
- `status`: `live_positive`
- `evidence_class`: `dialog_text`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: direct-launched named saves `02-voisin.LBA`, `02-dome.LBA`,
  `imperial hotel window.LBA`, and `04-house.LBA`, plus the prior room `36/36`
  Sendell Ball proof lane from `ball of sendell.LBA`
- source state: named saves loaded with active `autosave.lba` hidden when using
  the direct original-runtime launch lane
- triggers:
  - `02-voisin.LBA`: face/reach the neighbor and press `W`
  - `02-dome.LBA`: move close enough to Dino-Fly, face him, press `W`, then use
    `Space`, `Up`/`Down`, and `Enter` on the destination menu
  - `imperial hotel window.LBA`: face beta `3500` and move toward the
    NPC/window until proximity text appears
  - `04-house.LBA`: face the wall painting and hold `W` long enough to open the
    inspection text
  - `ball of sendell.LBA`: drive the Sendell Ball acquisition/event text lane
    through acknowledgement checkpoints
- destination: text renderer state opens, pages, or changes in the expected
  affordance family while surrounding owner state remains family-specific

This packet promotes the narrow runtime classification that multiple
player-facing text interactions share decoded text UI/pagination machinery but
are owned by different gameplay affordance families. It does not promote a
generic NPC dialogue system, generic object inspection, arbitrary service menus,
Dino-Fly travel transitions, or save/load persistence of live dialog UI state.

## Decode Evidence

The pinned text decoder globals from the room-36 proof lane are the common
evidence surface:

- `BufOrder = 0x004CC4A0`
- `BufText = 0x004CC494`
- `PtText = 0x004CC498`
- `SizeText = 0x004CC49C`
- `PtDial = 0x004CCDF0`
- `CurrentDial = 0x004CCF10`

`tools/life_trace/dialog_text_dump.py` reads these globals and decodes the
active text record. `CurrentDial` is evidence for record identity only; it is
not durable modal state. `PtText` anchors the decoded record and `PtDial`
advances through visible chunks/pages.

The old room-36 Sendell proof established the pagination rule that a visible
page turn can be renderer-owned movement inside one decoded record, not a
settled dialog-id transition. The same text cursor model appears in the new
object-inspection and actor/menu probes.

## Original Runtime Live Evidence

Actor conversation:

- `work/live_proofs/phase5_dialogue_voisin_turn_reply_20260501-210353/summary.json`
  proves `02-voisin.LBA` opens Twinsen's `CurrentDial=504` greeting, closes the
  visible box on `Space` while `CurrentDial` can remain stale, then opens the
  neighbor reply after a no-input actor-turn delay. The later long reply uses
  `CurrentDial=83` while `PtDial` advances through the same decoded record.

Actor service menu:

- `work/live_proofs/phase5_dialogue_dome_dinofly_close_target_20260501-213340/summary.json`
  proves Dino-Fly requires close range/facing before `W` opens `CurrentDial=101`
  (`Hi.`), then `CurrentDial=289` (`Where do you want to go, Twinsen?`).
- `work/live_proofs/phase5_dialogue_dome_dinofly_menu_safe_20260501-213937/summary.json`
  proves `Space` opens the destination menu, `Up`/`Down` changes selection, and
  `Enter` confirms the safe first option without travel. During selection,
  `CurrentDial` stays on prompt id `289` while decoded text reflects the
  selected option.

Ambient bark:

- `work/live_proofs/phase5_dialogue_hotel_window_bark_facing_20260501-214702/summary.json`
  proves proximity movement toward the hotel-window NPC triggers large centered
  bark text (`Theeeeee!!!` visually, `Hheeeeee!!!` in the decoded buffer) with
  `CurrentDial=0` and `PtDial=0x00000000`.

Object inspection:

- `work/live_proofs/phase5_dialogue_04_house_painting_inspect_repeat_20260501-220141/summary.json`
  proves pressing/holding `W` while facing the painting opens `CurrentDial=29`
  and the decoded painting record. Repeated `W` advances `PtDial` through chunks
  of the same record with no NPC actor turn or menu.

Scripted acquisition/event text:

- `docs/ROOM36_DIALOG_DECODE.md` and
  `tools/life_trace/capture_sendell_ball.py` preserve the Sendell Ball lane.
  The proof shows one decoded text record paginated by the renderer while
  surrounding script checkpoints capture durable story-state deltas. This is
  event-owned text, not passive object inspection or NPC conversation.

## Runtime Invariant

For these proof seams only, runtime text interaction support must separate the
shared text UI state from the gameplay owner that triggered it.

The canonical contract id is `text_interaction_affordance_families`.

Required owner split:

- actor conversation: action-triggered actor target, speaker turns, reply delay
- actor service menu: actor target plus choice menu selection/confirmation
- ambient bark: proximity/script-triggered text without dialog-record modal
  semantics
- object inspection: deliberate action against a prop/object with paginated text
- scripted event/acquisition text: room/life-script event text plus surrounding
  durable story-state mutation

## Positive Test

- `tools/validate_promotion_packets.py` validates packet identity, manifest
  entry, fixture presence, and runtime contract coverage.
- `tools/fixtures/promotion_packets/phase5_text_interaction_affordance_families_live_positive.json`
  records the live-positive proof families and non-promoted boundaries.
- `tools/life_trace/dialog_text_dump.py` and the preserved proof summaries
  provide the text-global evidence for each family.

## Negative Test

Do not infer a generic dialogue system from this packet. Specifically:

- `CurrentDial != 0` is not proof that a modal dialogue box is visible.
- Text appearing on screen is not proof of actor conversation.
- Dino-Fly menu selection does not promote travel transitions.
- The hotel-window bark does not promote the later `W` talk path.
- The painting proof does not promote all inspected props.
- The Sendell Ball proof does not make transient text UI state durable save
  state.
- Visible page turns do not imply new dialog ids without a new proof.

## Reproduction Command

Representative live probes used direct original-runtime named-save launches
with the active autosave hidden or preserved according to the named-save guard:

```powershell
py -3 tools\life_trace\dialog_text_dump.py --process-name LBA2.EXE
py -3 tools\life_trace\capture_sendell_ball.py --launch-save work\saves\ball of sendell.LBA
```

The newer family probes were run as one-shot automation scripts against
`02-voisin.LBA`, `02-dome.LBA`, `imperial hotel window.LBA`, and `04-house.LBA`
using `WindowInput`, screenshots, and `dialog_text_dump.snapshot_dialog_state`.
Their exact run outputs are preserved under `work/live_proofs/`.

## Failure Mode

If a run loads the wrong save because `autosave.lba` was active, if screenshots
do not show the expected visible text/menu/bark, if decoded text globals do not
match the visible claim, or if the trigger owner is ambiguous, do not use that
run as promotion evidence. If a text path depends on a new actor, prop, menu
destination, or story transition not listed here, treat it as a new proof target
instead of widening this packet by inference.

## Docs And Memory

- `tools/fixtures/promotion_packets/phase5_text_interaction_affordance_families_live_positive.json`
- `docs/ROOM36_DIALOG_DECODE.md`
- `docs/CLASSIC_TEST_ANCHORS.md`
- `docs/codex_memory/lessons.md`
- `work/live_proofs/phase5_dialogue_voisin_turn_reply_20260501-210353/summary.json`
- `work/live_proofs/phase5_dialogue_dome_dinofly_close_target_20260501-213340/summary.json`
- `work/live_proofs/phase5_dialogue_dome_dinofly_menu_safe_20260501-213937/summary.json`
- `work/live_proofs/phase5_dialogue_hotel_window_bark_facing_20260501-214702/summary.json`
- `work/live_proofs/phase5_dialogue_04_house_painting_inspect_repeat_20260501-220141/summary.json`

## Old Hypothesis Handling

This packet replaces the vague "dialogue" framing for the current Phase 5 text
work. The old Sendell Ball `513 -> 514` visible-page model remains stale:
page turns are renderer pagination inside one decoded record unless a new proof
shows a distinct record transition. The packet keeps text rendering separate
from actor ownership, service-menu ownership, ambient bark triggers,
object-inspection triggers, and scripted story-state events.

## Revision History

- 2026-05-02: Initial live-positive packet promoting the narrow text
  interaction affordance-family split from actor conversation, Dino-Fly service
  menu, hotel-window ambient bark, painting inspection, and prior Sendell Ball
  event-text evidence.
