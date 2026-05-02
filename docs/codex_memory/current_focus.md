# Current Focus

## Current Priorities

- Phase 5 remains active; the `0013` key-door-cellar slice is closed.
- Keep memory v2, guarded loads, promotion packets, and additive validation canonical.
- Preserve life/room/debugger boundaries.

## Active Streams

- Guarded loads: `19/19`, `2/2`, `11/10`, `187/187`; `44/2` rejects.
- `0013` is closed: packet covers save load, key pickup, door consume, cellar entry, and Down-return.
- Promoted contracts: Magic Ball pickup/throw/bounce/Tralu damage/Emerald Moon switches/multi-family levers; text interaction affordance-family owner split.
- Magic Ball switch activation is promoted only for Emerald Moon object `3` and corrected object `4`; object `2` remains unpromoted.
- Magic Ball lever activation is promoted only as `magic_ball_lever_activation_multi_family`; Warehouse is the negative control.
- Broader Magic-ball damage, generic switches/levers, remote pickup, enemy vulnerability, and collision geometry remain unpromoted.
- Runtime/gameplay seam widening requires `docs/promotion_packets/` and promotion validation.
- `inspect-room-transitions 2 1/2 0 --json` is runtime-aware for `0013`; read runtime fields over decoded rows.
- Original-runtime launch uses mixed-mode CD from Alcohol `E:`; WinMM proxy is opt-in only.
- Named saves use globals + pose + `SaveGame(TRUE)`; loads use `LBA2.EXE SAVE\<name>.LBA` with autosave guard.

## Blocked Items

- `2/2` is not solved interior handoff/locomotion semantics.
- `187/187` gameplay/transition beyond startup seed is unproved.
- `3/3` zones `1` and `8` remain live-negative for gameplay.
- `inside dark monk1.LBA` proves only cube `185` save with raw scene entry `187`.
- Room `36/36` page 2 is renderer pagination, not save/load behavior.
- Generic dialogue branching, Dino-Fly travel, hotel-window `W` talk, all object inspections, and dialog UI save persistence remain unpromoted.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails; fragment-zone CLI reports aligned-origin candidates.

## Next Actions

- For `0013`, maintain only: assert proof doc, fixture, promotion packet, and runtime-aware `inspect-room-transitions`.
- Before reopening `187/187`, require fresh mixed-mode CD proof with life-loss watcher enabled and target-zone membership or `NewCube/NewPos`.
- Keep packets current when widening Phase 5; do not broaden Tralu damage or Emerald Moon switches beyond their scoped packets.
- Before broad switch/lever implementation, use writer check: `0x004386ec`=`InitAnim`, `0x0042468c`=`DoTrack/TM_LABEL`; do not encode raw deltas.
- Decoded candidates can stay visible in tooling, but runtime commits require `live_positive` or `approved_exception`.
- Choose the next Phase 5 slice from a normal player affordance plus quest/world state, then prove the needed room, transition, dialog, inventory, or actor seam.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
